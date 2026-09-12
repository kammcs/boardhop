import 'dart:convert';
import 'dart:io';

import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
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
  final item = WorkItem.fromJson(_fixture('scratch_bug_item.json'));

  WorkItemFormState editState({WorkItem? on, FormSpec? using}) {
    final base = on ?? item;
    final used = using ?? spec;
    return WorkItemFormState(
      spec: used,
      initialValues: valuesFromItem(used, base),
      formats: formatsFromItem(used, base),
      isCreate: false,
      original: base,
    );
  }

  group('the edit form on the scratch Bug #15546', () {
    test('it initializes from the item', () {
      final state = editState();
      expect(state.title, '[phase3] the edit form loads from the item');
      expect(state.stateName, 'New');
      expect(state.originalState, 'New');
      expect(state.value('Microsoft.VSTS.Common.Priority'), 2);
      expect(state.value('Microsoft.VSTS.Common.Severity'), '3 - Medium');
      expect(state.tags, ['phase3', 'forms']);
      expect(state.assignedTo?.displayName, 'Kelly Kamm');
      // Long text keeps the item's own HTML, and its format map with it
      // (spike w01); the Markdown choice is not offered on an edit.
      expect(
        state.value('Microsoft.VSTS.TCM.ReproSteps'),
        '<div>Open the item and press the pencil.</div>',
      );
      expect(state.formatOf('Microsoft.VSTS.TCM.ReproSteps'), 'html');
      expect(state.canChooseFormat('System.Description'), isFalse);
      state.dispose();
    });

    testWidgets('the header shows the id and the type', (tester) async {
      final state = editState();
      await _pump(tester, state);

      expect(find.text('#15546'), findsOneWidget);
      expect(find.text('Bug'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
      state.dispose();
    });

    test('Save is disabled until something changes', () {
      final state = editState();
      expect(state.isDirty, isFalse);
      state.setValue('System.Title', 'a new title');
      expect(state.isDirty, isTrue);
      state.dispose();
    });

    test('an untouched form produces nothing but the guard', () {
      final state = editState();
      final ops = state.buildEditOps();
      expect(ops, [
        {'op': 'test', 'path': '/rev', 'value': 7},
      ]);
      state.dispose();
    });

    test('a title and priority change patch those two fields only', () {
      final state = editState();
      state
        ..setValue(
          'System.Title',
          '[phase3] the edit form loads from the item (edited)',
        )
        ..setValue('Microsoft.VSTS.Common.Priority', 1);
      final ops = state.buildEditOps();
      expect(ops.first, {'op': 'test', 'path': '/rev', 'value': 7});
      expect(ops.length, 3);
      expect(ops.skip(1).map((op) => op['path']).toSet(), {
        '/fields/System.Title',
        '/fields/Microsoft.VSTS.Common.Priority',
      });
      Object? valueOf(String path) => ops.firstWhere(
        (op) => op['path'] == path,
        orElse: () => const {},
      )['value'];
      expect(
        valueOf('/fields/System.Title'),
        '[phase3] the edit form loads from the item (edited)',
      );
      expect(valueOf('/fields/Microsoft.VSTS.Common.Priority'), 1);
      // The item's HTML is never re-escaped on its way back out.
      expect(
        ops.every(
          (op) => op['path'] != '/fields/Microsoft.VSTS.TCM.ReproSteps',
        ),
        isTrue,
      );
      state.dispose();
    });

    test('the state chip offers the legal transitions only', () {
      final state = editState();
      // Bug from New (spike w18).
      expect(state.legalTransitions, ['New', 'Closed', 'Resolved', 'Active']);
      state.dispose();
    });

    testWidgets('the sheet lists only the transitions of this state', (
      tester,
    ) async {
      // A type whose New state only moves to Active, so a state that exists
      // but is not reachable can be checked for.
      final state = editState(using: _restrictedTransitions(spec));
      await _pump(tester, state);

      await tester.tap(find.widgetWithText(ActionChip, 'New'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Active'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'New'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Closed'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Resolved'), findsNothing);

      await tester.tap(find.widgetWithText(ListTile, 'Active'));
      await tester.pumpAndSettle();
      expect(state.stateName, 'Active');
      state.dispose();
    });

    testWidgets('a transition reveals the Reason picklist', (tester) async {
      final state = editState();
      await _pump(tester, state);
      expect(state.showReason, isFalse);
      expect(find.text('Reason'), findsNothing);

      state.setStateName('Active');
      await tester.pump();
      expect(state.showReason, isTrue);
      expect(find.text('Reason'), findsOneWidget);
      // The reason of the state it came from never travels with it: unsent,
      // the server picks the new state's default (spike w18).
      expect(state.value('System.Reason'), isNull);
      final ops = state.buildEditOps();
      expect(ops.any((op) => op['path'] == '/fields/System.Reason'), isFalse);
      expect(
        ops.any(
          (op) =>
              op['path'] == '/fields/System.State' && op['value'] == 'Active',
        ),
        isTrue,
      );

      state.setValue('System.Reason', 'Approved');
      expect(
        state.buildEditOps().any(
          (op) =>
              op['path'] == '/fields/System.Reason' &&
              op['value'] == 'Approved',
        ),
        isTrue,
      );
      state.dispose();
    });

    testWidgets('a 412 shows the banner with Reload and Discard', (
      tester,
    ) async {
      final state = editState();
      var reloaded = 0;
      var discarded = 0;
      state
        ..onReload = (() => reloaded++)
        ..onDiscard = (() => discarded++);
      await _pump(tester, state);
      expect(find.text('This item changed on the server'), findsNothing);

      // What `_save` does on an AdoStaleRevisionException.
      state.setConflict(true);
      await tester.pump();
      expect(find.text('This item changed on the server'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Reload'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Discard'));
      await tester.pump();
      expect(reloaded, 1);
      expect(discarded, 1);
      state.dispose();
    });

    test('a conflict reload keeps the fields the user changed', () {
      final state = editState();
      state.setValue('System.Title', 'mine');
      // What `_reload(keepChanges: true)` builds: the fresh item underneath,
      // the dirty values on top, and the new revision as the guard.
      final fresh = WorkItem(
        id: item.id,
        rev: item.rev + 1,
        fields: {...item.fields, 'System.Title': 'theirs'},
        multilineFieldsFormat: item.multilineFieldsFormat,
      );
      final next = WorkItemFormState(
        spec: spec,
        initialValues: {
          ...valuesFromItem(spec, fresh),
          for (final reference in state.dirtyFields)
            reference: state.value(reference),
        },
        dirtyFields: state.dirtyFields,
        isCreate: false,
        original: fresh,
      );
      expect(next.title, 'mine');
      expect(next.isDirty, isTrue);
      final ops = next.buildEditOps();
      expect(ops.first, {'op': 'test', 'path': '/rev', 'value': 8});
      expect(ops.length, 2);
      expect(ops.last['value'], 'mine');
      state.dispose();
      next.dispose();
    });

    testWidgets('a read-only control with a value shows as text', (
      tester,
    ) async {
      final readOnly = _withReadOnlyControl(spec);
      final resolved = WorkItem(
        id: item.id,
        rev: item.rev,
        fields: {
          ...item.fields,
          'Microsoft.VSTS.Common.ResolvedReason': 'Fixed',
        },
      );
      final state = editState(on: resolved, using: readOnly);
      await _pump(tester, state);

      expect(find.text('Resolved Reason'), findsOneWidget);
      expect(find.text('Fixed'), findsOneWidget);
      // Never editable, and never part of the patch.
      expect(
        state.isReadOnlyField('Microsoft.VSTS.Common.ResolvedReason'),
        isTrue,
      );
      state.setValue('System.Title', 'touched');
      expect(
        state.buildEditOps().any(
          (op) => op['path'] == '/fields/Microsoft.VSTS.Common.ResolvedReason',
        ),
        isFalse,
      );
      state.dispose();
    });

    test('a read-only control with no value is not shown at all', () {
      final readOnly = _withReadOnlyControl(spec);
      final bare = WorkItem(
        id: item.id,
        rev: item.rev,
        fields: {...item.fields}
          ..remove('Microsoft.VSTS.Common.ResolvedReason'),
      );
      final state = editState(on: bare, using: readOnly);
      expect(
        state.fieldRefs.contains('Microsoft.VSTS.Common.ResolvedReason'),
        isFalse,
      );
      state.dispose();
    });
  });
}

/// The same Bug, with New reaching only Active: the fixture's own four
/// transitions would match every state of the type.
FormSpec _restrictedTransitions(FormSpec spec) {
  final json = spec.toJson();
  (json['type'] as Map)['transitions'] = {
    '': [
      {'to': 'New'},
    ],
    'New': [
      {'to': 'New'},
      {'to': 'Active'},
    ],
  };
  return FormSpec.fromJson(json.cast<String, dynamic>());
}

/// Resolved Reason turned into a read-only control, as an inherited process
/// can mark any field; the stock scratch types have none on a card.
FormSpec _withReadOnlyControl(FormSpec spec) {
  final json = spec.toJson();
  final layout = (json['layout'] as Map).cast<String, dynamic>();
  for (final page in (layout['pages'] as List).cast<Map>()) {
    for (final section in (page['sections'] as List).cast<Map>()) {
      for (final group in (section['groups'] as List).cast<Map>()) {
        for (final control in (group['controls'] as List).cast<Map>()) {
          if (control['field'] == 'Microsoft.VSTS.Common.ResolvedReason') {
            control['readOnly'] = true;
          }
        }
      }
    }
  }
  return FormSpec.fromJson(json.cast<String, dynamic>());
}
