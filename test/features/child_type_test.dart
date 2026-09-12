import 'dart:convert';
import 'dart:io';

import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fixture(String name) =>
    (jsonDecode(File('test/fixtures/forms/$name').readAsStringSync()) as Map)
        .cast<String, dynamic>();

/// The scratch project's backlog configuration (`bugsBehavior: asTasks`).
BacklogTypes _asTasks() => WorkItemFormRepository.parseBacklogTypes(
  config: _fixture('scratch_backlogconfiguration.json'),
  categories: _fixture('scratch_workitemtypecategories.json'),
);

/// The same project with bugs on the requirement backlog, which is what the
/// service answers when the team chose "Bugs are managed with requirements".
BacklogTypes _asRequirements() {
  final config = _fixture('scratch_backlogconfiguration.json');
  config['bugsBehavior'] = 'asRequirements';
  (config['requirementBacklog'] as Map)['workItemTypes'] = [
    {'name': 'User Story'},
    {'name': 'Bug'},
  ];
  (config['taskBacklog'] as Map)['workItemTypes'] = [
    {'name': 'Task'},
  ];
  return WorkItemFormRepository.parseBacklogTypes(
    config: config,
    categories: _fixture('scratch_workitemtypecategories.json'),
  );
}

void main() {
  group('the child type of a work item', () {
    test('a level with nothing under it is never a parent', () {
      // "Add child" is left off the overflow when this is empty, so a Task
      // no longer offers Task and Bug (iOS walkthrough).
      expect(_asTasks().childTypeNames('Task'), isEmpty);
      expect(_asRequirements().childTypeNames('Task'), isEmpty);
    });

    test('each backlog level offers the level below it', () {
      final backlog = _asTasks();
      expect(backlog.childTypeNames('Epic'), const ['Feature']);
      expect(backlog.childTypeNames('Feature'), const ['User Story']);
      // Epics is a hidden *level* in the scratch project and still answers.
      expect(backlog.levels.first.isHidden, isTrue);
    });

    test('bugsBehavior asTasks puts Bug on the task level', () {
      final backlog = _asTasks();
      expect(backlog.bugsAreTasks, isTrue);
      // A story's children are the task-level types, Bug included.
      expect(backlog.childTypeNames('User Story'), const ['Task', 'Bug']);
      // The task level is the last one, so nothing sits under it: a Task
      // and (here) a Bug are never parents.
      expect(backlog.childTypeNames('Task'), isEmpty);
      expect(backlog.childTypeNames('Bug'), isEmpty);
    });

    test('bugsBehavior asRequirements puts Bug at the story level', () {
      final backlog = _asRequirements();
      expect(backlog.bugsAreRequirements, isTrue);
      expect(backlog.childTypeNames('Feature'), const ['User Story', 'Bug']);
      // A Bug then behaves like a story: its child is a Task.
      expect(backlog.childTypeNames('Bug'), const ['Task']);
      expect(backlog.childTypeNames('User Story'), const ['Task']);
      expect(backlog.childTypeNames('Task'), isEmpty);
    });

    test('a type on no backlog falls back to the task level', () {
      final backlog = _asTasks();
      expect(backlog.childTypeNames('Test Case'), const ['Task', 'Bug']);
    });

    test('a hidden type is never offered as a child', () {
      final backlog = BacklogTypes(
        levels: _asTasks().levels,
        hiddenTypes: const {'Bug'},
        bugsBehavior: 'asTasks',
      );
      expect(backlog.childTypeNames('User Story'), const ['Task']);
    });

    test('no backlog configuration offers nothing', () {
      expect(const BacklogTypes().childTypeNames('Task'), isEmpty);
    });
  });
}
