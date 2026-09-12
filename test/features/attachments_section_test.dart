import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:boardhop/features/work_items/form/controls/attachment_picker.dart';
import 'package:boardhop/features/work_items/form/controls/attachments_section.dart';
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

const _attachments = 'https://dev.azure.com/puremedia/_apis/wit/attachments';

/// The relation shape spike w17 left on scratch item #15540, plus a file
/// whose name only lives on the URL and one that is not an image.
WorkItemRelation _attached({
  required String id,
  String? name,
  int? size,
  String? comment,
}) {
  final attributes = <String, dynamic>{};
  if (name != null) attributes['name'] = name;
  if (size != null) attributes['resourceSize'] = size;
  if (comment != null) attributes['comment'] = comment;
  return WorkItemRelation(
    rel: WorkItemRelation.attachedFileRel,
    url: '$_attachments/$id${name == null ? '' : '?fileName=$name'}',
    attributes: attributes,
  );
}

void main() {
  final spec = _specFor('bug');
  final item = WorkItem.fromJson(_fixture('scratch_bug_item.json'));

  final png = _attached(
    id: '0e1d2c3b-4a59-4687-9cab-1122334455aa',
    name: 'boardhop-spike.png',
    size: 5_432,
  );
  final zip = _attached(
    id: 'aabbccdd-1122-3344-5566-778899001122',
    name: 'logs.zip',
    size: 524_288,
    comment: 'from the failing run',
  );
  final unnamed = WorkItemRelation(
    rel: WorkItemRelation.attachedFileRel,
    url: '$_attachments/ffffffff-0000-0000-0000-000000000001?fileName=note.txt',
  );

  WorkItemFormState editState({List<WorkItemRelation> relations = const []}) {
    final loaded = WorkItem.fromJson({
      ...item.toJson(),
      'relations': [for (final r in relations) r.toJson()],
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

  group('reading an AttachedFile relation', () {
    test('name, size, guid and kind come off the relation', () {
      final info = AttachmentInfo.of(png);
      expect(info.name, 'boardhop-spike.png');
      expect(info.size, 5432);
      expect(info.id, '0e1d2c3b-4a59-4687-9cab-1122334455aa');
      expect(info.isImage, isTrue);
      expect(info.extension, 'png');
    });

    test('a relation without attributes falls back to the URL name', () {
      final info = AttachmentInfo.of(unnamed);
      expect(info.name, 'note.txt');
      expect(info.isImage, isFalse);
      expect(info.size, isNull);
    });

    test('a non-image gets a glyph for its kind', () {
      final info = AttachmentInfo.of(zip);
      expect(info.isImage, isFalse);
      expect(info.icon, Icons.folder_zip_outlined);
      expect(info.comment, 'from the failing run');
    });

    test('the form separates attachments from links', () {
      final state = editState(
        relations: [
          png,
          zip,
          const WorkItemRelation(
            rel: WorkItemRelation.parentRel,
            url: 'https://dev.azure.com/puremedia/_apis/wit/workItems/15546',
          ),
        ],
      );
      expect(state.attachmentRelations, [png, zip]);
      expect(state.linkRelations.single.targetId, 15546);
      state.dispose();
    });
  });

  group('the size cap', () {
    test('it is the documented 60 MB', () {
      expect(WorkItemFormRepository.maxAttachmentBytes, 62914560);
    });

    test('the message names the file, its size and the ceiling', () {
      expect(
        attachmentTooLargeMessage('crash.dmp', 80 * 1024 * 1024),
        'crash.dmp is 80 MB. Azure DevOps accepts attachments up to 60 MB.',
      );
    });

    test('a picked photo is named after the moment it was taken', () {
      final at = DateTime(2026, 9, 12, 9, 58, 3);
      expect(photoFileName('19.png', now: at), 'photo-20260912-095803.png');
      // The plugin's own temp name never reaches Azure DevOps.
      expect(
        photoFileName('image_picker_EE2622C8-6B4C-4D3E-9E1F-0A.jpg', now: at),
        'photo-20260912-095803.jpg',
      );
      expect(
        photoFileName('screenshot-login.png', now: at),
        'photo-20260912-095803.png',
      );
      // No extension at all still produces one the service accepts.
      expect(photoFileName('42', now: at), 'photo-20260912-095803.jpg');
    });

    test('an oversize pick carries no bytes', () {
      const picked = PickedAttachment(name: 'big.zip', size: 80_000_000);
      expect(picked.isTooLarge, isTrue);
      final read = PickedAttachment(
        name: 'a.png',
        size: 3,
        bytes: Uint8List.fromList(const [1, 2, 3]),
      );
      expect(read.isTooLarge, isFalse);
    });
  });

  group('the patch', () {
    test('an attachment added on an existing item is one add op', () {
      final state = editState();
      state.addRelation(png);
      final ops = state.buildEditOps();
      expect(ops, [
        {'op': 'test', 'path': '/rev', 'value': 7},
        {
          'op': 'add',
          'path': '/relations/-',
          'value': {
            'rel': 'AttachedFile',
            'url': png.url,
            'attributes': {'name': 'boardhop-spike.png', 'resourceSize': 5432},
          },
        },
      ]);
      state.dispose();
    });

    test('removing one is a positional remove', () {
      final state = editState(relations: [png, zip]);
      state.removeRelation(png);
      expect(state.buildEditOps().skip(1).single, const {
        'op': 'remove',
        'path': '/relations/0',
      });
      state.dispose();
    });

    test('the pending list rides into the create patch', () {
      final state = WorkItemFormState(
        spec: spec,
        initialValues: const {'System.Title': '[phase5] created with a file'},
      );
      state.addRelation(png);
      final ops = state.buildOps();
      expect(ops.last, {
        'op': 'add',
        'path': '/relations/-',
        'value': {
          'rel': 'AttachedFile',
          'url': png.url,
          'attributes': {'name': 'boardhop-spike.png', 'resourceSize': 5432},
        },
      });
      // The uploaded file also survives a draft, so resuming does not
      // orphan it.
      expect(state.addedRelationValues, hasLength(1));
      state.dispose();
    });

    test('the relation builder matches what spike w17 sent', () {
      expect(
        WorkItemFormRepository.attachmentRelation(
          const AttachmentRef(
            id: 'guid',
            url: '$_attachments/guid?fileName=a.png',
            fileName: 'a.png',
          ),
          comment: 'screenshot',
        ),
        {
          'rel': 'AttachedFile',
          'url': '$_attachments/guid?fileName=a.png',
          'attributes': {'name': 'a.png', 'comment': 'screenshot'},
        },
      );
    });
  });

  group('the Attachments section', () {
    AttachmentSource source({Future<bool> Function()? commit}) =>
        AttachmentSource(
          // A 1x1 transparent GIF: enough for `Image.memory` to decode.
          bytes: (_) async => Uint8List.fromList(
            base64Decode(
              'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
            ),
          ),
          upload: (name, bytes) async => AttachmentRef(
            id: 'new-guid',
            url: '$_attachments/new-guid?fileName=$name',
            fileName: name,
          ),
          commit: commit,
        );

    Future<WorkItemFormState> pump(
      WidgetTester tester, {
      List<WorkItemRelation> relations = const [],
    }) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = editState(relations: relations);
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.dark(),
          home: Scaffold(
            body: AttachmentsSection(state: state, source: source()),
          ),
        ),
      );
      await tester.pump();
      return state;
    }

    testWidgets('a row per file, with its size', (tester) async {
      final state = await pump(tester, relations: [png, zip, unnamed]);

      expect(find.text('boardhop-spike.png'), findsOneWidget);
      expect(find.text('5 KB'), findsOneWidget);
      expect(find.text('logs.zip'), findsOneWidget);
      expect(find.text('512 KB · from the failing run'), findsOneWidget);
      expect(find.text('note.txt'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
      state.dispose();
    });

    testWidgets('an empty list says so', (tester) async {
      final state = await pump(tester);

      expect(find.text('No attachments yet.'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
      state.dispose();
    });

    testWidgets('the trailing remove drops the row', (tester) async {
      final state = await pump(tester, relations: [png]);

      await tester.tap(find.byTooltip('Remove attachment'));
      // Not pumpAndSettle: a thumbnail still loading spins forever.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('boardhop-spike.png'), findsNothing);
      expect(state.removedRelationKeys, {png.key});
      state.dispose();
    });

    testWidgets('a failed commit tells the user to Save', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = editState(relations: [png]);
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Scaffold(
            body: AttachmentsSection(
              state: state,
              source: source(commit: () async => false),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Remove attachment'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Save to remove it on the server.'), findsOneWidget);
      state.dispose();
    });

    testWidgets('the add sheet offers the three sources', (tester) async {
      final state = await pump(tester);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Take photo'), findsOneWidget);
      expect(find.text('Choose from library'), findsOneWidget);
      expect(find.text('Choose file'), findsOneWidget);
      state.dispose();
    });
  });
}
