import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/core/http/ado_exceptions.dart';
import 'package:boardhop/core/http/ado_host.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// The 400 bodies spike w16 recorded against the scratch project.
const _missingTitleBody = <String, dynamic>{
  'message':
      'TF401320: Rule Error for field Title. '
      'Error code: Required, InvalidEmpty.',
  'typeKey': 'RuleValidationException',
  'errorCode': 0,
  'customProperties': {
    'RuleValidationErrors': [
      {
        'fieldReferenceName': 'System.Title',
        'fieldStatusFlags': 'required, invalidEmpty',
        'errorMessage':
            'TF401320: Rule Error for field Title. '
            'Error code: Required, InvalidEmpty.',
        'fieldStatusCode': 524289,
        'ruleValidationErrors': null,
      },
    ],
  },
};

const _badPriorityBody = <String, dynamic>{
  'message':
      "The field 'Priority' contains the value '9' that is not in the "
      'list of supported values',
  'typeKey': 'RuleValidationException',
  'RuleValidationErrors': [
    {
      'fieldReferenceName': 'Microsoft.VSTS.Common.Priority',
      'fieldStatusFlags': 'hasValues, limitedToValues, invalidListValue',
      'errorMessage':
          "The field 'Priority' contains the value '9' that is not in the "
          'list of supported values',
      'fieldStatusCode': 4194316,
    },
  ],
};

const _unknownFieldBody = <String, dynamic>{
  'message': 'TF51535: Cannot find field Custom.DoesNotExist.',
  'typeKey': 'WorkItemTrackingFieldDefinitionNotFoundException',
  'errorCode': 0,
  'RuleValidationErrors': null,
};

WorkItem _item() => WorkItem.fromJson({
  'id': 15503,
  'rev': 7,
  'fields': {
    'System.Title': 'Login fails',
    'System.State': 'New',
    'System.Tags': 'spike; mobile',
    'Microsoft.VSTS.Common.Priority': 2,
    'Microsoft.VSTS.Scheduling.RemainingWork': 4.0,
    'System.AssignedTo': {
      'displayName': 'Kelly Kamm',
      'uniqueName': 'kelly@example.test',
      'id': 'kelly-id',
    },
    'System.Description': '<p>hi</p>',
  },
  'multilineFieldsFormat': {'System.Description': 'html'},
});

void main() {
  group('buildCreateOps', () {
    test('fields, tags, Markdown format, parent and attachment', () {
      final ops = WorkItemFormRepository.buildCreateOps(
        {
          'System.Title': 'w16 create',
          'System.Description': '# Heading',
          'System.Tags': ['boardhop', 'spike', 'boardhop'],
          'Microsoft.VSTS.Common.Priority': 1,
          'System.AssignedTo': const IdentityRef(
            displayName: 'Kelly Kamm',
            uniqueName: 'kelly@example.test',
          ),
          'Microsoft.VSTS.Scheduling.StartDate': DateTime.utc(2026, 9, 12, 8),
          'Custom.Empty': '',
          'Custom.Null': null,
        },
        markdownDescription: true,
        parentUrl: 'https://dev.azure.com/o/p/_apis/wit/workItems/15503',
        attachments: const [
          AttachmentRef(
            id: '6b75922d',
            url: 'https://dev.azure.com/o/p/_apis/wit/attachments/6b75922d',
            fileName: 'w17-pixel.png',
          ),
        ],
      );
      expect(ops.every((op) => op['op'] == 'add'), isTrue);
      Object? valueOf(String path) =>
          ops.firstWhere((op) => op['path'] == path)['value'];

      expect(valueOf('/fields/System.Title'), 'w16 create');
      // Tags are joined and de-duplicated.
      expect(valueOf('/fields/System.Tags'), 'boardhop; spike');
      expect(valueOf('/fields/Microsoft.VSTS.Common.Priority'), 1);
      expect(
        valueOf('/fields/System.AssignedTo'),
        'Kelly Kamm <kelly@example.test>',
      );
      expect(
        valueOf('/fields/Microsoft.VSTS.Scheduling.StartDate'),
        '2026-09-12T08:00:00.000Z',
      );
      expect(valueOf('/multilineFieldsFormat/System.Description'), 'Markdown');
      // Empty and null values never reach the patch.
      expect(
        ops.any((op) => '${op['path']}'.endsWith('Custom.Empty')),
        isFalse,
      );
      expect(ops.any((op) => '${op['path']}'.endsWith('Custom.Null')), isFalse);

      final relations = ops
          .where((op) => op['path'] == '/relations/-')
          .toList();
      expect(relations.length, 2);
      expect(
        (relations.first['value'] as Map)['rel'],
        'System.LinkTypes.Hierarchy-Reverse',
      );
      final attachment = relations.last['value'] as Map;
      expect(attachment['rel'], 'AttachedFile');
      expect((attachment['attributes'] as Map)['name'], 'w17-pixel.png');
    });

    test('no format op without Markdown, extra relations ride along', () {
      final ops = WorkItemFormRepository.buildCreateOps(
        {'System.Title': 'plain'},
        relations: const [
          {
            'rel': 'System.LinkTypes.Related',
            'url': 'https://dev.azure.com/o/p/_apis/wit/workItems/15504',
          },
        ],
      );
      expect(
        ops.any((op) => '${op['path']}'.startsWith('/multilineFieldsFormat')),
        isFalse,
      );
      expect(ops.last['path'], '/relations/-');
      expect(
        (ops.last['value'] as Map)['rel'],
        WorkItemFormRepository.relatedRel,
      );
    });

    test('named Markdown fields get their own format op', () {
      final ops = WorkItemFormRepository.buildCreateOps(
        {'Microsoft.VSTS.TCM.ReproSteps': '1. break it'},
        markdownFields: const {'Microsoft.VSTS.TCM.ReproSteps'},
      );
      expect(
        ops.last['path'],
        '/multilineFieldsFormat/Microsoft.VSTS.TCM.ReproSteps',
      );
    });
  });

  group('buildEditOps', () {
    test('test /rev first, then only what changed', () {
      final ops = WorkItemFormRepository.buildEditOps(_item(), {
        'System.Title': 'Login fails', // unchanged
        'System.State': 'Active', // changed
        'Microsoft.VSTS.Common.Priority': '2', // same value, string form
        'Microsoft.VSTS.Scheduling.RemainingWork': 4, // 4 == 4.0
        'System.Tags': ['spike', 'mobile'], // same set, same order
        'System.AssignedTo': const IdentityRef(
          displayName: 'Kelly Kamm',
          uniqueName: 'kelly@example.test',
          id: 'kelly-id',
        ),
      });
      expect(ops.first, {'op': 'test', 'path': '/rev', 'value': 7});
      expect(ops.length, 2);
      expect(ops[1], {
        'op': 'add',
        'path': '/fields/System.State',
        'value': 'Active',
      });
    });

    test('clearing a field sends an empty value', () {
      final ops = WorkItemFormRepository.buildEditOps(_item(), {
        'System.AssignedTo': null,
      });
      expect(ops.length, 2);
      expect(ops[1]['value'], '');
    });

    test('the format op appears only when the format changes', () {
      final unchanged = WorkItemFormRepository.buildEditOps(
        _item(),
        const {},
        formats: const {'System.Description': 'html'},
      );
      expect(unchanged.length, 1);

      final changed = WorkItemFormRepository.buildEditOps(
        _item(),
        const {'System.Description': '# hi'},
        formats: const {'System.Description': 'markdown'},
      );
      expect(changed.length, 3);
      expect(changed.last, {
        'op': 'add',
        'path': '/multilineFieldsFormat/System.Description',
        'value': 'Markdown',
      });
    });
  });

  group('tags and identities', () {
    test('formatTags joins, trims and de-duplicates', () {
      expect(
        WorkItemFormRepository.formatTags(['  a ', 'b', 'A', '', 'c']),
        'a; b; c',
      );
      expect(WorkItemFormRepository.formatTags(const []), '');
    });

    test('parseTags splits on semicolons', () {
      expect(WorkItemFormRepository.parseTags('spike; mobile ;'), [
        'spike',
        'mobile',
      ]);
      expect(WorkItemFormRepository.parseTags(null), isEmpty);
    });

    test('assignedToValue prefers the display form, else the id', () {
      // Spike s29: the work item store refuses the identity id the team
      // member list carries ("unknown identity"), so the id is only the
      // fallback for someone without a unique name.
      expect(
        WorkItemFormRepository.assignedToValue(
          const IdentityRef(
            displayName: 'Kelly Kamm',
            uniqueName: 'kelly@example.test',
            id: 'kelly-id',
          ),
        ),
        'Kelly Kamm <kelly@example.test>',
      );
      expect(
        WorkItemFormRepository.assignedToValue(
          const IdentityRef(displayName: 'Kelly Kamm', id: 'kelly-id'),
        ),
        'kelly-id',
      );
      expect(
        WorkItemFormRepository.assignedToValue(
          const IdentityRef(
            displayName: 'Kelly Kamm',
            uniqueName: 'kelly@example.test',
          ),
        ),
        'Kelly Kamm <kelly@example.test>',
      );
      expect(
        WorkItemFormRepository.assignedToValue(
          const IdentityRef(displayName: 'Kelly Kamm'),
        ),
        'Kelly Kamm',
      );
    });

    test('a Graph user maps to an identity without an id', () {
      final person = WorkItemFormRepository.identityFromGraphUser(const {
        'displayName': 'Kelly Kamm',
        'mailAddress': 'kkamm@example.test',
        'principalName': 'kkamm@example.test',
        'descriptor': 'aad.NWVkNjFiZWU',
        '_links': {
          'avatar': {
            'href':
                'https://dev.azure.com/o/_apis/GraphProfile/MemberAvatars/'
                'aad.NWVkNjFiZWU',
          },
        },
      });
      expect(person.id, isNull);
      expect(person.uniqueName, 'kkamm@example.test');
      expect(person.descriptor, 'aad.NWVkNjFiZWU');
      expect(person.avatarSource()?.isGraph, isTrue);
      expect(
        WorkItemFormRepository.assignedToValue(person),
        'Kelly Kamm <kkamm@example.test>',
      );
    });
  });

  group('validation errors', () {
    test('a missing required field', () {
      final errors = ValidationError.parseBody(_missingTitleBody);
      expect(errors.length, 1);
      expect(errors.single.fieldReferenceName, 'System.Title');
      expect(errors.single.flags, ['required', 'invalidEmpty']);
      expect(errors.single.isRequired, isTrue);
      expect(errors.single.message, contains('TF401320'));
    });

    test('an illegal picklist value, rule errors at the top level', () {
      final errors = ValidationError.parseBody(_badPriorityBody);
      expect(
        errors.single.fieldReferenceName,
        'Microsoft.VSTS.Common.Priority',
      );
      expect(errors.single.isInvalidValue, isTrue);
      expect(errors.single.isRequired, isFalse);
    });

    test('an unknown field carries no rule errors', () {
      expect(ValidationError.parseBody(_unknownFieldBody), isEmpty);
      final exception = WorkItemRuleException.fromBody(_unknownFieldBody);
      expect(exception.errors, isEmpty);
      expect(
        exception.typeKey,
        'WorkItemTrackingFieldDefinitionNotFoundException',
      );
      expect(exception.message, contains('TF51535'));
    });

    test('WorkItemRuleException finds the field and stays an AdoException', () {
      final exception = WorkItemRuleException.fromBody(
        _missingTitleBody,
        statusCode: 400,
      );
      expect(exception, isA<AdoException>());
      expect(exception, isA<AdoValidationException>());
      expect(exception.fields, {'System.Title'});
      expect(exception.forField('System.Title')?.isRequired, isTrue);
      expect(exception.forField('System.State'), isNull);
      // The base class keeps its own list so existing handlers still work.
      expect(exception.ruleErrors.single.fieldReferenceName, 'System.Title');
    });

    test('rebuilt from what AdoClient already parsed', () {
      final parsed = AdoValidationException(
        'refused',
        ruleErrors: [
          RuleValidationError.fromJson(const {
            'fieldReferenceName': 'System.State',
            'fieldStatusFlags':
                'required, hasValues, limitedToValues, invalidListValue',
            'errorMessage':
                "The field 'State' contains the value 'Done' that is not in "
                'the list of supported values',
          }),
        ],
        statusCode: 400,
      );
      final exception = WorkItemRuleException.fromValidation(parsed);
      expect(exception.errors.single.fieldReferenceName, 'System.State');
      expect(exception.errors.single.flags, contains('invalidListValue'));
      expect(exception.errors.single.isInvalidValue, isTrue);
      expect(exception.statusCode, 400);
    });
  });

  group('URLs', () {
    test('the create path keeps the dollar and encodes the space', () {
      expect(
        WorkItemFormRepository.createPath('User Story'),
        r'_apis/wit/workitems/$User Story',
      );
      final uri = AdoClient.buildUri(
        host: AdoHost.core,
        org: 'puremedia',
        project: 'DevOps Mobile App',
        path: WorkItemFormRepository.createPath('User Story'),
        apiVersion: '7.1',
        query: {'validateOnly': 'true'},
      );
      expect(
        uri.toString(),
        'https://dev.azure.com/puremedia/DevOps%20Mobile%20App/_apis/wit/'
        r'workitems/$User%20Story?validateOnly=true&api-version=7.1',
      );
    });

    test('the title search escapes quotes', () {
      final wiql = WorkItemFormRepository.titleSearchWiql("it's broken");
      expect(wiql, contains("CONTAINS 'it''s broken'"));
      expect(wiql, contains('[System.TeamProject] = @project'));
    });
  });
}
