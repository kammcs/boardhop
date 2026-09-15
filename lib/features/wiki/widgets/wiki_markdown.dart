import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/text/mention.dart';
import '../../../core/text/wiki_link.dart';
import '../../../data/models/wiki.dart';
import '../../shared/mention/mention_markdown.dart';
import '../../shared/mention/mention_style.dart';

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

/// The wiki's markdown body.
///
/// **This is the seam W-C replaces.** Everything the reader needs from a
/// rendered page is already expressed here — the resolved links, the
/// attachment images, the mention routing and the heading registry — so
/// W-C's job is to change what happens *inside* this widget (the wiki's
/// `[[_TOC_]]`, `:::` fences, tables, HTML subset and placeholder cards,
/// research/20 K3/K10) without touching a caller.
///
/// Two rules are settled and must survive that rewrite:
///
/// * the body is **never** `MarkdownBody(selectable: true)` — the W-A timing
///   spike measured it at about 7x the whole-document layout — so selection
///   comes from one [SelectionArea] around a plain body;
/// * headings are split into [WikiSection]s so each one carries a
///   `GlobalKey`, which is what `#anchor` links and the contents sheet
///   scroll to. A heading inside a fenced code block is not a heading.
class WikiMarkdown extends StatefulWidget {
  const WikiMarkdown({
    super.key,
    required this.content,
    required this.wiki,
    required this.pagePath,
    this.headings,
    this.onOpenPage,
    this.onOpenAnchor,
    this.onOpenAttachment,
    this.onOpenMention,
    this.attachmentUri,
    this.headers = const {},
    this.names = const {},
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

  /// Another page of this wiki, with the anchor the link carried.
  final void Function(String path, {String? anchor})? onOpenPage;

  /// A heading on this page.
  final void Function(String anchor)? onOpenAnchor;

  /// A file under `/.attachments/`: the image viewer or the share sheet.
  final void Function(String path)? onOpenAttachment;

  /// `#123` and `!456`, which open the work item and the pull request the
  /// app already has routes for (research/20 §4.2).
  final void Function(MentionKind kind, String id)? onOpenMention;

  /// The authenticated URL an attachment image is fetched from. There is no
  /// wiki route for attachments: they are files in the wiki's git
  /// repository (research/20 §1), so the page has to supply this.
  final Uri Function(String path)? attachmentUri;

  /// `Authorization` for those image fetches. Without it the service answers
  /// a sign-in page, not a 401, and the image draws as nothing.
  final Map<String, String> headers;

  /// Lower-cased identity GUID → display name, for `@<guid>`.
  final Map<String, String> names;

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
      final text = match[2]!.trim().replaceAll(RegExp(r'\s*#+\s*$'), '');
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

  @override
  void initState() {
    super.initState();
    _resplit();
  }

  @override
  void didUpdateWidget(WikiMarkdown old) {
    super.didUpdateWidget(old);
    if (old.content != widget.content || old.headings != widget.headings) {
      _resplit();
    }
  }

  void _resplit() {
    _sections = WikiMarkdown.split(widget.content);
    widget.headings?.reset([
      for (final s in _sections)
        if (s.heading != null) s.heading!,
    ]);
  }

  // ------------------------------------------------------------ link taps

  void _onTapLink(String? href) {
    if (href == null || href.isEmpty) return;
    final mention = MentionHref.parse(href);
    if (mention != null) {
      widget.onOpenMention?.call(mention.$1, mention.$2);
      return;
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
      return;
    }
    // An absolute URL. A web link into *this* wiki is a page of this wiki,
    // so it opens in the reader rather than the browser (K5).
    final link = WikiLink.parse(href);
    if (link != null && _isThisWiki(link)) {
      final path = link.path;
      if (path != null && path.isNotEmpty) {
        widget.onOpenPage?.call(path, anchor: link.anchor);
        return;
      }
    }
    final uri = Uri.tryParse(href);
    if (uri != null && uri.hasScheme) {
      unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
    }
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
    final href = uri.toString();
    final resolved = WikiLink.resolve(href, pagePath: widget.pagePath);
    final build = widget.attachmentUri;
    if (resolved == null || !resolved.isAttachment || build == null) {
      return Image.network(
        href,
        fit: BoxFit.scaleDown,
        semanticLabel: alt,
        errorBuilder: (context, error, stack) => _brokenImage(context, alt),
      );
    }
    final url = build(resolved.path).toString();
    final image = ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _imageMaxHeight),
      child: Image(
        image: CachedNetworkImageProvider(url, headers: widget.headers),
        fit: BoxFit.scaleDown,
        semanticLabel: alt,
        errorBuilder: (context, error, stack) => _brokenImage(context, alt),
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

  /// An image in a page is not a gallery: a tall screenshot would push the
  /// rest of the page off the screen. The viewer shows it full size.
  static const _imageMaxHeight = 360.0;

  Widget _brokenImage(BuildContext context, String? alt) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.broken_image_outlined,
          size: 20,
          color: theme.colorScheme.error,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            (alt ?? '').trim().isEmpty ? 'Image' : alt!.trim(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // One SelectionArea around plain bodies: `selectable: true` builds a
    // `SelectableText.rich` per block and measured ~7x slower (W-A spike).
    return SelectionArea(
      child: MentionScope(
        names: widget.names,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final section in _sections)
              KeyedSubtree(
                key: section.heading?.key,
                child: MarkdownBody(
                  data: section.markdown,
                  selectable: false,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                      .copyWith(a: mentionTextStyle(context)),
                  inlineSyntaxes: [MentionSyntax()],
                  builders: {MentionSyntax.personTag: MentionPersonBuilder()},
                  imageBuilder: _image,
                  onTapLink: (text, href, title) => _onTapLink(href),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
