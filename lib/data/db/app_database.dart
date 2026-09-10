import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Organizations the signed-in user can reach, from the Accounts API.
@DataClassName('OrgRow')
class Organizations extends Table {
  TextColumn get name => text()();
  TextColumn get uri => text()();
  TextColumn get accountId => text()();
  TextColumn get tenantId => text().nullable()();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {name};
}

@DataClassName('ProjectRow')
class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get orgName => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get state => text().nullable()();
  DateTimeColumn get lastUpdateTime => dateTime().nullable()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {orgName, id};
}

/// Queued writes for offline-first behaviour (decision: queued writes,
/// replayed with `test /rev` and surfaced as conflicts on 412).
@DataClassName('PendingWriteRow')
class PendingWrites extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => text()();
  TextColumn get orgName => text()();
  TextColumn get targetId => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}

@DriftDatabase(tables: [Organizations, Projects, PendingWrites])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'boardhop'));

  @override
  int get schemaVersion => 1;
}
