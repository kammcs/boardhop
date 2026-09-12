import 'dart:convert';
import 'dart:io';

import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fixture(String name) =>
    (jsonDecode(File('test/fixtures/forms/$name').readAsStringSync()) as Map)
        .cast<String, dynamic>();

List<Map<String, dynamic>> _values(Map<String, dynamic> json) => [
  for (final v in (json['value'] as List?) ?? const [])
    if (v is Map) v.cast<String, dynamic>(),
];

void main() {
  final orgFields = {
    for (final f in _values(_fixture('org_fields.json')))
      (f['referenceName'] as String): FieldSpec.fromOrgField(f),
  };

  FormSpec specFor(String type, {bool dropXmlForm = false}) {
    final typeJson = _fixture('scratch_${type}_type.json');
    if (dropXmlForm) typeJson.remove('xmlForm');
    return WorkItemFormRepository.buildSpec(
      typeJson: typeJson,
      typeFields: _values(_fixture('scratch_${type}_fields.json')),
      orgFields: orgFields,
    );
  }

  group('FormSpec assembled from the scratch Bug', () {
    final spec = specFor('bug');

    test('comes from the xmlForm and keeps the type', () {
      expect(spec.source, FormSource.xmlForm);
      expect(spec.type.name, 'Bug');
      expect(spec.type.referenceName, 'Microsoft.VSTS.WorkItemTypes.Bug');
      expect(spec.type.color, 'CC293D');
      expect(spec.fields.length, greaterThan(60));
    });

    test('field types come from the org list, rules from the type', () {
      expect(spec.fields['System.Title']!.type, FieldType.string);
      expect(spec.fields['System.Title']!.alwaysRequired, isTrue);
      expect(spec.fields['System.Description']!.type, FieldType.html);
      expect(spec.fields['System.AreaPath']!.type, FieldType.treePath);
      expect(spec.fields['System.History']!.type, FieldType.history);
      expect(spec.fields['System.BoardColumnDone']!.type, FieldType.boolean);
      expect(spec.fields['System.BoardColumnDone']!.readOnly, isTrue);
      expect(
        spec.fields['Microsoft.VSTS.Common.Priority']!.type,
        FieldType.integer,
      );
      expect(
        spec.fields['Microsoft.VSTS.Scheduling.StoryPoints']!.type,
        FieldType.decimal,
      );
      expect(spec.fields['System.ChangedDate']!.type, FieldType.dateTime);
    });

    test('identity fields are flagged even though their values are empty', () {
      final assigned = spec.fields['System.AssignedTo']!;
      expect(assigned.isIdentity, isTrue);
      expect(assigned.allowedValues, isEmpty);
      expect(assigned.allowedIdentities, isEmpty);
      expect(assigned.dependentFields, contains('System.State'));
    });

    test('picklists, defaults and help text survive', () {
      final priority = spec.fields['Microsoft.VSTS.Common.Priority']!;
      expect(priority.allowedValues, ['1', '2', '3', '4']);
      expect(priority.defaultValue, '2');
      expect(priority.helpText, isNotNull);
      expect(priority.hasAllowedValues, isTrue);
      expect(spec.fields['System.State']!.allowedValues, [
        'Active',
        'Closed',
        'New',
        'Resolved',
      ]);
    });

    test('required fields drop the ids the server derives', () {
      final required = spec.requiredFields.map((f) => f.referenceName).toSet();
      expect(required, contains('System.Title'));
      expect(required, contains('System.State'));
      expect(required, isNot(contains('System.AreaId')));
      expect(required, isNot(contains('System.IterationId')));
    });

    test('initial state and transitions', () {
      expect(spec.initialState, 'New');
      expect(spec.transitionsFrom(''), ['New']);
      expect(
        spec.transitionsFrom('Active'),
        containsAll(<String>['Resolved', 'Closed', 'New']),
      );
      expect(spec.transitionsFrom('Nowhere'), isEmpty);
    });

    test('controls of the Details page resolve to their fields', () {
      final controls = spec.controlsOnDetails;
      expect(controls, isNotEmpty);
      final repro = controls.first;
      expect(spec.fieldFor(repro)!.name, 'Repro Steps');
      // The panels (Development, Related Work, Deployments) are not fields.
      final development = controls.firstWhere(
        (c) => c.controlType == FormControlType.links,
      );
      expect(spec.fieldFor(development), isNull);
    });

    test('round-trips through JSON for the 24 h cache', () {
      final again = FormSpec.fromJson(
        (jsonDecode(jsonEncode(spec.toJson())) as Map).cast<String, dynamic>(),
      );
      expect(again.source, spec.source);
      expect(again.layout, spec.layout);
      expect(again.type, spec.type);
      expect(again.fields.length, spec.fields.length);
      expect(
        again.fields['Microsoft.VSTS.Common.Priority'],
        spec.fields['Microsoft.VSTS.Common.Priority'],
      );
      expect(again, spec);
    });
  });

  group('the field-list fallback', () {
    final spec = specFor('bug', dropXmlForm: true);

    test('kicks in when the xmlForm is gone', () {
      expect(spec.source, FormSource.fieldList);
      expect(spec.layout.pages.single.kind, FormPageKind.details);
      expect(spec.layout.header, isEmpty);
    });

    test('required first, then the common fields, then prefixes', () {
      final labels = spec.layout.pages.single.sections.single.groups
          .map((g) => g.label)
          .toList();
      expect(labels.first, 'Required');
      expect(labels[1], 'Details');
      expect(labels.last, 'System');
      // Microsoft.VSTS groups are named after the middle segment.
      expect(labels, containsAll(<String>['Common', 'Scheduling', 'Build']));
    });

    test('the Required group holds only fillable required fields', () {
      final required = spec.layout.pages.single.sections.single.groups.first;
      expect(required.controls.map((c) => c.fieldReferenceName).toList(), [
        'System.Title',
        'System.State',
        // The stock Agile Bug marks Value Area required too.
        'Microsoft.VSTS.Common.ValueArea',
      ]);
    });

    test('the Details group is in the documented order', () {
      final details = spec.layout.pages.single.sections.single.groups[1];
      expect(details.controls.map((c) => c.fieldReferenceName).toList(), const [
        'System.Description',
        'Microsoft.VSTS.TCM.ReproSteps',
        'Microsoft.VSTS.Common.Priority',
        'Microsoft.VSTS.Common.Severity',
        'Microsoft.VSTS.Scheduling.StoryPoints',
        'Microsoft.VSTS.Scheduling.RemainingWork',
        'Microsoft.VSTS.Common.Activity',
      ]);
    });

    test('read-only, bookkeeping and history fields are skipped', () {
      final references = {
        for (final c in spec.layout.pages.single.controls) c.fieldReferenceName,
      };
      expect(references, isNot(contains('System.Id')));
      expect(references, isNot(contains('System.Rev')));
      expect(references, isNot(contains('System.AreaId')));
      expect(references, isNot(contains('System.AreaLevel1')));
      expect(references, isNot(contains('System.AttachedFileCount')));
      expect(references, isNot(contains('System.Watermark')));
      expect(references, isNot(contains('System.ChangedDate')));
      expect(references, isNot(contains('System.History')));
      expect(references, contains('System.AssignedTo'));
      expect(references, contains('System.Tags'));
    });

    test('no field appears twice', () {
      final all = [
        for (final c in spec.layout.pages.single.controls) c.fieldReferenceName,
      ];
      expect(all.toSet().length, all.length);
    });

    test('custom fields group together, backlog field names are honoured', () {
      final layout = WorkItemFormRepository.fieldListLayout(
        {
          'System.Title': const FieldSpec(
            referenceName: 'System.Title',
            name: 'Title',
            alwaysRequired: true,
          ),
          'Custom.QAAssignee': const FieldSpec(
            referenceName: 'Custom.QAAssignee',
            name: 'QA Assignee',
            isIdentity: true,
          ),
          'Custom.QAStoryPoints': const FieldSpec(
            referenceName: 'Custom.QAStoryPoints',
            name: 'QA Story Points',
            type: FieldType.decimal,
          ),
          'Microsoft.VSTS.Scheduling.Effort': const FieldSpec(
            referenceName: 'Microsoft.VSTS.Scheduling.Effort',
            name: 'Effort',
            type: FieldType.decimal,
          ),
          'System.Tags': const FieldSpec(
            referenceName: 'System.Tags',
            name: 'Tags',
          ),
        },
        backlogTypeFields: const {'Effort': 'Microsoft.VSTS.Scheduling.Effort'},
      );
      final groups = layout.pages.single.sections.single.groups;
      expect(groups.map((g) => g.label).toList(), const [
        'Required',
        'Details',
        'Custom fields',
        'System',
      ]);
      expect(
        groups[1].controls.single.fieldReferenceName,
        'Microsoft.VSTS.Scheduling.Effort',
      );
      expect(
        groups[2].controls.map((c) => c.fieldReferenceName).toList(),
        const ['Custom.QAAssignee', 'Custom.QAStoryPoints'],
      );
    });

    test('control types follow the field type', () {
      expect(
        WorkItemFormRepository.controlTypeFor(FieldType.html),
        FormControlType.html,
      );
      expect(
        WorkItemFormRepository.controlTypeFor(FieldType.treePath),
        FormControlType.classification,
      );
      expect(
        WorkItemFormRepository.controlTypeFor(FieldType.dateTime),
        FormControlType.dateTime,
      );
      expect(
        WorkItemFormRepository.controlTypeFor(FieldType.picklistString),
        FormControlType.field,
      );
    });
  });

  group('team defaults and backlog levels', () {
    test('iteration paths are rewritten to the field form', () {
      expect(
        WorkItemFormRepository.iterationPath('DevOps Mobile App', {
          'name': 'Iteration 1',
          'path': r'\Iteration 1',
        }),
        r'DevOps Mobile App\Iteration 1',
      );
      expect(
        WorkItemFormRepository.iterationPath('DevOps Mobile App', {
          'name': 'DevOps Mobile App',
          'path': '',
        }),
        'DevOps Mobile App',
      );
      expect(
        WorkItemFormRepository.iterationPath('DevOps Mobile App', {
          'name': 'Iteration 1',
          'path': r'DevOps Mobile App\Iteration 1',
        }),
        r'DevOps Mobile App\Iteration 1',
      );
    });

    test('classification nodes carry the work item path', () {
      final node = ClassificationNode.fromJson({
        'id': 4557,
        'identifier': 'aa9f2381-54e4-499a-8b8b-e3f981aac964',
        'name': 'Iteration 1',
        'structureType': 'iteration',
        'hasChildren': false,
        'attributes': {
          'startDate': '2026-09-01T00:00:00Z',
          'finishDate': '2026-09-14T00:00:00Z',
        },
        'path': r'\DevOps Mobile App\Iteration\Iteration 1',
      });
      expect(node.path, r'DevOps Mobile App\Iteration 1');
      expect(node.isIteration, isTrue);
      expect(node.startDate?.toUtc().day, 1);
      expect(
        ClassificationNode.fieldPath(r'\DevOps Mobile App\Area\Mobile', 'area'),
        r'DevOps Mobile App\Mobile',
      );
    });

    test('team defaults prefer the current sprint', () {
      final defaults = WorkItemFormRepository.parseTeamDefaults(
        project: 'DevOps Mobile App',
        teamId: 'team-id',
        teamFieldValues: const {'defaultValue': 'DevOps Mobile App'},
        teamSettings: const {
          'backlogIteration': {'name': 'DevOps Mobile App', 'path': ''},
          'bugsBehavior': 'asTasks',
        },
        currentIterations: const {
          'value': [
            {'name': 'Iteration 1', 'path': r'DevOps Mobile App\Iteration 1'},
          ],
        },
      );
      expect(defaults.defaultArea, 'DevOps Mobile App');
      expect(defaults.iterationPath, r'DevOps Mobile App\Iteration 1');
      expect(defaults.backlogIterationPath, 'DevOps Mobile App');
      expect(defaults.bugsBehavior, 'asTasks');
      expect(TeamDefaults.fromJson(defaults.toJson()), defaults);
    });

    test('the team iteration list keeps wire order and marks the current', () {
      // Shape from spike s30 (scratch team, three iterations).
      final iterations = WorkItemFormRepository.parseTeamIterations(
        'DevOps Mobile App',
        const {
          'count': 3,
          'value': [
            {
              'id': 'aa9f2381',
              'name': 'Iteration 1',
              'path': r'DevOps Mobile App\Iteration 1',
              'attributes': {
                'startDate': null,
                'finishDate': null,
                'timeFrame': 'current',
              },
            },
            {
              'id': 'd24c4cbe',
              'name': 'Iteration 2',
              'path': r'Iteration 2',
              'attributes': {'timeFrame': 'future'},
            },
            {
              'id': 'a9cb9d0a',
              'name': 'Iteration 3',
              'path': r'\Iteration 3',
              'attributes': {
                'startDate': '2026-10-01T00:00:00Z',
                'timeFrame': 'future',
              },
            },
          ],
        },
      );
      expect(iterations.map((i) => i.name).toList(), const [
        'Iteration 1',
        'Iteration 2',
        'Iteration 3',
      ]);
      // Every path comes back project-rooted, however the wire spelled it.
      expect(iterations.map((i) => i.path).toList(), const [
        r'DevOps Mobile App\Iteration 1',
        r'DevOps Mobile App\Iteration 2',
        r'DevOps Mobile App\Iteration 3',
      ]);
      expect(iterations.first.isCurrent, isTrue);
      expect(iterations[1].isCurrent, isFalse);
      expect(iterations.last.startDate?.toUtc().month, 10);
    });

    test('backlog levels come back top-down with the hidden types', () {
      final types = WorkItemFormRepository.parseBacklogTypes(
        config: _fixture('scratch_backlogconfiguration.json'),
        categories: _fixture('scratch_workitemtypecategories.json'),
      );
      expect(types.levels.map((l) => l.name).toList(), const [
        'Epics',
        'Features',
        'Stories',
        'Tasks',
      ]);
      expect(types.levels.first.isHidden, isTrue);
      expect(types.bugsBehavior, 'asTasks');
      expect(types.orderedTypeNames, const [
        'Feature',
        'User Story',
        'Task',
        'Bug',
      ]);
      expect(types.hiddenTypes, contains('Test Plan'));
      expect(types.hiddenTypes, contains('Code Review Request'));
      expect(BacklogTypes.fromJson(types.toJson()).levels, types.levels);
    });
  });
}
