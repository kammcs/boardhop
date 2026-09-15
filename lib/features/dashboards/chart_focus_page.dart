import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../data/models/dashboard.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/sprint_repository.dart';
import '../../theme/theme.dart';
import '../shared/account_scope.dart';
import 'charts/chart_format.dart';
import 'charts/chart_payload.dart';
import 'team_overview.dart';
import 'widgets/chart_card.dart';
import 'widgets/dashboard_card.dart';
import 'widgets/registry.dart';

/// One chart, full screen (research/19 D7, D15).
///
/// Pushed over the shell by any chart card. It normally arrives with the
/// payload the card already drew, so the chart is on screen in the same
/// frame as the page; opened cold — a deep link, or the app restored on
/// this route — it finds the widget on the cached dashboard and loads the
/// chart through the same loader the card uses, cache first.
///
/// The layout follows the device's orientation and nothing else (D15): the
/// legend sits under the chart in portrait and beside it in landscape, and
/// the series is a list of numbers underneath either way, because a chart
/// on its own is not an accessible answer (DESIGN.md §8).
class ChartFocusPage extends StatefulWidget {
  const ChartFocusPage({
    super.key,
    required this.org,
    required this.project,
    required this.widgetId,
    this.dashboardId,
    this.initial,
  });

  final String org;
  final String project;

  /// The dashboard widget's id, from the route.
  final String widgetId;

  /// `?dashboard=` — the dashboard the widget sits on, or the Team
  /// overview's own id.
  final String? dashboardId;

  /// What the card handed over through `extra`, when it was a card that
  /// opened this.
  final ChartFocusArgs? initial;

  @override
  State<ChartFocusPage> createState() => _ChartFocusPageState();
}

class _ChartFocusPageState extends State<ChartFocusPage> {
  ChartPayload? _payload;
  DashboardCardArgs? _args;
  bool _loading = false;
  String? _error;
  String? _unavailable;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _payload = initial.payload;
      _args = initial.args;
      return;
    }
    _loading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  /// A cold open: find the widget on the cached dashboard (or build the
  /// Team overview, which needs nothing from the service) and load its
  /// chart the way its card would have.
  Future<void> _load() async {
    final dashboards = context.read<DashboardRepository>();
    final sprints = context.read<SprintRepository>();
    final id = widget.dashboardId;
    try {
      DashboardWidget? found;
      String? teamId;
      if (id == null || TeamOverview.isTeamOverview(id)) {
        try {
          teamId = await sprints.defaultTeamId(widget.org, widget.project);
        } on AdoException {
          teamId = null;
        }
        if (!mounted) return;
        found = _widgetOf(TeamOverview.forTeam(teamId).widgets);
      } else {
        final cached = await dashboards.cachedDashboard(
          widget.org,
          widget.project,
          id,
        );
        if (!mounted) return;
        found = _widgetOf(cached?.dashboard.widgets ?? const []);
        teamId = cached?.dashboard.teamId;
      }
      if (found == null) {
        setState(() {
          _loading = false;
          _error = 'This chart is no longer on the dashboard.';
        });
        return;
      }
      final args = DashboardCardArgs(
        org: widget.org,
        project: widget.project,
        widget: found,
        teamId: teamId,
        dashboardId: id,
      );
      setState(() => _args = args);
      final payload = await DashboardRegistry.loadChart(
        context,
        args,
        refresh: false,
      );
      if (!mounted) return;
      setState(() {
        _payload = payload;
        _loading = false;
      });
    } on AnalyticsUnavailable catch (e) {
      if (mounted) {
        setState(() {
          _unavailable = e.message;
          _loading = false;
        });
      }
    } on AdoAuthException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        context.read<AuthBloc>().add(
          AuthInteractionRequired(
            e.message,
            accountId: AccountScope.maybeOf(context),
          ),
        );
      }
    } on AdoException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  DashboardWidget? _widgetOf(List<DashboardWidget> widgets) {
    for (final w in widgets) {
      if (w.id == widget.widgetId) return w;
    }
    return null;
  }

  String get _title {
    final name = _args?.widget.name ?? '';
    if (name.isNotEmpty) return name;
    return _payload?.title ?? 'Chart';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final payload = _payload;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ContentColumn(
          child: switch (this) {
            _ when _unavailable != null => _Note(
              icon: Icons.insights_outlined,
              text: 'Analytics unavailable. $_unavailable',
              color: scheme.onSurfaceVariant,
            ),
            _ when _error != null => _Note(
              icon: Icons.error_outline,
              text: _error!,
              color: scheme.error,
            ),
            _ when _loading || payload == null => const Center(
              child: CircularProgressIndicator.adaptive(),
            ),
            _ when payload.isEmpty => _Note(
              icon: Icons.insights_outlined,
              text: payload.emptyNote,
              color: scheme.onSurfaceVariant,
            ),
            _ => ChartFocusView(payload: payload),
          },
        ),
      ),
    );
  }
}

/// The chart, its legend and its numbers, laid out for the orientation the
/// device is in (D15). Separate from the page so both breakpoints and both
/// orientations can be pumped without a router.
class ChartFocusView extends StatelessWidget {
  const ChartFocusView({super.key, required this.payload});

  final ChartPayload payload;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final landscape = constraints.maxWidth > constraints.maxHeight;
      final legend = Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: ChartLegend(keys: payload.keys(context)),
      );
      final rows = _RowList(payload: payload);
      if (!landscape) {
        // Portrait: chart, legend under it, numbers below (D15).
        final height = (constraints.maxHeight * 0.4).clamp(180.0, 420.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Headline(payload: payload),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.xs,
                Spacing.lg,
                Spacing.sm,
              ),
              child: payload.chart(context, height: height),
            ),
            legend,
            const SizedBox(height: Spacing.sm),
            Expanded(child: rows),
          ],
        );
      }
      // Landscape: the chart takes the height it can get and the legend
      // moves beside it, over the numbers.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Headline(payload: payload),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.md,
                      Spacing.xs,
                      Spacing.lg,
                      Spacing.md,
                    ),
                    child: LayoutBuilder(
                      builder: (context, inner) =>
                          payload.chart(context, height: inner.maxHeight),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Spacing.md),
                legend,
                const SizedBox(height: Spacing.sm),
                Expanded(child: rows),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _Headline extends StatelessWidget {
  const _Headline({required this.payload});

  final ChartPayload payload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final headline = payload.headline;
    if (headline == null) return const SizedBox(height: Spacing.md);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(headline, style: theme.textTheme.headlineSmall),
          if (payload.summary case final summary?)
            Text(
              summary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// The series as numbers: the part of a chart a screen reader can read, and
/// the part a person checks when the line is ambiguous.
class _RowList extends StatelessWidget {
  const _RowList({required this.payload});

  final ChartPayload payload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = payload.rows();
    return ListView.builder(
      padding: scrollEndPadding(context),
      itemCount: rows.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.xs,
            ),
            child: Text(payload.rowsTitle, style: theme.textTheme.titleSmall),
          );
        }
        final row = rows[index - 1];
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (row.color case final color?) ...[
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: Radii.chip,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(row.label, style: theme.textTheme.bodyMedium),
                    if (row.detail case final detail?)
                      Text(
                        detail,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Text(row.value, style: theme.textTheme.bodyMedium),
            ],
          ),
        );
      },
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
