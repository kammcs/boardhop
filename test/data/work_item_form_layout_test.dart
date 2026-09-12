import 'dart:convert';
import 'dart:io';

import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixtures recorded from the scratch project "DevOps Mobile App" by the
/// read-only spike `research/spikes/s27_form_fixtures.py`.
Map<String, dynamic> fixture(String name) =>
    (jsonDecode(File('test/fixtures/forms/$name').readAsStringSync()) as Map)
        .cast<String, dynamic>();

void main() {
  group('FormLayout from a real xmlForm (scratch Bug)', () {
    final type = WorkItemType.fromJson(fixture('scratch_bug_type.json'));
    final layout = type.form!;

    test('the raw XML is parsed and then dropped', () {
      expect(fixture('scratch_bug_type.json')['xmlForm'], isA<String>());
      expect(type.toJson().containsKey('xmlForm'), isFalse);
      expect(type.toJson()['layout'], isA<Map<String, dynamic>>());
    });

    test('header holds the controls above the tabs, spacers dropped', () {
      expect(layout.header.map((c) => c.fieldReferenceName).toList(), const [
        'System.Title',
        'System.Id',
        'System.AssignedTo',
        'System.State',
        'System.Reason',
        'System.AreaPath',
        'System.IterationPath',
        'System.ChangedDate',
      ]);
      expect(
        layout.header.every((c) => c.controlType != FormControlType.label),
        isTrue,
      );
    });

    test('labels lose their Windows accelerator', () {
      final assigned = layout.header[2];
      expect(assigned.label, 'Assigned To');
      expect(assigned.emptyText, 'Unassigned');
      expect(layout.header[3].label, 'State');
      expect(layout.header[5].label, 'Area');
      expect(layout.header[6].label, 'Iteration');
    });

    test('read-only and control types come from the XML', () {
      final changed = layout.header.last;
      expect(changed.controlType, FormControlType.dateTime);
      expect(changed.readOnly, isTrue);
      expect(layout.header.first.emptyText, 'Enter title here');
    });

    test('four tabs with their kinds', () {
      expect(layout.pages.map((p) => p.label).toList(), const [
        'Details',
        'History',
        'Links',
        'Attachments',
      ]);
      expect(layout.pages.map((p) => p.kind).toList(), const [
        FormPageKind.details,
        FormPageKind.history,
        FormPageKind.links,
        FormPageKind.attachments,
      ]);
      expect(layout.detailsPage, layout.pages.first);
    });

    test('the Details page keeps the two top-level columns', () {
      final details = layout.detailsPage!;
      expect(details.sections.length, 2);
      expect(details.sections.map((s) => s.percentWidth).toList(), [50, 50]);
    });

    test('labeled groups in web order, wrappers collapsed', () {
      final details = layout.detailsPage!;
      expect(details.sections[0].groups.map((g) => g.label).toList(), const [
        'Repro Steps',
        'System Info',
      ]);
      expect(details.sections[1].groups.map((g) => g.label).toList(), const [
        'Planning',
        'Effort (Hours)',
        'Deployment',
        'Development',
        'Related Work',
        'System Info',
      ]);
      // Every group of the Details page is a labeled one: the anonymous
      // wrapper groups and the 100 %/25 % columns are gone.
      expect(
        details.sections.every(
          (s) => s.groups.every((g) => g.label.isNotEmpty),
        ),
        isTrue,
      );
    });

    test('controls keep their order and type inside a group', () {
      final planning = layout.detailsPage!.sections[1].groups.first;
      expect(
        planning.controls.map((c) => c.fieldReferenceName).toList(),
        const [
          'Microsoft.VSTS.Common.ResolvedReason',
          'Microsoft.VSTS.Scheduling.StoryPoints',
          'Microsoft.VSTS.Common.Priority',
          'Microsoft.VSTS.Common.Severity',
          'Microsoft.VSTS.Common.Activity',
        ],
      );
      expect(
        planning.controls.every((c) => c.controlType == FormControlType.field),
        isTrue,
      );
      final repro =
          layout.detailsPage!.sections[0].groups.first.controls.single;
      expect(repro.controlType, FormControlType.html);
      expect(repro.fieldReferenceName, 'Microsoft.VSTS.TCM.ReproSteps');
    });

    test('the panels are recognised, not mistaken for fields', () {
      final right = layout.detailsPage!.sections[1].groups;
      final deployments = right[2].controls.single;
      final development = right[3].controls.single;
      expect(deployments.controlType, FormControlType.deployments);
      expect(development.controlType, FormControlType.links);
      expect(development.isPanel, isTrue);
      expect(layout.pages[1].controls.single.controlType, FormControlType.log);
      expect(
        layout.pages[2].controls.single.controlType,
        FormControlType.links,
      );
      expect(
        layout.pages[3].controls.single.controlType,
        FormControlType.attachments,
      );
    });

    test('a page with no labeled group keeps one anonymous group', () {
      final history = layout.pages[1];
      expect(history.sections.single.groups.single.label, '');
      expect(history.controls.single.fieldReferenceName, 'System.History');
    });

    test('round-trips through JSON for the cache', () {
      final again = FormLayout.fromJson(layout.toJson());
      expect(again, layout);
    });
  });

  group('FormLayout (scratch User Story)', () {
    final layout = WorkItemType.fromJson(
      fixture('scratch_user_story_type.json'),
    ).form!;

    test('its own groups in web order', () {
      final details = layout.detailsPage!;
      expect(details.sections.map((s) => s.percentWidth).toList(), [50, 50]);
      expect(details.sections[0].groups.map((g) => g.label).toList(), const [
        'Description',
        'Acceptance Criteria',
      ]);
      expect(details.sections[1].groups.map((g) => g.label).toList(), const [
        'Planning',
        'Classification',
        'Deployment',
        'Development',
        'Related Work',
      ]);
    });

    test('has the same four tabs', () {
      expect(layout.pages.map((p) => p.kind).toList(), const [
        FormPageKind.details,
        FormPageKind.history,
        FormPageKind.links,
        FormPageKind.attachments,
      ]);
    });
  });

  group('FormLayout.tryParse', () {
    test('null for missing, empty or broken XML', () {
      expect(FormLayout.tryParse(null), isNull);
      expect(FormLayout.tryParse('   '), isNull);
      expect(FormLayout.tryParse('<FORM><Layout'), isNull);
      expect(FormLayout.tryParse('<FORM></FORM>'), isNull);
    });

    test('a custom tab becomes a custom page', () {
      final layout = FormLayout.tryParse(
        '<FORM><Layout>'
        '<Group><Column PercentWidth="100">'
        '<Control Label="Title" FieldName="System.Title" Type="FieldControl" />'
        '</Column></Group>'
        '<TabGroup>'
        '<Tab Label="Details"><Group><Column PercentWidth="100">'
        '<Group Label="Planning"><Column PercentWidth="100">'
        '<Control Label="Effort" FieldName="Custom.Effort" Type="FieldControl" />'
        '</Column></Group></Column></Group></Tab>'
        '<Tab Label="Testing"><Group><Column PercentWidth="100">'
        '<Group Label="Plan"><Column PercentWidth="100">'
        '<Control Label="Plan" FieldName="Custom.TestingPlan" Type="HtmlFieldControl" />'
        '</Column></Group></Column></Group></Tab>'
        '</TabGroup></Layout></FORM>',
      )!;
      expect(layout.header.single.fieldReferenceName, 'System.Title');
      expect(layout.pages.map((p) => p.kind).toList(), const [
        FormPageKind.details,
        FormPageKind.custom,
      ]);
      expect(
        layout
            .pages[1]
            .sections
            .single
            .groups
            .single
            .controls
            .single
            .fieldReferenceName,
        'Custom.TestingPlan',
      );
    });

    test('an ampersand in a label survives as one', () {
      expect(FormControl.stripAccelerator('R&&D'), 'R&D');
      expect(FormControl.stripAccelerator('Assi&gned To'), 'Assigned To');
      expect(FormControl.stripAccelerator(''), '');
      expect(FormControl.stripAccelerator(null), isNull);
    });
  });
}
