import 'dart:convert';

import 'package:boardhop/data/models/dashboard.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixtures are the scratch project's own widgets (spike w36 wrote them and
/// read them back) and the redacted shapes from s58: every GUID that is not
/// the scratch project's is a made-up one.
const scratchProject = '98720989-0195-48cb-ae2e-0e58ec1bb9a9';
const scratchTeam = '8c08e1e1-7afd-411e-b414-4f9e1d14d8d6';
const scratchDashboard = '985ff75c-bdf6-4b2d-a2b0-0ef63431e6ec';
const scratchQuery = '8c808ce9-51d6-4cdf-a17a-17a70930d2f0';

const dashboards = 'ms.vss-dashboards-web.Microsoft.VisualStudioOnline'
    '.Dashboards';
const myWork = 'ms.vss-mywork-web.Microsoft.VisualStudioOnline.MyWork';

Map<String, dynamic> widgetJson({
  required String contributionId,
  String id = 'w1',
  String name = 'Widget',
  int row = 1,
  int column = 1,
  int rowSpan = 1,
  int columnSpan = 1,
  Object? settings,
  bool isEnabled = true,
}) => {
  'id': id,
  'name': name,
  'contributionId': contributionId,
  'position': {'row': row, 'column': column},
  'size': {'rowSpan': rowSpan, 'columnSpan': columnSpan},
  'settingsVersion': {'major': 1, 'minor': 0, 'patch': 0},
  'isEnabled': isEnabled,
  if (settings != null)
    'settings': settings is String ? settings : jsonEncode(settings),
};

void main() {
  group('WidgetKind from the contributionId suffix', () {
    test('the kinds decision D3 ships', () {
      expect(
        WidgetKind.fromContributionId('$dashboards.QueryScalarWidget'),
        WidgetKind.queryTile,
      );
      // Query Results and the legacy PR widget live under a different area.
      expect(
        WidgetKind.fromContributionId('$myWork.WitViewWidget'),
        WidgetKind.queryResults,
      );
      expect(
        WidgetKind.fromContributionId('$myWork.PullRequestWidget'),
        WidgetKind.pullRequests,
      );
      expect(
        WidgetKind.fromContributionId('$dashboards.PullrequestsWidget'),
        WidgetKind.pullRequests,
      );
      expect(
        WidgetKind.fromContributionId('$dashboards.WitChartWidget'),
        WidgetKind.workItemChart,
      );
      expect(
        WidgetKind.fromContributionId('$dashboards.BuildHistogramWidget'),
        WidgetKind.buildHistory,
      );
      expect(
        WidgetKind.fromContributionId('$dashboards.CodeScalarWidget'),
        WidgetKind.codeTile,
      );
      expect(
        WidgetKind.fromContributionId('$dashboards.CumulativeFlowDiagramWidget'),
        WidgetKind.cumulativeFlow,
      );
    });

    test('the two sprint burndowns are different kinds', () {
      expect(
        WidgetKind.fromContributionId(
          '$dashboards.AnalyticsSprintBurndownWidget',
        ),
        WidgetKind.sprintBurndown,
      );
      expect(
        WidgetKind.fromContributionId('$dashboards.SprintBurndownWidget'),
        WidgetKind.sprintBurndownLegacy,
      );
    });

    test('the hidden kinds still have names of their own (D10)', () {
      expect(
        WidgetKind.fromContributionId('$dashboards.IFrameWidget'),
        WidgetKind.embeddedWebpage,
      );
      expect(
        WidgetKind.fromContributionId(
          'ms.vss-releaseManagement-web.rm-deployment-status-widget',
        ),
        WidgetKind.deploymentStatus,
      );
      expect(
        WidgetKind.fromContributionId(
          'ms.vss-releaseManagement-web.release-definition-summary-widget',
        ),
        WidgetKind.releaseOverview,
      );
      expect(
        WidgetKind.fromContributionId(
          'ms.vss-test-web.Microsoft.VisualStudioTeamServices.TestManagement'
          '.AnalyticsTestTrendWidget',
        ),
        WidgetKind.testResultsTrend,
      );
      expect(
        WidgetKind.fromContributionId('$dashboards.SprintCapacityWidget'),
        WidgetKind.sprintCapacity,
      );
    });

    test('a widget from another publisher is a Marketplace widget', () {
      expect(
        WidgetKind.fromContributionId('acme.some-extension.CoolWidget'),
        WidgetKind.marketplace,
      );
      // An unrecognised Microsoft widget is unknown, not Marketplace.
      expect(
        WidgetKind.fromContributionId('$dashboards.SomethingNewWidget'),
        WidgetKind.unknown,
      );
      expect(WidgetKind.fromContributionId(null), WidgetKind.unknown);
      expect(WidgetKind.fromContributionId(''), WidgetKind.unknown);
    });
  });

  group('DashboardWidget', () {
    test('reads the 1-based position and the span', () {
      final w = DashboardWidget.fromJson(
        widgetJson(
          contributionId: '$dashboards.BurndownWidget',
          row: 3,
          column: 5,
          rowSpan: 3,
          columnSpan: 4,
        ),
      );
      expect(w.row, 3);
      expect(w.column, 5);
      expect(w.rowSpan, 3);
      expect(w.columnSpan, 4);
      expect(w.settingsVersion, '1.0.0');
      expect(w.kind, WidgetKind.burndown);
    });

    test('a widget with no position at all is top-left, 1x1', () {
      final w = DashboardWidget.fromJson({
        'id': 'w',
        'contributionId': '$dashboards.WorkLinksWidget',
      });
      expect((w.row, w.column, w.rowSpan, w.columnSpan), (1, 1, 1, 1));
      expect(w.settingsJson, isNull);
    });

    test('settingsJson is null when the settings are not a JSON object', () {
      // The Markdown widget's settings are the markdown itself (w36 wrote
      // plain text and read it back byte for byte).
      final markdown = DashboardWidget.fromJson(
        widgetJson(
          contributionId: '$dashboards.MarkdownWidget',
          settings: '## Boardhop scratch\n\n- a bullet\n',
        ),
      );
      expect(markdown.settingsJson, isNull);
      expect(markdown.settings, startsWith('## Boardhop'));

      // A JSON array is not an object either.
      final array = DashboardWidget.fromJson(
        widgetJson(
          contributionId: '$dashboards.WorkLinksWidget',
          settings: '[1, 2]',
        ),
      );
      expect(array.settingsJson, isNull);
    });

    test('round-trips through JSON for the cache', () {
      final json = widgetJson(
        contributionId: '$dashboards.QueryScalarWidget',
        settings: {'queryId': scratchQuery},
        row: 2,
        columnSpan: 3,
      );
      final again = DashboardWidget.fromJson(
        DashboardWidget.fromJson(json).toJson(),
      );
      expect(again.settingsJson?['queryId'], scratchQuery);
      expect(again.row, 2);
      expect(again.columnSpan, 3);
      expect(again.settingsVersion, '1.0.0');
    });
  });

  group('Dashboard', () {
    final json = {
      'id': scratchDashboard,
      'name': 'Overview',
      'dashboardScope': 'project_Team',
      'groupId': scratchTeam,
      'ownerId': scratchTeam,
      'position': 1,
      'refreshInterval': 0,
      'eTag': '13',
      'widgets': [
        widgetJson(
          id: 'b',
          contributionId: '$dashboards.PullrequestsWidget',
          row: 2,
          column: 1,
        ),
        widgetJson(
          id: 'a',
          contributionId: '$dashboards.QueryScalarWidget',
          row: 1,
          column: 3,
        ),
        widgetJson(
          id: 'c',
          contributionId: '$dashboards.WorkLinksWidget',
          row: 1,
          column: 1,
        ),
        widgetJson(
          id: 'off',
          contributionId: '$dashboards.TeamMembersWidget',
          row: 1,
          column: 5,
          isEnabled: false,
        ),
      ],
    };

    test('parses the scratch Overview and orders widgets for reading', () {
      final d = Dashboard.fromJson(json);
      expect(d.id, scratchDashboard);
      expect(d.name, 'Overview');
      expect(d.scope, DashboardScope.team);
      // groupId is the team, and it is what the GET by id needs.
      expect(d.teamId, scratchTeam);
      expect(d.eTag, '13');
      expect(d.widgets.length, 4);
      // Reading order is row, then column — and a disabled widget is gone.
      expect(d.orderedWidgets.map((w) => w.id), ['c', 'a', 'b']);
    });

    test('an eTag the service sends as a number is still a string', () {
      final d = Dashboard.fromJson({...json, 'eTag': 13});
      expect(d.eTag, '13');
    });

    test('summary keeps the list fields and counts the widgets', () {
      final summary = Dashboard.fromJson(json).summary;
      expect(summary.id, scratchDashboard);
      expect(summary.teamId, scratchTeam);
      expect(summary.widgetCount, 4);
    });

    test('round-trips through JSON', () {
      final again = Dashboard.fromJson(Dashboard.fromJson(json).toJson());
      expect(again.widgets.length, 4);
      expect(again.teamId, scratchTeam);
      expect(again.scope, DashboardScope.team);
    });

    test('an unknown scope does not throw', () {
      final d = Dashboard.fromJson({...json, 'dashboardScope': 'something'});
      expect(d.scope, DashboardScope.unknown);
    });
  });

  group('settings parsers (w36 readback and the s58 shapes)', () {
    Object? parse(String contributionId, Object? settings) =>
        parseWidgetSettings(
          DashboardWidget.fromJson(
            widgetJson(contributionId: contributionId, settings: settings),
          ),
        );

    test('Query Tile', () {
      final s =
          parse('$dashboards.QueryScalarWidget', {
                'colorRules': <Object>[],
                'defaultBackgroundColor': '#007acc',
                'lastArtifactName': 'Boardhop dashboard spike',
                'queryId': scratchQuery,
                'queryName': 'Boardhop dashboard spike',
              })
              as QueryTileSettings?;
      expect(s, isNotNull);
      expect(s!.queryId, scratchQuery);
      expect(s.label, 'Boardhop dashboard spike');
      expect(s.defaultBackgroundColor, '#007acc');
      expect(s.colorRules, isEmpty);
    });

    test('Query Tile without a query id is unreadable → hidden', () {
      expect(parse('$dashboards.QueryScalarWidget', {'queryName': 'x'}), isNull);
      expect(parse('$dashboards.QueryScalarWidget', null), isNull);
    });

    test('Query Results', () {
      final s =
          parse('$myWork.WitViewWidget', {
                'lastArtifactName': 'Boardhop dashboard spike',
                'queryId': scratchQuery,
                'queryName': 'Boardhop dashboard spike',
              })
              as QueryResultsSettings?;
      expect(s!.queryId, scratchQuery);
      expect(s.label, 'Boardhop dashboard spike');
      expect(s.columns, isEmpty);
    });

    test('Chart for Work Items carries a chart id and nothing else', () {
      final s =
          parse('$dashboards.WitChartWidget', {
                'chartId': 'c728c6dc-e606-4d38-88a2-066f9983af3c',
              })
              as WitChartSettings?;
      expect(s!.chartId, 'c728c6dc-e606-4d38-88a2-066f9983af3c');
      expect(parse('$dashboards.WitChartWidget', <String, Object>{}), isNull);
    });

    test('Burndown, from the client dashboard shape (s58, redacted)', () {
      final s =
          parse('$dashboards.BurndownWidget', {
                'aggregation': {
                  'identifier': 1,
                  'settings': 'Microsoft.VSTS.Scheduling.StoryPoints',
                },
                'burndownTrendlineEnabled': true,
                'completedWorkEnabled': true,
                'fieldFilters': [
                  {
                    'fieldName': 'System.IterationPath',
                    'queryOperation': '=',
                    'queryValue': 'Project\\Iteration 1',
                  },
                ],
                'includeBugsForRequirementCategory': false,
                'showResolvedItemsAsCompletedEnabled': true,
                'stackByWorkItemTypeEnabled': true,
                'teams': [
                  {
                    'projectId': '11111111-1111-1111-1111-111111111111',
                    'teamId': '22222222-2222-2222-2222-222222222222',
                  },
                ],
                'timePeriodConfiguration': {
                  'samplingConfiguration': {
                    'identifier': 0,
                    'settings': {
                      'endDate': '2024-10-07',
                      'lastDayOfWeek': 5,
                      'sampleInterval': 0,
                    },
                  },
                  'startDate': '2024-09-23',
                },
                'totalScopeTrendlineEnabled': true,
                'workItemTypeFilter': {
                  'identifier': 'BacklogCategory',
                  'settings': 'Microsoft.RequirementCategory',
                },
              })
              as BurndownSettings?;
      expect(s, isNotNull);
      expect(s!.team?.teamId, '22222222-2222-2222-2222-222222222222');
      expect(s.aggregation?.isSum, isTrue);
      expect(s.aggregation?.field, 'Microsoft.VSTS.Scheduling.StoryPoints');
      expect(s.workItemTypeFilter?.isBacklogCategory, isTrue);
      expect(s.workItemTypeFilter?.settings, 'Microsoft.RequirementCategory');
      expect(s.fieldFilters.single.fieldName, 'System.IterationPath');
      expect(s.startDate, DateTime.utc(2024, 9, 23));
      // The end date hides inside the sampling settings.
      expect(s.endDate, DateTime.utc(2024, 10, 7));
      expect(s.byIteration, isFalse);
      expect(s.sampleInterval, 0);
      expect(s.burndownTrendlineEnabled, isTrue);
    });

    test('Burndown with no team is unreadable → hidden', () {
      expect(
        parse('$dashboards.BurndownWidget', {'teams': <Object>[]}),
        isNull,
      );
    });

    test('a type filter that names types lists them', () {
      final filter = WidgetTypeFilter.parse({
        'identifier': 'WorkItemType',
        'settings': 'User Story,Bug',
      });
      expect(filter!.isBacklogCategory, isFalse);
      expect(filter.workItemTypes, ['User Story', 'Bug']);
    });

    test('Sprint Burndown (s58, redacted)', () {
      final s =
          parse('$dashboards.SprintBurndownWidget', {
                'aggregation': {
                  'identifier': 1,
                  'settings': 'Microsoft.VSTS.Scheduling.StoryPoints',
                },
                'completedWorkEnabled': false,
                'isCustomized': true,
                'isLegacy': false,
                'iterationId': 'abcdefghijklmnopq',
                'iterationPath': 'Project\\Iteration 1',
                'showNonWorkingDays': true,
                'team': {
                  'projectId': '11111111-1111-1111-1111-111111111111',
                  'teamId': '22222222-2222-2222-2222-222222222222',
                },
                'timePeriodConfiguration': {
                  'endDate': '2024-09-23',
                  'startDate': '2024-09-10',
                },
                'workItemTypeFilter': {
                  'identifier': 'BacklogCategory',
                  'settings': 'Microsoft.RequirementCategory',
                },
              })
              as SprintBurndownSettings?;
      expect(s!.iterationId, 'abcdefghijklmnopq');
      expect(s.iterationPath, 'Project\\Iteration 1');
      expect(s.startDate, DateTime.utc(2024, 9, 10));
      expect(s.endDate, DateTime.utc(2024, 9, 23));
      expect(s.isCustomized, isTrue);
      expect(s.isLegacy, isFalse);
      expect(s.team?.teamId, '22222222-2222-2222-2222-222222222222');
    });

    test('Sprint Burndown with neither team nor iteration is hidden', () {
      expect(
        parse('$dashboards.SprintBurndownWidget', {'isLegacy': true}),
        isNull,
      );
    });

    test('Velocity: null settings mean the defaults, not "hide me"', () {
      final none = parse('$dashboards.VelocityWidget', null) as VelocitySettings;
      expect(none, VelocitySettings.defaults);
      expect(none.iterations, 6);

      final configured =
          parse('$dashboards.VelocityWidget', {
                'aggregation': {
                  'identifier': 1,
                  'settings': 'Microsoft.VSTS.Scheduling.StoryPoints',
                },
                'fieldFilters': <Object>[],
                'numberOfIterations': 6,
                'projectId': scratchProject,
                'teamId': scratchTeam,
                'teams': [
                  {'projectId': scratchProject, 'teamId': scratchTeam},
                ],
                'workItemTypeFilter': {
                  'identifier': 'BacklogCategory',
                  'settings': 'Microsoft.RequirementCategory',
                },
              })
              as VelocitySettings;
      expect(configured.team?.teamId, scratchTeam);
      expect(configured.iterations, 6);
      expect(configured.aggregation?.isSum, isTrue);
    });

    test('Cumulative Flow Diagram (w36)', () {
      final s =
          parse('$dashboards.CumulativeFlowDiagramWidget', {
                'backlogLevelName': 'Stories',
                'boardName': 'Stories',
                'hideIncoming': false,
                'hideOutgoing': false,
                'numberOfDays': 30,
                'projectId': scratchProject,
                'swimlane': 'All',
                'teamId': scratchTeam,
              })
              as CfdSettings?;
      expect(s!.board, 'Stories');
      expect(s.days, 30);
      expect(s.team?.teamId, scratchTeam);
      expect(s.swimlane, 'All');
    });

    test('a CFD with no board name falls back to the backlog level', () {
      final s =
          parse('$dashboards.CumulativeFlowDiagramWidget', {
                'backlogLevelName': 'Stories',
                'teamId': scratchTeam,
              })
              as CfdSettings?;
      expect(s!.board, 'Stories');
      expect(s.days, 30);
      // Neither name at all: unreadable.
      expect(
        parse('$dashboards.CumulativeFlowDiagramWidget', {
          'teamId': scratchTeam,
        }),
        isNull,
      );
    });

    test('Cycle Time and Lead Time share one shape (w36)', () {
      for (final id in ['CycleTimeWidget', 'LeadTimeWidget']) {
        final s =
            parse('$dashboards.$id', {
                  'fieldFilters': <Object>[],
                  'projectId': scratchProject,
                  'teamId': scratchTeam,
                  'timePeriodInDays': 30,
                  'workItemTypeFilter': {
                    'identifier': 'BacklogCategory',
                    'settings': 'Microsoft.RequirementCategory',
                  },
                })
                as CycleTimeSettings?;
        expect(s!.team?.teamId, scratchTeam, reason: id);
        expect(s.days, 30, reason: id);
      }
      expect(parse('$dashboards.CycleTimeWidget', {'days': 5}), isNull);
    });

    test('Build History: the definition id is a string, or comes off the uri', () {
      final s =
          parse('$dashboards.BuildHistogramWidget', {
                'buildDefinition': '139',
                'defaultBranch': 'refs/heads/main',
                'uri': 'vstfs:///Build/Definition/139',
              })
              as BuildHistorySettings?;
      expect(s!.definitionId, 139);
      expect(s.defaultBranch, 'refs/heads/main');

      final fromUri =
          parse('$dashboards.BuildHistogramWidget', {
                'uri': 'vstfs:///Build/Definition/139',
              })
              as BuildHistorySettings?;
      expect(fromUri!.definitionId, 139);
      expect(parse('$dashboards.BuildHistogramWidget', {'uri': ''}), isNull);
    });

    test('Code Tile (w36)', () {
      final s =
          parse('$dashboards.CodeScalarWidget', {
                'branchName': 'main',
                'path': '/',
                'projectId': scratchProject,
                'repositoryId': '4c06881a-4e20-49c8-88c4-a21323fe04b5',
                'repositoryName': 'DevOps Mobile App',
              })
              as CodeTileSettings?;
      expect(s!.repositoryId, '4c06881a-4e20-49c8-88c4-a21323fe04b5');
      expect(s.branchName, 'main');
      expect(parse('$dashboards.CodeScalarWidget', {'path': '/'}), isNull);
    });

    test('Markdown: the settings string is the markdown (w36)', () {
      final s =
          parse(
                '$dashboards.MarkdownWidget',
                '## Boardhop scratch\n\n- a bullet\n',
              )
              as MarkdownSettings?;
      expect(s!.content, startsWith('## Boardhop scratch'));
      expect(s.isFile, isFalse);
    });

    test('Markdown also accepts the documented JSON wrapper', () {
      final inline =
          parse('$dashboards.MarkdownWidget', {'content': '# Hi'})
              as MarkdownSettings?;
      expect(inline!.content, '# Hi');

      final file =
          parse('$dashboards.MarkdownWidget', {
                'path': '/README.md',
                'repositoryId': '4c06881a-4e20-49c8-88c4-a21323fe04b5',
                'branch': 'refs/heads/main',
              })
              as MarkdownSettings?;
      expect(file!.isFile, isTrue);
      expect(file.path, '/README.md');
    });

    test('an empty Markdown widget is hidden', () {
      expect(parse('$dashboards.MarkdownWidget', '   '), isNull);
      expect(parse('$dashboards.MarkdownWidget', {'content': ''}), isNull);
    });

    test('Sprint Overview (w36)', () {
      final s =
          parse('$dashboards.SprintOverviewWidget', {'showWorkItems': true})
              as SprintOverviewSettings;
      expect(s.showWorkItems, isTrue);
      // No settings at all still means "the current sprint".
      expect(
        parse('$dashboards.SprintOverviewWidget', null),
        SprintOverviewSettings.defaults,
      );
    });

    test('the settings-less kinds parse to null and are still rendered', () {
      // These four carry `settings: null` on every dashboard seen; the card
      // needs no settings, so "no typed settings" is not "hide it".
      for (final id in [
        'AssignedToMeWidget',
        'PullrequestsWidget',
        'TeamMembersWidget',
        'WorkLinksWidget',
      ]) {
        final widget = DashboardWidget.fromJson(
          widgetJson(contributionId: '$dashboards.$id'),
        );
        expect(parseWidgetSettings(widget), isNull, reason: id);
        expect(widget.kind, isNot(WidgetKind.unknown), reason: id);
      }
    });

    test('a shape from a future service version does not throw', () {
      expect(
        () => parse('$dashboards.BurndownWidget', {
          'teams': [
            {'teamId': scratchTeam},
          ],
          'aggregation': 'sum-of-something',
          'timePeriodConfiguration': 'last 30 days',
          'fieldFilters': 'none',
        }),
        returnsNormally,
      );
    });
  });

  group('DashboardWidgetType', () {
    test('parses a catalog entry', () {
      final t = DashboardWidgetType.fromJson({
        'contributionId': '$dashboards.CumulativeFlowDiagramWidget',
        'name': 'Cumulative Flow Diagram (CFD)',
        'description': 'Shows the cumulative flow',
        'analyticsServiceRequired': true,
        'isVisibleFromCatalog': true,
      });
      expect(t.name, 'Cumulative Flow Diagram (CFD)');
      expect(t.analyticsServiceRequired, isTrue);
      expect(
        DashboardWidgetType.fromJson(t.toJson()).contributionId,
        t.contributionId,
      );
    });
  });
}
