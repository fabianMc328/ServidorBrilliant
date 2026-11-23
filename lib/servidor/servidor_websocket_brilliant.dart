import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../constantes_servidor.dart';
import '../dominio/estados_sala.dart';
import '../dominio/mensajes_protocolo.dart';
import '../dominio/modelos_mapa.dart';
import 'gestor_salas.dart';
import 'gestor_usuarios.dart';

/// Servidor WebSocket autoritativo en Dart puro para partidas de hasta 6 jugadores.
class ServidorWebsocketBrilliant {
  final ConfiguracionTiemposServidor _tiempos;
  final Duration _pingInterval;
  final Random? _random;
  final GestorUsuarios _gestorUsuarios;

  HttpServer? _httpServer;
  RawDatagramSocket? _udpDescubrimiento;
  GestorSalas? _gestor;
  final Map<String, WebSocket> _socketsPorJugador = {};
  final Set<WebSocket> _socketsAbiertos = {};
  WebSocket? _socketPendienteActual;

  ServidorWebsocketBrilliant({
    ConfiguracionTiemposServidor tiempos = const ConfiguracionTiemposServidor(),
    Duration pingInterval = ConstantesServidor.intervaloHeartbeat,
    Random? random,
    GestorUsuarios? gestorUsuarios,
    bool persistirUsuarios = false,
  })  : _tiempos = tiempos,
        _pingInterval = pingInterval,
        _random = random,
        _gestorUsuarios = gestorUsuarios ??
            GestorUsuarios(
              rutaArchivoPersistencia: persistirUsuarios
                  ? (Platform.environment['BRILLIANT_RUTA_USUARIOS'] ??
                      'datos/usuarios.json')
                  : null,
            );

  GestorUsuarios get gestorUsuarios => _gestorUsuarios;

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
    _gestorUsuarios.tieneConexionMultijugadorActiva =
        (apodo) => _gestor?.tieneJugadorConectadoConApodo(apodo) ?? false;

    final bindAddress = direccion ?? InternetAddress.anyIPv4;
    final server = await HttpServer.bind(bindAddress, puerto);
    _httpServer = server;

    server.listen(
      _manejarPeticionHttp,
      onError: (_) {},
      cancelOnError: false,
    );

    await _iniciarDescubrimientoUdp(server.port);

    return server.port;
  }

  Future<void> _iniciarDescubrimientoUdp(int puertoWebsocket) async {
    try {
      final udp = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        ConstantesServidor.puertoDescubrimientoUdp,
        reuseAddress: true,
      );
      udp.broadcastEnabled = true;
      _udpDescubrimiento = udp;

      udp.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          final datagram = udp.receive();
          if (datagram == null) return;

          final texto = utf8.decode(datagram.data, allowMalformed: true).trim();
          if (texto == ConstantesServidor.mensajeDescubrimientoUdp) {
            final respuesta = jsonEncode({
              'servicio': 'servidorBrilliant',
              'puerto': puertoWebsocket,
            });
            try {
              udp.send(
                utf8.encode(respuesta),
                datagram.address,
                datagram.port,
              );
            } catch (_) {}
          }
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {
      // Si el puerto UDP ya está ocupado (ej. pruebas paralelas), continúa sin error.
    }
  }

  /// Detiene el servidor y cierra limpiamente todos los sockets conectados.
  Future<void> detener() async {
    _udpDescubrimiento?.close();
    _udpDescubrimiento = null;

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
    _aplicarCabecerasCors(request.response);

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    if (request.uri.path == '/salud') {
      await _responderJson(
        request.response,
        HttpStatus.ok,
        {
          'servicio': 'servidorBrilliant',
          'estado': 'ok',
          'puerto': puertoEscucha,
          'salasActivas': cantidadSalasActivas,
          'usuariosRegistrados': _gestorUsuarios.cantidadUsuarios,
        },
      );
      return;
    }

    if (request.uri.path.startsWith('/auth/')) {
      await _manejarPeticionAuth(request);
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

  void _aplicarCabecerasCors(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type, Authorization',
    );
  }

  Future<void> _manejarPeticionAuth(HttpRequest request) async {
    final path = request.uri.path;

    try {
      if (path == '/auth/registro' && request.method == 'POST') {
        final cuerpo = await _leerJsonBody(request);
        final resultado = _gestorUsuarios.registrarUsuario(
          apodo: (cuerpo['apodo'] as String?) ?? '',
          email: (cuerpo['email'] as String?) ?? '',
          contrasena: (cuerpo['contrasena'] as String?) ?? '',
          dispositivoId: cuerpo['dispositivoId'] as String?,
        );
        await _responderJson(
          request.response,
          HttpStatus.created,
          resultado.toJson(),
        );
        return;
      }

      if (path == '/auth/login' && request.method == 'POST') {
        final cuerpo = await _leerJsonBody(request);
        final resultado = _gestorUsuarios.iniciarSesion(
          identificador: (cuerpo['identificador'] as String?) ?? '',
          contrasena: (cuerpo['contrasena'] as String?) ?? '',
          dispositivoId: cuerpo['dispositivoId'] as String?,
        );
        await _responderJson(
          request.response,
          HttpStatus.ok,
          resultado.toJson(),
        );
        return;
      }

      if (path == '/auth/sesion' && request.method == 'GET') {
        final token = _extraerBearerToken(request);
        final dispId = request.uri.queryParameters['dispositivoId'];
        final usuario = token == null
            ? null
            : _gestorUsuarios.obtenerUsuarioPorToken(
                token,
                dispositivoId: dispId,
              );
        if (usuario == null) {
          await _responderJson(
            request.response,
            HttpStatus.unauthorized,
            {'error': 'Sesión expirada o no válida.'},
          );
          return;
        }
        await _responderJson(
          request.response,
          HttpStatus.ok,
          {'usuario': usuario.toPublicJson()},
        );
        return;
      }

      if (path == '/auth/logout' && request.method == 'POST') {
        final token = _extraerBearerToken(request);
        if (token != null) {
          _gestorUsuarios.cerrarSesion(token);
        }
        await _responderJson(request.response, HttpStatus.ok, {'ok': true});
        return;
      }

      await _responderJson(
        request.response,
        HttpStatus.notFound,
        {'error': 'Ruta de autenticación no encontrada.'},
      );
    } on FalloAutenticacionServidor catch (fallo) {
      await _responderJson(
        request.response,
        fallo.statusCode,
        {
          'error': fallo.mensaje,
          'codigo': fallo.codigo,
        },
      );
    } on FormatException catch (e) {
      await _responderJson(
        request.response,
        HttpStatus.badRequest,
        {'error': e.message},
      );
    } catch (_) {
      await _responderJson(
        request.response,
        HttpStatus.internalServerError,
        {'error': 'Error interno al procesar la autenticación.'},
      );
    }
  }

  Future<Map<String, dynamic>> _leerJsonBody(HttpRequest request) async {
    const limiteBytes = 16 * 1024;
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > limiteBytes) {
        throw const FormatException('La solicitud supera el tamaño permitido.');
      }
    }
    final texto = utf8.decode(bytes);
    if (texto.trim().isEmpty) {
      throw const FormatException('El cuerpo JSON está vacío.');
    }
    final decoded = jsonDecode(texto);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Se esperaba un objeto JSON.');
    }
    return decoded;
  }

  String? _extraerBearerToken(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header == null || header.isEmpty) return null;
    const prefijo = 'Bearer ';
    if (header.startsWith(prefijo)) {
      return header.substring(prefijo.length).trim();
    }
    return null;
  }

  Future<void> _responderJson(
    HttpResponse response,
    int statusCode,
    Map<String, dynamic> data,
  ) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    await response.close();
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

      case TipoComandoCliente.tirarDados:
        final id = _exigirJugadorAutenticado(jugadorActualId);
        gestor.tirarDados(jugadorId: id);
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

      case TipoComandoCliente.enviarMensajeChat:
        final id = _exigirJugadorAutenticado(jugadorActualId);
        gestor.enviarMensajeChat(
          jugadorId: id,
          texto: (datos['texto'] as String?) ?? '',
        );
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
