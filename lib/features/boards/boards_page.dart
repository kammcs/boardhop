import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/util/format.dart';
import '../../data/models/board.dart';
import '../../data/models/work_item.dart';
import '../../data/repositories/board_repository.dart';
import '../../data/repositories/work_item_repository.dart';
import '../../data/write_queue.dart';
import '../../theme/theme.dart';
import '../work_items/widgets/work_item_visuals.dart';
import '../shared/account_scope.dart';
import '../work_items/widgets/work_view_switch.dart';
import 'widgets/kanban_board.dart';

/// The team's Kanban board. Columns become drop slots (a split column is two
/// slots, Doing and Done); swimlanes are a filter chip row, with every lane
/// shown at once by default. A cross-slot drop writes the WEF column, the
/// mapped state and the Done flag with `test /rev`, then the rank; an
/// in-slot drop writes only the rank. Moves are optimistic and reverted
/// with the message on failure.
class BoardsPage extends StatefulWidget {
  const BoardsPage({super.key, required this.org, required this.project});

  final String org;
  final String project;

  @override
  State<BoardsPage> createState() => _BoardsPageState();
}

class _BoardsPageState extends State<BoardsPage> {
  List<BoardSummary> _boards = const [];
  String? _boardId;
  Board? _board;
  List<List<WorkItem>> _cards = const [];
  String? _rankField;
  String? _lane; // null = all lanes
  WorkItemVisuals _visuals = const WorkItemVisuals({});
  String? _error;
  bool _loading = false;
  int _movesInFlight = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({String? boardId}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final boards = context.read<BoardRepository>();
    final workItems = context.read<WorkItemRepository>();
    try {
      final types = await workItems.types(widget.org, widget.project);
      _visuals = WorkItemVisuals({for (final t in types) t.name: t});
      if (_boards.isEmpty) {
        _boards = await boards.boards(widget.org, widget.project);
      }
      final id =
          boardId ?? _boardId ?? (_boards.isEmpty ? null : _boards.first.id);
      if (id == null) {
        setState(() => _error = 'This project has no boards.');
        return;
      }
      final snapshot = await boards.load(widget.org, widget.project, id);
      if (!mounted) return;
      setState(() {
        _boardId = id;
        _board = snapshot.board;
        _cards = snapshot.cardsBySlot;
        _rankField = snapshot.rankField;
        if (_lane != null && !snapshot.board.laneNames.contains(_lane)) {
          _lane = null;
        }
      });
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(
          AuthInteractionRequired(
            e.message,
            accountId: AccountScope.maybeOf(context),
          ),
        );
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<WorkItem> _visible(int slot) {
    final board = _board;
    if (board == null || slot >= _cards.length) return const [];
    final lane = _lane;
    if (lane == null) return _cards[slot];
    return [
      for (final c in _cards[slot])
        if (BoardRepository.laneOf(board, c) == lane) c,
    ];
  }

  /// Real index in the slot for a drop at [visibleIndex] of the filtered
  /// view (computed after the card has been removed from its source).
  int _realIndex(int slot, int visibleIndex) {
    if (_lane == null) return visibleIndex.clamp(0, _cards[slot].length);
    final visible = _visible(slot);
    if (visible.isEmpty) return _cards[slot].length;
    if (visibleIndex >= visible.length) {
      return _cards[slot].indexOf(visible.last) + 1;
    }
    return _cards[slot].indexOf(visible[visibleIndex]);
  }

  Future<void> _move(
    WorkItem card,
    int fromSlot,
    int fromVisibleIndex,
    int toSlot,
    int toVisibleIndex,
  ) async {
    final board = _board;
    if (board == null) return;
    final source = _cards[fromSlot];
    final realFrom = source.indexWhere((c) => c.id == card.id);
    if (realFrom < 0) return;
    late final int realTo;
    setState(() {
      source.removeAt(realFrom);
      realTo = _realIndex(toSlot, toVisibleIndex);
      _cards[toSlot].insert(realTo, card);
      _movesInFlight++;
      _error = null;
    });
    final repo = context.read<BoardRepository>();
    try {
      if (fromSlot != toSlot) {
        final updated = await repo.move(
          widget.org,
          widget.project,
          board,
          card,
          board.slots[toSlot],
        );
        if (!mounted) return;
        setState(() {
          final i = _cards[toSlot].indexWhere((c) => c.id == card.id);
          if (i >= 0) _cards[toSlot][i] = updated;
        });
      }
      final target = _cards[toSlot];
      final at = target.indexWhere((c) => c.id == card.id);
      final block = BoardRepository.reorderBlock(target, at, _rankField);
      final ranks = await repo.reorder(
        widget.org,
        widget.project,
        block.ids,
        previousId: block.previousId,
        nextId: block.nextId,
      );
      final rankField = _rankField;
      if (!mounted || rankField == null) return;
      setState(() {
        for (var i = 0; i < target.length; i++) {
          final rank = ranks[target[i].id];
          if (rank != null) {
            target[i] = target[i].copyWithFields({rankField: rank});
          }
        }
      });
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(
          AuthInteractionRequired(
            e.message,
            accountId: AccountScope.maybeOf(context),
          ),
        );
      }
    } on AdoNetworkException {
      // Offline: keep the move on screen, queue the column write (the rank
      // is not queued; it is recomputed on the next refresh).
      if (!mounted || fromSlot == toSlot) return;
      final ops = BoardRepository.moveOps(board, card, board.slots[toSlot]);
      final queue = context.read<WriteQueue>();
      final workItems = context.read<WorkItemRepository>();
      await queue.enqueuePatch(
        org: widget.org,
        project: widget.project,
        item: card,
        ops: ops,
        description: 'Move ${card.id} to ${board.slots[toSlot].title}',
      );
      final local = await workItems.applyLocally(
        widget.org,
        widget.project,
        card,
        WriteQueue.fieldsFromOps(ops),
      );
      if (!mounted) return;
      setState(() {
        final i = _cards[toSlot].indexWhere((c) => c.id == card.id);
        if (i >= 0) _cards[toSlot][i] = local;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offline: the move will sync later.')),
      );
    } on AdoException catch (e) {
      if (!mounted) return;
      setState(() {
        _cards[toSlot].removeWhere((c) => c.id == card.id);
        _cards[fromSlot].insert(
          realFrom.clamp(0, _cards[fromSlot].length),
          card,
        );
        _error = e is AdoStaleRevisionException
            ? 'Work item ${card.id} changed elsewhere; the board was reloaded, try again.'
            : 'Could not move ${card.id}: ${e.message}';
      });
      if (e is AdoStaleRevisionException) {
        await _load();
        if (mounted) {
          setState(
            () => _error =
                'Work item ${card.id} changed elsewhere; the board was reloaded, try again.',
          );
        }
      }
    } finally {
      if (mounted) setState(() => _movesInFlight--);
    }
  }

  void _open(WorkItem item) => context.push(
    '${orgRoute(context, widget.org)}/projects/'
    '${Uri.encodeComponent(widget.project)}/work-items/${item.id}',
  );

  int _columnCount(int columnIndex) {
    var n = 0;
    final slots = _board?.slots ?? const <BoardSlot>[];
    for (var i = 0; i < slots.length && i < _cards.length; i++) {
      if (slots[i].columnIndex == columnIndex) n += _cards[i].length;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final board = _board;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.project, overflow: TextOverflow.ellipsis),
            Text(
              board == null ? 'Board' : board.name,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        leading: IconButton(
          tooltip: 'Projects',
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.go('${orgRoute(context, widget.org)}/projects'),
        ),
        actions: [
          if (_boards.length > 1)
            PopupMenuButton<String>(
              tooltip: 'Choose board',
              icon: const Icon(Icons.swap_horiz),
              onSelected: (id) => _load(boardId: id),
              itemBuilder: (context) => [
                for (final b in _boards)
                  CheckedPopupMenuItem(
                    value: b.id,
                    checked: b.id == _boardId,
                    child: Text(b.name),
                  ),
              ],
            ),
          // The switch stays rightmost so it never moves when an action
          // appears next to it.
          WorkViewSwitch(
            org: widget.org,
            project: widget.project,
            current: WorkView.board,
          ),
          const SizedBox(width: Spacing.sm),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading || _movesInFlight > 0) const LinearProgressIndicator(),
          if (_error != null)
            Material(
              color: scheme.errorContainer,
              child: ListTile(
                leading: Icon(
                  Icons.error_outline,
                  color: scheme.onErrorContainer,
                ),
                title: Text(
                  _error!,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
                trailing: IconButton(
                  tooltip: 'Dismiss',
                  icon: Icon(Icons.close, color: scheme.onErrorContainer),
                  onPressed: () => setState(() => _error = null),
                ),
              ),
            ),
          if (board != null && board.hasLanes)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(
                  Spacing.lg + MediaQuery.paddingOf(context).left,
                  Spacing.xs,
                  Spacing.lg + MediaQuery.paddingOf(context).right,
                  Spacing.xs,
                ),
                children: [
                  ChoiceChip(
                    label: const Text('All lanes'),
                    selected: _lane == null,
                    onSelected: (_) => setState(() => _lane = null),
                  ),
                  for (final lane in board.laneNames) ...[
                    const SizedBox(width: Spacing.sm),
                    ChoiceChip(
                      label: Text(lane.isEmpty ? 'Default' : lane),
                      selected: _lane == lane,
                      onSelected: (_) => setState(() => _lane = lane),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: board == null
                ? (_loading
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : const SizedBox.shrink())
                // Pull down on any column to reload; the columns sit one
                // level inside the horizontal scroller.
                : RefreshIndicator(
                    onRefresh: _load,
                    notificationPredicate: (n) =>
                        n.depth == 1 && n.metrics.axis == Axis.vertical,
                    child: KanbanBoard<WorkItem>(
                      columns: [
                        for (var i = 0; i < board.slots.length; i++)
                          KanbanColumnData<WorkItem>(
                            id: board.slots[i].id,
                            title: board.slots[i].title,
                            subtitle: board.slots[i].subtitle,
                            wipLimit: board.slots[i].column.itemLimit,
                            count: board.slots[i].column.isSplit
                                ? _columnCount(board.slots[i].columnIndex)
                                : null,
                            accent: parseHexColor(
                              board.rows.isNotEmpty
                                  ? board.rows.first.color
                                  : null,
                            ),
                            cards: _visible(i),
                          ),
                      ],
                      keyOf: (item) => item.id,
                      // `canEdit` covers board configuration, not card moves
                      // (spike S10); a move the user may not make fails as a
                      // work item write and is reverted with the message.
                      canDrag: true,
                      cardBuilder: (context, item, dragging) => WorkItemCard(
                        item: item,
                        visuals: _visuals,
                        dragging: dragging,
                        badge: board.hasLanes && _lane == null
                            ? (BoardRepository.laneOf(board, item).isEmpty
                                  ? null
                                  : BoardRepository.laneOf(board, item))
                            : null,
                      ),
                      onCardTap: _open,
                      onMove: _move,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
