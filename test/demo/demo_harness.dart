import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/demo/demo_backend.dart';
import 'package:boardhop/demo/demo_fixtures.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';

/// A client wired to the full demo backend, and an in-memory database, so a
/// test can run a real repository against the demo fixtures.
({AdoClient client, AppDatabase db, DemoBackend backend}) demoHarness() {
  final backend = buildDemoBackend();
  final client = AdoClient(
    tokenProvider: ({tenantId, accountId}) async => 'demo',
    dio: Dio()..httpClientAdapter = backend,
  );
  final db = AppDatabase(NativeDatabase.memory());
  return (client: client, db: db, backend: backend);
}
