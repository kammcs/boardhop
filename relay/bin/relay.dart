import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:boardhop_relay/src/capture.dart';
import 'package:boardhop_relay/src/db.dart';
import 'package:boardhop_relay/src/gateway/gateway.dart';
import 'package:boardhop_relay/src/hooks/hook_event.dart';
import 'package:boardhop_relay/src/hooks/hook_queue.dart';
import 'package:boardhop_relay/src/hooks/ingest.dart';
import 'package:boardhop_relay/src/identity.dart';
import 'package:boardhop_relay/src/log.dart';
import 'package:boardhop_relay/src/registration.dart';
import 'package:boardhop_relay/src/routing/prefs.dart';
import 'package:boardhop_relay/src/routing/routing_state.dart';
import 'package:boardhop_relay/src/routing/rule_engine.dart';
import 'package:boardhop_relay/src/routing/send_ledger.dart';
import 'package:boardhop_relay/src/routing/sink.dart';
import 'package:boardhop_relay/src/server.dart';

Future<void> main(List<String> args) async {
  final port = int.tryParse(env('RELAY_PORT', '8080')) ?? 8080;
  final version = env('RELAY_VERSION', '0.0.1');
  final secret = env('RELAY_CAPTURE_SECRET', '');
  final adminSecret = env('RELAY_ADMIN_SECRET', '');
  final captureDir = Directory(env('RELAY_CAPTURE_DIR', '/data/capture'))..createSync(recursive: true);

  final db = RelayDb.open(env('RELAY_DB', '/data/relay.sqlite'));

  if (secret.isEmpty) {
    // Not fatal: /healthz stays up so the failure is visible, but every
    // capture request answers 401 until RELAY_CAPTURE_SECRET is set.
    logEvent('RELAY_CAPTURE_SECRET is not set; capture endpoints will reject every request', level: 'warn');
  }
  if (adminSecret.isEmpty) {
    logEvent('RELAY_ADMIN_SECRET is not set; /v1/admin/* answers 404', level: 'warn');
  }

  final gateway = PushGateway.fromEnv(env, db: db);
  // One line each at startup, so a missing key is obvious in the log as well
  // as in /healthz.
  logEvent('push gateway', fields: {'apns': gateway.apns.status, 'fcm': gateway.fcm.status});

  // The ingest hand-off: `POST /hooks/{org}` validates and enqueues, and this
  // one consumer does the work — the R2.2 audience engine (research/14 §2).
  // Without a database there is no routing state and no send ledger, so the
  // relay falls back to the R2.1 logging processor and says so.
  final HookProcessor processor = db == null
      ? const LoggingHookProcessor()
      : RuleEngine(
          state: DbRoutingState(db),
          prefs: const DefaultPrefsSource(),
          // R2.3 puts the push gateway behind this interface.
          sink: const LoggingNotificationSink(),
          sends: DbSendLedger(db),
        );
  if (db == null) logEvent('routing disabled: no database', level: 'warn');
  final hookQueue = HookQueue(processor: processor);

  final server = RelayServer(
    version: version,
    captureSecret: secret,
    captures: CaptureStore(captureDir),
    dbStatus: db == null ? 'error' : 'ok',
    gateway: gateway,
    hooks: HookIngest(db: db, queue: hookQueue, adminSecret: adminSecret),
    registrations: Registrations(
      db: db,
      validator: connectionDataValidator(),
      gateway: gateway,
      adminSecret: adminSecret,
    ),
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
      'schema': RelayDb.schemaVersion,
    },
  );

  Future<void> shutdown(ProcessSignal signal) async {
    logEvent('shutting down', fields: {'signal': signal.toString()});
    await http.close(force: true);
    await hookQueue.close();
    await gateway.close();
    db?.close();
    exit(0);
  }

  // SIGTERM is what `docker stop` sends; it does not exist on Windows.
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(shutdown);
  ProcessSignal.sigint.watch().listen(shutdown);
}
