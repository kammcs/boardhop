import 'dart:convert';
import 'dart:io';

import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:boardhop/features/work_items/form/work_item_form_state.dart';
import 'package:boardhop/features/work_items/widgets/work_item_field_groups.dart';
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

/// The scratch User Story with CloudCover 2.0's three custom fields grafted
/// into its layout the way spike s26 found them: QA Story Points and QA
/// Assignee inside Planning, Testing Plan as a group of its own.
FormSpec _customizedUserStory() {
  final typeJson = _fixture('scratch_user_story_type.json');
  final xml = typeJson['xmlForm'] as String;

  const qaControls =
      '<Control Label="QA Story Points" LabelPosition="Top" '
      'FieldName="Custom.QAStoryPoints" Type="FieldControl" />'
      '<Control Label="QA Assignee" LabelPosition="Top" '
      'FieldName="Custom.QAAssignee" Type="FieldControl" />';
  const testingPlan =
      '<Group Label="Testing Plan"><Column PercentWidth="100">'
      '<Control Label="" LabelPosition="Top" FieldName="Custom.TestingPlan" '
      'Type="HtmlFieldControl" /></Column></Group>';

  const planningAnchor =
      '<Control Label="Story Points" LabelPosition="Top" '
      'FieldName="Microsoft.VSTS.Scheduling.StoryPoints" Type="FieldControl" '
      'Margin="(0,0,0,10)" />';
  if (!xml.contains(planningAnchor)) {
    throw StateError('the User Story fixture no longer holds Story Points');
  }
  final acceptanceGroup = RegExp(
    r'<Group Label="Acceptance Criteria">.*?</Group>',
    dotAll: true,
  ).firstMatch(xml)!.group(0)!;

  typeJson['xmlForm'] = xml
      .replaceFirst(planningAnchor, '$planningAnchor$qaControls')
      .replaceFirst(acceptanceGroup, '$acceptanceGroup$testingPlan');

  final orgFields = {
    for (final f in _values(_fixture('org_fields.json')))
      (f['referenceName'] as String): FieldSpec.fromOrgField(f),
    'Custom.QAStoryPoints': FieldSpec.fromOrgField(const {
      'referenceName': 'Custom.QAStoryPoints',
      'name': 'QA Story Points',
      'type': 'double',
    }),
    'Custom.QAAssignee': FieldSpec.fromOrgField(const {
      'referenceName': 'Custom.QAAssignee',
      'name': 'QA Assignee',
      'type': 'string',
      'isIdentity': true,
    }),
    'Custom.TestingPlan': FieldSpec.fromOrgField(const {
      'referenceName': 'Custom.TestingPlan',
      'name': 'Testing Plan',
      'type': 'html',
    }),
  };

  return WorkItemFormRepository.buildSpec(
    typeJson: typeJson,
    typeFields: [
      ..._values(_fixture('scratch_user_story_fields.json')),
      const {
        'referenceName': 'Custom.QAStoryPoints',
        'name': 'QA Story Points',
      },
      const {'referenceName': 'Custom.QAAssignee', 'name': 'QA Assignee'},
      const {'referenceName': 'Custom.TestingPlan', 'name': 'Testing Plan'},
    ],
    orgFields: orgFields,
  );
}

/// An item the way `$expand=all` returns it: the layout's fields with a
/// value, and the empty ones simply absent (Risk, Description).
WorkItem _item({Map<String, dynamic> extra = const {}}) => WorkItem(
  id: 15303,
  rev: 35,
  fields: {
    'System.WorkItemType': 'User Story',
    'System.Title': 'Triage Agent',
    'System.State': 'Active',
    'System.Reason': 'Moved to state Active',
    'System.AreaPath': r'Scratch\Area',
    'System.IterationPath': r'Scratch\Iteration 1',
    'System.Tags': 'product-discovery',
    'System.CreatedDate': '2026-08-29T16:21:59.993Z',
    'System.ChangedDate': '2026-09-11T21:27:16.147Z',
    'Microsoft.VSTS.Common.Priority': 2,
    'Microsoft.VSTS.Common.ValueArea': 'Business',
    'Microsoft.VSTS.Common.AcceptanceCriteria':
        '<h4>Configuration</h4><ul><li>A system setting</li></ul>',
    'Microsoft.VSTS.Scheduling.StoryPoints': 5.0,
    'Custom.QAStoryPoints': 1.0,
    'Custom.QAAssignee': const {
      'displayName': 'Karen Teran',
      'uniqueName': 'karen@example.com',
    },
    'Custom.TestingPlan': '<p>All ten stages are built</p>',
    ...extra,
  },
  multilineFieldsFormat: const {
    'Microsoft.VSTS.Common.AcceptanceCriteria': 'html',
    'Custom.TestingPlan': 'html',
  },
);

void main() {
  final spec = _customizedUserStory();

  group('the detail page groups', () {
    test('follow the web order and hold only the filled fields', () {
      final groups = detailGroupsFor(spec, _item());

      expect(
        groups.map((g) => g.label).toList(),
        // Description is empty on this item, so its group is left out.
        // Related Work has its own section on the page and never appears,
        // but Deployment and Development do, as the line of text that says
        // Azure DevOps owns them.
        [
          'Acceptance Criteria',
          'Testing Plan',
          'Planning',
          'Classification',
          'Deployment',
          'Development',
        ],
      );
      final planning = groups.firstWhere((g) => g.label == 'Planning');
      expect(planning.controls.map((c) => c.fieldReferenceName).toList(), [
        'Microsoft.VSTS.Scheduling.StoryPoints',
        'Custom.QAStoryPoints',
        'Custom.QAAssignee',
      ]);
      expect(
        groups.where((g) => g.isPanel).map((g) => g.panel).toSet(),
        {FormPanelKind.external},
      );
      expect(groups.any((g) => g.pageLabel != null), isFalse);
    });

    test('leave out what the header and the facts rows already show', () {
      final refs = {
        for (final group in detailGroupsFor(spec, _item()))
          for (final control in group.controls) control.fieldReferenceName,
      };

      // Priority is the header's own chip, Risk has no value, and the
      // header and facts own the rest.
      expect(refs, isNot(contains('Microsoft.VSTS.Common.Priority')));
      expect(refs, isNot(contains('Microsoft.VSTS.Common.Risk')));
      for (final reference in [
        'System.Title',
        'System.State',
        'System.Reason',
        'System.AssignedTo',
        'System.AreaPath',
        'System.IterationPath',
        'System.Tags',
        'System.Id',
        'System.CreatedDate',
        'System.ChangedDate',
      ]) {
        expect(refs, isNot(contains(reference)), reason: reference);
      }
    });

    test(
      'an item with nothing filled has only panels, so the page falls back',
      () {
        final bare = WorkItem(
          id: 1,
          rev: 1,
          fields: const {
            'System.WorkItemType': 'User Story',
            'System.Title': 'Bare',
            'System.State': 'New',
            'Microsoft.VSTS.Common.Priority': 2,
          },
        );

        final groups = detailGroupsFor(spec, bare);
        // Only the service's own panels, which is what the page reads as
        // "nothing of the layout to show" before it falls back.
        expect(groups.every((g) => g.isPanel), isTrue);
        expect(
          groups.map((g) => g.label).toList(),
          ['Deployment', 'Development'],
        );
      },
    );

    test('a field the layout does not carry stays hidden', () {
      final groups = detailGroupsFor(
        spec,
        _item(extra: const {'Custom.NotOnTheForm': 'hello'}),
      );
      final refs = {
        for (final group in groups)
          for (final control in group.controls) control.fieldReferenceName,
      };

      expect(refs, isNot(contains('Custom.NotOnTheForm')));
    });
  });

  group('field values', () {
    FieldSpec fieldOf(String reference) => spec.fields[reference]!;

    test('a double loses its trailing zero', () {
      expect(formatFieldValue(fieldOf('Custom.QAStoryPoints'), 1.0), '1');
      expect(formatFieldValue(fieldOf('Custom.QAStoryPoints'), 1.5), '1.5');
      expect(
        formatFieldValue(fieldOf('Microsoft.VSTS.Scheduling.StoryPoints'), 5),
        '5',
      );
    });

    test('an identity shows its display name', () {
      expect(
        formatFieldValue(fieldOf('Custom.QAAssignee'), const {
          'displayName': 'Karen Teran',
        }),
        'Karen Teran',
      );
      expect(
        formatFieldValue(
          fieldOf('Custom.QAAssignee'),
          const IdentityRef(displayName: 'Kelly Kamm'),
        ),
        'Kelly Kamm',
      );
    });

    test('a boolean is Yes or No and a date is absolute', () {
      expect(formatFieldValue(null, true), 'Yes');
      expect(formatFieldValue(null, false), 'No');
      const due = FieldSpec(
        referenceName: 'Custom.QADate',
        name: 'QA date',
        type: FieldType.dateTime,
      );
      expect(
        formatFieldValue(due, '2026-09-12T18:30:00Z'),
        contains('Sep 12, 2026'),
      );
      expect(formatFieldValue(null, null), '');
    });

    test('an emptied HTML field counts as empty, an image does not', () {
      expect(hasRichContent('<div><br></div>'), isFalse);
      expect(hasRichContent('<div>&nbsp;</div>'), isFalse);
      expect(hasRichContent('<div><img src="x"></div>'), isTrue);
      expect(hasRichContent('<p>All ten stages</p>'), isTrue);
    });
  });

  group('the rendered groups', () {
    Future<void> pump(
      WidgetTester tester, {
      Size size = const Size(400, 2400),
    }) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final item = _item();
      return tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: WorkItemFieldGroups(
                spec: spec,
                item: item,
                groups: detailGroupsFor(spec, item),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('show the custom fields under their own group labels', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Acceptance Criteria'), findsOneWidget);
      expect(find.text('Testing Plan'), findsOneWidget);
      expect(find.text('Planning'), findsOneWidget);
      expect(find.text('Classification'), findsOneWidget);

      // The long-text fields as rich text, not as markup.
      expect(
        find.textContaining('All ten stages are built', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('A system setting', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('<p>', findRichText: true), findsNothing);

      // The rows: label on the left, the formatted value on the right.
      expect(find.text('QA Story Points'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('QA Assignee'), findsOneWidget);
      expect(find.text('Karen Teran'), findsOneWidget);
      expect(find.text('Story Points'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('Business'), findsOneWidget);

      // The header's chip owns Priority; nothing repeats it here.
      expect(find.text('Priority'), findsNothing);
      expect(find.text('Risk'), findsNothing);
    });

    testWidgets('say who owns Development and Deployment', (tester) async {
      await pump(tester);

      // The form says it; the detail page did not, so the two groups were
      // simply missing there (iOS walkthrough).
      expect(find.text('Deployment'), findsOneWidget);
      expect(find.text('Development'), findsOneWidget);
      expect(find.text('Managed in Azure DevOps'), findsNWidgets(2));
      // The editable panels keep their own sections on the page.
      expect(find.text('Related Work'), findsNothing);
    });

    testWidgets('read the same at the expanded breakpoint', (tester) async {
      await pump(tester, size: const Size(900, 2400));

      expect(find.text('Testing Plan'), findsOneWidget);
      expect(find.text('QA Assignee'), findsOneWidget);
      expect(find.text('Karen Teran'), findsOneWidget);
    });
  });
}
