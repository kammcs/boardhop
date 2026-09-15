import 'dart:math' as math;

import '../../../data/models/analytics.dart';
import '../../../data/models/sprint.dart';
import '../../dashboards/charts/chart_payload.dart';
import '../../dashboards/charts/chart_sources.dart';
import '../../dashboards/team_overview.dart';

/// Canned chart data for the dashboard probe (phase D-C).
///
/// The scratch project cannot produce most of these shapes — it has one
/// dated sprint, a handful of work items and one pipeline — so the charts
/// themselves are checked here: six sprints of velocity, a month of
/// cumulative flow, sixty days of completed items. Everything is invented
/// and deterministic (`Random(7)`); no client data goes anywhere near the
/// probe, and nothing here touches Azure DevOps.
abstract final class DashboardProbeData {
  static final _rng = math.Random(7);

  static DateTime get _today => DateTime.utc(2026, 9, 15);

  static List<BurndownDay> _snapshotDays(int days) {
    var remaining = 34;
    var done = 0;
    return [
      for (var i = 0; i < days; i++)
        () {
          final closed = i == 0 ? 0 : _rng.nextInt(4);
          remaining = math.max(0, remaining - closed + (i % 7 == 3 ? 2 : 0));
          done += closed;
          return BurndownDay(
            date: _today.subtract(Duration(days: days - 1 - i)),
            remaining: remaining,
            done: done,
            points: remaining * 1.5,
          );
        }(),
    ];
  }

  /// A fortnight of sprint burndown.
  ///
  /// Every chart is a `static final` rather than a getter: the generator
  /// advances one seeded `Random`, so a getter would answer different
  /// numbers each time the probe rebuilt and the chart would change under
  /// the scroll.
  static final BurndownPayload burndown = burndownPayload(
    title: 'Sprint burndown',
    days: _snapshotDays(14),
    burnup: false,
    finish: _today.add(const Duration(days: 4)),
    summary: 'Sprint 24',
  );

  /// The same rows read the other way: work completed, climbing.
  static final BurndownPayload burnup = burndownPayload(
    title: 'Burnup',
    days: _snapshotDays(30),
    burnup: true,
    finish: _today.add(const Duration(days: 10)),
    summary: 'User Story, Bug',
  );

  /// Six sprints, which no scratch team has.
  static final VelocityPayload velocity = VelocityPayload(
    title: 'Velocity',
    iterations: [
      for (var i = 0; i < 6; i++)
        VelocityIteration(
          iteration: AnalyticsIteration(
            sk: 'it-$i',
            name: 'Sprint ${24 - i}',
            startDate: _today.subtract(Duration(days: 14 * (i + 1))),
            endDate: _today.subtract(Duration(days: 14 * i)),
            isEnded: i > 0,
          ),
          planned: 12 + _rng.nextInt(6),
          plannedPoints: 24 + _rng.nextInt(10).toDouble(),
          completed: 8 + _rng.nextInt(5),
          completedPoints: 18 + _rng.nextInt(8).toDouble(),
          completedLate: _rng.nextInt(3),
          completedLatePoints: _rng.nextInt(5).toDouble(),
          incomplete: _rng.nextInt(4),
          incompletePoints: _rng.nextInt(6).toDouble(),
        ),
    ],
  );

  /// Thirty days of cumulative flow over five columns.
  static final CumulativeFlowPayload cumulativeFlow = _cumulativeFlow();

  static CumulativeFlowPayload _cumulativeFlow() {
    const columns = ['New', 'Approved', 'Committed', 'In test', 'Done'];
    var done = 6;
    return CumulativeFlowPayload(
      title: 'Cumulative flow',
      days: 30,
      boardName: 'Stories',
      flow: CumulativeFlow(
        columns: columns,
        days: [
          for (var i = 0; i < 30; i++)
            () {
              done += _rng.nextInt(3);
              return CumulativeFlowDay(
                date: _today.subtract(Duration(days: 29 - i)),
                counts: {
                  'New': 5 + _rng.nextInt(4),
                  'Approved': 3 + _rng.nextInt(3),
                  'Committed': 2 + _rng.nextInt(4),
                  'In test': 1 + _rng.nextInt(3),
                  'Done': done,
                },
              );
            }(),
        ],
      ),
    );
  }

  /// Sixty days of completed items, which is what the rolling average
  /// needs to be visible at all.
  static final CycleTimePayload cycleTime = CycleTimePayload(
    title: 'Cycle and lead time',
    days: 60,
    showBoth: true,
    data: CycleLeadTime(
      items: [
        for (var i = 0; i < 46; i++)
          () {
            final cycle = 1 + _rng.nextInt(12) + _rng.nextDouble();
            return CycleLeadItem(
              workItemId: 15600 + i,
              workItemType: i.isEven ? 'User Story' : 'Bug',
              state: 'Closed',
              cycleTimeDays: cycle,
              leadTimeDays: cycle + 2 + _rng.nextInt(9),
              completedDate: _today.subtract(Duration(days: 59 - i)),
            );
          }(),
      ],
    ),
  );

  static final WorkByStatePayload workByState = WorkByStatePayload(
    title: 'Work by state',
    counts: const [
      WorkStateCount(
        workItemType: 'User Story',
        state: 'New',
        stateCategory: 'Proposed',
        count: 12,
      ),
      WorkStateCount(
        workItemType: 'User Story',
        state: 'Active',
        stateCategory: 'InProgress',
        count: 7,
      ),
      WorkStateCount(
        workItemType: 'User Story',
        state: 'Closed',
        stateCategory: 'Completed',
        count: 21,
      ),
      WorkStateCount(
        workItemType: 'Bug',
        state: 'New',
        stateCategory: 'Proposed',
        count: 5,
      ),
      WorkStateCount(
        workItemType: 'Bug',
        state: 'Resolved',
        stateCategory: 'Resolved',
        count: 3,
      ),
      WorkStateCount(
        workItemType: 'Task',
        state: 'To Do',
        stateCategory: 'Proposed',
        count: 9,
      ),
      WorkStateCount(
        workItemType: 'Task',
        state: 'Doing',
        stateCategory: 'InProgress',
        count: 4,
      ),
    ],
  );

  static final PipelineOutcomesPayload pipelineOutcomes = _pipelineOutcomes();

  static PipelineOutcomesPayload _pipelineOutcomes() {
    final runs = [
      for (var i = 0; i < 20; i++)
        AnalyticsPipelineRun(
          runId: 900 + i,
          runNumber: '20260915.${20 - i}',
          outcome: i % 7 == 2
              ? 'Failed'
              : i % 11 == 5
              ? 'Canceled'
              : 'Succeed',
          completedDate: _today.subtract(Duration(days: i * 2)),
          durationSeconds: 90 + _rng.nextInt(240).toDouble(),
        ),
    ];
    return PipelineOutcomesPayload(
      title: 'Pipeline pass rate',
      days: 90,
      pipelineName: 'boardhop-scratch',
      pipelineId: 139,
      outcomes: PipelineOutcomes(
        total: 42,
        succeeded: 35,
        failed: 5,
        partial: 1,
        canceled: 1,
        runs: runs,
      ),
    );
  }

  /// The canned chart for a Team overview built-in kind, so the probe can
  /// draw the six cards without an account.
  static ChartPayload forBuiltIn(String builtInKind) => switch (builtInKind) {
    TeamOverview.sprintBurndown => burndown,
    TeamOverview.workByState => workByState,
    TeamOverview.cumulativeFlow => cumulativeFlow,
    TeamOverview.cycleLeadTime => cycleTime,
    TeamOverview.velocity => velocity,
    _ => pipelineOutcomes,
  };

  /// Every canned chart, for the probe's own gallery.
  static final List<ChartPayload> all = [
    burndown,
    burnup,
    velocity,
    cumulativeFlow,
    cycleTime,
    workByState,
    pipelineOutcomes,
  ];
}
