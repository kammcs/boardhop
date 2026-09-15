import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/text/mention.dart';
import '../../../core/text/wiki_link.dart';
import '../../../data/models/wiki.dart';
import '../../../theme/theme.dart';
import '../../shared/mention/mention_markdown.dart';
import 'wiki_blocks.dart';
import 'wiki_builders.dart';
import 'wiki_find.dart';
import 'wiki_syntaxes.dart';

/// One heading of a page, with the key the reader scrolls to it by.
///
/// The key is created here and handed to the widget that draws the heading,
/// so the contents sheet (K9) can `ensureVisible` it. W-C's own heading
/// builders register through the same [WikiHeadings], which is the seam this
/// phase exists to pin down.
class WikiHeading {
  WikiHeading({required this.level, required this.text, required this.anchor})
    : key = GlobalKey(debugLabel: 'wiki-heading-$anchor');

  final int level;
  final String text;

  /// The wiki's own anchor id for [text] ([WikiLink.anchorId]).
  final String anchor;
  final GlobalKey key;
}

/// The headings of the page on screen, in document order.
///
/// A `ChangeNotifier` rather than a plain list because the body is built
/// during a frame and the app bar's contents button is built in the same
/// one: the button listens and appears once there are two or more headings
/// (K9). [WikiMarkdown] resets it whenever the content changes, so a page
/// never inherits the previous page's contents.
class WikiHeadings extends ChangeNotifier {
  final _headings = <WikiHeading>[];

  List<WikiHeading> get all => List.unmodifiable(_headings);

  /// K9: the contents button appears from two headings up — one heading is
  /// the page title again and a sheet with one row is not worth a tap.
  List<WikiHeading> get contents => [
    for (final h in _headings)
      if (h.level <= 3) h,
  ];

  bool get hasContents => contents.length >= 2;

  void reset(Iterable<WikiHeading> headings) {
    _headings
      ..clear()
      ..addAll(headings);
    // The body is built inside a frame; notifying a listener that is being
    // built in the same frame is the "setState during build" assert.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
  }

  /// The heading an anchor names, matched the way the wiki matches them.
  WikiHeading? find(String anchor) {
    for (final h in _headings) {
      if (WikiLink.anchorMatches(h.anchor, anchor)) return h;
    }
    return null;
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// One section of a page: the heading that opens it (null for the text
/// before the first heading) and the markdown under it.
@immutable
class WikiSection {
  const WikiSection({required this.markdown, this.heading});

  final String markdown;
  final WikiHeading? heading;
}

/// The handle the reader keeps on a body it cannot reach with a
/// `GlobalKey`.
///
/// On a short page every heading is built, so `Scrollable.ensureVisible` on
/// its key is enough and this does nothing. On a long one the body is a
/// `SuperListView` and the heading four screens down has not been built at
/// all: the only way there is the list's own `jumpToItem`, which is what
/// this exposes (W-C item 11).
class WikiBodyController {
  _WikiMarkdownState? _state;

  /// True while the body on screen is the lazy one.
  bool get isLazy => _state?._lazy ?? false;

  /// Scrolls to the heading [anchor] names. False when this body does not
  /// have it, so the caller can fall back to its own `ensureVisible`.
  bool jumpToAnchor(String anchor) {
    final state = _state;
    if (state == null || !state._lazy) return false;
    return state._jumpToAnchor(anchor);
  }

  /// Scrolls to one of [WikiMarkdown.split]'s sections, for the find bar.
  bool jumpToSection(int section) {
    final state = _state;
    if (state == null || !state._lazy) return false;
    return state._jumpToSection(section);
  }

  void _attach(_WikiMarkdownState state) => _state = state;

  void _detach(_WikiMarkdownState state) {
    if (identical(_state, state)) _state = null;
  }
}

/// The wiki's markdown body.
///
/// W-C fills the seam W-B left: the page's front matter, `[[_TOC_]]` and
/// `[[_TOSP_]]`, the `:::` fence family and the mermaid/math fences as
/// placeholder cards (K3), highlighted and copyable code, the wrapping and
/// panning table (K10), a small inline-HTML subset with HTML blocks through
/// `HtmlWidget`, sized attachment images, GUID mentions and find-in-page.
///
/// Three rules are settled and survive every rewrite:
///
/// * the body is **never** `MarkdownBody(selectable: true)` — the W-A timing
///   spike measured it at about 7x the whole-document layout — so selection
///   comes from one [SelectionArea] around a plain body;
/// * headings are split into [WikiSection]s so each one carries a
///   `GlobalKey`, which is what `#anchor` links and the contents sheet
///   scroll to. A heading inside a fenced code block is not a heading;
/// * every syntax list, builder map and style sheet is built **per body**.
///   `flutter_markdown_plus` appends block-builder keys to one global list
///   and `markdown` keeps its syntaxes in a set, so a shared `const` list is
///   how a construct ends up parsed twice.
class WikiMarkdown extends StatefulWidget {
  const WikiMarkdown({
    super.key,
    required this.content,
    required this.wiki,
    required this.pagePath,
    this.headings,
    this.subPages = const [],
    this.onOpenPage,
    this.onOpenAnchor,
    this.onOpenAttachment,
    this.onOpenMention,
    this.onOpenOnWeb,
    this.onOpenQuery,
    this.attachmentUri,
    this.headers = const {},
    this.names = const {},
    this.find,
    this.bodyController,
    this.lazyLeading = const [],
    this.lazyTrailing = const [],
  });

  /// The raw markdown of the page.
  final String content;

  /// The wiki the page belongs to — a code wiki's attachments and links
  /// resolve against its branch and mapped path (K8).
  final Wiki wiki;

  /// The page's own path (title form); every relative href resolves against
  /// its folder.
  final String pagePath;

  /// Filled as the body builds, so the app bar can offer the contents sheet
  /// and an anchor link has something to scroll to.
  final WikiHeadings? headings;

  /// The page's child pages, which is what `[[_TOSP_]]` draws.
  final List<WikiPageNode> subPages;

  /// Another page of this wiki, with the anchor the link carried.
  final void Function(String path, {String? anchor})? onOpenPage;

  /// A heading on this page.
  final void Function(String anchor)? onOpenAnchor;

  /// A file under `/.attachments/`: the image viewer or the share sheet.
  final void Function(String path)? onOpenAttachment;

  /// `#123` and `!456`, which open the work item and the pull request the
  /// app already has routes for (research/20 §4.2).
  final void Function(MentionKind kind, String id)? onOpenMention;

  /// This page on the web — every placeholder card offers it (K3).
  final VoidCallback? onOpenOnWeb;

  /// A `::: query-table {guid}`, opened in the Work items page (K3).
  final void Function(String queryId)? onOpenQuery;

  /// The authenticated URL an attachment image is fetched from. There is no
  /// wiki route for attachments: they are files in the wiki's git
  /// repository (research/20 §1), so the page has to supply this.
  final Uri Function(String path)? attachmentUri;

  /// `Authorization` for those image fetches. Without it the service answers
  /// a sign-in page, not a 401, and the image draws as nothing.
  final Map<String, String> headers;

  /// Lower-cased identity GUID → display name, for `@<guid>`.
  final Map<String, String> names;

  /// Find-in-page (K4). Null leaves the body unhighlighted.
  final WikiFindController? find;

  /// The handle the reader uses to reach a section of the **lazy** body.
  final WikiBodyController? bodyController;

  /// Rows the lazy body puts above the page (the reader's header), so a long
  /// page keeps one scroll view rather than a pinned header over a list.
  /// Ignored on a short page, which the reader scrolls itself.
  final List<Widget> lazyLeading;

  /// Rows the lazy body puts below the page (the reader's footer).
  final List<Widget> lazyTrailing;

  /// Above this many characters the body stops being one `MarkdownBody` and
  /// becomes a lazily built list of sections.
  ///
  /// The W-A spike measured the first frame of a `SelectionArea` body at
  /// about 8.7 ms per KB and super-linear beyond that, so ~100 KB is where a
  /// page stops opening instantly (`wiki_markdown_perf_test.dart`).
  static const lazyThreshold = 100 * 1024;

  /// Above this, nothing is rendered until the reader asks: a megabyte of
  /// markdown is a data dump, and even the lazy body has to parse every
  /// section to split it.
  static const refuseThreshold = 1024 * 1024;

  static bool isLazy(String content) =>
      content.length > lazyThreshold && content.length <= refuseThreshold;

  static bool isTooLong(String content) => content.length > refuseThreshold;

  /// The page split at its headings, fences respected.
  ///
  /// Static and pure so the split is unit-testable without a widget tree —
  /// it is the part W-C has to keep working.
  static List<WikiSection> split(String content) {
    final sections = <WikiSection>[];
    final buffer = StringBuffer();
    WikiHeading? current;
    var fence = '';
    void flush() {
      final text = buffer.toString();
      if (current != null || text.trim().isNotEmpty) {
        sections.add(WikiSection(markdown: text, heading: current));
      }
      buffer.clear();
    }

    for (final line in content.split(_newline)) {
      final trimmed = line.trimLeft();
      if (fence.isNotEmpty) {
        if (trimmed.startsWith(fence)) fence = '';
        buffer.writeln(line);
        continue;
      }
      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        fence = trimmed.substring(0, 3);
        buffer.writeln(line);
        continue;
      }
      final match = _atx.firstMatch(line);
      if (match == null) {
        buffer.writeln(line);
        continue;
      }
      flush();
      final text = headingText(
        match[2]!.trim().replaceAll(RegExp(r'\s*#+\s*$'), ''),
      );
      current = WikiHeading(
        level: match[1]!.length,
        text: text,
        anchor: WikiLink.anchorId(text),
      );
      buffer.writeln(line);
    }
    flush();
    return sections;
  }

  /// A heading's own words, without the inline markdown that styles them.
  ///
  /// Both the contents row's label and the anchor the wiki gives a heading
  /// come from the **rendered** text, not the source. A real page whose
  /// heading reads `**_Optional step for after the meeting_**` listed the
  /// asterisks and the underscores in the contents sheet and in an in-place
  /// `[[_TOC_]]` (found on the iPhone, 2026-09-15).
  ///
  /// A link keeps its label; `**`, `*`, `~~` and backticks always go. An
  /// underscore goes only at a word boundary, so `snake_case` in a heading
  /// keeps its own.
  static String headingText(String source) {
    var text = source.replaceAllMapped(
      RegExp(r'!?\[([^\]]*)\]\([^)]*\)'),
      (m) => m[1] ?? '',
    );
    text = text.replaceAll(RegExp(r'\*\*|~~|\*|`'), '');
    text = text.replaceAll(
      RegExp(r'(?<![A-Za-z0-9])__?|__?(?![A-Za-z0-9])'),
      '',
    );
    return text.trim();
  }

  /// ATX headings only. Setext (`===` under a line) is not used anywhere in
  /// the client wiki's 134 pages (research/20 §1 census) and splitting on it
  /// would need a look-ahead the fence tracking does not have.
  static final _atx = RegExp(r'^ {0,3}(#{1,6})\s+(.*)$');

  static final _newline = RegExp(r'\r\n|\r|\n');

  @override
  State<WikiMarkdown> createState() => _WikiMarkdownState();
}

class _WikiMarkdownState extends State<WikiMarkdown> {
  late List<WikiSection> _sections;
  WikiFrontMatter? _matter;
  String _body = '';

  final _listController = ListController();
  final _scroll = ScrollController();

  /// Set once the reader has answered the "Load anyway" card.
  bool _loadAnyway = false;

  /// The find pass the sections on screen were parsed for.
  int _findPass = -1;

  bool get _lazy => !_loadAnyway && WikiMarkdown.isLazy(_body);

  bool get _tooLong => !_loadAnyway && WikiMarkdown.isTooLong(_body);

  @override
  void initState() {
    super.initState();
    _resplit();
    widget.bodyController?._attach(this);
    widget.find?.addListener(_onFind);
  }

  @override
  void didUpdateWidget(WikiMarkdown old) {
    super.didUpdateWidget(old);
    if (old.bodyController != widget.bodyController) {
      old.bodyController?._detach(this);
      widget.bodyController?._attach(this);
    }
    if (old.find != widget.find) {
      old.find?.removeListener(_onFind);
      widget.find?.addListener(_onFind);
    }
    if (old.content != widget.content || old.headings != widget.headings) {
      _loadAnyway = false;
      _resplit();
    }
  }

  @override
  void dispose() {
    widget.find?.removeListener(_onFind);
    widget.bodyController?._detach(this);
    _listController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _resplit() {
    final (matter, body) = WikiFrontMatter.split(widget.content);
    _matter = matter;
    _body = WikiPreprocess.run(body);
    _sections = WikiMarkdown.split(_body);
    widget.headings?.reset([
      for (final s in _sections)
        if (s.heading != null) s.heading!,
    ]);
    _publishFindCounts();
  }

  // ----------------------------------------------------------------- find

  void _onFind() {
    if (mounted) setState(() {});
  }

  /// The lazy body cannot count what it has not built, so its hit count is
  /// scanned off the source instead (K4). The short body counts the runs it
  /// actually drew, which is exact.
  void _publishFindCounts() {
    final find = widget.find;
    if (find == null) return;
    if (_lazy) {
      find.useSectionCounts([
        for (final section in _sections)
          wikiCountMatches(section.markdown, find.term),
      ]);
    } else {
      find.useDrawnHits();
    }
  }

  bool _jumpToAnchor(String anchor) {
    for (var i = 0; i < _sections.length; i++) {
      final heading = _sections[i].heading;
      if (heading == null) continue;
      if (WikiLink.anchorMatches(heading.anchor, anchor)) {
        return _jumpToSection(i);
      }
    }
    return false;
  }

  bool _jumpToSection(int section) {
    if (!_lazy || section < 0 || section >= _sections.length) return false;
    _listController.jumpToItem(
      index: _leadingCount + section,
      scrollController: _scroll,
      alignment: 0.05,
    );
    return true;
  }

  /// The rows the lazy list puts before the first section.
  int get _leadingCount =>
      widget.lazyLeading.length + (_matter == null ? 0 : 1);

  // ------------------------------------------------------------ link taps

  /// True when the reader took [href] itself; false sends it on.
  bool _onTapLink(String? href) {
    if (href == null || href.isEmpty) return false;
    final mention = MentionHref.parse(href);
    if (mention != null) {
      widget.onOpenMention?.call(mention.$1, mention.$2);
      return true;
    }
    final relative = WikiLink.resolve(href, pagePath: widget.pagePath);
    if (relative != null) {
      switch (relative.kind) {
        case WikiHrefKind.anchor:
          widget.onOpenAnchor?.call(relative.anchor!);
        case WikiHrefKind.page:
          widget.onOpenPage?.call(relative.path, anchor: relative.anchor);
        case WikiHrefKind.attachment:
          widget.onOpenAttachment?.call(relative.path);
      }
      return true;
    }
    // An absolute URL. A web link into *this* wiki is a page of this wiki,
    // so it opens in the reader rather than the browser (K5).
    final link = WikiLink.parse(href);
    if (link != null && _isThisWiki(link)) {
      final path = link.path;
      if (path != null && path.isNotEmpty) {
        widget.onOpenPage?.call(path, anchor: link.anchor);
        return true;
      }
    }
    final uri = Uri.tryParse(href);
    if (uri != null && uri.hasScheme) {
      unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
      return true;
    }
    return false;
  }

  /// A parsed wiki URL naming the wiki on screen — by GUID or by name, both
  /// of which the service accepts on every route (spike w37).
  bool _isThisWiki(WikiLink link) {
    final named = link.wikiIdOrName.toLowerCase();
    return named == widget.wiki.id.toLowerCase() ||
        named == widget.wiki.name.toLowerCase();
  }

  // --------------------------------------------------------------- images

  Widget _image(Uri uri, String? title, String? alt) {
    final (href, maxWidth, maxHeight) = _sized(uri);
    final resolved = WikiLink.resolve(href, pagePath: widget.pagePath);
    final build = widget.attachmentUri;
    final constraints = BoxConstraints(
      maxWidth: maxWidth ?? double.infinity,
      maxHeight: maxHeight == null
          ? _imageMaxHeight
          : (maxHeight < _imageMaxHeight ? maxHeight : _imageMaxHeight),
    );
    if (resolved == null || !resolved.isAttachment || build == null) {
      return ConstrainedBox(
        constraints: constraints,
        child: Image.network(
          href,
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          semanticLabel: alt,
          errorBuilder: (context, error, stack) => _brokenImage(context, alt),
        ),
      );
    }
    final url = build(resolved.path).toString();
    final image = ConstrainedBox(
      constraints: constraints,
      child: Image(
        image: CachedNetworkImageProvider(url, headers: widget.headers),
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        semanticLabel: alt,
        errorBuilder: (context, error, stack) =>
            _brokenImage(context, alt ?? _fileName(resolved.path)),
      ),
    );
    final open = widget.onOpenAttachment;
    if (open == null) return image;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => open(resolved.path),
      child: image,
    );
  }

  /// Splits the `=WxH` size [WikiPreprocess] folded into the query back off
  /// the source, and reads it as a **maximum** rather than a size: a wiki
  /// author's `=1200x800` means "as big as it goes", and honouring it
  /// literally would push the page sideways on a phone.
  (String, double?, double?) _sized(Uri uri) {
    final params = Map<String, String>.of(uri.queryParameters);
    final width = double.tryParse(
      params.remove(WikiImageSize.widthParam) ?? '',
    );
    final height = double.tryParse(
      params.remove(WikiImageSize.heightParam) ?? '',
    );
    if (width == null && height == null) return (uri.toString(), null, null);
    final stripped = uri.replace(
      queryParameters: params.isEmpty ? null : params,
    );
    // `Uri.replace` with no parameters still leaves a bare `?`.
    var href = stripped.toString();
    if (params.isEmpty && href.endsWith('?')) {
      href = href.substring(0, href.length - 1);
    }
    return (href, width, height);
  }

  static String _fileName(String path) {
    final at = path.lastIndexOf('/');
    return at < 0 ? path : path.substring(at + 1);
  }

  /// An image in a page is not a gallery: a tall screenshot would push the
  /// rest of the page off the screen. The viewer shows it full size.
  static const _imageMaxHeight = 360.0;

  /// An image that could not be fetched: the glyph and what it was of.
  ///
  /// Sized against the box it is given, because an author's `=16x16` badge
  /// leaves 16 dp and the icon and its label do not fit in it — the row
  /// overflowed with the red stripes on the first sized image that failed.
  Widget _brokenImage(BuildContext context, String? alt) {
    final theme = Theme.of(context);
    final label = (alt ?? '').trim().isEmpty ? 'Image' : alt!.trim();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width < 96) {
          return Icon(
            Icons.broken_image_outlined,
            size: width.isFinite && width < 20 ? width : 20,
            color: theme.colorScheme.error,
            semanticLabel: label,
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 20,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: Spacing.xs),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------- build

  WikiMarkdownConfig _config() => WikiMarkdownConfig(
    cell: _cell,
    tocHeadings: [
      for (final section in _sections)
        if (section.heading != null)
          (
            level: section.heading!.level,
            text: section.heading!.text,
            anchor: section.heading!.anchor,
          ),
    ],
    subPages: widget.subPages,
    onOpenAnchor: widget.onOpenAnchor,
    onOpenPage: (path) => widget.onOpenPage?.call(path),
    onOpenOnWeb: widget.onOpenOnWeb,
    onOpenQuery: widget.onOpenQuery,
    onOpenUrl: (uri) =>
        unawaited(launchUrl(uri, mode: LaunchMode.externalApplication)),
    imageUrl: widget.attachmentUri == null
        ? null
        : (src) {
            final resolved = WikiLink.resolve(src, pagePath: widget.pagePath);
            if (resolved == null || !resolved.isAttachment) return src;
            return widget.attachmentUri!(resolved.path).toString();
          },
    headers: widget.headers,
    onTapHref: _onTapLink,
    find: widget.find,
  );

  /// One table cell: the same body, minus the block constructs a cell cannot
  /// hold. Inline only, so a cell stays a line of text with its links,
  /// mentions, code and `<br>` intact.
  Widget _cell(BuildContext context, String markdown, TextAlign align) {
    if (markdown.trim().isEmpty) return const SizedBox.shrink();
    return MarkdownBody(
      data: markdown,
      selectable: false,
      shrinkWrap: true,
      fitContent: true,
      styleSheet: wikiStyleSheet(context).copyWith(
        textAlign: switch (align) {
          TextAlign.center => WrapAlignment.center,
          TextAlign.right => WrapAlignment.end,
          _ => WrapAlignment.start,
        },
        pPadding: EdgeInsets.zero,
      ),
      extensionSet: md.ExtensionSet.gitHubWeb,
      inlineSyntaxes: wikiInlineSyntaxes(findTerm: widget.find?.term),
      builders: wikiBuilders(_config()),
      imageBuilder: _image,
      onTapLink: (text, href, title) => _onTapLink(href),
    );
  }

  Widget _section(BuildContext context, WikiSection section) {
    final pass = widget.find?.pass ?? 0;
    return MarkdownBody(
      // `MarkdownBody` re-parses on its data or its style sheet, never on
      // its syntaxes, so a new find term needs a new element to take.
      key: ValueKey('wiki-section-$pass'),
      data: section.markdown,
      selectable: false,
      styleSheet: wikiStyleSheet(context),
      // Heading ids, `:rocket:`, footnotes and strikethrough all come from
      // here; the wiki's own extensions are the block and inline syntaxes
      // beside it.
      extensionSet: md.ExtensionSet.gitHubWeb,
      blockSyntaxes: wikiBlockSyntaxes(),
      inlineSyntaxes: wikiInlineSyntaxes(findTerm: widget.find?.term),
      builders: wikiBuilders(_config()),
      imageBuilder: _image,
      onTapLink: (text, href, title) => _onTapLink(href),
    );
  }

  Widget _loadAnywayCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: Radii.card,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This page is very large', style: theme.textTheme.titleSmall),
          const SizedBox(height: Spacing.xs),
          Text(
            '${(_body.length / 1024).round()} KB of markdown. Rendering it '
            'may take a while on this device.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          FilledButton(
            onPressed: () => setState(() => _loadAnyway = true),
            child: const Text('Load anyway'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_tooLong) return _loadAnywayCard(context);
    final find = widget.find;
    // A new pass means the sections are re-keyed and will re-register their
    // hits; every other rebuild must leave the keys of the last pass alone,
    // or the up/down buttons lose the page. `settle` is scheduled only for a
    // real pass, so its own notification cannot start another one.
    if (find != null && _findPass != find.pass) {
      _findPass = find.pass;
      _publishFindCounts();
      find.beginPass();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) find.settle();
      });
    }

    // One SelectionArea around plain bodies: `selectable: true` builds a
    // `SelectableText.rich` per block and measured ~7x slower (W-A spike).
    return SelectionArea(
      child: MentionScope(
        names: widget.names,
        child: _lazy ? _lazyBody(context) : _eagerBody(context),
      ),
    );
  }

  Widget _eagerBody(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_matter != null) WikiFrontMatterView(matter: _matter!),
      for (final section in _sections)
        KeyedSubtree(
          key: section.heading?.key,
          child: _section(context, section),
        ),
    ],
  );

  /// The long-page body: one row per section, built as it comes into view,
  /// with the reader's header and footer as rows of the same list so the
  /// page keeps a single scroll (W-C item 11).
  Widget _lazyBody(BuildContext context) {
    final leading = widget.lazyLeading.length;
    final matter = _matter == null ? 0 : 1;
    final count =
        leading + matter + _sections.length + widget.lazyTrailing.length;
    return SuperListView.builder(
      controller: _scroll,
      listController: _listController,
      itemCount: count,
      padding: EdgeInsets.only(bottom: scrollEndPadding(context).bottom),
      itemBuilder: (context, index) {
        if (index < leading) return widget.lazyLeading[index];
        if (matter == 1 && index == leading) {
          return WikiFrontMatterView(matter: _matter!);
        }
        final at = index - leading - matter;
        if (at < _sections.length) {
          final section = _sections[at];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: KeyedSubtree(
              key: section.heading?.key,
              child: _section(context, section),
            ),
          );
        }
        return widget.lazyTrailing[at - _sections.length];
      },
    );
  }
}
