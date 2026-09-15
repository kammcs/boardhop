import 'package:boardhop/core/text/wiki_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// The scratch wiki (spike w37): project `DevOps Mobile App`, wiki
/// `DevOps-Mobile-App.wiki`, branch `wikiMaster`.
const org = 'puremedia';
const projectId = '98720989-0195-48cb-ae2e-0e58ec1bb9a9';
const wikiId = '2bd59283-17a5-4fd0-b964-cd9a4189f721';
const wikiName = 'DevOps-Mobile-App.wiki';

void main() {
  group('parse: the id form (the web\'s Copy page URL)', () {
    test('project, wiki name, page id and title', () {
      final link = WikiLink.parse(
        'https://dev.azure.com/puremedia/DevOps%20Mobile%20App/_wiki/wikis/'
        '$wikiName/238/Constructs',
      )!;

      expect(link.org, org);
      expect(link.project, 'DevOps Mobile App');
      expect(link.wikiIdOrName, wikiName);
      expect(link.pageId, 238);
      expect(link.path, isNull);
      expect(link.title, 'Constructs');
      expect(link.isWikiRoot, isFalse);
    });

    test('the slug reads back as a title, hyphens as spaces', () {
      final link = WikiLink.parse(
        'https://dev.azure.com/puremedia/Proj/_wiki/wikis/W/246/Level-4',
      )!;

      expect(link.pageId, 246);
      expect(link.title, 'Level 4');
    });

    test('a fragment is the anchor', () {
      final link = WikiLink.parse(
        'https://dev.azure.com/puremedia/Proj/_wiki/wikis/W/238/'
        'Constructs#math',
      )!;

      expect(link.pageId, 238);
      expect(link.anchor, 'math');
    });

    test('an id without a title still parses', () {
      final link = WikiLink.parse(
        'https://dev.azure.com/puremedia/Proj/_wiki/wikis/W/240',
      )!;

      expect(link.pageId, 240);
      expect(link.title, isNull);
    });
  });

  group('parse: the path form (the REST remoteUrl)', () {
    test('pagePath and the project GUID', () {
      final link = WikiLink.parse(
        'https://dev.azure.com/puremedia/$projectId/_wiki/wikis/$wikiId'
        '?pagePath=%2FBoardhop%2FConstructs',
      )!;

      expect(link.org, org);
      expect(link.project, projectId);
      expect(link.wikiIdOrName, wikiId);
      expect(link.pageId, isNull);
      expect(link.path, '/Boardhop/Constructs');
      expect(link.version, isNull);
    });

    test('a path with a space comes back decoded', () {
      final link = WikiLink.parse(
        'https://dev.azure.com/puremedia/$projectId/_wiki/wikis/$wikiId'
        '?pagePath=%2FBoardhop%2FLinks%2FDeep%20child%2FLevel%204',
      )!;

      expect(link.path, '/Boardhop/Links/Deep child/Level 4');
    });

    test('wikiVersion=GB{branch} is the branch', () {
      final link = WikiLink.parse(
        'https://dev.azure.com/puremedia/Proj/_wiki/wikis/Code.wiki'
        '?pagePath=%2FDocs%2FSetup&wikiVersion=GBmain',
      )!;

      expect(link.version, 'main');
      expect(link.path, '/Docs/Setup');
    });

    test('the anchor may ride in the query as well as the fragment', () {
      expect(
        WikiLink.parse(
          'https://dev.azure.com/o/p/_wiki/wikis/W?pagePath=%2FA&anchor=setup',
        )!.anchor,
        'setup',
      );
      expect(
        WikiLink.parse(
          'https://dev.azure.com/o/p/_wiki/wikis/W?pagePath=%2FA#setup',
        )!.anchor,
        'setup',
      );
    });
  });

  group('parse: the wiki root and the odd hosts', () {
    test('a wiki with no page is a root link', () {
      final link = WikiLink.parse(
        'https://dev.azure.com/puremedia/$projectId/_wiki/wikis/$wikiId',
      )!;

      expect(link.wikiIdOrName, wikiId);
      expect(link.pageId, isNull);
      expect(link.path, isNull);
      expect(link.isWikiRoot, isTrue);
    });

    test('the legacy visualstudio.com host', () {
      final link = WikiLink.parse(
        'https://puremedia.visualstudio.com/Proj/_wiki/wikis/W/12/Page',
      )!;

      expect(link.org, org);
      expect(link.project, 'Proj');
      expect(link.pageId, 12);
    });

    test('an organization-level wiki URL has no project', () {
      final link = WikiLink.parse(
        'https://dev.azure.com/puremedia/_wiki/wikis/W?pagePath=%2FA',
      )!;

      expect(link.org, org);
      expect(link.project, isNull);
      expect(link.path, '/A');
    });

    test('anything that is not a wiki URL is null', () {
      expect(WikiLink.parse(''), isNull);
      expect(WikiLink.parse('/Boardhop/Links'), isNull);
      expect(
        WikiLink.parse('https://dev.azure.com/puremedia/Proj/_git/repo'),
        isNull,
      );
      expect(
        WikiLink.parse('https://dev.azure.com/puremedia/Proj/_wiki/wikis'),
        isNull,
      );
      expect(WikiLink.parse('https://example.test/a/b'), isNull);
    });
  });

  group('parse: the vstfs artifact URI', () {
    test('project, wiki and the page path (spike w37 §7)', () {
      final link = WikiLink.parse(
        'vstfs:///Wiki/WikiPage/$projectId%2F$wikiId%2FBoardhop%2FConstructs',
      )!;

      expect(link.project, projectId);
      expect(link.wikiIdOrName, wikiId);
      expect(link.path, '/Boardhop/Constructs');
      expect(link.org, isNull);
      expect(link.pageId, isNull);
    });

    test('segments are URL-encoded inside the %2F join', () {
      final link = WikiLink.parse(
        'vstfs:///Wiki/WikiPage/$projectId%2F$wikiId'
        '%2FBoardhop%2FLinks%2FDeep%20child',
      )!;

      expect(link.path, '/Boardhop/Links/Deep child');
    });

    test('a wiki-level artifact URI carries no path', () {
      final link = WikiLink.parse(
        'vstfs:///Wiki/WikiPage/$projectId%2F$wikiId',
      )!;

      expect(link.path, isNull);
      expect(link.isWikiRoot, isTrue);
    });

    test('a truncated artifact URI is null', () {
      expect(WikiLink.parse('vstfs:///Wiki/WikiPage/$projectId'), isNull);
      expect(WikiLink.parse('vstfs:///Git/Commit/abc'), isNull);
    });
  });

  group('resolve: wiki-relative hrefs', () {
    const page = '/Boardhop/Links';

    test('an absolute path starts at the wiki root', () {
      final href = WikiLink.resolve('/Boardhop/Constructs', pagePath: page)!;

      expect(href.kind, WikiHrefKind.page);
      expect(href.path, '/Boardhop/Constructs');
      expect(href.anchor, isNull);
    });

    test('./ and a bare name resolve against the page\'s own folder', () {
      expect(
        WikiLink.resolve('./Constructs', pagePath: page)!.path,
        '/Boardhop/Constructs',
      );
      expect(
        WikiLink.resolve('Constructs', pagePath: page)!.path,
        '/Boardhop/Constructs',
      );
    });

    test('../ climbs out of it', () {
      expect(
        WikiLink.resolve(
          '../Pushed tidy',
          pagePath: '/Boardhop/Links/Deep child',
        )!.path,
        '/Boardhop/Pushed tidy',
      );
      // Past the root it stops at the root rather than going negative.
      expect(WikiLink.resolve('../../../A', pagePath: page)!.path, '/A');
    });

    test('a child page of the current one', () {
      expect(
        WikiLink.resolve('Links/Deep child', pagePath: '/Boardhop/X')!.path,
        '/Boardhop/Links/Deep child',
      );
    });

    test('%20 and %2D come back as a space and a hyphen', () {
      expect(
        WikiLink.resolve('/Boardhop/Links/Deep%20child', pagePath: page)!.path,
        '/Boardhop/Links/Deep child',
      );
      expect(
        WikiLink.resolve('/Boardhop/Links/Re%2DOrder', pagePath: page)!.path,
        '/Boardhop/Links/Re-Order',
      );
    });

    test('a .md suffix is dropped: a page path never has one', () {
      expect(
        WikiLink.resolve('./Constructs.md', pagePath: page)!.path,
        '/Boardhop/Constructs',
      );
    });

    test('#anchor alone stays on the page', () {
      final href = WikiLink.resolve('#Math', pagePath: page)!;

      expect(href.kind, WikiHrefKind.anchor);
      expect(href.isAnchor, isTrue);
      expect(href.anchor, 'math');
      expect(href.path, '');
    });

    test('a path and an anchor together', () {
      final href = WikiLink.resolve(
        '/Boardhop/Constructs#Task list',
        pagePath: page,
      )!;

      expect(href.kind, WikiHrefKind.page);
      expect(href.path, '/Boardhop/Constructs');
      expect(href.anchor, 'task-list');
    });

    test('/.attachments/x.png is an attachment, not a page', () {
      final href = WikiLink.resolve(
        '/.attachments/boardhop-w37-b64.png',
        pagePath: page,
      )!;

      expect(href.kind, WikiHrefKind.attachment);
      expect(href.isAttachment, isTrue);
      expect(href.path, '/.attachments/boardhop-w37-b64.png');
    });

    test('a relative .attachments path names the same file', () {
      expect(
        WikiLink.resolve('.attachments/x.png', pagePath: page)!.path,
        '/.attachments/x.png',
      );
    });

    test('an absolute URL and an empty href are not wiki-relative', () {
      expect(
        WikiLink.resolve('https://example.test/x', pagePath: page),
        isNull,
      );
      expect(WikiLink.resolve('mailto:a@b.test', pagePath: page), isNull);
      expect(WikiLink.resolve('   ', pagePath: page), isNull);
      expect(WikiLink.resolve('#', pagePath: page), isNull);
    });

    test('a query string is dropped', () {
      expect(
        WikiLink.resolve('/Boardhop/Constructs?x=1', pagePath: page)!.path,
        '/Boardhop/Constructs',
      );
    });
  });

  group('anchorId', () {
    test('the documented example, hyphens uncollapsed', () {
      expect(
        WikiLink.anchorId('Team #1 : Release Wiki!'),
        'team-1--release-wiki',
      );
    });

    test('lower-cases, drops punctuation, keeps hyphens and underscores', () {
      expect(WikiLink.anchorId('Task list'), 'task-list');
      expect(WikiLink.anchorId('HTML block'), 'html-block');
      expect(WikiLink.anchorId('Anchor and footnote'), 'anchor-and-footnote');
      expect(WikiLink.anchorId('A-B_C'), 'a-b_c');
      expect(WikiLink.anchorId('  Spaced  '), 'spaced');
    });

    test('letters outside ASCII survive', () {
      expect(WikiLink.anchorId('Übersicht'), 'übersicht');
    });

    test('anchorMatches falls back to collapsed hyphens', () {
      expect(WikiLink.anchorMatches('math', 'math'), isTrue);
      expect(
        WikiLink.anchorMatches('team-1--release-wiki', 'team-1-release-wiki'),
        isTrue,
      );
      expect(WikiLink.anchorMatches('-math-', 'math'), isTrue);
      expect(WikiLink.anchorMatches('math', 'video'), isFalse);
    });
  });

  group('building URLs', () {
    test('webUrl writes the id form the web writes', () {
      expect(
        WikiLink.webUrl(org, 'DevOps Mobile App', wikiName, 238, 'Constructs'),
        'https://dev.azure.com/puremedia/DevOps%20Mobile%20App/_wiki/wikis/'
        'DevOps-Mobile-App.wiki/238/Constructs',
      );
    });

    test('webUrl turns spaces in the title into hyphens', () {
      expect(
        WikiLink.webUrl(org, 'Proj', 'W', 246, 'Level 4'),
        'https://dev.azure.com/puremedia/Proj/_wiki/wikis/W/246/Level-4',
      );
    });

    test('pageUrl writes the path form, with the branch when given', () {
      expect(
        WikiLink.pageUrl(org, 'Proj', wikiId, '/Boardhop/Constructs'),
        'https://dev.azure.com/puremedia/Proj/_wiki/wikis/$wikiId'
        '?pagePath=%2FBoardhop%2FConstructs',
      );
      expect(
        WikiLink.pageUrl(org, 'Proj', 'Code.wiki', '/Docs', version: 'main'),
        'https://dev.azure.com/puremedia/Proj/_wiki/wikis/Code.wiki'
        '?pagePath=%2FDocs&wikiVersion=GBmain',
      );
    });

    test('withVersion puts the branch on a code wiki remoteUrl', () {
      // Spike w38: the service's own remoteUrl for a code wiki page is
      // `…/_wiki/wikis/{id}?pagePath=%2FHome` — no wikiVersion at all, on
      // a wiki published from two branches.
      const remote =
          'https://dev.azure.com/puremedia/$projectId/_wiki/wikis/$wikiId'
          '?pagePath=%2FHome';
      expect(
        WikiLink.withVersion(remote, 'wiki-docs-v2'),
        '$remote&wikiVersion=GBwiki-docs-v2',
      );
      expect(
        WikiLink.parse(WikiLink.withVersion(remote, 'wiki-docs-v2'))!.version,
        'wiki-docs-v2',
      );
      // Nothing to add, or one already there: the URL is untouched.
      expect(WikiLink.withVersion(remote, null), remote);
      expect(WikiLink.withVersion(remote, ''), remote);
      expect(
        WikiLink.withVersion('$remote&wikiVersion=GBmain', 'other'),
        '$remote&wikiVersion=GBmain',
      );
      // The id form has no query of its own, and an anchor stays last.
      final id = WikiLink.webUrl(org, 'Proj', wikiName, 252, 'Home');
      expect(
        WikiLink.withVersion(id, 'wiki-docs'),
        '$id?wikiVersion=GBwiki-docs',
      );
      expect(
        WikiLink.withVersion('$id#anchor-target', 'wiki-docs'),
        '$id?wikiVersion=GBwiki-docs#anchor-target',
      );
    });

    test('artifactUri matches what the work item relation carries', () {
      expect(
        WikiLink.artifactUri(projectId, wikiId, '/Boardhop/Constructs'),
        'vstfs:///Wiki/WikiPage/$projectId%2F$wikiId%2FBoardhop%2FConstructs',
      );
    });

    test('every built URL parses back to what it was built from', () {
      final web = WikiLink.parse(
        WikiLink.webUrl(org, 'Proj', wikiName, 238, 'Constructs'),
      )!;
      expect(web.pageId, 238);
      expect(web.wikiIdOrName, wikiName);

      final path = WikiLink.parse(
        WikiLink.pageUrl(org, 'Proj', wikiId, '/Boardhop/Links/Deep child'),
      )!;
      expect(path.path, '/Boardhop/Links/Deep child');

      final artifact = WikiLink.parse(
        WikiLink.artifactUri(projectId, wikiId, '/Boardhop/Links/Deep child'),
      )!;
      expect(artifact.path, '/Boardhop/Links/Deep child');
      expect(artifact.wikiIdOrName, wikiId);
    });
  });
}
