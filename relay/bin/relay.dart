import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:boardhop_relay/src/capture.dart';
import 'package:boardhop_relay/src/db.dart';
import 'package:boardhop_relay/src/log.dart';
import 'package:boardhop_relay/src/server.dart';

Future<void> main(List<String> args) async {
  final port = int.tryParse(env('RELAY_PORT', '8080')) ?? 8080;
  final version = env('RELAY_VERSION', '0.0.1');
  final secret = env('RELAY_CAPTURE_SECRET', '');
  final captureDir = Directory(env('RELAY_CAPTURE_DIR', '/data/capture'))..createSync(recursive: true);

  final db = RelayDb.open(env('RELAY_DB', '/data/relay.sqlite'));

  if (secret.isEmpty) {
    // Not fatal: /healthz stays up so the failure is visible, but every
    // capture request answers 401 until RELAY_CAPTURE_SECRET is set.
    logEvent('RELAY_CAPTURE_SECRET is not set; capture endpoints will reject every request', level: 'warn');
  }

  final server = RelayServer(
    version: version,
    captureSecret: secret,
    captures: CaptureStore(captureDir),
    dbStatus: db == null ? 'error' : 'ok',
  );

  final http = await shelf_io.serve(server.handler, InternetAddress.anyIPv4, port, shared: false);
  http.autoCompress = true;
  logEvent(
    'relay listening',
    fields: {
      'port': http.port,
      'version': version,
      'captureDir': captureDir.path,
      'db': db == null ? 'error' : db.path,
      'sqlite': db?.sqliteVersion,
    },
  );

  Future<void> shutdown(ProcessSignal signal) async {
    logEvent('shutting down', fields: {'signal': signal.toString()});
    await http.close(force: true);
    db?.close();
    exit(0);
  }

  // SIGTERM is what `docker stop` sends; it does not exist on Windows.
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(shutdown);
  ProcessSignal.sigint.watch().listen(shutdown);
}
