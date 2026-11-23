import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import 'package:servidor_brilliant/constantes_servidor.dart';
import 'package:servidor_brilliant/dominio/catalogo_esquemas_mapa.dart';
import 'package:servidor_brilliant/dominio/estado_sala.dart';
import 'package:servidor_brilliant/dominio/estados_sala.dart';
import 'package:servidor_brilliant/dominio/mensajes_protocolo.dart';
import 'package:servidor_brilliant/dominio/modelos_mapa.dart';
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

      final esperaDados1 = await j1.esperarSala(
        (s) => s.fase == FaseSala.jugandoRondas && s.esperandoTiroDados,
      );
      expect(esperaDados1.dado1, isNull);
      expect(esperaDados1.dado2, isNull);

      // Invitado NO puede tirar dados
      await expectLater(
        () => j2.enviarConRespuesta(TipoComandoCliente.tirarDados),
        throwsA(
          isA<FalloMultijugador>().having(
            (f) => f.codigo,
            'codigo',
            CodigoFalloMultijugador.permisoDenegado,
          ),
        ),
      );

      // El anfitrión tira los dados para iniciar la Ronda 1
      j1.enviarComando(TipoComandoCliente.tirarDados);

      final r1 = await j1.esperarSala(
        (s) => s.fase == FaseSala.jugandoRondas && !s.esperandoTiroDados,
      );
      final r2 = await j2.esperarSala(
        (s) => s.fase == FaseSala.jugandoRondas && !s.esperandoTiroDados,
      );
      final r3 = await j3.esperarSala(
        (s) => s.fase == FaseSala.jugandoRondas && !s.esperandoTiroDados,
      );

      expect(r1.dado1, isNotNull);
      expect(r1.dado1, r2.dado1);
      expect(r1.dado1, r3.dado1);
      expect(r1.dado2, r2.dado2);
      expect(r1.metaPuntos, 24);

      // Todos pasan turno -> pasa a Ronda 2 pero NO se tiran dados automáticamente
      j1.enviarComando(TipoComandoCliente.pasarTurno, {'ronda': 1});
      j2.enviarComando(TipoComandoCliente.pasarTurno, {'ronda': 1});
      j3.enviarComando(TipoComandoCliente.pasarTurno, {'ronda': 1});

      final ronda2Espera = await j1.esperarSala(
        (s) => s.rondaActual == 2 && s.esperandoTiroDados,
      );
      expect(ronda2Espera.dado1, isNull);
      expect(ronda2Espera.dado2, isNull);

      // J3 concede -> J3 también recibe su estado actualizado y la partida continúa entre J1 y J2
      j3.enviarComando(TipoComandoCliente.concederPartida);
      final trasJ3ParaJ3 = await j3.esperarSala(
        (s) => s.jugadores.any(
          (j) =>
              j.id == s.miJugadorId &&
              j.participacion == EstadoParticipacion.concedido,
        ),
      );
      expect(
        trasJ3ParaJ3.jugadores
            .firstWhere((j) => j.id == trasJ3ParaJ3.miJugadorId)
            .participacion,
        EstadoParticipacion.concedido,
      );
      final trasJ3 = await j1.esperarSala(
        (s) => s.jugadores.any(
          (j) =>
              j.apodo == 'Tres' &&
              j.participacion == EstadoParticipacion.concedido,
        ),
      );
      expect(trasJ3.fase, FaseSala.jugandoRondas);

      // J2 concede -> tanto J1 (ganador) como J2 (quien concedió) reciben FaseSala.finalizada
      j2.enviarComando(TipoComandoCliente.concederPartida);
      final fin = await j1.esperarSala((s) => s.fase == FaseSala.finalizada);
      final finParaJ2 =
          await j2.esperarSala((s) => s.fase == FaseSala.finalizada);
      expect(fin.motivoFin, MotivoFinPartida.concesionRival);
      expect(fin.ganadoresIds, [fin.miJugadorId]);
      expect(finParaJ2.motivoFin, MotivoFinPartida.concesionRival);
      expect(finParaJ2.ganadoresIds, [fin.miJugadorId]);
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

    test('Envía y difunde mensajes de chat a todos los integrantes de la sala', () async {
      final j1 = await nuevoCliente();
      final j2 = await nuevoCliente();

      final ev1 = await j1.enviarConRespuesta(
        TipoComandoCliente.crearSala,
        {'apodo': 'HostChat', 'nivelId': 'nivel_1'},
      );
      final codigo = ev1.credencial!.codigoSala;

      await j2.enviarConRespuesta(
        TipoComandoCliente.unirseSala,
        {'codigoSala': codigo, 'apodo': 'InvitadoChat'},
      );

      final escuchaChatJ2 = j2.eventos.firstWhere(
        (e) =>
            e.tipo == TipoEventoServidor.mensajeChatRecibido &&
            e.mensajeChat?.texto == '¡Hola desde J1!',
      ).timeout(const Duration(seconds: 3));

      j1.enviarComando(
        TipoComandoCliente.enviarMensajeChat,
        {'texto': '¡Hola desde J1!'},
      );

      final recibidoJ2 = await escuchaChatJ2;
      expect(recibidoJ2.mensajeChat?.remitenteApodo, 'HostChat');
      expect(recibidoJ2.mensajeChat?.texto, '¡Hola desde J1!');
      expect(recibidoJ2.mensajeChat?.esSistema, isFalse);
    });

    test('Gracia por desconexión es de 30s y difunde contador regresivo en tiempo real', () async {
      expect(ConstantesServidor.segundosGraciaReconexionPartida, 30);
      expect(ConstantesServidor.segundosGraciaReconexionLobby, 30);

      final j1 = await nuevoCliente();
      final j2 = await nuevoCliente();

      final ev1 = await j1.enviarConRespuesta(
        TipoComandoCliente.crearSala,
        {'apodo': 'AnfitrionTimer', 'nivelId': 'nivel_1'},
      );
      final codigo = ev1.credencial!.codigoSala;
      await j2.enviarConRespuesta(
        TipoComandoCliente.unirseSala,
        {'codigoSala': codigo, 'apodo': 'InvitadoTimer'},
      );

      // J1 se desconecta abruptamente en el lobby -> gracia inicial 3s (según setUp) y baja a 2s, 1s en tiempo real
      await j1.socket.close(WebSocketStatus.goingAway);

      final estadoInicial = await j2.esperarSala(
        (s) =>
            (s.mensajeEventoReciente ?? '').contains('3s') &&
            s.jugadores.any(
              (j) =>
                  j.apodo == 'AnfitrionTimer' &&
                  j.segundosReconexionRestantes == 3,
            ),
      );
      expect(estadoInicial.mensajeEventoReciente, contains('3s'));

      final estadoCuentaRegresiva = await j2.esperarSala(
        (s) =>
            (s.mensajeEventoReciente ?? '').contains('2s') &&
            s.jugadores.any(
              (j) =>
                  j.apodo == 'AnfitrionTimer' &&
                  j.segundosReconexionRestantes == 2,
            ),
      );
      expect(estadoCuentaRegresiva.mensajeEventoReciente, contains('2s'));
    });

    test('Partida llena de 6 jugadores: simula rondas completas, reconexión y salirSala activa', () async {
      final jugadores = <_ClientePruebaWs>[];
      for (int i = 0; i < 6; i++) {
        jugadores.add(await nuevoCliente());
      }

      final evHost = await jugadores.first.enviarConRespuesta(
        TipoComandoCliente.crearSala,
        {'apodo': 'Jugador1', 'nivelId': 'nivel_1'},
      );
      final codigo = evHost.credencial!.codigoSala;

      for (int i = 1; i < 6; i++) {
        await jugadores[i].enviarConRespuesta(
          TipoComandoCliente.unirseSala,
          {'codigoSala': codigo, 'apodo': 'Jugador${i + 1}'},
        );
      }

      // Un 7º jugador debe ser rechazado con salaLlena
      final j7 = await nuevoCliente();
      await expectLater(
        () => j7.enviarConRespuesta(
          TipoComandoCliente.unirseSala,
          {'codigoSala': codigo, 'apodo': 'Sobreviviente7'},
        ),
        throwsA(
          isA<FalloMultijugador>().having(
            (f) => f.codigo,
            'codigo',
            CodigoFalloMultijugador.salaLlena,
          ),
        ),
      );

      // Todos pulsan Listo y anfitrión arranca la partida llena (6/6)
      for (final c in jugadores) {
        c.enviarComando(TipoComandoCliente.alternarListo, {'listo': true});
      }
      await jugadores.first.esperarSala((s) => s.todosListosParaIniciar);
      jugadores.first.enviarComando(TipoComandoCliente.iniciarPartida);

      for (final c in jugadores) {
        final s = await c.esperarSala(
          (st) => st.fase == FaseSala.configurandoIniciales,
        );
        expect(s.metaPuntos, ConstantesServidor.metaPuntos5o6Jugadores);
        expect(s.jugadores.length, 6);
      }

      // Todos confirman sus 6 estrellas iniciales
      final estrellas = _estrellasSerializadas('nivel_1');
      for (final c in jugadores) {
        c.enviarComando(
          TipoComandoCliente.confirmarIniciales,
          {'valoresEstrellas': estrellas},
        );
      }

      final mapa = CatalogoEsquemasMapa.porId('nivel_1');
      bool p6Reconectado = false;
      bool p5Salio = false;
      _ClientePruebaWs p6Actual = jugadores[5];

      // Simular rondas completas con jugadas legales hasta finalizar la partida
      for (int iter = 0; iter < 55; iter++) {
        final estadoHost = await jugadores.first.esperarSala(
          (s) =>
              s.fase == FaseSala.finalizada ||
              (s.fase == FaseSala.jugandoRondas && s.esperandoTiroDados),
        );
        if (estadoHost.fase == FaseSala.finalizada) break;

        final ronda = estadoHost.rondaActual;

        // En ronda 2 probamos caída abrupta y reconexión real de J6
        if (ronda == 2 && !p6Reconectado) {
          p6Reconectado = true;
          final credP6 = p6Actual.credencial!;
          await p6Actual.socket.close(WebSocketStatus.goingAway);
          await jugadores.first.esperarSala(
            (s) => s.jugadores.any(
              (j) =>
                  j.id == credP6.jugadorId &&
                  j.participacion == EstadoParticipacion.reconectando,
            ),
          );
          final nuevoP6 = await nuevoCliente();
          final evRec = await nuevoP6.enviarConRespuesta(
            TipoComandoCliente.reconectarSala,
            {
              'codigoSala': credP6.codigoSala,
              'jugadorId': credP6.jugadorId,
              'tokenSesion': credP6.tokenSesion,
            },
          );
          expect(evRec.estadoSala?.fase, FaseSala.jugandoRondas);
          p6Actual = nuevoP6;
        }

        // En ronda 3 probamos salirSala en plena partida activa para J5
        if (ronda == 3 && !p5Salio) {
          p5Salio = true;
          final idP5 = jugadores[4].credencial!.jugadorId;
          jugadores[4].enviarComando(TipoComandoCliente.salirSala);
          await jugadores.first.esperarSala(
            (s) => s.jugadores.any(
              (j) =>
                  j.id == idP5 &&
                  j.participacion == EstadoParticipacion.concedido,
            ),
          );
        }

        // Anfitrión tira los dados obligatorios de esta ronda
        jugadores.first.enviarComando(TipoComandoCliente.tirarDados);

        final activos = [
          jugadores[0],
          jugadores[1],
          jugadores[2],
          jugadores[3],
          if (!p5Salio) jugadores[4],
          p6Actual,
        ];

        for (final c in activos) {
          final st = await c.esperarSala(
            (s) =>
                s.fase == FaseSala.finalizada ||
                (s.rondaActual == ronda &&
                    !s.esperandoTiroDados &&
                    s.dado1 != null &&
                    s.dado2 != null),
          );
          if (st.fase == FaseSala.finalizada) break;

          final jugada = _buscarPrimeraJugadaLegal(
            mapa: mapa,
            valores: st.misValoresTablero,
            d1: st.dado1!,
            d2: st.dado2!,
          );
          if (jugada != null) {
            c.enviarComando(TipoComandoCliente.jugarTurno, {
              'ronda': ronda,
              'ancla': jugada.$1.toJson(),
              'destino': jugada.$2.toJson(),
              'valorColocado': jugada.$3,
            });
          } else {
            c.enviarComando(TipoComandoCliente.pasarTurno, {'ronda': ronda});
          }
        }
      }

      final fin = await jugadores.first.esperarSala(
        (s) => s.fase == FaseSala.finalizada,
      );
      expect(fin.ganadoresIds, isNotEmpty);
      expect(p6Reconectado, isTrue);
      expect(p5Salio, isTrue);
      expect(
        fin.jugadores.firstWhere((j) => j.apodo == 'Jugador5').participacion,
        EstadoParticipacion.concedido,
      );
    });

    test('Dos salas multijugador simultáneas en el mismo servidor operan en paralelo sin interferencias', () async {
      // Sala A: 6 jugadores en nivel_2
      final salaA = <_ClientePruebaWs>[];
      for (int i = 0; i < 6; i++) {
        salaA.add(await nuevoCliente());
      }
      final evA = await salaA.first.enviarConRespuesta(
        TipoComandoCliente.crearSala,
        {'apodo': 'HostA', 'nivelId': 'nivel_2'},
      );
      final codA = evA.credencial!.codigoSala;
      for (int i = 1; i < 6; i++) {
        await salaA[i].enviarConRespuesta(
          TipoComandoCliente.unirseSala,
          {'codigoSala': codA, 'apodo': 'A_$i'},
        );
      }

      // Sala B al mismo tiempo: 4 jugadores en nivel_4
      final salaB = <_ClientePruebaWs>[];
      for (int i = 0; i < 4; i++) {
        salaB.add(await nuevoCliente());
      }
      final evB = await salaB.first.enviarConRespuesta(
        TipoComandoCliente.crearSala,
        {'apodo': 'HostB', 'nivelId': 'nivel_4'},
      );
      final codB = evB.credencial!.codigoSala;
      expect(codA, isNot(codB));
      expect(servidor.cantidadSalasActivas, 2);

      for (int i = 1; i < 4; i++) {
        await salaB[i].enviarConRespuesta(
          TipoComandoCliente.unirseSala,
          {'codigoSala': codB, 'apodo': 'B_$i'},
        );
      }

      // Chat en Sala A NO debe llegar a Sala B y viceversa
      final chatEnB = salaB[1].eventos.firstWhere(
            (e) =>
                e.tipo == TipoEventoServidor.mensajeChatRecibido &&
                e.mensajeChat?.texto == 'SoloSalaB',
          );
      bool fugasDeChatEnB = false;
      final subFuga = salaB[1].eventos.listen((e) {
        if (e.tipo == TipoEventoServidor.mensajeChatRecibido &&
            e.mensajeChat?.texto == 'SoloSalaA') {
          fugasDeChatEnB = true;
        }
      });
      addTearDown(subFuga.cancel);

      salaA[0].enviarComando(
        TipoComandoCliente.enviarMensajeChat,
        {'texto': 'SoloSalaA'},
      );
      salaB[0].enviarComando(
        TipoComandoCliente.enviarMensajeChat,
        {'texto': 'SoloSalaB'},
      );
      await chatEnB.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fugasDeChatEnB, isFalse);

      // Iniciar ambas salas simultáneamente
      for (final c in [...salaA, ...salaB]) {
        c.enviarComando(TipoComandoCliente.alternarListo, {'listo': true});
      }
      await salaA.first.esperarSala((s) => s.todosListosParaIniciar);
      await salaB.first.esperarSala((s) => s.todosListosParaIniciar);

      salaA.first.enviarComando(TipoComandoCliente.iniciarPartida);
      salaB.first.enviarComando(TipoComandoCliente.iniciarPartida);

      final estA = _estrellasSerializadas('nivel_2');
      final estB = _estrellasSerializadas('nivel_4');

      for (final c in salaA) {
        final s = await c.esperarSala(
          (st) => st.fase == FaseSala.configurandoIniciales,
        );
        expect(s.codigoSala, codA);
        expect(s.nivelId, 'nivel_2');
        expect(s.metaPuntos, ConstantesServidor.metaPuntos5o6Jugadores);
        c.enviarComando(
          TipoComandoCliente.confirmarIniciales,
          {'valoresEstrellas': estA},
        );
      }
      for (final c in salaB) {
        final s = await c.esperarSala(
          (st) => st.fase == FaseSala.configurandoIniciales,
        );
        expect(s.codigoSala, codB);
        expect(s.nivelId, 'nivel_4');
        expect(s.metaPuntos, ConstantesServidor.metaPuntos4Jugadores);
        c.enviarComando(
          TipoComandoCliente.confirmarIniciales,
          {'valoresEstrellas': estB},
        );
      }

      // Ronda 1 simultánea en Sala A y Sala B
      await salaA.first.esperarSala(
        (s) => s.fase == FaseSala.jugandoRondas && s.esperandoTiroDados,
      );
      await salaB.first.esperarSala(
        (s) => s.fase == FaseSala.jugandoRondas && s.esperandoTiroDados,
      );

      salaA.first.enviarComando(TipoComandoCliente.tirarDados);
      salaB.first.enviarComando(TipoComandoCliente.tirarDados);

      final mapaA = CatalogoEsquemasMapa.porId('nivel_2');
      final mapaB = CatalogoEsquemasMapa.porId('nivel_4');

      for (final c in salaA) {
        final st = await c.esperarSala(
          (s) => s.rondaActual == 1 && !s.esperandoTiroDados,
        );
        final jug = _buscarPrimeraJugadaLegal(
          mapa: mapaA,
          valores: st.misValoresTablero,
          d1: st.dado1!,
          d2: st.dado2!,
        );
        if (jug != null) {
          c.enviarComando(TipoComandoCliente.jugarTurno, {
            'ronda': 1,
            'ancla': jug.$1.toJson(),
            'destino': jug.$2.toJson(),
            'valorColocado': jug.$3,
          });
        } else {
          c.enviarComando(TipoComandoCliente.pasarTurno, {'ronda': 1});
        }
      }

      for (final c in salaB) {
        final st = await c.esperarSala(
          (s) => s.rondaActual == 1 && !s.esperandoTiroDados,
        );
        final jug = _buscarPrimeraJugadaLegal(
          mapa: mapaB,
          valores: st.misValoresTablero,
          d1: st.dado1!,
          d2: st.dado2!,
        );
        if (jug != null) {
          c.enviarComando(TipoComandoCliente.jugarTurno, {
            'ronda': 1,
            'ancla': jug.$1.toJson(),
            'destino': jug.$2.toJson(),
            'valorColocado': jug.$3,
          });
        } else {
          c.enviarComando(TipoComandoCliente.pasarTurno, {'ronda': 1});
        }
      }

      final r2A = await salaA.first.esperarSala((s) => s.rondaActual == 2);
      final r2B = await salaB.first.esperarSala((s) => s.rondaActual == 2);
      expect(r2A.codigoSala, codA);
      expect(r2A.jugadores.length, 6);
      expect(r2B.codigoSala, codB);
      expect(r2B.jugadores.length, 4);
      expect(servidor.cantidadSalasActivas, 2);
    });

    test('Simulación real de partidas de 2, 3, 4, 5 y 6 jugadores en salas simultáneas con movimientos y rendiciones', () async {
      final metasEsperadas = {2: 26, 3: 24, 4: 22, 5: 20, 6: 20};
      final mapasCiclo = ['nivel_1', 'nivel_2', 'nivel_3', 'nivel_4', 'nivel_1'];
      final salasSimultaneas = <int, List<_ClientePruebaWs>>{};
      final codigosPorTamano = <int, String>{};

      // 1. Crear 5 salas simultáneas en el mismo servidor (de 2, 3, 4, 5 y 6 jugadores)
      var idxMapa = 0;
      for (final cantJugadores in [2, 3, 4, 5, 6]) {
        final nivelId = mapasCiclo[idxMapa++];
        final clientesSala = <_ClientePruebaWs>[];
        for (int i = 0; i < cantJugadores; i++) {
          clientesSala.add(await nuevoCliente());
        }

        final evHost = await clientesSala.first.enviarConRespuesta(
          TipoComandoCliente.crearSala,
          {'apodo': 'S${cantJugadores}_J1', 'nivelId': nivelId},
        );
        final codigo = evHost.credencial!.codigoSala;
        codigosPorTamano[cantJugadores] = codigo;

        for (int i = 1; i < cantJugadores; i++) {
          await clientesSala[i].enviarConRespuesta(
            TipoComandoCliente.unirseSala,
            {'codigoSala': codigo, 'apodo': 'S${cantJugadores}_J${i + 1}'},
          );
        }

        for (final c in clientesSala) {
          c.enviarComando(TipoComandoCliente.alternarListo, {'listo': true});
        }
        await clientesSala.first.esperarSala((s) => s.todosListosParaIniciar);
        clientesSala.first.enviarComando(TipoComandoCliente.iniciarPartida);

        final estadoIni = await clientesSala.first.esperarSala(
          (s) => s.fase == FaseSala.configurandoIniciales,
        );
        expect(estadoIni.metaPuntos, metasEsperadas[cantJugadores]);
        salasSimultaneas[cantJugadores] = clientesSala;
      }

      expect(servidor.cantidadSalasActivas, 5);

      // 2. En la sala de 5 jugadores, el jugador 5 se rinde durante la fase de estrellas iniciales
      salasSimultaneas[5]![4].enviarComando(TipoComandoCliente.concederPartida);
      await salasSimultaneas[5]!.first.esperarSala(
        (s) => s.jugadores.any(
          (j) =>
              j.apodo == 'S5_J5' &&
              j.participacion == EstadoParticipacion.concedido,
        ),
      );

      // Todos los jugadores activos de las 5 salas confirman sus estrellas iniciales
      idxMapa = 0;
      for (final cantJugadores in [2, 3, 4, 5, 6]) {
        final nivelId = mapasCiclo[idxMapa++];
        final estrellas = _estrellasSerializadas(nivelId);
        final clientes = salasSimultaneas[cantJugadores]!;
        for (int i = 0; i < clientes.length; i++) {
          if (cantJugadores == 5 && i == 4) continue; // ya concedió
          clientes[i].enviarComando(
            TipoComandoCliente.confirmarIniciales,
            {'valoresEstrellas': estrellas},
          );
        }
      }

      // 3. Todas las salas pasan a Ronda 1 esperando tiro de dados
      for (final cantJugadores in [2, 3, 4, 5, 6]) {
        final st = await salasSimultaneas[cantJugadores]!.first.esperarSala(
          (s) => s.fase == FaseSala.jugandoRondas && s.rondaActual == 1,
        );
        expect(st.esperandoTiroDados, isTrue);
      }

      // 4. En la sala de 4 jugadores, el ANFITRIÓN (S4_J1) se rinde antes de tirar los dados ->
      //    S4_J2 hereda el rol de anfitrión, el banner lo anuncia y tira los dados sin bloquear la sala
      salasSimultaneas[4]!.first.enviarComando(TipoComandoCliente.concederPartida);
      final stNuevoHost4 = await salasSimultaneas[4]![1].esperarSala(
        (s) => s.soyAnfitrion && s.esperandoTiroDados,
      );
      expect(
        stNuevoHost4.jugadores.firstWhere((j) => j.esAnfitrion).apodo,
        'S4_J2',
      );
      expect(
        stNuevoHost4.mensajeEventoReciente,
        contains('S4_J2 es el nuevo anfitrión y debe tirar los dados'),
      );

      // 5. Jugar 3 rondas reales en todas las salas simultáneamente
      idxMapa = 0;
      for (final cantJugadores in [2, 3, 4, 5, 6]) {
        final nivelId = mapasCiclo[idxMapa++];
        final mapa = CatalogoEsquemasMapa.porId(nivelId);
        final clientes = salasSimultaneas[cantJugadores]!;

        for (int ronda = 1; ronda <= 3; ronda++) {
          final indiceHostActual = cantJugadores == 4 ? 1 : 0;
          clientes[indiceHostActual].enviarComando(TipoComandoCliente.tirarDados);

          for (int i = 0; i < clientes.length; i++) {
            if (cantJugadores == 5 && i == 4) continue;
            if (cantJugadores == 4 && i == 0) continue;

            final st = await clientes[i].esperarSala(
              (s) => s.rondaActual == ronda && !s.esperandoTiroDados,
            );
            final jugada = _buscarPrimeraJugadaLegal(
              mapa: mapa,
              valores: st.misValoresTablero,
              d1: st.dado1!,
              d2: st.dado2!,
            );
            if (jugada != null) {
              clientes[i].enviarComando(TipoComandoCliente.jugarTurno, {
                'ronda': ronda,
                'ancla': jugada.$1.toJson(),
                'destino': jugada.$2.toJson(),
                'valorColocado': jugada.$3,
              });
            } else {
              clientes[i].enviarComando(
                TipoComandoCliente.pasarTurno,
                {'ronda': ronda},
              );
            }
          }

          final sig = await clientes[indiceHostActual].esperarSala(
            (s) => s.rondaActual == ronda + 1 || s.fase == FaseSala.finalizada,
          );
          expect(sig.rondaActual, ronda + 1);
        }
      }

      // 6. En la sala de 2 jugadores, S2_J2 se rinde -> S2_J1 gana inmediatamente y ambos reciben finalizada
      salasSimultaneas[2]![1].enviarComando(TipoComandoCliente.concederPartida);
      final finS2Host = await salasSimultaneas[2]!.first.esperarSala(
        (s) => s.fase == FaseSala.finalizada,
      );
      final finS2Rend = await salasSimultaneas[2]![1].esperarSala(
        (s) => s.fase == FaseSala.finalizada,
      );
      expect(finS2Host.motivoFin, MotivoFinPartida.concesionRival);
      expect(finS2Rend.motivoFin, MotivoFinPartida.concesionRival);

      // 7. En la sala de 3 jugadores, tiran dados en Ronda 4, J1 y J2 juegan, y J3 (el único que faltaba)
      //    se rinde a mitad de ronda -> la ronda se cierra al instante y pasa a Ronda 5 entre J1 y J2
      salasSimultaneas[3]!.first.enviarComando(TipoComandoCliente.tirarDados);
      for (int i = 0; i < 2; i++) {
        await salasSimultaneas[3]![i].esperarSala(
          (s) => s.rondaActual == 4 && !s.esperandoTiroDados,
        );
        salasSimultaneas[3]![i].enviarComando(
          TipoComandoCliente.pasarTurno,
          {'ronda': 4},
        );
      }
      await salasSimultaneas[3]![2].esperarSala(
        (s) => s.rondaActual == 4 && !s.esperandoTiroDados,
      );
      salasSimultaneas[3]![2].enviarComando(TipoComandoCliente.concederPartida);
      final r5S3 = await salasSimultaneas[3]!.first.esperarSala(
        (s) => s.rondaActual == 5 && s.esperandoTiroDados,
      );
      expect(
        r5S3.jugadores.where((j) => j.participacion.sigueEnCompetencia).length,
        2,
      );
    });
  });
}

(PosicionMapa, PosicionMapa, int)? _buscarPrimeraJugadaLegal({
  required EsquemaMapa mapa,
  required Map<PosicionMapa, int> valores,
  required int d1,
  required int d2,
}) {
  final tablero = TableroServidorJugador(mapa: mapa, valoresIniciales: valores);
  for (final entry in valores.entries) {
    final ancla = entry.key;
    final val = entry.value;
    if (val == d1) {
      for (final vecino in tablero.vecinosOrtogonales(ancla)) {
        if (tablero.esJugadaLegal(
          ancla: ancla,
          destino: vecino,
          dado1: d1,
          dado2: d2,
          valorAColocar: d2,
        )) {
          return (ancla, vecino, d2);
        }
      }
    }
    if (val == d2) {
      for (final vecino in tablero.vecinosOrtogonales(ancla)) {
        if (tablero.esJugadaLegal(
          ancla: ancla,
          destino: vecino,
          dado1: d1,
          dado2: d2,
          valorAColocar: d1,
        )) {
          return (ancla, vecino, d1);
        }
      }
    }
  }
  return null;
}
