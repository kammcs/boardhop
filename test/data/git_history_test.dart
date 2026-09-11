import 'package:boardhop/data/models/git_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sha = 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';

  test('GitVersion maps refs to version descriptors', () {
    expect(GitVersion.query('main'), {
      'versionDescriptor.version': 'main',
      'versionDescriptor.versionType': 'branch',
    });
    expect(GitVersion.query('refs/tags/v1.2', prefix: 'base'), {
      'base.version': 'v1.2',
      'base.versionType': 'tag',
    });
    expect(GitVersion.query(sha)['versionDescriptor.versionType'], 'commit');
    expect(GitVersion.isCommit(sha), isTrue);
    expect(GitVersion.isCommit('main'), isFalse);
    expect(GitVersion.label(sha), 'a1b2c3d');
    expect(GitVersion.label('refs/tags/v1'), 'v1');
    expect(GitVersion.label('feature/x'), 'feature/x');
  });

  test('GitCommit parses list and batch shapes', () {
    final c = GitCommit.fromJson({
      'commitId': sha,
      'comment': 'docs: rewrite guide\n\nLonger body here.\n',
      'commentTruncated': false,
      'author': {
        'name': 'Kelly',
        'email': 'k@example.com',
        'date': '2026-09-10T12:00:00Z',
      },
      'committer': {'name': 'Azure DevOps', 'date': '2026-09-10T12:01:00Z'},
      'changeCounts': {'Add': 2, 'Edit': 5, 'Delete': 1},
      'parents': ['p1', 'p2'],
      'workItems': [
        {'id': '15503', 'url': 'x'},
        {'id': 'nope'},
      ],
    });
    expect(c.shortId, 'a1b2c3d');
    expect(c.subject, 'docs: rewrite guide');
    expect(c.body, 'Longer body here.');
    expect(c.authorName, 'Kelly');
    expect(c.authorDate, DateTime.utc(2026, 9, 10, 12));
    expect(c.added, 2);
    expect(c.edited, 5);
    expect(c.deleted, 1);
    expect(c.isMerge, isTrue);
    expect(c.workItemIds, [15503]);
    final bare = GitCommit.fromJson({'commitId': 'abc', 'comment': 'one'});
    expect(bare.body, '');
    expect(bare.hasCounts, isFalse);
    expect(bare.isMerge, isFalse);
  });

  test('GitChange reads item, type and rename source', () {
    final c = GitChange.fromJson({
      'item': {
        'gitObjectType': 'blob',
        'path': '/src/new.ts',
        'objectId': 'o1',
        'originalObjectId': 'o0',
      },
      'changeType': 'edit, rename',
      'sourceServerItem': '/src/old.ts',
    });
    expect(c.name, 'new.ts');
    expect(c.isRename, isTrue);
    expect(c.isAdd, isFalse);
    expect(c.originalPath, '/src/old.ts');
    final folder = GitChange.fromJson({
      'item': {'gitObjectType': 'tree', 'path': '/src', 'isFolder': true},
      'changeType': 'add',
    });
    expect(folder.isFolder, isTrue);
  });

  test('GitTag peels annotated tags and strips the ref prefix', () {
    final t = GitTag.fromJson({
      'name': 'refs/tags/v2.0',
      'objectId': 'tagobj',
      'peeledObjectId': sha,
      'creator': {'displayName': 'Kelly'},
    });
    expect(t.name, 'v2.0');
    expect(t.commitId, sha);
    expect(t.isAnnotated, isTrue);
    expect(t.ref, 'refs/tags/v2.0');
    final light = GitTag.fromJson({'name': 'refs/tags/v1', 'objectId': sha});
    expect(light.commitId, sha);
    expect(light.isAnnotated, isFalse);
  });

  test('GitCompare keeps counts and files only', () {
    final cmp = GitCompare.fromJson({
      'aheadCount': 17,
      'behindCount': 4,
      'commonCommit': 'c0',
      'baseCommit': 'b0',
      'targetCommit': 't0',
      'allChangesIncluded': true,
      'changes': [
        {
          'item': {'gitObjectType': 'tree', 'path': '/docs'},
          'changeType': 'edit',
        },
        {
          'item': {'gitObjectType': 'blob', 'path': '/docs/a.md'},
          'changeType': 'add',
        },
      ],
    });
    expect(cmp.aheadCount, 17);
    expect(cmp.behindCount, 4);
    expect(cmp.changes.length, 2);
    expect(cmp.files.map((c) => c.path), ['/docs/a.md']);
  });
}
