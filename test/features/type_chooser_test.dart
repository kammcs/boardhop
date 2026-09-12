import 'dart:convert';
import 'dart:io';

import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:boardhop/features/work_items/form/type_chooser.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fixture(String name) =>
    (jsonDecode(File('test/fixtures/forms/$name').readAsStringSync()) as Map)
        .cast<String, dynamic>();

/// The scratch project's types; only the names and the disabled flag matter
/// to the chooser's ordering.
List<WorkItemType> _types({Set<String> disabled = const {}}) => [
  for (final name in const [
    'Bug',
    'Code Review Request',
    'Code Review Response',
    'Epic',
    'Feature',
    'Feedback Request',
    'Feedback Response',
    'Shared Parameter',
    'Shared Steps',
    'Task',
    'Test Case',
    'Test Plan',
    'Test Suite',
    'User Story',
  ])
    WorkItemType(
      name: name,
      referenceName: 'Microsoft.VSTS.WorkItemTypes.${name.replaceAll(' ', '')}',
      isDisabled: disabled.contains(name),
    ),
];

BacklogTypes _backlog() => WorkItemFormRepository.parseBacklogTypes(
  config: _fixture('scratch_backlogconfiguration.json'),
  categories: _fixture('scratch_workitemtypecategories.json'),
);

void main() {
  group('the type chooser order', () {
    test('backlog levels top-down, then the rest under Other', () {
      final model = buildTypeChooserModel(types: _types(), backlog: _backlog());
      // Epics is a hidden *level* in this project, but Epic is not a hidden
      // *type*, so it still leads the list.
      expect(model.backlog.map((t) => t.name).toList(), const [
        'Epic',
        'Feature',
        'User Story',
        'Task',
        'Bug',
      ]);
      // Microsoft.HiddenCategory never appears; what is left sorts by name.
      expect(model.other.map((t) => t.name).toList(), const ['Test Case']);
      expect(model.recent, isNull);
    });

    test('a disabled type is not offered', () {
      final model = buildTypeChooserModel(
        types: _types(disabled: {'Bug', 'Test Case'}),
        backlog: _backlog(),
      );
      expect(model.backlog.map((t) => t.name), isNot(contains('Bug')));
      expect(model.other, isEmpty);
    });

    test('the project last used type comes first', () {
      final model = buildTypeChooserModel(
        types: _types(),
        backlog: _backlog(),
        recentTypeName: 'Task',
      );
      expect(model.recent?.name, 'Task');
      expect(model.all.first.name, 'Epic');
    });

    test('a remembered type that is no longer offered is dropped', () {
      final model = buildTypeChooserModel(
        types: _types(),
        backlog: _backlog(),
        recentTypeName: 'Test Plan',
      );
      expect(model.recent, isNull);
    });
  });

  group('the chooser sheet', () {
    testWidgets('lists the backlog types and answers with the pick', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final model = buildTypeChooserModel(
        types: _types(),
        backlog: _backlog(),
        recentTypeName: 'Task',
      );
      TypeChoice? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    picked = await showTypeChooser(context, model: model),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('New work item'), findsOneWidget);
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Epic'), findsOneWidget);
      expect(find.text('User Story'), findsOneWidget);
      // "Other" starts collapsed.
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Test Case'), findsNothing);

      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      expect(find.text('Test Case'), findsOneWidget);

      await tester.tap(find.text('Test Case'));
      await tester.pumpAndSettle();
      expect(picked?.typeName, 'Test Case');
      expect(picked?.template, isNull);
    });

    testWidgets('a type with templates offers Blank and the names', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final model = buildTypeChooserModel(types: _types(), backlog: _backlog());
      const template = WorkItemTemplate(
        id: 'abc',
        name: 'Regression bug',
        workItemTypeName: 'Bug',
      );
      TypeChoice? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => picked = await showTypeChooser(
                  context,
                  model: model,
                  templates: const {
                    'Bug': [template],
                  },
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Regression bug'), findsNothing);
      await tester.tap(find.text('Bug'));
      await tester.pumpAndSettle();
      expect(find.text('Blank'), findsOneWidget);

      await tester.tap(find.text('Regression bug'));
      await tester.pumpAndSettle();
      expect(picked?.typeName, 'Bug');
      expect(picked?.template?.id, 'abc');
    });
  });
}
