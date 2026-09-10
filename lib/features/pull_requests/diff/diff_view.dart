import 'dart:math';

import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../../data/repositories/pr_diff_source.dart';
import '../../../theme/theme.dart';
import 'diff_model.dart';
import 'highlighter.dart';

/// Rows of a unified diff with syntax-colored runs, existing threads under
/// their lines, and one open composer. The parent owns the data and the
/// writes; this widget only lays it out (spike F5).
class DiffView extends StatefulWidget {
  const DiffView({
    super.key,
    required this.diff,
    required this.oldRuns,
    required this.newRuns,
    this.threads = const [],
    this.composerLine,
    this.onGutterTap,
    this.onPost,
    this.onCancelComposer,
    this.posting = false,
  });

  final LineDiffResult diff;
  final List<List<CodeRun>> oldRuns;
  final List<List<CodeRun>> newRuns;
  final List<PrThread> threads;

  /// New-side line under which the composer is open.
  final int? composerLine;
  final ValueChanged<int>? onGutterTap;
  final Future<void> Function(int line, String text)? onPost;
  final VoidCallback? onCancelComposer;
  final bool posting;

  @override
  State<DiffView> createState() => _DiffViewState();
}

sealed class _Row {
  const _Row();
}

class _LineRow extends _Row {
  const _LineRow(this.line, this.runs);
  final DiffLine line;
  final List<CodeRun> runs;
}

class _ThreadRow extends _Row {
  const _ThreadRow(this.thread);
  final PrThread thread;
}

class _ComposerRow extends _Row {
  const _ComposerRow(this.line);
  final int line;
}

class _DiffViewState extends State<DiffView> {
  static const _gutterWidth = 88.0;

  final _listController = ListController();
  final _vertical = ScrollController();
  List<_Row> _rows = const [];
  double _charWidth = 7;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _measureChar();
    _rebuildRows();
  }

  @override
  void didUpdateWidget(DiffView old) {
    super.didUpdateWidget(old);
    if (old.diff != widget.diff ||
        old.threads != widget.threads ||
        old.composerLine != widget.composerLine ||
        old.oldRuns != widget.oldRuns ||
        old.newRuns != widget.newRuns) {
      _rebuildRows();
    }
  }

  @override
  void dispose() {
    _listController.dispose();
    _vertical.dispose();
    super.dispose();
  }

  TextStyle _codeStyle(BuildContext context) =>
      BoardhopTheme.codeStyle(context).copyWith(fontSize: 12, height: 1.45);

  void _measureChar() {
    final painter = TextPainter(
      text: TextSpan(text: 'M', style: _codeStyle(context)),
      textDirection: TextDirection.ltr,
    )..layout();
    _charWidth = painter.width;
  }

  static List<CodeRun> _runsFor(List<List<CodeRun>> all, int? no, String text) {
    if (no == null || no < 1 || no > all.length) return [CodeRun(text, null)];
    return all[no - 1];
  }

  void _rebuildRows() {
    final colors = context.boardhopColors;
    final addEmphasis = TextStyle(
      backgroundColor: colors.diffAdded.withValues(alpha: 0.28),
    );
    final removeEmphasis = TextStyle(
      backgroundColor: colors.diffRemoved.withValues(alpha: 0.28),
    );
    final threadsByLine = <int, List<PrThread>>{};
    for (final t in widget.threads) {
      if (t.rightLine == null) continue;
      threadsByLine.putIfAbsent(t.rightLine!, () => []).add(t);
    }
    final rows = <_Row>[];
    for (final line in widget.diff.lines) {
      final base = switch (line.kind) {
        DiffKind.removed => _runsFor(widget.oldRuns, line.oldNo, line.text),
        _ => _runsFor(widget.newRuns, line.newNo, line.text),
      };
      final runs = switch (line.kind) {
        DiffKind.added => CodeHighlighter.emphasize(
          base,
          line.emphasis,
          addEmphasis,
        ),
        DiffKind.removed => CodeHighlighter.emphasize(
          base,
          line.emphasis,
          removeEmphasis,
        ),
        DiffKind.context => base,
      };
      rows.add(_LineRow(line, runs));
      final n = line.newNo;
      if (n != null) {
        for (final t in threadsByLine[n] ?? const <PrThread>[]) {
          rows.add(_ThreadRow(t));
        }
        if (widget.composerLine == n) rows.add(_ComposerRow(n));
      }
    }
    setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    final width =
        _gutterWidth + widget.diff.maxChars * _charWidth + Spacing.lg * 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = max(width, constraints.maxWidth);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: contentWidth,
            child: SuperListView.builder(
              controller: _vertical,
              listController: _listController,
              itemCount: _rows.length,
              itemBuilder: (context, i) => _buildRow(context, _rows[i]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRow(BuildContext context, _Row row) => switch (row) {
    _LineRow() => _DiffLineView(
      row: row,
      style: _codeStyle(context),
      gutterWidth: _gutterWidth,
      onGutterTap: row.line.newNo == null || widget.onGutterTap == null
          ? null
          : () => widget.onGutterTap!(row.line.newNo!),
    ),
    _ThreadRow() => _ThreadView(thread: row.thread, gutterWidth: _gutterWidth),
    _ComposerRow() => _ComposerView(
      line: row.line,
      gutterWidth: _gutterWidth,
      posting: widget.posting,
      onCancel: widget.onCancelComposer,
      onPost: widget.onPost == null
          ? null
          : (text) => widget.onPost!(row.line, text),
    ),
  };
}

class _DiffLineView extends StatelessWidget {
  const _DiffLineView({
    required this.row,
    required this.style,
    required this.gutterWidth,
    required this.onGutterTap,
  });

  final _LineRow row;
  final TextStyle style;
  final double gutterWidth;
  final VoidCallback? onGutterTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.boardhopColors;
    final scheme = Theme.of(context).colorScheme;
    final line = row.line;
    final (
      Color? background,
      String marker,
      Color markerColor,
    ) = switch (line.kind) {
      DiffKind.added => (colors.diffAddedBackground, '+', colors.diffAdded),
      DiffKind.removed => (
        colors.diffRemovedBackground,
        '−',
        colors.diffRemoved,
      ),
      DiffKind.context => (null, ' ', scheme.onSurfaceVariant),
    };
    final numberStyle = style.copyWith(color: scheme.onSurfaceVariant);
    return ColoredBox(
      color: background ?? Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onGutterTap,
            child: SizedBox(
              width: gutterWidth,
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      line.oldNo?.toString() ?? '',
                      textAlign: TextAlign.right,
                      style: numberStyle,
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      line.newNo?.toString() ?? '',
                      textAlign: TextAlign.right,
                      style: numberStyle,
                    ),
                  ),
                  SizedBox(
                    width: 16,
                    child: Text(
                      marker,
                      textAlign: TextAlign.center,
                      style: style.copyWith(
                        color: markerColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: Spacing.lg),
              child: Text.rich(
                TextSpan(
                  style: style,
                  children: [
                    for (final r in row.runs)
                      TextSpan(text: r.text, style: r.style),
                    if (row.runs.isEmpty) const TextSpan(text: ' '),
                  ],
                ),
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadView extends StatelessWidget {
  const _ThreadView({required this.thread, required this.gutterWidth});

  final PrThread thread;
  final double gutterWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutterWidth,
        Spacing.xs,
        Spacing.lg,
        Spacing.xs,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: Radii.card,
          child: Padding(
            padding: Spacing.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 16,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: Spacing.xs),
                    Text(
                      '${thread.status}'
                      '${thread.trackedFromLine != null && thread.trackedFromLine != thread.rightLine ? ' · moved from line ${thread.trackedFromLine}' : ''}',
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
                for (final c in thread.comments) ...[
                  const SizedBox(height: Spacing.xs),
                  Text(c.author, style: theme.textTheme.labelLarge),
                  SelectableText(c.content, style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposerView extends StatefulWidget {
  const _ComposerView({
    required this.line,
    required this.gutterWidth,
    required this.posting,
    required this.onCancel,
    required this.onPost,
  });

  final int line;
  final double gutterWidth;
  final bool posting;
  final VoidCallback? onCancel;
  final Future<void> Function(String text)? onPost;

  @override
  State<_ComposerView> createState() => _ComposerViewState();
}

class _ComposerViewState extends State<_ComposerView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.gutterWidth,
        Spacing.xs,
        Spacing.lg,
        Spacing.xs,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: Radii.card,
          child: Padding(
            padding: Spacing.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Comment on line ${widget.line}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: Spacing.xs),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  maxLines: 5,
                  minLines: 2,
                  enabled: !widget.posting,
                  decoration: const InputDecoration(
                    hintText: 'Markdown, or a ```suggestion block',
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: widget.posting ? null : widget.onCancel,
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: Spacing.sm),
                    FilledButton(
                      onPressed: widget.posting || widget.onPost == null
                          ? null
                          : () {
                              final text = _controller.text.trim();
                              if (text.isNotEmpty) widget.onPost!(text);
                            },
                      child: Text(widget.posting ? 'Posting…' : 'Post'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
