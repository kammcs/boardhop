import 'package:boardhop/data/repositories/pr_diff_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PrFileChange.listFrom', () {
    test('a deleted file with a null item.path takes originalPath', () {
      // The shape a client PR's delete came back in (2026-09-19); the
      // `as String` cast it replaced left the pull request page blank.
      final changes = PrFileChange.listFrom([
        {
          'changeTrackingId': 3,
          'changeType': 'delete',
          'originalPath': '/src/gone.ts',
          'item': {'path': null, 'originalObjectId': 'old'},
        },
        {
          'changeTrackingId': 4,
          'changeType': 'edit',
          'item': {'path': '/src/kept.ts', 'objectId': 'new'},
        },
      ]);
      expect(
        [for (final c in changes) c.path],
        ['/src/gone.ts', '/src/kept.ts'],
      );
      expect(changes.first.isDelete, isTrue);
      expect(changes.first.originalPath, '/src/gone.ts');
      expect(changes.last.objectId, 'new');
    });

    test('folders and entries with no path at all are dropped', () {
      final changes = PrFileChange.listFrom([
        {
          'changeType': 'add',
          'item': {'path': '/src', 'gitObjectType': 'tree'},
        },
        {'changeType': 'edit', 'item': <String, dynamic>{}},
        {'changeType': 'edit'},
      ]);
      expect(changes, isEmpty);
    });

    test('a missing changeEntries answers an empty list', () {
      expect(PrFileChange.listFrom(null), isEmpty);
    });
  });
}
