import 'package:boardhop/data/models/wiki.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixtures are the scratch wiki of spike w37 ("DevOps Mobile App"), whose
/// GUIDs and page ids are quotable (research/20 §1).
const projectId = '98720989-0195-48cb-ae2e-0e58ec1bb9a9';
const wikiId = '2bd59283-17a5-4fd0-b964-cd9a4189f721';

Map<String, dynamic> wikiJson() => {
  'id': wikiId,
  'versions': [
    {'version': 'wikiMaster'},
  ],
  'url': 'https://dev.azure.com/puremedia/$projectId/_apis/wiki/wikis/$wikiId',
  'remoteUrl': 'https://dev.azure.com/puremedia/$projectId/_wiki/wikis/$wikiId',
  'type': 'projectWiki',
  'name': 'DevOps-Mobile-App.wiki',
  'projectId': projectId,
  'repositoryId': wikiId,
  'mappedPath': '/',
};

/// The scratch tree exactly as `recursionLevel=full` answers it — siblings
/// in the service's own (alphabetical) order, and no ids anywhere.
Map<String, dynamic> treeJson() => {
  'path': '/',
  'order': 0,
  'isParentPage': true,
  'gitItemPath': '/',
  'subPages': [
    {
      'path': '/Boardhop',
      'order': 0,
      'isParentPage': true,
      'gitItemPath': '/Boardhop.md',
      'subPages': [
        {
          'path': '/Boardhop/Constructs',
          'order': 1,
          'gitItemPath': '/Boardhop/Constructs.md',
          'subPages': <Object?>[],
        },
        {
          'path': '/Boardhop/Links',
          'order': 0,
          'isParentPage': true,
          'gitItemPath': '/Boardhop/Links.md',
          'subPages': [
            {
              'path': '/Boardhop/Links/Deep child',
              'order': 1,
              'isParentPage': true,
              'gitItemPath': '/Boardhop/Links/Deep-child.md',
              'subPages': [
                {
                  'path': '/Boardhop/Links/Deep child/Level 4',
                  'order': 0,
                  'gitItemPath': '/Boardhop/Links/Deep-child/Level-4.md',
                  'subPages': <Object?>[],
                },
              ],
            },
            {
              'path': '/Boardhop/Links/Re-Order',
              'order': 0,
              'gitItemPath': '/Boardhop/Links/Re%2DOrder.md',
              'subPages': <Object?>[],
            },
          ],
        },
        {
          'path': '/Boardhop/Pushed page',
          'order': 2147483647,
          'isNonConformant': true,
          'gitItemPath': '/Boardhop/Pushed page.md',
          'subPages': <Object?>[],
        },
        {
          'path': '/Boardhop/Pushed tidy',
          'order': 2147483647,
          'gitItemPath': '/Boardhop/Pushed-tidy.md',
          'subPages': <Object?>[],
        },
      ],
    },
  ],
};

/// What `POST pagesbatch` answers for the same wiki.
const batchIds = <String, int>{
  '/Boardhop': 236,
  '/Boardhop/Constructs': 238,
  '/Boardhop/Links': 240,
  '/Boardhop/Links/Deep child': 242,
  '/Boardhop/Links/Re-Order': 244,
  '/Boardhop/Links/Deep child/Level 4': 246,
  '/Boardhop/Pushed page': 248,
  '/Boardhop/Pushed tidy': 249,
};

void main() {
  group('Wiki', () {
    test('reads the project wiki the scratch project answers', () {
      final wiki = Wiki.fromJson(wikiJson());

      expect(wiki.id, wikiId);
      expect(wiki.name, 'DevOps-Mobile-App.wiki');
      expect(wiki.type, WikiType.projectWiki);
      expect(wiki.isProjectWiki, isTrue);
      expect(wiki.projectId, projectId);
      // A project wiki's repository is the wiki itself.
      expect(wiki.repositoryId, wikiId);
      expect(wiki.mappedPath, '/');
      expect(wiki.hasMappedPath, isFalse);
      expect(wiki.versions, ['wikiMaster']);
      expect(wiki.version, 'wikiMaster');
      expect(wiki.remoteUrl, contains('/_wiki/wikis/'));
    });

    test('a code wiki carries its folder and its branches', () {
      final wiki = Wiki.fromJson({
        'id': 'c0de',
        'name': 'docs.wiki',
        'type': 'codeWiki',
        'repositoryId': 'repo-1',
        'mappedPath': '/docs',
        'versions': [
          {'version': 'main'},
          {'version': 'release'},
        ],
      });

      expect(wiki.type, WikiType.codeWiki);
      expect(wiki.isProjectWiki, isFalse);
      expect(wiki.repositoryId, 'repo-1');
      expect(wiki.hasMappedPath, isTrue);
      // Every read passes the first published version (K8).
      expect(wiki.version, 'main');
    });

    test('an empty answer does not throw and round-trips', () {
      final wiki = Wiki.fromJson(const {});

      expect(wiki.id, '');
      expect(wiki.type, WikiType.projectWiki);
      expect(wiki.version, 'wikiMaster');
      expect(
        Wiki.fromJson(Wiki.fromJson(wikiJson()).toJson()),
        Wiki.fromJson(wikiJson()),
      );
    });
  });

  group('WikiPageNode', () {
    test('the scratch tree parses whole, with no ids', () {
      final root = WikiPageNode.fromJson(treeJson());

      expect(root.isRoot, isTrue);
      expect(root.flatten().length, 9); // the root plus eight pages
      expect(root.flatten().every((n) => n.id == null), isTrue);
      expect(root.subPages.single.path, '/Boardhop');
    });

    test('the title is the last segment, spaces and hyphens kept', () {
      final root = WikiPageNode.fromJson(treeJson());

      expect(root.find('/Boardhop/Links/Deep child')!.title, 'Deep child');
      expect(root.find('/Boardhop/Links/Re-Order')!.title, 'Re-Order');
      expect(root.title, '');
    });

    test('the file form is never derived from the title form', () {
      final root = WikiPageNode.fromJson(treeJson());

      expect(
        root.find('/Boardhop/Links/Deep child')!.gitItemPath,
        '/Boardhop/Links/Deep-child.md',
      );
      expect(
        root.find('/Boardhop/Links/Re-Order')!.gitItemPath,
        '/Boardhop/Links/Re%2DOrder.md',
      );
    });

    test('siblings come out in .order order, not the service\'s', () {
      final root = WikiPageNode.fromJson(treeJson());
      final children = root.find('/Boardhop')!.subPages;

      // The service answers Constructs (order 1) first; `.order` says Links.
      expect(
        [for (final c in children) c.title],
        ['Links', 'Constructs', 'Pushed page', 'Pushed tidy'],
      );
      // Everything outside `.order` sorts behind, alphabetically.
      expect(children.last.order, WikiPageNode.unordered);
    });

    test('the git-pushed page is flagged non-conformant', () {
      final root = WikiPageNode.fromJson(treeJson());

      expect(root.find('/Boardhop/Pushed page')!.isNonConformant, isTrue);
      expect(root.find('/Boardhop/Pushed tidy')!.isNonConformant, isFalse);
    });

    test('find matches exactly, then case-insensitively', () {
      final root = WikiPageNode.fromJson(treeJson());

      expect(root.find('/Boardhop/Constructs')!.order, 1);
      expect(root.find('/boardhop/constructs')!.path, '/Boardhop/Constructs');
      expect(root.find('/Boardhop/Constructs/')!.path, '/Boardhop/Constructs');
      expect(root.find('/nope'), isNull);
    });

    test('ancestorsOf is the chain above the page, outermost first', () {
      final root = WikiPageNode.fromJson(treeJson());

      expect(
        [
          for (final n in root.ancestorsOf(
            '/Boardhop/Links/Deep child/Level 4',
          ))
            n.path,
        ],
        ['/Boardhop', '/Boardhop/Links', '/Boardhop/Links/Deep child'],
      );
      expect(root.ancestorsOf('/Boardhop'), isEmpty);
      expect(root.ancestorsOf('/nope'), isEmpty);
    });

    test('withIds joins the pagesbatch ids on path', () {
      final root = WikiPageNode.fromJson(treeJson()).withIds(batchIds);

      expect(root.find('/Boardhop')!.id, 236);
      expect(root.find('/Boardhop/Constructs')!.id, 238);
      expect(root.find('/Boardhop/Links/Deep child/Level 4')!.id, 246);
      expect(root.find('/Boardhop/Pushed page')!.id, 248);
      // The root is not a page and the batch never names it.
      expect(root.id, isNull);
      expect(root.flatten().where((n) => !n.isRoot && n.id == null), isEmpty);
    });

    test('a path the batch did not carry keeps no id', () {
      final root = WikiPageNode.fromJson(treeJson())
          .withIds(const {'/Boardhop': 236});

      expect(root.find('/Boardhop')!.id, 236);
      expect(root.find('/Boardhop/Constructs')!.id, isNull);
    });

    test('the joined tree round-trips through JSON (it is what is cached)', () {
      final joined = WikiPageNode.fromJson(treeJson()).withIds(batchIds);

      expect(WikiPageNode.fromJson(joined.toJson()), joined);
    });

    test('a node with nothing in it does not throw', () {
      final node = WikiPageNode.fromJson(const {});

      expect(node.path, '/');
      expect(node.isRoot, isTrue);
      expect(node.subPages, isEmpty);
      expect(node.flatten(), [node]);
    });
  });

  group('WikiPage', () {
    test('reads a page and the ETag the repository put on it', () {
      final page = WikiPage.fromJson({
        'id': 238,
        'path': '/Boardhop/Constructs',
        'order': 1,
        'gitItemPath': '/Boardhop/Constructs.md',
        'content': '# Constructs\n',
        'subPages': <Object?>[],
        'remoteUrl':
            'https://dev.azure.com/puremedia/$projectId/_wiki/wikis/$wikiId'
            '?pagePath=%2FBoardhop%2FConstructs',
        'etag': '"e33a90d23344d6dacb346e7a12def64a48e0a05f"',
      });

      expect(page.id, 238);
      expect(page.title, 'Constructs');
      expect(page.content, '# Constructs\n');
      // The quotes of the header are not part of the blob SHA.
      expect(page.etag, 'e33a90d23344d6dacb346e7a12def64a48e0a05f');
    });

    test('a weak ETag is unwrapped too, and a missing one is null', () {
      expect(
        WikiPage.fromJson(const {'path': '/A', 'etag': 'W/"abc"'}).etag,
        'abc',
      );
      expect(WikiPage.fromJson(const {'path': '/A'}).etag, isNull);
      expect(WikiPage.fromJson(const {'path': '/A', 'etag': ''}).etag, isNull);
    });

    test('subPages of a page answer are nodes, sorted like the tree', () {
      final page = WikiPage.fromJson({
        'id': 236,
        'path': '/Boardhop',
        'content': '',
        'subPages': [
          {'path': '/Boardhop/Constructs', 'order': 1},
          {'path': '/Boardhop/Links', 'order': 0},
        ],
      });

      expect([for (final s in page.subPages) s.title], ['Links', 'Constructs']);
    });

    test('round-trips through JSON, which is how it is cached', () {
      final page = WikiPage.fromJson({
        'id': 240,
        'path': '/Boardhop/Links',
        'gitItemPath': '/Boardhop/Links.md',
        'content': 'body',
        'etag': '"2f17480709d03c64260cf818bd16747766e27e94"',
        'subPages': <Object?>[],
      });

      expect(WikiPage.fromJson(page.toJson()), page);
      expect(page.copyWith(etag: 'other').etag, 'other');
    });
  });

  group('WikiSearchHit', () {
    Map<String, dynamic> hitJson({
      String path = '/Boardhop.md',
      String mappedPath = '/',
    }) => {
      'fileName': path.split('/').last,
      'path': path,
      'collection': {'name': 'puremedia'},
      'project': {'id': projectId, 'name': 'DevOps Mobile App'},
      'wiki': {
        'name': 'DevOps-Mobile-App.wiki',
        'id': wikiId,
        'mappedPath': mappedPath,
        'version': 'wikiMaster',
      },
      'contentId': 'cfb72c3bac53fad93c24ef5408a5276183a911bf',
      'hits': [
        {
          'fieldReferenceName': 'fileNames',
          'highlights': ['<highlighthit>Boardhop</highlighthit>'],
        },
        {
          'fieldReferenceName': 'content',
          'highlights': ['<highlighthit>Boardhop</highlighthit> wiki spike'],
        },
      ],
    };

    test('reads the wiki, project and content id off a hit', () {
      final hit = WikiSearchHit.fromJson(hitJson());

      expect(hit.fileName, 'Boardhop.md');
      expect(hit.wikiId, wikiId);
      expect(hit.wikiName, 'DevOps-Mobile-App.wiki');
      expect(hit.version, 'wikiMaster');
      expect(hit.projectName, 'DevOps Mobile App');
      expect(hit.projectId, projectId);
      // The same value a page's ETag carries.
      expect(hit.contentId, 'cfb72c3bac53fad93c24ef5408a5276183a911bf');
      expect(hit.highlights, hasLength(2));
      // A content match says more than the file name the title shows.
      expect(hit.highlight!.fieldReferenceName, 'content');
    });

    test('pagePath converts the git file path back to a page path', () {
      expect(WikiSearchHit.fromJson(hitJson()).pagePath, '/Boardhop');
      expect(
        WikiSearchHit.fromJson(hitJson(path: '/Boardhop/Links/Deep-child.md'))
            .pagePath,
        '/Boardhop/Links/Deep child',
      );
      // %2D outlives the hyphen-to-space step, which is why it runs second.
      expect(
        WikiSearchHit.fromJson(hitJson(path: '/Boardhop/Links/Re%2DOrder.md'))
            .pagePath,
        '/Boardhop/Links/Re-Order',
      );
      expect(
        WikiSearchHit.fromJson(
          hitJson(path: '/Boardhop/Links/Deep-child/Level-4.md'),
        ).title,
        'Level 4',
      );
    });

    test('a code wiki\'s mappedPath is dropped from the path', () {
      final hit = WikiSearchHit.fromJson(
        hitJson(path: '/docs/Setup-guide.md', mappedPath: '/docs'),
      );

      expect(hit.pagePath, '/Setup guide');
      expect(hit.title, 'Setup guide');
    });

    test('round-trips through JSON, which is how a search is cached', () {
      final hit = WikiSearchHit.fromJson(hitJson());

      expect(WikiSearchHit.fromJson(hit.toJson()), hit);
    });

    test('an empty hit does not throw', () {
      final hit = WikiSearchHit.fromJson(const {});

      expect(hit.path, '');
      expect(hit.pagePath, '');
      expect(hit.highlight, isNull);
    });
  });

  group('WikiPageChange', () {
    test('reads the author, date and message of a commit', () {
      final change = WikiPageChange.fromJson({
        'commitId': 'abc',
        'author': {
          'name': 'Kelly Kamm',
          'email': 'kelly@kammcs.com',
          'date': '2026-09-15T16:40:00Z',
        },
        'committer': {'name': 'Kelly Kamm', 'date': '2026-09-15T16:40:00Z'},
        'comment': 'spike w37',
      });

      expect(change.author, 'Kelly Kamm');
      expect(change.date, DateTime.utc(2026, 9, 15, 16, 40));
      expect(change.comment, 'spike w37');
      expect(change.isEmpty, isFalse);
    });

    test('falls back to the committer and reports an empty change', () {
      final change = WikiPageChange.fromJson({
        'committer': {'name': 'Build', 'date': '2026-09-15T16:40:00Z'},
      });

      expect(change.author, 'Build');
      expect(WikiPageChange.fromJson(const {}).isEmpty, isTrue);
    });
  });
}
