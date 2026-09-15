import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../../data/models/wiki.dart';
import '../../../theme/theme.dart';
import '../../pull_requests/diff/highlighter.dart';
import 'wiki_syntaxes.dart';

// ------------------------------------------------------------- front matter

/// The `---` block at the top of a page, drawn rather than printed.
///
/// Tags are chips (that is what they are on a work item, and a reader scans
/// them); everything else is a quiet two-column list; anything with more
/// shape than a scalar keeps its own text in a code card.
class WikiFrontMatterView extends StatelessWidget {
  const WikiFrontMatterView({super.key, required this.matter});

  final WikiFrontMatter matter;

  @override
  Widget build(BuildContext context) {
    if (matter.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (matter.tags.isNotEmpty)
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: Spacing.xs),
                  child: Text(
                    'Tags',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final tag in matter.tags)
                  Chip(
                    label: Text(tag),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          for (final entry in matter.entries)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.xs),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${entry.key}: ',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(entry.value, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          if (matter.raw != null)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: WikiSourceBlock(source: matter.raw!),
            ),
          const Divider(height: Spacing.xl),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- contents

/// `[[_TOC_]]`: the page's own headings, indented by level.
///
/// Rendered in place, as the wiki does, *and* offered from the app bar's
/// contents button (K9) — a reader who has scrolled past it still has one.
class WikiTocList extends StatelessWidget {
  const WikiTocList({super.key, required this.headings, this.onTap});

  final List<({int level, String text, String anchor})> headings;
  final void Function(String anchor)? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.boardhopColors;
    if (headings.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: Radii.card,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              0,
              Spacing.md,
              Spacing.xs,
            ),
            child: Text(
              // Not "Contents": the app bar's sheet is called that, and one
              // page must not have two things with the same name.
              'On this page',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final heading in headings)
            InkWell(
              onTap: onTap == null ? null : () => onTap!(heading.anchor),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  Spacing.md + (heading.level - 1).clamp(0, 3) * Spacing.md,
                  Spacing.xs,
                  Spacing.md,
                  Spacing.xs,
                ),
                child: Text(
                  heading.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.mention,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `[[_TOSP_]]`: the page's child pages, as in-app links.
class WikiSubPagesList extends StatelessWidget {
  const WikiSubPagesList({super.key, required this.pages, this.onOpen});

  final List<WikiPageNode> pages;
  final void Function(String path)? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.boardhopColors;
    if (pages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Spacing.md),
        child: Text(
          'This page has no child pages.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final page in pages)
            InkWell(
              onTap: onOpen == null ? null : () => onOpen!(page.path),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                child: Row(
                  children: [
                    Icon(
                      Icons.article_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: Spacing.sm),
                    Flexible(
                      child: Text(
                        page.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.mention,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- placeholders

/// A construct the app does not render, drawn as a card that says what it is
/// and offers the two things a reader can actually do with it (K3).
///
/// Never a spinner and never raw text: a mermaid graph left as its source
/// reads as a rendering fault, and a spinner promises something that is not
/// coming.
class WikiPlaceholderCard extends StatefulWidget {
  const WikiPlaceholderCard({
    super.key,
    required this.kind,
    required this.source,
    this.info = '',
    this.onOpenOnWeb,
    this.onOpenQuery,
    this.onOpenUrl,
  });

  final WikiPlaceholderKind kind;

  /// The block's own text, shown by Show source.
  final String source;

  /// Whatever followed the `:::` marker — the query GUID, for a query table.
  final String info;

  final VoidCallback? onOpenOnWeb;

  /// `::: query-table {guid}` opens the query in the Work items page (K3).
  final void Function(String queryId)? onOpenQuery;

  /// `::: video` opens the embedded URL in the browser.
  final void Function(Uri url)? onOpenUrl;

  /// The `src` of the `<iframe>` or `<video>` a video block wraps.
  static Uri? videoUrl(String source) {
    final match = RegExp(
      '''src\\s*=\\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(source);
    final raw = match?[1]?.trim() ?? source.trim();
    final uri = Uri.tryParse(raw);
    return uri != null && uri.hasScheme ? uri : null;
  }

  /// The saved-query GUID of a `query-table` block, from the marker line or
  /// from the block's body.
  static String? queryId(String info, String source) {
    final pattern = RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
      caseSensitive: false,
    );
    return pattern.firstMatch(info)?[0] ?? pattern.firstMatch(source)?[0];
  }

  static IconData iconFor(WikiPlaceholderKind kind) => switch (kind) {
    WikiPlaceholderKind.mermaid => Icons.account_tree_outlined,
    WikiPlaceholderKind.math => Icons.functions,
    WikiPlaceholderKind.video => Icons.play_circle_outline,
    WikiPlaceholderKind.queryTable => Icons.table_chart_outlined,
    WikiPlaceholderKind.other => Icons.extension_outlined,
  };

  @override
  State<WikiPlaceholderCard> createState() => _WikiPlaceholderCardState();
}

class _WikiPlaceholderCardState extends State<WikiPlaceholderCard> {
  bool _source = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = widget.kind == WikiPlaceholderKind.queryTable
        ? WikiPlaceholderCard.queryId(widget.info, widget.source)
        : null;
    final video = widget.kind == WikiPlaceholderKind.video
        ? WikiPlaceholderCard.videoUrl(widget.source)
        : null;
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: Radii.card,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                WikiPlaceholderCard.iconFor(widget.kind),
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  widget.kind.label,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Text(
              'Not shown in the app.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_source && widget.source.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: WikiSourceBlock(source: widget.source),
            ),
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Wrap(
              spacing: Spacing.sm,
              children: [
                if (widget.source.trim().isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _source = !_source),
                    child: Text(_source ? 'Hide source' : 'Show source'),
                  ),
                if (widget.onOpenOnWeb != null)
                  TextButton(
                    onPressed: widget.onOpenOnWeb,
                    child: const Text('Open on web'),
                  ),
                if (query != null && widget.onOpenQuery != null)
                  TextButton(
                    onPressed: () => widget.onOpenQuery!(query),
                    child: const Text('Open in Boardhop'),
                  ),
                if (video != null && widget.onOpenUrl != null)
                  TextButton(
                    onPressed: () => widget.onOpenUrl!(video),
                    child: const Text('Open video'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Unhighlighted source in a code card: a placeholder's Show source and the
/// front matter's leftovers.
class WikiSourceBlock extends StatelessWidget {
  const WikiSourceBlock({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: context.boardhopColors.codeBackground,
        borderRadius: Radii.chip,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(source, style: BoardhopTheme.codeStyle(context)),
      ),
    );
  }
}

// ----------------------------------------------------------------- code block

/// A fenced code block: highlighted, pannable, copyable.
///
/// Plain monospace is drawn first and the highlighted runs are swapped in
/// when the isolate answers ([CodeHighlighter.highlightLinesAsync]), so a
/// page with ten fences never waits on grammar work — the same contract the
/// file and diff views have.
class WikiCodeBlock extends StatefulWidget {
  const WikiCodeBlock({super.key, required this.code, this.language});

  final String code;

  /// The fence's own id (`cs`, `yml`, `ps1`), not a highlight.js name.
  final String? language;

  /// Above this many lines the block stays plain: the grammar pass is
  /// linear but the spans are not free, and a thousand-line fence in a wiki
  /// page is a data dump, not code to read.
  static const maxHighlightedLines = 400;

  /// The fence ids the wiki's authors write, mapped onto the highlighter's
  /// language names. Anything not here falls back to
  /// [CodeHighlighter.languageFor], which knows the file extensions.
  static const aliases = <String, String>{
    'cs': 'csharp',
    'c#': 'csharp',
    'csharp': 'csharp',
    'ps1': 'powershell',
    'powershell': 'powershell',
    'pwsh': 'powershell',
    'yml': 'yaml',
    'yaml': 'yaml',
    'sh': 'bash',
    'shell': 'bash',
    'bash': 'bash',
    'zsh': 'bash',
    'ts': 'typescript',
    'tsx': 'typescript',
    'js': 'javascript',
    'jsx': 'javascript',
    'json': 'json',
    'jsonc': 'json',
    'dart': 'dart',
    'kt': 'kotlin',
    'kts': 'kotlin',
    'swift': 'swift',
    'sql': 'sql',
    'md': 'markdown',
    'markdown': 'markdown',
    'py': 'python',
    'xml': 'xml',
    'html': 'xml',
    'diff': 'diff',
    'text': '',
    'plaintext': '',
  };

  /// The highlight.js language for a fence id, or null for plain text.
  static String? languageFor(String? fence) {
    final id = (fence ?? '').trim().toLowerCase();
    if (id.isEmpty) return null;
    final alias = aliases[id];
    if (alias != null) return alias.isEmpty ? null : alias;
    return CodeHighlighter.languageFor('file.$id');
  }

  @override
  State<WikiCodeBlock> createState() => _WikiCodeBlockState();
}

class _WikiCodeBlockState extends State<WikiCodeBlock> {
  final _scroll = ScrollController();
  List<List<CodeRun>>? _runs;
  Brightness? _for;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_for == brightness) return;
    _for = brightness;
    _highlight(brightness);
  }

  @override
  void didUpdateWidget(WikiCodeBlock old) {
    super.didUpdateWidget(old);
    if (old.code != widget.code || old.language != widget.language) {
      _runs = null;
      _highlight(_for ?? Theme.of(context).brightness);
    }
  }

  Future<void> _highlight(Brightness brightness) async {
    final language = WikiCodeBlock.languageFor(widget.language);
    if (language == null) return;
    if ('\n'.allMatches(widget.code).length >=
        WikiCodeBlock.maxHighlightedLines) {
      return;
    }
    try {
      final runs = await CodeHighlighter.highlightLinesAsync(
        widget.code,
        language,
        brightness,
      );
      if (mounted && _for == brightness) setState(() => _runs = runs);
    } catch (_) {
      // Plain text is a fine answer; nothing on the page depends on colour.
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(content: Text('Code copied'), persist: false),
      );
  }

  @override
  Widget build(BuildContext context) {
    final style = BoardhopTheme.codeStyle(context);
    final runs = _runs;
    final span = runs == null
        ? TextSpan(text: widget.code.trimRight(), style: style)
        : TextSpan(
            style: style,
            children: [
              for (var i = 0; i < runs.length; i++) ...[
                if (i > 0) const TextSpan(text: '\n'),
                for (final run in runs[i])
                  TextSpan(text: run.text, style: run.style),
              ],
            ],
          );
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.xxl + Spacing.sm,
            Spacing.md,
          ),
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: Text.rich(span),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton(
            tooltip: 'Copy code',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _copy,
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------- table

/// A pipe table laid out the way K10 asks for: cells that wrap rather than
/// stretch, a shaded header row, and a sideways pan for a table too wide for
/// the phone.
class WikiTableView extends StatefulWidget {
  const WikiTableView({
    super.key,
    required this.source,
    required this.cellBuilder,
  });

  /// The raw markdown of the table, header and delimiter rows included.
  final String source;

  /// Renders one cell's markdown. The reader passes its own body builder in
  /// so a cell keeps mentions, links, `<br>` and inline code.
  final Widget Function(BuildContext context, String markdown, TextAlign align)
  cellBuilder;

  /// The widest a single column may be before its text wraps, in logical
  /// pixels: the smaller of 360 and 80 % of the viewport (K10).
  static double columnCap(double viewportWidth) =>
      math.min(360.0, math.max(120.0, viewportWidth * 0.8));

  /// Splits one row on its unescaped pipes.
  static List<String> cells(String line) {
    final out = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == r'\' && i + 1 < line.length && line[i + 1] == '|') {
        buffer.write('|');
        i++;
        continue;
      }
      if (ch == '|') {
        out.add(buffer.toString());
        buffer.clear();
        continue;
      }
      buffer.write(ch);
    }
    out.add(buffer.toString());
    if (out.isNotEmpty && out.first.trim().isEmpty) out.removeAt(0);
    if (out.isNotEmpty && out.last.trim().isEmpty) out.removeLast();
    return [for (final cell in out) cell.trim()];
  }

  /// The alignment each column asks for in the delimiter row.
  static List<TextAlign> alignments(String delimiter) => [
    for (final cell in cells(delimiter))
      if (cell.startsWith(':') && cell.endsWith(':'))
        TextAlign.center
      else if (cell.endsWith(':'))
        TextAlign.right
      else
        TextAlign.left,
  ];

  /// Header cells, alignments and body rows, or null when [source] is not a
  /// table after all.
  static ({List<String> head, List<TextAlign> align, List<List<String>> body})?
  parse(String source) {
    final lines = source
        .split(RegExp(r'\r\n|\r|\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) return null;
    final head = cells(lines.first);
    final align = alignments(lines[1]);
    final columns = math.max(head.length, align.length);
    final body = <List<String>>[];
    for (final line in lines.skip(2)) {
      final row = cells(line);
      body.add([
        for (var i = 0; i < columns; i++) i < row.length ? row[i] : '',
      ]);
    }
    return (
      head: [for (var i = 0; i < columns; i++) i < head.length ? head[i] : ''],
      align: [
        for (var i = 0; i < columns; i++)
          i < align.length ? align[i] : TextAlign.left,
      ],
      body: body,
    );
  }

  @override
  State<WikiTableView> createState() => _WikiTableViewState();
}

class _WikiTableViewState extends State<WikiTableView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parsed = WikiTableView.parse(widget.source);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (parsed == null) {
      return Text(widget.source, style: theme.textTheme.bodyMedium);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cap = WikiTableView.columnCap(
            constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width,
          );
          final table = Table(
            defaultColumnWidth: MinColumnWidth(
              const IntrinsicColumnWidth(),
              FixedColumnWidth(cap),
            ),
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            border: TableBorder.all(color: scheme.outlineVariant),
            children: [
              TableRow(
                decoration: BoxDecoration(color: scheme.surfaceContainer),
                children: [
                  for (var i = 0; i < parsed.head.length; i++)
                    _cell(parsed.head[i], parsed.align[i], header: true),
                ],
              ),
              for (final row in parsed.body)
                TableRow(
                  children: [
                    for (var i = 0; i < parsed.head.length; i++)
                      _cell(i < row.length ? row[i] : '', parsed.align[i]),
                  ],
                ),
            ],
          );
          return Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : 0,
                ),
                child: table,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cell(String markdown, TextAlign align, {bool header = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      child: DefaultTextStyle.merge(
        style: header ? const TextStyle(fontWeight: FontWeight.w600) : null,
        child: Align(
          alignment: switch (align) {
            TextAlign.center => Alignment.topCenter,
            TextAlign.right => Alignment.topRight,
            _ => Alignment.topLeft,
          },
          child: widget.cellBuilder(context, markdown, align),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- HTML block

/// A block of raw HTML inside a wiki page, through the same renderer a work
/// item description uses.
///
/// `<details>` keeps its summary and collapses, and an `<img src="/.
/// attachments/…">` loads with the bearer token — neither of which the
/// Markdown path can do, because the service's markdown is not HTML and the
/// image fetch is authenticated (research/17 §4).
class WikiHtmlBlock extends StatelessWidget {
  const WikiHtmlBlock({
    super.key,
    required this.html,
    this.imageUrl,
    this.headers = const {},
    this.onTapUrl,
  });

  final String html;

  /// Turns an `<img src>` into the URL its bytes come from — the wiki
  /// repository's items route for an attachment.
  final String Function(String src)? imageUrl;

  final Map<String, String> headers;

  /// Answers true when the reader took the link (another wiki page, a work
  /// item); false sends it to the browser.
  final bool Function(String url)? onTapUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: HtmlWidget(
        html,
        textStyle: theme.textTheme.bodyMedium,
        factoryBuilder: () => _WikiHtmlFactory(imageUrl, headers, onTapUrl),
        onErrorBuilder: (context, element, error) => Text(
          'Could not render part of this page.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}

class _WikiHtmlFactory extends WidgetFactory {
  _WikiHtmlFactory(this.imageUrl, this.headers, this.onTap);

  final String Function(String src)? imageUrl;
  final Map<String, String> headers;
  final bool Function(String url)? onTap;

  @override
  ImageProvider? imageProviderFromNetwork(String url) =>
      CachedNetworkImageProvider(imageUrl?.call(url) ?? url, headers: headers);

  /// A wiki page's `<img src="/.attachments/x.png">` and its relative links
  /// have no scheme, and the core factory resolves those against
  /// `HtmlWidget.baseUrl` — **returning null when there is none**, which
  /// drops the image and the link before anything else is asked. The wiki
  /// has no single base URL (an attachment is read from the git items route
  /// and a page from the wiki route), so the raw href is passed through and
  /// resolved by [imageProviderFromNetwork] and [onTapUrl] instead.
  @override
  String? urlFull(String url) =>
      super.urlFull(url) ?? (url.isEmpty ? null : url);

  @override
  Future<bool> onTapUrl(String url) async {
    if (onTap?.call(url) ?? false) return true;
    return super.onTapUrl(url);
  }
}
