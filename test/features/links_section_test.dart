import 'dart:convert';
import 'dart:io';

import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:boardhop/features/work_items/form/controls/links_section.dart';
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

const _base = 'https://dev.azure.com/puremedia/_apis/wit/workItems';
const _attachments = 'https://dev.azure.com/puremedia/_apis/wit/attachments';

WorkItemRelation _link(String rel, int id) =>
    WorkItemRelation(rel: rel, url: '$_base/$id');

WorkItem _target(int id, {String type = 'Task', String state = 'New'}) =>
    WorkItem.fromJson({
      'id': id,
      'rev': 1,
      'url': '$_base/$id',
      'fields': {
        'System.WorkItemType': type,
        'System.Title': 'target $id',
        'System.State': state,
      },
    });

/// The relation list the walkthrough items carry, plus one of every other
/// kind and three relations the Links page must ignore.
final _relations = <WorkItemRelation>[
  _link(WorkItemRelation.parentRel, 15546),
  _link(WorkItemRelation.childRel, 15550),
  _link(WorkItemRelation.childRel, 15551),
  _link(WorkItemRelation.relatedRel, 15547),
  _link(WorkItemRelation.predecessorRel, 15503),
  _link(WorkItemRelation.successorRel, 15504),
  _link(WorkItemRelation.duplicateRel, 15505),
  _link(WorkItemRelation.duplicateOfRel, 15506),
  _link('Custom.LinkTypes.Whatever-Forward', 15507),
  WorkItemRelation(
    rel: WorkItemRelation.attachedFileRel,
    url: '$_attachments/1111?fileName=shot.png',
    attributes: const {'name': 'shot.png'},
  ),
  const WorkItemRelation(
    rel: WorkItemRelation.hyperlinkRel,
    url: 'https://example.test/spec',
  ),
  const WorkItemRelation(
    rel: WorkItemRelation.artifactLinkRel,
    url: 'vstfs:///Git/PullRequestId/1/2/8336',
  ),
];

void main() {
  final spec = _specFor('bug');
  final item = WorkItem.fromJson(_fixture('scratch_bug_item.json'));

  /// The form as the page builds it: the item it loaded, whose own
  /// `relations[]` is both the list on screen and the index base of a
  /// removal (research/01 §2.6).
  WorkItemFormState editState({List<WorkItemRelation>? relations}) {
    final loaded = WorkItem.fromJson({
      ...item.toJson(),
      'relations': [for (final r in relations ?? _relations) r.toJson()],
    });
    return WorkItemFormState(
      spec: spec,
      initialValues: valuesFromItem(spec, loaded),
      formats: formatsFromItem(spec, loaded),
      isCreate: false,
      original: loaded,
      relations: loaded.relations,
    );
  }

  group('grouping by kind', () {
    test('the kinds come out in the page order, wire order kept inside', () {
      final groups = groupLinkRelations(_relations);
      expect(
        groups.map((g) => '${g.kind.name}:${g.relations.length}').toList(),
        const [
          'parent:1',
          'child:2',
          'related:1',
          'predecessor:1',
          'successor:1',
          'duplicate:1',
          'duplicateOf:1',
          'other:1',
        ],
      );
      expect(groups[1].relations.map((r) => r.targetId).toList(), const [
        15550,
        15551,
      ]);
    });

    test('attachments, hyperlinks and artifact links are not links', () {
      final listed = [
        for (final g in groupLinkRelations(_relations)) ...g.relations,
      ];
      expect(listed.length, 9);
      expect(listed.any((r) => r.isAttachment), isFalse);
      expect(
        listed.any((r) => r.rel == WorkItemRelation.hyperlinkRel),
        isFalse,
      );
      expect(
        listed.any((r) => r.rel == WorkItemRelation.artifactLinkRel),
        isFalse,
      );
    });

    test('an unknown rel lands in Other, and headings pluralize', () {
      expect(LinkKind.of('Custom.LinkTypes.Whatever-Forward'), LinkKind.other);
      expect(LinkKind.of(WorkItemRelation.childRel), LinkKind.child);
      expect(LinkKind.child.heading, 'Children');
      expect(LinkKind.parent.heading, 'Parent');
    });

    test('the picker offers the six kinds a user can add', () {
      expect(LinkKind.addableKinds.map((k) => k.label).toList(), const [
        'Parent',
        'Child',
        'Related',
        'Predecessor',
        'Successor',
        'Duplicate of',
      ]);
      // Child and Related may repeat, so the search multi-selects.
      expect(LinkKind.child.multiple, isTrue);
      expect(LinkKind.related.multiple, isTrue);
      expect(LinkKind.parent.multiple, isFalse);
    });
  });

  group('the edit patch', () {
    test('an added link is one add op after the guard', () {
      final state = editState(relations: const []);
      expect(state.isDirty, isFalse);
      state.addRelation(_link(WorkItemRelation.relatedRel, 15547));
      expect(state.isDirty, isTrue);
      final ops = state.buildEditOps();
      expect(ops, [
        {'op': 'test', 'path': '/rev', 'value': 7},
        {
          'op': 'add',
          'path': '/relations/-',
          'value': {'rel': WorkItemRelation.relatedRel, 'url': '$_base/15547'},
        },
      ]);
      state.dispose();
    });

    test('removals are by index, in descending order', () {
      final state = editState();
      // Indices 1, 3 and 9 of the item's own relation list.
      state
        ..removeRelation(_relations[3])
        ..removeRelation(_relations[1])
        ..removeRelation(_relations[9]);
      final ops = state.buildEditOps().skip(1).toList();
      expect(ops.map((op) => op['path']).toList(), const [
        '/relations/9',
        '/relations/3',
        '/relations/1',
      ]);
      expect(ops.every((op) => op['op'] == 'remove'), isTrue);
      state.dispose();
    });

    test('the indices come from the item the ops are built against', () {
      final state = editState();
      state.removeRelation(_relations[4]);
      // The same relation sits at a different index on a fresh read.
      final moved = WorkItem.fromJson({
        'id': 15546,
        'rev': 8,
        'fields': const {'System.Title': 'moved on'},
        'relations': [
          for (final r in [_relations[0], _relations[4]]) r.toJson(),
        ],
      });
      expect(state.buildRelationOps(moved).single, const {
        'op': 'remove',
        'path': '/relations/1',
      });
      state.dispose();
    });

    test('removals come before the additions', () {
      final state = editState();
      state
        ..removeRelation(_relations[3])
        ..addRelation(_link(WorkItemRelation.relatedRel, 15552));
      final ops = state.buildEditOps().skip(1).toList();
      expect(ops.first['op'], 'remove');
      expect(ops.last['op'], 'add');
      state.dispose();
    });

    test('a second parent replaces the first', () {
      final state = editState();
      state.addRelation(_link(WorkItemRelation.parentRel, 15503));
      // The old parent (index 0) goes, the new one is added.
      final ops = state.buildEditOps().skip(1).toList();
      expect(ops, [
        {'op': 'remove', 'path': '/relations/0'},
        {
          'op': 'add',
          'path': '/relations/-',
          'value': {'rel': WorkItemRelation.parentRel, 'url': '$_base/15503'},
        },
      ]);
      expect(
        state.linkRelations.where((r) => r.isParent).single.targetId,
        15503,
      );
      state.dispose();
    });

    test('adding back what was removed is the removal undone', () {
      final state = editState();
      state
        ..removeRelation(_relations[3])
        ..addRelation(_relations[3]);
      expect(state.hasRelationChanges, isFalse);
      expect(state.buildEditOps().length, 1);
      state.dispose();
    });

    test('the same link is never added twice', () {
      final state = editState();
      state
        ..addRelation(_link(WorkItemRelation.relatedRel, 15547))
        ..addRelation(_link(WorkItemRelation.relatedRel, 15547));
      expect(state.buildEditOps().length, 1 + 0);
      expect(state.linkRelations.where((r) => r.isRelated).length, 1);
      state.dispose();
    });

    test('a rebase on a list without the addition keeps it pending', () {
      // `WorkItemRepository.patch` asks for `$expand=relations` exactly so
      // this does not happen: a response without them would leave the
      // addition pending and the next Save would be refused with
      // "Relation already exists" (found on the emulator, phase 5).
      final state = editState(relations: const []);
      state.addRelation(_link(WorkItemRelation.relatedRel, 15547));
      state.rebaseRelations(const []);
      expect(state.hasRelationChanges, isTrue);
      expect(state.linkRelations.single.targetId, 15547);
      state.dispose();
    });

    test('a commit rebases the form on the server list', () {
      final state = editState(relations: const []);
      state.addRelation(_link(WorkItemRelation.relatedRel, 15547));
      state.rebaseRelations([_link(WorkItemRelation.relatedRel, 15547)]);
      expect(state.hasRelationChanges, isFalse);
      expect(state.isDirty, isFalse);
      expect(state.linkRelations.single.targetId, 15547);
      state.dispose();
    });
  });

  group('the create patch', () {
    test('the pending links ride in buildCreateOps', () {
      final state = WorkItemFormState(
        spec: spec,
        initialValues: {
          'System.Title': '[phase5] created with a link',
          'System.State': spec.initialState,
        },
        newRelations: [_link(WorkItemRelation.parentRel, 15546)],
      );
      // The parent the form was opened with is there but is not a change.
      expect(state.isDirty, isFalse);
      state.addRelation(_link(WorkItemRelation.relatedRel, 15547));
      final ops = state.buildOps();
      expect(
        ops
            .where((op) => op['path'] == '/relations/-')
            .map((op) => op['value']),
        [
          {'rel': WorkItemRelation.parentRel, 'url': '$_base/15546'},
          {'rel': WorkItemRelation.relatedRel, 'url': '$_base/15547'},
        ],
      );
      // State and Reason are still the server's on a new item.
      expect(
        ops.any((op) => '${op['path']}'.contains('System.State')),
        isFalse,
      );
      state.dispose();
    });

    test('a relation dropped before Create never reaches the patch', () {
      final state = WorkItemFormState(
        spec: spec,
        initialValues: const {'System.Title': 'x'},
        newRelations: [_link(WorkItemRelation.parentRel, 15546)],
      );
      state.removeRelation(_link(WorkItemRelation.parentRel, 15546));
      expect(
        state.buildOps().any((op) => op['path'] == '/relations/-'),
        isFalse,
      );
      state.dispose();
    });
  });

  group('the Links section', () {
    LinkSource source({List<WorkItem> results = const []}) => LinkSource(
      resolve: (ids) async => [for (final id in ids) _target(id)],
      search: (text) async => results,
      open: (_) {},
    );

    Future<WorkItemFormState> pump(
      WidgetTester tester, {
      List<WorkItemRelation>? relations,
      LinkSource? with_,
    }) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = editState(relations: relations);
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LinksSection(state: state, source: with_ ?? source()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('it heads each group and resolves every row', (tester) async {
      final state = await pump(tester);

      expect(find.text('Parent'), findsOneWidget);
      expect(find.text('Children (2)'), findsOneWidget);
      expect(find.text('Related'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('#15550 target 15550'), findsOneWidget);
      expect(find.text('Task · New'), findsWidgets);
      expect(find.text('Add link'), findsOneWidget);
      state.dispose();
    });

    testWidgets('an empty list says so', (tester) async {
      final state = await pump(tester, relations: const []);

      expect(find.text('No links yet.'), findsOneWidget);
      expect(find.text('Add link'), findsOneWidget);
      state.dispose();
    });

    testWidgets('a target that cannot be read shows as its id', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = editState(
        relations: [_link(WorkItemRelation.relatedRel, 99999)],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Scaffold(
            body: LinksSection(
              state: state,
              source: LinkSource(
                resolve: (_) async => throw Exception('no access'),
                search: (_) async => const [],
                open: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('#99999'), findsOneWidget);
      state.dispose();
    });

    testWidgets('the trailing remove drops the row', (tester) async {
      final state = await pump(
        tester,
        relations: [_link(WorkItemRelation.relatedRel, 15547)],
      );

      expect(find.text('#15547 target 15547'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove link'));
      await tester.pumpAndSettle();

      expect(find.text('#15547 target 15547'), findsNothing);
      expect(state.removedRelationKeys, hasLength(1));
      state.dispose();
    });

    testWidgets('the sheet searches and multi-selects children', (
      tester,
    ) async {
      final state = await pump(
        tester,
        relations: const [],
        with_: source(results: [_target(15547), _target(15550)]),
      );

      await tester.tap(find.text('Add link'));
      await tester.pumpAndSettle();
      expect(find.text('Add link'), findsWidgets);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Child'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'phase2');
      await tester.pumpAndSettle();

      expect(find.text('#15547 target 15547'), findsOneWidget);
      await tester.tap(find.text('#15547 target 15547'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add 1 child'));
      await tester.pumpAndSettle();

      expect(state.linkRelations.single.rel, WorkItemRelation.childRel);
      expect(state.linkRelations.single.targetId, 15547);
      state.dispose();
    });

    testWidgets('a single-valued kind picks on the tap', (tester) async {
      final state = await pump(
        tester,
        relations: const [],
        with_: source(results: [_target(15546, type: 'User Story')]),
      );

      await tester.tap(find.text('Add link'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Parent'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '15546');
      await tester.pumpAndSettle();
      await tester.tap(find.text('#15546 target 15546'));
      await tester.pumpAndSettle();

      expect(state.linkRelations.single.rel, WorkItemRelation.parentRel);
      state.dispose();
    });
  });
}
