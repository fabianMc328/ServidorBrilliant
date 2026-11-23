import 'package:test/test.dart';

import 'autenticacion_servidor_test.dart' as autenticacion_servidor_test;
import 'dominio_servidor_test.dart' as dominio_servidor_test;
import 'servidor_websocket_test.dart' as servidor_websocket_test;

void main() {
  group('Suite Completa - servidorBrilliant', () {
    autenticacion_servidor_test.main();
    dominio_servidor_test.main();
    servidor_websocket_test.main();
  });
}
