import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import 'package:servidor_brilliant/dominio/catalogo_esquemas_mapa.dart';
import 'package:servidor_brilliant/dominio/estado_sala.dart';
import 'package:servidor_brilliant/dominio/estados_sala.dart';
import 'package:servidor_brilliant/dominio/mensajes_protocolo.dart';
import 'package:servidor_brilliant/servidor/gestor_salas.dart';
import 'package:servidor_brilliant/servidor/servidor_websocket_brilliant.dart';

/// Cliente WebSocket ligero exclusivo para pruebas de integración del servidor.
class _ClientePruebaWs {
  final WebSocket socket;
  final StreamController<EventoServidor> _eventos =
      StreamController<EventoServidor>.broadcast();
  CredencialSesionSala? credencial;
  EstadoSalaMultijugador? ultimoEstado;
  int _seq = 0;

  _ClientePruebaWs._(this.socket) {
    socket.listen((raw) {
      if (raw is! String) return;
      final ev = EventoServidor.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (ev.credencial != null) credencial = ev.credencial;
      if (ev.estadoSala != null) ultimoEstado = ev.estadoSala;
      if (!_eventos.isClosed) _eventos.add(ev);
    });
  }

  static Future<_ClientePruebaWs> conectar(String url) async {
    final ws = await WebSocket.connect(url);
    return _ClientePruebaWs._(ws);
  }

  Stream<EventoServidor> get eventos => _eventos.stream;

  Future<EventoServidor> enviarConRespuesta(
    TipoComandoCliente tipo, [
    Map<String, dynamic> datos = const {},
  ]) async {
    final id = 'req_${++_seq}';
    final futuro = eventos
        .firstWhere((e) => e.solicitudId == id)
        .timeout(const Duration(seconds: 3));
    socket.add(
      jsonEncode(
        ComandoCliente(tipo: tipo, solicitudId: id, datos: datos).toJson(),
      ),
    );
    final ev = await futuro;
    if (ev.tipo == TipoEventoServidor.errorOperacion && ev.fallo != null) {
      throw ev.fallo!;
    }
    return ev;
  }

  void enviarComando(
    TipoComandoCliente tipo, [
    Map<String, dynamic> datos = const {},
  ]) {
    socket.add(
      jsonEncode(ComandoCliente(tipo: tipo, datos: datos).toJson()),
    );
  }

  Future<EstadoSalaMultijugador> esperarSala(
    bool Function(EstadoSalaMultijugador) condicion, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (ultimoEstado != null && condicion(ultimoEstado!)) {
      return ultimoEstado!;
    }
    final ev = await eventos
        .firstWhere((e) => e.estadoSala != null && condicion(e.estadoSala!))
        .timeout(timeout);
    return ev.estadoSala!;
  }

  Future<void> cerrar() async {
    try {
      await socket.close();
    } catch (_) {}
    if (!_eventos.isClosed) await _eventos.close();
  }
}

Map<String, int> _estrellasSerializadas(String nivelId) {
  final esquema = CatalogoEsquemasMapa.porId(nivelId);
  final mapa = {
    for (int i = 0; i < esquema.casillasIniciales.length; i++)
      esquema.casillasIniciales[i]: i + 1,
  };
  return ComandoCliente.serializarMapaPosiciones(mapa);
}

void main() {
  group('ServidorWebsocketBrilliant - Integración en Tiempo Real', () {
    late ServidorWebsocketBrilliant servidor;
    late int puerto;
    late String urlWs;
    final clientes = <_ClientePruebaWs>[];

    Future<_ClientePruebaWs> nuevoCliente() async {
      final c = await _ClientePruebaWs.conectar(urlWs);
      clientes.add(c);
      return c;
    }

    setUp(() async {
      servidor = ServidorWebsocketBrilliant(
        tiempos: const ConfiguracionTiemposServidor(
          segundosFaseInicial: 30,
          segundosPorRonda: 30,
          segundosGraciaReconexionPartida: 3,
          segundosGraciaReconexionLobby: 3,
          intervaloTickReloj: Duration(milliseconds: 75),
        ),
        random: Random(42),
      );
      puerto = await servidor.iniciar(
        direccion: InternetAddress.loopbackIPv4,
        puerto: 0,
      );
      urlWs = 'ws://127.0.0.1:$puerto';
    });

    tearDown(() async {
      for (final c in clientes) {
        await c.cerrar();
      }
      clientes.clear();
      await servidor.detener();
    });

    test('Endpoint HTTP /salud responde estado ok y mensajes malformados no tumban el servidor', () async {
      final http = HttpClient();
      addTearDown(http.close);

      final reqSalud = await http.getUrl(
        Uri.parse('http://127.0.0.1:$puerto/salud'),
      );
      final respSalud = await reqSalud.close();
      expect(respSalud.statusCode, HttpStatus.ok);
      final body = await utf8.decoder.bind(respSalud).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['estado'], 'ok');
      expect(json['salasActivas'], 0);

      // Petición HTTP normal a la raíz devuelve 400 (exige upgrade WebSocket)
      final reqRaiz = await http.getUrl(Uri.parse('http://127.0.0.1:$puerto/'));
      final respRaiz = await reqRaiz.close();
      expect(respRaiz.statusCode, HttpStatus.badRequest);

      // Texto basura por WebSocket devuelve errorOperacion(mensajeMalformado)
      final c = await nuevoCliente();
      final futuroErr = c.eventos.firstWhere(
        (e) => e.tipo == TipoEventoServidor.errorOperacion,
      );
      c.socket.add('esto no es json');
      final err = await futuroErr.timeout(const Duration(seconds: 2));
      expect(err.fallo?.codigo, CodigoFalloMultijugador.mensajeMalformado);
    });

    test('Lobby de 6 jugadores, bloquea el 7º, valida códigos, comparte mapa y exige Listo de los 6', () async {
      final host = await nuevoCliente();
      final evCreacion = await host.enviarConRespuesta(
        TipoComandoCliente.crearSala,
        {'apodo': 'Jugador1', 'nivelId': 'nivel_3'},
      );
      final codigo = evCreacion.estadoSala!.codigoSala;
      expect(codigo.length, 6);
      expect(evCreacion.estadoSala!.nivelId, 'nivel_3');

      // Código inexistente
      final intruso = await nuevoCliente();
      await expectLater(
        () => intruso.enviarConRespuesta(
          TipoComandoCliente.unirseSala,
          {'codigoSala': 'ZZZZZZ', 'apodo': 'X1'},
        ),
        throwsA(
          isA<FalloMultijugador>().having(
            (f) => f.codigo,
            'codigo',
            CodigoFalloMultijugador.salaNoEncontrada,
          ),
        ),
      );

      // Apodo duplicado
      final dup = await nuevoCliente();
      await expectLater(
        () => dup.enviarConRespuesta(
          TipoComandoCliente.unirseSala,
          {'codigoSala': codigo, 'apodo': 'jugador1'},
        ),
        throwsA(
          isA<FalloMultijugador>().having(
            (f) => f.codigo,
            'codigo',
            CodigoFalloMultijugador.apodoEnUso,
          ),
        ),
      );

      // Se unen 5 jugadores más (total 6)
      final invitados = <_ClientePruebaWs>[];
      for (int i = 2; i <= 6; i++) {
        final inv = await nuevoCliente();
        final ev = await inv.enviarConRespuesta(
          TipoComandoCliente.unirseSala,
          {'codigoSala': codigo, 'apodo': 'Jugador$i'},
        );
        expect(ev.estadoSala!.nivelId, 'nivel_3');
        invitados.add(inv);
      }

      await host.esperarSala((s) => s.jugadores.length == 6);

      // 7º jugador rechazado con salaLlena
      final septimo = await nuevoCliente();
      await expectLater(
        () => septimo.enviarConRespuesta(
          TipoComandoCliente.unirseSala,
          {'codigoSala': codigo, 'apodo': 'Jugador7'},
        ),
        throwsA(
          isA<FalloMultijugador>().having(
            (f) => f.codigo,
            'codigo',
            CodigoFalloMultijugador.salaLlena,
          ),
        ),
      );

      // Si solo 5 están listos, iniciarPartida emite noTodosListos
      host.enviarComando(TipoComandoCliente.alternarListo, {'listo': true});
      for (int i = 0; i < 4; i++) {
        invitados[i].enviarComando(
          TipoComandoCliente.alternarListo,
          {'listo': true},
        );
      }
      await host.esperarSala((s) => s.cantidadListos == 5);

      final futuroFaltaListo = host.eventos.firstWhere(
        (e) => e.tipo == TipoEventoServidor.errorOperacion,
      );
      host.enviarComando(TipoComandoCliente.iniciarPartida);
      final errNoListos =
          await futuroFaltaListo.timeout(const Duration(seconds: 2));
      expect(errNoListos.fallo?.codigo, CodigoFalloMultijugador.noTodosListos);

      // Host cambia a nivel_2 -> reinicia Listo de invitados y sincroniza nivel_2 a los 6
      host.enviarComando(
        TipoComandoCliente.seleccionarNivel,
        {'nivelId': 'nivel_2'},
      );
      final sCambio = await invitados.first.esperarSala(
        (s) => s.nivelId == 'nivel_2',
      );
      expect(sCambio.estoyListo, isFalse);

      // Los 6 confirman Listo e inician partida
      for (final inv in invitados) {
        inv.enviarComando(TipoComandoCliente.alternarListo, {'listo': true});
      }
      await host.esperarSala((s) => s.todosListosParaIniciar);
      host.enviarComando(TipoComandoCliente.iniciarPartida);

      for (final c in [host, ...invitados]) {
        final iniciada = await c.esperarSala(
          (s) => s.fase == FaseSala.configurandoIniciales,
        );
        expect(iniciada.nivelId, 'nivel_2');
        expect(iniciada.metaPuntos, 20);
      }
    });

    test('Estrellas iniciales, dados compartidos y concesión con 3 y 2 jugadores', () async {
      final j1 = await nuevoCliente();
      final j2 = await nuevoCliente();
      final j3 = await nuevoCliente();

      final ev = await j1.enviarConRespuesta(
        TipoComandoCliente.crearSala,
        {'apodo': 'Uno', 'nivelId': 'nivel_1'},
      );
      final codigo = ev.estadoSala!.codigoSala;
      await j2.enviarConRespuesta(
        TipoComandoCliente.unirseSala,
        {'codigoSala': codigo, 'apodo': 'Dos'},
      );
      await j3.enviarConRespuesta(
        TipoComandoCliente.unirseSala,
        {'codigoSala': codigo, 'apodo': 'Tres'},
      );

      for (final c in [j1, j2, j3]) {
        c.enviarComando(TipoComandoCliente.alternarListo, {'listo': true});
      }
      await j1.esperarSala((s) => s.todosListosParaIniciar);
      j1.enviarComando(TipoComandoCliente.iniciarPartida);
      await j1.esperarSala((s) => s.fase == FaseSala.configurandoIniciales);

      final estrellas = _estrellasSerializadas('nivel_1');
      for (final c in [j1, j2, j3]) {
        c.enviarComando(
          TipoComandoCliente.confirmarIniciales,
          {'valoresEstrellas': estrellas},
        );
      }

      final r1 = await j1.esperarSala((s) => s.fase == FaseSala.jugandoRondas);
      final r2 = await j2.esperarSala((s) => s.fase == FaseSala.jugandoRondas);
      final r3 = await j3.esperarSala((s) => s.fase == FaseSala.jugandoRondas);

      expect(r1.dado1, isNotNull);
      expect(r1.dado1, r2.dado1);
      expect(r1.dado1, r3.dado1);
      expect(r1.dado2, r2.dado2);
      expect(r1.metaPuntos, 24);

      // J3 concede -> la partida continúa entre J1 y J2
      j3.enviarComando(TipoComandoCliente.concederPartida);
      final trasJ3 = await j1.esperarSala(
        (s) => s.jugadores.any(
          (j) =>
              j.apodo == 'Tres' &&
              j.participacion == EstadoParticipacion.concedido,
        ),
      );
      expect(trasJ3.fase, FaseSala.jugandoRondas);

      // J2 concede -> J1 gana automáticamente
      j2.enviarComando(TipoComandoCliente.concederPartida);
      final fin = await j1.esperarSala((s) => s.fase == FaseSala.finalizada);
      expect(fin.motivoFin, MotivoFinPartida.concesionRival);
      expect(fin.ganadoresIds, [fin.miJugadorId]);
    });

    test('Desconexión abrupta, reconexión por token de sesión, Host Migration y abandono por expiración', () async {
      final j1 = await nuevoCliente();
      final j2 = await nuevoCliente();

      final ev = await j1.enviarConRespuesta(
        TipoComandoCliente.crearSala,
        {'apodo': 'Host'},
      );
      final codigo = ev.estadoSala!.codigoSala;
      await j2.enviarConRespuesta(
        TipoComandoCliente.unirseSala,
        {'codigoSala': codigo, 'apodo': 'Invitado'},
      );

      // Host sale voluntariamente en Lobby -> J2 hereda el rol de Anfitrión
      j1.enviarComando(TipoComandoCliente.salirSala);
      final nuevoHost = await j2.esperarSala(
        (s) => s.soyAnfitrion && s.jugadores.length == 1,
      );
      expect(nuevoHost.soyAnfitrion, isTrue);

      // Se une J3 e inician partida con J2 como nuevo Host
      final j3 = await nuevoCliente();
      await j3.enviarConRespuesta(
        TipoComandoCliente.unirseSala,
        {'codigoSala': codigo, 'apodo': 'Rival'},
      );
      final credJ3 = j3.credencial!;

      j2.enviarComando(TipoComandoCliente.alternarListo, {'listo': true});
      j3.enviarComando(TipoComandoCliente.alternarListo, {'listo': true});
      await j2.esperarSala((s) => s.todosListosParaIniciar);
      j2.enviarComando(TipoComandoCliente.iniciarPartida);
      await j3.esperarSala((s) => s.fase == FaseSala.configurandoIniciales);

      // J3 sufre caída abrupta de socket
      final vioReconectando = j2.esperarSala(
        (s) => s.jugadores.any(
          (j) =>
              j.id == credJ3.jugadorId &&
              j.participacion == EstadoParticipacion.reconectando,
        ),
      );
      await j3.socket.close(WebSocketStatus.goingAway);
      await vioReconectando;

      // J3 reconecta con sus credenciales en un socket nuevo dentro del periodo de gracia
      final j3Reconectado = await nuevoCliente();
      final evRec = await j3Reconectado.enviarConRespuesta(
        TipoComandoCliente.reconectarSala,
        {
          'codigoSala': credJ3.codigoSala,
          'jugadorId': credJ3.jugadorId,
          'tokenSesion': credJ3.tokenSesion,
        },
      );
      expect(evRec.estadoSala?.fase, FaseSala.configurandoIniciales);
      await j2.esperarSala(
        (s) => s.jugadores.any(
          (j) =>
              j.id == credJ3.jugadorId &&
              j.participacion == EstadoParticipacion.conectado,
        ),
      );

      // Si vuelve a caer y deja expirar el periodo de gracia -> J2 gana por abandonoRival
      await j3Reconectado.socket.close(WebSocketStatus.goingAway);
      final victoriaAbandono = await j2.esperarSala(
        (s) => s.fase == FaseSala.finalizada,
      );
      expect(victoriaAbandono.motivoFin, MotivoFinPartida.abandonoRival);
      expect(victoriaAbandono.ganadoresIds, [victoriaAbandono.miJugadorId]);
    });
  });
}
