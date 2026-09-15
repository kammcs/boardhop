import '../../../data/models/work_item.dart';
import '../../../data/models/work_item_form.dart';
import '../../../data/models/sprint.dart';
import '../../sprints/widgets/task_card_sheet.dart';
import '../../work_items/widgets/work_item_visuals.dart';

/// Canned sprint for the widget probe. No client data: the shape copies the
/// scratch project ("DevOps Mobile App", Iteration 1, a customized taskboard
/// of To Do / In Progress / Verify / Done), the titles come from a word bank
/// and the people are initials.
///
/// Remaining Work is filled in here even though no real team fills it
/// (research/18 §1) — the probe has to show what the rollups look like when
/// someone does.
class SprintProbeData {
  SprintProbeData._({
    required this.columns,
    required this.rows,
    required this.visuals,
    required this.iterations,
    required this.days,
  });

  final List<TaskboardColumn> columns;

  /// Unparented first, as the web pins it.
  final List<SprintRow> rows;
  final WorkItemVisuals visuals;
  final List<TeamIteration> iterations;
  final List<BurndownDay> days;

  static const _people = ['Kim Kaur', 'Ada Moss', 'Joel Reyes', 'Tia Sundar'];

  static WorkItem _item({
    required int id,
    required String type,
    required String title,
    required String state,
    double? remaining,
    int? person,
  }) => WorkItem(
    id: id,
    rev: 3,
    fields: {
      'System.WorkItemType': type,
      'System.Title': title,
      'System.State': state,
      kRemainingWorkField: ?remaining,
      if (person != null)
        'System.AssignedTo': {
          'displayName': _people[person % _people.length],
          'uniqueName': 'person$person@example.invalid',
          'id': 'person-$person',
        },
    },
  );

  /// The four columns a customized Scrum taskboard has, with the state each
  /// task type lands in. `Verify` and `In Progress` share `Active` for Task,
  /// which is the case that needs the explicit column call (research/18 §1).
  static List<TaskboardColumn> _columns() => const [
    TaskboardColumn(
      id: 'c1',
      name: 'To Do',
      order: 1,
      mappings: {'Task': 'To Do', 'Bug': 'New'},
      stateCategory: 'Proposed',
    ),
    TaskboardColumn(
      id: 'c2',
      name: 'In Progress',
      order: 2,
      mappings: {'Task': 'In Progress', 'Bug': 'Active'},
      stateCategory: 'InProgress',
    ),
    TaskboardColumn(
      id: 'c3',
      name: 'Verify',
      order: 3,
      // No Bug mapping: a bug cannot reach Verify, which is what greys the
      // row out in the move sheet.
      mappings: {'Task': 'In Progress'},
      stateCategory: 'InProgress',
    ),
    TaskboardColumn(
      id: 'c4',
      name: 'Done',
      order: 4,
      mappings: {'Task': 'Done', 'Bug': 'Closed'},
      stateCategory: 'Completed',
    ),
  ];

  static SprintRow _row(
    WorkItem? parent,
    List<WorkItem> tasks, {
    int done = 0,
  }) {
    var remaining = 0.0;
    var any = false;
    for (final task in tasks) {
      final v = task.field<num>(kRemainingWorkField)?.toDouble();
      if (v != null) {
        remaining += v;
        any = true;
      }
    }
    return SprintRow(
      parent: parent,
      tasks: tasks,
      remaining: any ? remaining : null,
      done: done,
    );
  }

  static SprintProbeData generate() {
    final story1 = _item(
      id: 15503,
      type: 'User Story',
      title: 'Sign in with Entra on a shared device',
      state: 'Active',
    );
    final story2 = _item(
      id: 15510,
      type: 'User Story',
      title: 'Refresh the token before it expires',
      state: 'New',
    );
    final story3 = _item(
      id: 15521,
      type: 'User Story',
      title: 'Sign out everywhere',
      state: 'Resolved',
    );
    final rows = <SprintRow>[
      _row(null, [
        _item(
          id: 15540,
          type: 'Task',
          title: 'Rotate the debug keystore hash',
          state: 'To Do',
          remaining: 4,
          person: 0,
        ),
        _item(
          id: 15541,
          type: 'Bug',
          title: 'Broker path never returns on a cold start',
          state: 'Active',
          remaining: 2,
          person: 1,
        ),
      ]),
      _row(story1, [
        _item(
          id: 15542,
          type: 'Task',
          title: 'Add the redirect URI to the app registration',
          state: 'To Do',
          remaining: 3,
          person: 2,
        ),
        _item(
          id: 15543,
          type: 'Task',
          title: 'Handle the interaction-required claims challenge',
          state: 'In Progress',
          remaining: 6,
          person: 0,
        ),
        _item(
          id: 15544,
          type: 'Task',
          title: 'Cache the account list per tenant',
          state: 'In Progress',
          remaining: 2,
          person: 3,
        ),
        _item(
          id: 15545,
          type: 'Task',
          title: 'Write the sign-in walkthrough',
          state: 'Done',
          person: 1,
        ),
      ], done: 1),
      _row(story2, [
        _item(
          id: 15546,
          type: 'Task',
          title: 'Silent refresh on resume',
          state: 'To Do',
          remaining: 8,
          person: 3,
        ),
        _item(
          id: 15547,
          type: 'Task',
          title: 'Back off when the token endpoint throttles',
          state: 'To Do',
          remaining: 5,
          person: 2,
        ),
      ]),
      _row(story3, const [], done: 0),
    ];
    return SprintProbeData._(
      columns: _columns(),
      rows: rows,
      visuals: const WorkItemVisuals({}),
      iterations: _iterations(),
      days: _days(),
    );
  }

  static List<TeamIteration> _iterations() => [
    TeamIteration(
      id: 'iter-1',
      name: 'Iteration 1',
      path: r'DevOps Mobile App\Iteration 1',
      timeFrame: 'current',
      startDate: DateTime.utc(2026, 9, 7),
      finishDate: DateTime.utc(2026, 9, 18),
    ),
    const TeamIteration(
      id: 'iter-2',
      name: 'Iteration 2',
      path: r'DevOps Mobile App\Iteration 2',
      timeFrame: 'future',
    ),
    TeamIteration(
      id: 'iter-0',
      name: 'Iteration 0',
      path: r'DevOps Mobile App\Iteration 0',
      timeFrame: 'past',
      startDate: DateTime.utc(2026, 8, 24),
      finishDate: DateTime.utc(2026, 9, 4),
    ),
  ];

  /// Twelve days of a burndown that fell behind and then caught up, with
  /// the weekend in the middle so the non-working bands show.
  static List<BurndownDay> _days() {
    const remaining = <int>[30, 29, 27, 26, 24, 24, 24, 20, 16, 13, 9, 6];
    const points = <double>[18, 18, 16, 16, 14, 14, 14, 11, 9, 7, 5, 3];
    return [
      for (var i = 0; i < remaining.length; i++)
        BurndownDay(
          date: DateTime.utc(2026, 9, 7).add(Duration(days: i)),
          remaining: remaining[i],
          done: 30 - remaining[i],
          points: points[i],
        ),
    ];
  }
}
