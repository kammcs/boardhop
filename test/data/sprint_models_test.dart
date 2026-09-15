import 'dart:convert';

import 'package:boardhop/data/models/sprint.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:flutter_test/flutter_test.dart';

WorkItem item(
  int id, {
  String type = 'Task',
  String state = 'New',
  String title = 'A task',
  double? remaining,
}) => WorkItem.fromJson({
  'id': id,
  'rev': 3,
  'fields': {
    'System.Id': id,
    'System.WorkItemType': type,
    'System.Title': title,
    'System.State': state,
    'Microsoft.VSTS.Scheduling.RemainingWork': ?remaining,
  },
});

TeamIteration iteration({
  String id = 'aa9f2381-0000-0000-0000-000000000001',
  DateTime? start,
  DateTime? finish,
  String timeFrame = 'current',
}) => TeamIteration(
  id: id,
  name: 'Iteration 1',
  path: r'DevOps Mobile App\Iteration 1',
  timeFrame: timeFrame,
  startDate: start,
  finishDate: finish,
);

/// A trip through `jsonEncode`/`jsonDecode`, which is what `JsonCache` does
/// to a snapshot: a model that only round trips through its own maps can
/// still fail on a `DateTime` or an int key.
Map<String, dynamic> cycle(Map<String, dynamic> json) =>
    (jsonDecode(jsonEncode(json)) as Map).cast<String, dynamic>();

void main() {
  group('TaskboardColumn', () {
    test('round trips a derived column', () {
      const column = TaskboardColumn(
        name: 'In Progress',
        order: 1,
        mappings: {'Task': 'Active'},
        states: {
          'Task': ['Active', 'Resolved'],
        },
        stateCategory: 'InProgress',
      );

      final back = TaskboardColumn.fromJson(cycle(column.toJson()));

      expect(back, column);
      expect(back.id, isNull);
      expect(back.isCustomized, isFalse);
      expect(back.isDone, isFalse);
    });

    test('a Completed column is the done column', () {
      const column = TaskboardColumn(
        name: 'Done',
        order: 2,
        stateCategory: 'Completed',
      );
      expect(column.isDone, isTrue);
    });

    test('fromWire reads the mappings list and accepts that state', () {
      final column = TaskboardColumn.fromWire({
        'id': 'dbba394c-0000-0000-0000-000000000001',
        'name': 'Verify',
        'order': 2,
        'mappings': [
          {'workItemType': 'Task', 'state': 'Active'},
          {'workItemType': 'Bug', 'state': 'Active'},
        ],
      });

      expect(column.isCustomized, isTrue);
      expect(column.mappings, {'Task': 'Active', 'Bug': 'Active'});
      expect(column.accepts('Task', 'Active'), isTrue);
      expect(column.accepts('Task', 'New'), isFalse);
      expect(TaskboardColumn.fromJson(cycle(column.toJson())), column);
    });
  });

  group('SprintSnapshot', () {
    test('round trips rows, the unparented row and explicit columns', () {
      final snapshot = SprintSnapshot(
        iteration: iteration(
          start: DateTime.utc(2026, 9, 8),
          finish: DateTime.utc(2026, 9, 21),
        ),
        columns: const [
          TaskboardColumn(name: 'To Do', order: 0, stateCategory: 'Proposed'),
          TaskboardColumn(name: 'Done', order: 1, stateCategory: 'Completed'),
        ],
        rows: [
          SprintRow(
            parent: item(15546, type: 'User Story', title: 'Story'),
            tasks: [
              item(15550),
              item(15551, state: 'Closed'),
            ],
            remaining: 3,
            done: 1,
          ),
        ],
        unparented: SprintRow(tasks: [item(15553)]),
        explicitColumns: const {15550: 'Verify'},
        fetchedAt: DateTime.utc(2026, 9, 15, 10, 30),
      );

      final back = SprintSnapshot.fromJson(cycle(snapshot.toJson()));

      expect(back, snapshot);
      expect(back.iteration.startDate, DateTime.utc(2026, 9, 8));
      expect(back.rows.single.parent!.id, 15546);
      expect(back.rows.single.remaining, 3);
      // Int keys survive the string keys JSON forces on a map.
      expect(back.explicitColumns[15550], 'Verify');
      expect(back.unparented.tasks.single.id, 15553);
    });

    test('the unparented row comes first and only when it has tasks', () {
      final row = SprintRow(parent: item(1, type: 'User Story'));
      final snapshot = SprintSnapshot(
        iteration: iteration(),
        columns: const [],
        rows: [row],
        fetchedAt: DateTime.utc(2026),
      );

      expect(snapshot.allRows, [row]);
      expect(snapshot.taskCount, 0);

      final withOrphans = snapshot.copyWith(
        unparented: SprintRow(tasks: [item(2)]),
      );
      expect(withOrphans.allRows.first.isUnparented, isTrue);
      expect(withOrphans.allRows.length, 2);
      expect(withOrphans.taskCount, 1);
    });

    test('a snapshot with no columns is not customized', () {
      final snapshot = SprintSnapshot(
        iteration: iteration(),
        columns: const [
          TaskboardColumn(name: 'To Do', order: 0),
          TaskboardColumn(id: 'c-1', name: 'In Progress', order: 1),
        ],
        rows: const [],
        fetchedAt: DateTime.utc(2026),
      );
      expect(snapshot.isCustomized, isTrue);
      expect(
        SprintSnapshot(
          iteration: iteration(),
          columns: const [TaskboardColumn(name: 'To Do', order: 0)],
          rows: const [],
          fetchedAt: DateTime.utc(2026),
        ).isCustomized,
        isFalse,
      );
    });
  });

  group('SprintCapacity', () {
    test('reads the teamMembers collection, not value', () {
      final capacity = SprintCapacity.fromJson({
        'teamMembers': [
          {
            'teamMember': {'displayName': 'Kelly Kamm', 'id': 'k'},
            'activities': [
              {'capacityPerDay': 6.0, 'name': 'Development'},
              {'capacityPerDay': 2.0, 'name': 'Testing'},
            ],
            'daysOff': [
              {'start': '2026-09-10T00:00:00Z', 'end': '2026-09-11T00:00:00Z'},
            ],
          },
        ],
        'teamDaysOff': [
          {'start': '2026-09-14T00:00:00Z', 'end': '2026-09-14T00:00:00Z'},
        ],
        'workingDays': ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'],
      });

      expect(capacity.isEmpty, isFalse);
      expect(capacity.members.single.member.displayName, 'Kelly Kamm');
      expect(capacity.members.single.capacityPerDay, 8);
      expect(capacity.members.single.daysOffCount, 2);
      expect(capacity.totalPerDay, 8);
      expect(SprintCapacity.fromJson(cycle(capacity.toJson())), capacity);
    });

    test('an unfilled sprint is empty, which is the normal case', () {
      final capacity = SprintCapacity.fromJson({
        'teamMembers': const [],
        'totalCapacityPerDay': 0.0,
        'totalDaysOff': 0,
      });
      expect(capacity.isEmpty, isTrue);
      expect(capacity.totalPerDay, 0);
    });

    test('working days skip the weekend and the team days off', () {
      final capacity = SprintCapacity.fromJson({
        'teamMembers': const [],
        'teamDaysOff': [
          {'start': '2026-09-16T00:00:00Z', 'end': '2026-09-16T00:00:00Z'},
        ],
        'workingDays': ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'],
      });

      expect(capacity.isWorkingDay(DateTime(2026, 9, 15)), isTrue); // Tue
      expect(capacity.isWorkingDay(DateTime(2026, 9, 16)), isFalse); // day off
      expect(capacity.isWorkingDay(DateTime(2026, 9, 19)), isFalse); // Sat
    });

    test('with no workingDays read it is Monday to Friday', () {
      const capacity = SprintCapacity();
      expect(capacity.isWorkingDay(DateTime(2026, 9, 18)), isTrue);
      expect(capacity.isWorkingDay(DateTime(2026, 9, 20)), isFalse);
    });
  });

  group('BurndownDay', () {
    test('round trips and sums the scope', () {
      final day = BurndownDay(
        date: DateTime.utc(2026, 9, 8),
        remaining: 39,
        done: 8,
        points: 16.5,
      );

      final back = BurndownDay.fromJson(cycle(day.toJson()));

      expect(back, day);
      expect(back.scope, 47);
      expect(back.date.isUtc, isTrue);
    });
  });

  group('SprintIterations', () {
    final past1 = iteration(id: 'p1', timeFrame: 'past');
    final past2 = iteration(id: 'p2', timeFrame: 'past');
    final current = iteration(id: 'c1');
    final future = iteration(id: 'f1', timeFrame: 'future');

    test('splits the wire order and lists past newest first', () {
      final all = SprintIterations(all: [past1, past2, current, future]);

      expect(all.current, [current]);
      expect(all.future, [future]);
      expect(all.past, [past2, past1]);
      expect(all.defaultIteration, current);
      expect(all.byId('f1'), future);
      expect(all.byId('nope'), isNull);
    });

    test('with no current sprint it opens on the next future one', () {
      expect(SprintIterations(all: [past1, future]).defaultIteration, future);
      expect(SprintIterations(all: [past1, past2]).defaultIteration, past2);
      expect(const SprintIterations().defaultIteration, isNull);
    });
  });

  group('SprintDates', () {
    final now = DateTime(2026, 9, 15, 11);

    test('an undated sprint has no counters at all', () {
      final undated = iteration();
      expect(undated.hasDates, isFalse);
      expect(undated.isEnded(now: now), isFalse);
      expect(undated.daysRemaining(now: now), isNull);
      expect(undated.daysSinceEnd(now: now), isNull);
      expect(undated.lengthInDays, isNull);
    });

    test('a running sprint counts today as a day left', () {
      final running = iteration(
        start: DateTime.utc(2026, 9, 8),
        finish: DateTime.utc(2026, 9, 21),
      );
      expect(running.isEnded(now: now), isFalse);
      expect(running.daysRemaining(now: now), 7);
      expect(running.lengthInDays, 14);
      expect(running.daysSinceEnd(now: now), isNull);
    });

    test('a sprint the service still calls current can have ended (S12)', () {
      final ended = iteration(
        start: DateTime.utc(2026, 8, 25),
        finish: DateTime.utc(2026, 9, 7),
      );
      expect(ended.isCurrent, isTrue);
      expect(ended.isEnded(now: now), isTrue);
      expect(ended.daysSinceEnd(now: now), 8);
      expect(ended.daysRemaining(now: now), isNull);
    });

    test('the last day of a sprint is not over yet', () {
      final today = iteration(
        start: DateTime.utc(2026, 9, 8),
        finish: DateTime.utc(2026, 9, 15),
      );
      expect(today.isEnded(now: now), isFalse);
      expect(today.daysRemaining(now: now), 1);
    });
  });
}
