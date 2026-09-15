import 'package:boardhop/data/models/wiki.dart';
import 'package:boardhop/features/wiki/widgets/wiki_blocks.dart';
import 'package:boardhop/features/wiki/widgets/wiki_builders.dart';
import 'package:boardhop/features/wiki/widgets/wiki_find.dart';
import 'package:boardhop/features/wiki/widgets/wiki_markdown.dart';
import 'package:boardhop/features/wiki/widgets/wiki_syntaxes.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:boardhop/theme/wiki_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:super_sliver_list/super_sliver_list.dart';

/// W-C: the wiki's markdown extensions (research/20 §4.2, K3 and K10).
///
/// The parsing half is unit-tested against `markdown` directly — an element
/// tree is what the builders are handed, and asserting on it is far more
/// precise than hunting widgets — and the drawing half through the reader's
/// own body.
void main() {
  const wiki = Wiki(
    id: 'wiki-1',
    name: 'DevOps-Mobile-App.wiki',
    type: WikiType.projectWiki,
    versions: ['wikiMaster'],
  );

  /// The element tree a page parses into, with the wiki's own syntaxes.
  List<md.Node> parse(String source, {String? findTerm}) => md.Document(
    blockSyntaxes: wikiBlockSyntaxes(),
    inlineSyntaxes: wikiInlineSyntaxes(findTerm: findTerm),
    extensionSet: md.ExtensionSet.gitHubWeb,
    encodeHtml: false,
  ).parse(WikiPreprocess.run(source));

  /// Every element with [tag] anywhere in the tree.
  List<md.Element> findAll(List<md.Node> nodes, String tag) {
    final out = <md.Element>[];
    void walk(md.Node node) {
      if (node is! md.Element) return;
      if (node.tag == tag) out.add(node);
      for (final child in node.children ?? const <md.Node>[]) {
        walk(child);
      }
    }

    for (final node in nodes) {
      walk(node);
    }
    return out;
  }

  /// [bounded] gives the body the whole screen instead of an unbounded
  /// column: the lazy body scrolls itself, the way the reader hands it the
  /// viewport.
  Widget host(
    Widget child, {
    Brightness brightness = Brightness.light,
    bool bounded = false,
  }) => MaterialApp(
    theme: brightness == Brightness.dark
        ? BoardhopTheme.dark()
        : BoardhopTheme.light(),
    home: Scaffold(body: bounded ? child : SingleChildScrollView(child: child)),
  );

  // ------------------------------------------------------------ front matter

  group('front matter', () {
    test('a leading --- block is stripped, tags and scalars read', () {
      const page = '''
---
tags:
- boardhop
- spike
title: Constructs
---
[[_TOC_]]

# Constructs
''';
      final (matter, body) = WikiFrontMatter.split(page);

      expect(matter, isNotNull);
      expect(matter!.tags, ['boardhop', 'spike']);
      expect(matter.entries.single.key, 'title');
      expect(matter.entries.single.value, 'Constructs');
      expect(matter.raw, isNull);
      expect(body.trimLeft(), startsWith('[[_TOC_]]'));
      expect(body, isNot(contains('---')));
    });

    test('a flow list and quoted values', () {
      final matter = WikiFrontMatter.parse([
        'tags: [ "one", two ]',
        "owner: 'Nobody'",
      ]);

      expect(matter.tags, ['one', 'two']);
      expect(matter.entries.single.value, 'Nobody');
    });

    test('a nested object is kept verbatim rather than half-read', () {
      final matter = WikiFrontMatter.parse(['meta:', '  nested: 1']);

      expect(matter.raw, contains('nested: 1'));
    });

    test('a page opening with a horizontal rule keeps its text', () {
      const page = '---\n\nA paragraph.\n';

      final (matter, body) = WikiFrontMatter.split(page);

      expect(matter, isNull);
      expect(body, contains('A paragraph.'));
    });

    test('no front matter leaves the page alone', () {
      const page = '# Title\n\nBody.\n';

      final (matter, body) = WikiFrontMatter.split(page);

      expect(matter, isNull);
      expect(body, page);
    });
  });

  // ----------------------------------------------------------- preprocessing

  group('preprocessing', () {
    test('=WxH becomes a query the builder reads as a maximum', () {
      final out = WikiPreprocess.destinations(
        '![x](/.attachments/x.png =16x16)',
      );

      expect(out, contains('${WikiImageSize.widthParam}=16'));
      expect(out, contains('${WikiImageSize.heightParam}=16'));
      expect(out, startsWith('![x](/.attachments/x.png?'));
    });

    test('a half size gives one parameter only', () {
      expect(
        WikiPreprocess.destinations('![x](/a.png =16x)'),
        '![x](/a.png?${WikiImageSize.widthParam}=16)',
      );
      expect(
        WikiPreprocess.destinations('![x](/a.png =x16)'),
        '![x](/a.png?${WikiImageSize.heightParam}=16)',
      );
    });

    test('spaces in a destination are encoded and a title survives', () {
      expect(
        WikiPreprocess.destinations(
          '![x](/.attachments/two words.png "A title")',
        ),
        '![x](/.attachments/two%20words.png "A title")',
      );
    });

    test('a link destination with a space is encoded too', () {
      expect(
        WikiPreprocess.destinations('[Deep child](/Boardhop/Links/Deep child)'),
        '[Deep child](/Boardhop/Links/Deep%20child)',
      );
    });

    test('an ordinary image is untouched', () {
      const image = '![x](/.attachments/x.png)';

      expect(WikiPreprocess.destinations(image), image);
    });

    test('only the first [[_TOC_]] survives', () {
      const page = '[[_TOC_]]\n\n# A\n\n[[_TOC_]]\n';

      expect(
        '[[_TOC_]]'.allMatches(WikiPreprocess.keepFirstToc(page)).length,
        1,
      );
    });
  });

  // ------------------------------------------------------------ block syntax

  group('block syntaxes', () {
    test('[[_TOC_]] and [[_TOSP_]] parse into their own elements', () {
      final nodes = parse('[[_TOC_]]\n\n# A\n\n[[_TOSP_]]\n');

      expect(findAll(nodes, WikiTags.toc), hasLength(1));
      expect(findAll(nodes, WikiTags.subPages), hasLength(1));
    });

    test('[[_toc_]] in the wrong case is text, as the wiki has it', () {
      final nodes = parse('[[_toc_]]\n');

      expect(findAll(nodes, WikiTags.toc), isEmpty);
    });

    test('::: mermaid, ::: video and ::: query-table become placeholders', () {
      final nodes = parse('''
::: mermaid
graph LR
  A --> B
:::

::: video
<iframe src="https://example.com/v"></iframe>
:::

::: query-table 11111111-2222-3333-4444-555555555555
:::
''');

      final cards = findAll(nodes, WikiTags.placeholder);
      expect(cards, hasLength(3));
      expect(cards.map((c) => c.attributes[WikiTags.kindAttribute]), [
        'mermaid',
        'video',
        'query-table',
      ]);
      expect(cards.first.textContent, contains('graph LR'));
      expect(
        cards.last.attributes[WikiTags.infoAttribute],
        '11111111-2222-3333-4444-555555555555',
      );
    });

    test('a ```mermaid fence is a placeholder, ```dart stays code', () {
      final nodes = parse('''
```mermaid
sequenceDiagram
```

```dart
void main() {}
```
''');

      expect(findAll(nodes, WikiTags.placeholder), hasLength(1));
      final pre = findAll(nodes, 'pre').single;
      expect(WikiCodeBlockBuilder.languageOf(pre), 'dart');
    });

    test(r'a $$ block is a formula placeholder', () {
      final nodes = parse('A line.\n\n\$\$\n\\sum i\n\$\$\n');

      final card = findAll(nodes, WikiTags.placeholder).single;
      expect(card.attributes[WikiTags.kindAttribute], 'math');
      expect(card.textContent, contains(r'\sum i'));
    });

    test('a pipe table is captured whole for the wiki table builder', () {
      final nodes = parse('''
| Column | Value |
|---|---|
| break | line one<br/>line two |
''');

      expect(findAll(nodes, 'table'), isEmpty);
      final table = findAll(nodes, WikiTags.table).single;
      expect(table.textContent, contains('| break |'));
    });

    test('an HTML block keeps its markup, blank lines included', () {
      final nodes = parse('''
<details>
<summary>Collapsed</summary>

Hidden text.
</details>

After.
''');

      final html = findAll(nodes, WikiTags.html).single;
      expect(html.textContent, contains('<summary>Collapsed</summary>'));
      expect(html.textContent, contains('Hidden text.'));
      expect(html.textContent, isNot(contains('After.')));
    });

    test('a one-line <img> block does not swallow the rest of the page', () {
      final nodes = parse('<img src="/.attachments/x.png">\n\nAfter.\n');

      expect(findAll(nodes, WikiTags.html), hasLength(1));
      expect(
        findAll(nodes, 'p').map((p) => p.textContent).join(),
        contains('After.'),
      );
    });
  });

  // ----------------------------------------------------------- inline syntax

  group('inline syntaxes', () {
    test('<br/> is a line break', () {
      final nodes = parse('one<br/>two\n');

      expect(findAll(nodes, 'br'), hasLength(1));
    });

    test('the styling subset keeps its text in its own element', () {
      final nodes = parse(
        '<u>under</u> <sup>up</sup> <sub>down</sub> <del>gone</del> '
        '<ins>in</ins> <small>small</small> <b>bold</b>\n',
      );

      for (final tag in ['u', 'sup', 'sub', 'del', 'ins', 'small']) {
        expect(findAll(nodes, tag), hasLength(1), reason: tag);
      }
      // `<b>` is `strong`, which the style sheet already carries.
      expect(findAll(nodes, 'strong'), hasLength(1));
    });

    test('a colour tag is dropped and its text kept', () {
      final nodes = parse('<font color="red">still here</font>\n');

      final text = findAll(nodes, 'p').single.textContent;
      expect(text, contains('still here'));
      expect(text, isNot(contains('font')));
    });

    test(r'$E = mc^2$ is math and $5 and $7 is money', () {
      expect(
        findAll(parse(r'Inline $E = mc^2$ here.'), WikiTags.math),
        hasLength(1),
      );
      expect(findAll(parse(r'It cost $5 and $7.'), WikiTags.math), isEmpty);
    });

    test('a find term becomes mark elements, case-insensitively', () {
      final nodes = parse('Relay and relay again.\n', findTerm: 'relay');

      expect(findAll(nodes, WikiTags.mark), hasLength(2));
    });

    test('gitHubWeb still gives emoji, footnotes and heading ids', () {
      final nodes = parse('# A heading\n\nShip it :rocket:\n');

      expect(findAll(nodes, 'h1').single.generatedId, 'a-heading');
      expect(findAll(nodes, 'p').single.textContent, contains('🚀'));
    });
  });

  // ---------------------------------------------------------------- pieces

  group('pieces', () {
    test('the fence-id alias map', () {
      expect(WikiCodeBlock.languageFor('cs'), 'csharp');
      expect(WikiCodeBlock.languageFor('yml'), 'yaml');
      expect(WikiCodeBlock.languageFor('ps1'), 'powershell');
      expect(WikiCodeBlock.languageFor('sh'), 'bash');
      expect(WikiCodeBlock.languageFor('ts'), 'typescript');
      expect(WikiCodeBlock.languageFor('kt'), 'kotlin');
      expect(WikiCodeBlock.languageFor('md'), 'markdown');
      // Not in the map, but a known extension.
      expect(WikiCodeBlock.languageFor('go'), 'go');
      expect(WikiCodeBlock.languageFor('nonsense'), isNull);
      expect(WikiCodeBlock.languageFor(null), isNull);
    });

    test('table rows split on unescaped pipes only', () {
      expect(WikiTableView.cells(r'| a | b\|c |'), ['a', 'b|c']);
      expect(WikiTableView.cells('a | b'), ['a', 'b']);
    });

    test('alignment comes from the delimiter row', () {
      expect(WikiTableView.alignments('|:--|:-:|--:|---|'), [
        TextAlign.left,
        TextAlign.center,
        TextAlign.right,
        TextAlign.left,
      ]);
    });

    test('a short row is padded out so the grid stays rectangular', () {
      final parsed = WikiTableView.parse('| a | b |\n|---|---|\n| one |\n')!;

      expect(parsed.head, ['a', 'b']);
      expect(parsed.body.single, ['one', '']);
    });

    test('the column cap is the smaller of 360 and 80 % of the viewport', () {
      expect(WikiTableView.columnCap(1000), 360);
      expect(WikiTableView.columnCap(390), closeTo(312, 0.1));
    });

    test('a video block gives up its src and a query table its guid', () {
      expect(
        WikiPlaceholderCard.videoUrl(
          '<iframe src="https://example.com/embed/x"></iframe>',
        ).toString(),
        'https://example.com/embed/x',
      );
      expect(
        WikiPlaceholderCard.queryId('11111111-2222-3333-4444-555555555555', ''),
        '11111111-2222-3333-4444-555555555555',
      );
      expect(WikiPlaceholderCard.queryId('', ''), isNull);
    });

    test('the find count is case-insensitive and non-overlapping', () {
      expect(wikiCountMatches('Relay relay RELAY', 'relay'), 3);
      expect(wikiCountMatches('aaaa', 'aa'), 2);
      expect(wikiCountMatches('anything', ''), 0);
    });

    test('the lazy thresholds follow the W-A spike', () {
      expect(WikiMarkdown.isLazy('x' * 50), isFalse);
      expect(WikiMarkdown.isLazy('x' * (200 * 1024)), isTrue);
      expect(WikiMarkdown.isTooLong('x' * (2 * 1024 * 1024)), isTrue);
      expect(WikiMarkdown.isLazy('x' * (2 * 1024 * 1024)), isFalse);
    });
  });

  // ----------------------------------------------------------- style sheet

  group('the style sheet', () {
    testWidgets('links are never Colors.blue and the checkbox is visible in '
        'dark', (tester) async {
      late MarkdownStyleSheet light;
      late MarkdownStyleSheet dark;
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          host(
            Builder(
              builder: (context) {
                final sheet = wikiStyleSheet(context);
                if (brightness == Brightness.light) {
                  light = sheet;
                } else {
                  dark = sheet;
                }
                return const SizedBox.shrink();
              },
            ),
            brightness: brightness,
          ),
        );
        // `MaterialApp` lerps between themes, so the first frame after a
        // swap still resolves the old one.
        await tester.pumpAndSettle();
      }

      for (final sheet in [light, dark]) {
        expect(sheet.a!.color, isNot(Colors.blue));
        expect(sheet.a!.decoration, TextDecoration.underline);
        expect(sheet.checkbox!.color, isNotNull);
        expect(sheet.checkbox!.fontSize, isNotNull);
        // h1–h4 are four distinct sizes, which `fromTheme` does not manage
        // (it gives h4, h5 and h6 the same `bodyLarge`).
        expect(
          {
            sheet.h1,
            sheet.h2,
            sheet.h3,
            sheet.h4,
          }.map((s) => s!.fontSize).toSet(),
          hasLength(4),
        );
      }
      expect(light.checkbox!.color, isNot(dark.checkbox!.color));
    });
  });

  // --------------------------------------------------------------- the body

  group('the body', () {
    const page = '''
---
tags:
- boardhop
title: Constructs
---
[[_TOC_]]

# Constructs

## Mermaid

::: mermaid
graph LR
:::

## Table

| Column | Value |
|---|---|
| break | one<br/>two |

## Code

```dart
void main() {}
```

## HTML

<details>
<summary>Collapsed section</summary>
Hidden.
</details>

## Sub pages

[[_TOSP_]]
''';

    Widget body({
      WikiFindController? find,
      List<WikiPageNode> subPages = const [],
      void Function(String queryId)? onOpenQuery,
      VoidCallback? onOpenOnWeb,
      String content = page,
      bool bounded = false,
    }) => host(
      bounded: bounded,
      WikiMarkdown(
        content: content,
        wiki: wiki,
        pagePath: '/Boardhop/Constructs',
        subPages: subPages,
        find: find,
        onOpenQuery: onOpenQuery,
        onOpenOnWeb: onOpenOnWeb,
      ),
    );

    testWidgets('every construct draws as its own widget', (tester) async {
      await tester.pumpWidget(
        body(
          subPages: const [
            WikiPageNode(path: '/Boardhop/Constructs/Child', id: 1),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(WikiFrontMatterView), findsOneWidget);
      expect(find.text('boardhop'), findsOneWidget);
      expect(find.byType(WikiTocList), findsOneWidget);
      expect(find.byType(WikiPlaceholderCard), findsOneWidget);
      expect(find.text('Diagram (mermaid)'), findsOneWidget);
      expect(find.byType(WikiTableView), findsOneWidget);
      expect(find.byType(WikiCodeBlock), findsOneWidget);
      expect(find.byType(WikiHtmlBlock), findsOneWidget);
      expect(find.byType(WikiSubPagesList), findsOneWidget);
      expect(find.text('Child'), findsOneWidget);
      // Nothing was left as its own source text.
      expect(find.text('[[_TOC_]]'), findsNothing);
      expect(find.textContaining('::: mermaid'), findsNothing);
    });

    testWidgets('the in-page contents lists the headings', (tester) async {
      await tester.pumpWidget(body());
      await tester.pump();

      final toc = tester.widget<WikiTocList>(find.byType(WikiTocList));
      expect(
        toc.headings.map((h) => h.text),
        containsAll(['Constructs', 'Mermaid', 'Table', 'Code']),
      );
    });

    testWidgets('a placeholder shows its source and opens on the web', (
      tester,
    ) async {
      var web = 0;
      await tester.pumpWidget(body(onOpenOnWeb: () => web++));
      await tester.pump();

      await tester.tap(find.text('Show source'));
      await tester.pump();
      expect(find.textContaining('graph LR'), findsOneWidget);

      await tester.tap(find.text('Open on web'));
      await tester.pump();
      expect(web, 1);
    });

    testWidgets('a query table offers Open in Boardhop', (tester) async {
      String? opened;
      await tester.pumpWidget(
        body(
          content:
              '::: query-table 11111111-2222-3333-4444-555555555555\n:::\n',
          onOpenQuery: (id) => opened = id,
        ),
      );
      await tester.pump();

      expect(find.text('Query results'), findsOneWidget);
      await tester.tap(find.text('Open in Boardhop'));
      await tester.pump();
      expect(opened, '11111111-2222-3333-4444-555555555555');
    });

    testWidgets('a code block copies to the clipboard', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(body());
      await tester.pump();

      await tester.ensureVisible(find.byTooltip('Copy code'));
      await tester.pump();
      await tester.tap(find.byTooltip('Copy code'));
      await tester.pump();

      expect(copied.single, contains('void main()'));
    });

    testWidgets('a cell keeps its <br> as a line break', (tester) async {
      await tester.pumpWidget(body(content: '| A |\n|---|\n| one<br/>two |\n'));
      await tester.pump();

      expect(find.byType(WikiTableView), findsOneWidget);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.textSpan?.toPlainText() ?? t.data ?? '')
          .join('\n');
      expect(texts, contains('one\ntwo'));
    });

    testWidgets('a sized image is capped, not stretched', (tester) async {
      await tester.pumpWidget(
        body(content: '![x](/.attachments/x.png =16x16)\n'),
      );
      await tester.pump();

      final box = tester.widgetList<ConstrainedBox>(
        find.byType(ConstrainedBox),
      );
      expect(
        box.any(
          (b) => b.constraints.maxWidth == 16 && b.constraints.maxHeight == 16,
        ),
        isTrue,
      );
    });

    testWidgets('a mention without a name still reads @someone', (
      tester,
    ) async {
      await tester.pumpWidget(
        body(content: 'Hello @<11111111-2222-3333-4444-555555555555>.\n'),
      );
      await tester.pump();

      expect(find.textContaining('@someone'), findsOneWidget);
    });

    testWidgets('find marks every hit and counts them', (tester) async {
      final find_ = WikiFindController();
      addTearDown(find_.dispose);
      await tester.pumpWidget(
        body(
          find: find_,
          content: 'Relay one.\n\n## Relay two\n\nAnd relay three.\n',
        ),
      );
      await tester.pump();

      find_.term = 'relay';
      await tester.pump();
      await tester.pump();

      expect(find_.total, 3);
      expect(find_.label, '1 of 3');
      find_.next();
      expect(find_.label, '2 of 3');
      find_.previous();
      find_.previous();
      expect(find_.label, '3 of 3');
    });

    testWidgets('a long page becomes a lazily built list', (tester) async {
      final long = StringBuffer();
      var section = 0;
      while (long.length <= WikiMarkdown.lazyThreshold) {
        section++;
        long
          ..writeln('## Section $section')
          ..writeln()
          ..writeln('A paragraph that is long enough to matter. ' * 8)
          ..writeln();
      }

      await tester.pumpWidget(body(content: long.toString(), bounded: true));
      await tester.pump();

      expect(find.byType(SuperListView), findsOneWidget);
    });

    testWidgets('a page above a megabyte asks before rendering', (
      tester,
    ) async {
      await tester.pumpWidget(body(content: '# A\n\n${'word ' * 300000}'));
      await tester.pump();

      expect(find.text('Load anyway'), findsOneWidget);
      expect(find.byType(MarkdownBody), findsNothing);

      await tester.tap(find.text('Load anyway'));
      await tester.pump();

      expect(find.byType(MarkdownBody), findsWidgets);
    });

    testWidgets('it draws in dark too', (tester) async {
      await tester.pumpWidget(
        host(
          const WikiMarkdown(
            content: page,
            wiki: wiki,
            pagePath: '/Boardhop/Constructs',
          ),
          brightness: Brightness.dark,
        ),
      );
      await tester.pump();

      expect(find.byType(WikiTableView), findsOneWidget);
    });
  });
}
