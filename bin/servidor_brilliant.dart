import 'dart:io';

import 'package:servidor_brilliant/constantes_servidor.dart';
import 'package:servidor_brilliant/servidor/servidor_websocket_brilliant.dart';

/// Ejecutable CLI para levantar el servidor multijugador independiente de Brilliant.
/// Uso: dart run bin/servidor_brilliant.dart [puerto]
Future<void> main(List<String> args) async {
  int puerto = ConstantesServidor.puertoPorDefecto;
  if (args.isNotEmpty) {
    final parseado = int.tryParse(args.first);
    if (parseado != null && parseado >= 0 && parseado <= 65535) {
      puerto = parseado;
    }
  }

  final servidor = ServidorWebsocketBrilliant();
  final puertoActivo = await servidor.iniciar(puerto: puerto);

  stdout.writeln('=====================================================');
  stdout.writeln(' Servidor Multijugador Brilliant ACTIVO (2-6 jug.)');
  stdout.writeln('=====================================================');
  stdout.writeln(' -> Local / Web / Desktop : ws://localhost:$puertoActivo');
  stdout.writeln(' -> Emulador Android      : ws://10.0.2.2:$puertoActivo');
  stdout.writeln(' -> Healthcheck HTTP      : http://localhost:$puertoActivo/salud');

  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        stdout.writeln(
          ' -> Red Local (${iface.name}) : ws://${addr.address}:$puertoActivo',
        );
      }
    }
  } catch (_) {}

  stdout.writeln('-----------------------------------------------------');
  stdout.writeln(' Presiona Ctrl+C para detener el servidor.');

  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('\nDeteniendo servidor...');
    await servidor.detener();
    exit(0);
  });
}
