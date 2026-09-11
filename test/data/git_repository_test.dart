import 'package:boardhop/data/models/git_repository.dart';
import 'package:boardhop/data/repositories/repo_repository.dart';
import 'package:boardhop/features/repos/widgets/repo_visuals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GitRepository', () {
    test('parses the list shape and derives the short default branch', () {
      final r = GitRepository.fromJson({
        'id': 'r1',
        'name': 'MonitorIT',
        'defaultBranch': 'refs/heads/main',
        'size': 26131367,
        'isDisabled': false,
        'isInMaintenance': false,
        'project': {'id': 'p1', 'name': 'CloudCover 2.0'},
        'webUrl': 'https://dev.azure.com/o/p/_git/MonitorIT',
      });
      expect(r.defaultBranchName, 'main');
      expect(r.isActive, isTrue);
      expect(r.isEmpty, isFalse);
      expect(r.projectId, 'p1');
      final empty = GitRepository.fromJson({
        'id': 'r2',
        'name': 'New',
        'isDisabled': true,
        'project': {'id': 'p1', 'name': 'x'},
      });
      expect(empty.isEmpty, isTrue);
      expect(empty.isActive, isFalse);
      expect(GitRepository.shortRef('refs/tags/v1'), 'v1');
    });

    test('language metrics keep real languages, biggest first', () {
      final langs = RepoRepository.parseLanguages({
        'repositoryLanguageAnalytics': [
          {
            'name': 'MonitorIT',
            'languageBreakdown': [
              {'name': 'SQL', 'filesPercentage': 0.1},
              {'name': 'TypeScript', 'filesPercentage': 73.1},
              {'name': 'Java', 'filesPercentage': 19.2},
              {'name': '.lock', 'filesPercentage': 0.1},
              {'name': 'Unknown', 'filesPercentage': 5},
            ],
          },
          {'name': 'Empty', 'languageBreakdown': []},
        ],
      });
      expect(langs['MonitorIT']!.map((l) => l.name), [
        'TypeScript',
        'Java',
        'SQL',
      ]);
      expect(langs['Empty'], isEmpty);
    });

    test('branch stats carry standing and tip commit', () {
      final b = GitBranch.fromJson({
        'name': 'production',
        'aheadCount': 15,
        'behindCount': 18,
        'isBaseVersion': false,
        'commit': {
          'commitId': 'abc',
          'comment': 'Merge branch x\n\nDetails',
          'author': {'name': 'Jeff Baugh', 'date': '2023-06-23T19:56:42Z'},
        },
      });
      expect(b.subject, 'Merge branch x');
      expect(b.authorName, 'Jeff Baugh');
      expect(b.date, DateTime.utc(2023, 6, 23, 19, 56, 42));
      expect(b.isDefault, isFalse);
      // Another branch at the default's commit reports isBaseVersion too.
      final twin = GitBranch.fromJson({
        'name': 'release/3.3',
        'isBaseVersion': true,
      }, defaultBranch: 'main');
      expect(twin.isDefault, isFalse);
      expect(
        GitBranch.fromJson({
          'name': 'main',
          'isBaseVersion': true,
        }, defaultBranch: 'main').isDefault,
        isTrue,
      );
    });
  });

  group('RepoSections', () {
    GitRepository repo(String id, {bool disabled = false}) =>
        GitRepository.fromJson({
          'id': id,
          'name': id,
          'defaultBranch': 'refs/heads/main',
          'isDisabled': disabled,
          'project': {'id': 'p', 'name': 'p'},
        });

    test('orders favorites, recents, the rest, then disabled', () {
      final s = RepoSections.build(
        [repo('a'), repo('b'), repo('c'), repo('d', disabled: true)],
        favoriteIds: {'c'},
        recentIds: ['b', 'c', 'zzz'],
      );
      expect(s.favorites.map((r) => r.id), ['c']);
      expect(s.recents.map((r) => r.id), ['b']);
      expect(s.all.map((r) => r.id), ['a']);
      expect(s.inactive.map((r) => r.id), ['d']);
    });

    test('filters by name', () {
      final s = RepoSections.build(
        [repo('Portal'), repo('MonitorIT')],
        favoriteIds: const {},
        recentIds: const [],
        query: 'mon',
      );
      expect(s.all.map((r) => r.id), ['MonitorIT']);
      expect(s.isEmpty, isFalse);
    });
  });

  test('formatBytes', () {
    expect(formatBytes(238301), '233 KB');
    expect(formatBytes(26131367), '25 MB');
    expect(formatBytes(1963889), '1.9 MB');
    expect(formatBytes(null), '');
  });

  _phase2();
}

void _phase2() {
  group('GitItem', () {
    test('parses a listing child and a single item with metadata', () {
      final child = GitItem.fromJson({
        'objectId': 'abc',
        'gitObjectType': 'tree',
        'commitId': 'c1',
        'path': '/src/lib',
      });
      expect(child.isFolder, isTrue);
      expect(child.name, 'lib');
      expect(child.isBinary, isNull);
      final file = GitItem.fromJson({
        'objectId': 'def',
        'gitObjectType': 'blob',
        'path': '/docs/Logo.PNG',
        'contentMetadata': {
          'encoding': -1,
          'contentType': 'image/png',
          'isBinary': true,
          'isImage': true,
        },
      });
      expect(file.isFolder, isFalse);
      expect(file.extension, 'png');
      expect(file.isImage, isTrue);
      expect(file.contentType, 'image/png');
      expect(GitItem.fromJson({'path': '/README'}).extension, '');
      expect(GitItem.fromJson({'path': '/.gitignore'}).extension, '');
    });

    test('tree parsing drops the folder itself and sorts folders first', () {
      final items = RepoRepository.parseTree([
        {'path': '/src', 'gitObjectType': 'tree', 'isFolder': true},
        {'path': '/src/b.dart', 'gitObjectType': 'blob'},
        {'path': '/src/A.dart', 'gitObjectType': 'blob'},
        {'path': '/src/zeta', 'gitObjectType': 'tree'},
        {'path': '/src/alpha', 'gitObjectType': 'tree'},
      ], '/src/');
      expect(items.map((i) => i.name), ['alpha', 'zeta', 'A.dart', 'b.dart']);
    });
  });

  group('RepoPaths', () {
    test('normalize, parent, segments, prefix', () {
      expect(RepoPaths.normalize('src/lib/'), '/src/lib');
      expect(RepoPaths.normalize('/'), '/');
      expect(RepoPaths.normalize(''), '/');
      expect(RepoPaths.parent('/src/lib/main.dart'), '/src/lib');
      expect(RepoPaths.parent('/README.md'), '/');
      expect(RepoPaths.parent('/'), '/');
      expect(RepoPaths.segments('/a/b/c'), ['a', 'b', 'c']);
      expect(RepoPaths.segments('/'), isEmpty);
      expect(RepoPaths.prefix('/a/b/c', 2), '/a/b');
      expect(RepoPaths.prefix('/a/b/c', 0), '/');
    });

    test('resolves Markdown links against the file folder', () {
      const from = '/docs/guide/README.md';
      expect(
        RepoPaths.resolve(from, 'images/a.png'),
        '/docs/guide/images/a.png',
      );
      expect(RepoPaths.resolve(from, './b.md#intro'), '/docs/guide/b.md');
      expect(RepoPaths.resolve(from, '../c.md?x=1'), '/docs/c.md');
      expect(RepoPaths.resolve(from, '../../../../d.md'), '/d.md');
      expect(RepoPaths.resolve(from, '/root.md'), '/root.md');
      expect(RepoPaths.resolve(from, 'my%20file.md'), '/docs/guide/my file.md');
      expect(RepoPaths.resolve(from, 'https://x.y/z'), isNull);
      expect(RepoPaths.resolve(from, '#anchor'), isNull);
      expect(RepoPaths.resolve(from, '..'), '/docs');
    });
  });

  test('web links match the browser format', () {
    final repo = GitRepository.fromJson({
      'id': 'r',
      'name': 'MonitorIT',
      'project': {'id': 'p', 'name': 'x'},
      'webUrl': 'https://dev.azure.com/o/p/_git/MonitorIT',
    });
    expect(
      RepoWebUrls.file(repo, '/src/app.ts', 'feature/x y'),
      'https://dev.azure.com/o/p/_git/MonitorIT'
      '?path=%2Fsrc%2Fapp.ts&version=GBfeature%2Fx+y',
    );
    expect(
      RepoWebUrls.commit(repo, 'abc'),
      'https://dev.azure.com/o/p/_git/MonitorIT/commit/abc',
    );
    final bare = GitRepository.fromJson({
      'id': 'r',
      'name': 'n',
      'project': {'id': 'p', 'name': 'x'},
    });
    expect(RepoWebUrls.folder(bare, '/', 'main'), isNull);
  });
}
