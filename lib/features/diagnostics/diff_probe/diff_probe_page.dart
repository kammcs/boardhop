import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../../core/http/ado_client.dart';
import '../../../core/http/ado_exceptions.dart';
import '../../../theme/theme.dart';
import '../frame_stats.dart';
import '../../../data/repositories/pr_diff_source.dart';
import '../../pull_requests/diff/diff_model.dart';
import '../../pull_requests/diff/highlighter.dart';

enum _Source { synthetic, live }

enum _ListImpl { superList, plain }

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
  const _ComposerRow(this.newLine);

  final int newLine;
}

/// Spike F5: unified diff viewer with syntax highlighting, a tap-to-comment
/// gutter, existing PR threads at their tracked lines, and jump-to-line on
/// a `super_sliver_list`. Synthetic 3,000-line fixture by default; the live
/// mode reads one pull request (nothing is written).
class DiffProbePage extends StatefulWidget {
  const DiffProbePage({super.key});

  @override
  State<DiffProbePage> createState() => _DiffProbePageState();
}

class _DiffProbePageState extends State<DiffProbePage> {
  final _stats = FrameStats();
  final _listController = ListController();
  final _vertical = ScrollController();
  final _org = TextEditingController(text: 'puremedia');
  final _prId = TextEditingController(text: '8319');

  _Source _source = _Source.synthetic;
  _ListImpl _listImpl = _ListImpl.superList;
  String _fileName = 'sample.dart';
  LineDiffResult? _diff;
  List<List<CodeRun>> _oldRuns = const [];
  List<List<CodeRun>> _newRuns = const [];
  List<_Row> _rows = const [];
  final Map<int, int> _rowByNewLine = <int, int>{};
  final Set<int> _composers = <int>{};
  List<PrThread> _threads = const [];
  int _threadsOnFile = 0;
  double _charWidth = 7;
  Duration? _diffTime;
  Duration? _highlightTime;
  Duration? _rowsTime;
  Duration? _jumpTime;
  int? _lastJump;
  String? _status;
  bool _busy = false;

  // Live mode state.
  PrRef? _pr;
  List<PrIteration> _iterations = const [];
  int? _iteration;
  List<PrFileChange> _changes = const [];
  PrFileChange? _selectedFile;

  @override
  void initState() {
    super.initState();
    _stats.attach();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSynthetic());
  }

  @override
  void dispose() {
    _stats.detach();
    _listController.dispose();
    _vertical.dispose();
    _org.dispose();
    _prId.dispose();
    super.dispose();
  }

  TextStyle _codeStyle(BuildContext context) =>
      BoardhopTheme.codeStyle(context).copyWith(fontSize: 12, height: 1.45);

  void _measureChar(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: 'M', style: _codeStyle(context)),
      textDirection: TextDirection.ltr,
    )..layout();
    _charWidth = painter.width;
  }

  Future<void> _loadSynthetic() async {
    setState(() {
      _busy = true;
      _status = 'Generating the fixture…';
      _source = _Source.synthetic;
      _fileName = 'sample.dart';
      _threads = const [];
      _threadsOnFile = 0;
    });
    await Future<void>.delayed(Duration.zero);
    final oldText = SampleDiff.original();
    final newText = SampleDiff.edited();
    _apply(oldText, newText);
  }

  void _apply(String oldText, String newText) {
    final brightness = Theme.of(context).brightness;
    final sw = Stopwatch()..start();
    final diff = LineDiff.compute(oldText, newText);
    _diffTime = sw.elapsed;
    sw.reset();
    final language = CodeHighlighter.languageFor(_fileName);
    _oldRuns = CodeHighlighter.highlightLines(oldText, language, brightness);
    _newRuns = CodeHighlighter.highlightLines(newText, language, brightness);
    _highlightTime = sw.elapsed;
    _composers.clear();
    _stats.reset();
    _jumpTime = null;
    _lastJump = null;
    setState(() {
      _diff = diff;
      _busy = false;
      _status = null;
      _rebuildRows();
    });
  }

  void _rebuildRows() {
    final diff = _diff;
    if (diff == null) {
      _rows = const [];
      return;
    }
    final sw = Stopwatch()..start();
    final colors = context.boardhopColors;
    final addEmphasis = TextStyle(
      backgroundColor: colors.diffAdded.withValues(alpha: 0.28),
    );
    final removeEmphasis = TextStyle(
      backgroundColor: colors.diffRemoved.withValues(alpha: 0.28),
    );
    final threadsByLine = <int, List<PrThread>>{};
    _threadsOnFile = 0;
    for (final t in _threads) {
      if (t.filePath != _selectedFile?.path || t.rightLine == null) continue;
      threadsByLine.putIfAbsent(t.rightLine!, () => []).add(t);
      _threadsOnFile++;
    }
    final rows = <_Row>[];
    _rowByNewLine.clear();
    for (final line in diff.lines) {
      final base = switch (line.kind) {
        DiffKind.removed => _runsFor(_oldRuns, line.oldNo, line.text),
        _ => _runsFor(_newRuns, line.newNo, line.text),
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
      if (line.newNo != null) _rowByNewLine[line.newNo!] = rows.length;
      rows.add(_LineRow(line, runs));
      final n = line.newNo;
      if (n != null) {
        for (final t in threadsByLine[n] ?? const <PrThread>[]) {
          rows.add(_ThreadRow(t));
        }
        if (_composers.contains(n)) rows.add(_ComposerRow(n));
      }
    }
    _rows = rows;
    _rowsTime = sw.elapsed;
  }

  static List<CodeRun> _runsFor(List<List<CodeRun>> all, int? no, String text) {
    if (no == null || no < 1 || no > all.length) return [CodeRun(text, null)];
    return all[no - 1];
  }

  Future<void> _loadPullRequest() async {
    final client = context.read<AdoClient>();
    final src = PrDiffSource(client);
    final id = int.tryParse(_prId.text.trim());
    if (id == null) return;
    setState(() {
      _busy = true;
      _status = 'Loading PR $id…';
      _source = _Source.live;
    });
    try {
      final pr = await src.pullRequest(_org.text.trim(), id);
      final iterations = await src.iterations(pr);
      final last = iterations.isEmpty ? null : iterations.last.id;
      List<PrFileChange> changes = const [];
      List<PrThread> threads = const [];
      if (last != null) {
        changes = await src.changes(pr, last);
        threads = await src.threads(pr, iteration: last, baseIteration: 0);
      }
      setState(() {
        _pr = pr;
        _iterations = iterations;
        _iteration = last;
        _changes = changes;
        _threads = threads;
        _selectedFile = changes.isEmpty ? null : changes.first;
        _status =
            'PR $id "${pr.title}": ${iterations.length} iterations, '
            '${changes.length} files, ${threads.length} threads '
            '(${threads.where((t) => t.filePath != null).length} on files).';
        _busy = false;
      });
      if (_selectedFile != null) await _loadFile();
    } on AdoException catch (e) {
      setState(() {
        _status = e.toString();
        _busy = false;
      });
    }
  }

  Future<void> _loadFile() async {
    final pr = _pr;
    final file = _selectedFile;
    final iteration = _iteration;
    if (pr == null || file == null || iteration == null) return;
    final src = PrDiffSource(context.read<AdoClient>());
    final it = _iterations.firstWhere((i) => i.id == iteration);
    setState(() {
      _busy = true;
      _status = 'Fetching ${file.path} at both commits…';
    });
    try {
      final sw = Stopwatch()..start();
      final oldText = file.isAdd
          ? ''
          : await src.fileAt(
              pr,
              file.originalPath ?? file.path,
              it.commonCommit,
            );
      final newText = file.isDelete
          ? ''
          : await src.fileAt(pr, file.path, it.sourceCommit);
      final fetch = sw.elapsed;
      _fileName = file.path;
      _apply(oldText, newText);
      setState(() {
        _status =
            'Fetched ${oldText.length + newText.length} chars in '
            '${fetch.inMilliseconds} ms; threads on this file: $_threadsOnFile.';
      });
    } on AdoException catch (e) {
      setState(() {
        _status = e.toString();
        _busy = false;
      });
    }
  }

  Future<void> _changeIteration(int? id) async {
    if (id == null || _pr == null) return;
    final src = PrDiffSource(context.read<AdoClient>());
    setState(() {
      _iteration = id;
      _busy = true;
    });
    try {
      final changes = await src.changes(_pr!, id);
      final threads = await src.threads(_pr!, iteration: id, baseIteration: 0);
      setState(() {
        _changes = changes;
        _threads = threads;
        _selectedFile = changes.any((c) => c.path == _selectedFile?.path)
            ? changes.firstWhere((c) => c.path == _selectedFile?.path)
            : (changes.isEmpty ? null : changes.first);
        _busy = false;
      });
      await _loadFile();
    } on AdoException catch (e) {
      setState(() {
        _status = e.toString();
        _busy = false;
      });
    }
  }

  void _toggleComposer(int newLine) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_composers.remove(newLine)) _composers.add(newLine);
      _rebuildRows();
    });
  }

  Future<void> _jumpDialog() async {
    final diff = _diff;
    if (diff == null) return;
    final ctl = TextEditingController(
      text: '${max(1, (_rowByNewLine.length * 0.9).round())}',
    );
    final target = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Jump to line'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'New-side line number'),
          onSubmitted: (v) => Navigator.of(context).pop(int.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(int.tryParse(ctl.text)),
            child: const Text('Jump'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (target != null) _jumpTo(target);
  }

  void _jumpTo(int newLine) {
    final index = _rowByNewLine[newLine];
    if (index == null) {
      setState(() => _status = 'Line $newLine is not on the new side.');
      return;
    }
    final sw = Stopwatch()..start();
    if (_listImpl == _ListImpl.superList) {
      _listController.jumpToItem(
        index: index,
        scrollController: _vertical,
        alignment: 0.2,
      );
    } else {
      // Plain ListView has no item addressing; estimate by average extent.
      final avg = _vertical.position.maxScrollExtent / max(1, _rows.length);
      _vertical.jumpTo(
        (index * avg).clamp(0, _vertical.position.maxScrollExtent),
      );
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _jumpTime = sw.elapsed;
        _lastJump = newLine;
      });
    });
  }

  String _report() {
    final diff = _diff;
    final b = StringBuffer('F5 diff probe: ');
    b.writeln(
      _source == _Source.synthetic
          ? 'synthetic $_fileName'
          : 'PR ${_pr?.id} iteration $_iteration $_fileName',
    );
    b.writeln(
      'mode ${FrameStats.buildMode}, list ${_listImpl.name}, '
      'lines ${diff?.lines.length}, hunks ${diff?.hunks}, '
      '+${diff?.added} -${diff?.removed}, edit distance ${diff?.editDistance}'
      '${diff?.truncated == true ? ' (truncated)' : ''}, '
      'max ${diff?.maxChars} chars, rows ${_rows.length}, '
      'threads on file $_threadsOnFile, composers ${_composers.length}',
    );
    b.writeln(
      'diff ${_diffTime?.inMilliseconds} ms, highlight '
      '${_highlightTime?.inMilliseconds} ms, rows ${_rowsTime?.inMilliseconds} ms, '
      'jump to $_lastJump ${_jumpTime?.inMilliseconds} ms',
    );
    b.writeln('frames: ${_stats.all.summary(_stats.budget)}');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _measureChar(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diff probe (spike F5)'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Jump to line',
            icon: const Icon(Icons.moving),
            onPressed: _diff == null ? null : _jumpDialog,
          ),
          IconButton(
            tooltip: 'Refresh stats',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
          IconButton(
            tooltip: 'Copy report',
            icon: const Icon(Icons.copy),
            onPressed: () {
              final report = _report();
              debugPrint(report);
              Clipboard.setData(ClipboardData(text: report));
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.sm,
              Spacing.lg,
              0,
            ),
            child: Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                SegmentedButton<_Source>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: _Source.synthetic,
                      label: Text('3k fixture'),
                    ),
                    ButtonSegment(value: _Source.live, label: Text('Live PR')),
                  ],
                  selected: {_source},
                  onSelectionChanged: _busy
                      ? null
                      : (s) {
                          if (s.first == _Source.synthetic) {
                            _loadSynthetic();
                          } else {
                            setState(() => _source = _Source.live);
                          }
                        },
                ),
                SegmentedButton<_ListImpl>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: _ListImpl.superList,
                      label: Text('Super'),
                    ),
                    ButtonSegment(value: _ListImpl.plain, label: Text('List')),
                  ],
                  selected: {_listImpl},
                  onSelectionChanged: (s) => setState(() {
                    _listImpl = s.first;
                    _stats.reset();
                  }),
                ),
              ],
            ),
          ),
          if (_source == _Source.live) _liveControls(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.sm,
              Spacing.lg,
              Spacing.xs,
            ),
            child: Text(
              _status ??
                  '$_fileName · ${_diff?.lines.length} lines, ${_diff?.hunks} hunks, '
                      '+${_diff?.added} −${_diff?.removed} · diff ${_diffTime?.inMilliseconds} ms · '
                      'highlight ${_highlightTime?.inMilliseconds} ms · rows ${_rowsTime?.inMilliseconds} ms'
                      '${_lastJump == null ? '' : ' · jump to $_lastJump ${_jumpTime?.inMilliseconds} ms'}\n'
                      'frames: ${_stats.all.summary(_stats.budget)}',
              style: BoardhopTheme.codeStyle(context).copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: _diff == null
                ? const Center(child: CircularProgressIndicator())
                : _diffView(context),
          ),
        ],
      ),
    );
  }

  Widget _liveControls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _org,
                  decoration: const InputDecoration(
                    labelText: 'Org',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: TextField(
                  controller: _prId,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'PR',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              FilledButton(
                onPressed: _busy ? null : _loadPullRequest,
                child: const Text('Load'),
              ),
            ],
          ),
          if (_pr != null) ...[
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                SizedBox(
                  width: 96,
                  child: DropdownButtonFormField<int>(
                    initialValue: _iteration,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Iter.',
                      isDense: true,
                    ),
                    items: [
                      for (final it in _iterations)
                        DropdownMenuItem(value: it.id, child: Text('${it.id}')),
                    ],
                    onChanged: _busy ? null : _changeIteration,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedFile?.path,
                    isDense: true,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'File',
                      isDense: true,
                    ),
                    items: [
                      for (final c in _changes)
                        DropdownMenuItem(
                          value: c.path,
                          child: Text(
                            '${c.changeType}: ${c.path}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (p) {
                            _selectedFile = _changes.firstWhere(
                              (c) => c.path == p,
                            );
                            _loadFile();
                          },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static const _gutterWidth = 88.0;

  Widget _diffView(BuildContext context) {
    final diff = _diff!;
    final width = _gutterWidth + diff.maxChars * _charWidth + Spacing.lg * 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = max(width, constraints.maxWidth);
        Widget list;
        if (_listImpl == _ListImpl.superList) {
          list = SuperListView.builder(
            controller: _vertical,
            listController: _listController,
            itemCount: _rows.length,
            itemBuilder: (context, i) => _buildRow(context, _rows[i]),
          );
        } else {
          list = ListView.builder(
            controller: _vertical,
            itemCount: _rows.length,
            itemBuilder: (context, i) => _buildRow(context, _rows[i]),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: contentWidth, child: list),
        );
      },
    );
  }

  Widget _buildRow(BuildContext context, _Row row) => switch (row) {
    _LineRow() => _DiffLineView(
      row: row,
      style: _codeStyle(context),
      gutterWidth: _gutterWidth,
      onGutterTap: row.line.newNo == null
          ? null
          : () => _toggleComposer(row.line.newNo!),
    ),
    _ThreadRow() => _ThreadView(thread: row.thread, gutterWidth: _gutterWidth),
    _ComposerRow() => _ComposerView(
      newLine: row.newLine,
      gutterWidth: _gutterWidth,
      onClose: () => _toggleComposer(row.newLine),
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
                      'Thread ${thread.id} · ${thread.status}'
                      '${thread.trackedFromLine != null && thread.trackedFromLine != thread.rightLine ? ' · moved from line ${thread.trackedFromLine}' : ''}',
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
                for (final c in thread.comments) ...[
                  const SizedBox(height: Spacing.xs),
                  Text(c.author, style: theme.textTheme.labelLarge),
                  Text(c.content, style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposerView extends StatelessWidget {
  const _ComposerView({
    required this.newLine,
    required this.gutterWidth,
    required this.onClose,
  });

  final int newLine;
  final double gutterWidth;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Comment on line $newLine',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: Spacing.xs),
                const TextField(
                  maxLines: 3,
                  minLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Leave a comment (spike: nothing is posted)',
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: onClose, child: const Text('Cancel')),
                    const SizedBox(width: Spacing.sm),
                    const Tooltip(
                      message: 'Disabled in the spike',
                      child: FilledButton(onPressed: null, child: Text('Post')),
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
