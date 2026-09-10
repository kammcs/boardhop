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
import '../../theme/theme.dart';
import '../work_items/widgets/work_item_visuals.dart';
import 'widgets/kanban_board.dart';

/// The team's Kanban board with drag-and-drop column moves written through
/// the WEF column field plus the mapped state (spike w02), guarded by
/// `test /rev`. Moves are optimistic and reverted on failure.
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
      final id = boardId ?? _boardId ?? (_boards.isEmpty ? null : _boards.first.id);
      if (id == null) {
        setState(() => _error = 'This project has no boards.');
        return;
      }
      final snapshot = await boards.load(widget.org, widget.project, id);
      if (!mounted) return;
      setState(() {
        _boardId = id;
        _board = snapshot.board;
        _cards = snapshot.cardsByColumn;
      });
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(AuthInteractionRequired(e.message));
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _move(
    WorkItem card,
    int fromColumn,
    int fromIndex,
    int toColumn,
    int toIndex,
  ) async {
    final board = _board;
    if (board == null) return;
    // Optimistic: move locally, then write; revert if the write fails.
    setState(() {
      _cards[fromColumn].removeAt(fromIndex);
      _cards[toColumn].insert(toIndex, card);
      _movesInFlight++;
      _error = null;
    });
    if (fromColumn == toColumn) {
      // Reordering inside a column is local only; rank writes come later.
      setState(() => _movesInFlight--);
      return;
    }
    final target = board.columns[toColumn];
    try {
      final updated = await context.read<BoardRepository>().move(
        widget.org,
        widget.project,
        board,
        card,
        target,
      );
      if (!mounted) return;
      setState(() {
        final i = _cards[toColumn].indexWhere((c) => c.id == card.id);
        if (i >= 0) _cards[toColumn][i] = updated;
      });
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(AuthInteractionRequired(e.message));
      }
    } on AdoException catch (e) {
      if (!mounted) return;
      setState(() {
        _cards[toColumn].removeWhere((c) => c.id == card.id);
        _cards[fromColumn].insert(
          fromIndex.clamp(0, _cards[fromColumn].length),
          card,
        );
        _error = e is AdoStaleRevisionException
            ? 'Work item ${card.id} changed elsewhere; refresh and try again.'
            : 'Could not move ${card.id}: ${e.message}';
      });
    } finally {
      if (mounted) setState(() => _movesInFlight--);
    }
  }

  void _open(WorkItem item) => context.push(
    '/orgs/${Uri.encodeComponent(widget.org)}/projects/'
    '${Uri.encodeComponent(widget.project)}/work-items/${item.id}',
  );

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
              context.go('/orgs/${Uri.encodeComponent(widget.org)}/projects'),
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
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
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
                leading: Icon(Icons.error_outline, color: scheme.onErrorContainer),
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
          Expanded(
            child: board == null
                ? (_loading
                      ? const Center(child: CircularProgressIndicator.adaptive())
                      : const SizedBox.shrink())
                : KanbanBoard<WorkItem>(
                    columns: [
                      for (var c = 0; c < board.columns.length; c++)
                        KanbanColumnData<WorkItem>(
                          id: board.columns[c].id,
                          title: board.columns[c].name,
                          subtitle: board.columns[c].isSplit
                              ? 'Doing · Done'
                              : null,
                          wipLimit: board.columns[c].itemLimit,
                          accent: parseHexColor(
                            board.rows.isNotEmpty ? board.rows.first.color : null,
                          ),
                          cards: c < _cards.length ? _cards[c] : const [],
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
                    ),
                    onCardTap: _open,
                    onMove: _move,
                  ),
          ),
        ],
      ),
    );
  }
}
