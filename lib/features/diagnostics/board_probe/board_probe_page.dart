import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/theme.dart';
import 'board_probe_data.dart';
import 'frame_stats.dart';
import 'hand_rolled_board.dart';
import 'probe_widgets.dart';

/// Spike F4: the Kanban drag-and-drop probe on generated data, with frame
/// timings for the whole session and for the drags alone.
///
/// The spike compared `drag_and_drop_lists`, `appflowy_board`, `boardview`
/// and Flutter's own drag primitives on this page; the primitives won (see
/// research/spikes/results/README.md) and are the only board left here.
class BoardProbePage extends StatefulWidget {
  const BoardProbePage({super.key});

  @override
  State<BoardProbePage> createState() => _BoardProbePageState();
}

class _BoardProbePageState extends State<BoardProbePage> {
  static const _description = 'Flutter LongPressDraggable + DragTarget';

  final _stats = FrameStats();
  int _cardCount = 200;
  late BoardData _data = BoardData.generate(cards: _cardCount);
  int _moves = 0;
  int _drags = 0;
  int _generation = 0;
  String _lastMove = '-';
  late final _hooks = BoardProbeHooks(
    onDragStart: () {
      _drags++;
      _stats.dragging = true;
    },
    onDragEnd: () {
      _stats.dragging = false;
      if (mounted) setState(() {});
    },
    onMove: (m) {
      _moves++;
      final from = _data.columns[m.fromColumn].name;
      final to = _data.columns[m.toColumn].name;
      _lastMove = '#${m.card.id} $from[${m.fromIndex}] → $to[${m.toIndex}]';
    },
  );

  @override
  void initState() {
    super.initState();
    _stats.attach();
  }

  @override
  void dispose() {
    _stats.detach();
    super.dispose();
  }

  void _reset({int? cards}) {
    setState(() {
      _cardCount = cards ?? _cardCount;
      _data = BoardData.generate(cards: _cardCount);
      _stats.reset();
      _moves = 0;
      _drags = 0;
      _lastMove = '-';
      _generation++;
    });
  }

  String _report() {
    final b = StringBuffer('F4 board probe: $_description\n');
    b.writeln(
      'mode ${FrameStats.buildMode}, cards $_cardCount across '
      '${_data.columns.length} columns, drags $_drags, moves $_moves',
    );
    b.writeln('all:  ${_stats.all.summary(_stats.budget)}');
    b.writeln('drag: ${_stats.drag.summary(_stats.budget)}');
    b.writeln('last move: $_lastMove');
    b.writeln(
      'columns: ${_data.columns.map((c) => '${c.name}=${c.cards.length}').join(', ')}',
    );
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Board probe (spike F4)'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh stats',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
          IconButton(
            tooltip: 'Reset data and stats',
            icon: const Icon(Icons.restart_alt),
            onPressed: _reset,
          ),
          IconButton(
            tooltip: 'Copy report',
            icon: const Icon(Icons.copy),
            onPressed: () {
              final report = _report();
              // Also to the console so a run over adb can collect the numbers.
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
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$_description · ${FrameStats.buildMode}',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 200, label: Text('200')),
                    ButtonSegment(value: 1000, label: Text('1k')),
                  ],
                  selected: {_cardCount},
                  onSelectionChanged: (s) => _reset(cards: s.first),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.sm,
              Spacing.lg,
              Spacing.xs,
            ),
            child: Text(
              'drags $_drags · moves $_moves · $_lastMove\n'
              'all:  ${_stats.all.summary(_stats.budget)}\n'
              'drag: ${_stats.drag.summary(_stats.budget)}',
              style: BoardhopTheme.codeStyle(
                context,
              ).copyWith(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey((_cardCount, _generation)),
              child: HandRolledBoard(data: _data, hooks: _hooks),
            ),
          ),
        ],
      ),
    );
  }
}
