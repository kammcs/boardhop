import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../data/models/wiki.dart';
import '../../../theme/theme.dart';
import '../../shared/mention/mention_markdown.dart';
import 'wiki_blocks.dart';
import 'wiki_find.dart';
import 'wiki_syntaxes.dart';

/// Everything the wiki's element builders need from the page around them.
///
/// A plain value object rather than an inherited widget: a
/// [MarkdownElementBuilder] is handed a `BuildContext` only in
/// `visitElementAfterWithContext`, and the table builder has to be able to
/// render a cell without one.
@immutable
class WikiMarkdownConfig {
  const WikiMarkdownConfig({
    required this.cell,
    this.tocHeadings = const [],
    this.subPages = const [],
    this.onOpenAnchor,
    this.onOpenPage,
    this.onOpenOnWeb,
    this.onOpenQuery,
    this.onOpenUrl,
    this.imageUrl,
    this.headers = const {},
    this.onTapHref,
    this.find,
  });

  /// Renders the markdown of one table cell — the reader's own body builder,
  /// so a cell keeps mentions, links, `<br>` and inline code (K10).
  final Widget Function(BuildContext context, String markdown, TextAlign align)
  cell;

  /// The page's headings, for `[[_TOC_]]`.
  final List<({int level, String text, String anchor})> tocHeadings;

  /// The page's child pages, for `[[_TOSP_]]`.
  final List<WikiPageNode> subPages;

  final void Function(String anchor)? onOpenAnchor;
  final void Function(String path)? onOpenPage;

  /// The page on the web: every placeholder card offers it (K3).
  final VoidCallback? onOpenOnWeb;

  /// `::: query-table {guid}` → the Work items page.
  final void Function(String queryId)? onOpenQuery;

  /// `::: video` → the browser.
  final void Function(Uri url)? onOpenUrl;

  /// An `<img src>` inside an HTML block → the URL its bytes come from.
  final String Function(String src)? imageUrl;

  /// `Authorization` for those fetches.
  final Map<String, String> headers;

  /// A link inside an HTML block. True when the reader took it.
  final bool Function(String href)? onTapHref;

  final WikiFindController? find;
}

/// The wiki's block syntaxes, in the order they are tried.
///
/// **A fresh list every build.** `flutter_markdown_plus` appends every block
/// builder's key to one global `_kBlockTags`, and `markdown`'s `Document`
/// keeps its syntaxes in a set it adds to; a shared `const` list handed to
/// two bodies is how the package's own deprecated `TaskListSyntax` ends up
/// applied twice. Building them per body costs nothing measurable (the W-A
/// spike put the whole parse at 0.5 ms/KB) and cannot accumulate.
List<md.BlockSyntax> wikiBlockSyntaxes() => <md.BlockSyntax>[
  const WikiTocSyntax(),
  const WikiSubPagesSyntax(),
  const WikiDirectiveSyntax(),
  const WikiPlaceholderFenceSyntax(),
  const WikiMathBlockSyntax(),
  const WikiHtmlBlockSyntax(),
  const WikiTableSyntax(),
];

/// The wiki's inline syntaxes, in the order they are tried.
///
/// Order is the whole design here: `<br>` before the tag stripper (which
/// would otherwise eat it), the paired tags before it too (it would eat the
/// opening tag and leave the closing one), and the find highlighter last so
/// it never splits a construct in half.
List<md.InlineSyntax> wikiInlineSyntaxes({String? findTerm}) =>
    <md.InlineSyntax>[
      MentionSyntax(),
      WikiBrSyntax(),
      WikiInlineTagSyntax(),
      WikiStripTagSyntax(),
      WikiInlineMathSyntax(),
      if (findTerm != null && findTerm.isNotEmpty) WikiMarkSyntax(findTerm),
    ];

/// The wiki's element builders. A fresh map every build, for the same reason
/// [wikiBlockSyntaxes] is a fresh list.
Map<String, MarkdownElementBuilder> wikiBuilders(WikiMarkdownConfig config) =>
    <String, MarkdownElementBuilder>{
      MentionSyntax.personTag: MentionPersonBuilder(),
      WikiTags.toc: _TocBuilder(config),
      WikiTags.subPages: _SubPagesBuilder(config),
      WikiTags.placeholder: _PlaceholderBuilder(config),
      WikiTags.table: _TableBuilder(config),
      WikiTags.html: _HtmlBuilder(config),
      WikiTags.math: _InlineMathBuilder(),
      WikiTags.mark: WikiMarkBuilder(config.find),
      'pre': WikiCodeBlockBuilder(),
      for (final tag in const ['u', 'sup', 'sub', 'ins', 'small'])
        tag: _InlineTagBuilder(tag),
    };

/// A block builder that draws the element itself and wants none of the text
/// the package would otherwise lay out under it.
abstract class _WikiBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  /// The element's own text is the source we render from, not something to
  /// draw as a paragraph.
  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) => null;
}

class _TocBuilder extends _WikiBlockBuilder {
  _TocBuilder(this.config);

  final WikiMarkdownConfig config;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => WikiTocList(headings: config.tocHeadings, onTap: config.onOpenAnchor);
}

class _SubPagesBuilder extends _WikiBlockBuilder {
  _SubPagesBuilder(this.config);

  final WikiMarkdownConfig config;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => WikiSubPagesList(pages: config.subPages, onOpen: config.onOpenPage);
}

class _PlaceholderBuilder extends _WikiBlockBuilder {
  _PlaceholderBuilder(this.config);

  final WikiMarkdownConfig config;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => WikiPlaceholderCard(
    kind: WikiPlaceholderKind.parse(element.attributes[WikiTags.kindAttribute]),
    source: element.textContent,
    info: element.attributes[WikiTags.infoAttribute] ?? '',
    onOpenOnWeb: config.onOpenOnWeb,
    onOpenQuery: config.onOpenQuery,
    onOpenUrl: config.onOpenUrl,
  );
}

class _TableBuilder extends _WikiBlockBuilder {
  _TableBuilder(this.config);

  final WikiMarkdownConfig config;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => WikiTableView(source: element.textContent, cellBuilder: config.cell);
}

class _HtmlBuilder extends _WikiBlockBuilder {
  _HtmlBuilder(this.config);

  final WikiMarkdownConfig config;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => WikiHtmlBlock(
    html: element.textContent,
    imageUrl: config.imageUrl,
    headers: config.headers,
    onTapUrl: config.onTapHref,
  );
}

/// A fenced code block: the wiki's fence id, the app's highlighter, a copy
/// button (W-C item 5).
class WikiCodeBlockBuilder extends _WikiBlockBuilder {
  /// `class="language-cs"` on the `<code>` the fence parses into.
  static String? languageOf(md.Element pre) {
    for (final child in pre.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        final classes = child.attributes['class'] ?? '';
        const prefix = 'language-';
        for (final name in classes.split(RegExp(r'\s+'))) {
          if (name.startsWith(prefix)) return name.substring(prefix.length);
        }
      }
    }
    return null;
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => WikiCodeBlock(code: element.textContent, language: languageOf(element));
}

/// One find-in-page hit.
///
/// The zero-width [WidgetSpan] is the only way to keep a key on an inline
/// run: `MarkdownBuilder` merges adjacent `Text` widgets into one rich text
/// and a widget's key does not survive that, but a non-`TextSpan` child of
/// the merged span does — so the key rides inside the span instead of on the
/// widget, and `Scrollable.ensureVisible` has a real element to find.
class WikiMarkBuilder extends MarkdownElementBuilder {
  WikiMarkBuilder(this.find);

  final WikiFindController? find;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final key = find?.register();
    return Text.rich(
      TextSpan(
        children: [
          if (key != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: SizedBox.shrink(key: key),
            ),
          TextSpan(
            text: element.textContent,
            style: (parentStyle ?? const TextStyle()).copyWith(
              backgroundColor: wikiMarkBackground(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// `$x$` as a monospace chip — readable, obviously not typeset, and it flows
/// with the sentence because it is a span and not a widget.
class _InlineMathBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => Text.rich(
    TextSpan(
      text: element.textContent,
      style: (parentStyle ?? const TextStyle())
          .merge(BoardhopTheme.codeStyle(context))
          .copyWith(backgroundColor: context.boardhopColors.codeBackground),
    ),
  );
}

/// `<u>`, `<sup>`, `<sub>`, `<ins>` and `<small>`: a styled run, nothing
/// more. `<del>`, `<b>` and `<i>` need no builder — the style sheet already
/// carries `del`, `strong` and `em`.
class _InlineTagBuilder extends MarkdownElementBuilder {
  _InlineTagBuilder(this.tag);

  final String tag;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final base = parentStyle ?? const TextStyle();
    final size =
        base.fontSize ?? Theme.of(context).textTheme.bodyMedium!.fontSize!;
    final style = switch (tag) {
      'u' => base.copyWith(decoration: TextDecoration.underline),
      'ins' => base.copyWith(decoration: TextDecoration.underline),
      'small' => base.copyWith(fontSize: size * 0.85),
      'sup' => base.copyWith(
        fontSize: size * 0.75,
        fontFeatures: const [FontFeature.enable('sups')],
      ),
      'sub' => base.copyWith(
        fontSize: size * 0.75,
        fontFeatures: const [FontFeature.enable('subs')],
      ),
      _ => base,
    };
    return Text.rich(TextSpan(text: element.textContent, style: style));
  }
}
