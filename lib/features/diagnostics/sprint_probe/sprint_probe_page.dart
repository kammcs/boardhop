import 'package:flutter/material.dart';

import '../../../data/models/work_item.dart';
import '../../../theme/theme.dart';
import '../../boards/widgets/kanban_board.dart';
import '../../sprints/widgets/person_filter_menu.dart';
import '../../sprints/widgets/sprint_burndown_chart.dart';
import '../../sprints/widgets/sprint_format.dart';
import '../../sprints/widgets/sprint_header.dart';
import '../../sprints/widgets/sprint_picker_sheet.dart';
import '../../sprints/widgets/story_chip_strip.dart';
import '../../sprints/widgets/task_card_sheet.dart';
import '../../sprints/widgets/taskboard_grid.dart';
import '../../../data/models/sprint.dart';
import '../../work_items/widgets/work_item_visuals.dart';
import 'sprint_probe_data.dart';

/// Phase P-B probe: every sprint widget on canned data, so the grid, the
/// move sheet, the chart, the header and the pickers can be looked at on
/// both simulators in light and dark and at xxxL without a network, an
/// account or a repository.
///
/// Diagnostics only (`AppConfig.diagnosticsEnabled`), like the board and
/// mention probes.
class SprintProbePage extends StatefulWidget {
  const SprintProbePage({super.key});

  @override
  State<SprintProbePage> createState() => _SprintProbePageState();
}

class _SprintProbePageState extends State<SprintProbePage> {
  final SprintProbeState _state = SprintProbeState(SprintProbeData.generate());

  @override
  Widget build(BuildContext context) {
    final data = _state.data;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sprint widgets (P-B)'),
          actions: [
            PersonFilterMenu(
              people: _state.people,
              selected: _state.person,
              meCount: 2,
              onSelected: (value) => setState(() => _state.person = value),
            ),
            IconButton(
              tooltip: 'Sprint picker',
              icon: const Icon(Icons.calendar_month),
              onPressed: () async {
                final picked = await showSprintPicker(
                  context,
                  iterations: data.iterations,
                  teamName: 'DevOps Mobile App Team',
                  currentIterationId: _state.iterationId,
                  teams: const [
                    SprintTeamRef(id: 't1', name: 'DevOps Mobile App Team'),
                    SprintTeamRef(id: 't2', name: 'Relay Team'),
                  ],
                );
                if (picked is SprintIterationPicked) {
                  setState(() => _state.iterationId = picked.iteration.id);
                }
                if (picked is SprintTeamPicked && mounted) {
                  setState(() => _state.note = 'Team: ${picked.team.name}');
                }
              },
            ),
            const SizedBox(width: Spacing.sm),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Grid (tablet)'),
              Tab(text: 'Phone'),
              Tab(text: 'Burndown'),
              Tab(text: 'Header'),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              if (_state.note.isNotEmpty)
                Material(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: ListTile(
                    dense: true,
                    title: Text(_state.note),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _state.note = ''),
                    ),
                  ),
                ),
              Expanded(
                child: TabBarView(
                  children: [_grid(), _phone(), _burndown(), _header()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid() => TaskboardGrid(
    columns: _state.data.columns,
    rows: _state.visibleRows,
    columnOf: _state.columnOf,
    visuals: _state.data.visuals,
    cardBuilder: (context, card, dragging) => WorkItemCard(
      item: card,
      visuals: _state.data.visuals,
      dragging: dragging,
      badge:
          formatRemaining(card.field<num>(kRemainingWorkField)?.toDouble())
              .isEmpty
          ? null
          : formatRemaining(card.field<num>(kRemainingWorkField)!.toDouble()),
    ),
    onMove: (card, fromRow, fromColumn, toRow, toColumn, toIndex) =>
        setState(() => _state.move(card, toRow, toColumn, toIndex)),
    onAddTask: (row) => setState(
      () => _state.note = 'Add task under ${row.parent?.id ?? 'Unparented'}',
    ),
    onCardTap: (card) => setState(() => _state.note = 'Open ${card.id}'),
    onRowTap: (row) =>
        setState(() => _state.note = 'Open story ${row.parent?.id}'),
    onCardLongPress: _openSheet,
  );

  Widget _phone() {
    final rows = _state.visibleRows;
    final tasks = [
      for (final row in rows)
        if (_state.selectedRow == null ||
            sprintRowKey(row) == _state.selectedRow)
          ...row.tasks,
    ];
    return Column(
      children: [
        StoryChipStrip(
          rows: rows,
          visuals: _state.data.visuals,
          selected: _state.selectedRow,
          onSelected: (key) => setState(() => _state.selectedRow = key),
        ),
        Expanded(
          child: KanbanBoard<WorkItem>(
            columns: [
              for (var c = 0; c < _state.data.columns.length; c++)
                KanbanColumnData<WorkItem>(
                  id: _state.data.columns[c].name,
                  title: _state.data.columns[c].name,
                  cards: [
                    for (final task in tasks)
                      if (_state.columnOf(task) == c) task,
                  ],
                ),
            ],
            keyOf: (card) => card.id,
            cardBuilder: (context, card, dragging) => WorkItemCard(
              item: card,
              visuals: _state.data.visuals,
              dragging: dragging,
              badge: _state.parentIdOf(card),
            ),
            onCardTap: _openSheet,
            onMove: (card, fromColumn, fromIndex, toColumn, toIndex) =>
                setState(() => _state.moveToColumn(card, toColumn)),
          ),
        ),
      ],
    );
  }

  Widget _burndown() => ListView(
    padding: Spacing.page,
    children: [
      Text('Sparkline', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: Spacing.sm),
      SprintBurndownChart(days: _state.data.days),
      const SizedBox(height: Spacing.xl),
      Text('Full', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: Spacing.sm),
      SprintBurndownChart(
        days: _state.data.days,
        mode: BurndownMode.full,
        showPoints: true,
      ),
      const SizedBox(height: Spacing.sm),
      const BurndownLegend(showPoints: true),
      const SizedBox(height: Spacing.xl),
      Text('Empty', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: Spacing.sm),
      const SprintBurndownChart(days: [], mode: BurndownMode.full),
      const Text('(draws nothing and does not throw)'),
    ],
  );

  Widget _header() => ListView(
    padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
    children: [
      SprintHeader(
        data: SprintHeaderData(
          // The figure the taskboard has now, which is the last day of the
          // canned burndown.
          remaining: 6,
          done: 4,
          total: 12,
          scopeChange: 6,
          days: _state.data.days,
          start: DateTime.utc(2026, 9, 7),
          finish: DateTime.utc(2026, 9, 18),
          now: DateTime.utc(2026, 9, 15),
        ),
        onTileTap: (which) => setState(() => _state.note = 'Tile: $which'),
      ),
      SprintHeader(
        data: SprintHeaderData(
          remaining: null,
          done: 0,
          total: 0,
          start: null,
          finish: null,
          now: DateTime.utc(2026, 9, 15),
        ),
      ),
      SprintHeader(
        data: SprintHeaderData(
          remaining: 12,
          done: 10,
          total: 12,
          days: _state.data.days,
          start: DateTime.utc(2026, 8, 24),
          finish: DateTime.utc(2026, 9, 4),
          isEnded: true,
          now: DateTime.utc(2026, 9, 15),
        ),
      ),
    ],
  );

  Future<void> _openSheet(WorkItem card) async {
    final action = await showTaskCardSheet(
      context,
      task: card,
      columns: _state.data.columns,
      visuals: _state.data.visuals,
      currentColumn: _state.columnOf(card),
    );
    if (!mounted || action == null) return;
    setState(() {
      switch (action) {
        case MoveTaskAction(:final columnIndex, :final column):
          _state.moveToColumn(card, columnIndex);
          _state.note = 'Moved ${card.id} to ${column.name}';
        case SetRemainingWorkAction(:final hours):
          _state.setRemaining(card, hours);
          _state.note = 'Remaining work on ${card.id} → $hours';
        case AssignToMeAction():
          _state.note = 'Assign ${card.id} to me';
        case OpenTaskAction():
          _state.note = 'Open ${card.id}';
      }
    });
  }
}

/// Mutable probe state: the canned sprint plus the moves made on it.
class SprintProbeState {
  SprintProbeState(this.data) : rows = [...data.rows];

  final SprintProbeData data;
  List<SprintRow> rows;
  String? person;
  String? selectedRow;
  String iterationId = 'iter-1';
  String note = '';

  List<SprintPerson> get people => const [
    SprintPerson(id: 'person-0', displayName: 'Kim Kaur', count: 2),
    SprintPerson(id: 'person-1', displayName: 'Ada Moss', count: 2),
    SprintPerson(id: 'person-2', displayName: 'Joel Reyes', count: 2),
    SprintPerson(id: 'person-3', displayName: 'Tia Sundar', count: 2),
  ];

  List<SprintRow> get visibleRows {
    if (person == null || person == kMePersonFilter) return rows;
    return [
      for (final row in rows)
        SprintRow(
          parent: row.parent,
          tasks: [
            for (final task in row.tasks)
              if (task.assignedTo?.id == person) task,
          ],
          remaining: row.remaining,
          done: row.done,
        ),
    ];
  }

  /// Stands in for `SprintRepository.columnFor`: the first column whose
  /// mapping for this type matches the item's state.
  int columnOf(WorkItem task) {
    for (var c = 0; c < data.columns.length; c++) {
      if (data.columns[c].mappings[task.type] == task.state) return c;
    }
    return 0;
  }

  String? parentIdOf(WorkItem task) {
    for (final row in rows) {
      if (row.tasks.any((t) => t.id == task.id)) {
        return row.parent == null ? 'Unparented' : '#${row.parent!.id}';
      }
    }
    return null;
  }

  void move(WorkItem card, int toRow, int toColumn, int toIndex) {
    final state = data.columns[toColumn].mappings[card.type];
    if (state == null) return;
    _replace(card, card.copyWithFields({'System.State': state}));
  }

  void moveToColumn(WorkItem card, int toColumn) => move(card, 0, toColumn, 0);

  void setRemaining(WorkItem card, double hours) =>
      _replace(card, card.copyWithFields({kRemainingWorkField: hours}));

  void _replace(WorkItem card, WorkItem updated) {
    rows = [
      for (final row in rows)
        SprintRow(
          parent: row.parent,
          tasks: [
            for (final task in row.tasks)
              if (task.id == card.id) updated else task,
          ],
          remaining: row.remaining,
          done: row.done,
        ),
    ];
  }
}
