import 'dart:convert';
import 'dart:io';

import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:boardhop/features/work_items/form/controls/boolean_control.dart';
import 'package:boardhop/features/work_items/form/controls/date_control.dart';
import 'package:boardhop/features/work_items/form/controls/picklist_control.dart';
import 'package:boardhop/features/work_items/form/controls/text_control.dart';
import 'package:boardhop/features/work_items/form/work_item_form_body.dart';
import 'package:boardhop/features/work_items/form/work_item_form_state.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fixture(String name) =>
    (jsonDecode(File('test/fixtures/forms/$name').readAsStringSync()) as Map)
        .cast<String, dynamic>();

List<Map<String, dynamic>> _values(Map<String, dynamic> json) => [
  for (final v in (json['value'] as List?) ?? const [])
    if (v is Map) v.cast<String, dynamic>(),
];

FormSpec _specFor(String type) {
  final orgFields = {
    for (final f in _values(_fixture('org_fields.json')))
      (f['referenceName'] as String): FieldSpec.fromOrgField(f),
  };
  return WorkItemFormRepository.buildSpec(
    typeJson: _fixture('scratch_${type}_type.json'),
    typeFields: _values(_fixture('scratch_${type}_fields.json')),
    orgFields: orgFields,
  );
}

Widget _host(WorkItemFormState state) => MaterialApp(
  theme: BoardhopTheme.light(),
  home: Scaffold(body: WorkItemFormBody(state: state)),
);

/// A tall phone-width surface so the whole form is laid out at once.
Future<void> _pump(
  WidgetTester tester,
  WorkItemFormState state, {
  Size size = const Size(400, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(state));
  await tester.pump();
}

void main() {
  final spec = _specFor('bug');

  WorkItemFormState newState({Map<String, Object?> values = const {}}) =>
      WorkItemFormState(
        spec: spec,
        initialValues: {'System.State': spec.initialState, ...values},
      );

  group('the form body from the scratch Bug', () {
    testWidgets('the header carries the type, the title and the chips', (
      tester,
    ) async {
      final state = newState();
      await _pump(tester, state);

      expect(find.text('Bug'), findsOneWidget);
      expect(find.text('Title *'), findsOneWidget);
      expect(find.text('Enter title here'), findsOneWidget);
      // The state chip is read-only on create and shows the initial state.
      expect(find.text('New'), findsOneWidget);
      expect(find.text('Assigned to'), findsOneWidget);
      expect(find.text('Area'), findsOneWidget);
      expect(find.text('Iteration'), findsOneWidget);
      expect(find.text('Tags'), findsOneWidget);
      state.dispose();
    });

    test('the groups follow the web, all columns flattened top-down', () {
      final state = newState();
      expect(state.groups.map((g) => g.label).toList(), const [
        'Repro Steps',
        'System Info',
        'Planning',
        'Effort (Hours)',
        'Deployment',
        'Development',
        'Related Work',
        'System Info',
      ]);
      // Panels need an id: phase 5 replaces the placeholder.
      expect(
        state.groups.where((g) => g.unavailable).map((g) => g.label).toList(),
        const ['Deployment', 'Development', 'Related Work'],
      );
      expect(
        state.groups[2].controls.map((c) => c.fieldReferenceName).toList(),
        const [
          'Microsoft.VSTS.Common.ResolvedReason',
          'Microsoft.VSTS.Scheduling.StoryPoints',
          'Microsoft.VSTS.Common.Priority',
          'Microsoft.VSTS.Common.Severity',
          'Microsoft.VSTS.Common.Activity',
        ],
      );
      // The header's own fields are not repeated in a card.
      final all = [
        for (final g in state.groups)
          for (final c in g.controls) c.fieldReferenceName,
      ];
      expect(all, isNot(contains('System.Title')));
      expect(all, isNot(contains('System.AreaPath')));
      state.dispose();
    });

    testWidgets('each control matches its field type', (tester) async {
      final state = newState();
      await _pump(tester, state);

      // Repro Steps is an html field: a multi-line box in phase 1.
      expect(find.text('Repro Steps'), findsWidgets);
      // Priority, Severity, Activity and Resolved Reason are allowed-value
      // lists; Story Points and the three effort fields are numbers.
      expect(find.byType(PicklistControl), findsWidgets);
      expect(find.byType(TextControl), findsWidgets);
      expect(find.byType(DateControl), findsNothing);
      expect(find.byType(BooleanControl), findsNothing);
      expect(find.text('Available after creation'), findsWidgets);
      state.dispose();
    });

    testWidgets('an empty title blocks Create locally', (tester) async {
      final state = newState();
      await _pump(tester, state);

      expect(state.validateLocally(), isFalse);
      expect(state.errorFor('System.Title'), 'Title is required');
      await tester.pump();
      expect(find.text('Title is required'), findsOneWidget);
      expect(state.firstErrorField, 'System.Title');

      state.setValue('System.Title', '[phase1] created from the app');
      expect(state.validateLocally(), isTrue);
      state.dispose();
    });

    testWidgets('a numeric field rejects letters', (tester) async {
      final state = newState(
        values: {'System.Title': 'Numbers only', 'System.AreaPath': 'P'},
      );
      await _pump(tester, state);

      final points = find.ancestor(
        of: find.text('Story Points'),
        matching: find.byType(TextControl),
      );
      expect(points, findsOneWidget);
      await tester.enterText(
        find.descendant(of: points, matching: find.byType(TextField)),
        'abc',
      );
      await tester.pump();
      // The formatter drops the letters, so nothing lands in the value.
      expect(state.value('Microsoft.VSTS.Scheduling.StoryPoints'), isNull);

      await tester.enterText(
        find.descendant(of: points, matching: find.byType(TextField)),
        '3.5',
      );
      await tester.pump();
      expect(state.value('Microsoft.VSTS.Scheduling.StoryPoints'), 3.5);
      state.dispose();
    });

    test('a parse error survives a local validation pass', () {
      final state = newState(values: {'System.Title': 'Parse'});
      state.setParseError('Microsoft.VSTS.Common.Priority', 'Enter a number');
      expect(state.validateLocally(), isFalse);
      expect(
        state.errorFor('Microsoft.VSTS.Common.Priority'),
        'Enter a number',
      );
      state.dispose();
    });

    test('the state produces the create patch phase 0 expects', () {
      final state = newState(
        values: {
          'System.Title': '[phase1] created from the app',
          'System.AreaPath': 'DevOps Mobile App',
          'System.IterationPath': r'DevOps Mobile App\Iteration 1',
          'System.Tags': ['phase1'],
          'System.AssignedTo': const IdentityRef(
            displayName: 'Kelly Kamm',
            id: 'abc',
          ),
          'Microsoft.VSTS.Common.Priority': '3',
          'Microsoft.VSTS.TCM.ReproSteps': 'a & b\nc',
        },
      );
      final ops = state.buildOps(
        parentUrl: 'https://dev.azure.com/puremedia/_apis/wit/workItems/15503',
      );
      Object? valueOf(String path) => ops.firstWhere(
        (op) => op['path'] == path,
        orElse: () => const {},
      )['value'];

      expect(valueOf('/fields/System.Title'), '[phase1] created from the app');
      expect(valueOf('/fields/System.AssignedTo'), 'abc');
      expect(valueOf('/fields/System.Tags'), 'phase1');
      expect(valueOf('/fields/Microsoft.VSTS.Common.Priority'), '3');
      // An html field is escaped into one div until phase 2.
      expect(
        valueOf('/fields/Microsoft.VSTS.TCM.ReproSteps'),
        '<div>a &amp; b<br>c</div>',
      );
      // State and Reason are the server's on a new item.
      expect(ops.every((op) => op['path'] != '/fields/System.State'), isTrue);
      expect(ops.last['value'], {
        'rel': WorkItemFormRepository.parentRel,
        'url': 'https://dev.azure.com/puremedia/_apis/wit/workItems/15503',
      });
      state.dispose();
    });

    test('server rule errors land under their field, the rest in a banner', () {
      final state = newState(values: {'System.Title': 'Rules'});
      state.applyRuleErrors(
        WorkItemRuleException(
          'refused',
          errors: const [
            ValidationError(
              fieldReferenceName: 'Microsoft.VSTS.Common.Priority',
              flags: ['invalidListValue'],
              message: 'Priority 9 is not allowed',
            ),
            ValidationError(
              fieldReferenceName: 'Custom.NotOnTheForm',
              flags: ['required'],
              message: 'is required',
            ),
          ],
        ),
      );
      expect(
        state.errorFor('Microsoft.VSTS.Common.Priority'),
        'Priority 9 is not allowed',
      );
      expect(state.bannerError, contains('Custom.NotOnTheForm'));
      state.clearServerErrors();
      expect(state.errorFor('Microsoft.VSTS.Common.Priority'), isNull);
      expect(state.bannerError, isNull);
      state.dispose();
    });
  });
}
