import 'dart:convert';

import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/write_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fieldsFromOps keeps only field adds', () {
    final fields = WriteQueue.fieldsFromOps([
      {'op': 'test', 'path': '/rev', 'value': 3},
      {'op': 'add', 'path': '/fields/System.State', 'value': 'Active'},
      {'op': 'add', 'path': '/fields/WEF_X_Kanban.Column', 'value': 'Active'},
      {'op': 'remove', 'path': '/fields/System.Tags'},
    ]);
    expect(fields, {
      'System.State': 'Active',
      'WEF_X_Kanban.Column': 'Active',
    });
  });

  test('PendingWrite decodes a queued patch and a conflict', () {
    final row = PendingWriteRow(
      id: 7,
      kind: 'patch',
      orgName: 'puremedia',
      targetId: '15506',
      payload: jsonEncode({
        'project': 'DevOps Mobile App',
        'rev': 12,
        'ops': [
          {'op': 'add', 'path': '/fields/System.State', 'value': 'Active'},
        ],
        'description': 'Move 15506 to Active',
      }),
      createdAt: DateTime(2026, 9, 10),
      attempts: 1,
      lastError: 'conflict',
    );
    final w = PendingWrite.fromRow(row);
    expect(w.targetId, 15506);
    expect(w.rev, 12);
    expect(w.project, 'DevOps Mobile App');
    expect(w.ops.single['value'], 'Active');
    expect(w.description, 'Move 15506 to Active');
    expect(w.isConflict, isTrue);
  });
}
