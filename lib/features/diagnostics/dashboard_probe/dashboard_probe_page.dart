import 'package:flutter/material.dart';

import '../../../data/models/dashboard.dart';
import '../../../data/models/dashboard_layout.dart';
import '../../../data/models/sprint.dart' show SprintTeamRef;
import '../../../theme/theme.dart';
import '../../boards/widgets/kanban_board.dart' show boardTextScale;
import '../../dashboards/team_overview.dart';
import '../../dashboards/widgets/dashboard_card.dart';
import '../../dashboards/widgets/dashboard_chrome.dart';
import '../../dashboards/widgets/picker_sheet.dart';
import '../../dashboards/widgets/registry.dart';

/// Phase D-B probe: the Dashboards view's layout, card frames and page
/// furniture on **canned** widgets, so the grid, the four card states, the
/// empty-dashboard offer, the hidden-widget line and the picker can be
/// looked at on both simulators in light and dark and at xxxL without a
/// network, an account or a repository (D14).
///
/// Nothing here touches Azure DevOps and nothing here is client data: every
/// name is invented. Diagnostics only (`AppConfig.diagnosticsEnabled`), like
/// the board, mention and sprint probes.
class DashboardProbePage extends StatefulWidget {
  const DashboardProbePage({super.key});

  @override
  State<DashboardProbePage> createState() => _DashboardProbePageState();
}

class _DashboardProbePageState extends State<DashboardProbePage> {
  static const _org = 'probe-org';
  static const _project = 'Probe project';

  /// A dashboard shaped like the scratch project's Overview after w36: a
  /// mix of kinds Boardhop draws, kinds it hides, and a chart it names but
  /// cannot draw yet.
  static final populated = Dashboard(
    id: 'probe-populated',
    name: 'Probe Overview',
    scope: DashboardScope.team,
    teamId: 'probe-team',
    widgets: [
      _widget('w1', 'Open bugs', 'QueryScalarWidget', 1, 1, 1, 1),
      _widget('w2', 'Recent work', 'WitViewWidget', 1, 2, 2, 2),
      _widget('w3', 'Assigned to me', 'AssignedToMeWidget', 1, 4, 2, 2),
      _widget('w4', 'Team members', 'TeamMembersWidget', 3, 1, 2, 2),
      _widget('w5', 'Notes', 'MarkdownWidget', 3, 3, 2, 2),
      _widget('w6', 'Handy links', 'WorkLinksWidget', 3, 5, 2, 1),
      _widget(
        'w7',
        'Sprint burndown',
        'AnalyticsSprintBurndownWidget',
        5,
        1,
        2,
        2,
      ),
      // Hidden: D2 (no chart route) and D10 (an iframe).
      _widget('w8', 'Chart for work items', 'WitChartWidget', 5, 3, 2, 2),
      _widget('w9', 'Embedded page', 'IFrameWidget', 5, 5, 2, 2),
    ],
  );

  static final empty = Dashboard(
    id: 'probe-empty',
    name: 'Empty Overview',
    scope: DashboardScope.team,
    teamId: 'probe-team',
  );

  static DashboardWidget _widget(
    String id,
    String name,
    String suffix,
    int row,
    int column,
    int rowSpan,
    int columnSpan,
  ) => DashboardWidget(
    id: id,
    name: name,
    contributionId:
        'ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.$suffix',
    row: row,
    column: column,
    rowSpan: rowSpan,
    columnSpan: columnSpan,
    settings: switch (suffix) {
      'QueryScalarWidget' =>
        '{"queryId":"00000000-0000-0000-0000-000000000001",'
            '"queryName":"Open bugs"}',
      'WitViewWidget' =>
        '{"queryId":"00000000-0000-0000-0000-000000000002",'
            '"queryName":"Recent work"}',
      'AnalyticsSprintBurndownWidget' =>
        '{"team":{"projectId":"00000000-0000-0000-0000-0000000000aa",'
            '"teamId":"00000000-0000-0000-0000-0000000000bb"},'
            '"iterationId":"00000000-0000-0000-0000-0000000000cc"}',
      'MarkdownWidget' =>
        '## Probe notes\n\nThis text is the widget settings, verbatim.',
      _ => null,
    },
  );

  Dashboard _current = populated;

  @override
  Widget build(BuildContext context) {
    final widgets = [
      for (final w in _current.widgets)
        if (w.isEnabled && DashboardRegistry.renders(w)) w,
    ];
    final hidden = _current.widgets.length - widgets.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboards (D-B)'),
        actions: [
          IconButton(
            tooltip: 'Picker',
            icon: const Icon(Icons.dashboard_customize_outlined),
            onPressed: () => showDashboardPicker(
              context,
              dashboards: [populated.summary, empty.summary],
              teams: const [
                SprintTeamRef(id: 'probe-team', name: 'Probe team'),
              ],
              favorites: const {'probe-populated'},
              currentId: _current.id,
              projectName: _project,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Dashboard',
            icon: const Icon(Icons.swap_horiz),
            onSelected: (value) => setState(() {
              _current = switch (value) {
                'empty' => empty,
                'overview' => TeamOverview.forTeam('probe-team'),
                _ => populated,
              };
            }),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'populated', child: Text('Populated')),
              PopupMenuItem(value: 'empty', child: Text('Empty')),
              PopupMenuItem(value: 'overview', child: Text('Team overview')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ContentColumn(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = DashboardLayout.columnsFor(
                constraints.maxWidth,
                widgets: widgets,
              );
              final rows = DashboardLayout.layout(widgets, columns);
              final scale = boardTextScale(context).clamp(1.0, 1.6);
              return ListView(
                padding: scrollEndPadding(context),
                children: [
                  DashboardCacheLine(
                    shownAt: DateTime.now().subtract(
                      const Duration(minutes: 3),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.lg,
                      Spacing.sm,
                      Spacing.lg,
                      0,
                    ),
                    child: Text(
                      '$columns column${columns == 1 ? '' : 's'} at '
                      '${constraints.maxWidth.round()} dp',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  if (widgets.isEmpty)
                    DashboardEmptyOffer(
                      isTeamOverview: TeamOverview.isTeamOverview(_current.id),
                      onShowTeamOverview: () => setState(
                        () => _current = TeamOverview.forTeam('probe-team'),
                      ),
                    ),
                  for (final row in rows)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Spacing.lg,
                        Spacing.sm,
                        Spacing.lg,
                        Spacing.sm,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < row.widgets.length; i++) ...[
                            if (i > 0) const SizedBox(width: Spacing.sm),
                            Expanded(
                              flex: row.widgets[i].columnSpan,
                              child: columns <= 1
                                  ? _frame(row.widgets[i].widget, false)
                                  : SizedBox(
                                      height: row.rowSpan * 160 * scale,
                                      child: _frame(
                                        row.widgets[i].widget,
                                        true,
                                      ),
                                    ),
                            ),
                          ],
                          if (row.columnsUsed < columns)
                            Spacer(flex: columns - row.columnsUsed),
                        ],
                      ),
                    ),
                  DashboardHiddenLine(hidden: hidden, onOpenWeb: () {}),
                  const Divider(height: Spacing.xl),
                  Padding(
                    padding: Spacing.pageHorizontal,
                    child: Text(
                      'Card states',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  for (final state in _states)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Spacing.lg,
                        Spacing.sm,
                        Spacing.lg,
                        Spacing.sm,
                      ),
                      child: state,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Every card the probe draws itself, with no repository behind it: the
  /// frame in each of its four states, which is what a card shows while it
  /// loads, when Analytics refuses it (D14), when a read fails and when it
  /// has content.
  static const _states = <Widget>[
    DashboardCard(
      title: 'Loading',
      icon: Icons.filter_alt_outlined,
      loading: true,
      child: SizedBox.shrink(),
    ),
    DashboardCard(
      title: 'Analytics refused',
      icon: Icons.insights_outlined,
      unavailable:
          'The Analytics service did not accept this sign-in. A project or '
          'organization administrator can check that Analytics is enabled.',
      child: SizedBox.shrink(),
    ),
    DashboardCard(
      title: 'Read failed',
      icon: Icons.list_alt_outlined,
      error:
          'TF401019: The Git repository does not exist or you do not have '
          'permission.',
      child: SizedBox.shrink(),
    ),
    DashboardCard(
      title: 'Content',
      icon: Icons.notes_outlined,
      child: Text('Whatever the card drew.'),
    ),
  ];

  Widget _frame(DashboardWidget widget, bool filled) {
    final args = DashboardCardArgs(
      org: _org,
      project: _project,
      widget: widget,
      teamId: _current.teamId,
      filled: filled,
    );
    // The repository-backed cards cannot run without an account, so the
    // probe draws their frame with a canned body; the ones that need
    // nothing (links, markdown, the placeholders) are the real cards.
    return switch (widget.kind) {
      WidgetKind.markdown ||
      WidgetKind.workLinks ||
      WidgetKind.otherLinks ||
      WidgetKind.welcome ||
      WidgetKind.vsShortcuts ||
      WidgetKind.newWorkItem ||
      WidgetKind.codeTile => DashboardRegistry.cardFor(widget)!(args),
      _ when widget.isBuiltIn => DashboardRegistry.cardFor(widget)!(args),
      _ => DashboardCard(
        title: widget.name,
        icon: Icons.dashboard_outlined,
        filled: filled,
        child: Text('${widget.kind.name} · needs an account'),
      ),
    };
  }
}
