import 'dart:convert';
import 'dart:io';

import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:boardhop/features/work_items/form/work_item_form_state.dart';
import 'package:drift/native.dart';
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

const _project = 'DevOps Mobile App';
const _org = 'puremedia';

void main() {
  late AppDatabase db;
  late WorkItemFormRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final client = AdoClient(
      tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
    );
    repo = WorkItemFormRepository(
      client,
      WorkItemRepository(client, db),
      db,
      'account-1',
    );
  });

  tearDown(() => db.close());

  group('a draft in the cache', () {
    test('round-trips through the repository', () async {
      final draft = WorkItemDraft(
        project: _project,
        type: 'Bug',
        savedAt: DateTime.now(),
        values: const {
          'System.Title': 'Login fails on the tablet',
          'System.Tags': 'boardhop; draft',
          'System.AssignedTo': 'Kelly Kamm <kelly@example.test>',
          'Microsoft.VSTS.TCM.ReproSteps': '<div>typed</div>',
        },
        formats: const {'Microsoft.VSTS.TCM.ReproSteps': 'html'},
        prefill: const {'state': 'Active', 'team': 'team-1'},
      );
      await repo.saveDraft(_org, draft);

      final back = await repo.draft(_org, _project, 'Bug');
      expect(back, isNotNull);
      expect(back!.title, 'Login fails on the tablet');
      expect(back.prefill['state'], 'Active');
      expect(back.formats['Microsoft.VSTS.TCM.ReproSteps'], 'html');

      // And it is offered in the project's list.
      final all = await repo.drafts(_org, _project);
      expect(all.map((d) => d.type), ['Bug']);

      await repo.clearDraft(_org, _project, 'Bug');
      expect(await repo.draft(_org, _project, 'Bug'), isNull);
      expect(await repo.drafts(_org, _project), isEmpty);
    });

    test('newest first, and an empty draft is not offered', () async {
      final now = DateTime.now();
      await repo.saveDraft(
        _org,
        WorkItemDraft(
          project: _project,
          type: 'Bug',
          savedAt: now.subtract(const Duration(minutes: 30)),
          values: const {'System.Title': 'older'},
        ),
      );
      await repo.saveDraft(
        _org,
        WorkItemDraft(
          project: _project,
          type: 'Task',
          savedAt: now,
          values: const {'System.Title': 'newer'},
        ),
      );
      await repo.saveDraft(
        _org,
        WorkItemDraft(
          project: _project,
          type: 'User Story',
          savedAt: now,
          values: const {'System.Title': '   '},
        ),
      );
      final all = await repo.drafts(_org, _project);
      expect(all.map((d) => d.type), ['Task', 'Bug']);
    });

    test('one older than 30 days is dropped on read', () async {
      final old = WorkItemDraft(
        project: _project,
        type: 'Bug',
        savedAt: DateTime.now().subtract(const Duration(days: 31)),
        values: const {'System.Title': 'forgotten'},
      );
      expect(old.isExpired(), isTrue);
      await repo.saveDraft(_org, old);
      expect(await repo.draft(_org, _project, 'Bug'), isNull);
      // The read also removes it, so the chooser never sees it again.
      expect(await repo.drafts(_org, _project), isEmpty);
    });

    test('29 days old is still offered', () async {
      await repo.saveDraft(
        _org,
        WorkItemDraft(
          project: _project,
          type: 'Bug',
          savedAt: DateTime.now().subtract(const Duration(days: 29)),
          values: const {'System.Title': 'still here'},
        ),
      );
      expect(await repo.draft(_org, _project, 'Bug'), isNotNull);
    });
  });

  group('the form and a draft', () {
    final spec = _specFor('bug');

    test('what the form keeps is what the patch would send', () {
      final form = WorkItemFormState(spec: spec)
        ..setValue('System.Title', 'Login fails')
        ..setValue('System.Tags', ['boardhop', 'draft'])
        ..setValue(
          'System.AssignedTo',
          const IdentityRef(
            displayName: 'Kelly Kamm',
            uniqueName: 'kelly@example.test',
          ),
        )
        ..setRichValue('Microsoft.VSTS.TCM.ReproSteps', '<p>typed</p>');
      final values = form.draftValues();
      expect(values['System.Title'], 'Login fails');
      expect(values['System.Tags'], 'boardhop; draft');
      expect(values['System.AssignedTo'], 'Kelly Kamm <kelly@example.test>');
      expect(values['Microsoft.VSTS.TCM.ReproSteps'], '<p>typed</p>');
      // The server owns the state of a new item, so it is never in a draft.
      expect(values.containsKey('System.State'), isFalse);
      // The draft is plain JSON.
      expect(jsonEncode(values), isA<String>());
      form.dispose();
    });

    test('resuming applies the values, marks them dirty and keeps HTML', () {
      final draft = WorkItemDraft(
        project: _project,
        type: 'Bug',
        savedAt: DateTime.now(),
        values: const {
          'System.Title': 'Login fails',
          'System.Tags': 'boardhop; draft',
          'Microsoft.VSTS.TCM.ReproSteps': '<p>typed</p>',
        },
      );
      final values = <String, Object?>{'System.State': spec.initialState};
      final dirty = <String>{};
      final rich = <String>{};
      for (final entry in draft.values.entries) {
        values[entry.key] = decodeFieldValue(spec, entry.key, entry.value);
        dirty.add(entry.key);
        if (spec.fields[entry.key]?.type == FieldType.html) rich.add(entry.key);
      }
      final form = WorkItemFormState(
        spec: spec,
        initialValues: values,
        dirtyFields: dirty,
        richFields: rich,
      );
      expect(form.isDirty, isTrue);
      expect(form.isDirtyField('System.Title'), isTrue);
      expect(form.title, 'Login fails');
      expect(form.tags, ['boardhop', 'draft']);
      final ops = form.buildOps();
      Object? valueOf(String path) =>
          ops.firstWhere((op) => op['path'] == path)['value'];
      // Long text from a draft is HTML already and is never escaped again.
      expect(valueOf('/fields/Microsoft.VSTS.TCM.ReproSteps'), '<p>typed</p>');
      expect(valueOf('/fields/System.Tags'), 'boardhop; draft');
      form.dispose();
    });
  });
}
