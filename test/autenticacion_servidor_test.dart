import 'dart:convert';
import 'dart:io';

import 'package:servidor_brilliant/servidor/gestor_usuarios.dart';
import 'package:servidor_brilliant/servidor/servidor_websocket_brilliant.dart';
import 'package:test/test.dart';

Future<(int, Map<String, dynamic>)> _peticionJson({
  required String metodo,
  required Uri uri,
  Map<String, dynamic>? body,
  String? bearerToken,
}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(metodo, uri);
    req.headers.contentType = ContentType.json;
    if (bearerToken != null) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
    }
    if (body != null) {
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final texto = await utf8.decodeStream(res);
    final decoded = jsonDecode(texto) as Map<String, dynamic>;
    return (res.statusCode, decoded);
  } finally {
    client.close(force: true);
  }
}

void main() {
  group('GestorUsuarios y unicidad global de apodos', () {
    test('Impide registrar dos usuarios con el mismo apodo (mayúsculas, espacios o acentos)', () {
      final gestor = GestorUsuarios();

      final primero = gestor.registrarUsuario(
        apodo: 'Fabian',
        email: 'fabian1@correo.com',
        contrasena: 'clave_segura1',
      );
      expect(primero.usuario.apodo, 'Fabian');
      expect(primero.token, isNotEmpty);

      // Mismo apodo exacto con distinto correo -> rechazado
      expect(
        () => gestor.registrarUsuario(
          apodo: 'Fabian',
          email: 'fabian2@correo.com',
          contrasena: 'clave_segura2',
        ),
        throwsA(
          predicate<FalloAutenticacionServidor>(
            (e) => e.codigo == 'APODO_EN_USO' && e.statusCode == 409,
          ),
        ),
      );

      // Minúsculas / mayúsculas -> rechazado
      expect(
        () => gestor.registrarUsuario(
          apodo: 'fAbIaN',
          email: 'fabian3@correo.com',
          contrasena: 'clave_segura3',
        ),
        throwsA(
          predicate<FalloAutenticacionServidor>((e) => e.codigo == 'APODO_EN_USO'),
        ),
      );

      // Acento equivalente -> rechazado
      expect(
        () => gestor.registrarUsuario(
          apodo: 'Fabián',
          email: 'fabian4@correo.com',
          contrasena: 'clave_segura4',
        ),
        throwsA(
          predicate<FalloAutenticacionServidor>((e) => e.codigo == 'APODO_EN_USO'),
        ),
      );

      // Espacios exteriores -> rechazado
      expect(
        () => gestor.registrarUsuario(
          apodo: '  fabian  ',
          email: 'fabian5@correo.com',
          contrasena: 'clave_segura5',
        ),
        throwsA(
          predicate<FalloAutenticacionServidor>((e) => e.codigo == 'APODO_EN_USO'),
        ),
      );

      // Correo repetido con distinto apodo -> rechazado
      expect(
        () => gestor.registrarUsuario(
          apodo: 'OtroJugador',
          email: 'FABIAN1@CORREO.COM',
          contrasena: 'clave_segura6',
        ),
        throwsA(
          predicate<FalloAutenticacionServidor>(
            (e) => e.codigo == 'EMAIL_EN_USO' && e.statusCode == 409,
          ),
        ),
      );
    });

    test('Persiste cuentas y tokens en archivo JSON y permite login tras recargar', () {
      final dirTemp = Directory.systemTemp.createTempSync('brilliant_auth_');
      addTearDown(() => dirTemp.deleteSync(recursive: true));
      final archivo = '${dirTemp.path}${Platform.pathSeparator}usuarios.json';

      final gestor1 = GestorUsuarios(rutaArchivoPersistencia: archivo);
      final reg = gestor1.registrarUsuario(
        apodo: 'CarlosPro',
        email: 'carlos@correo.com',
        contrasena: 'miPassword1',
      );

      // Nuevo gestor leyendo del mismo archivo
      final gestor2 = GestorUsuarios(rutaArchivoPersistencia: archivo);
      expect(gestor2.cantidadUsuarios, 1);

      final desdeToken = gestor2.obtenerUsuarioPorToken(reg.token);
      expect(desdeToken?.apodo, 'CarlosPro');

      // Otro usuario intenta tomar el mismo apodo tras recarga -> bloqueado
      expect(
        () => gestor2.registrarUsuario(
          apodo: 'carlospro',
          email: 'otro@correo.com',
          contrasena: 'miPassword2',
        ),
        throwsA(
          predicate<FalloAutenticacionServidor>((e) => e.codigo == 'APODO_EN_USO'),
        ),
      );

      // Login con apodo (sin distinción de mayúsculas) funciona
      final login = gestor2.iniciarSesion(
        identificador: 'CARLOSPRO',
        contrasena: 'miPassword1',
      );
      expect(login.usuario.email, 'carlos@correo.com');
    });

    test('Endpoints HTTP /auth/registro, /auth/login, /auth/sesion y /auth/logout end-to-end', () async {
      final servidor = ServidorWebsocketBrilliant(persistirUsuarios: false);
      final puerto = await servidor.iniciar(
        direccion: InternetAddress.loopbackIPv4,
        puerto: 0,
      );
      addTearDown(servidor.detener);

      final base = 'http://127.0.0.1:$puerto';

      // 1. Registro del primer dispositivo (PC)
      final (statusReg1, bodyReg1) = await _peticionJson(
        metodo: 'POST',
        uri: Uri.parse('$base/auth/registro'),
        body: {
          'apodo': 'JugadorUnico',
          'email': 'pc@correo.com',
          'contrasena': 'clavePC123',
        },
      );
      expect(statusReg1, HttpStatus.created);
      expect((bodyReg1['usuario'] as Map)['apodo'], 'JugadorUnico');
      final token = bodyReg1['token'] as String;
      expect(token, isNotEmpty);

      // 2. Segundo dispositivo (Celular) intenta registrarse con el mismo apodo -> 409
      final (statusDup, bodyDup) = await _peticionJson(
        metodo: 'POST',
        uri: Uri.parse('$base/auth/registro'),
        body: {
          'apodo': 'jugadorunico',
          'email': 'cel@correo.com',
          'contrasena': 'claveCel123',
        },
      );
      expect(statusDup, HttpStatus.conflict);
      expect(bodyDup['codigo'], 'APODO_EN_USO');

      // 3. Validar sesión con token
      final (statusSes, bodySes) = await _peticionJson(
        metodo: 'GET',
        uri: Uri.parse('$base/auth/sesion'),
        bearerToken: token,
      );
      expect(statusSes, HttpStatus.ok);
      expect((bodySes['usuario'] as Map)['apodo'], 'JugadorUnico');

      // 4. Contraseña incorrecta -> 401
      final (statusMalPass, _) = await _peticionJson(
        metodo: 'POST',
        uri: Uri.parse('$base/auth/login'),
        body: {
          'identificador': 'JugadorUnico',
          'contrasena': 'incorrecta',
        },
      );
      expect(statusMalPass, HttpStatus.unauthorized);

      // 5. Logout revoca el token
      final (statusOut, _) = await _peticionJson(
        metodo: 'POST',
        uri: Uri.parse('$base/auth/logout'),
        bearerToken: token,
      );
      expect(statusOut, HttpStatus.ok);

      final (statusSesPostOut, _) = await _peticionJson(
        metodo: 'GET',
        uri: Uri.parse('$base/auth/sesion'),
        bearerToken: token,
      );
      expect(statusSesPostOut, HttpStatus.unauthorized);
    });
  });
}
