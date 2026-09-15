import 'dart:convert';

import 'package:equatable/equatable.dart';

/// Dashboards, their widgets, and the typed settings of every widget kind
/// Boardhop renders (research/19 §4.1).
///
/// Three things from the spikes shape these models (research/19 §1, s57/s58
/// and the w36 write):
///
/// * **The list route carries no widgets.** `{project}/_apis/dashboard/
///   dashboards` answers the summaries of every team's dashboards;
///   `widgets[]` only arrives from the team-scoped GET by id, which is a 404
///   without the team segment. So [DashboardSummary] and [Dashboard] are two
///   models, not one with a nullable list.
/// * **`settings` is an opaque string the service never validates.** w36
///   posted thirteen widgets to the scratch dashboard and every one read back
///   byte-for-byte, including a Markdown widget whose settings are plain text
///   and not JSON at all. So [DashboardWidget.settings] stays a raw string,
///   [DashboardWidget.settingsJson] is lazy and null when the string is not a
///   JSON object, and every typed parser tolerates missing keys and returns
///   null on a shape it does not understand (→ the widget is hidden, D10).
/// * **The kind is the contributionId's last segment.** Publisher and area
///   differ (`ms.vss-dashboards-web.…`, `ms.vss-mywork-web.…`,
///   `ms.vss-releaseManagement-web.…`), the suffix does not; anything from a
///   publisher other than `ms` is a Marketplace widget.

/// `dashboardScope` on the wire. Every dashboard in puremedia is
/// `project_Team`; `project` exists in the service and has never been seen.
enum DashboardScope {
  team('project_Team'),
  project('project'),
  unknown('');

  const DashboardScope(this.wire);

  final String wire;

  static DashboardScope parse(String? value) => values.firstWhere(
    (s) => s.wire.toLowerCase() == (value ?? '').toLowerCase(),
    orElse: () => DashboardScope.unknown,
  );
}

/// The widget kinds Boardhop knows by name. Everything else is [unknown] and
/// is hidden behind the footer line (D10), named from the widget-type catalog.
enum WidgetKind {
  queryTile,
  queryResults,
  workItemChart,
  assignedToMe,
  pullRequests,
  teamMembers,
  markdown,
  buildHistory,
  codeTile,
  burndown,
  burnup,
  sprintOverview,
  sprintBurndown,
  sprintBurndownLegacy,
  cycleTime,
  leadTime,
  cumulativeFlow,
  velocity,
  sprintCapacity,
  newWorkItem,
  welcome,
  otherLinks,
  vsShortcuts,
  workLinks,
  embeddedWebpage,
  releaseOverview,
  deploymentStatus,
  testResultsTrend,
  marketplace,
  unknown;

  /// The last dot-separated segment of a contributionId, which is the only
  /// stable part: `ms.vss-dashboards-web.Microsoft.VisualStudioOnline.
  /// Dashboards.QueryScalarWidget` → `QueryScalarWidget`.
  static const _bySuffix = <String, WidgetKind>{
    'QueryScalarWidget': WidgetKind.queryTile,
    'WitViewWidget': WidgetKind.queryResults,
    'WitChartWidget': WidgetKind.workItemChart,
    'AssignedToMeWidget': WidgetKind.assignedToMe,
    'PullrequestsWidget': WidgetKind.pullRequests,
    // The legacy My Work widget shows the same pull requests.
    'PullRequestWidget': WidgetKind.pullRequests,
    'TeamMembersWidget': WidgetKind.teamMembers,
    'MarkdownWidget': WidgetKind.markdown,
    'BuildHistogramWidget': WidgetKind.buildHistory,
    'CodeScalarWidget': WidgetKind.codeTile,
    'BurndownWidget': WidgetKind.burndown,
    'BurnupWidget': WidgetKind.burnup,
    'SprintOverviewWidget': WidgetKind.sprintOverview,
    'AnalyticsSprintBurndownWidget': WidgetKind.sprintBurndown,
    'SprintBurndownWidget': WidgetKind.sprintBurndownLegacy,
    'CycleTimeWidget': WidgetKind.cycleTime,
    'LeadTimeWidget': WidgetKind.leadTime,
    'CumulativeFlowDiagramWidget': WidgetKind.cumulativeFlow,
    'VelocityWidget': WidgetKind.velocity,
    'SprintCapacityWidget': WidgetKind.sprintCapacity,
    'NewWorkItemWidget': WidgetKind.newWorkItem,
    'HowToLinksWidget': WidgetKind.welcome,
    'OtherLinksWidget': WidgetKind.otherLinks,
    'VSLinksWidget': WidgetKind.vsShortcuts,
    'WorkLinksWidget': WidgetKind.workLinks,
    'IFrameWidget': WidgetKind.embeddedWebpage,
    'rm-deployment-status-widget': WidgetKind.deploymentStatus,
    'release-definition-summary-widget': WidgetKind.releaseOverview,
    'TestResultsTrendWidget': WidgetKind.testResultsTrend,
    'AnalyticsTestTrendWidget': WidgetKind.testResultsTrend,
    'TestResultsDurationTrendWidget': WidgetKind.testResultsTrend,
    'TestResultsFailureTrendWidget': WidgetKind.testResultsTrend,
  };

  static WidgetKind fromContributionId(String? contributionId) {
    final id = contributionId ?? '';
    if (id.isEmpty) return WidgetKind.unknown;
    // Publisher is the first segment: anything but `ms` came from the
    // Marketplace and Boardhop cannot render it (D10).
    final publisher = id.split('.').first;
    final suffix = id.split('.').last;
    final known = _bySuffix[suffix];
    if (known != null) return known;
    return publisher == 'ms' ? WidgetKind.unknown : WidgetKind.marketplace;
  }
}

/// One entry of the project-wide dashboard list (no widgets).
class DashboardSummary extends Equatable {
  const DashboardSummary({
    required this.id,
    required this.name,
    this.description,
    this.scope = DashboardScope.unknown,
    this.teamId,
    this.ownerId,
    this.position = 0,
    this.refreshInterval = 0,
    this.widgetCount,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) =>
      DashboardSummary(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        scope: DashboardScope.parse(json['dashboardScope'] as String?),
        // `groupId` is the team the dashboard belongs to and is what the
        // team-scoped GET by id needs.
        teamId: json['groupId'] as String?,
        ownerId: json['ownerId'] as String?,
        position: _int(json['position']) ?? 0,
        refreshInterval: _int(json['refreshInterval']) ?? 0,
        widgetCount: json['widgets'] is List
            ? (json['widgets']! as List).length
            : null,
      );

  final String id;
  final String name;
  final String? description;
  final DashboardScope scope;

  /// `groupId` on the wire: the team that owns the dashboard.
  final String? teamId;
  final String? ownerId;
  final int position;

  /// Minutes; 0 is off. Boardhop ignores it (D12) and keeps it for the UI to
  /// explain itself if it ever needs to.
  final int refreshInterval;
  final int? widgetCount;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    'dashboardScope': scope.wire,
    if (teamId != null) 'groupId': teamId,
    if (ownerId != null) 'ownerId': ownerId,
    'position': position,
    'refreshInterval': refreshInterval,
  };

  @override
  List<Object?> get props => [id, name, description, scope, teamId, position];
}

/// One dashboard with its widgets, from the team-scoped GET by id.
class Dashboard extends Equatable {
  const Dashboard({
    required this.id,
    required this.name,
    this.description,
    this.scope = DashboardScope.unknown,
    this.teamId,
    this.ownerId,
    this.position = 0,
    this.refreshInterval = 0,
    this.eTag,
    this.widgets = const [],
  });

  factory Dashboard.fromJson(Map<String, dynamic> json) => Dashboard(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String?,
    scope: DashboardScope.parse(json['dashboardScope'] as String?),
    teamId: json['groupId'] as String?,
    ownerId: json['ownerId'] as String?,
    position: _int(json['position']) ?? 0,
    refreshInterval: _int(json['refreshInterval']) ?? 0,
    // The service sends an eTag as a string on an edited dashboard and
    // nothing at all on one nobody has touched.
    eTag: json['eTag']?.toString(),
    widgets: [
      for (final w in _list(json['widgets']))
        if (w is Map) DashboardWidget.fromJson(w.cast<String, dynamic>()),
    ],
  );

  final String id;
  final String name;
  final String? description;
  final DashboardScope scope;
  final String? teamId;
  final String? ownerId;
  final int position;
  final int refreshInterval;
  final String? eTag;

  /// In wire order, which is not reading order: [orderedWidgets] sorts.
  final List<DashboardWidget> widgets;

  /// Enabled widgets in reading order (row, then column), which is the order
  /// the phone stacks them in (D4).
  List<DashboardWidget> get orderedWidgets =>
      [...widgets.where((w) => w.isEnabled)]..sort((a, b) {
        final byRow = a.row.compareTo(b.row);
        return byRow != 0 ? byRow : a.column.compareTo(b.column);
      });

  DashboardSummary get summary => DashboardSummary(
    id: id,
    name: name,
    description: description,
    scope: scope,
    teamId: teamId,
    ownerId: ownerId,
    position: position,
    refreshInterval: refreshInterval,
    widgetCount: widgets.length,
  );

  Map<String, dynamic> toJson() => {
    ...summary.toJson(),
    if (eTag != null) 'eTag': eTag,
    'widgets': [for (final w in widgets) w.toJson()],
  };

  @override
  List<Object?> get props => [id, name, scope, teamId, eTag, widgets];
}

/// One widget on a dashboard.
///
/// [row] and [column] are **1-based** and the web grid is 10 columns wide.
/// [settings] is whatever string the widget's own configuration wrote; the
/// service stores it verbatim (w36), so nothing about it can be assumed.
class DashboardWidget extends Equatable {
  DashboardWidget({
    required this.id,
    required this.name,
    required this.contributionId,
    this.row = 1,
    this.column = 1,
    this.rowSpan = 1,
    this.columnSpan = 1,
    this.settings,
    this.settingsVersion,
    this.isEnabled = true,
    this.typeId,
    this.configurationContributionId,
    this.builtInKind = '',
  });

  factory DashboardWidget.fromJson(Map<String, dynamic> json) {
    final position = _map(json['position']);
    final size = _map(json['size']);
    final version = _map(json['settingsVersion']);
    return DashboardWidget(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      contributionId: json['contributionId'] as String? ?? '',
      // The grid is 1-based; a widget with no position is top-left.
      row: _int(position?['row']) ?? 1,
      column: _int(position?['column']) ?? 1,
      rowSpan: _int(size?['rowSpan']) ?? 1,
      columnSpan: _int(size?['columnSpan']) ?? 1,
      settings: json['settings'] as String?,
      settingsVersion: version == null
          ? null
          : '${version['major'] ?? 0}.${version['minor'] ?? 0}'
                '.${version['patch'] ?? 0}',
      isEnabled: _bool(json['isEnabled']) ?? true,
      typeId: json['typeId'] as String?,
      configurationContributionId:
          json['configurationContributionId'] as String?,
    );
  }

  final String id;
  final String name;
  final String contributionId;
  final int row;
  final int column;
  final int rowSpan;
  final int columnSpan;
  final String? settings;
  final String? settingsVersion;
  final bool isEnabled;
  final String? typeId;
  final String? configurationContributionId;

  /// Boardhop's own card name for a **synthetic** widget — one this app
  /// composed rather than read from the service, which is the Team overview
  /// and nothing else (research/19 D9). Empty for every widget that came
  /// off the wire, so [kind] and the hiding rules are untouched by it.
  ///
  /// A synthetic contributionId was the alternative and is worse: the
  /// publisher segment of anything but `ms` is a Marketplace widget
  /// ([WidgetKind.fromContributionId]), so `boardhop.…` would classify the
  /// Team overview's own cards as unrenderable.
  final String builtInKind;

  bool get isBuiltIn => builtInKind.isNotEmpty;

  WidgetKind get kind => WidgetKind.fromContributionId(contributionId);

  /// [settings] decoded, or null when it is absent, not JSON (the Markdown
  /// widget stores plain text) or not a JSON **object**. Decoded once, on
  /// first use: a card asks for it on every build.
  late final Map<String, dynamic>? settingsJson = _decodeSettings();

  Map<String, dynamic>? _decodeSettings() {
    final raw = settings;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      // Plain text settings: not an error, just not JSON.
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'contributionId': contributionId,
    'position': {'row': row, 'column': column},
    'size': {'rowSpan': rowSpan, 'columnSpan': columnSpan},
    if (settings != null) 'settings': settings,
    if (settingsVersion != null) 'settingsVersion': _versionJson,
    'isEnabled': isEnabled,
    if (typeId != null) 'typeId': typeId,
    if (configurationContributionId != null)
      'configurationContributionId': configurationContributionId,
  };

  Map<String, dynamic> get _versionJson {
    final parts = (settingsVersion ?? '').split('.');
    int at(int i) => i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0;
    return {'major': at(0), 'minor': at(1), 'patch': at(2)};
  }

  @override
  List<Object?> get props => [
    id,
    name,
    contributionId,
    row,
    column,
    rowSpan,
    columnSpan,
    settings,
    isEnabled,
    builtInKind,
  ];
}

/// An entry of the widget-type catalog, used only to name a widget kind the
/// app does not render (D10).
class DashboardWidgetType extends Equatable {
  const DashboardWidgetType({
    required this.contributionId,
    required this.name,
    this.description,
    this.catalogIconUrl,
    this.analyticsServiceRequired = false,
    this.isVisibleFromCatalog = true,
  });

  factory DashboardWidgetType.fromJson(Map<String, dynamic> json) =>
      DashboardWidgetType(
        contributionId: json['contributionId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        catalogIconUrl: json['catalogIconUrl'] as String?,
        analyticsServiceRequired:
            _bool(json['analyticsServiceRequired']) ?? false,
        isVisibleFromCatalog: _bool(json['isVisibleFromCatalog']) ?? true,
      );

  final String contributionId;
  final String name;
  final String? description;
  final String? catalogIconUrl;
  final bool analyticsServiceRequired;
  final bool isVisibleFromCatalog;

  Map<String, dynamic> toJson() => {
    'contributionId': contributionId,
    'name': name,
    if (description != null) 'description': description,
    if (catalogIconUrl != null) 'catalogIconUrl': catalogIconUrl,
    'analyticsServiceRequired': analyticsServiceRequired,
    'isVisibleFromCatalog': isVisibleFromCatalog,
  };

  @override
  List<Object?> get props => [contributionId, name];
}

// --------------------------------------------------------------- settings

/// `{projectId, teamId}`, the pair every team-scoped widget carries.
class WidgetTeamRef extends Equatable {
  const WidgetTeamRef({this.projectId, this.teamId});

  static WidgetTeamRef? parse(Object? json) {
    if (json is! Map) return null;
    final team = json['teamId'] as String?;
    final project = json['projectId'] as String?;
    if ((team ?? '').isEmpty && (project ?? '').isEmpty) return null;
    return WidgetTeamRef(projectId: project, teamId: team);
  }

  final String? projectId;
  final String? teamId;

  @override
  List<Object?> get props => [projectId, teamId];
}

/// `workItemTypeFilter: {identifier, settings}`. [identifier] is
/// `BacklogCategory` (settings = a category reference name such as
/// `Microsoft.RequirementCategory`) or `WorkItemType` (settings = a type
/// name, or a comma-separated list).
class WidgetTypeFilter extends Equatable {
  const WidgetTypeFilter({required this.identifier, this.settings});

  static WidgetTypeFilter? parse(Object? json) {
    if (json is! Map) return null;
    final identifier = json['identifier'] as String?;
    if (identifier == null || identifier.isEmpty) return null;
    return WidgetTypeFilter(
      identifier: identifier,
      settings: json['settings']?.toString(),
    );
  }

  final String identifier;
  final String? settings;

  bool get isBacklogCategory => identifier == 'BacklogCategory';

  /// The explicit work item types when the filter names them, else empty
  /// (the caller then resolves the backlog category through Analytics).
  List<String> get workItemTypes => isBacklogCategory
      ? const []
      : [
          for (final t in (settings ?? '').split(','))
            if (t.trim().isNotEmpty) t.trim(),
        ];

  @override
  List<Object?> get props => [identifier, settings];
}

/// `fieldFilters: [{fieldName, queryOperation, queryValue}]`.
class WidgetFieldFilter extends Equatable {
  const WidgetFieldFilter({
    required this.fieldName,
    this.queryOperation,
    this.queryValue,
  });

  static WidgetFieldFilter? parse(Object? json) {
    if (json is! Map) return null;
    final field = json['fieldName'] as String?;
    if (field == null || field.isEmpty) return null;
    return WidgetFieldFilter(
      fieldName: field,
      queryOperation: json['queryOperation']?.toString(),
      queryValue: json['queryValue']?.toString(),
    );
  }

  final String fieldName;
  final String? queryOperation;
  final String? queryValue;

  @override
  List<Object?> get props => [fieldName, queryOperation, queryValue];
}

/// `aggregation: {identifier, settings}` — `0` counts work items, `1` sums
/// the field named in settings (Story Points on every dashboard seen).
class WidgetAggregation extends Equatable {
  const WidgetAggregation({required this.isSum, this.field});

  static WidgetAggregation? parse(Object? json) {
    if (json is! Map) return null;
    final identifier = json['identifier'];
    final isSum = identifier is num
        ? identifier.toInt() == 1
        : identifier?.toString().toLowerCase() == 'sum';
    return WidgetAggregation(isSum: isSum, field: json['settings']?.toString());
  }

  final bool isSum;

  /// The field as the widget stores it: a work item **reference name**, such
  /// as `Microsoft.VSTS.Scheduling.StoryPoints`.
  final String? field;

  /// [field] as the Analytics entity names the same value.
  ///
  /// The widget settings carry the work item reference name, and Analytics
  /// does not: `Microsoft.VSTS.Scheduling.StoryPoints` in an `aggregate(…
  /// with sum as …)` is a **400 Bad Request**, which is what the client
  /// project's Burndown and Burnup cards were showing (D-D walkthrough).
  /// System and Microsoft fields drop their namespace; a custom field keeps
  /// its `Custom_` prefix; anything already unqualified is passed through,
  /// so a settings value that is an Analytics name still works.
  String? get analyticsField {
    final name = field?.trim();
    if (name == null || name.isEmpty) return null;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return name;
    final prefix = name.substring(0, dot);
    final leaf = name.substring(dot + 1);
    if (leaf.isEmpty) return null;
    if (prefix == 'System' || prefix.startsWith('Microsoft.')) return leaf;
    // A custom field is `Custom.Foo` on the work item and `Custom_Foo` on
    // the Analytics entity.
    return '${prefix.replaceAll('.', '_')}_$leaf';
  }

  @override
  List<Object?> get props => [isSum, field];
}

/// Query Tile (`QueryScalarWidget`): one number, optionally colored by rules.
class QueryTileSettings extends Equatable {
  const QueryTileSettings({
    required this.queryId,
    this.queryName,
    this.lastArtifactName,
    this.defaultBackgroundColor,
    this.colorRules = const [],
  });

  static QueryTileSettings? parse(Map<String, dynamic>? json) {
    final id = json?['queryId'] as String?;
    if (id == null || id.isEmpty) return null;
    return QueryTileSettings(
      queryId: id,
      queryName: json?['queryName'] as String?,
      lastArtifactName: json?['lastArtifactName'] as String?,
      defaultBackgroundColor: json?['defaultBackgroundColor'] as String?,
      colorRules: [
        for (final r in _list(json?['colorRules']))
          if (r is Map)
            QueryTileColorRule.parse(r.cast<String, dynamic>()) ??
                const QueryTileColorRule(),
      ],
    );
  }

  final String queryId;
  final String? queryName;
  final String? lastArtifactName;
  final String? defaultBackgroundColor;
  final List<QueryTileColorRule> colorRules;

  /// What the tile is called when the widget has no name of its own.
  String? get label => queryName ?? lastArtifactName;

  @override
  List<Object?> get props => [queryId, queryName, defaultBackgroundColor];
}

/// One `colorRules[]` entry: `{backgroundColor, isEnabled, operator,
/// thresholdCount}`. Never seen populated live (every dashboard had `[]`),
/// so every key is optional.
class QueryTileColorRule extends Equatable {
  const QueryTileColorRule({
    this.backgroundColor,
    this.operator,
    this.threshold,
    this.isEnabled = true,
  });

  static QueryTileColorRule? parse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return QueryTileColorRule(
      backgroundColor: json['backgroundColor'] as String?,
      operator: json['operator']?.toString(),
      threshold: _int(json['thresholdCount']),
      isEnabled: _bool(json['isEnabled']) ?? true,
    );
  }

  final String? backgroundColor;
  final String? operator;
  final int? threshold;
  final bool isEnabled;

  @override
  List<Object?> get props => [backgroundColor, operator, threshold, isEnabled];
}

/// Query Results (`WitViewWidget`): a query's rows in a list.
class QueryResultsSettings extends Equatable {
  const QueryResultsSettings({
    required this.queryId,
    this.queryName,
    this.lastArtifactName,
    this.columns = const [],
  });

  static QueryResultsSettings? parse(Map<String, dynamic>? json) {
    final id = json?['queryId'] as String?;
    if (id == null || id.isEmpty) return null;
    return QueryResultsSettings(
      queryId: id,
      queryName: json?['queryName'] as String?,
      lastArtifactName: json?['lastArtifactName'] as String?,
      columns: [
        for (final c in _list(json?['columns']))
          if (c is String && c.isNotEmpty) c,
      ],
    );
  }

  final String queryId;
  final String? queryName;
  final String? lastArtifactName;

  /// The web lets the widget pick columns; out of v1 on phones (research/19
  /// §6), kept so the card can title itself.
  final List<String> columns;

  String? get label => queryName ?? lastArtifactName;

  @override
  List<Object?> get props => [queryId, queryName, columns];
}

/// Chart for Work Items (`WitChartWidget`): `{chartId}` and nothing else.
///
/// The chart definition has no public route (nine candidates 404, spike
/// s60), and the widget does not carry the query the chart was built on — so
/// D2's fallback has the chart id, the widget's name, and nothing more.
class WitChartSettings extends Equatable {
  const WitChartSettings({required this.chartId});

  static WitChartSettings? parse(Map<String, dynamic>? json) {
    final id = json?['chartId'] as String?;
    if (id == null || id.isEmpty) return null;
    return WitChartSettings(chartId: id);
  }

  final String chartId;

  @override
  List<Object?> get props => [chartId];
}

/// Burndown and Burnup (`BurndownWidget`, `BurnupWidget`): a team burndown
/// over a date range, not a sprint.
class BurndownSettings extends Equatable {
  const BurndownSettings({
    this.teams = const [],
    this.workItemTypeFilter,
    this.fieldFilters = const [],
    this.aggregation,
    this.startDate,
    this.endDate,
    this.sampleInterval,
    this.lastDayOfWeek,
    this.byIteration = false,
    this.burndownTrendlineEnabled = false,
    this.totalScopeTrendlineEnabled = false,
    this.completedWorkEnabled = false,
    this.stackByWorkItemTypeEnabled = false,
    this.showResolvedItemsAsCompletedEnabled = false,
    this.includeBugsForRequirementCategory = false,
  });

  static BurndownSettings? parse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    final teams = [
      for (final t in _list(json['teams'])) ?WidgetTeamRef.parse(t),
    ];
    if (teams.isEmpty) return null;
    final period = _map(json['timePeriodConfiguration']);
    final sampling = _map(period?['samplingConfiguration']);
    final samplingSettings = _map(sampling?['settings']);
    return BurndownSettings(
      teams: teams,
      workItemTypeFilter: WidgetTypeFilter.parse(json['workItemTypeFilter']),
      fieldFilters: [
        for (final f in _list(json['fieldFilters']))
          ?WidgetFieldFilter.parse(f),
      ],
      aggregation: WidgetAggregation.parse(json['aggregation']),
      startDate: _date(period?['startDate']),
      // The end date sits inside the sampling settings, not beside the
      // start date — the one asymmetry in this shape.
      endDate: _date(samplingSettings?['endDate']),
      sampleInterval: _int(samplingSettings?['sampleInterval']),
      lastDayOfWeek: _int(samplingSettings?['lastDayOfWeek']),
      byIteration: _int(sampling?['identifier']) == 1,
      burndownTrendlineEnabled:
          _bool(json['burndownTrendlineEnabled']) ?? false,
      totalScopeTrendlineEnabled:
          _bool(json['totalScopeTrendlineEnabled']) ?? false,
      completedWorkEnabled: _bool(json['completedWorkEnabled']) ?? false,
      stackByWorkItemTypeEnabled:
          _bool(json['stackByWorkItemTypeEnabled']) ?? false,
      showResolvedItemsAsCompletedEnabled:
          _bool(json['showResolvedItemsAsCompletedEnabled']) ?? false,
      includeBugsForRequirementCategory:
          _bool(json['includeBugsForRequirementCategory']) ?? false,
    );
  }

  final List<WidgetTeamRef> teams;
  final WidgetTypeFilter? workItemTypeFilter;
  final List<WidgetFieldFilter> fieldFilters;
  final WidgetAggregation? aggregation;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? sampleInterval;
  final int? lastDayOfWeek;

  /// `samplingConfiguration.identifier`: 0 samples by date, 1 by iteration.
  final bool byIteration;
  final bool burndownTrendlineEnabled;
  final bool totalScopeTrendlineEnabled;
  final bool completedWorkEnabled;
  final bool stackByWorkItemTypeEnabled;
  final bool showResolvedItemsAsCompletedEnabled;
  final bool includeBugsForRequirementCategory;

  WidgetTeamRef? get team => teams.isEmpty ? null : teams.first;

  @override
  List<Object?> get props => [
    teams,
    workItemTypeFilter,
    fieldFilters,
    aggregation,
    startDate,
    endDate,
  ];
}

/// Sprint Burndown, both the Analytics widget and the legacy one: one team,
/// one iteration, an explicit start and end.
class SprintBurndownSettings extends Equatable {
  const SprintBurndownSettings({
    this.team,
    this.iterationId,
    this.iterationPath,
    this.startDate,
    this.endDate,
    this.aggregation,
    this.workItemTypeFilter,
    this.isLegacy = false,
    this.isCustomized = false,
    this.showNonWorkingDays = false,
    this.completedWorkEnabled = false,
    this.totalScopeTrendlineEnabled = false,
    this.showResolvedItemsAsCompletedEnabled = false,
    this.stackByWorkItemTypeEnabled = false,
  });

  static SprintBurndownSettings? parse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    final team = WidgetTeamRef.parse(json['team']);
    final iterationId = json['iterationId']?.toString();
    // Neither a team nor an iteration means nothing can be charted.
    if (team == null && (iterationId == null || iterationId.isEmpty)) {
      return null;
    }
    final period = _map(json['timePeriodConfiguration']);
    return SprintBurndownSettings(
      team: team,
      iterationId: (iterationId?.isEmpty ?? true) ? null : iterationId,
      iterationPath: json['iterationPath'] as String?,
      startDate: _date(period?['startDate']),
      endDate: _date(period?['endDate']),
      aggregation: WidgetAggregation.parse(json['aggregation']),
      workItemTypeFilter: WidgetTypeFilter.parse(json['workItemTypeFilter']),
      isLegacy: _bool(json['isLegacy']) ?? false,
      isCustomized: _bool(json['isCustomized']) ?? false,
      showNonWorkingDays: _bool(json['showNonWorkingDays']) ?? false,
      completedWorkEnabled: _bool(json['completedWorkEnabled']) ?? false,
      totalScopeTrendlineEnabled:
          _bool(json['totalScopeTrendlineEnabled']) ?? false,
      showResolvedItemsAsCompletedEnabled:
          _bool(json['showResolvedItemsAsCompletedEnabled']) ?? false,
      stackByWorkItemTypeEnabled:
          _bool(json['stackByWorkItemTypeEnabled']) ?? false,
    );
  }

  final WidgetTeamRef? team;

  /// A GUID as a string on the Analytics widget; the legacy widget has been
  /// seen with a 17-character id, so this is never parsed as anything but
  /// text.
  final String? iterationId;
  final String? iterationPath;
  final DateTime? startDate;
  final DateTime? endDate;
  final WidgetAggregation? aggregation;
  final WidgetTypeFilter? workItemTypeFilter;
  final bool isLegacy;
  final bool isCustomized;
  final bool showNonWorkingDays;
  final bool completedWorkEnabled;
  final bool totalScopeTrendlineEnabled;
  final bool showResolvedItemsAsCompletedEnabled;
  final bool stackByWorkItemTypeEnabled;

  @override
  List<Object?> get props => [
    team,
    iterationId,
    iterationPath,
    startDate,
    endDate,
    isLegacy,
  ];
}

/// Velocity. The configured shape is w36's; the widget's settings are
/// **null** on every dashboard seen live, which means "this team, six
/// iterations, count" — so this parser answers [defaults] rather than null
/// for an absent shape.
class VelocitySettings extends Equatable {
  const VelocitySettings({
    this.team,
    this.iterations = defaultIterations,
    this.aggregation,
    this.workItemTypeFilter,
    this.fieldFilters = const [],
  });

  static const defaultIterations = 6;
  static const defaults = VelocitySettings();

  static VelocitySettings parse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return defaults;
    final teams = _list(json['teams']);
    final team =
        WidgetTeamRef.parse(teams.isEmpty ? null : teams.first) ??
        WidgetTeamRef.parse({
          'projectId': json['projectId'],
          'teamId': json['teamId'],
        });
    final count =
        _int(json['numberOfIterations']) ??
        _int(json['iterations']) ??
        defaultIterations;
    return VelocitySettings(
      team: team,
      iterations: count <= 0 ? defaultIterations : count,
      aggregation: WidgetAggregation.parse(json['aggregation']),
      workItemTypeFilter: WidgetTypeFilter.parse(json['workItemTypeFilter']),
      fieldFilters: [
        for (final f in _list(json['fieldFilters']))
          ?WidgetFieldFilter.parse(f),
      ],
    );
  }

  final WidgetTeamRef? team;
  final int iterations;
  final WidgetAggregation? aggregation;
  final WidgetTypeFilter? workItemTypeFilter;
  final List<WidgetFieldFilter> fieldFilters;

  @override
  List<Object?> get props => [team, iterations, aggregation, fieldFilters];
}

/// Cumulative Flow Diagram.
class CfdSettings extends Equatable {
  const CfdSettings({
    this.team,
    this.boardName,
    this.backlogLevelName,
    this.swimlane,
    this.days = defaultDays,
    this.hideIncoming = false,
    this.hideOutgoing = false,
  });

  static const defaultDays = 30;

  static CfdSettings? parse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    final team = WidgetTeamRef.parse({
      'projectId': json['projectId'],
      'teamId': json['teamId'],
    });
    final board = json['boardName'] as String?;
    final level = json['backlogLevelName'] as String?;
    // The board is what the Analytics query filters on; without either name
    // the card cannot pick one.
    if ((board ?? '').isEmpty && (level ?? '').isEmpty) return null;
    final days = _int(json['numberOfDays']) ?? defaultDays;
    return CfdSettings(
      team: team,
      boardName: (board?.isEmpty ?? true) ? null : board,
      backlogLevelName: (level?.isEmpty ?? true) ? null : level,
      swimlane: json['swimlane'] as String?,
      days: days <= 0 ? defaultDays : days,
      hideIncoming: _bool(json['hideIncoming']) ?? false,
      hideOutgoing: _bool(json['hideOutgoing']) ?? false,
    );
  }

  final WidgetTeamRef? team;
  final String? boardName;
  final String? backlogLevelName;

  /// `All` means every lane; a named lane is a filter the card ignores in v1.
  final String? swimlane;
  final int days;
  final bool hideIncoming;
  final bool hideOutgoing;

  /// The board the Analytics query names; the backlog level's name is the
  /// board's name in every process seen.
  String get board => boardName ?? backlogLevelName ?? '';

  @override
  List<Object?> get props => [team, boardName, backlogLevelName, days];
}

/// Cycle Time and Lead Time: the same shape, one per widget kind.
class CycleTimeSettings extends Equatable {
  const CycleTimeSettings({
    this.team,
    this.workItemTypeFilter,
    this.fieldFilters = const [],
    this.days = defaultDays,
  });

  static const defaultDays = 30;

  static CycleTimeSettings? parse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    final team = WidgetTeamRef.parse({
      'projectId': json['projectId'],
      'teamId': json['teamId'],
    });
    if (team == null) return null;
    final days =
        _int(json['timePeriodInDays']) ??
        _int(json['numberOfDays']) ??
        defaultDays;
    return CycleTimeSettings(
      team: team,
      workItemTypeFilter: WidgetTypeFilter.parse(json['workItemTypeFilter']),
      fieldFilters: [
        for (final f in _list(json['fieldFilters']))
          ?WidgetFieldFilter.parse(f),
      ],
      days: days <= 0 ? defaultDays : days,
    );
  }

  final WidgetTeamRef? team;
  final WidgetTypeFilter? workItemTypeFilter;
  final List<WidgetFieldFilter> fieldFilters;
  final int days;

  @override
  List<Object?> get props => [team, workItemTypeFilter, fieldFilters, days];
}

/// Build History (`BuildHistogramWidget`).
class BuildHistorySettings extends Equatable {
  const BuildHistorySettings({
    required this.definitionId,
    this.defaultBranch,
    this.uri,
  });

  static BuildHistorySettings? parse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    // `buildDefinition` is the id **as a string**; `uri` is
    // `vstfs:///Build/Definition/{id}` and is the fallback.
    final raw = json['buildDefinition'] ?? json['buildDefinitionId'];
    var id = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    final uri = json['uri'] as String?;
    id ??= int.tryParse((uri ?? '').split('/').last);
    if (id == null) return null;
    return BuildHistorySettings(
      definitionId: id,
      defaultBranch: json['defaultBranch'] as String?,
      uri: uri,
    );
  }

  final int definitionId;
  final String? defaultBranch;
  final String? uri;

  @override
  List<Object?> get props => [definitionId, defaultBranch, uri];
}

/// Code Tile (`CodeScalarWidget`).
class CodeTileSettings extends Equatable {
  const CodeTileSettings({
    required this.repositoryId,
    this.projectId,
    this.repositoryName,
    this.branchName,
    this.path,
  });

  static CodeTileSettings? parse(Map<String, dynamic>? json) {
    final id = json?['repositoryId'] as String?;
    if (id == null || id.isEmpty) return null;
    return CodeTileSettings(
      repositoryId: id,
      projectId: json?['projectId'] as String?,
      repositoryName: json?['repositoryName'] as String?,
      branchName: json?['branchName'] as String?,
      path: json?['path'] as String?,
    );
  }

  final String repositoryId;
  final String? projectId;
  final String? repositoryName;
  final String? branchName;
  final String? path;

  @override
  List<Object?> get props => [
    repositoryId,
    projectId,
    repositoryName,
    branchName,
    path,
  ];
}

/// Markdown. The settings string **is** the markdown: w36 wrote plain text
/// and read it back unchanged. The web's own configuration has also been
/// documented to wrap it as `{"content": …}` with a repo-file variant
/// (`{"path", "repositoryId", "branch"}`), so both are accepted.
class MarkdownSettings extends Equatable {
  const MarkdownSettings({
    this.content = '',
    this.repositoryId,
    this.path,
    this.branch,
  });

  /// Takes the **raw** settings string, not the decoded map: the common case
  /// is not JSON at all.
  static MarkdownSettings? parse(String? raw) {
    final text = raw ?? '';
    if (text.trim().isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      decoded = null;
    }
    if (decoded is! Map) return MarkdownSettings(content: text);
    final json = decoded.cast<String, dynamic>();
    final content = (json['content'] ?? json['markdown'] ?? '').toString();
    final path = json['path'] as String?;
    final repo = json['repositoryId'] as String?;
    if (content.trim().isEmpty && (path ?? '').isEmpty) return null;
    return MarkdownSettings(
      content: content,
      repositoryId: repo,
      path: path,
      branch: (json['branch'] ?? json['branchName']) as String?,
    );
  }

  final String content;

  /// The repo-file variant: the widget renders a file instead of inline
  /// text. Out of v1 (the card shows a link), but parsed so it is not hidden.
  final String? repositoryId;
  final String? path;
  final String? branch;

  bool get isFile => (path ?? '').isNotEmpty;

  @override
  List<Object?> get props => [content, repositoryId, path, branch];
}

/// Sprint Overview. The one key seen is `showWorkItems`; a widget with no
/// settings at all shows the current sprint, so an empty map is valid.
class SprintOverviewSettings extends Equatable {
  const SprintOverviewSettings({this.showWorkItems = true});

  static const defaults = SprintOverviewSettings();

  static SprintOverviewSettings parse(Map<String, dynamic>? json) =>
      SprintOverviewSettings(
        showWorkItems: _bool(json?['showWorkItems']) ?? true,
      );

  final bool showWorkItems;

  @override
  List<Object?> get props => [showWorkItems];
}

/// Typed settings for a widget, or null when the kind has none, the shape is
/// unrecognised (→ hidden, D10) or Boardhop does not render the kind.
Object? parseWidgetSettings(DashboardWidget widget) => switch (widget.kind) {
  WidgetKind.queryTile => QueryTileSettings.parse(widget.settingsJson),
  WidgetKind.queryResults => QueryResultsSettings.parse(widget.settingsJson),
  WidgetKind.workItemChart => WitChartSettings.parse(widget.settingsJson),
  WidgetKind.burndown ||
  WidgetKind.burnup => BurndownSettings.parse(widget.settingsJson),
  WidgetKind.sprintBurndown || WidgetKind.sprintBurndownLegacy =>
    SprintBurndownSettings.parse(widget.settingsJson),
  WidgetKind.velocity => VelocitySettings.parse(widget.settingsJson),
  WidgetKind.cumulativeFlow => CfdSettings.parse(widget.settingsJson),
  WidgetKind.cycleTime ||
  WidgetKind.leadTime => CycleTimeSettings.parse(widget.settingsJson),
  WidgetKind.buildHistory => BuildHistorySettings.parse(widget.settingsJson),
  WidgetKind.codeTile => CodeTileSettings.parse(widget.settingsJson),
  WidgetKind.markdown => MarkdownSettings.parse(widget.settings),
  WidgetKind.sprintOverview => SprintOverviewSettings.parse(
    widget.settingsJson,
  ),
  _ => null,
};

/// `true`/`false`, or null for anything that is not a boolean.
bool? _bool(Object? value) => value is bool ? value : null;

/// An integer, or null for anything that is not a number.
int? _int(Object? value) => value is num ? value.toInt() : null;

/// A nested object, or null when the key is missing or holds something else.
/// The service stores `settings` verbatim (w36), so a future widget version
/// can put a string where this version put an object; a cast would throw and
/// hide the whole dashboard instead of one card.
Map<String, dynamic>? _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : null;

/// A nested array, or an empty list for anything else.
List<Object?> _list(Object? value) => value is List ? value : const [];

DateTime? _date(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  // Dates arrive as `2024-09-23` (date only) or a full timestamp; both are
  // kept in UTC so a local shift never moves a chart's first day.
  final parsed = DateTime.tryParse(
    text.length == 10 ? '${text}T00:00:00Z' : text,
  );
  return parsed?.toUtc();
}
