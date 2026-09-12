import 'dart:convert';
import 'dart:io';

import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:boardhop/features/work_items/form/controls/boolean_control.dart';
import 'package:boardhop/features/work_items/form/controls/date_control.dart';
import 'package:boardhop/features/work_items/form/controls/links_section.dart';
import 'package:boardhop/features/work_items/form/controls/picklist_control.dart';
import 'package:boardhop/features/work_items/form/controls/rich_text_control.dart';
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

    testWidgets('a board column shows the state the card will land in', (
      tester,
    ) async {
      // The form opens with the column's state, which stays read-only: only
      // the initial state is legal on a create (spike w18).
      final state = newState(values: {'System.State': 'Active'});
      await _pump(tester, state);
      expect(find.text('Active'), findsOneWidget);
      expect(
        find.byTooltip('Created in New, then moved to Active'),
        findsOneWidget,
      );
      expect(
        state.buildOps().any((op) => '${op['path']}'.endsWith('System.State')),
        isFalse,
      );
      state.dispose();
    });

    testWidgets('Add child names the parent under the type chip', (
      tester,
    ) async {
      final state = WorkItemFormState(
        spec: spec,
        initialValues: {'System.State': spec.initialState},
        link: const FormLinkTarget(
          id: 15546,
          title: 'Phase 2 story',
          rel: WorkItemRelation.parentRel,
          url: 'https://dev.azure.com/o/p/_apis/wit/workItems/15546',
        ),
      );
      await _pump(tester, state);
      expect(find.text('Child of #15546 - Phase 2 story'), findsOneWidget);
      state.dispose();
    });

    testWidgets('Add related says so instead', (tester) async {
      final state = WorkItemFormState(
        spec: spec,
        initialValues: {'System.State': spec.initialState},
        link: const FormLinkTarget(
          id: 15503,
          title: 'Login fails',
          rel: WorkItemRelation.relatedRel,
          url: 'https://dev.azure.com/o/p/_apis/wit/workItems/15503',
        ),
      );
      await _pump(tester, state);
      expect(find.text('Related to #15503 - Login fails'), findsOneWidget);
      state.dispose();
    });

    testWidgets('a template fills the title and keeps its trailing space', (
      tester,
    ) async {
      // Spike w20's template: `System.Title` is "[template] ", which the
      // user types on the end of.
      final state = newState(
        values: {
          'System.Title': '[template] ',
          'Microsoft.VSTS.Common.Priority': '1',
        },
      );
      await _pump(tester, state);
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, '[template] ');
      expect(field.controller?.selection.baseOffset, '[template] '.length);
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
        // The Links and Attachments pages follow, each one panel whose own
        // label is dropped because the page heading already says it
        // (phase 5).
        '',
        '',
      ]);
      // The panels of the Details page: Deployment and Development carry
      // Git and pipeline artifacts the service owns, Related Work is a real
      // link list (phase 5).
      expect(
        [
          for (final g in state.groups)
            if (g.isPanel) '${g.label}:${g.panel.name}',
        ],
        const [
          'Deployment:external',
          'Development:external',
          'Related Work:links',
          ':links',
          ':attachments',
        ],
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

    test('the phone stacks one link list, not two', () {
      final state = newState();
      // The layout carries both: the Details page's "Related Work" panel
      // and the Links page's own.
      expect(
        [
          for (final g in state.groups)
            if (g.panel == FormPanelKind.links) g.label,
        ],
        const ['Related Work', ''],
      );
      // Stacked on one screen they were two identical editable lists, so
      // the phone keeps the Links page's alone (iOS walkthrough).
      expect(
        [
          for (final g in state.stackedGroups)
            if (g.panel == FormPanelKind.links) g.pageLabel,
        ],
        const ['Links'],
      );
      // The tablet keeps both: they are on separate tabs.
      expect(state.pages.map((p) => p.label).toList(), const [
        'Details',
        'Links',
        'Attachments',
      ]);
      state.dispose();
    });

    testWidgets('the phone form renders the links section once', (
      tester,
    ) async {
      final state = newState();
      await _pump(tester, state, size: const Size(400, 4000));

      expect(find.byType(LinksSection), findsOneWidget);
      expect(find.text('Add link'), findsOneWidget);
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
      // The panels the service owns say so; Related Work is a real link
      // list (phase 5). The Links and Attachments pages sit further down
      // the lazy list and have their own tests.
      expect(find.text('Managed in Azure DevOps'), findsNWidgets(2));
      expect(find.byType(LinksSection), findsWidgets);
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

  group('the tablet arrangement', () {
    final storySpec = _specFor('user_story');

    test('the layout keeps the web sections as columns', () {
      final state = WorkItemFormState(spec: spec);
      // Details, then the Links and Attachments pages (phase 5).
      expect(state.pages.map((p) => p.label).toList(), const [
        'Details',
        'Links',
        'Attachments',
      ]);
      final columns = state.pages.first.columns;
      expect(columns.map((c) => c.percentWidth).toList(), const [50, 50]);
      expect(columns.first.groups.map((g) => g.label).toList(), const [
        'Repro Steps',
        'System Info',
      ]);
      expect(columns.last.groups.map((g) => g.label).toList(), const [
        'Planning',
        'Effort (Hours)',
        'Deployment',
        'Development',
        'Related Work',
        'System Info',
      ]);
      // The phone order is those columns flattened, as phase 1 settled,
      // with the Links and Attachments panels under their own headings.
      expect(state.groups.map((g) => g.label).toList(), [
        ...columns.first.groups.map((g) => g.label),
        ...columns.last.groups.map((g) => g.label),
        '',
        '',
      ]);
      state.dispose();
    });

    testWidgets('1000 dp wide puts the sections next to each other', (
      tester,
    ) async {
      final state = newState();
      await _pump(tester, state, size: const Size(1000, 800));

      final left = tester.getTopLeft(find.text('Repro Steps').first);
      final right = tester.getTopLeft(find.text('Planning').first);
      expect(right.dx, greaterThan(left.dx + 200));
      // The first card of each column starts on the same line.
      expect((right.dy - left.dy).abs(), lessThan(1));
      state.dispose();
    });

    testWidgets('500 dp wide keeps one column', (tester) async {
      final state = newState();
      await _pump(tester, state, size: const Size(500, 2400));

      final left = tester.getTopLeft(find.text('Repro Steps').first);
      final planning = tester.getTopLeft(find.text('Planning').first);
      expect(planning.dx, left.dx);
      expect(planning.dy, greaterThan(left.dy));
      state.dispose();
    });

    testWidgets('a custom page becomes a tab', (tester) async {
      final state = WorkItemFormState(spec: _withCustomPage(storySpec));
      await _pump(tester, state, size: const Size(1000, 800));

      expect(find.byType(TabBar), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Details'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'QA'), findsOneWidget);
      state.dispose();
    });
  });

  group('the rich text control', () {
    final storySpec = _specFor('user_story');

    WorkItemFormState storyState({Map<String, String> formats = const {}}) =>
        WorkItemFormState(
          spec: storySpec,
          initialValues: {'System.State': storySpec.initialState},
          formats: formats,
        );

    testWidgets('an empty description shows the placeholder once', (
      tester,
    ) async {
      final state = storyState();
      await _pump(tester, state);

      expect(find.byType(RichTextControl), findsWidgets);
      expect(find.text('Add description…'), findsOneWidget);
      // The card title says "Description"; the control does not repeat it.
      expect(find.text('Description'), findsOneWidget);
      state.dispose();
    });

    testWidgets('Done writes the editor content back into the form', (
      tester,
    ) async {
      // Markdown, so the test never has to boot the editor's WebView; the
      // Done path is the same one the HTML editor takes.
      final state = storyState(formats: {'System.Description': 'markdown'});
      await _pump(tester, state);

      await tester.tap(find.text('Add description…'));
      await tester.pumpAndSettle();
      expect(find.byType(RichTextEditor), findsOneWidget);
      // The format choice is offered on a new item's description.
      expect(
        find.widgetWithText(SegmentedButton<String>, 'Markdown'),
        findsOneWidget,
      );

      await tester.enterText(
        find.descendant(
          of: find.byType(RichTextEditor),
          matching: find.byType(TextField),
        ),
        '**bold** list',
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(state.value('System.Description'), '**bold** list');
      expect(state.isMarkdown('System.Description'), isTrue);
      final ops = state.buildOps();
      Object? valueOf(String path) => ops.firstWhere(
        (op) => op['path'] == path,
        orElse: () => const {},
      )['value'];
      // Markdown rides on the create patch as the format op (spike w01)
      // and the text is never escaped into HTML.
      expect(valueOf('/fields/System.Description'), '**bold** list');
      expect(valueOf('/multilineFieldsFormat/System.Description'), 'Markdown');
      state.dispose();
    });

    test('HTML from the editor goes into the patch as it stands', () {
      final state = storyState();
      state.setRichValue(
        'System.Description',
        '<div>a &amp; b<br><b>bold</b></div>',
      );
      final ops = state.buildOps();
      Object? valueOf(String path) => ops.firstWhere(
        (op) => op['path'] == path,
        orElse: () => const {},
      )['value'];
      expect(
        valueOf('/fields/System.Description'),
        '<div>a &amp; b<br><b>bold</b></div>',
      );
      // No format op: HTML is the default (spike w01).
      expect(ops.every((op) => '${op['path']}'.startsWith('/fields/')), isTrue);
      state.dispose();
    });
  });
}

/// The stock scratch types have one page; this adds a custom one so the
/// tablet tab bar can be checked.
FormSpec _withCustomPage(FormSpec spec) {
  final json = spec.toJson();
  (json['layout'] as Map)['pages'] = [
    ...(spec.layout.toJson()['pages'] as List),
    {
      'label': 'QA',
      'kind': 'custom',
      'sections': [
        {
          'percentWidth': 100,
          'groups': [
            {
              'label': 'QA',
              'controls': [
                {
                  'field': 'Microsoft.VSTS.Common.Risk',
                  'label': 'Risk',
                  'type': 'FieldControl',
                },
              ],
            },
          ],
        },
      ],
    },
  ];
  return FormSpec.fromJson(json.cast<String, dynamic>());
}
