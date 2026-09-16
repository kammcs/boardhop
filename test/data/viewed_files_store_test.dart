import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/repositories/pr_diff_source.dart';
import 'package:boardhop/data/viewed_files_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const account = 'kelly@kammcs.com-home';
const other = 'kelly@kammcs.com-work';
const org = 'puremedia';
const prId = 8401;

PrFileChange change(String path, {String? objectId}) => PrFileChange(
  path: path,
  changeType: 'edit',
  changeTrackingId: 1,
  objectId: objectId,
);

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('nothing is viewed on a fresh pull request', () async {
    final store = ViewedFilesStore(db, userId: account);
    expect(await store.isViewed(org, prId, '/src/app.ts'), isFalse);
    expect(await store.marks(org, prId), isEmpty);
  });

  test('a mark survives a restart of the app', () async {
    await ViewedFilesStore(
      db,
      userId: account,
    ).markViewed(org, prId, '/src/app.ts', iterationId: 5, objectId: 'c0d1a2');

    // A second store over the same database is what a cold start sees.
    final reopened = ViewedFilesStore(db, userId: account);
    expect(await reopened.isViewed(org, prId, '/src/app.ts'), isTrue);
    expect((await reopened.marks(org, prId))['/src/app.ts'], (
      iterationId: 5,
      objectId: 'c0d1a2',
    ));
  });

  test('marks are namespaced per account', () async {
    await ViewedFilesStore(
      db,
      userId: account,
    ).markViewed(org, prId, '/src/app.ts', iterationId: 5);

    final elsewhere = ViewedFilesStore(db, userId: other);
    expect(await elsewhere.isViewed(org, prId, '/src/app.ts'), isFalse);
  });

  test('marks are per pull request and per organization', () async {
    final store = ViewedFilesStore(db, userId: account);
    await store.markViewed(org, prId, '/src/app.ts', iterationId: 5);

    expect(await store.isViewed(org, 8334, '/src/app.ts'), isFalse);
    expect(await store.isViewed('contoso', prId, '/src/app.ts'), isFalse);
    expect(ViewedFilesStore.key(org, prId), 'pr:viewed:$org:$prId');
  });

  test('clear drops one file, or the whole pull request', () async {
    final store = ViewedFilesStore(db, userId: account);
    await store.markViewed(org, prId, '/a.txt', iterationId: 1);
    await store.markViewed(org, prId, '/b.txt', iterationId: 1);

    await store.clear(org, prId, path: '/a.txt');
    expect(await store.isViewed(org, prId, '/a.txt'), isFalse);
    expect(await store.isViewed(org, prId, '/b.txt'), isTrue);

    await store.clear(org, prId);
    expect(await store.marks(org, prId), isEmpty);
    // And it is really gone from the database, not only from the memo.
    expect(
      await ViewedFilesStore(db, userId: account).marks(org, prId),
      isEmpty,
    );
  });

  group('prune', () {
    test('a new blob for the same path clears the mark', () async {
      final store = ViewedFilesStore(db, userId: account);
      await store.markViewed(
        org,
        prId,
        '/src/app.ts',
        iterationId: 1,
        objectId: 'old',
      );
      await store.markViewed(
        org,
        prId,
        '/spike/w39/one.txt',
        iterationId: 1,
        objectId: 'same',
      );

      final dropped = await store.prune(org, prId, [
        change('/src/app.ts', objectId: 'new'),
        change('/spike/w39/one.txt', objectId: 'same'),
      ], iterationId: 5);

      expect(dropped, 1);
      expect(await store.isViewed(org, prId, '/src/app.ts'), isFalse);
      expect(await store.isViewed(org, prId, '/spike/w39/one.txt'), isTrue);
    });

    test('without blob ids a later iteration clears the mark', () async {
      final store = ViewedFilesStore(db, userId: account);
      await store.markViewed(org, prId, '/src/app.ts', iterationId: 1);

      expect(
        await store.prune(org, prId, [change('/src/app.ts')], iterationId: 1),
        0,
      );
      expect(await store.isViewed(org, prId, '/src/app.ts'), isTrue);

      expect(
        await store.prune(org, prId, [change('/src/app.ts')], iterationId: 5),
        1,
      );
      expect(await store.isViewed(org, prId, '/src/app.ts'), isFalse);
    });

    test('a file absent from the changes keeps its mark', () async {
      final store = ViewedFilesStore(db, userId: account);
      await store.markViewed(
        org,
        prId,
        '/src/app.ts',
        iterationId: 1,
        objectId: 'old',
      );

      final dropped = await store.prune(org, prId, [
        change('/spike/w39/two.txt', objectId: 'x'),
      ], iterationId: 5);

      expect(dropped, 0);
      expect(await store.isViewed(org, prId, '/src/app.ts'), isTrue);
    });

    test('pruning nothing writes nothing', () async {
      final store = ViewedFilesStore(db, userId: account);
      expect(await store.prune(org, prId, const [], iterationId: 5), 0);
    });

    test('the pruned state survives a restart', () async {
      final store = ViewedFilesStore(db, userId: account);
      await store.markViewed(
        org,
        prId,
        '/src/app.ts',
        iterationId: 1,
        objectId: 'old',
      );
      await store.prune(org, prId, [
        change('/src/app.ts', objectId: 'new'),
      ], iterationId: 5);

      expect(
        await ViewedFilesStore(
          db,
          userId: account,
        ).isViewed(org, prId, '/src/app.ts'),
        isFalse,
      );
    });
  });

  test('without a database the store is harmless', () async {
    final store = ViewedFilesStore(null, userId: account);
    await store.markViewed(org, prId, '/src/app.ts', iterationId: 1);
    // The memo still answers within the session; nothing is persisted.
    expect(await store.isViewed(org, prId, '/src/app.ts'), isTrue);
    expect(
      await ViewedFilesStore(
        null,
        userId: account,
      ).isViewed(org, prId, '/src/app.ts'),
      isFalse,
    );
  });
}
