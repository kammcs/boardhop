import 'dart:convert';

import '../../demo_world.dart';
import 'demo_history.dart';

/// The Boardhop team's three dashboards and the saved queries their tiles
/// and lists run. Built on request, so every date and count follows
/// `DemoWorld` on the day the screenshots are taken.
abstract final class DemoDashboards {
  static const overviewId = 'a3f1c2d4-5e6b-4a7c-8d9e-0f1a2b3c4d5e';
  static const releaseId = 'b4e2d3c5-6f7a-4b8d-9e0f-1a2b3c4d5e6f';
  static const relayId = 'c5f3e4d6-7a8b-4c9e-8f1a-2b3c4d5e6f70';

  static const _dashboards =
      'ms.vss-dashboards-web.Microsoft.VisualStudioOnline'
      '.Dashboards';
  static const _analytics = 'ms.vss-analytics-dashboards';

  static final String _teamUrl =
      '${DemoWorld.projectUrl}/${DemoWorld.teamId}/_apis/dashboard/dashboards';

  static List<Map<String, dynamic>> get all => [overview(), release(), relay()];

  static Map<String, dynamic>? byId(String id) {
    for (final d in all) {
      if ((d['id'] as String).toLowerCase() == id.toLowerCase()) return d;
    }
    return null;
  }

  /// The list route's shape: no widgets.
  static Map<String, dynamic> summary(Map<String, dynamic> d) => {
    for (final e in d.entries)
      if (e.key != 'widgets') e.key: e.value,
  };

  // ------------------------------------------------------------ dashboards

  static Map<String, dynamic> _dashboard({
    required String id,
    required String name,
    required String description,
    required int position,
    required int eTag,
    required List<Map<String, dynamic>> widgets,
  }) => {
    'id': id,
    'name': name,
    'description': description,
    'dashboardScope': 'project_Team',
    'groupId': DemoWorld.teamId,
    'ownerId': DemoWorld.teamId,
    'position': position,
    'refreshInterval': 0,
    'eTag': '$eTag',
    'modifiedDate': DemoWorld.iso(DemoWorld.daysAgo(2 + position)),
    'lastAccessedDate': DemoWorld.iso(DemoWorld.hoursAgo(position)),
    'url': '$_teamUrl/$id',
    '_links': {
      'self': {'href': '$_teamUrl/$id'},
      'group': {'href': _teamUrl},
    },
    'widgets': [
      for (final w in widgets)
        {
          ...w,
          'url': '$_teamUrl/$id/widgets/${w['id']}',
          'dashboard': {'eTag': '$eTag'},
        },
    ],
  };

  static Map<String, dynamic> _widget({
    required String id,
    required String name,
    required String contribution,
    required int row,
    required int column,
    int rowSpan = 1,
    int columnSpan = 1,
    Object? settings,
  }) {
    final typeId = contribution.split('.').last;
    return {
      'id': id,
      'name': name,
      'position': {'row': row, 'column': column},
      'size': {'rowSpan': rowSpan, 'columnSpan': columnSpan},
      'settings': switch (settings) {
        null => null,
        String() => settings,
        _ => jsonEncode(settings),
      },
      'settingsVersion': {'major': 1, 'minor': 0, 'patch': 0},
      'artifactId': '',
      'isEnabled': true,
      'contentUri': null,
      'contributionId': contribution,
      'typeId': typeId,
      'configurationContributionId': '${contribution}Configuration',
      'configurationContributionRelativeId': '${typeId}Configuration',
      'isNameConfigurable': true,
      'loadingImageUrl': null,
      'lightboxOptions': null,
      'allowedSizes': null,
      'areSettingsBlockedForUser': false,
    };
  }

  static String _wid(int n) =>
      '0d1e2f3a-4b5c-4d6e-8f70-81920a3b4c${n.toString().padLeft(2, '0')}';

  static Map<String, String> get _team => {
    'projectId': DemoWorld.projectId,
    'teamId': DemoWorld.teamId,
  };

  static const _requirements = {
    'identifier': 'BacklogCategory',
    'settings': 'Microsoft.RequirementCategory',
  };

  static const _storyPoints = {
    'identifier': 1,
    'settings': 'Microsoft.VSTS.Scheduling.StoryPoints',
  };

  static Map<String, dynamic> _queryTile(
    int n,
    DemoQuery q, {
    required int row,
    required int column,
  }) => _widget(
    id: _wid(n),
    name: q.name,
    contribution: '$_dashboards.QueryScalarWidget',
    row: row,
    column: column,
    settings: {
      'queryId': q.id,
      'queryName': q.name,
      'lastArtifactName': q.name,
      'colorRules': <Object>[],
    },
  );

  static Map<String, dynamic> _queryList(
    int n,
    DemoQuery q, {
    required int row,
    required int column,
  }) => _widget(
    id: _wid(n),
    name: q.name,
    contribution: '$_dashboards.WitViewWidget',
    row: row,
    column: column,
    rowSpan: 2,
    columnSpan: 2,
    settings: {
      'queryId': q.id,
      'queryName': q.name,
      'lastArtifactName': q.name,
      'columns': ['System.Id', 'System.Title', 'System.State'],
    },
  );

  static Map<String, dynamic> _markdown(
    int n,
    String name,
    String content, {
    required int row,
    required int column,
    int rowSpan = 1,
    int columnSpan = 2,
  }) => _widget(
    id: _wid(n),
    name: name,
    contribution: '$_dashboards.MarkdownWidget',
    row: row,
    column: column,
    rowSpan: rowSpan,
    columnSpan: columnSpan,
    settings: content,
  );

  static Map<String, dynamic> _cycleTime(
    int n,
    String name, {
    required int row,
    required int column,
    int days = 30,
    bool lead = false,
  }) => _widget(
    id: _wid(n),
    name: name,
    contribution: '$_analytics.${lead ? 'LeadTimeWidget' : 'CycleTimeWidget'}',
    row: row,
    column: column,
    rowSpan: 2,
    columnSpan: 2,
    settings: {
      ..._team,
      'workItemTypeFilter': _requirements,
      'swimlane': 'All',
      'timePeriodInDays': days,
      'fieldFilters': <Object>[],
    },
  );

  /// The team's release burnup (or burndown) from Sprint 9 to Sprint 16.
  static Map<String, dynamic> _release(
    int n,
    String name, {
    required int row,
    required int column,
    required bool burnup,
  }) {
    final first = DemoHistory.sprints.first;
    final last = DemoHistory.sprints.last;
    return _widget(
      id: _wid(n),
      name: name,
      contribution: '$_analytics.${burnup ? 'BurnupWidget' : 'BurndownWidget'}',
      row: row,
      column: column,
      rowSpan: 2,
      columnSpan: 2,
      settings: {
        'teams': [_team],
        'workItemTypeFilter': _requirements,
        'fieldFilters': <Object>[],
        'aggregation': burnup
            ? {'identifier': 0, 'settings': ''}
            : _storyPoints,
        'timePeriodConfiguration': {
          'startDate': DemoHistory.day(first.start),
          'samplingConfiguration': {
            'identifier': 0,
            'settings': {
              'endDate': DemoHistory.day(last.finish),
              'sampleInterval': 1,
              'lastDayOfWeek': 5,
            },
          },
        },
        'burndownTrendlineEnabled': !burnup,
        'totalScopeTrendlineEnabled': true,
        'completedWorkEnabled': burnup,
        'stackByWorkItemTypeEnabled': false,
        'showResolvedItemsAsCompletedEnabled': false,
        'includeBugsForRequirementCategory': true,
      },
    );
  }

  /// "Boardhop Overview": the dashboard the store screenshot opens on.
  ///
  /// Laid out on six web columns. A tablet packs it into a row of three
  /// charts, a row of tiles and cards, and a row of lists and charts; a
  /// phone stacks it in the same reading order, charts first.
  static Map<String, dynamic> overview() {
    final sprint = DemoWorld.currentSprint;
    return _dashboard(
      id: overviewId,
      name: 'Boardhop Overview',
      description: 'How the current sprint and the last six are going.',
      position: 1,
      eTag: 27,
      widgets: [
        _widget(
          id: _wid(1),
          name: 'Sprint burndown',
          contribution: '$_analytics.AnalyticsSprintBurndownWidget',
          row: 1,
          column: 1,
          rowSpan: 2,
          columnSpan: 2,
          settings: {
            'team': _team,
            'workItemTypeFilter': {
              'identifier': 'BacklogCategory',
              'settings': 'Microsoft.TaskCategory',
            },
            'aggregation': {'identifier': 0, 'settings': ''},
            'isLegacy': false,
            'isCustomized': false,
            'showNonWorkingDays': false,
            'totalScopeTrendlineEnabled': true,
          },
        ),
        _widget(
          id: _wid(2),
          name: 'Velocity',
          contribution: '$_analytics.VelocityWidget',
          row: 1,
          column: 3,
          rowSpan: 2,
          columnSpan: 2,
          settings: {
            ..._team,
            'numberOfIterations': 6,
            'aggregation': _storyPoints,
            'workItemTypeFilter': _requirements,
            'fieldFilters': <Object>[],
          },
        ),
        _widget(
          id: _wid(3),
          name: 'Cumulative flow',
          contribution: '$_analytics.CumulativeFlowDiagramWidget',
          row: 1,
          column: 5,
          rowSpan: 2,
          columnSpan: 2,
          settings: {
            ..._team,
            'backlogLevelName': DemoHistory.boardName,
            'boardName': DemoHistory.boardName,
            'swimlane': 'All',
            'numberOfDays': 30,
            'hideIncoming': false,
            'hideOutgoing': false,
          },
        ),
        _queryTile(4, DemoQueries.activeBugs, row: 3, column: 1),
        _queryTile(5, DemoQueries.inReview, row: 3, column: 2),
        _widget(
          id: _wid(6),
          name: '${sprint.name} overview',
          contribution: '$_dashboards.SprintOverviewWidget',
          row: 3,
          column: 3,
          columnSpan: 2,
          settings: {'showWorkItems': true},
        ),
        _markdown(
          7,
          'Sprint goal',
          '**${sprint.name}:** drag cards between split columns, capacity '
              'bars on the taskboard, and approving a waiting stage straight '
              'from a push.',
          row: 3,
          column: 5,
        ),
        _queryList(8, DemoQueries.priorityOne, row: 4, column: 1),
        _cycleTime(9, 'Cycle time', row: 4, column: 3),
        _release(10, 'Boardhop 1.0 burnup', row: 4, column: 5, burnup: true),
      ],
    );
  }

  static Map<String, dynamic> release() => _dashboard(
    id: releaseId,
    name: 'Release readiness',
    description: 'What stands between us and Boardhop 1.0 in the stores.',
    position: 2,
    eTag: 14,
    widgets: [
      _queryTile(21, DemoQueries.openForRelease, row: 1, column: 1),
      _queryTile(22, DemoQueries.priorityOne, row: 1, column: 2),
      _markdown(
        23,
        'Release checklist',
        '### Boardhop 1.0\n'
            '- Sign-in with Entra on iOS and Android: **done**\n'
            '- Offline boards and work items: **done**\n'
            '- Approvals from a push notification: in progress\n'
            '- Relay token rotation: in progress\n'
            '- TestFlight and Play closed testing sign-off\n',
        row: 1,
        column: 3,
        rowSpan: 2,
      ),
      _release(24, 'Scope burnup', row: 3, column: 1, burnup: true),
      _release(25, 'Points burndown', row: 3, column: 3, burnup: false),
      _queryList(26, DemoQueries.priorityOne, row: 5, column: 1),
      _cycleTime(27, 'Lead time', row: 5, column: 3, days: 60, lead: true),
    ],
  );

  static Map<String, dynamic> relay() => _dashboard(
    id: relayId,
    name: 'Relay health',
    description: 'Push delivery through the tenant relay and its hooks.',
    position: 3,
    eTag: 9,
    widgets: [
      _queryTile(31, DemoQueries.relayBugs, row: 1, column: 1),
      _queryTile(32, DemoQueries.relayWork, row: 1, column: 2),
      _markdown(
        33,
        'On call',
        '### Relay on call\n'
            'Pushes arrive through the tenant relay from the project\'s '
            'service hooks. When a phone stops getting them, check the '
            'hook subscriptions first, then the APNs and FCM credentials.\n',
        row: 1,
        column: 3,
        rowSpan: 2,
      ),
      _queryList(34, DemoQueries.relayWork, row: 3, column: 1),
      _cycleTime(35, 'Cycle time', row: 3, column: 3, days: 60),
    ],
  );

  /// The widget-type catalog, for naming kinds the app hides.
  static Map<String, dynamic> catalog() {
    Map<String, dynamic> type(
      String contribution,
      String name,
      bool analytics,
    ) => {
      'contributionId': contribution,
      'name': name,
      'description': name,
      'catalogIconUrl':
          '${DemoWorld.baseUrl}/_static/Widgets/CatalogIcons/'
          '${contribution.split('.').last}.png',
      'analyticsServiceRequired': analytics,
      'isVisibleFromCatalog': true,
      'defaultSettings': null,
    };
    return {
      'widgetTypes': [
        type('$_dashboards.QueryScalarWidget', 'Query Tile', false),
        type('$_dashboards.WitViewWidget', 'Query Results', false),
        type('$_dashboards.WitChartWidget', 'Chart for Work Items', false),
        type('$_dashboards.MarkdownWidget', 'Markdown', false),
        type('$_dashboards.SprintOverviewWidget', 'Sprint Overview', false),
        type('$_dashboards.IFrameWidget', 'Embedded Webpage', false),
        type(
          '$_analytics.AnalyticsSprintBurndownWidget',
          'Sprint Burndown',
          true,
        ),
        type('$_analytics.VelocityWidget', 'Velocity', true),
        type(
          '$_analytics.CumulativeFlowDiagramWidget',
          'Cumulative Flow Diagram (CFD)',
          true,
        ),
        type('$_analytics.CycleTimeWidget', 'Cycle Time', true),
        type('$_analytics.LeadTimeWidget', 'Lead Time', true),
        type('$_analytics.BurndownWidget', 'Burndown', true),
        type('$_analytics.BurnupWidget', 'Burnup', true),
      ],
      'uri': '${DemoWorld.projectUrl}/_apis/dashboard/widgettypes',
      'userId': DemoWorld.me.id,
    };
  }

  static Map<String, dynamic> favorites() => {
    'count': 1,
    'value': [
      {
        'id': '7e1d2c3b-4a59-4687-9a0b-1c2d3e4f5061',
        'artifactId': overviewId,
        'artifactType': 'Microsoft.TeamFoundation.Dashboards.Dashboard',
        'artifactName': 'Boardhop Overview',
        'artifactScope': {
          'id': DemoWorld.projectId,
          'type': 'Project',
          'name': DemoWorld.project,
        },
        'artifactIsDeleted': false,
        'creationDate': DemoWorld.iso(DemoWorld.daysAgo(40)),
        'owner': {'id': DemoWorld.me.id, 'displayName': DemoWorld.me.name},
      },
    ],
  };
}

/// One saved query under Shared Queries/Dashboards, evaluated against the
/// world whenever it runs.
class DemoQuery {
  const DemoQuery({
    required this.id,
    required this.name,
    required this.wiql,
    required this.matches,
  });

  final String id;
  final String name;
  final String wiql;
  final bool Function(DemoWorkItem item) matches;

  String get path => 'Shared Queries/Dashboards/$name';

  /// The query's rows in its order: priority, then id.
  List<DemoWorkItem> run() =>
      [
        for (final w in DemoWorld.workItems)
          if (matches(w)) w,
      ]..sort((a, b) {
        final p = a.priority.compareTo(b.priority);
        return p != 0 ? p : a.id.compareTo(b.id);
      });
}

abstract final class DemoQueries {
  static bool _open(DemoWorkItem w) =>
      DemoHistory.stateCategory(w.state) != 'Completed';

  static const _select =
      'SELECT [System.Id], [System.WorkItemType], [System.Title], '
      '[System.AssignedTo], [System.State], [System.Tags] FROM WorkItems ';
  static const _order =
      ' ORDER BY [Microsoft.VSTS.Common.Priority], [System.Id]';

  static final activeBugs = DemoQuery(
    id: 'e7a1b2c3-d4e5-4f60-8a71-b2c3d4e5f601',
    name: 'Active bugs',
    wiql:
        "${_select}WHERE [System.TeamProject] = @project AND "
        "[System.WorkItemType] = 'Bug' AND [System.State] IN ('New', 'Active')"
        '$_order',
    matches: (w) =>
        w.type == 'Bug' && (w.state == 'New' || w.state == 'Active'),
  );

  static final inReview = DemoQuery(
    id: 'e7a1b2c3-d4e5-4f60-8a71-b2c3d4e5f602',
    name: 'Ready for review',
    wiql:
        "${_select}WHERE [System.TeamProject] = @project AND "
        "[System.BoardColumn] = 'Review'$_order",
    matches: (w) => w.column == 'Review',
  );

  static final openForRelease = DemoQuery(
    id: 'e7a1b2c3-d4e5-4f60-8a71-b2c3d4e5f603',
    name: 'Open for 1.0',
    wiql:
        "${_select}WHERE [System.TeamProject] = @project AND "
        "[System.WorkItemType] IN GROUP 'Microsoft.RequirementCategory' AND "
        "[System.State] NOT IN ('Closed', 'Removed')$_order",
    matches: (w) => DemoHistory.isRequirement(w) && _open(w),
  );

  static final priorityOne = DemoQuery(
    id: 'e7a1b2c3-d4e5-4f60-8a71-b2c3d4e5f604',
    name: 'Priority 1 still open',
    wiql:
        "${_select}WHERE [System.TeamProject] = @project AND "
        "[System.WorkItemType] IN GROUP 'Microsoft.RequirementCategory' AND "
        '[Microsoft.VSTS.Common.Priority] = 1 AND '
        "[System.State] NOT IN ('Closed', 'Removed')$_order",
    matches: (w) => DemoHistory.isRequirement(w) && w.priority == 1 && _open(w),
  );

  static const _relayTags = {'relay', 'push', 'extension'};

  static bool _relay(DemoWorkItem w) => w.tags.any(_relayTags.contains);

  static final relayBugs = DemoQuery(
    id: 'e7a1b2c3-d4e5-4f60-8a71-b2c3d4e5f605',
    name: 'Relay bugs',
    wiql:
        "${_select}WHERE [System.TeamProject] = @project AND "
        "[System.WorkItemType] = 'Bug' AND ([System.Tags] CONTAINS 'relay' "
        "OR [System.Tags] CONTAINS 'push') AND "
        "[System.State] NOT IN ('Closed', 'Removed')$_order",
    matches: (w) => w.type == 'Bug' && _relay(w) && _open(w),
  );

  static final relayWork = DemoQuery(
    id: 'e7a1b2c3-d4e5-4f60-8a71-b2c3d4e5f606',
    name: 'Relay and push work',
    wiql:
        "${_select}WHERE [System.TeamProject] = @project AND "
        "([System.Tags] CONTAINS 'relay' OR [System.Tags] CONTAINS 'push' OR "
        "[System.Tags] CONTAINS 'extension') AND "
        "[System.State] NOT IN ('Closed', 'Done', 'Removed')$_order",
    matches: (w) => _relay(w) && _open(w),
  );

  static final all = [
    activeBugs,
    inReview,
    openForRelease,
    priorityOne,
    relayBugs,
    relayWork,
  ];

  static DemoQuery? byId(String id) {
    for (final q in all) {
      if (q.id.toLowerCase() == id.toLowerCase()) return q;
    }
    return null;
  }

  static const _columns = [
    ('System.Id', 'ID'),
    ('System.WorkItemType', 'Work Item Type'),
    ('System.Title', 'Title'),
    ('System.AssignedTo', 'Assigned To'),
    ('System.State', 'State'),
    ('System.Tags', 'Tags'),
  ];

  static List<Map<String, dynamic>> _columnRefs() => [
    for (final (ref, name) in _columns)
      {
        'referenceName': ref,
        'name': name,
        'url': '${DemoWorld.baseUrl}/_apis/wit/fields/$ref',
      },
  ];

  /// `GET wit/queries/{id}?$expand=wiql`.
  static Map<String, dynamic> definition(DemoQuery q) {
    final url = '${DemoWorld.projectUrl}/_apis/wit/queries/${q.id}';
    return {
      'id': q.id,
      'name': q.name,
      'path': q.path,
      'createdBy': DemoWorld.sofia.identity(),
      'createdDate': DemoWorld.iso(DemoWorld.daysAgo(96)),
      'lastModifiedBy': DemoWorld.kelly.identity(),
      'lastModifiedDate': DemoWorld.iso(DemoWorld.daysAgo(12)),
      'isPublic': true,
      'isFolder': false,
      'hasChildren': false,
      'queryType': 'flat',
      'wiql': q.wiql,
      'columns': _columnRefs(),
      'sortColumns': [
        {
          'field': {
            'referenceName': 'Microsoft.VSTS.Common.Priority',
            'name': 'Priority',
            'url':
                '${DemoWorld.baseUrl}/_apis/wit/fields/Microsoft.VSTS.Common.Priority',
          },
          'descending': false,
        },
      ],
      '_links': {
        'self': {'href': url},
        'html': {
          'href':
              '${DemoWorld.baseUrl}/${DemoWorld.project}/_queries/query/${q.id}',
        },
        'wiql': {'href': '${DemoWorld.projectUrl}/_apis/wit/wiql/${q.id}'},
      },
      'url': url,
    };
  }

  /// `GET wit/wiql/{id}`: the ids, in query order.
  static Map<String, dynamic> result(DemoQuery q, {int? top}) {
    final rows = q.run();
    return {
      'queryType': 'flat',
      'queryResultType': 'workItem',
      'asOf': DemoWorld.iso(DemoWorld.now),
      'columns': _columnRefs(),
      'sortColumns': [
        {
          'field': {
            'referenceName': 'Microsoft.VSTS.Common.Priority',
            'name': 'Priority',
            'url':
                '${DemoWorld.baseUrl}/_apis/wit/fields/Microsoft.VSTS.Common.Priority',
          },
          'descending': false,
        },
      ],
      'workItems': [
        for (final w in top == null ? rows : rows.take(top))
          {
            'id': w.id,
            'url': '${DemoWorld.baseUrl}/_apis/wit/workItems/${w.id}',
          },
      ],
    };
  }
}
