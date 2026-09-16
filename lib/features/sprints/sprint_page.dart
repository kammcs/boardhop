import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../auth/auth_service.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/routes.dart';
import '../../core/util/format.dart';
import '../../data/models/sprint.dart';
import '../../data/models/work_item.dart';
import '../../data/models/work_item_form.dart';
import '../../data/repositories/analytics_repository.dart';
import '../../data/repositories/board_repository.dart';
import '../../data/repositories/sprint_repository.dart';
import '../../data/repositories/work_item_repository.dart';
import '../../theme/theme.dart';
import '../boards/move_choreography.dart';
import '../boards/widgets/kanban_board.dart';
import '../boards/widgets/new_card_row.dart';
import '../shared/account_scope.dart';
import '../shared/widgets/tab_count_badge.dart';
import '../work_items/form/new_work_item_button.dart';
import '../work_items/widgets/work_item_visuals.dart';
import '../work_items/widgets/work_view_switch.dart';
import 'sprint_prefs.dart';
import 'widgets/person_filter_menu.dart';
import 'widgets/sprint_backlog_tab.dart';
import 'widgets/sprint_burndown_chart.dart';
import 'widgets/sprint_burndown_tab.dart';
import 'widgets/sprint_format.dart';
import 'widgets/sprint_header.dart';
import 'widgets/sprint_picker_sheet.dart';
import 'widgets/story_chip_strip.dart';
import 'widgets/task_card_sheet.dart';
import 'widgets/taskboard_grid.dart';
import '../projects/widgets/project_picker_button.dart';

/// The Sprint view: the third segment of the Work pill (decision S1).
///
/// Three tabs over one snapshot (S2) — Backlog, Taskboard, Burndown — for
/// the team's current sprint unless the route names another. The page reads
/// cache first and network second at every step, because resolving a
/// sprint is three network reads deep (default team → iterations →
/// snapshot) and a cold `teamsettings/iterations` on a hundred-iteration
/// team took 19 seconds once (spike s54).
class SprintPage extends StatefulWidget {
  const SprintPage({
    super.key,
    required this.org,
    required this.project,
    this.iteration,
    this.initialTab,
  });

  final String org;
  final String project;

  /// Team iteration GUID; null means the team's current sprint.
  final String? iteration;

  /// `backlog`, `taskboard` or `burndown`.
  final String? initialTab;

  @override
  State<SprintPage> createState() => _SprintPageState();
}

class _SprintPageState extends State<SprintPage>
    with SingleTickerProviderStateMixin {
  static const _backlogTab = 0;
  static const _taskboardTab = 1;
  static const _burndownTab = 2;

  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(_onTabChanged);

  String? _teamId;
  String? _teamName;

  /// The project's teams, for the picker's switch row (S8). Read off the
  /// critical path and empty until it answers; the row is hidden below two.
  List<SprintTeamRef> _teams = const [];
  SprintIterations _iterations = const SprintIterations();
  String? _iterationId;
  SprintSnapshot? _snapshot;
  SprintCapacity? _capacity;
  WorkItemVisuals _visuals = const WorkItemVisuals({});

  List<BurndownDay> _burndown = const [];
  bool _burndownLoading = false;
  bool _burndownAsked = false;
  bool _analyticsRefused = false;
  String? _burndownError;

  /// null = Everyone, [kMePersonFilter] = Me, else an identity id.
  String? _person;

  /// The phone's row axis: null = All, [kUnparentedRowKey], else a parent id.
  String? _story;

  String? _me;
  String? _error;
  bool _loading = false;
  int _writesInFlight = 0;

  /// Where the snapshot on screen came from, and whether the last refresh
  /// failed with a network error — the board's own offline treatment (S9).
  DateTime? _shownAt;
  bool _offline = false;

  /// Whether the tab on screen was chosen (by the route, by the person, or
  /// from the remembered one) rather than still being the default.
  bool _tabChosen = false;

  /// True while the page is setting the default tab itself, so the
  /// controller's listener does not record it as the person's choice — and
  /// go on to remember it and put it in the route.
  bool _settingDefault = false;

  int? _flashId;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    // The route names the sprint only on the first build; from then on
    // `_iterationId` is the page's own answer and the route follows it.
    _iterationId = widget.iteration;
    final fromRoute = SprintPrefs.tabs.indexOf(widget.initialTab ?? '');
    if (fromRoute >= 0) {
      _tabs.index = fromRoute;
      _tabChosen = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void didUpdateWidget(SprintPage old) {
    super.didUpdateWidget(old);
    // The route changed under the same State — a deep link, a
    // notification, or the picker, which navigates rather than calling
    // setState. The picker has already set `_iterationId` and loaded, so
    // the second check makes this a no-op for it.
    if (widget.iteration == old.iteration) return;
    if (widget.iteration == _iterationId) return;
    // Back to the plain route means "whichever sprint is current", so the
    // page works it out again rather than staying where it was.
    _iterationId = widget.iteration;
    unawaited(_load());
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging || _settingDefault) return;
    setState(() => _tabChosen = true);
    unawaited(SprintPrefs.setLastTab(widget.org, widget.project, _tabs.index));
    if (_tabs.index == _burndownTab) unawaited(_loadBurndown());
  }

  // ------------------------------------------------------------- loading

  Future<void> _start() async {
    final remembered = await SprintPrefs.lastTab(widget.org, widget.project);
    if (remembered != null && !_tabChosen && mounted) {
      _tabs.index = remembered;
      _tabChosen = true;
    }
    if (!mounted) return;
    _me ??= context
        .read<AuthService>()
        .accountById(AccountScope.of(context))
        ?.username;
    await _load();
  }

  /// The cached snapshot, drawn before anything touches the network.
  ///
  /// Which sprint that is, is itself the question: the route may name one,
  /// and otherwise the last one opened in this project is remembered, since
  /// resolving "current" needs the team and the iteration list.
  Future<void> _drawCached() async {
    if (_snapshot != null) return;
    final id =
        widget.iteration ??
        _iterationId ??
        await SprintPrefs.lastIteration(widget.org, widget.project);
    if (id == null || !mounted) return;
    final repo = context.read<SprintRepository>();
    final cached = await repo.cachedSnapshot(
      widget.org,
      widget.project,
      id,
      team: _teamId,
    );
    if (cached == null || !mounted || _snapshot != null) return;
    setState(() {
      // Deliberately *not* `_iterationId = id`. The remembered sprint is
      // only here so a cold open has something to draw; the plain route
      // means "whichever sprint is current" and the iteration list is what
      // decides that. Adopting the memory here reopened last week's sprint
      // from the plain route (iPhone check, P-C).
      _snapshot = cached;
      _shownAt = cached.fetchedAt;
      _applyDefaultTab(cached);
    });
  }

  /// The sprint the page is on: the one it resolved, or — before that has
  /// happened, or offline — the one the cached snapshot belongs to.
  String? get _sprintId => _iterationId ?? _snapshot?.iteration.id;

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = context.read<SprintRepository>();
    final workItems = context.read<WorkItemRepository>();
    await _drawCached();
    try {
      final types = await workItems.types(widget.org, widget.project);
      if (!mounted) return;
      _visuals = WorkItemVisuals({for (final t in types) t.name: t});
      _teamId ??= await repo.defaultTeamId(widget.org, widget.project);
      _teamName ??= await repo.defaultTeamName(widget.org, widget.project);
      final iterations = await repo.iterations(
        widget.org,
        widget.project,
        team: _teamId,
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() => _iterations = iterations);
      // `_iterationId` first, not the route: the picker sets it and then
      // navigates, and `widget.iteration` is still the *previous* sprint
      // for the rest of that frame. Reading the route here put Iteration
      // 3's (empty) contents under Iteration 2's title on the second
      // switch in a row (iPhone check, P-C).
      //
      // S12: a sprint the service still calls current opens as current
      // even when its finish date has passed.
      final chosen =
          (_iterationId == null ? null : iterations.byId(_iterationId!)) ??
          iterations.defaultIteration;
      if (chosen == null) {
        setState(() => _error = 'This team has no sprints.');
        return;
      }
      _iterationId = chosen.id;
      unawaited(
        SprintPrefs.setLastIteration(widget.org, widget.project, chosen.id),
      );
      final snapshot = await repo.load(
        widget.org,
        widget.project,
        chosen.id,
        team: _teamId,
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _shownAt = null;
        _offline = false;
        _applyDefaultTab(snapshot);
        if (_story != null &&
            !snapshot.allRows.any((r) => sprintRowKey(r) == _story)) {
          _story = null;
        }
      });
      unawaited(_loadCapacity());
      unawaited(_loadTeams());
      // The chart is never on the taskboard's critical path (research/18
      // S6): it is asked for after the first frame the sprint is on.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_loadBurndown()),
      );
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(
          AuthInteractionRequired(
            e.message,
            accountId: AccountScope.maybeOf(context),
          ),
        );
      }
    } on AdoNetworkException catch (e) {
      // Offline with a sprint on screen is not an error: say where it came
      // from and leave it there, as the board now does (S9).
      if (!mounted) return;
      setState(() {
        if (_snapshot == null) {
          _error = e.message;
        } else {
          _offline = true;
        }
      });
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Taskboard when the sprint has tasks, Backlog when it has none (S2).
  /// Only until the person, the route or the remembered tab has spoken.
  void _applyDefaultTab(SprintSnapshot snapshot) {
    if (_tabChosen) return;
    _settingDefault = true;
    _tabs.index = snapshot.tasks.isNotEmpty ? _taskboardTab : _backlogTab;
    _settingDefault = false;
  }

  /// The picker's team switch (S8). Never on the critical path: the list
  /// is only needed when the sheet opens, it is cached a day, and a project
  /// the account cannot enumerate teams on simply shows no switch.
  Future<void> _loadTeams() async {
    if (_teams.isNotEmpty || !mounted) return;
    try {
      final teams = await context.read<SprintRepository>().teams(
        widget.org,
        widget.project,
      );
      if (mounted && teams.isNotEmpty) setState(() => _teams = teams);
    } on AdoException {
      // No switch rather than an error: the sprint itself is fine.
    }
  }

  Future<void> _loadCapacity() async {
    final id = _sprintId;
    if (id == null || !mounted) return;
    try {
      final capacity = await context.read<SprintRepository>().capacities(
        widget.org,
        widget.project,
        id,
        team: _teamId,
      );
      // S7: the strip exists only when the team actually filled it in.
      if (mounted && !capacity.isEmpty) setState(() => _capacity = capacity);
    } on AdoException {
      // Capacity is decoration; a project that cannot read it shows none.
    }
  }

  Future<void> _loadBurndown({bool refresh = false}) async {
    final id = _sprintId;
    final iteration = _iteration;
    if (id == null || iteration == null || !mounted) return;
    if (_burndownLoading) return;
    if (_burndownAsked && !refresh) return;
    final start = iteration.startDate;
    final finish = iteration.finishDate;
    // No dates, nothing to burn down against; the tab explains.
    if (start == null || finish == null) {
      setState(() => _burndownAsked = true);
      return;
    }
    setState(() {
      _burndownLoading = true;
      _burndownAsked = true;
      _burndownError = null;
    });
    try {
      final days = await context.read<AnalyticsRepository>().burndown(
        widget.org,
        widget.project,
        id,
        start: start,
        end: finish,
        refresh: refresh,
      );
      if (mounted) {
        setState(() {
          _burndown = days;
          _analyticsRefused = false;
        });
      }
    } on AnalyticsUnavailable {
      // Not an AdoAuthException on purpose (P-A §2): a chart never pushes
      // anyone into an interactive sign-in.
      if (mounted) setState(() => _analyticsRefused = true);
    } on AdoException catch (e) {
      if (mounted) setState(() => _burndownError = e.message);
    } finally {
      if (mounted) setState(() => _burndownLoading = false);
    }
  }

  Future<void> _refresh() async {
    _burndownAsked = false;
    await _load(refresh: true);
    await _loadBurndown(refresh: true);
  }

  // -------------------------------------------------------------- derived

  TeamIteration? get _iteration {
    final snapshot = _snapshot;
    final id = _iterationId;
    if (id != null) {
      final known = _iterations.byId(id);
      if (known != null) return known;
    }
    return snapshot?.iteration;
  }

  List<TaskboardColumn> get _columns => _snapshot?.columns ?? const [];

  bool _matchesPerson(WorkItem task) {
    final person = _person;
    if (person == null) return true;
    final assigned = task.assignedTo;
    if (assigned == null) return false;
    if (person == kMePersonFilter) {
      final me = _me;
      return me != null &&
          (assigned.uniqueName?.toLowerCase() == me.toLowerCase());
    }
    return (assigned.id ?? assigned.uniqueName) == person;
  }

  /// Every row with the person filter applied to its tasks. The rollups are
  /// recomputed so a filtered row says what it is actually showing.
  List<SprintRow> get _rows {
    final snapshot = _snapshot;
    if (snapshot == null) return const [];
    if (_person == null) return snapshot.allRows;
    return [
      for (final row in snapshot.allRows)
        () {
          final tasks = [
            for (final t in row.tasks)
              if (_matchesPerson(t)) t,
          ];
          final totals = SprintRepository.rollup(
            tasks,
            snapshot.columns,
            explicitColumns: snapshot.explicitColumns,
          );
          return SprintRow(
            parent: row.parent,
            tasks: tasks,
            remaining: totals.remaining,
            done: totals.done,
          );
        }(),
    ];
  }

  /// The taskboard's rows: only the ones that have tasks. CloudCover 2.0's
  /// current sprint has 143 requirement rows and 5 task-type items; a grid
  /// of 143 mostly empty rows is not a taskboard (research/18 §5.3). A
  /// story with no tasks is reached from the Backlog tab's "Add task".
  List<SprintRow> get _taskboardRows => [
    for (final row in _rows)
      if (row.tasks.isNotEmpty) row,
  ];

  List<WorkItem> get _tasks => [for (final row in _rows) ...row.tasks];

  /// The row a task sits in, as an index into [_taskboardRows].
  int _rowOf(WorkItem task) =>
      _taskboardRows.indexWhere((r) => r.tasks.any((t) => t.id == task.id));

  int _columnOf(WorkItem task) => SprintRepository.columnIndexFor(
    _columns,
    task,
    explicitColumns: _snapshot?.explicitColumns ?? const {},
  );

  List<SprintPerson> get _people {
    final snapshot = _snapshot;
    if (snapshot == null) return const [];
    final counts = <String, ({String name, int count})>{};
    for (final task in snapshot.tasks) {
      final who = task.assignedTo;
      if (who == null) continue;
      final key = who.id ?? who.uniqueName ?? who.displayName;
      final seen = counts[key];
      counts[key] = (name: who.displayName, count: (seen?.count ?? 0) + 1);
    }
    final people = [
      for (final e in counts.entries)
        SprintPerson(
          id: e.key,
          displayName: e.value.name,
          count: e.value.count,
        ),
    ]..sort((a, b) => a.displayName.compareTo(b.displayName));
    return people;
  }

  int? get _meCount {
    final snapshot = _snapshot;
    final me = _me;
    if (snapshot == null || me == null) return null;
    return snapshot.tasks
        .where(
          (t) => t.assignedTo?.uniqueName?.toLowerCase() == me.toLowerCase(),
        )
        .length;
  }

  /// What the header counts. Hours when the team fills Remaining Work in,
  /// otherwise items — which is every team probed (spike s54).
  /// The same figures over the **whole** sprint, whatever the person filter
  /// is set to. The header is about the sprint: its verdict compares
  /// against a burndown series Analytics computed for everyone, so a
  /// filtered "remaining" next to an unfiltered ideal line reads as
  /// "1.3 items/day ahead" the moment you filter to yourself (iPhone
  /// check, P-C). The lists below it are what the filter narrows.
  ({double? remaining, int done, int total, String unit}) get _sprintTotals =>
      _totalsOver(_snapshot?.tasks ?? const []);

  ({double? remaining, int done, int total, String unit}) _totalsOver(
    List<WorkItem> tasks,
  ) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return (remaining: null, done: 0, total: 0, unit: 'items');
    }
    final totals = SprintRepository.rollup(
      tasks,
      snapshot.columns,
      explicitColumns: snapshot.explicitColumns,
    );
    // `> 0`, not `!= null`: clearing Remaining Work writes a real 0 (the
    // service refuses null), so one cleared task left the header of a
    // 14-task sprint reading "Remaining 0 h" for good (iPhone check, P-D).
    // Zero hours is the same answer as no hours — count the items.
    final hours = totals.remaining;
    if (hours != null && hours > 0) {
      return (
        remaining: hours,
        done: totals.done,
        total: tasks.length,
        unit: 'h',
      );
    }
    return (
      remaining: (tasks.length - totals.done).toDouble(),
      done: totals.done,
      total: tasks.length,
      unit: 'items',
    );
  }

  SprintHeaderData get _headerData {
    final totals = _sprintTotals;
    final iteration = _iteration;
    final days = _burndown;
    return SprintHeaderData(
      remaining: totals.remaining,
      done: totals.done,
      total: totals.total,
      scopeChange: days.length < 2
          ? null
          : (days.last.scope - days.first.scope).toDouble(),
      // The sparkline is items even when the rollup is in hours — Analytics
      // counts work items, never Remaining Work (research/18 §1) — so the
      // series goes in whole and `seriesUnit` keeps the two apart. Dropping
      // it when the unit was hours made one task with 2 h on it hide four
      // days of burndown behind "No burndown data" (iPhone check, P-D).
      days: days,
      ideal: burndownIdealLine(days, finish: iteration?.finishDate),
      start: iteration?.startDate,
      finish: iteration?.finishDate,
      isEnded: iteration?.isEnded() ?? false,
      unit: totals.unit,
      seriesUnit: 'items',
    );
  }

  // --------------------------------------------------------------- writes

  Future<void> _move(
    WorkItem card,
    int fromRow,
    int fromColumn,
    int toRow,
    int toColumn,
    int toIndex,
  ) async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    // Decision P-C: the grid reports a cross-row drop, but re-parenting is
    // a `System.Parent` write the sprint's move does not do and the web
    // taskboard does not offer either. Refuse it out loud rather than
    // silently dropping the card back.
    if (toRow != fromRow) {
      _say('Moving a task to another story is not supported yet');
      return;
    }
    if (toColumn < 0 || toColumn >= _columns.length) return;
    final target = _columns[toColumn];
    final rows = _taskboardRows;
    if (fromRow < 0 || fromRow >= rows.length) return;
    final parentId = rows[fromRow].parent?.id ?? 0;

    final before = snapshot;
    final reordered = _applyMoveLocally(card, fromRow, toColumn, toIndex);
    if (reordered == null) return;
    setState(() {
      _snapshot = reordered;
      _writesInFlight++;
      _error = null;
    });

    final repo = context.read<SprintRepository>();
    final iterationId = _sprintId;
    final outcome = await runMoveChoreography(
      context,
      org: widget.org,
      project: widget.project,
      card: card,
      failureLabel: 'sprint',
      offlineDescription: 'Move ${card.id} to ${target.name}',
      // S9: the state patch queues, the taskboard column call does not —
      // it is a placement among columns that share a state and is
      // recomputed from the state on the next refresh.
      offlineOps: () => SprintRepository.moveOps(target, card),
      onQueued: (local) => setState(() => _snapshot = _replace(local)),
      onFailed: (message) => setState(() {
        _snapshot = before;
        _error = message;
      }),
      write: () async {
        final updated = await repo.move(
          widget.org,
          widget.project,
          card,
          target,
          columns: _columns,
          iterationId: iterationId,
          team: _teamId,
        );
        if (!mounted) return;
        setState(() => _snapshot = _replace(updated));
        await _clearRemainingIfDone(repo, target, updated);
        if (!mounted) return;
        // Rank within the cell, the same block the board computes.
        final cell = _cellCards(fromRow, toColumn);
        final at = cell.indexWhere((c) => c.id == card.id);
        if (at < 0) return;
        final block = BoardRepository.reorderBlock(cell, at, _rankField);
        await repo.reorder(
          widget.org,
          widget.project,
          block.ids,
          previousId: block.previousId,
          nextId: block.nextId,
          parentId: parentId,
          team: _teamId,
        );
      },
    );
    if (outcome == MoveOutcome.stale && mounted) {
      final message = _error;
      await _load(refresh: true);
      if (mounted) setState(() => _error = message);
    }
    if (mounted) setState(() => _writesInFlight--);
  }

  /// A finished task must not go on claiming hours, or every rollup on the
  /// page is wrong — but the zero cannot ride in the move's own patch.
  ///
  /// The stock processes carry a rule that Remaining Work is **empty** on a
  /// task's completed state, and sending a zero with the state is refused
  /// with `TF401320 … InvalidNotEmpty` (seen on the scratch project). The
  /// rule also does the clearing itself, so on those processes the item
  /// comes back from the state patch with nothing left to do here. This is
  /// the fallback for a process that has no such rule: one extra patch,
  /// after the move, and only when the hours actually survived.
  Future<void> _clearRemainingIfDone(
    SprintRepository repo,
    TaskboardColumn target,
    WorkItem moved,
  ) async {
    if (!target.isDone) return;
    final hours = moved
        .field<num>(SprintRepository.remainingWorkField)
        ?.toDouble();
    if (hours == null || hours <= 0) return;
    try {
      final cleared = await repo.setRemainingWork(
        widget.org,
        widget.project,
        moved,
        0,
      );
      if (mounted) setState(() => _snapshot = _replace(cleared));
    } on AdoException {
      // The move itself succeeded; a process that refuses the zero as well
      // has its own opinion about the field and is allowed to keep it.
    }
  }

  static const _rankField = 'Microsoft.VSTS.Common.StackRank';

  List<WorkItem> _cellCards(int row, int column) {
    final rows = _taskboardRows;
    if (row < 0 || row >= rows.length) return const [];
    return [
      for (final task in rows[row].tasks)
        if (_columnOf(task) == column) task,
    ];
  }

  /// The optimistic half of a move: put the card at [toIndex] of the target
  /// cell and pin it to that column.
  ///
  /// The pin is an [SprintSnapshot.explicitColumns] entry, which is exactly
  /// how a customized taskboard already places a card — so the card lands
  /// where it was dropped without the page having to guess at the state the
  /// service will write, and a derived board gets the same treatment for
  /// the fraction of a second before the refreshed item comes back.
  SprintSnapshot? _applyMoveLocally(
    WorkItem card,
    int row,
    int toColumn,
    int toIndex,
  ) {
    final snapshot = _snapshot;
    if (snapshot == null) return null;
    final key = sprintRowKey(_taskboardRows[row]);
    SprintRow? rewrite(SprintRow source) {
      if (sprintRowKey(source) != key) return null;
      final tasks = [...source.tasks];
      final from = tasks.indexWhere((t) => t.id == card.id);
      if (from < 0) return null;
      tasks.removeAt(from);
      // Where the target cell's members sit in this row's flat list.
      final cell = [
        for (final t in tasks)
          if (_columnOf(t) == toColumn) t,
      ];
      final int insertAt;
      if (cell.isEmpty) {
        insertAt = tasks.length;
      } else if (toIndex >= cell.length) {
        insertAt = tasks.indexOf(cell.last) + 1;
      } else {
        insertAt = tasks.indexOf(cell[toIndex]);
      }
      tasks.insert(insertAt.clamp(0, tasks.length), card);
      return SprintRow(
        parent: source.parent,
        tasks: tasks,
        remaining: source.remaining,
        done: source.done,
      );
    }

    final unparented = rewrite(snapshot.unparented);
    return snapshot.copyWith(
      unparented: unparented ?? snapshot.unparented,
      rows: unparented != null
          ? snapshot.rows
          : [for (final r in snapshot.rows) rewrite(r) ?? r],
      explicitColumns: {
        ...snapshot.explicitColumns,
        card.id: _columns[toColumn].name,
      },
    );
  }

  /// The snapshot with one card replaced by a fresher copy of itself.
  SprintSnapshot _replace(WorkItem item) {
    final snapshot = _snapshot!;
    SprintRow swap(SprintRow row) => SprintRow(
      parent: row.parent,
      tasks: [
        for (final t in row.tasks)
          if (t.id == item.id) item else t,
      ],
      remaining: row.remaining,
      done: row.done,
    );
    return snapshot.copyWith(
      rows: [for (final r in snapshot.rows) swap(r)],
      unparented: swap(snapshot.unparented),
    );
  }

  Future<void> _openTaskSheet(WorkItem task) async {
    final action = await showTaskCardSheet(
      context,
      task: task,
      columns: _columns,
      visuals: _visuals,
      currentColumn: _columnOf(task) < 0 ? null : _columnOf(task),
      canAssignToMe: _me != null,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case MoveTaskAction(:final columnIndex):
        final row = _rowOf(task);
        if (row < 0) return;
        await _move(
          task,
          row,
          _columnOf(task),
          row,
          columnIndex,
          _cellCards(row, columnIndex).length,
        );
      case SetRemainingWorkAction(:final hours):
        await _write(
          task,
          (repo) =>
              repo.setRemainingWork(widget.org, widget.project, task, hours),
          'Could not set remaining work on ${task.id}',
        );
      case AssignToMeAction():
        final me = _me;
        if (me == null) return;
        await _assign(task, me);
      case OpenTaskAction():
        _open(task);
    }
  }

  Future<void> _assign(WorkItem task, String me) async {
    setState(() {
      _writesInFlight++;
      _error = null;
    });
    final repo = context.read<WorkItemRepository>();
    try {
      final updated = await repo.patch(widget.org, widget.project, task, [
        {'op': 'add', 'path': '/fields/System.AssignedTo', 'value': me},
      ]);
      if (mounted) setState(() => _snapshot = _replace(updated));
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
      if (mounted) {
        setState(() => _error = 'Could not assign ${task.id}: ${e.message}');
      }
    } finally {
      if (mounted) setState(() => _writesInFlight--);
    }
  }

  Future<void> _write(
    WorkItem task,
    Future<WorkItem> Function(SprintRepository repo) run,
    String failure,
  ) async {
    setState(() {
      _writesInFlight++;
      _error = null;
    });
    final repo = context.read<SprintRepository>();
    try {
      final updated = await run(repo);
      if (mounted) setState(() => _snapshot = _replace(updated));
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
      if (mounted) setState(() => _error = '$failure: ${e.message}');
    } finally {
      if (mounted) setState(() => _writesInFlight--);
    }
  }

  /// Move an item into or out of the sprint (S3): an iteration path patch,
  /// offered over the team's current and future sprints.
  Future<void> _moveToSprint(WorkItem item) async {
    final choices = [..._iterations.current, ..._iterations.future];
    final picked = await showSprintPicker(
      context,
      iterations: choices,
      teamName: _teamName ?? widget.project,
      currentIterationId: _sprintId,
    );
    if (picked is! SprintIterationPicked || !mounted) return;
    final target = picked.iteration;
    if (target.id == _sprintId) return;
    setState(() {
      _writesInFlight++;
      _error = null;
    });
    final repo = context.read<SprintRepository>();
    try {
      await repo.setIteration(widget.org, widget.project, item, target.path);
      if (!mounted) return;
      _say('${item.id} moved to ${target.name}');
      await _load(refresh: true);
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
      if (mounted) {
        setState(() => _error = 'Could not move ${item.id}: ${e.message}');
      }
    } finally {
      if (mounted) setState(() => _writesInFlight--);
    }
  }

  /// The `+` on a row, and the New task row under a taskboard column: a
  /// task parented on the row's requirement, which is what puts it in this
  /// sprint (the form takes the parent's iteration, research/11 4.7).
  Future<void> _newTask(SprintRow? row) async {
    final iteration = _iteration;
    final target = row ?? await _pickRow();
    if (target == null || !mounted) return;
    final taskType = _taskType;
    if (taskType == null) {
      _say('This project has no task type on its sprint backlog');
      return;
    }
    final id = await openWorkItemForm(
      context,
      org: widget.org,
      project: widget.project,
      typeName: taskType,
      teamId: _teamId,
      parentId: target.parent?.id,
    );
    if (id == null || !mounted) return;
    // An unparented task takes the team's default iteration, which is not
    // necessarily the sprint on screen; a parented one inherits its
    // parent's. Put it in this sprint either way.
    if (target.parent == null && iteration != null) {
      try {
        final created = await context.read<WorkItemRepository>().batch(
          widget.org,
          widget.project,
          [id],
        );
        if (created.isNotEmpty &&
            created.first.iterationPath != iteration.path &&
            mounted) {
          await context.read<SprintRepository>().setIteration(
            widget.org,
            widget.project,
            created.first,
            iteration.path,
          );
        }
      } on AdoException {
        // The task exists; it is simply in another sprint, which the
        // refresh below makes visible.
      }
    }
    if (!mounted) return;
    await _load(refresh: true);
    if (mounted) _flash(id);
  }

  /// The sprint's task type: the first type the taskboard's columns map.
  String? get _taskType {
    for (final column in _columns) {
      if (column.mappings.isNotEmpty) return column.mappings.keys.first;
      if (column.states.isNotEmpty) return column.states.keys.first;
    }
    return null;
  }

  /// Which story a new task belongs under, when the phone's chip strip is
  /// on All and the tap came from a column footer rather than a row.
  Future<SprintRow?> _pickRow() async {
    final rows = _rows;
    if (rows.isEmpty) return null;
    if (rows.length == 1) return rows.first;
    return showModalBottomSheet<SprintRow>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                'New task under',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            for (final row in rows)
              ListTile(
                leading: row.parent == null
                    ? const Icon(Icons.inbox_outlined)
                    : Icon(
                        _visuals.typeIcon(row.parent!),
                        color: _visuals.typeColor(context, row.parent!),
                      ),
                title: Text(row.parent?.title ?? 'No parent'),
                subtitle: row.parent == null
                    ? const Text('A task with no parent in this sprint')
                    : Text('${row.parent!.type} ${row.parent!.id}'),
                onTap: () => Navigator.of(context).pop(row),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSprint() async {
    unawaited(_loadTeams());
    final picked = await showSprintPicker(
      context,
      iterations: _iterations.all,
      teamName: _teamName ?? widget.project,
      currentIterationId: _sprintId,
      teams: _teams,
    );
    if (picked == null || !mounted) return;
    switch (picked) {
      case SprintIterationPicked(:final iteration):
        if (iteration.id == _sprintId) return;
        // The route carries the sprint (S1), and it is left out when it is
        // the team's current one so the plain route stays the plain view.
        final isCurrent = _iterations.current.any((i) => i.id == iteration.id);
        setState(() {
          _snapshot = null;
          _burndown = const [];
          _burndownAsked = false;
          _analyticsRefused = false;
          _capacity = null;
          _story = null;
          _iterationId = iteration.id;
        });
        context.go(
          Routes.sprint(
            AccountScope.of(context),
            widget.org,
            widget.project,
            iteration: isCurrent ? null : iteration.id,
            tab: _tabChosen ? SprintPrefs.tabs[_tabs.index] : null,
          ),
        );
        await _load();
      case SprintTeamPicked(:final team):
        if (team.id == _teamId) return;
        // Another team is another set of iterations, another taskboard and
        // another snapshot, so everything resolved for the old one goes —
        // including the sprint in the route, which names an iteration this
        // team does not have. The plain route means "this team's current".
        setState(() {
          _teamId = team.id;
          _teamName = team.name;
          _snapshot = null;
          _iterationId = null;
          _iterations = const SprintIterations();
          _capacity = null;
          _burndown = const [];
          _burndownAsked = false;
          _analyticsRefused = false;
          _story = null;
        });
        if (widget.iteration != null) {
          context.go(
            Routes.sprint(
              AccountScope.of(context),
              widget.org,
              widget.project,
              tab: _tabChosen ? SprintPrefs.tabs[_tabs.index] : null,
            ),
          );
        }
        await _load(refresh: true);
    }
  }

  void _open(WorkItem item) => context.push(
    Routes.workItem(
      AccountScope.of(context),
      widget.org,
      widget.project,
      '${item.id}',
    ),
  );

  /// One transient line. `persist: false` because Flutter 3.47 otherwise
  /// keeps a bar with an action open until it is dismissed and queues every
  /// later one behind it (DESIGN.md §7).
  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          persist: false,
          action: SnackBarAction(
            label: 'OK',
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentSnackBar(),
          ),
        ),
      );
  }

  void _flash(int id) {
    _flashTimer?.cancel();
    setState(() => _flashId = id);
    _flashTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _flashId = null);
    });
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final iteration = _iteration;
    final snapshot = _snapshot;
    // The **sprint** is what this page is about, so it takes the first
    // line whole; the project and the dates share the second. Project-first
    // truncated both halves to nothing on a phone ("DevOp…" / "Iteration
    // 1 ·…", P-C's 04) because the project shell has already said which
    // project this is, twice.
    final title = iteration?.name ?? 'Sprint';
    final when = iteration == null
        ? null
        : iteration.isEnded()
        ? sprintEndedLabel(iteration.finishDate)
        : sprintDateRange(iteration.startDate, iteration.finishDate);
    // A phone's app bar already carries the back arrow, the person filter
    // and a three-segment pill; a fourth control left the two-line title
    // reading "Dev…" / "Iter…". The title *is* the sprint picker instead —
    // which is where the web puts its sprint selector too — and the
    // separate button comes back where there is room for it.
    final compact = context.breakpoint.isCompact;
    // What is left for the title on an iPhone 17 is 84 dp (measured), so
    // the first line takes the app bar's smaller title size there and the
    // second drops the project: "DevOps Mobile App · 8–21 Sep" truncates
    // to "8–21 Sep · De…", and two letters of a project the shell has
    // already named are worth less than the dates. From medium up both
    // fit, and the project comes back.
    final subtitle = when == null || when.isEmpty
        ? widget.project
        : compact
        ? when
        : '${widget.project} · $when';
    final canPick = !_iterations.isEmpty;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: canPick ? _pickSprint : null,
          borderRadius: Radii.chip,
          child: Padding(
            // Vertical only: `titleSpacing: 0` has already put the title
            // hard against the back arrow, and every dp of the 84 the
            // phone leaves here is the difference between "Iteration 2"
            // and "Iteratio…".
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: compact
                            ? theme.textTheme.titleMedium
                            : theme.textTheme.titleLarge,
                      ),
                      Text(
                        subtitle,
                        overflow: TextOverflow.ellipsis,
                        style:
                            (compact
                                    ? theme.textTheme.labelSmall
                                    : theme.textTheme.labelMedium)
                                ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (canPick)
                  Icon(
                    Icons.arrow_drop_down,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                    semanticLabel: 'Choose sprint',
                  ),
              ],
            ),
          ),
        ),
        // 44 dp rather than the default 56: still Apple's minimum target,
        // and the 12 dp it gives back is what lets the second line say
        // "Ended 8 days ago" instead of "Ended 8 day…" on an iPhone.
        leadingWidth: ProjectPickerButton.leadingWidth,
        leading: ProjectPickerButton(org: widget.org, project: widget.project),
        actions: [
          PersonFilterMenu(
            people: _people,
            selected: _person,
            meCount: _meCount,
            onSelected: (value) => setState(() => _person = value),
          ),
          if (!compact)
            IconButton(
              tooltip: 'Choose sprint',
              icon: const Icon(Icons.event_note_outlined),
              onPressed: canPick ? _pickSprint : null,
            ),
          // The switch stays rightmost so it never moves when an action
          // appears next to it.
          WorkViewSwitch(
            org: widget.org,
            project: widget.project,
            current: WorkView.sprint,
          ),
          const SizedBox(width: Spacing.sm),
        ],
        bottom: CountedTabBar(
          controller: _tabs,
          tabs: [
            TabCount('Backlog', snapshot == null ? null : _rows.length),
            TabCount('Taskboard', snapshot == null ? null : _tasks.length),
            const TabCount('Burndown'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading || _writesInFlight > 0)
              const LinearProgressIndicator(),
            _cacheLine(context),
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
            Expanded(
              child: snapshot == null
                  ? (_loading
                        ? const Center(
                            child: CircularProgressIndicator.adaptive(),
                          )
                        : const SizedBox.shrink())
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _refreshable(_backlog()),
                        _refreshable(_taskboard()),
                        _refreshable(_burndownTabBody()),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pull to refresh on every tab. The depth-1 predicate is what makes it
  /// work inside the taskboard's horizontal scroller.
  Widget _refreshable(Widget child) => RefreshIndicator(
    onRefresh: _refresh,
    notificationPredicate: (n) =>
        n.depth <= 1 && n.metrics.axis == Axis.vertical,
    child: child,
  );

  Widget _header() => SprintHeader(data: _headerData);

  Widget _backlog() => SprintBacklogTab(
    rows: _rows,
    visuals: _visuals,
    capacity: _capacity,
    unit: _sprintTotals.unit,
    header: _header(),
    onOpen: _open,
    onRowAction: (action, row, item) => switch (action) {
      SprintRowAction.moveToSprint => _moveToSprint(item),
      SprintRowAction.addTask => _newTask(row),
    },
  );

  Widget _burndownTabBody() => SprintBurndownTab(
    days: _burndown,
    header: _header(),
    capacity: _capacity,
    loading: _burndownLoading,
    unavailable: _analyticsRefused,
    error: _burndownError,
    iteration: _iteration,
    unit: 'items',
  );

  Widget _taskboard() {
    final rows = _taskboardRows;
    if (_columns.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: Spacing.page,
            child: Text(
              'This project has no taskboard columns.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      );
    }
    // The tablet gets the real grid, the phone the story chip strip over
    // one Kanban board (S4/S5). Neither gets the sprint header: the tiles,
    // the sparkline and the verdict belong to the Backlog and Burndown
    // tabs, and over a board they only push the cards down (Kelly, S13).
    if (!context.breakpoint.isCompact) return _grid(rows);
    return _phoneBoard(rows);
  }

  /// The tablet's taskboard: the grid and nothing else.
  ///
  /// It had the sprint header above it and a burndown / capacity pane
  /// beside it (S5). Both are gone (S13): a taskboard is read as a grid,
  /// and the two of them together took a third of an iPad's width and
  /// 180 dp of its height away from the cells. The burndown lives on its
  /// own tab and the capacity strip on the Backlog tab.
  Widget _grid(List<SprintRow> rows) {
    return TaskboardGrid(
      columns: _columns,
      rows: rows,
      columnOf: _columnOf,
      visuals: _visuals,
      onMove: _move,
      onAddTask: _newTask,
      onCardTap: _openTaskSheet,
      onRowTap: (row) {
        final parent = row.parent;
        if (parent != null) _open(parent);
      },
      cardBuilder: (context, card, dragging) => WorkItemCard(
        item: card,
        visuals: _visuals,
        dragging: dragging,
        flash: card.id == _flashId,
        badge: _badgeFor(card, showParent: false),
      ),
    );
  }

  Widget _phoneBoard(List<SprintRow> rows) {
    final selected = _story;
    final shown = selected == null
        ? rows
        : [
            for (final row in rows)
              if (sprintRowKey(row) == selected) row,
          ];
    final tasks = [for (final row in shown) ...row.tasks];
    final cells = SprintRepository.distribute(
      _columns,
      tasks,
      explicitColumns: _snapshot?.explicitColumns ?? const {},
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StoryChipStrip(
          rows: rows,
          visuals: _visuals,
          selected: selected,
          onSelected: (value) => setState(() => _story = value),
        ),
        Expanded(
          child: KanbanBoard<WorkItem>(
            columns: [
              for (var c = 0; c < _columns.length; c++)
                KanbanColumnData<WorkItem>(
                  id: _columns[c].name,
                  title: _columns[c].name,
                  subtitle: _columnSubtitle(cells[c]),
                  cards: cells[c],
                ),
            ],
            keyOf: (item) => item.id,
            columnFooterBuilder: (context, c) => NewCardRow(
              label: 'New task',
              onTap: _loading
                  ? null
                  : () => _newTask(shown.length == 1 ? shown.first : null),
            ),
            cardBuilder: (context, card, dragging) => WorkItemCard(
              item: card,
              visuals: _visuals,
              dragging: dragging,
              flash: card.id == _flashId,
              badge: _badgeFor(card, showParent: selected == null),
            ),
            // Tap opens the sheet, not the work item: `KanbanBoard` and
            // `TaskboardGrid` both spend long-press on the drag, so the
            // sheet — which is the WCAG 2.2 2.5.7 alternative to that drag
            // and the only move `tool/shot-ios.sh` can perform — needs the
            // tap. "Open task" is its last row (decision P-C).
            onCardTap: _openTaskSheet,
            onMove: (card, fromColumn, fromIndex, toColumn, toIndex) {
              final row = _rowOf(card);
              if (row < 0) return;
              _move(card, row, fromColumn, row, toColumn, toIndex);
            },
          ),
        ),
      ],
    );
  }

  String? _columnSubtitle(List<WorkItem> cards) {
    var sum = 0.0;
    for (final card in cards) {
      final hours = card
          .field<num>(SprintRepository.remainingWorkField)
          ?.toDouble();
      if (hours != null) sum += hours;
    }
    // `any` is not enough: a task whose Remaining Work was cleared holds a
    // real 0, and `formatRemaining(0)` is the empty string — which left the
    // column header reading " remaining" with no number (iPhone check,
    // P-D).
    final text = formatRemaining(sum);
    return text.isEmpty ? null : '$text remaining';
  }

  /// The card's trailing label: the parent's id while every story is on
  /// screen at once, and the remaining work otherwise (S4).
  String? _badgeFor(WorkItem card, {required bool showParent}) {
    if (showParent) {
      final parent = card.field<num>('System.Parent')?.toInt();
      if (parent != null) return '#$parent';
    }
    final hours = card
        .field<num>(SprintRepository.remainingWorkField)
        ?.toDouble();
    final text = formatRemaining(hours);
    return text.isEmpty ? null : text;
  }

  /// "offline · showing the cached copy · 3m", the line the board and the
  /// search page show over stale content.
  Widget _cacheLine(BuildContext context) {
    final at = _shownAt;
    if (at == null && !_offline) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final age = at == null ? '' : ' · ${relativeTime(at)}';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg + MediaQuery.paddingOf(context).left,
        Spacing.xs,
        Spacing.lg + MediaQuery.paddingOf(context).right,
        0,
      ),
      child: Row(
        children: [
          Icon(
            _offline ? Icons.cloud_off_outlined : Icons.history_toggle_off,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: Text(
              _offline ? 'offline · showing the cached copy$age' : 'cached$age',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
