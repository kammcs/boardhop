import 'dart:math';

import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../../core/text/mention.dart';
import '../../../data/repositories/pr_diff_source.dart';
import '../../../theme/theme.dart';
import '../../shared/attachments/inline_attachments.dart';
import '../../shared/attachments/pending_attachments.dart';
import '../../shared/dismiss_keyboard_on_drag.dart';
import '../../shared/mention/mention_controller.dart';
import '../../shared/mention/mention_field.dart';
import '../../shared/mention/mention_hint.dart';
import '../../shared/mention/mention_source.dart';
import '../../wiki/wiki_page_source.dart';
import '../../wiki/widgets/wiki_page_picker_sheet.dart';
import '../../work_items/form/controls/attachment_picker.dart';
import '../../work_items/form/controls/attachments_section.dart'
    show AttachmentSource;
import '../widgets/thread_card.dart';
import 'diff_model.dart';
import 'highlighter.dart';

/// Where a comment is anchored: one line, a range of lines, either side of
/// the diff, or the file as a whole (R9, R10).
@immutable
class DiffAnchor {
  const DiffAnchor({
    required this.line,
    this.endLine,
    this.leftSide = false,
    this.fileLevel = false,
  });

  /// A comment on the file rather than on a line; it renders above the
  /// first hunk and posts with a `threadContext` that carries only the path.
  const DiffAnchor.file()
    : line = 0,
      endLine = null,
      leftSide = false,
      fileLevel = true;

  final int line;

  /// Last line of a range; null or below [line] means a single line.
  final int? endLine;

  /// Anchored on the original (removed) side: what the gutter of a removed
  /// line posts.
  final bool leftSide;
  final bool fileLevel;

  int get last {
    final end = endLine;
    return end == null || end < line ? line : end;
  }

  bool get isRange => last > line;

  /// Whether [no] is inside this anchor on [leftSide]'s side.
  bool covers(int? no, {required bool left}) =>
      no != null && left == leftSide && no >= line && no <= last;

  String get title {
    if (fileLevel) return 'Comment on this file';
    final side = leftSide ? ' (original)' : '';
    return isRange
        ? 'Comment on lines $line–$last$side'
        : 'Comment on line $line$side';
  }

  @override
  bool operator ==(Object other) =>
      other is DiffAnchor &&
      other.line == line &&
      other.last == last &&
      other.leftSide == leftSide &&
      other.fileLevel == fileLevel;

  @override
  int get hashCode => Object.hash(line, last, leftSide, fileLevel);
}

/// The row indices the ▲▼ control steps through, rebuilt with the rows.
@immutable
class DiffStops {
  const DiffStops({
    this.changes = const [],
    this.comments = const [],
    this.rowCount = 0,
  });

  /// First row of every run of changed lines, ascending (R5).
  final List<int> changes;

  /// Rows that carry a thread, **unresolved first** and each group in row
  /// order: the order ▼ walks them (R5).
  final List<int> comments;
  final int rowCount;
}

/// The page's handle on a [DiffView]: what the ▲▼ control can step through,
/// where the viewport is, and how to move it.
class DiffViewController extends ChangeNotifier {
  _DiffViewState? _state;
  DiffStops _stops = const DiffStops();

  DiffStops get stops => _stops;
  bool get isAttached => _state != null;

  void _publish(DiffStops stops) {
    _stops = stops;
    notifyListeners();
  }

  /// Puts row [index] a fifth of the way down the viewport (R6). Reduced
  /// motion jumps instead of animating. False when the list is not laid
  /// out yet and the caller should try again next frame.
  bool jumpTo(int index, {bool animate = true}) =>
      _state?.jumpToRow(index, animate: animate) ?? false;

  /// First and last row on screen, or null before the list is laid out.
  (int, int)? get visibleRows => _state?.visibleRows;

  /// Row that carries new-side line [line], for `?line=` and for the jump
  /// into a file the reader has just stepped into (R7).
  int? rowForNewLine(int line) => _state?._rowByNewLine[line];
}

/// Rows of a unified (or, from the expanded breakpoint, side-by-side) diff
/// with syntax-colored runs, existing threads under their lines, and one
/// open composer. The parent owns the data and the writes; this widget only
/// lays it out (spike F5).
class DiffView extends StatefulWidget {
  const DiffView({
    super.key,
    required this.diff,
    required this.oldRuns,
    required this.newRuns,
    this.threads = const [],
    this.composerLine,
    this.composer,
    this.controller,
    this.wrap = false,
    this.sideBySide = false,
    this.endPadding = 0,
    this.onGutterTap,
    this.onPost,
    this.onCancelComposer,
    this.posting = false,
    this.canAct = false,
    this.onReply,
    this.onSetThreadStatus,
    this.onApplySuggestion,
    this.meId,
    this.onEditComment,
    this.onDeleteComment,
    this.onLikeComment,
    this.mentions,
    this.mentionNames = const {},
    this.attachments,
    this.uploads,
    this.wikiPages,
    this.offline = false,
    this.pick = pickAttachment,
    this.onOpenMention,
  });

  final LineDiffResult diff;
  final List<List<CodeRun>> oldRuns;
  final List<List<CodeRun>> newRuns;
  final List<PrThread> threads;

  /// New-side line under which the composer is open. Kept for the callers
  /// that only ever open a right-side single-line composer; [composer] is
  /// the full form and wins when both are set.
  final int? composerLine;
  final DiffAnchor? composer;

  /// Publishes the navigation stops and takes jump commands (R5–R7).
  final DiffViewController? controller;

  /// Long lines wrap instead of panning sideways (R16). Always on in
  /// [sideBySide], where a pane is half a screen wide.
  final bool wrap;

  /// Two panes, original left and new right (R16).
  final bool sideBySide;

  /// Room under the last row for the floating navigation pill.
  final double endPadding;

  final ValueChanged<DiffAnchor>? onGutterTap;
  final Future<void> Function(DiffAnchor anchor, String text)? onPost;
  final VoidCallback? onCancelComposer;
  final bool posting;

  /// Whether threads offer reply and status changes (active PR).
  final bool canAct;
  final Future<bool> Function(PrThread thread, String text)? onReply;
  final Future<bool> Function(PrThread thread, String status)?
  onSetThreadStatus;

  /// Commits a suggestion; null when the file is not at the latest
  /// iteration or the PR is closed.
  final Future<void> Function(
    PrThread thread,
    PrComment comment,
    String suggestion,
  )?
  onApplySuggestion;

  /// Identity of the signed-in user: only their own comments offer the
  /// edit and delete menu (R9).
  final String? meId;
  final Future<bool> Function(PrThread thread, PrComment comment, String text)?
  onEditComment;
  final Future<bool> Function(PrThread thread, PrComment comment)?
  onDeleteComment;
  final Future<bool> Function(PrThread thread, PrComment comment, bool like)?
  onLikeComment;

  /// What the reply boxes and the new-thread composer offer behind `@`, `#`
  /// and `!`. Null leaves plain fields (research/16 M1).
  final MentionSource? mentions;

  /// Lower-cased identity GUID → display name for the comments on screen.
  final Map<String, String> mentionNames;

  /// Images and files the threads under these lines carry (research/17 §4).
  final InlineAttachments? attachments;

  /// Where a file picked into the line composer or a reply box is uploaded
  /// on Send — the write side of [attachments]. Null leaves no attach
  /// button on either.
  final AttachmentSource? uploads;

  /// The project's wikis, for the book button in the reply and line-comment
  /// composers (research/20 K12).
  final WikiPageSource? wikiPages;

  /// The page's last request could not reach the service (decision T6).
  final bool offline;

  /// The platform picker, injected by the tests.
  final Future<PickedAttachment?> Function(AttachmentPickSource) pick;

  /// Tapping a `#123` or `!456` inside a comment.
  final void Function(MentionKind kind, String id)? onOpenMention;

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

/// One row of the side-by-side layout: the original line on the left and
/// the new one on the right, either of which may be missing.
class _PairRow extends _Row {
  const _PairRow(this.left, this.right);
  final _LineRow? left;
  final _LineRow? right;
}

class _ThreadRow extends _Row {
  const _ThreadRow(this.thread, {this.leftSide = false});
  final PrThread thread;

  /// Drawn under the original pane in the side-by-side layout (R9).
  final bool leftSide;
}

class _ComposerRow extends _Row {
  const _ComposerRow(this.anchor);
  final DiffAnchor anchor;
}

/// Which gutter a range drag started or landed on (R10).
@immutable
class _GutterAnchor {
  const _GutterAnchor(this.line, this.leftSide);
  final int line;
  final bool leftSide;
}

class _DiffViewState extends State<DiffView> {
  static const _gutterWidth = 88.0;

  final _listController = ListController();
  final _vertical = ScrollController();

  /// Long lines pan sideways under one scroll view; the line numbers and
  /// the comment cards follow it back so they stay where they were.
  final _horizontal = ScrollController();
  List<_Row> _rows = const [];
  DiffStops _stops = const DiffStops();

  /// New-side line number → row index, rebuilt with the rows.
  final Map<int, int> _rowByNewLine = {};
  double _charWidth = 7;

  /// The line a long press started on and the line the finger is over now
  /// (R10); both null when no range is being drawn.
  _GutterAnchor? _rangeStart;
  _GutterAnchor? _rangeEnd;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _measureChar();
    _rebuildRows();
  }

  @override
  void didUpdateWidget(DiffView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._state == this) old.controller?._state = null;
      widget.controller?._state = this;
    }
    if (old.diff != widget.diff ||
        old.threads != widget.threads ||
        old.composerLine != widget.composerLine ||
        old.composer != widget.composer ||
        old.wrap != widget.wrap ||
        old.sideBySide != widget.sideBySide ||
        old.oldRuns != widget.oldRuns ||
        old.newRuns != widget.newRuns) {
      _rebuildRows();
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _listController.dispose();
    _vertical.dispose();
    _horizontal.dispose();
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

  DiffAnchor? get _composer =>
      widget.composer ??
      (widget.composerLine == null
          ? null
          : DiffAnchor(line: widget.composerLine!));

  /// Long lines never pan in the side-by-side layout: a pane is half a
  /// screen wide, so its text wraps.
  bool get _wraps => widget.wrap || widget.sideBySide;

  (int, int)? get visibleRows {
    if (!_vertical.hasClients || _rows.isEmpty) return null;
    return _listController.visibleRange;
  }

  bool jumpToRow(int index, {bool animate = true}) {
    if (index < 0 || index >= _rows.length || !_vertical.hasClients) {
      return false;
    }
    // Respect the platform's reduced-motion switch: a long jump that
    // animates is exactly what it asks not to happen.
    final reduced =
        !animate || MediaQuery.maybeDisableAnimationsOf(context) == true;
    if (reduced) {
      _listController.jumpToItem(
        index: index,
        scrollController: _vertical,
        alignment: 0.2,
      );
      return true;
    }
    _listController.animateToItem(
      index: index,
      scrollController: _vertical,
      alignment: 0.2,
      duration: (_) => const Duration(milliseconds: 220),
      curve: (_) => Curves.easeOutCubic,
    );
    return true;
  }

  static List<CodeRun> _runsFor(List<List<CodeRun>> all, int? no, String text) {
    if (no == null || no < 1 || no > all.length) return [CodeRun(text, null)];
    return all[no - 1];
  }

  _LineRow _lineRow(DiffLine line, TextStyle add, TextStyle remove) {
    final base = switch (line.kind) {
      DiffKind.removed => _runsFor(widget.oldRuns, line.oldNo, line.text),
      _ => _runsFor(widget.newRuns, line.newNo, line.text),
    };
    final runs = switch (line.kind) {
      DiffKind.added => CodeHighlighter.emphasize(base, line.emphasis, add),
      DiffKind.removed => CodeHighlighter.emphasize(
        base,
        line.emphasis,
        remove,
      ),
      DiffKind.context => base,
    };
    return _LineRow(line, runs);
  }

  void _rebuildRows() {
    final colors = context.boardhopColors;
    final addEmphasis = TextStyle(
      backgroundColor: colors.diffAdded.withValues(alpha: 0.28),
    );
    final removeEmphasis = TextStyle(
      backgroundColor: colors.diffRemoved.withValues(alpha: 0.28),
    );

    // A thread lives on exactly one side: the right when it has a new-side
    // anchor, the left otherwise, which is how left-only threads reach the
    // screen at all (R9).
    final rightThreads = <int, List<PrThread>>{};
    final leftThreads = <int, List<PrThread>>{};
    final fileThreads = <PrThread>[];
    for (final t in widget.threads) {
      if (t.isFileLevel) {
        fileThreads.add(t);
      } else if (t.rightLine != null) {
        rightThreads.putIfAbsent(t.rightLine!, () => []).add(t);
      } else if (t.leftLine != null) {
        leftThreads.putIfAbsent(t.leftLine!, () => []).add(t);
      }
    }

    final composer = _composer;
    final rows = <_Row>[];
    _rowByNewLine.clear();
    // Row index of each line of the diff, so `hunkStarts` can be mapped
    // onto the rows the list actually builds.
    final rowByLine = List<int>.filled(widget.diff.lines.length, -1);

    // File-level comments sit above the first hunk (R9).
    for (final t in fileThreads) {
      rows.add(_ThreadRow(t));
    }
    if (composer != null && composer.fileLevel) {
      rows.add(_ComposerRow(composer));
    }

    void addAnchored(DiffLine? left, DiffLine? right) {
      final newNo = right?.newNo;
      final oldNo = left?.oldNo;
      if (newNo != null) {
        for (final t in rightThreads[newNo] ?? const <PrThread>[]) {
          rows.add(_ThreadRow(t));
        }
      }
      if (oldNo != null) {
        for (final t in leftThreads[oldNo] ?? const <PrThread>[]) {
          rows.add(_ThreadRow(t, leftSide: true));
        }
      }
      if (composer == null || composer.fileLevel) return;
      final on = composer.leftSide ? oldNo : newNo;
      if (on == composer.last) rows.add(_ComposerRow(composer));
    }

    if (widget.sideBySide) {
      for (final (left, right) in _pairs()) {
        final leftLine = left == null ? null : widget.diff.lines[left];
        final rightLine = right == null ? null : widget.diff.lines[right];
        if (left != null) rowByLine[left] = rows.length;
        if (right != null) {
          rowByLine[right] = rows.length;
          final no = rightLine?.newNo;
          if (no != null) _rowByNewLine[no] = rows.length;
        }
        rows.add(
          _PairRow(
            leftLine == null
                ? null
                : _lineRow(leftLine, addEmphasis, removeEmphasis),
            rightLine == null
                ? null
                : _lineRow(rightLine, addEmphasis, removeEmphasis),
          ),
        );
        addAnchored(leftLine, rightLine);
      }
    } else {
      for (var i = 0; i < widget.diff.lines.length; i++) {
        final line = widget.diff.lines[i];
        rowByLine[i] = rows.length;
        if (line.newNo != null) _rowByNewLine[line.newNo!] = rows.length;
        rows.add(_lineRow(line, addEmphasis, removeEmphasis));
        addAnchored(line, line);
      }
    }

    final changes = <int>[
      for (final i in widget.diff.hunkStarts)
        if (i >= 0 && i < rowByLine.length && rowByLine[i] >= 0) rowByLine[i],
    ];
    // Unresolved threads first, each group in the order they appear (R5).
    final open = <int>[];
    final settled = <int>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row is! _ThreadRow) continue;
      (row.thread.isResolved ? settled : open).add(i);
    }

    setState(() {
      _rows = rows;
      _stops = DiffStops(
        changes: changes,
        comments: [...open, ...settled],
        rowCount: rows.length,
      );
    });
    widget.controller?._publish(_stops);
  }

  /// Pairs the unified rows for the side-by-side layout: context lines face
  /// themselves, and a run of removed lines is aligned index for index with
  /// the run of added lines under it.
  List<(int?, int?)> _pairs() {
    final lines = widget.diff.lines;
    final out = <(int?, int?)>[];
    var i = 0;
    while (i < lines.length) {
      if (lines[i].kind == DiffKind.context) {
        out.add((i, i));
        i++;
        continue;
      }
      var j = i;
      while (j < lines.length && lines[j].kind == DiffKind.removed) {
        j++;
      }
      var k = j;
      while (k < lines.length && lines[k].kind == DiffKind.added) {
        k++;
      }
      final removed = j - i;
      final added = k - j;
      for (var p = 0; p < max(removed, added); p++) {
        out.add((p < removed ? i + p : null, p < added ? j + p : null));
      }
      i = k;
    }
    return out;
  }

  void _startRange(_GutterAnchor anchor) {
    setState(() {
      _rangeStart = anchor;
      _rangeEnd = anchor;
    });
  }

  void _extendRange(_GutterAnchor anchor) {
    final start = _rangeStart;
    if (start == null || anchor.leftSide != start.leftSide) return;
    if (_rangeEnd?.line == anchor.line) return;
    setState(() => _rangeEnd = anchor);
  }

  /// The finger came up: post the range if it grew, otherwise treat the
  /// long press as a tap on that line.
  void _finishRange() {
    final start = _rangeStart;
    final end = _rangeEnd ?? start;
    setState(() {
      _rangeStart = null;
      _rangeEnd = null;
    });
    if (start == null || widget.onGutterTap == null) return;
    final from = min(start.line, end!.line);
    final to = max(start.line, end.line);
    widget.onGutterTap!(
      DiffAnchor(line: from, endLine: to, leftSide: start.leftSide),
    );
  }

  /// The range being drawn right now, for the highlight under the finger.
  DiffAnchor? get _pendingRange {
    final start = _rangeStart;
    final end = _rangeEnd;
    if (start == null || end == null) return null;
    return DiffAnchor(
      line: min(start.line, end.line),
      endLine: max(start.line, end.line),
      leftSide: start.leftSide,
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = LayoutBuilder(
      builder: (context, constraints) {
        final rows = DismissKeyboardOnDrag(
          child: SuperListView.builder(
            controller: _vertical,
            listController: _listController,
            itemCount: _rows.length,
            padding: scrollEndPadding(context, extra: widget.endPadding),
            itemBuilder: (context, i) =>
                _buildRow(context, _rows[i], constraints.maxWidth),
          ),
        );
        if (_wraps) return rows;
        final width =
            _gutterWidth + widget.diff.maxChars * _charWidth + Spacing.lg * 2;
        return SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: max(width, constraints.maxWidth), child: rows),
        );
      },
    );
    return list;
  }

  Widget _buildRow(
    BuildContext context,
    _Row row,
    double viewportWidth,
  ) => switch (row) {
    _LineRow() => _lineView(row, half: false),
    _PairRow() => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: row.left == null
                ? const _BlankHalf()
                : _lineView(row.left!, half: true, left: true),
          ),
          Expanded(
            child: row.right == null
                ? const _BlankHalf()
                : _lineView(row.right!, half: true, left: false),
          ),
        ],
      ),
    ),
    _ThreadRow() => _sided(
      row.leftSide,
      _ThreadView(
        key: ValueKey('thread-${row.thread.id}'),
        thread: row.thread,
        gutterWidth: _wraps ? Spacing.lg : _gutterWidth,
        horizontal: _wraps ? null : _horizontal,
        viewportWidth: widget.sideBySide ? viewportWidth / 2 : viewportWidth,
        canAct: widget.canAct,
        busy: widget.posting,
        mentions: widget.mentions,
        mentionNames: widget.mentionNames,
        attachments: widget.attachments,
        uploads: widget.uploads,
        wikiPages: widget.wikiPages,
        offline: widget.offline,
        pick: widget.pick,
        meId: widget.meId,
        onOpenMention: widget.onOpenMention,
        onReply: widget.onReply == null
            ? null
            : (text) => widget.onReply!(row.thread, text),
        onSetStatus: widget.onSetThreadStatus == null
            ? null
            : (status) => widget.onSetThreadStatus!(row.thread, status),
        onApplySuggestion: widget.onApplySuggestion == null
            ? null
            : (comment, suggestion) =>
                  widget.onApplySuggestion!(row.thread, comment, suggestion),
        onEdit: widget.onEditComment == null
            ? null
            : (comment, text) =>
                  widget.onEditComment!(row.thread, comment, text),
        onDelete: widget.onDeleteComment == null
            ? null
            : (comment) => widget.onDeleteComment!(row.thread, comment),
        onLike: widget.onLikeComment == null
            ? null
            : (comment, like) =>
                  widget.onLikeComment!(row.thread, comment, like),
      ),
    ),
    _ComposerRow() => _sided(
      row.anchor.leftSide,
      _ComposerView(
        key: ValueKey('composer-${row.anchor.hashCode}'),
        anchor: row.anchor,
        gutterWidth: _wraps ? Spacing.lg : _gutterWidth,
        horizontal: _wraps ? null : _horizontal,
        viewportWidth: widget.sideBySide ? viewportWidth / 2 : viewportWidth,
        posting: widget.posting,
        mentions: widget.mentions,
        attachments: widget.uploads,
        wikiPages: widget.wikiPages,
        offline: widget.offline,
        pick: widget.pick,
        onCancel: widget.onCancelComposer,
        onPost: widget.onPost == null
            ? null
            : (text) => widget.onPost!(row.anchor, text),
      ),
    ),
  };

  /// In the side-by-side layout a card belongs under the pane it comments
  /// on; in the unified one there is only one column.
  Widget _sided(bool left, Widget child) {
    if (!widget.sideBySide) return child;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left ? child : const SizedBox.shrink()),
        Expanded(child: left ? const SizedBox.shrink() : child),
      ],
    );
  }

  Widget _lineView(_LineRow row, {required bool half, bool left = false}) {
    final line = row.line;
    final side = half ? left : line.newNo == null;
    final no = side ? line.oldNo : line.newNo;
    final anchor = no == null ? null : _GutterAnchor(no, side);
    final range = _pendingRange;
    return _DiffLineView(
      row: row,
      style: _codeStyle(context),
      gutterWidth: half ? 56 : _gutterWidth,
      horizontal: _wraps ? null : _horizontal,
      wrap: _wraps,
      half: half,
      showsOld: !half || left,
      showsNew: !half || !left,
      inRange: range != null && range.covers(no, left: side),
      onGutterTap: anchor == null || widget.onGutterTap == null
          ? null
          : () => widget.onGutterTap!(
              DiffAnchor(line: anchor.line, leftSide: anchor.leftSide),
            ),
      rangeAnchor: widget.onGutterTap == null ? null : anchor,
      onRangeStart: _startRange,
      onRangeExtend: _extendRange,
      onRangeFinish: _finishRange,
    );
  }
}

/// The empty half of a side-by-side row: the other side has no line here.
class _BlankHalf extends StatelessWidget {
  const _BlankHalf();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: const SizedBox(width: double.infinity),
  );
}

/// Holds [child] at the same place on screen while the diff pans
/// sideways, by moving it with the scroll offset.
class _Pinned extends StatelessWidget {
  const _Pinned({required this.horizontal, required this.child});

  final ScrollController? horizontal;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final horizontal = this.horizontal;
    if (horizontal == null) return child;
    return AnimatedBuilder(
      animation: horizontal,
      builder: (context, pinned) => Transform.translate(
        offset: Offset(horizontal.hasClients ? horizontal.offset : 0, 0),
        child: pinned,
      ),
      child: child,
    );
  }
}

class _DiffLineView extends StatelessWidget {
  const _DiffLineView({
    required this.row,
    required this.style,
    required this.gutterWidth,
    required this.horizontal,
    required this.wrap,
    required this.half,
    required this.showsOld,
    required this.showsNew,
    required this.inRange,
    required this.onGutterTap,
    required this.rangeAnchor,
    required this.onRangeStart,
    required this.onRangeExtend,
    required this.onRangeFinish,
  });

  final _LineRow row;
  final TextStyle style;
  final double gutterWidth;
  final ScrollController? horizontal;
  final bool wrap;

  /// One pane of the side-by-side layout rather than a full-width row.
  final bool half;
  final bool showsOld;
  final bool showsNew;

  /// Inside the range being drawn by a long-press drag (R10).
  final bool inRange;
  final VoidCallback? onGutterTap;
  final _GutterAnchor? rangeAnchor;
  final ValueChanged<_GutterAnchor> onRangeStart;
  final ValueChanged<_GutterAnchor> onRangeExtend;
  final VoidCallback onRangeFinish;

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
    final tint = inRange
        ? scheme.primary.withValues(alpha: 0.18)
        : (background ?? Colors.transparent);
    final text = Text.rich(
      TextSpan(
        style: style,
        children: [
          for (final r in row.runs) TextSpan(text: r.text, style: r.style),
          if (row.runs.isEmpty) const TextSpan(text: ' '),
        ],
      ),
      softWrap: wrap,
      overflow: TextOverflow.visible,
    );
    final gutter = _gutter(
      context,
      numberStyle: numberStyle,
      marker: marker,
      markerColor: markerColor,
      background: inRange ? tint : background,
    );
    if (wrap) {
      // Nothing pans, so the gutter is simply the first column.
      return ColoredBox(
        color: tint,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            gutter,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: Spacing.sm),
                child: text,
              ),
            ),
          ],
        ),
      );
    }
    // The code sits under the gutter, which is painted last and moved
    // with the horizontal scroll, so the line numbers never leave.
    return ColoredBox(
      color: tint,
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(left: gutterWidth, right: Spacing.lg),
            child: text,
          ),
          _Pinned(horizontal: horizontal, child: gutter),
        ],
      ),
    );
  }

  Widget _gutter(
    BuildContext context, {
    required TextStyle numberStyle,
    required String marker,
    required Color markerColor,
    required Color? background,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final line = row.line;
    final numbers = SizedBox(
      width: gutterWidth,
      child: Row(
        children: [
          if (showsOld)
            SizedBox(
              width: half ? 40 : 36,
              child: Text(
                line.oldNo?.toString() ?? '',
                textAlign: TextAlign.right,
                style: numberStyle,
              ),
            ),
          if (showsNew)
            SizedBox(
              width: half ? 40 : 36,
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
    );
    Widget gutter = InkWell(
      onTap: onGutterTap,
      child: ColoredBox(color: background ?? scheme.surface, child: numbers),
    );
    final anchor = rangeAnchor;
    if (anchor == null) return gutter;
    // Long-press a gutter and drag to extend the range, exactly as the
    // board moves a card (R10).
    gutter = LongPressDraggable<_GutterAnchor>(
      data: anchor,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => onRangeStart(anchor),
      onDragEnd: (_) => onRangeFinish(),
      onDraggableCanceled: (_, _) => onRangeFinish(),
      feedback: _RangeFeedback(line: anchor.line, leftSide: anchor.leftSide),
      childWhenDragging: gutter,
      child: gutter,
    );
    return DragTarget<_GutterAnchor>(
      onWillAcceptWithDetails: (details) {
        onRangeExtend(anchor);
        return details.data.leftSide == anchor.leftSide;
      },
      onMove: (details) {
        if (details.data.leftSide == anchor.leftSide) onRangeExtend(anchor);
      },
      onAcceptWithDetails: (_) {},
      builder: (context, _, _) => gutter,
    );
  }
}

class _RangeFeedback extends StatelessWidget {
  const _RangeFeedback({required this.line, required this.leftSide});

  final int line;
  final bool leftSide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.inverseSurface,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.xs,
        ),
        child: Text(
          'Drag to line…',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: scheme.onInverseSurface),
        ),
      ),
    );
  }
}

class _ThreadView extends StatelessWidget {
  const _ThreadView({
    super.key,
    required this.thread,
    required this.gutterWidth,
    required this.horizontal,
    required this.viewportWidth,
    required this.canAct,
    required this.busy,
    required this.onReply,
    required this.onSetStatus,
    required this.onApplySuggestion,
    this.meId,
    this.onEdit,
    this.onDelete,
    this.onLike,
    this.mentions,
    this.mentionNames = const {},
    this.attachments,
    this.uploads,
    this.wikiPages,
    this.offline = false,
    this.pick = pickAttachment,
    this.onOpenMention,
  });

  final PrThread thread;
  final double gutterWidth;
  final ScrollController? horizontal;
  final double viewportWidth;
  final bool canAct;
  final bool busy;
  final MentionSource? mentions;
  final Map<String, String> mentionNames;

  /// Images and files the threads under these lines carry (research/17 §4).
  final InlineAttachments? attachments;

  /// Where a file picked into this thread's reply box is uploaded.
  final AttachmentSource? uploads;
  final WikiPageSource? wikiPages;
  final bool offline;
  final Future<PickedAttachment?> Function(AttachmentPickSource) pick;
  final void Function(MentionKind kind, String id)? onOpenMention;
  final Future<bool> Function(String text)? onReply;
  final Future<bool> Function(String status)? onSetStatus;
  final Future<void> Function(PrComment comment, String suggestion)?
  onApplySuggestion;
  final String? meId;
  final Future<bool> Function(PrComment comment, String text)? onEdit;
  final Future<bool> Function(PrComment comment)? onDelete;
  final Future<bool> Function(PrComment comment, bool like)? onLike;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A comment is prose, not code: it stays where it is while the code
    // beside it pans.
    return _Pinned(
      horizontal: horizontal,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          gutterWidth,
          Spacing.xs,
          Spacing.lg,
          Spacing.xs,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: max(
                240,
                min(520, viewportWidth - gutterWidth - Spacing.lg),
              ),
            ),
            child: ThreadCard(
              thread: thread,
              canAct: canAct,
              busy: busy,
              mentions: mentions,
              mentionNames: mentionNames,
              attachments: attachments,
              uploads: uploads,
              wikiPages: wikiPages,
              offline: offline,
              pick: pick,
              meId: meId,
              onOpenMention: onOpenMention,
              onReply: onReply,
              onSetStatus: onSetStatus,
              onApplySuggestion: onApplySuggestion,
              onEditComment: onEdit,
              onDeleteComment: onDelete,
              onLikeComment: onLike,
              color: scheme.surfaceContainerHigh,
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposerView extends StatefulWidget {
  const _ComposerView({
    super.key,
    required this.anchor,
    required this.gutterWidth,
    required this.horizontal,
    required this.viewportWidth,
    required this.posting,
    required this.onCancel,
    required this.onPost,
    this.mentions,
    this.attachments,
    this.wikiPages,
    this.offline = false,
    this.pick = pickAttachment,
  });

  final DiffAnchor anchor;
  final double gutterWidth;
  final ScrollController? horizontal;
  final double viewportWidth;
  final bool posting;
  final MentionSource? mentions;

  /// Where a file picked into this composer is uploaded on Post.
  final AttachmentSource? attachments;

  /// The project's wikis, for the book button (research/20 K12).
  final WikiPageSource? wikiPages;
  final bool offline;
  final Future<PickedAttachment?> Function(AttachmentPickSource) pick;
  final VoidCallback? onCancel;
  final Future<void> Function(String text)? onPost;

  @override
  State<_ComposerView> createState() => _ComposerViewState();
}

class _ComposerViewState extends State<_ComposerView>
    with ComposerAttachments<_ComposerView> {
  final _controller = MentionController();

  /// Owned here so the wiki picker can give the focus back (K12).
  final _focus = FocusNode();

  @override
  AttachmentSource? get attachmentSource => widget.attachments;

  @override
  Future<PickedAttachment?> Function(AttachmentPickSource) get attachmentPick =>
      widget.pick;

  @override
  bool get attachmentsOffline => widget.offline;

  /// One busy state covers the uploads and the post (T3).
  bool get _busy => widget.posting || uploadingAttachments;

  Future<void> _post() async {
    if (_busy || widget.onPost == null) return;
    // `@Kelly Kamm` posts as `@<guid>`.
    final text = _controller.toWire(MentionWire.markdown).trim();
    // A line comment may be files alone (T3).
    if (text.isEmpty && pending.isEmpty) return;
    final body = await bodyWithAttachments(text);
    if (body == null || body.isEmpty || !mounted) return;
    // The keyboard goes with the comment (Kelly, 2026-09-14).
    FocusManager.instance.primaryFocus?.unfocus();
    await widget.onPost!(body);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Pinned(
      horizontal: widget.horizontal,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          widget.gutterWidth,
          Spacing.xs,
          Spacing.lg,
          Spacing.xs,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: max(
              240,
              min(520, widget.viewportWidth - widget.gutterWidth - Spacing.lg),
            ),
          ),
          child: Material(
            color: scheme.surfaceContainerHigh,
            borderRadius: Radii.card,
            child: Padding(
              padding: Spacing.card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.anchor.title,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: Spacing.xs),
                  MentionField(
                    controller: _controller,
                    source: widget.mentions,
                    focusNode: _focus,
                    autofocus: true,
                    maxLines: 5,
                    minLines: 2,
                    enabled: !_busy,
                    contentInsertionConfiguration: contentInsertion,
                    decoration: InputDecoration(
                      hintText: widget.anchor.leftSide
                          ? 'Markdown'
                          : 'Markdown, or a ```suggestion block',
                    ),
                  ),
                  MentionHint(controller: _controller),
                  attachmentsBar(busy: _busy),
                  const SizedBox(height: Spacing.sm),
                  Row(
                    children: [
                      // The leading edge of the button row, so Post stays
                      // the rightmost control (a2 §3.1).
                      if (widget.wikiPages != null)
                        WikiPageButton(
                          source: widget.wikiPages!,
                          controller: _controller,
                          focusNode: _focus,
                          enabled: !_busy,
                        ),
                      if (canAttach) attachButton(busy: _busy),
                      const Spacer(),
                      TextButton(
                        onPressed: _busy ? null : widget.onCancel,
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: Spacing.sm),
                      FilledButton(
                        onPressed: _busy || widget.onPost == null
                            ? null
                            : _post,
                        child: Text(_busy ? 'Posting…' : 'Post'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
