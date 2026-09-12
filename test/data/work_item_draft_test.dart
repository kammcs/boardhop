import 'dart:convert';

import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkItemDraft', () {
    final draft = WorkItemDraft(
      project: 'DevOps Mobile App',
      type: 'Bug',
      savedAt: DateTime.utc(2026, 9, 12, 10, 30),
      values: {
        'System.Title': 'Login fails on the tablet',
        'Microsoft.VSTS.Common.Priority': 1,
        'System.Tags': 'boardhop; spike',
        'Microsoft.VSTS.Scheduling.StartDate': DateTime.utc(2026, 9, 12),
        'Custom.Done': false,
      },
      relations: const [
        {
          'rel': 'System.LinkTypes.Hierarchy-Reverse',
          'url': 'https://dev.azure.com/o/p/_apis/wit/workItems/15503',
        },
      ],
    );

    test('round-trips through JSON', () {
      final again = WorkItemDraft.fromJson(
        (jsonDecode(jsonEncode(draft.toJson())) as Map).cast<String, dynamic>(),
      );
      expect(again.project, draft.project);
      expect(again.type, draft.type);
      expect(again.savedAt, draft.savedAt);
      expect(again.title, 'Login fails on the tablet');
      expect(again.values['Microsoft.VSTS.Common.Priority'], 1);
      expect(again.values['Custom.Done'], false);
      // A DateTime is stored in ISO form, which is what the patch sends.
      expect(
        again.values['Microsoft.VSTS.Scheduling.StartDate'],
        '2026-09-12T00:00:00.000Z',
      );
      expect(again.relations.single['rel'], WorkItemFormRepository.parentRel);
    });

    test('an untouched draft reports itself empty', () {
      final empty = WorkItemDraft(
        project: 'DevOps Mobile App',
        type: 'Task',
        savedAt: DateTime.utc(2026, 9, 12),
        values: const {'System.Title': '   ', 'System.Description': null},
      );
      expect(empty.isEmpty, isTrue);
      expect(empty.title, '   ');
      expect(draft.isEmpty, isFalse);
    });

    test('a missing or broken entry decodes to defaults', () {
      final bare = WorkItemDraft.fromJson(const {});
      expect(bare.project, '');
      expect(bare.type, '');
      expect(bare.values, isEmpty);
      expect(bare.relations, isEmpty);
      expect(bare.savedAt.year, 1970);
    });

    test('the cache key is per org, project and type', () {
      expect(
        WorkItemFormRepository.draftKey(
          'puremedia',
          'DevOps Mobile App',
          'Bug',
        ),
        'form:draft:puremedia:DevOps Mobile App:Bug',
      );
      expect(
        WorkItemFormRepository.specKey('puremedia', 'DevOps Mobile App', 'Bug'),
        'form:spec2:puremedia:DevOps Mobile App:Bug',
      );
    });
  });
}
