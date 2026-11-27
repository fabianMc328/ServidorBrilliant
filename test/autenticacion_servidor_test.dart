import 'dart:convert';
import 'dart:io';

import 'package:servidor_brilliant/dominio/estados_sala.dart';
import 'package:servidor_brilliant/servidor/gestor_salas.dart';
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
  group('GestorUsuarios, sesión única y unicidad global de apodos', () {
    test('Impide registrar dos usuarios con el mismo apodo (mayúsculas, espacios o acentos)', () {
      final gestor = GestorUsuarios();

      final primero = gestor.registrarUsuario(
        apodo: 'Fabian',
        email: 'fabian1@correo.com',
        contrasena: 'clave_segura1',
        dispositivoId: 'disp_pc',
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

    test('Bloquea iniciar sesión desde otro dispositivo si la cuenta ya está conectada', () async {
      final gestor = GestorUsuarios(
        duracionInactividadSesion: const Duration(milliseconds: 120),
      );

      final sesionCelular = gestor.registrarUsuario(
        apodo: 'Fabian',
        email: 'fabian@correo.com',
        contrasena: 'miPassword1',
        dispositivoId: 'disp_celular',
      );

      // Intento de entrar desde PC/Web mientras el celular tiene sesión activa -> bloqueado (409 SESION_YA_ACTIVA)
      expect(
        () => gestor.iniciarSesion(
          identificador: 'Fabian',
          contrasena: 'miPassword1',
          dispositivoId: 'disp_web',
        ),
        throwsA(
          predicate<FalloAutenticacionServidor>(
            (e) => e.codigo == 'SESION_YA_ACTIVA' && e.statusCode == 409,
          ),
        ),
      );

      // El MISMO dispositivo (ej. recarga en el mismo celular) sí puede renovar su propia sesión
      final renovada = gestor.iniciarSesion(
        identificador: 'Fabian',
        contrasena: 'miPassword1',
        dispositivoId: 'disp_celular',
      );
      expect(renovada.usuario.apodo, 'Fabian');

      // Al cerrar sesión en el celular, ahora la Web/PC puede entrar de inmediato
      gestor.cerrarSesion(renovada.token);
      final sesionWeb = gestor.iniciarSesion(
        identificador: 'fabian@correo.com',
        contrasena: 'miPassword1',
        dispositivoId: 'disp_web',
      );
      expect(sesionWeb.token, isNot(sesionCelular.token));

      // Si la Web deja de enviar latido y expira el tiempo de inactividad, otro dispositivo puede entrar
      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(gestor.obtenerUsuarioPorToken(sesionWeb.token), isNull);

      final trasExpiracion = gestor.iniciarSesion(
        identificador: 'Fabian',
        contrasena: 'miPassword1',
        dispositivoId: 'disp_otro',
      );
      expect(trasExpiracion.usuario.apodo, 'Fabian');
    });

    test('Persiste cuentas y tokens en archivo JSON y bloquea doble conexión tras recargar', () {
      final dirTemp = Directory.systemTemp.createTempSync('brilliant_auth_');
      addTearDown(() => dirTemp.deleteSync(recursive: true));
      final archivo = '${dirTemp.path}${Platform.pathSeparator}usuarios.json';

      final gestor1 = GestorUsuarios(rutaArchivoPersistencia: archivo);
      final reg = gestor1.registrarUsuario(
        apodo: 'CarlosPro',
        email: 'carlos@correo.com',
        contrasena: 'miPassword1',
        dispositivoId: 'disp_1',
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

      // Otro dispositivo intenta iniciar sesión mientras disp_1 sigue activo -> bloqueado
      expect(
        () => gestor2.iniciarSesion(
          identificador: 'CARLOSPRO',
          contrasena: 'miPassword1',
          dispositivoId: 'disp_2',
        ),
        throwsA(
          predicate<FalloAutenticacionServidor>(
            (e) => e.codigo == 'SESION_YA_ACTIVA',
          ),
        ),
      );

      // Tras cerrar sesión en disp_1, disp_2 puede iniciar sesión
      gestor2.cerrarSesion(reg.token);
      final login = gestor2.iniciarSesion(
        identificador: 'CARLOSPRO',
        contrasena: 'miPassword1',
        dispositivoId: 'disp_2',
      );
      expect(login.usuario.email, 'carlos@correo.com');
    });

    test('GestorSalas impide que una misma cuenta cree o se una a otra sala mientras ya está conectada', () {
      final gestorSalas = GestorSalas(
        enviarEventoAJugador: (_, __) {},
      );
      addTearDown(gestorSalas.cerrar);

      final cred1 = gestorSalas.crearSala(apodo: 'Fabian');
      expect(gestorSalas.tieneJugadorConectadoConApodo('fabian'), isTrue);

      // No puede crear una segunda sala con la misma cuenta activa
      expect(
        () => gestorSalas.crearSala(apodo: 'FABIAN'),
        throwsA(
          predicate<FalloMultijugador>(
            (f) => f.codigo == CodigoFalloMultijugador.apodoEnUso,
          ),
        ),
      );

      // Tampoco puede unirse a otra sala mientras sigue en la primera
      final credOtraSala = gestorSalas.crearSala(apodo: 'Anfitrion2');
      expect(
        () => gestorSalas.unirseASala(
          codigoSala: credOtraSala.codigoSala,
          apodo: 'Fabián',
        ),
        throwsA(
          predicate<FalloMultijugador>(
            (f) => f.codigo == CodigoFalloMultijugador.apodoEnUso,
          ),
        ),
      );

      // Al salir de la primera sala, queda libre para unirse a la segunda
      gestorSalas.salirDeSala(jugadorId: cred1.jugadorId);
      expect(gestorSalas.tieneJugadorConectadoConApodo('Fabian'), isFalse);

      final unido = gestorSalas.unirseASala(
        codigoSala: credOtraSala.codigoSala,
        apodo: 'Fabian',
      );
      expect(unido.apodo, 'Fabian');

      // Si recarga la página (F5) y su socket anterior queda en 'reconectando',
      // puede volver a unirse a la misma sala de inmediato sin esperar 30 segundos
      gestorSalas.notificarDesconexionAbrupta(unido.jugadorId);
      final reingresoInmediato = gestorSalas.unirseASala(
        codigoSala: credOtraSala.codigoSala,
        apodo: 'Fabian',
      );
      expect(reingresoInmediato.apodo, 'Fabian');
    });

    test('Endpoints HTTP /auth/registro, /auth/login (bloqueo doble sesión), /auth/sesion y /auth/logout end-to-end', () async {
      final servidor = ServidorWebsocketBrilliant(persistirUsuarios: false);
      final puerto = await servidor.iniciar(
        direccion: InternetAddress.loopbackIPv4,
        puerto: 0,
      );
      addTearDown(servidor.detener);

      final base = 'http://127.0.0.1:$puerto';

      // 1. Registro del primer dispositivo (Celular)
      final (statusReg1, bodyReg1) = await _peticionJson(
        metodo: 'POST',
        uri: Uri.parse('$base/auth/registro'),
        body: {
          'apodo': 'JugadorUnico',
          'email': 'cel@correo.com',
          'contrasena': 'claveCel123',
          'dispositivoId': 'disp_celular_1',
        },
      );
      expect(statusReg1, HttpStatus.created);
      expect((bodyReg1['usuario'] as Map)['apodo'], 'JugadorUnico');
      final token = bodyReg1['token'] as String;
      expect(token, isNotEmpty);

      // 2. Segundo dispositivo (Web) intenta registrarse con el mismo apodo -> 409 APODO_EN_USO
      final (statusDup, bodyDup) = await _peticionJson(
        metodo: 'POST',
        uri: Uri.parse('$base/auth/registro'),
        body: {
          'apodo': 'jugadorunico',
          'email': 'web@correo.com',
          'contrasena': 'claveWeb123',
          'dispositivoId': 'disp_web_2',
        },
      );
      expect(statusDup, HttpStatus.conflict);
      expect(bodyDup['codigo'], 'APODO_EN_USO');

      // 3. Segundo dispositivo (Web) intenta hacer LOGIN con esa cuenta ya conectada -> 409 SESION_YA_ACTIVA
      final (statusDobleLogin, bodyDobleLogin) = await _peticionJson(
        metodo: 'POST',
        uri: Uri.parse('$base/auth/login'),
        body: {
          'identificador': 'JugadorUnico',
          'contrasena': 'claveCel123',
          'dispositivoId': 'disp_web_2',
        },
      );
      expect(statusDobleLogin, HttpStatus.conflict);
      expect(bodyDobleLogin['codigo'], 'SESION_YA_ACTIVA');

      // 4. Validar sesión con token activo del celular
      final (statusSes, bodySes) = await _peticionJson(
        metodo: 'GET',
        uri: Uri.parse('$base/auth/sesion?dispositivoId=disp_celular_1'),
        bearerToken: token,
      );
      expect(statusSes, HttpStatus.ok);
      expect((bodySes['usuario'] as Map)['apodo'], 'JugadorUnico');

      // 4b. Si otra pestaña/dispositivo intenta reutilizar el mismo token -> 409 SESION_YA_ACTIVA
      final (statusOtraPestana, bodyOtraPestana) = await _peticionJson(
        metodo: 'GET',
        uri: Uri.parse('$base/auth/sesion?dispositivoId=disp_pestana_2'),
        bearerToken: token,
      );
      expect(statusOtraPestana, HttpStatus.conflict);
      expect(bodyOtraPestana['codigo'], 'SESION_YA_ACTIVA');

      // 5. Contraseña incorrecta -> 401
      final (statusMalPass, _) = await _peticionJson(
        metodo: 'POST',
        uri: Uri.parse('$base/auth/login'),
        body: {
          'identificador': 'JugadorUnico',
          'contrasena': 'incorrecta',
          'dispositivoId': 'disp_celular_1',
        },
      );
      expect(statusMalPass, HttpStatus.unauthorized);

      // 6. Logout en celular libera la cuenta para que Web ahora sí pueda entrar
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

      final (statusLoginWeb, bodyLoginWeb) = await _peticionJson(
        metodo: 'POST',
        uri: Uri.parse('$base/auth/login'),
        body: {
          'identificador': 'JugadorUnico',
          'contrasena': 'claveCel123',
          'dispositivoId': 'disp_web_2',
        },
      );
      expect(statusLoginWeb, HttpStatus.ok);
      expect((bodyLoginWeb['usuario'] as Map)['apodo'], 'JugadorUnico');
    });

    test('Rankings Multijugador/Solitario y restauración híbrida completa tras reinicio del servidor', () async {
      final servidor1 = ServidorWebsocketBrilliant(persistirUsuarios: false);
      final puerto1 = await servidor1.iniciar(
        direccion: InternetAddress.loopbackIPv4,
        puerto: 0,
      );
      addTearDown(servidor1.detener);
      final base1 = 'http://127.0.0.1:$puerto1';

      // Registrar a Fabian y Carlos
      final (_, regFabian) = await _peticionJson(
        metodo: 'POST',
        uri: Uri.parse('$base1/auth/registro'),
        body: {
          'apodo': 'Fabian',
          'email': 'fabian@gmail.com',
          'contrasena': 'clave123',
          'dispositivoId': 'disp_f',
        },
      );
      final tokenFabian = regFabian['token'] as String;

      final (_, regCarlos) = await _peticionJson(
        metodo: 'POST',
        uri: Uri.parse('$base1/auth/registro'),
        body: {
          'apodo': 'Carlos',
          'email': 'carlos@gmail.com',
          'contrasena': 'clave123',
          'dispositivoId': 'disp_c',
        },
      );
      final tokenCarlos = regCarlos['token'] as String;

      // Terminar partida multijugador: Fabian gana con 26 pts, Carlos hace 19 pts
      servidor1.gestorUsuarios.registrarResultadoPartidaSala(const [
        ResultadoJugadorRankingSala(
          apodo: 'Fabian',
          puntuacion: 26,
          esGanador: true,
        ),
        ResultadoJugadorRankingSala(
          apodo: 'Carlos',
          puntuacion: 19,
          esGanador: false,
        ),
      ]);

      // Carlos registra récord de 34 pts en Modo Solitario
      final (statusSol, _) = await _peticionJson(
        metodo: 'POST',
        uri: Uri.parse('$base1/rankings/solitario'),
        bearerToken: tokenCarlos,
        body: {'apodo': 'Carlos', 'puntaje': 34},
      );
      expect(statusSol, HttpStatus.ok);

      // Consultar GET /rankings
      final (statusRank, bodyRank) = await _peticionJson(
        metodo: 'GET',
        uri: Uri.parse('$base1/rankings'),
      );
      expect(statusRank, HttpStatus.ok);
      final topMulti = bodyRank['multijugador'] as List;
      final topSol = bodyRank['solitario'] as List;
      expect((topMulti.first as Map)['apodo'], 'Fabian');
      expect((topMulti.first as Map)['victoriasMulti'], 1);
      expect((topMulti.first as Map)['mejorPuntajeMulti'], 26);
      expect((topSol.first as Map)['apodo'], 'Carlos');
      expect((topSol.first as Map)['mejorPuntajeSolitario'], 34);

      final respaldoCliente = bodyRank['respaldoCuentas'] as List;
      expect(respaldoCliente.length, 2);

      // Simular que Render Free se durmió y levantó un contenedor nuevo en 0 usuarios
      final servidor2 = ServidorWebsocketBrilliant(persistirUsuarios: false);
      final puerto2 = await servidor2.iniciar(
        direccion: InternetAddress.loopbackIPv4,
        puerto: 0,
      );
      addTearDown(servidor2.detener);
      final base2 = 'http://127.0.0.1:$puerto2';
      expect(servidor2.gestorUsuarios.cantidadUsuarios, 0);

      // El cliente sincroniza su respaldo de SharedPreferences al servidor recién despierto
      final (statusSync, bodySync) = await _peticionJson(
        metodo: 'POST',
        uri: Uri.parse('$base2/rankings/sincronizar'),
        body: {
          'cuentas': respaldoCliente,
          'sesionActiva': {
            'token': tokenFabian,
            'apodo': 'Fabian',
            'dispositivoId': 'disp_f',
          },
        },
      );
      expect(statusSync, HttpStatus.ok);
      expect(servidor2.gestorUsuarios.cantidadUsuarios, 2);

      // Las cuentas, sesiones y rankings siguen intactos tras el reinicio
      final multiRestaurado = bodySync['multijugador'] as List;
      final solRestaurado = bodySync['solitario'] as List;
      expect((multiRestaurado.first as Map)['apodo'], 'Fabian');
      expect((multiRestaurado.first as Map)['victoriasMulti'], 1);
      expect((solRestaurado.first as Map)['apodo'], 'Carlos');
      expect((solRestaurado.first as Map)['mejorPuntajeSolitario'], 34);

      final (statusSesionRestaurada, _) = await _peticionJson(
        metodo: 'GET',
        uri: Uri.parse('$base2/auth/sesion?dispositivoId=disp_f'),
        bearerToken: tokenFabian,
      );
      expect(statusSesionRestaurada, HttpStatus.ok);
    });
  });
}
