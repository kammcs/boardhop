import 'package:boardhop/core/text/mention.dart';
import 'package:boardhop/data/models/wiki.dart';
import 'package:boardhop/features/shared/mention/mention_controller.dart';
import 'package:boardhop/features/wiki/wiki_page_source.dart';
import 'package:boardhop/features/wiki/widgets/wiki_page_picker_sheet.dart';
import 'package:boardhop/features/work_items/widgets/work_item_actions.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// research/20 K5/K12: the book button beside attach opens a sheet with the
/// wiki's tree and a filter, and what is picked goes into the field at the
/// caret as plain `[Page title](url)` Markdown — which is what makes
/// `MentionController` leave it alone.
const projectWiki = Wiki(
  id: '2bd59283-17a5-4fd0-b964-cd9a4189f721',
  name: 'DevOps-Mobile-App.wiki',
  type: WikiType.projectWiki,
  versions: ['wikiMaster'],
);

const codeWiki = Wiki(
  id: 'c0de0000-0000-0000-0000-000000000000',
  name: 'boardhop.wiki',
  type: WikiType.codeWiki,
  mappedPath: '/docs',
  versions: ['main'],
);

/// The scratch wiki's shape (spike w37): `/Boardhop` with `Constructs` and
/// `Links`, and a child under `Links`.
const tree = WikiPageNode(
  path: '/',
  isParentPage: true,
  subPages: [
    WikiPageNode(
      path: '/Boardhop',
      id: 236,
      isParentPage: true,
      subPages: [
        WikiPageNode(path: '/Boardhop/Constructs', id: 238),
        WikiPageNode(
          path: '/Boardhop/Links',
          id: 240,
          isParentPage: true,
          subPages: [WikiPageNode(path: '/Boardhop/Links/Deep child', id: 242)],
        ),
        // No id: the batch did not carry this one, so it can only be
        // linked by its path.
        WikiPageNode(path: '/Boardhop/Pushed tidy'),
      ],
    ),
  ],
);

void main() {
  late List<String> posted;

  setUp(() => posted = []);

  WikiPageSource source({List<Wiki> wikis = const [projectWiki]}) =>
      WikiPageSource(
        org: 'puremedia',
        project: 'DevOps Mobile App',
        wikis: () async => wikis,
        tree: (wiki) async => tree,
      );

  Future<void> pumpComposer(
    WidgetTester tester, {
    WikiPageSource? wikiPages,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: CommentComposer(
            onSubmit: (text) async {
              posted.add(text);
              return true;
            },
            wikiPages: wikiPages,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await tester.pumpAndSettle();
  }

  group('the book button', () {
    testWidgets('is absent without a source, so an unwired host is '
        'unchanged', (tester) async {
      await pumpComposer(tester);
      expect(find.byIcon(Icons.menu_book_outlined), findsNothing);
    });

    testWidgets('inserts the picked page at the caret and posts it', (
      tester,
    ) async {
      await pumpComposer(tester, wikiPages: source());
      await tester.enterText(find.byType(TextField), 'see ');
      await openPicker(tester);

      expect(find.text('Link a wiki page'), findsOneWidget);
      // The tree starts collapsed at the top level.
      expect(find.text('Boardhop'), findsOneWidget);
      expect(find.text('Constructs'), findsNothing);
      await tester.tap(find.byIcon(Icons.chevron_right).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Constructs'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'see [Constructs](https://dev.azure.com/puremedia/'
          'DevOps%20Mobile%20App/_wiki/wikis/DevOps-Mobile-App.wiki/238/'
          'Constructs)',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(posted.single, contains('[Constructs](https://dev.azure.com/'));
    });

    testWidgets('the filter searches titles across the whole tree', (
      tester,
    ) async {
      await pumpComposer(tester, wikiPages: source());
      await openPicker(tester);
      await tester.enterText(
        find.descendant(
          of: find.byType(WikiPagePickerSheet),
          matching: find.byType(TextField),
        ),
        'deep',
      );
      await tester.pumpAndSettle();

      expect(find.text('Deep child'), findsOneWidget);
      expect(find.text('/Boardhop/Links/Deep child'), findsOneWidget);
      expect(find.text('Constructs'), findsNothing);

      await tester.tap(find.text('Deep child'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('[Deep child](', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a page with no id is linked by its path', (tester) async {
      await pumpComposer(tester, wikiPages: source());
      await openPicker(tester);
      await tester.enterText(
        find.descendant(
          of: find.byType(WikiPagePickerSheet),
          matching: find.byType(TextField),
        ),
        'pushed',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pushed tidy'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('pagePath=%2FBoardhop%2FPushed%20tidy'),
        findsOneWidget,
      );
    });

    testWidgets('the wiki switcher is offered only with more than one wiki', (
      tester,
    ) async {
      await pumpComposer(tester, wikiPages: source());
      await openPicker(tester);
      expect(find.text('Wiki'), findsNothing);
    });

    testWidgets('with two wikis the switcher is offered', (tester) async {
      await pumpComposer(
        tester,
        wikiPages: source(wikis: const [projectWiki, codeWiki]),
      );
      await openPicker(tester);
      expect(find.text('Wiki'), findsOneWidget);
      expect(find.textContaining('Project wiki'), findsOneWidget);
    });
  });

  group('the URL a pick is linked by', () {
    test('the id form when the node carries an id', () {
      expect(
        wikiPageLinkUrl(
          org: 'puremedia',
          project: 'DevOps Mobile App',
          wiki: projectWiki,
          node: const WikiPageNode(path: '/Boardhop/Deep child', id: 242),
        ),
        'https://dev.azure.com/puremedia/DevOps%20Mobile%20App/_wiki/wikis/'
        'DevOps-Mobile-App.wiki/242/Deep-child',
      );
    });

    test('the path form, with a code wiki\'s branch, when it does not', () {
      expect(
        wikiPageLinkUrl(
          org: 'puremedia',
          project: 'DevOps Mobile App',
          wiki: codeWiki,
          node: const WikiPageNode(path: '/Guides/Setup'),
        ),
        'https://dev.azure.com/puremedia/DevOps%20Mobile%20App/_wiki/wikis/'
        'boardhop.wiki?pagePath=%2FGuides%2FSetup&wikiVersion=GBmain',
      );
    });
  });

  group('MentionController.insertPlain', () {
    test('inserts at the caret and creates no token', () {
      final controller = MentionController(text: 'see  now');
      controller.selection = const TextSelection.collapsed(offset: 4);
      controller.insertPlain('[Page](https://example.test/p)');
      expect(controller.text, 'see [Page](https://example.test/p) now');
      expect(controller.tokens, isEmpty);
      expect(controller.selection.baseOffset, 34);
      // Plain Markdown survives the wire form untouched.
      expect(controller.toWire(MentionWire.markdown), controller.text);
      controller.dispose();
    });

    test('an existing mention shifts rather than breaking', () {
      final controller = MentionController(text: 'hi ');
      controller.insertToken(
        MentionKind.person,
        '11111111-2222-3333-4444-555555555555',
        '@Kelly Kamm',
        replacing: const TextRange(start: 3, end: 3),
      );
      controller.selection = const TextSelection.collapsed(offset: 0);
      controller.insertPlain('[P](u) ');
      expect(controller.text, startsWith('[P](u) hi @Kelly Kamm'));
      expect(controller.tokens, hasLength(1));
      expect(
        controller.toWire(MentionWire.markdown),
        '[P](u) hi @<11111111-2222-3333-4444-555555555555> ',
      );
      controller.dispose();
    });
  });
}
