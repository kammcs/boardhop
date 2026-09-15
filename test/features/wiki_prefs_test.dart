import 'package:boardhop/features/wiki/wiki_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const org = 'puremedia';
const project = 'DevOps Mobile App';
const wikiId = '2bd59283-17a5-4fd0-b964-cd9a4189f721';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('the wiki last opened in a project', () {
    test('is null before anything is opened', () async {
      expect(await WikiPrefs.lastWiki(org, project), isNull);
    });

    test('round-trips, and is scoped to the project', () async {
      await WikiPrefs.setLastWiki(org, project, wikiId);

      expect(await WikiPrefs.lastWiki(org, project), wikiId);
      expect(await WikiPrefs.lastWiki(org, 'Other'), isNull);
      expect(await WikiPrefs.lastWiki('other-org', project), isNull);
    });

    test('an empty id is not stored', () async {
      await WikiPrefs.setLastWiki(org, project, wikiId);
      await WikiPrefs.setLastWiki(org, project, '');

      expect(await WikiPrefs.lastWiki(org, project), wikiId);
    });
  });

  group('the page last read in a wiki', () {
    test('round-trips, and is scoped to the wiki', () async {
      await WikiPrefs.setLastPath(org, project, wikiId, '/Boardhop/Links');

      expect(await WikiPrefs.lastPath(org, project, wikiId), '/Boardhop/Links');
      expect(await WikiPrefs.lastPath(org, project, 'other-wiki'), isNull);
    });

    test('an empty path is not stored', () async {
      await WikiPrefs.setLastPath(org, project, wikiId, '/Boardhop');
      await WikiPrefs.setLastPath(org, project, wikiId, '');

      expect(await WikiPrefs.lastPath(org, project, wikiId), '/Boardhop');
    });
  });

  group('recents (K11: five per wiki, on the device)', () {
    Future<List<WikiRecent>> add(String path, String title) =>
        WikiPrefs.addRecent(
          org,
          project,
          wikiId,
          WikiRecent(path: path, title: title),
        );

    test('start empty', () async {
      expect(await WikiPrefs.recents(org, project, wikiId), isEmpty);
    });

    test('the newest comes first and carries its title', () async {
      await add('/Boardhop', 'Boardhop');
      final kept = await add('/Boardhop/Constructs', 'Constructs');

      expect([for (final r in kept) r.title], ['Constructs', 'Boardhop']);
      expect(kept.first.path, '/Boardhop/Constructs');
      expect(await WikiPrefs.recents(org, project, wikiId), kept);
    });

    test('re-reading a page moves it to the front, not in twice', () async {
      await add('/A', 'A');
      await add('/B', 'B');
      final kept = await add('/A', 'A');

      expect([for (final r in kept) r.path], ['/A', '/B']);
    });

    test('never grows past five', () async {
      for (final n in [1, 2, 3, 4, 5, 6, 7]) {
        await add('/P$n', 'P$n');
      }
      final kept = await WikiPrefs.recents(org, project, wikiId);

      expect(kept, hasLength(WikiPrefs.maxRecents));
      expect([for (final r in kept) r.title], ['P7', 'P6', 'P5', 'P4', 'P3']);
    });

    test('are per wiki, and clear', () async {
      await add('/A', 'A');

      expect(await WikiPrefs.recents(org, project, 'other-wiki'), isEmpty);
      await WikiPrefs.clearRecents(org, project, wikiId);
      expect(await WikiPrefs.recents(org, project, wikiId), isEmpty);
    });

    test('an entry with no path is refused', () async {
      final kept = await add('', 'Nothing');

      expect(kept, isEmpty);
    });

    test(
      'unreadable stored recents read back as none, not as a throw',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'flutter.wiki_recents:$org/$project/$wikiId': 'not json',
        });

        expect(await WikiPrefs.recents(org, project, wikiId), isEmpty);
        // And the next write repairs the entry.
        expect(await add('/A', 'A'), hasLength(1));
      },
    );
  });
}
