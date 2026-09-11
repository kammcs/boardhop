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
}
