import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../constantes_servidor.dart';

/// Limpia espacios exteriores y colapsa espacios múltiples internos del apodo.
String normalizarApodoVisible(String apodo) {
  return apodo.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Genera una clave canónica para impedir apodos duplicados por mayúsculas,
/// espacios extra o acentos equivalentes (por ejemplo "Fabian", "fabian" o "Fabián").
String normalizarApodoClave(String apodo) {
  final limpio = normalizarApodoVisible(apodo).toLowerCase();
  const mapaAcentos = {
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
  };

  final buffer = StringBuffer();
  for (final rune in limpio.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(mapaAcentos[ch] ?? ch);
  }
  return buffer.toString();
}

/// Excepción controlada del sistema de autenticación en el servidor.
class FalloAutenticacionServidor implements Exception {
  final int statusCode;
  final String codigo;
  final String mensaje;

  const FalloAutenticacionServidor({
    required this.statusCode,
    required this.codigo,
    required this.mensaje,
  });

  @override
  String toString() => 'FalloAutenticacionServidor($codigo): $mensaje';
}

/// Cuenta registrada en el servidor autoritativo de Brilliant.
class UsuarioCuenta {
  final String id;
  final String apodo;
  final String email;
  final DateTime fechaRegistro;
  final String sal;
  final String hashContrasena;

  const UsuarioCuenta({
    required this.id,
    required this.apodo,
    required this.email,
    required this.fechaRegistro,
    required this.sal,
    required this.hashContrasena,
  });

  Map<String, dynamic> toPublicJson() => {
        'id': id,
        'apodo': apodo,
        'email': email,
        'fechaRegistro': fechaRegistro.toUtc().toIso8601String(),
      };

  Map<String, dynamic> toStorageJson() => {
        'id': id,
        'apodo': apodo,
        'email': email,
        'fechaRegistro': fechaRegistro.toUtc().toIso8601String(),
        'sal': sal,
        'hashContrasena': hashContrasena,
      };

  factory UsuarioCuenta.fromStorageJson(Map<String, dynamic> json) {
    return UsuarioCuenta(
      id: json['id'] as String,
      apodo: json['apodo'] as String,
      email: json['email'] as String,
      fechaRegistro:
          DateTime.tryParse(json['fechaRegistro'] as String? ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      sal: json['sal'] as String,
      hashContrasena: json['hashContrasena'] as String,
    );
  }
}

/// Sesión activa asociada a una cuenta para impedir doble conexión simultánea.
class SesionActivaCuenta {
  final String token;
  final String usuarioId;
  final String? dispositivoId;
  DateTime ultimaActividad;

  SesionActivaCuenta({
    required this.token,
    required this.usuarioId,
    required this.ultimaActividad,
    this.dispositivoId,
  });

  Map<String, dynamic> toStorageJson() => {
        'token': token,
        'usuarioId': usuarioId,
        if (dispositivoId != null) 'dispositivoId': dispositivoId,
        'ultimaActividad': ultimaActividad.toUtc().toIso8601String(),
      };

  factory SesionActivaCuenta.fromStorageJson(Map<String, dynamic> json) {
    return SesionActivaCuenta(
      token: json['token'] as String,
      usuarioId: json['usuarioId'] as String,
      dispositivoId: json['dispositivoId'] as String?,
      ultimaActividad:
          DateTime.tryParse(json['ultimaActividad'] as String? ?? '')
                  ?.toUtc() ??
              DateTime.now().toUtc(),
    );
  }
}

/// Respuesta pública devuelta al cliente tras iniciar sesión o registrarse.
class ResultadoAuthServidor {
  final UsuarioCuenta usuario;
  final String token;

  const ResultadoAuthServidor({
    required this.usuario,
    required this.token,
  });

  Map<String, dynamic> toJson() => {
        'usuario': usuario.toPublicJson(),
        'token': token,
      };
}

/// Gestor autoritativo de cuentas de usuario, sesiones únicas e unicidad global de apodos.
class GestorUsuarios {
  static final RegExp _regexEmail = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final RegExp _regexCaracteresProhibidos = RegExp(
    r'[\x00-\x1F\x7F\u200B-\u200D\uFEFF]',
  );
  static final RegExp _regexAlfanumerico = RegExp(
    r'[a-zA-Z0-9áéíóúÁÉÍÓÚüÜñÑ]',
  );

  final String? _rutaPersistencia;
  final Random _randomSeguro;
  final Duration duracionInactividadSesion;
  bool Function(String apodo)? tieneConexionMultijugadorActiva;

  final Map<String, UsuarioCuenta> _usuariosPorId = {};
  final Map<String, UsuarioCuenta> _usuariosPorApodoClave = {};
  final Map<String, UsuarioCuenta> _usuariosPorEmail = {};
  final Map<String, SesionActivaCuenta> _sesionesPorToken = {};

  GestorUsuarios({
    String? rutaArchivoPersistencia,
    Random? randomSeguro,
    this.duracionInactividadSesion = const Duration(seconds: 75),
    this.tieneConexionMultijugadorActiva,
  })  : _rutaPersistencia = rutaArchivoPersistencia,
        _randomSeguro = randomSeguro ?? _crearRandomSeguro() {
    _cargarDesdeDisco();
  }

  static Random _crearRandomSeguro() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  int get cantidadUsuarios => _usuariosPorId.length;

  /// Registra una cuenta nueva exigiendo apodo y correo únicos en todo el servidor.
  ResultadoAuthServidor registrarUsuario({
    required String apodo,
    required String email,
    required String contrasena,
    String? dispositivoId,
  }) {
    final apodoLimpio = _validarApodo(apodo);
    final apodoClave = normalizarApodoClave(apodoLimpio);
    final emailLimpio = _validarEmail(email);
    _validarContrasena(contrasena, esRegistro: true);

    if (_usuariosPorApodoClave.containsKey(apodoClave)) {
      throw FalloAutenticacionServidor(
        statusCode: HttpStatus.conflict,
        codigo: 'APODO_EN_USO',
        mensaje:
            'El apodo "$apodoLimpio" ya está registrado. Elige otro nombre.',
      );
    }

    if (_usuariosPorEmail.containsKey(emailLimpio)) {
      throw const FalloAutenticacionServidor(
        statusCode: HttpStatus.conflict,
        codigo: 'EMAIL_EN_USO',
        mensaje: 'El correo electrónico ya está registrado.',
      );
    }

    final sal = _generarHexAleatorio(16);
    final hash = _hashearContrasena(contrasena, sal);
    final nuevoId = 'usr_${_generarHexAleatorio(12)}';

    final usuario = UsuarioCuenta(
      id: nuevoId,
      apodo: apodoLimpio,
      email: emailLimpio,
      fechaRegistro: DateTime.now().toUtc(),
      sal: sal,
      hashContrasena: hash,
    );

    _usuariosPorId[nuevoId] = usuario;
    _usuariosPorApodoClave[apodoClave] = usuario;
    _usuariosPorEmail[emailLimpio] = usuario;

    final token = _crearSesionUnicaPara(
      nuevoId,
      dispositivoId: dispositivoId?.trim(),
    );
    _guardarEnDisco();

    return ResultadoAuthServidor(usuario: usuario, token: token);
  }

  /// Inicia sesión usando correo electrónico o apodo único y bloquea el acceso si la
  /// cuenta ya está conectada activamente en otro dispositivo.
  ResultadoAuthServidor iniciarSesion({
    required String identificador,
    required String contrasena,
    String? dispositivoId,
  }) {
    final limpio = identificador.trim();
    if (limpio.isEmpty) {
      throw const FalloAutenticacionServidor(
        statusCode: HttpStatus.badRequest,
        codigo: 'DATOS_INVALIDOS',
        mensaje: 'Ingresa tu usuario o correo electrónico.',
      );
    }

    if (limpio.contains('@')) {
      if (RegExp(r'\s').hasMatch(limpio)) {
        throw const FalloAutenticacionServidor(
          statusCode: HttpStatus.badRequest,
          codigo: 'DATOS_INVALIDOS',
          mensaje: 'El correo electrónico no puede contener espacios.',
        );
      }
      if (!_regexEmail.hasMatch(limpio.toLowerCase())) {
        throw const FalloAutenticacionServidor(
          statusCode: HttpStatus.badRequest,
          codigo: 'DATOS_INVALIDOS',
          mensaje: 'Ingresa un correo electrónico válido.',
        );
      }
    } else if (RegExp(r'\s{2,}').hasMatch(limpio)) {
      throw const FalloAutenticacionServidor(
        statusCode: HttpStatus.badRequest,
        codigo: 'DATOS_INVALIDOS',
        mensaje: 'El usuario no puede contener espacios consecutivos.',
      );
    }

    _validarContrasena(contrasena, esRegistro: false);

    final UsuarioCuenta? usuario = limpio.contains('@')
        ? _usuariosPorEmail[limpio.toLowerCase()]
        : _usuariosPorApodoClave[normalizarApodoClave(limpio)];

    if (usuario == null) {
      throw const FalloAutenticacionServidor(
        statusCode: HttpStatus.unauthorized,
        codigo: 'CUENTA_NO_ENCONTRADA',
        mensaje: 'No existe ninguna cuenta registrada con esos datos.',
      );
    }

    final hashIngresado = _hashearContrasena(contrasena, usuario.sal);
    if (!_comparacionTiempoConstante(usuario.hashContrasena, hashIngresado)) {
      throw const FalloAutenticacionServidor(
        statusCode: HttpStatus.unauthorized,
        codigo: 'CREDENCIALES_INVALIDAS',
        mensaje: 'Contraseña incorrecta.',
      );
    }

    final dispLimpio =
        (dispositivoId != null && dispositivoId.trim().isNotEmpty)
            ? dispositivoId.trim()
            : null;

    final sesionActiva = _obtenerSesionActivaDeUsuario(usuario);
    if (sesionActiva != null) {
      final esMismoDispositivo = dispLimpio != null &&
          sesionActiva.dispositivoId != null &&
          sesionActiva.dispositivoId == dispLimpio;
      if (!esMismoDispositivo) {
        throw const FalloAutenticacionServidor(
          statusCode: HttpStatus.conflict,
          codigo: 'SESION_YA_ACTIVA',
          mensaje:
              'Esta cuenta ya está conectada en otro dispositivo. Cierra sesión allá antes de entrar.',
        );
      }
    }

    // Si no tenía sesión HTTP pero el apodo está conectado en una sala multijugador activa desde otro cliente
    if (sesionActiva == null &&
        (tieneConexionMultijugadorActiva?.call(usuario.apodo) ?? false)) {
      throw const FalloAutenticacionServidor(
        statusCode: HttpStatus.conflict,
        codigo: 'SESION_YA_ACTIVA',
        mensaje:
            'Esta cuenta ya tiene una partida o sala activa en otro dispositivo.',
      );
    }

    final token = _crearSesionUnicaPara(
      usuario.id,
      dispositivoId: dispLimpio,
    );
    _guardarEnDisco();

    return ResultadoAuthServidor(usuario: usuario, token: token);
  }

  /// Devuelve la cuenta asociada a [token] y renueva su latido de actividad, o `null` si expiró/no existe.
  UsuarioCuenta? obtenerUsuarioPorToken(String token) {
    final limpio = token.trim();
    if (limpio.isEmpty) return null;
    final sesion = _sesionesPorToken[limpio];
    if (sesion == null) return null;

    final usuario = _usuariosPorId[sesion.usuarioId];
    if (usuario == null) {
      _sesionesPorToken.remove(limpio);
      return null;
    }

    if (!_sesionSigueVigente(sesion, usuario)) {
      _sesionesPorToken.remove(limpio);
      _guardarEnDisco();
      return null;
    }

    sesion.ultimaActividad = DateTime.now().toUtc();
    return usuario;
  }

  /// Revoca un token de sesión activo liberando la cuenta de inmediato.
  void cerrarSesion(String token) {
    final limpio = token.trim();
    if (limpio.isEmpty) return;
    if (_sesionesPorToken.remove(limpio) != null) {
      _guardarEnDisco();
    }
  }

  bool _sesionSigueVigente(SesionActivaCuenta sesion, UsuarioCuenta usuario) {
    if (tieneConexionMultijugadorActiva?.call(usuario.apodo) ?? false) {
      return true;
    }
    final transcurrido = DateTime.now().toUtc().difference(sesion.ultimaActividad);
    return transcurrido <= duracionInactividadSesion;
  }

  SesionActivaCuenta? _obtenerSesionActivaDeUsuario(UsuarioCuenta usuario) {
    final tokensExpirados = <String>[];
    SesionActivaCuenta? activa;

    _sesionesPorToken.forEach((token, sesion) {
      if (sesion.usuarioId == usuario.id) {
        if (_sesionSigueVigente(sesion, usuario)) {
          activa = sesion;
        } else {
          tokensExpirados.add(token);
        }
      }
    });

    for (final t in tokensExpirados) {
      _sesionesPorToken.remove(t);
    }
    return activa;
  }

  String _crearSesionUnicaPara(String usuarioId, {String? dispositivoId}) {
    _sesionesPorToken.removeWhere((_, s) => s.usuarioId == usuarioId);
    final token = _generarHexAleatorio(24);
    _sesionesPorToken[token] = SesionActivaCuenta(
      token: token,
      usuarioId: usuarioId,
      dispositivoId:
          (dispositivoId != null && dispositivoId.isNotEmpty) ? dispositivoId : null,
      ultimaActividad: DateTime.now().toUtc(),
    );
    return token;
  }

  String _validarApodo(String rawApodo) {
    final sinExtremos = rawApodo.trim();
    if (sinExtremos.isEmpty) {
      throw const FalloAutenticacionServidor(
        statusCode: HttpStatus.badRequest,
        codigo: 'APODO_INVALIDO',
        mensaje: 'Ingresa un apodo o nombre de jugador.',
      );
    }
    if (_regexCaracteresProhibidos.hasMatch(sinExtremos)) {
      throw const FalloAutenticacionServidor(
        statusCode: HttpStatus.badRequest,
        codigo: 'APODO_INVALIDO',
        mensaje: 'El apodo contiene caracteres no permitidos.',
      );
    }
    if (RegExp(r'\s{2,}').hasMatch(sinExtremos)) {
      throw const FalloAutenticacionServidor(
        statusCode: HttpStatus.badRequest,
        codigo: 'APODO_INVALIDO',
        mensaje: 'El apodo no puede contener espacios consecutivos.',
      );
    }
    if (sinExtremos.contains('@')) {
      throw const FalloAutenticacionServidor(
        statusCode: HttpStatus.badRequest,
        codigo: 'APODO_INVALIDO',
        mensaje: 'El apodo no puede contener el símbolo @.',
      );
    }
    if (sinExtremos.length < ConstantesServidor.minLongitudApodo ||
        sinExtremos.length > ConstantesServidor.maxLongitudApodo) {
      throw const FalloAutenticacionServidor(
        statusCode: HttpStatus.badRequest,
        codigo: 'APODO_INVALIDO',
        mensaje: 'El apodo debe contener entre 2 y 18 caracteres.',
      );
    }
    if (!_regexAlfanumerico.hasMatch(sinExtremos)) {
      throw const FalloAutenticacionServidor(
        statusCode: HttpStatus.badRequest,
        codigo: 'APODO_INVALIDO',
        mensaje: 'El apodo debe incluir al menos una letra o número.',
      );
    }
    return sinExtremos;
  }

  String _validarEmail(String rawEmail) {
    final limpio = rawEmail.trim().toLowerCase();
    if (limpio.isEmpty) {
      throw const FalloAutenticacionServidor(
        statusCode: HttpStatus.badRequest,
        codigo: 'EMAIL_INVALIDO',
        mensaje: 'Ingresa un correo electrónico.',
      );
    }
    if (RegExp(r'\s').hasMatch(limpio)) {
      throw const FalloAutenticacionServidor(
        statusCode: HttpStatus.badRequest,
        codigo: 'EMAIL_INVALIDO',
        mensaje: 'El correo electrónico no puede contener espacios.',
      );
    }
    if (!_regexEmail.hasMatch(limpio)) {
      throw const FalloAutenticacionServidor(
        statusCode: HttpStatus.badRequest,
        codigo: 'EMAIL_INVALIDO',
        mensaje: 'Ingresa un correo electrónico válido.',
      );
    }
    return limpio;
  }

  void _validarContrasena(String contrasena, {required bool esRegistro}) {
    if (contrasena.isEmpty) {
      throw FalloAutenticacionServidor(
        statusCode: HttpStatus.badRequest,
        codigo: 'CONTRASENA_INVALIDA',
        mensaje: esRegistro
            ? 'Ingresa una contraseña.'
            : 'Ingresa tu contraseña.',
      );
    }
    if (RegExp(r'\s').hasMatch(contrasena)) {
      throw const FalloAutenticacionServidor(
        statusCode: HttpStatus.badRequest,
        codigo: 'CONTRASENA_INVALIDA',
        mensaje: 'La contraseña no puede contener espacios.',
      );
    }
    if (contrasena.length < 6) {
      throw const FalloAutenticacionServidor(
        statusCode: HttpStatus.badRequest,
        codigo: 'CONTRASENA_INVALIDA',
        mensaje: 'La contraseña debe tener al menos 6 caracteres.',
      );
    }
  }

  String _hashearContrasena(String contrasena, String sal) {
    final bytes = utf8.encode('brilliant_srv_2026:$sal:$contrasena');
    return sha256.convert(bytes).toString();
  }

  bool _comparacionTiempoConstante(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  String _generarHexAleatorio(int bytes) {
    final buffer = StringBuffer();
    for (int i = 0; i < bytes; i++) {
      buffer.write(_randomSeguro.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  void _cargarDesdeDisco() {
    final ruta = _rutaPersistencia;
    if (ruta == null || ruta.trim().isEmpty) return;

    try {
      final file = File(ruta);
      if (!file.existsSync()) return;
      final contenido = file.readAsStringSync();
      if (contenido.trim().isEmpty) return;

      final decoded = jsonDecode(contenido);
      if (decoded is! Map<String, dynamic>) return;

      final usuariosJson = decoded['usuarios'];
      if (usuariosJson is List) {
        for (final item in usuariosJson) {
          if (item is Map<String, dynamic>) {
            final usuario = UsuarioCuenta.fromStorageJson(item);
            _usuariosPorId[usuario.id] = usuario;
            _usuariosPorApodoClave[normalizarApodoClave(usuario.apodo)] =
                usuario;
            _usuariosPorEmail[usuario.email.toLowerCase()] = usuario;
          }
        }
      }

      final sesionesDetalladas = decoded['sesionesActivas'];
      if (sesionesDetalladas is List) {
        for (final item in sesionesDetalladas) {
          if (item is Map<String, dynamic>) {
            final sesion = SesionActivaCuenta.fromStorageJson(item);
            if (_usuariosPorId.containsKey(sesion.usuarioId)) {
              _sesionesPorToken[sesion.token] = sesion;
            }
          }
        }
      } else {
        final sesionesLegado = decoded['sesiones'];
        if (sesionesLegado is Map<String, dynamic>) {
          sesionesLegado.forEach((token, uid) {
            if (uid is String && _usuariosPorId.containsKey(uid)) {
              _sesionesPorToken[token] = SesionActivaCuenta(
                token: token,
                usuarioId: uid,
                ultimaActividad: DateTime.now().toUtc(),
              );
            }
          });
        }
      }
    } catch (_) {
      // Si el archivo inicial no puede leerse o está corrupto, inicia limpio sin detener el servidor.
    }
  }

  void _guardarEnDisco() {
    final ruta = _rutaPersistencia;
    if (ruta == null || ruta.trim().isEmpty) return;

    try {
      final file = File(ruta);
      final dir = file.parent;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final datos = jsonEncode({
        'usuarios': _usuariosPorId.values.map((u) => u.toStorageJson()).toList(),
        'sesionesActivas':
            _sesionesPorToken.values.map((s) => s.toStorageJson()).toList(),
      });
      final temporal = File('$ruta.tmp');
      temporal.writeAsStringSync(datos, flush: true);
      temporal.renameSync(ruta);
    } catch (_) {
      // En sistemas sin disco persistente escribible, el estado permanece operativo en memoria.
    }
  }
}
