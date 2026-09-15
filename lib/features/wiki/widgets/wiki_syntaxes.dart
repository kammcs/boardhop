import 'package:markdown/markdown.dart' as md;

/// The element tags the wiki's own syntaxes parse into, and the attributes
/// they carry.
///
/// They are deliberately not HTML tags: `flutter_markdown_plus` keeps one
/// **global** list of block tags and appends every block builder's key to it
/// (`builder.dart`, `MarkdownBuilder.build`), so a tag reused from the HTML
/// vocabulary would change how every other Markdown body in the app — a
/// comment, a README — lays that tag out. A `wiki` prefix cannot collide.
abstract final class WikiTags {
  /// `[[_TOC_]]`, the page's own table of contents.
  static const toc = 'wikiToc';

  /// `[[_TOSP_]]`, the page's child pages.
  static const subPages = 'wikiTosp';

  /// A construct the app does not render: mermaid, math, video, a query
  /// table (research/20 K3). Carries [kindAttribute] and [infoAttribute];
  /// its text is the source.
  static const placeholder = 'wikiPlaceholder';

  /// A pipe table, captured whole so the wiki's own table builder can lay it
  /// out (K10). Its text is the raw markdown of the table.
  static const table = 'wikiTable';

  /// A block of raw HTML, rendered through `HtmlWidget`. Its text is the
  /// raw HTML.
  static const html = 'wikiHtml';

  /// `$x$`, drawn as a monospace chip rather than typeset.
  static const math = 'wikiMath';

  /// One find-in-page hit.
  static const mark = 'mark';

  /// Inline HTML that only changes how a run looks.
  static const inlineTags = <String>{'u', 'sup', 'sub', 'ins', 'small', 'mark'};

  static const kindAttribute = 'kind';
  static const infoAttribute = 'info';
}

/// What a [WikiTags.placeholder] stands in for (research/20 K3).
enum WikiPlaceholderKind {
  mermaid('Diagram (mermaid)'),
  math('Formula'),
  video('Video'),
  queryTable('Query results'),
  other('Unsupported block');

  const WikiPlaceholderKind(this.label);

  /// The card's title. Says what the block *is*, so the reader knows what
  /// Open on web will show them.
  final String label;

  static WikiPlaceholderKind parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'mermaid':
        return WikiPlaceholderKind.mermaid;
      case 'math':
      case 'latex':
      case 'katex':
        return WikiPlaceholderKind.math;
      case 'video':
        return WikiPlaceholderKind.video;
      case 'query-table':
      case 'querytable':
        return WikiPlaceholderKind.queryTable;
      default:
        return WikiPlaceholderKind.other;
    }
  }
}

// ---------------------------------------------------------------- front matter

/// The YAML front matter of a wiki page, read by hand.
///
/// No `yaml` package: research/20 §2 settles that W-C adds no dependency,
/// and the client wiki has **zero** front matter blocks (§1 census) — this
/// exists for the scratch page and for pages pushed from a repository, whose
/// front matter is a handful of scalars and one list. Anything with more
/// shape than that is kept verbatim in [raw] and shown as source, which is
/// honest rather than half-parsed.
class WikiFrontMatter {
  const WikiFrontMatter({
    this.tags = const [],
    this.entries = const [],
    this.raw,
  });

  /// The `tags:` (or `tag:`) list, drawn as a chip row.
  final List<String> tags;

  /// Every other scalar `key: value`, drawn as a small two-column table.
  final List<MapEntry<String, String>> entries;

  /// The lines that were not a scalar or a list item — a nested object,
  /// say. Shown as a code card so nothing is silently dropped.
  final String? raw;

  bool get isEmpty =>
      tags.isEmpty && entries.isEmpty && (raw == null || raw!.isEmpty);

  static final _fence = RegExp(r'^(---|\.\.\.)\s*$');
  static final _scalar = RegExp(
    r'^([A-Za-z0-9_][A-Za-z0-9_.\- ]*)\s*:\s*(.*)$',
  );
  static final _item = RegExp(r'^\s*-\s+(.*)$');
  static final _newline = RegExp(r'\r\n|\r|\n');

  /// Splits [content] into its front matter (null when there is none) and
  /// the markdown body.
  ///
  /// A block only counts when the **very first** line is `---` and a closing
  /// `---` or `...` follows: a page that opens with a horizontal rule, or a
  /// setext heading whose underline is `---`, must not lose its first
  /// paragraph.
  static (WikiFrontMatter?, String) split(String content) {
    final text = content.startsWith('﻿') ? content.substring(1) : content;
    final lines = text.split(_newline);
    if (lines.isEmpty || lines.first.trimRight() != '---') {
      return (null, text);
    }
    var end = -1;
    for (var i = 1; i < lines.length; i++) {
      if (_fence.hasMatch(lines[i].trimRight())) {
        end = i;
        break;
      }
    }
    if (end < 0) return (null, text);
    final matter = parse(lines.sublist(1, end));
    final body = lines.sublist(end + 1).join('\n');
    // A closing fence followed straight by a heading reads better with the
    // blank line the author would have written.
    return (matter, body.startsWith('\n') ? body : '\n$body');
  }

  /// The lines between the fences.
  static WikiFrontMatter parse(List<String> lines) {
    final tags = <String>[];
    final entries = <MapEntry<String, String>>[];
    final raw = <String>[];
    String? listKey;

    bool isTagKey(String key) {
      final k = key.trim().toLowerCase();
      return k == 'tags' || k == 'tag';
    }

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final item = _item.firstMatch(line);
      if (item != null) {
        final value = _unquote(item[1]!);
        if (listKey != null && isTagKey(listKey)) {
          if (value.isNotEmpty) tags.add(value);
        } else if (listKey != null) {
          entries.add(MapEntry(listKey, value));
        } else {
          raw.add(line);
        }
        continue;
      }
      final scalar = line.startsWith(' ') ? null : _scalar.firstMatch(line);
      if (scalar == null) {
        raw.add(line);
        continue;
      }
      final key = scalar[1]!.trim();
      final value = _unquote(scalar[2]!);
      if (value.isEmpty) {
        listKey = key;
        continue;
      }
      listKey = null;
      if (isTagKey(key)) {
        tags.addAll(
          value
              .replaceAll('[', '')
              .replaceAll(']', '')
              .split(RegExp('[,;]'))
              .map((t) => _unquote(t.trim()))
              .where((t) => t.isNotEmpty),
        );
      } else {
        entries.add(MapEntry(key, value));
      }
    }
    return WikiFrontMatter(
      tags: tags,
      entries: entries,
      raw: raw.isEmpty ? null : raw.join('\n'),
    );
  }

  static String _unquote(String value) {
    final text = value.trim();
    if (text.length >= 2 &&
        ((text.startsWith('"') && text.endsWith('"')) ||
            (text.startsWith("'") && text.endsWith("'")))) {
      return text.substring(1, text.length - 1);
    }
    return text;
  }
}

// ------------------------------------------------------------- preprocessing

/// The query parameters an `=WxH` image size is rewritten into.
///
/// `![x](/a.png =16x16)` is not Markdown: the space before the size makes
/// the whole thing a failed link, which is why it printed literally
/// (research/20 §1). `flutter_markdown_plus` splits a `#WxH` **fragment**
/// off the source before the image builder ever sees it (`builder.dart`
/// `_buildImage`), so the size has to travel as a query instead — the
/// builder reads it back and treats it as a **maximum**, because a wiki
/// author's 16x16 is a badge but their 1200x800 is "full width".
abstract final class WikiImageSize {
  static const widthParam = 'boardhopMaxWidth';
  static const heightParam = 'boardhopMaxHeight';

  /// `=16x16`, `=16x`, `=x16`.
  static final pattern = RegExp(r'\s+=(\d+)?x(\d+)?$');
}

/// Everything that has to happen to a page's markdown **before** it is
/// parsed, because no syntax can express it.
///
/// Keeps the two jobs separate so both are unit-testable on their own.
abstract final class WikiPreprocess {
  static final _destination = RegExp(r'(!?)\[([^\]\n]*)\]\(([^)\n]*)\)');
  static final _title = RegExp('''\\s+(["'])(.*)\\1\$''');
  static final _toc = RegExp(r'^[ \t]*\[\[_TOC_\]\][ \t]*$', multiLine: true);

  /// The whole pre-parse pass.
  static String run(String content) => keepFirstToc(destinations(content));

  /// Repairs the two things a wiki author writes that CommonMark refuses.
  ///
  /// * `![alt](dest =WxH "title")` — the space before the size makes the
  ///   whole thing a failed link, so the size moves into a query;
  /// * `[Deep child](/Boardhop/Links/Deep child)` — a **space in the
  ///   destination**, which the web resolves and the parser does not. Both
  ///   printed literally on the scratch pages; the spaces are percent-encoded
  ///   and `WikiLink.resolve` decodes them back.
  static String destinations(String content) {
    return content.replaceAllMapped(_destination, (match) {
      final bang = match[1]!;
      final alt = match[2]!;
      var inside = match[3]!.trim();
      if (inside.isEmpty) return match[0]!;

      String title = '';
      final titled = _title.firstMatch(inside);
      if (titled != null) {
        title = ' ${titled[1]}${titled[2]}${titled[1]}';
        inside = inside.substring(0, titled.start).trim();
      }

      final query = <String>[];
      // A size only means anything on an image.
      final size = bang.isEmpty
          ? null
          : WikiImageSize.pattern.firstMatch(inside);
      if (size != null) {
        if (size[1] != null) {
          query.add('${WikiImageSize.widthParam}=${size[1]}');
        }
        if (size[2] != null) {
          query.add('${WikiImageSize.heightParam}=${size[2]}');
        }
        inside = inside.substring(0, size.start).trim();
      }
      if (inside.isEmpty) return match[0]!;

      // `<…>` is the escape hatch the spec gives a destination with spaces;
      // the wiki's own authors do not use it, so the spaces are encoded.
      if (inside.startsWith('<') && inside.endsWith('>')) {
        inside = inside.substring(1, inside.length - 1);
      }
      var dest = inside.replaceAll(' ', '%20');
      if (query.isNotEmpty) {
        dest += '${dest.contains('?') ? '&' : '?'}${query.join('&')}';
      }
      return '$bang[$alt]($dest$title)';
    });
  }

  /// Only the first `[[_TOC_]]` is a table of contents; the wiki ignores the
  /// rest, and two contents lists on one page would both be right and both
  /// be noise. Later ones are dropped.
  static String keepFirstToc(String content) {
    var seen = false;
    return content.replaceAllMapped(_toc, (match) {
      if (!seen) {
        seen = true;
        return match[0]!;
      }
      return '';
    });
  }
}

// ------------------------------------------------------------ block syntaxes

/// `[[_TOC_]]` on a line of its own.
///
/// Case-sensitive, as the wiki is: `[[_toc_]]` is text. The underscores are
/// why it printed as `[[TOC]]` before — the emphasis syntax ate them.
class WikiTocSyntax extends md.BlockSyntax {
  const WikiTocSyntax();

  @override
  RegExp get pattern => _pattern;

  static final _pattern = RegExp(r'^[ \t]*\[\[_TOC_\]\][ \t]*$');

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance();
    return md.Element.empty(WikiTags.toc);
  }
}

/// `[[_TOSP_]]` on a line of its own: the page's child pages.
class WikiSubPagesSyntax extends md.BlockSyntax {
  const WikiSubPagesSyntax();

  @override
  RegExp get pattern => _pattern;

  static final _pattern = RegExp(r'^[ \t]*\[\[_TOSP_\]\][ \t]*$');

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance();
    return md.Element.empty(WikiTags.subPages);
  }
}

/// The wiki's `::: kind … :::` fence family: `mermaid`, `video` and
/// `query-table {guid}` (research/20 K3).
class WikiDirectiveSyntax extends md.BlockSyntax {
  const WikiDirectiveSyntax();

  @override
  RegExp get pattern => _open;

  static final _open = RegExp(r'^[ \t]*:::[ \t]*(\S+)[ \t]*(.*)$');
  static final _close = RegExp(r'^[ \t]*:::[ \t]*$');

  @override
  bool canParse(md.BlockParser parser) {
    final line = parser.current.content;
    return !_close.hasMatch(line) && _open.hasMatch(line);
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final open = _open.firstMatch(parser.current.content)!;
    parser.advance();
    final body = <String>[];
    while (!parser.isDone && !_close.hasMatch(parser.current.content)) {
      body.add(parser.current.content);
      parser.advance();
    }
    if (!parser.isDone) parser.advance();
    return md.Element.text(WikiTags.placeholder, body.join('\n'))
      ..attributes[WikiTags.kindAttribute] = open[1]!
      ..attributes[WikiTags.infoAttribute] = open[2]!.trim();
  }
}

/// A ```` ```mermaid ```` or ```` ```math ```` fence: a code fence by
/// syntax, a diagram by intent. Everything else stays a code block.
class WikiPlaceholderFenceSyntax extends md.BlockSyntax {
  const WikiPlaceholderFenceSyntax();

  @override
  RegExp get pattern => _open;

  static final _open = RegExp(
    r'^[ \t]{0,3}(`{3,}|~{3,})[ \t]*(mermaid|math|latex|katex)[ \t]*$',
    caseSensitive: false,
  );

  @override
  md.Node parse(md.BlockParser parser) {
    final open = _open.firstMatch(parser.current.content)!;
    final marker = open[1]!.substring(0, 3);
    parser.advance();
    final body = <String>[];
    while (!parser.isDone) {
      final line = parser.current.content;
      if (line.trimLeft().startsWith(marker) && line.trim().length <= 10) {
        parser.advance();
        break;
      }
      body.add(line);
      parser.advance();
    }
    return md.Element.text(WikiTags.placeholder, body.join('\n'))
      ..attributes[WikiTags.kindAttribute] = open[2]!
      ..attributes[WikiTags.infoAttribute] = '';
  }
}

/// A `$$ … $$` display-math block.
class WikiMathBlockSyntax extends md.BlockSyntax {
  const WikiMathBlockSyntax();

  @override
  RegExp get pattern => _open;

  static final _open = RegExp(r'^[ \t]*\$\$(.*)$');

  @override
  md.Node parse(md.BlockParser parser) {
    final first = _open.firstMatch(parser.current.content)!;
    final head = first[1]!.trim();
    parser.advance();
    // `$$ x = 1 $$` on one line.
    if (head.endsWith(r'$$')) {
      return _math(head.substring(0, head.length - 2).trim());
    }
    final body = <String>[if (head.isNotEmpty) head];
    while (!parser.isDone) {
      final line = parser.current.content;
      if (line.trim().endsWith(r'$$')) {
        final rest = line.trim();
        final tail = rest.substring(0, rest.length - 2).trim();
        if (tail.isNotEmpty) body.add(tail);
        parser.advance();
        break;
      }
      body.add(line);
      parser.advance();
    }
    return _math(body.join('\n'));
  }

  md.Element _math(String source) =>
      md.Element.text(WikiTags.placeholder, source)
        ..attributes[WikiTags.kindAttribute] = 'math'
        ..attributes[WikiTags.infoAttribute] = '';
}

/// A pipe table, captured whole.
///
/// The package's own table rendering cannot be replaced by a builder — the
/// `table` branch of `MarkdownBuilder.visitElementAfter` overwrites whatever
/// a builder returned and rebuilds the `Table` from its own row stack — so
/// K10's table has to be parsed out before the stock `TableSyntax` sees it.
class WikiTableSyntax extends md.BlockSyntax {
  const WikiTableSyntax();

  @override
  RegExp get pattern => _row;

  static final _row = RegExp(r'^[ \t]{0,3}\S.*\|');
  static final _delimiter = RegExp(
    r'^[ \t]{0,3}\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$',
  );

  @override
  bool canParse(md.BlockParser parser) {
    if (!_row.hasMatch(parser.current.content)) return false;
    final next = parser.next;
    if (next == null) return false;
    return _delimiter.hasMatch(next.content) && next.content.contains('|');
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final lines = <String>[parser.current.content];
    parser.advance();
    lines.add(parser.current.content);
    parser.advance();
    while (!parser.isDone) {
      final line = parser.current.content;
      if (line.trim().isEmpty || !line.contains('|')) break;
      lines.add(line);
      parser.advance();
    }
    return md.Element.text(WikiTags.table, lines.join('\n'));
  }
}

/// A block of raw HTML the reader hands to `HtmlWidget`.
///
/// Only the handful of block tags the client wiki actually uses (§1 census:
/// `div`, `center`, `br`, `font`, `span`) plus `details` and `img`, which
/// the scratch page exercises. Markdown **inside** the block stays raw; that
/// is the documented gap in research/20 §6.
class WikiHtmlBlockSyntax extends md.BlockSyntax {
  const WikiHtmlBlockSyntax();

  @override
  RegExp get pattern => _open;

  static const tags = <String>{
    'details',
    'div',
    'table',
    'img',
    'p',
    'center',
    'figure',
  };

  /// Tags with no closing form.
  static const voids = <String>{'img'};

  static final _open = RegExp(
    '^[ \\t]{0,3}<(${tags.join('|')})(\\s|>|/>)',
    caseSensitive: false,
  );

  @override
  md.Node parse(md.BlockParser parser) {
    final tag = _open.firstMatch(parser.current.content)![1]!.toLowerCase();
    final open = RegExp('<$tag(\\s|>|/>)', caseSensitive: false);
    final close = RegExp('</$tag\\s*>', caseSensitive: false);
    final lines = <String>[];
    var depth = 0;
    while (!parser.isDone) {
      final line = parser.current.content;
      lines.add(line);
      parser.advance();
      // A void element never closes, so its one line is the whole block —
      // without this an `<img>` on its own swallowed the rest of the page
      // looking for a `</img>` that does not exist.
      if (voids.contains(tag) || line.trimRight().endsWith('/>')) break;
      depth += open.allMatches(line).length - close.allMatches(line).length;
      // Anything else runs to its closing tag, blank lines included — a
      // `<details>` with markdown inside has one.
      if (depth <= 0) break;
    }
    return md.Element.text(WikiTags.html, lines.join('\n'));
  }
}

// ----------------------------------------------------------- inline syntaxes

/// `<br>` and `<br/>` — a line break, which is what an author means by it in
/// a table cell (research/20 §1: 44 uses across the client wiki).
class WikiBrSyntax extends md.InlineSyntax {
  WikiBrSyntax() : super(r'<br\s*/?>', caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty('br'));
    return true;
  }
}

/// The inline HTML subset a wiki page is allowed to style itself with.
///
/// A pair in one match rather than an open/close delimiter pair: the
/// markdown package's delimiter machinery is for `*` and `_`, and a regex
/// over the whole element is enough for the one-line runs the census found.
/// The cost is that markdown **inside** the tag stays raw, which is the same
/// gap the HTML blocks have.
class WikiInlineTagSyntax extends md.InlineSyntax {
  WikiInlineTagSyntax()
    : super(
        r'<(u|sup|sub|del|ins|mark|small|strike|s|b|strong|i|em)'
        r'(?:\s[^<>]*)?>([^<>]*)</\1\s*>',
        caseSensitive: false,
      );

  static const _aliases = <String, String>{
    'b': 'strong',
    'i': 'em',
    'strike': 'del',
    's': 'del',
  };

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final raw = match[1]!.toLowerCase();
    final tag = _aliases[raw] ?? raw;
    parser.addNode(md.Element.text(tag, match[2]!));
    return true;
  }
}

/// Everything else in angle brackets: `<font color=…>`, `<span style=…>`,
/// `<center>` and any tag the reader has no meaning for.
///
/// The tag goes, the text stays. Without this the stock `InlineHtmlSyntax`
/// passes the markup through as text and the reader prints
/// `<font color="red">` at the user.
class WikiStripTagSyntax extends md.InlineSyntax {
  WikiStripTagSyntax() : super(r'</?[A-Za-z][A-Za-z0-9]*(?:\s[^<>]*)?/?>');

  @override
  bool onMatch(md.InlineParser parser, Match match) => true;
}

/// `$E = mc^2$`.
///
/// The pattern insists on at least one of `\ ^ _ { } =` inside, so a
/// sentence about money (`it cost $5 and $7`) is never swallowed — the
/// census found no math at all in the client wiki, and a false positive
/// there would be far worse than an unrendered formula.
class WikiInlineMathSyntax extends md.InlineSyntax {
  WikiInlineMathSyntax()
    : super(
        r'\$(?![\s$])((?:[^$\n\\]|\\[\s\S])*?'
        r'[\\^_{}=]'
        r'(?:[^$\n\\]|\\[\s\S])*?)(?<!\s)\$',
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text(WikiTags.math, match[1]!));
    return true;
  }
}

/// One find-in-page hit (K4).
///
/// Case-insensitive, literal: a reader typing `(` into the find bar is
/// looking for a bracket, not writing a regex.
class WikiMarkSyntax extends md.InlineSyntax {
  WikiMarkSyntax(String term)
    : super(RegExp.escape(term), caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text(WikiTags.mark, match[0]!));
    return true;
  }
}

/// How many times [term] occurs in [text], case-insensitively.
///
/// The find bar's count for the lazy body, where only the sections on screen
/// have been built and the built hits cannot be counted.
int wikiCountMatches(String text, String term) {
  if (term.isEmpty) return 0;
  final needle = term.toLowerCase();
  final haystack = text.toLowerCase();
  var count = 0;
  var at = haystack.indexOf(needle);
  while (at >= 0) {
    count++;
    at = haystack.indexOf(needle, at + needle.length);
  }
  return count;
}
