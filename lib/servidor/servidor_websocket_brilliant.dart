import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../constantes_servidor.dart';
import '../dominio/estados_sala.dart';
import '../dominio/mensajes_protocolo.dart';
import '../dominio/modelos_mapa.dart';
import 'gestor_salas.dart';

/// Servidor WebSocket autoritativo en Dart puro para partidas de hasta 6 jugadores.
class ServidorWebsocketBrilliant {
  final ConfiguracionTiemposServidor _tiempos;
  final Duration _pingInterval;
  final Random? _random;

  HttpServer? _httpServer;
  GestorSalas? _gestor;
  final Map<String, WebSocket> _socketsPorJugador = {};
  final Set<WebSocket> _socketsAbiertos = {};
  WebSocket? _socketPendienteActual;

  ServidorWebsocketBrilliant({
    ConfiguracionTiemposServidor tiempos = const ConfiguracionTiemposServidor(),
    Duration pingInterval = ConstantesServidor.intervaloHeartbeat,
    Random? random,
  })  : _tiempos = tiempos,
        _pingInterval = pingInterval,
        _random = random;

  bool get estaActivo => _httpServer != null;

  int? get puertoEscucha => _httpServer?.port;

  int get cantidadSalasActivas => _gestor?.cantidadSalasActivas ?? 0;

  /// Inicia el servidor en [direccion] y [puerto] (usa puerto 0 para puerto efímero en pruebas).
  Future<int> iniciar({
    InternetAddress? direccion,
    int puerto = ConstantesServidor.puertoPorDefecto,
  }) async {
    if (_httpServer != null) {
      return _httpServer!.port;
    }

    _gestor = GestorSalas(
      enviarEventoAJugador: _enviarEventoAJugador,
      tiempos: _tiempos,
      random: _random,
    );

    final bindAddress = direccion ?? InternetAddress.anyIPv4;
    final server = await HttpServer.bind(bindAddress, puerto);
    _httpServer = server;

    server.listen(
      _manejarPeticionHttp,
      onError: (_) {},
      cancelOnError: false,
    );

    return server.port;
  }

  /// Detiene el servidor y cierra limpiamente todos los sockets conectados.
  Future<void> detener() async {
    _gestor?.cerrar();
    _gestor = null;
    _socketsPorJugador.clear();

    final abiertos = _socketsAbiertos.toList();
    _socketsAbiertos.clear();
    for (final ws in abiertos) {
      try {
        await ws.close(WebSocketStatus.goingAway, 'Servidor detenido');
      } catch (_) {}
    }

    final server = _httpServer;
    _httpServer = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> _manejarPeticionHttp(HttpRequest request) async {
    if (request.uri.path == '/salud') {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'estado': 'ok',
          'salasActivas': cantidadSalasActivas,
        }),
      );
      await request.response.close();
      return;
    }

    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('Se requiere conexión WebSocket.');
      await request.response.close();
      return;
    }

    try {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.pingInterval = _pingInterval;
      _registrarConexion(socket);
    } catch (_) {}
  }

  void _registrarConexion(WebSocket socket) {
    _socketsAbiertos.add(socket);
    String? jugadorVinculadoId;

    socket.listen(
      (dynamic rawData) {
        final gestor = _gestor;
        if (gestor == null) return;

        ComandoCliente? comando;
        try {
          if (rawData is! String) {
            throw const FormatException('Se esperaba texto JSON.');
          }
          final decoded = jsonDecode(rawData);
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('Raíz JSON inválida.');
          }
          comando = ComandoCliente.fromJson(decoded);
        } catch (_) {
          _enviarDirecto(
            socket,
            const EventoServidor(
              tipo: TipoEventoServidor.errorOperacion,
              fallo: FalloMultijugador(
                codigo: CodigoFalloMultijugador.mensajeMalformado,
                mensaje: 'Mensaje de red malformado o no reconocido.',
              ),
            ),
          );
          return;
        }

        try {
          jugadorVinculadoId = _procesarComando(
            gestor: gestor,
            socket: socket,
            comando: comando,
            jugadorActualId: jugadorVinculadoId,
          );
        } on FalloMultijugador catch (fallo) {
          _enviarDirecto(
            socket,
            EventoServidor(
              tipo: TipoEventoServidor.errorOperacion,
              solicitudId: comando.solicitudId,
              fallo: fallo,
            ),
          );
        } catch (_) {
          _enviarDirecto(
            socket,
            EventoServidor(
              tipo: TipoEventoServidor.errorOperacion,
              solicitudId: comando.solicitudId,
              fallo: const FalloMultijugador(
                codigo: CodigoFalloMultijugador.desconocido,
                mensaje: 'Error interno al procesar la solicitud.',
              ),
            ),
          );
        }
      },
      onDone: () => _manejarCierreSocket(socket, jugadorVinculadoId),
      onError: (_) => _manejarCierreSocket(socket, jugadorVinculadoId),
      cancelOnError: true,
    );
  }

  String? _procesarComando({
    required GestorSalas gestor,
    required WebSocket socket,
    required ComandoCliente comando,
    required String? jugadorActualId,
  }) {
    final datos = comando.datos;

    switch (comando.tipo) {
      case TipoComandoCliente.ping:
        _enviarDirecto(
          socket,
          EventoServidor(
            tipo: TipoEventoServidor.pong,
            solicitudId: comando.solicitudId,
          ),
        );
        return jugadorActualId;

      case TipoComandoCliente.crearSala:
        String? creadoId;
        final cred = _ejecutarVinculandoSocket(
          socket: socket,
          accion: () {
            final c = gestor.crearSala(
              apodo: (datos['apodo'] as String?) ?? '',
              nivelId: (datos['nivelId'] as String?) ?? 'nivel_1',
              solicitudId: comando.solicitudId,
            );
            creadoId = c.jugadorId;
            return c;
          },
        );
        return creadoId ?? cred.jugadorId;

      case TipoComandoCliente.unirseSala:
        final cred = _ejecutarVinculandoSocket(
          socket: socket,
          accion: () => gestor.unirseASala(
            codigoSala: (datos['codigoSala'] as String?) ?? '',
            apodo: (datos['apodo'] as String?) ?? '',
            solicitudId: comando.solicitudId,
          ),
        );
        return cred.jugadorId;

      case TipoComandoCliente.reconectarSala:
        final jugadorId = (datos['jugadorId'] as String?) ?? '';
        final socketAnterior = _socketsPorJugador[jugadorId];
        _socketsPorJugador[jugadorId] = socket;
        try {
          final cred = gestor.reconectarJugador(
            codigoSala: (datos['codigoSala'] as String?) ?? '',
            jugadorId: jugadorId,
            tokenSesion: (datos['tokenSesion'] as String?) ?? '',
            solicitudId: comando.solicitudId,
          );
          if (socketAnterior != null && socketAnterior != socket) {
            try {
              socketAnterior.close(
                WebSocketStatus.normalClosure,
                'Sesión reemplazada por reconexión',
              );
            } catch (_) {}
          }
          return cred.jugadorId;
        } catch (e) {
          if (socketAnterior != null) {
            _socketsPorJugador[jugadorId] = socketAnterior;
          } else {
            _socketsPorJugador.remove(jugadorId);
          }
          rethrow;
        }

      case TipoComandoCliente.salirSala:
        if (jugadorActualId != null) {
          _socketsPorJugador.remove(jugadorActualId);
          gestor.salirDeSala(jugadorId: jugadorActualId);
        }
        return null;

      case TipoComandoCliente.seleccionarNivel:
        final id = _exigirJugadorAutenticado(jugadorActualId);
        gestor.seleccionarNivel(
          jugadorId: id,
          nivelId: (datos['nivelId'] as String?) ?? '',
        );
        return id;

      case TipoComandoCliente.alternarListo:
        final id = _exigirJugadorAutenticado(jugadorActualId);
        gestor.alternarListo(
          jugadorId: id,
          listo: (datos['listo'] as bool?) ?? false,
        );
        return id;

      case TipoComandoCliente.iniciarPartida:
        final id = _exigirJugadorAutenticado(jugadorActualId);
        gestor.iniciarPartida(jugadorId: id);
        return id;

      case TipoComandoCliente.confirmarIniciales:
        final id = _exigirJugadorAutenticado(jugadorActualId);
        final rawMapa =
            (datos['valoresEstrellas'] as Map<String, dynamic>?) ?? const {};
        gestor.confirmarValoresIniciales(
          jugadorId: id,
          valoresEstrellas: ComandoCliente.deserializarMapaPosiciones(rawMapa),
        );
        return id;

      case TipoComandoCliente.jugarTurno:
        final id = _exigirJugadorAutenticado(jugadorActualId);
        gestor.jugarTurno(
          jugadorId: id,
          ronda: (datos['ronda'] as num?)?.toInt() ?? -1,
          ancla: PosicionMapa.fromJson(
            (datos['ancla'] as Map<String, dynamic>?) ?? const {},
          ),
          destino: PosicionMapa.fromJson(
            (datos['destino'] as Map<String, dynamic>?) ?? const {},
          ),
          valorColocado: (datos['valorColocado'] as num?)?.toInt() ?? -1,
        );
        return id;

      case TipoComandoCliente.pasarTurno:
        final id = _exigirJugadorAutenticado(jugadorActualId);
        gestor.pasarTurno(
          jugadorId: id,
          ronda: (datos['ronda'] as num?)?.toInt() ?? -1,
        );
        return id;

      case TipoComandoCliente.concederPartida:
        final id = _exigirJugadorAutenticado(jugadorActualId);
        gestor.concederPartida(jugadorId: id);
        return id;
    }
  }

  CredencialSesionSala _ejecutarVinculandoSocket({
    required WebSocket socket,
    required CredencialSesionSala Function() accion,
  }) {
    _socketPendienteActual = socket;
    try {
      final credencial = accion();
      _socketsPorJugador[credencial.jugadorId] = socket;
      return credencial;
    } finally {
      _socketPendienteActual = null;
    }
  }

  String _exigirJugadorAutenticado(String? jugadorActualId) {
    if (jugadorActualId == null) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.permisoDenegado,
        mensaje: 'Debes unirte o crear una sala primero.',
      );
    }
    return jugadorActualId;
  }

  void _manejarCierreSocket(WebSocket socketCerrado, String? jugadorId) {
    _socketsAbiertos.remove(socketCerrado);
    if (jugadorId == null) return;

    if (_socketsPorJugador[jugadorId] == socketCerrado) {
      _socketsPorJugador.remove(jugadorId);
      _gestor?.notificarDesconexionAbrupta(jugadorId);
    }
  }

  void _enviarEventoAJugador(String jugadorId, EventoServidor evento) {
    var socket = _socketsPorJugador[jugadorId];
    if (socket == null &&
        _socketPendienteActual != null &&
        evento.tipo == TipoEventoServidor.sesionEstablecida) {
      socket = _socketPendienteActual;
      _socketsPorJugador[jugadorId] = socket!;
    }
    if (socket == null) return;
    _enviarDirecto(socket, evento);
  }

  void _enviarDirecto(WebSocket socket, EventoServidor evento) {
    if (socket.readyState != WebSocket.open) return;
    try {
      socket.add(jsonEncode(evento.toJson()));
    } catch (_) {}
  }
}
