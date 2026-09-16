import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/http/ado_exceptions.dart';
import '../../core/routes.dart';
import '../../data/models/dashboard.dart';
import '../../data/models/dashboard_layout.dart';
import '../../data/models/sprint.dart' show SprintTeamRef;
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/sprint_repository.dart';
import '../../theme/theme.dart';
import '../boards/widgets/kanban_board.dart' show boardTextScale;
import '../projects/widgets/home_view_switch.dart';
import '../shared/account_scope.dart';
import '../shared/reload_on_return.dart';
import 'dashboard_prefs.dart';
import 'team_overview.dart';
import 'widgets/dashboard_card.dart';
import 'widgets/dashboard_chrome.dart';
import 'widgets/picker_sheet.dart';
import 'widgets/registry.dart';
import '../projects/widgets/project_picker_button.dart';

/// The Dashboards view: the Home tab's second segment (research/19).
///
/// The page owns the **dashboard**; every card owns its own data. That is
/// what lets one refused Analytics call, one missing pipeline or one query
/// the account cannot run degrade a single card while the rest of the
/// dashboard draws (D14), and it is why pull-to-refresh both refetches the
/// dashboard and bumps [DashboardReload] for the cards (D12).
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.org,
    required this.project,
    this.dashboardId,
  });

  final String org;
  final String project;

  /// `?dashboard=` — a dashboard GUID, or [TeamOverview.id]. Null means the
  /// one last opened in this project, and failing that the default team's
  /// Overview (D6).
  final String? dashboardId;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with ReloadOnReturn {
  /// One row span on a tablet, before the text scale (research/19 §4.2).
  static const rowHeight = 160.0;

  final _reload = DashboardReload();

  Dashboard? _dashboard;
  String? _currentId;
  String? _teamId;
  List<DashboardSummary> _summaries = const [];
  List<SprintTeamRef> _teams = const [];
  Set<String> _favorites = const {};

  String? _error;

  /// Set when the **dashboard API itself** refuses this account, which is
  /// not a sign-out (see [_load]): the page says so once, over the Team
  /// overview, instead of sending the person to a sign-in sheet that
  /// cannot help.
  String? _refusal;

  bool _loading = false;

  /// Where what is on screen came from: the cache (and when), and whether
  /// the last read failed with a network error (D12, the sprint's line).
  DateTime? _shownAt;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _currentId = widget.dashboardId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(DashboardPage old) {
    super.didUpdateWidget(old);
    // The route changed under the same State: a deep link, the pill, or the
    // picker — which has already set `_currentId` and loaded, so the second
    // check makes this a no-op for it.
    if (widget.dashboardId == old.dashboardId) return;
    if (widget.dashboardId == _currentId) return;
    _currentId = widget.dashboardId;
    unawaited(_load());
  }

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() => _load();

  // ------------------------------------------------------------- loading

  /// The cached dashboard, drawn before anything touches the network.
  /// Which dashboard that is, is itself a question: the route may name one,
  /// and otherwise the last one opened here is remembered — without that
  /// there is no cache key to look up and a cold offline open is blank.
  Future<void> _drawCached() async {
    if (_dashboard != null) return;
    final id =
        widget.dashboardId ??
        _currentId ??
        await DashboardPrefs.lastDashboard(widget.org, widget.project);
    if (id == null || id.isEmpty || !mounted) return;
    if (TeamOverview.isTeamOverview(id)) {
      // Built here, not read: it is always available, online or not.
      setState(() {
        _dashboard = TeamOverview.forTeam(_teamId);
        _currentId = id;
      });
      return;
    }
    final cached = await context.read<DashboardRepository>().cachedDashboard(
      widget.org,
      widget.project,
      id,
    );
    if (cached == null || !mounted || _dashboard != null) return;
    setState(() {
      _dashboard = cached.dashboard;
      _currentId = cached.dashboard.id;
      _teamId = cached.dashboard.teamId;
      _shownAt = cached.fetchedAt;
    });
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _refusal = null;
    });
    final repo = context.read<DashboardRepository>();
    await _drawCached();
    try {
      final summaries = await repo.list(
        widget.org,
        widget.project,
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() => _summaries = summaries);
      final wanted =
          _currentId ??
          await DashboardPrefs.lastDashboard(widget.org, widget.project);
      if (!mounted) return;
      if (TeamOverview.isTeamOverview(wanted)) {
        await _resolveTeam();
        if (!mounted) return;
        setState(() {
          _dashboard = TeamOverview.forTeam(_teamId);
          _currentId = TeamOverview.id;
          _shownAt = null;
          _offline = false;
        });
        unawaited(_loadSide());
        return;
      }
      final chosen = _chooseFrom(summaries, wanted);
      if (chosen == null) {
        setState(() => _error = 'This project has no dashboards you can read.');
        return;
      }
      _currentId = chosen.id;
      unawaited(
        DashboardPrefs.setLastDashboard(widget.org, widget.project, chosen.id),
      );
      final teamId = chosen.teamId ?? await _defaultTeam();
      if (!mounted || teamId == null) return;
      final dashboard = await repo.get(
        widget.org,
        widget.project,
        teamId,
        chosen.id,
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _dashboard = dashboard;
        _teamId = dashboard.teamId ?? teamId;
        _shownAt = null;
        _offline = false;
      });
      unawaited(_loadSide());
    } on AdoAuthException catch (e) {
      // **Not** a sign-out. Verified on the iPhone 17 simulator
      // (2026-09-15): `_apis/dashboard/dashboards` answers
      // `401 InvalidIdentityException: TF400813` to Boardhop's Entra token
      // while Analytics, work items, code and builds all accept it in the
      // same session — the registration has no `vso.dashboards` scope
      // (research/09). Raising sign-in here put the person in a loop: the
      // sheet opens, they sign in, the same call refuses again.
      //
      // So a refusal of *the dashboard resource* is reported where it
      // happened and the page falls back to the Team overview, which needs
      // nothing from this API. Every other `AdoAuthException` — the cards'
      // included — still raises sign-in the way it always did.
      if (!mounted) return;
      await _resolveTeam();
      if (!mounted) return;
      setState(() {
        _refusal = e.message;
        _dashboard = TeamOverview.forTeam(_teamId);
        _currentId = TeamOverview.id;
        _shownAt = null;
        _offline = false;
      });
    } on AdoNetworkException catch (e) {
      // Offline with a dashboard on screen is not an error: say where it
      // came from and leave it there.
      if (!mounted) return;
      setState(() {
        if (_dashboard == null) {
          _error = e.message;
        } else {
          _offline = true;
        }
      });
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        markLoaded();
      }
    }
  }

  /// The dashboard to open: the one asked for, else the default team's
  /// first by `position`, else the project's first (D6).
  DashboardSummary? _chooseFrom(
    List<DashboardSummary> summaries,
    String? wanted,
  ) {
    if (summaries.isEmpty) return null;
    if (wanted != null && wanted.isNotEmpty) {
      for (final s in summaries) {
        if (s.id == wanted) return s;
      }
    }
    final sorted = [...summaries]
      ..sort((a, b) => a.position.compareTo(b.position));
    final team = _teamId;
    if (team != null) {
      for (final s in sorted) {
        if (s.teamId == team) return s;
      }
    }
    return sorted.first;
  }

  Future<String?> _defaultTeam() async {
    final cached = _teamId;
    if (cached != null) return cached;
    try {
      final id = await context.read<SprintRepository>().defaultTeamId(
        widget.org,
        widget.project,
      );
      if (mounted) setState(() => _teamId = id);
      return id;
    } on AdoException {
      return null;
    }
  }

  Future<void> _resolveTeam() async {
    if (_teamId != null) return;
    await _defaultTeam();
  }

  /// Favorites and the team names are only the picker's, so they are never
  /// on the critical path and a project that refuses either simply shows a
  /// picker without stars or without group headings.
  Future<void> _loadSide() async {
    final repo = context.read<DashboardRepository>();
    final sprints = context.read<SprintRepository>();
    try {
      final favorites = await repo.favorites(widget.org, widget.project);
      if (mounted) setState(() => _favorites = favorites);
    } on AdoException {
      // Favorites need their own scope; a picker without stars is fine.
    }
    try {
      final teams = await sprints.teams(widget.org, widget.project);
      if (mounted) setState(() => _teams = teams);
    } on AdoException {
      // Grouping falls back to the project's name.
    }
  }

  Future<void> _refresh() async {
    await _load(refresh: true);
    // Every card reloads itself (D12).
    _reload.bump();
  }

  // ---------------------------------------------------------- navigation

  Future<void> _pick() async {
    final picked = await showDashboardPicker(
      context,
      dashboards: _summaries,
      teams: _teams,
      favorites: _favorites,
      currentId: _currentId,
      projectName: widget.project,
    );
    if (picked == null || !mounted) return;
    final id = switch (picked) {
      DashboardSummaryPicked(:final summary) => summary.id,
      TeamOverviewPicked() => TeamOverview.id,
    };
    if (id == _currentId) return;
    setState(() {
      _dashboard = null;
      _shownAt = null;
      _offline = false;
      if (picked case DashboardSummaryPicked(:final summary)) {
        _teamId = summary.teamId ?? _teamId;
      }
      _currentId = id;
    });
    unawaited(DashboardPrefs.setLastDashboard(widget.org, widget.project, id));
    context.go(
      Routes.dashboards(
        AccountScope.of(context),
        widget.org,
        widget.project,
        dashboard: id,
      ),
    );
    await _load();
  }

  Future<void> _openTeamOverview() async {
    setState(() {
      _dashboard = null;
      _shownAt = null;
      _currentId = TeamOverview.id;
    });
    unawaited(
      DashboardPrefs.setLastDashboard(
        widget.org,
        widget.project,
        TeamOverview.id,
      ),
    );
    context.go(
      Routes.dashboards(
        AccountScope.of(context),
        widget.org,
        widget.project,
        dashboard: TeamOverview.id,
      ),
    );
    await _load();
  }

  Future<void> _openOnWeb() async {
    final id = _currentId;
    if (id == null || TeamOverview.isTeamOverview(id)) return;
    final uri = DashboardRepository.webUri(widget.org, widget.project, id);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // --------------------------------------------------------------- build

  /// The dashboard's team, for the title's second line.
  String get _teamLabel {
    final team = _dashboard?.teamId ?? _teamId;
    for (final t in _teams) {
      if (t.id == team) return t.name;
    }
    return widget.project;
  }

  List<DashboardWidget> get _shown => [
    for (final w in _dashboard?.widgets ?? const <DashboardWidget>[])
      if (w.isEnabled && DashboardRegistry.renders(w)) w,
  ];

  int get _hiddenCount => [
    for (final w in _dashboard?.widgets ?? const <DashboardWidget>[])
      if (w.isEnabled && !DashboardRegistry.renders(w)) w,
  ].length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = context.breakpoint.isCompact;
    final dashboard = _dashboard;
    final title = dashboard?.name ?? 'Dashboards';
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        // The title *is* the picker, as the sprint's is: a phone's app bar
        // already carries the back arrow and a two-segment pill, and a
        // fourth control would leave the title reading "Ove…".
        title: InkWell(
          onTap: _pick,
          borderRadius: Radii.chip,
          child: Padding(
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
                        _teamLabel,
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
                Icon(
                  Icons.arrow_drop_down,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                  semanticLabel: 'Choose dashboard',
                ),
              ],
            ),
          ),
        ),
        leadingWidth: ProjectPickerButton.leadingWidth,
        leading: ProjectPickerButton(org: widget.org, project: widget.project),
        actions: [
          // D5: no Search here; it stays on Summary.
          if (!compact)
            IconButton(
              tooltip: 'Choose dashboard',
              icon: const Icon(Icons.dashboard_customize_outlined),
              onPressed: _pick,
            ),
          HomeViewSwitch(
            org: widget.org,
            project: widget.project,
            current: HomeView.dashboards,
          ),
          const SizedBox(width: Spacing.sm),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: DashboardReloadScope(
          notifier: _reload,
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ContentColumn(
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    _scroller(context, constraints.maxWidth),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scroller(BuildContext context, double width) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dashboard = _dashboard;
    final widgets = _shown;
    final columns = DashboardLayout.columnsFor(width, widgets: widgets);
    final rows = DashboardLayout.layout(widgets, columns);
    // A tablet's cards share a row and so must share a height; a phone's
    // card is alone on its row and sizes itself (D4).
    final scale = boardTextScale(context).clamp(1.0, 1.6);
    final hidden = _hiddenCount;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (_loading && dashboard == null)
          const SliverToBoxAdapter(child: LinearProgressIndicator()),
        SliverToBoxAdapter(
          child: DashboardCacheLine(shownAt: _shownAt, offline: _offline),
        ),
        if (_refusal != null)
          SliverToBoxAdapter(child: _refusalLine(context, _refusal!)),
        if (_error != null)
          SliverToBoxAdapter(
            child: Material(
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
          ),
        if (dashboard != null && widgets.isEmpty && hidden == 0)
          SliverToBoxAdapter(
            child: DashboardEmptyOffer(
              isTeamOverview: TeamOverview.isTeamOverview(_currentId),
              onShowTeamOverview: _openTeamOverview,
            ),
          )
        else
          SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) =>
                _row(context, rows[index], columns, scale),
          ),
        if (hidden > 0)
          SliverToBoxAdapter(
            child: DashboardHiddenLine(hidden: hidden, onOpenWeb: _openOnWeb),
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: scrollEndPadding(context).bottom),
        ),
      ],
    );
  }

  /// The dashboard API refusing this account, said once and quietly: the
  /// Team overview below it is what Boardhop can still draw.
  Widget _refusalLine(BuildContext context, String message) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'This account cannot read this project’s dashboards, so '
              'Boardhop is showing its own overview. $message',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, LayoutRow row, int columns, double scale) {
    final onePerRow = columns <= 1;
    final height = row.rowSpan * rowHeight * scale;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.sm,
      ),
      child: Row(
        // Not `stretch`: a phone's row is inside a sliver with no bounded
        // height, and stretching into that is an infinite constraint. Every
        // card on a tablet's row already carries the same fixed height.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < row.widgets.length; i++) ...[
            if (i > 0) const SizedBox(width: Spacing.sm),
            Expanded(
              flex: row.widgets[i].columnSpan,
              child: onePerRow
                  ? _card(row.widgets[i].widget, filled: false)
                  : SizedBox(
                      height: height,
                      child: _card(row.widgets[i].widget, filled: true),
                    ),
            ),
          ],
          // A short last row keeps its cards their own width rather than
          // stretching two cards across six columns.
          if (row.columnsUsed < columns)
            Spacer(flex: columns - row.columnsUsed),
        ],
      ),
    );
  }

  Widget _card(DashboardWidget widget, {required bool filled}) {
    final builder = DashboardRegistry.cardFor(widget);
    if (builder == null) return const SizedBox.shrink();
    return builder(
      DashboardCardArgs(
        org: this.widget.org,
        project: this.widget.project,
        widget: widget,
        teamId: _dashboard?.teamId ?? _teamId,
        dashboardId: _dashboard?.id ?? _currentId,
        filled: filled,
        // A phone's card sizes itself, capped per kind so one long list
        // cannot own the screen (D4).
        maxBodyHeight: filled
            ? null
            : switch (DashboardRegistry.phoneCap(widget)) {
                final cap? => cap * boardTextScale(context).clamp(1.0, 1.6),
                _ => null,
              },
      ),
    );
  }
}
