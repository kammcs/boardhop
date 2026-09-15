import '../../data/models/dashboard.dart';

/// Boardhop's own dashboard (decision D9), offered when a team's real
/// dashboard is empty — which three of the four puremedia projects' are —
/// and listed in the picker as an entry of its own (D6).
///
/// It is a [Dashboard] like any other, so the page, the layout mapper and
/// the card registry need to know nothing about it: six widgets, placed on
/// the same 10-column grid the service uses, each tagged with
/// [DashboardWidget.builtInKind] rather than a contributionId. A synthetic
/// contributionId was the alternative and would have been read as a
/// Marketplace widget (`WidgetKind.fromContributionId` treats any publisher
/// but `ms` as one) and hidden.
///
/// The cards themselves arrive with the charting phase; until then every
/// one of them draws the placeholder frame, so the page, the picker entry
/// and the empty-dashboard offer all work end to end.
abstract final class TeamOverview {
  /// The id the route and [DashboardPrefs] use for it. Not a GUID on
  /// purpose: it can never collide with a dashboard of the service, and a
  /// deep link that carries it is unambiguous.
  static const id = 'boardhop-team-overview';

  static const name = 'Team overview';

  /// The built-in card kinds, in the order they are laid out.
  static const sprintBurndown = 'sprintBurndown';
  static const workByState = 'workByState';
  static const cumulativeFlow = 'cumulativeFlow';
  static const cycleLeadTime = 'cycleLeadTime';
  static const velocity = 'velocity';
  static const pipelineOutcomes = 'pipelineOutcomes';

  static bool isTeamOverview(String? dashboardId) => dashboardId == id;

  /// The six cards as a dashboard. [teamId] is the team whose data they
  /// draw; it rides along on the dashboard so the cards receive it the way
  /// a real dashboard's `groupId` reaches them.
  static Dashboard forTeam(String? teamId) => Dashboard(
    id: id,
    name: name,
    description: "Boardhop's own overview of this team.",
    scope: DashboardScope.team,
    teamId: teamId,
    widgets: [
      _widget('burndown', 'Sprint burndown', sprintBurndown, 1, 1, 2, 2),
      _widget('by-state', 'Work by state', workByState, 1, 3, 2, 2),
      _widget('cfd', 'Cumulative flow', cumulativeFlow, 3, 1, 2, 2),
      _widget('cycle', 'Cycle and lead time', cycleLeadTime, 3, 3, 2, 2),
      _widget('velocity', 'Velocity', velocity, 5, 1, 2, 2),
      _widget('pipelines', 'Pipeline pass rate', pipelineOutcomes, 5, 3, 2, 2),
    ],
  );

  static DashboardWidget _widget(
    String id,
    String name,
    String kind,
    int row,
    int column,
    int rowSpan,
    int columnSpan,
  ) => DashboardWidget(
    id: 'boardhop.$id',
    name: name,
    contributionId: '',
    row: row,
    column: column,
    rowSpan: rowSpan,
    columnSpan: columnSpan,
    builtInKind: kind,
  );

  /// What each card will draw once the charting phase lands, for the
  /// placeholder to name.
  static String noteFor(String builtInKind) => switch (builtInKind) {
    sprintBurndown =>
      'The current sprint’s burndown arrives in the '
          'next phase.',
    workByState => 'Work by state arrives in the next phase.',
    cumulativeFlow =>
      'The cumulative flow of the last 30 days arrives in '
          'the next phase.',
    cycleLeadTime =>
      'Cycle and lead time over 60 days arrive in the next '
          'phase.',
    velocity =>
      'Velocity over the last six sprints arrives in the next '
          'phase.',
    pipelineOutcomes =>
      'The 90-day pipeline pass rate arrives in the next '
          'phase.',
    _ => 'Chart arrives in the next phase.',
  };
}
