import '../../demo_world.dart';
import 'boards.dart';
import 'content.dart';
import 'process.dart';

/// The demo's work item store: every [DemoWorkItem] turned into the field
/// map, relations and comments Azure DevOps would answer, and kept mutable
/// so a drag on the board, an edit on the form or a new comment sticks for
/// the rest of the session.
class DemoWorkStore {
  DemoWorkStore() {
    for (final w in DemoWorld.workItems) {
      _items[w.id] = _build(w);
    }
    for (final w in DemoWorld.workItems) {
      _items[w.id]!.relations.addAll(_relationsOf(w));
    }
    for (final entry in DemoWorkContent.comments.entries) {
      final list = _comments[entry.key] = [];
      for (final (i, c) in entry.value.indexed) {
        list.add(_comment(entry.key, 6100000 + entry.key * 10 + i, c));
      }
      _items[entry.key]?.fields['System.CommentCount'] = list.length;
    }
  }

  final Map<int, DemoStoredItem> _items = {};
  final Map<int, List<Map<String, dynamic>>> _comments = {};
  int _nextId = 1290;
  int _nextCommentId = 6200000;

  static const _base = DemoWorld.baseUrl;
  static const _projectUrl = DemoWorld.projectUrl;

  Iterable<DemoStoredItem> get items => _items.values;
  DemoStoredItem? operator [](int id) => _items[id];

  static String itemUrl(int id) => '$_projectUrl/_apis/wit/workItems/$id';

  /// Backlog order: the sprint's rows in the order the team ranked them,
  /// then everything else by id.
  static const _rank = [
    1234,
    1231,
    1241,
    1252,
    1238,
    1236,
    1255,
    1243,
    1257,
    1285,
    1286,
    1246,
    1248,
    1284,
    1280,
    1283,
    1281,
    1282,
  ];

  static const _estimates = <int, num>{
    1260: 5,
    1261: 3,
    1262: 6,
    1263: 8,
    1264: 5,
    1265: 8,
    1266: 10,
    1267: 4,
    1268: 6,
    1269: 4,
    1270: 5,
    1271: 6,
    1272: 4,
    1273: 3,
    1274: 4,
    1275: 6,
    1276: 3,
    1277: 2,
    1278: 4,
    1279: 5,
  };

  static const _related = <(int, int)>[
    (1234, 1252),
    (1231, 1286),
    (1241, 1255),
  ];

  static double _stackRankOf(DemoWorkItem w) {
    final i = _rank.indexOf(w.id);
    if (i >= 0) return 1000.0 * (i + 1);
    if (w.isTask) {
      final parentRank = w.parent == null
          ? 500000.0
          : _stackRankOf(DemoWorld.workItem(w.parent!));
      return parentRank + (w.id % 100);
    }
    return 100000.0 + w.id;
  }

  DemoStoredItem _build(DemoWorkItem w) {
    final sprint = w.iteration;
    final changed = w.changedDate;
    final created = w.createdDate;
    final author = w.assignee ?? DemoWorld.kelly;
    final changedBy = DemoWorld.workItemChangedHoursAgo.containsKey(w.id)
        ? author
        : (w.isTask ? author : DemoWorld.kelly);
    final category = DemoProcess.categoryOf(w.type, w.state);
    final started = category != 'Proposed';
    final resolved = category == 'Resolved' || category == 'Completed';
    final closed = category == 'Completed';
    final stateChanged = changed.subtract(
      Duration(hours: (w.id % 4) * (closed ? 30 : 6)),
    );
    final board = DemoBoard.forType(w.type);
    final column = board == null
        ? null
        : board == DemoBoard.stories
        ? (w.column ?? board.columnForState(w.type, w.state))
        : board.columnForState(w.type, w.state);
    final description = DemoWorkContent.description(w);
    final criteria = DemoWorkContent.acceptanceCriteria[w.id];
    final repro = DemoWorkContent.reproSteps[w.id];
    final identity = w.assignee?.identity();
    final estimate = _estimates[w.id] ?? (w.remaining ?? 0) + 2;
    final isRoot = w.iterationPath == DemoWorld.area;

    final fields = <String, dynamic>{
      'System.Id': w.id,
      'System.AreaId': 1100,
      'System.AreaPath': DemoWorld.area,
      'System.TeamProject': DemoWorld.project,
      'System.NodeName': DemoWorld.area,
      'System.AreaLevel1': DemoWorld.area,
      'System.Rev': 0,
      'System.AuthorizedDate': DemoWorld.iso(changed),
      'System.RevisedDate': '9999-01-01T00:00:00Z',
      'System.IterationId': isRoot ? 1200 : 1200 + sprint.number,
      'System.IterationPath': w.iterationPath,
      'System.IterationLevel1': DemoWorld.area,
      if (!isRoot) 'System.IterationLevel2': sprint.name,
      'System.WorkItemType': w.type,
      'System.State': w.state,
      'System.Reason': DemoProcess.reasonFor(w.type, w.state),
      'System.AssignedTo': ?identity,
      'System.CreatedDate': DemoWorld.iso(created),
      'System.CreatedBy': DemoWorld.kelly.identity(),
      'System.ChangedDate': DemoWorld.iso(changed),
      'System.ChangedBy': changedBy.identity(),
      'System.AuthorizedAs': changedBy.identity(),
      'System.PersonId': 41250000 + (w.id % 97),
      'System.Watermark': 20000 + w.id * 3,
      'System.CommentCount': 0,
      'System.Title': w.title,
      if (column != null) ...{
        'System.BoardColumn': column,
        'System.BoardColumnDone': w.columnDone,
        board!.columnField: column,
        board.doneField: w.columnDone,
      },
      'Microsoft.VSTS.Common.StateChangeDate': DemoWorld.iso(stateChanged),
      if (started) ...{
        'Microsoft.VSTS.Common.ActivatedDate': DemoWorld.iso(
          stateChanged.subtract(const Duration(days: 2)),
        ),
        'Microsoft.VSTS.Common.ActivatedBy': author.identity(),
      },
      if (resolved && !w.isTask) ...{
        'Microsoft.VSTS.Common.ResolvedDate': DemoWorld.iso(stateChanged),
        'Microsoft.VSTS.Common.ResolvedBy': author.identity(),
      },
      if (closed) ...{
        'Microsoft.VSTS.Common.ClosedDate': DemoWorld.iso(stateChanged),
        'Microsoft.VSTS.Common.ClosedBy': author.identity(),
      },
      'Microsoft.VSTS.Common.Priority': w.priority,
      'Microsoft.VSTS.Common.StackRank': _stackRankOf(w),
      if (w.type == 'Bug') ...{
        'Microsoft.VSTS.Common.Severity': w.severity ?? '3 - Medium',
        'Microsoft.VSTS.Common.Activity': 'Development',
        'Microsoft.VSTS.TCM.ReproSteps': ?repro,
        'Microsoft.VSTS.TCM.SystemInfo':
            '<div>iPhone 17 Pro, iOS 26.5, Boardhop 1.0 (17)</div>',
        if (resolved) 'Microsoft.VSTS.Common.ResolvedReason': 'Fixed',
      },
      if (w.type != 'Bug' && !w.isTask)
        'Microsoft.VSTS.Common.ValueArea': w.id == 1255 || w.id == 1246
            ? 'Architectural'
            : 'Business',
      if (w.type == 'User Story') 'Microsoft.VSTS.Common.Risk': '2 - Medium',
      'Microsoft.VSTS.Scheduling.StoryPoints': ?w.points,
      if (w.type == 'Feature' || w.type == 'Epic') ...{
        'Microsoft.VSTS.Scheduling.Effort': w.type == 'Epic' ? 120 : 34,
        'Microsoft.VSTS.Common.BusinessValue': 400 - (w.id % 7) * 40,
        'Microsoft.VSTS.Common.TimeCriticality': 3,
        'Microsoft.VSTS.Scheduling.TargetDate': DemoWorld.iso(
          DemoWorld.sprints.last.finish,
        ),
      },
      if (w.isTask) ...{
        'Microsoft.VSTS.Common.Activity': w.id == 1263 || w.id == 1275
            ? 'Design'
            : w.id == 1261 || w.id == 1277
            ? 'Testing'
            : 'Development',
        'Microsoft.VSTS.Scheduling.OriginalEstimate': estimate,
        if (!closed) 'Microsoft.VSTS.Scheduling.RemainingWork': ?w.remaining,
        'Microsoft.VSTS.Scheduling.CompletedWork': closed
            ? estimate
            : estimate - (w.remaining ?? 0),
      },
      'System.Description': ?(description.isEmpty ? null : description),
      'Microsoft.VSTS.Common.AcceptanceCriteria': ?criteria,
      if (w.tags.isNotEmpty) 'System.Tags': w.tags.join('; '),
      'System.Parent': ?w.parent,
    };
    // A task's CompletedWork is 0 when it has not started.
    if (w.isTask && w.state == 'To Do') {
      fields['Microsoft.VSTS.Scheduling.CompletedWork'] = 0;
      fields['Microsoft.VSTS.Scheduling.OriginalEstimate'] = w.remaining;
    }
    final rev =
        4 +
        (w.id % 7) +
        (DemoWorkContent.comments[w.id]?.length ?? 0) +
        (started ? 2 : 0);
    fields['System.Rev'] = rev;
    return DemoStoredItem(w.id, rev, fields);
  }

  List<Map<String, dynamic>> _relationsOf(DemoWorkItem w) => [
    if (w.parent != null)
      {
        'rel': 'System.LinkTypes.Hierarchy-Reverse',
        'url': itemUrl(w.parent!),
        'attributes': {'isLocked': false, 'name': 'Parent'},
      },
    for (final child in DemoWorld.workItems)
      if (child.parent == w.id)
        {
          'rel': 'System.LinkTypes.Hierarchy-Forward',
          'url': itemUrl(child.id),
          'attributes': {'isLocked': false, 'name': 'Child'},
        },
    for (final (a, b) in _related)
      if (a == w.id || b == w.id)
        {
          'rel': 'System.LinkTypes.Related',
          'url': itemUrl(a == w.id ? b : a),
          'attributes': {'isLocked': false, 'name': 'Related'},
        },
    for (final pr in DemoWorld.pullRequests)
      if (pr.workItems.contains(w.id))
        {
          'rel': 'ArtifactLink',
          'url':
              'vstfs:///Git/PullRequestId/${DemoWorld.projectId}%2F${pr.repo.id}%2F${pr.id}',
          'attributes': {
            'authorizedDate': DemoWorld.iso(
              DemoWorld.hoursAgo(pr.createdHoursAgo),
            ),
            'id': 80000 + pr.id,
            'resourceCreatedDate': DemoWorld.iso(
              DemoWorld.hoursAgo(pr.createdHoursAgo),
            ),
            'resourceModifiedDate': DemoWorld.iso(
              DemoWorld.hoursAgo(pr.createdHoursAgo),
            ),
            'revisedDate': '9999-01-01T00:00:00Z',
            'name': 'Pull Request',
          },
        },
    if (w.id == 1234)
      {
        'rel': 'Hyperlink',
        'url': 'https://kammcs.com/boardhop/design/taskboard',
        'attributes': {
          'authorizedDate': DemoWorld.iso(DemoWorld.daysAgo(9)),
          'id': 91234,
          'resourceCreatedDate': DemoWorld.iso(DemoWorld.daysAgo(9)),
          'resourceModifiedDate': DemoWorld.iso(DemoWorld.daysAgo(9)),
          'revisedDate': '9999-01-01T00:00:00Z',
          'comment': 'Taskboard design notes',
          'name': 'Hyperlink',
        },
      },
  ];

  Map<String, dynamic> _comment(int workItemId, int id, DemoComment c) {
    final html = DemoWorkContent.renderMentions(c.html);
    final at = DemoWorld.iso(DemoWorld.hoursAgo(c.hoursAgo));
    return {
      'mentions': [
        for (final p in DemoWorkContent.mentionedIn(c.html))
          {
            'artifactId': '$id',
            'artifactType': 'Person',
            'commentId': id,
            'targetId': p.id,
          },
      ],
      'workItemId': workItemId,
      'id': id,
      'version': 1,
      'text': html,
      'renderedText': html,
      'format': 'html',
      'createdBy': c.author.identity(),
      'createdDate': at,
      'modifiedBy': c.author.identity(),
      'modifiedDate': at,
      'url': '$_projectUrl/_apis/wit/workItems/$workItemId/comments/$id',
    };
  }

  // ---------------------------------------------------------------- reads

  /// A work item as `workitems/{id}` or `workitemsbatch` answers it.
  Map<String, dynamic> json(
    int id, {
    List<String>? fields,
    bool relations = false,
    bool links = false,
  }) {
    final item = _items[id]!;
    final selected = fields == null
        ? item.fields
        : {
            for (final f in fields)
              if (item.fields.containsKey(f)) f: item.fields[f],
          };
    return {
      'id': id,
      'rev': item.rev,
      'fields': selected,
      if (fields == null) 'multilineFieldsFormat': <String, String>{},
      if (relations) 'relations': item.relations,
      if (links)
        '_links': {
          'self': {'href': itemUrl(id)},
          'workItemUpdates': {'href': '${itemUrl(id)}/updates'},
          'workItemRevisions': {'href': '${itemUrl(id)}/revisions'},
          'workItemComments': {'href': '${itemUrl(id)}/comments'},
          'html': {'href': '$_base/${DemoWorld.projectId}/_workitems/edit/$id'},
          'workItemType': {
            'href': DemoProcess.typeUrl(
              '${item.fields['System.WorkItemType']}',
            ),
          },
          'fields': {'href': '$_projectUrl/_apis/wit/fields'},
        },
      if (fields == null && _comments.containsKey(id))
        'commentVersionRef': {
          'commentId': 6100000 + id * 10,
          'version': 1,
          'url': '${itemUrl(id)}/comments/${6100000 + id * 10}/versions/1',
        },
      'url': itemUrl(id),
    };
  }

  /// Comments newest first, as `order=desc` asks.
  List<Map<String, dynamic>> comments(int id) =>
      (_comments[id] ?? const []).reversed.toList();

  // --------------------------------------------------------------- writes

  /// Applies a JSON Patch; [validateOnly] answers the result without
  /// keeping it. Returns null when the item does not exist.
  Map<String, dynamic>? patch(
    int id,
    List<Object?> ops, {
    bool validateOnly = false,
  }) {
    final item = _items[id];
    if (item == null) return null;
    final fields = Map<String, dynamic>.of(item.fields);
    final relations = List<Map<String, dynamic>>.of(item.relations);
    _apply(fields, relations, ops);
    if (validateOnly) {
      return {
        'id': id,
        'rev': item.rev,
        'fields': fields,
        'relations': relations,
        'url': itemUrl(id),
      };
    }
    item.rev++;
    fields['System.Rev'] = item.rev;
    fields['System.ChangedDate'] = DemoWorld.iso(DateTime.now().toUtc());
    fields['System.ChangedBy'] = DemoWorld.me.identity();
    item.fields
      ..clear()
      ..addAll(fields);
    item.relations
      ..clear()
      ..addAll(relations);
    return json(id, relations: true);
  }

  /// `POST workitems/${type}`.
  Map<String, dynamic> create(
    String type,
    List<Object?> ops, {
    bool validateOnly = false,
  }) {
    final states = DemoProcess.statesOf(type);
    final now = DemoWorld.iso(DateTime.now().toUtc());
    final fields = <String, dynamic>{
      'System.AreaPath': DemoWorld.area,
      'System.TeamProject': DemoWorld.project,
      'System.IterationPath': DemoWorld.area,
      'System.WorkItemType': type,
      'System.State': states.first.$1,
      'System.Reason': DemoProcess.reasonFor(type, states.first.$1),
      'System.CreatedDate': now,
      'System.CreatedBy': DemoWorld.me.identity(),
      'System.ChangedDate': now,
      'System.ChangedBy': DemoWorld.me.identity(),
      'System.CommentCount': 0,
      'Microsoft.VSTS.Common.Priority': 2,
      if (type != 'Task' && type != 'Bug')
        'Microsoft.VSTS.Common.ValueArea': 'Business',
    };
    final relations = <Map<String, dynamic>>[];
    _apply(fields, relations, ops);
    final parent = relations
        .where((r) => r['rel'] == 'System.LinkTypes.Hierarchy-Reverse')
        .map((r) => int.tryParse(Uri.parse('${r['url']}').pathSegments.last))
        .firstOrNull;
    if (parent != null) fields['System.Parent'] = parent;
    if (validateOnly) {
      return {'fields': fields, 'relations': relations};
    }
    final id = _nextId++;
    fields['System.Id'] = id;
    fields['System.Rev'] = 1;
    final board = DemoBoard.forType(type);
    if (board != null && !fields.containsKey(board.columnField)) {
      final column = board.columnForState(type, '${fields['System.State']}');
      fields['System.BoardColumn'] = column;
      fields['System.BoardColumnDone'] = false;
      fields[board.columnField] = column;
      fields[board.doneField] = false;
    }
    _items[id] = DemoStoredItem(id, 1, fields)..relations.addAll(relations);
    if (parent != null) {
      _items[parent]?.relations.add({
        'rel': 'System.LinkTypes.Hierarchy-Forward',
        'url': itemUrl(id),
        'attributes': {'isLocked': false, 'name': 'Child'},
      });
    }
    return json(id, relations: true);
  }

  /// `POST comments?format=markdown|html`.
  Map<String, dynamic>? addComment(int id, String text, String format) {
    if (!_items.containsKey(id)) return null;
    final commentId = _nextCommentId++;
    final mentioned = <DemoPerson>[];
    var rendered = text;
    if (format == 'markdown') {
      final escaped = text
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;');
      rendered = escaped.replaceAllMapped(
        RegExp(r'@&lt;([0-9a-fA-F-]{36})&gt;'),
        (m) {
          final person = DemoWorld.people
              .where((p) => p.id.toLowerCase() == m.group(1)!.toLowerCase())
              .firstOrNull;
          if (person == null) return m.group(0)!;
          mentioned.add(person);
          return DemoWorkContent.mentionAnchor(person);
        },
      );
      rendered = [
        for (final para in rendered.split(RegExp(r'\n\s*\n')))
          '<p>${para.replaceAll('\n', '<br>')}</p>',
      ].join();
    } else {
      for (final m in RegExp(
        r'data-vss-mention="version:2\.0,([0-9a-fA-F-]{36})"',
      ).allMatches(text)) {
        final person = DemoWorld.people
            .where((p) => p.id.toLowerCase() == m.group(1)!.toLowerCase())
            .firstOrNull;
        if (person != null) mentioned.add(person);
      }
    }
    final at = DemoWorld.iso(DateTime.now().toUtc());
    final comment = {
      'mentions': [
        for (final p in mentioned)
          {
            'artifactId': '$commentId',
            'artifactType': 'Person',
            'commentId': commentId,
            'targetId': p.id,
          },
      ],
      'workItemId': id,
      'id': commentId,
      'version': 1,
      'text': text,
      'renderedText': rendered,
      'format': format,
      'createdBy': DemoWorld.me.identity(),
      'createdDate': at,
      'modifiedBy': DemoWorld.me.identity(),
      'modifiedDate': at,
      'url': '$_projectUrl/_apis/wit/workItems/$id/comments/$commentId',
    };
    final list = _comments.putIfAbsent(id, () => []);
    list.add(comment);
    final item = _items[id]!;
    item.fields['System.CommentCount'] = list.length;
    item.rev++;
    item.fields['System.Rev'] = item.rev;
    item.fields['System.ChangedDate'] = at;
    return comment;
  }

  void _apply(
    Map<String, dynamic> fields,
    List<Map<String, dynamic>> relations,
    List<Object?> ops,
  ) {
    for (final raw in ops) {
      if (raw is! Map) continue;
      final op = '${raw['op']}';
      final path = '${raw['path']}';
      final value = raw['value'];
      if (op == 'test') continue;
      if (path.startsWith('/fields/')) {
        final name = path.substring('/fields/'.length);
        if (op == 'remove') {
          fields.remove(name);
        } else {
          _setField(fields, name, value);
        }
      } else if (path == '/relations/-' && value is Map) {
        relations.add(value.cast<String, dynamic>());
      } else if (path.startsWith('/relations/') && op == 'remove') {
        final index = int.tryParse(path.substring('/relations/'.length));
        if (index != null && index >= 0 && index < relations.length) {
          relations.removeAt(index);
        }
      }
    }
  }

  static void _setField(Map<String, dynamic> fields, String name, Object? v) {
    switch (name) {
      case 'System.History':
        return;
      case 'System.AssignedTo' ||
          'Microsoft.VSTS.Common.ActivatedBy' ||
          'Microsoft.VSTS.Common.ResolvedBy' ||
          'Microsoft.VSTS.Common.ClosedBy':
        if (v == null || (v is String && v.isEmpty)) {
          fields.remove(name);
          return;
        }
        final text = v is Map ? '${v['uniqueName'] ?? v['id']}' : '$v';
        final person = DemoWorld.people.where((p) {
          final t = text.toLowerCase();
          return t == p.email ||
              t == p.id ||
              t == p.name.toLowerCase() ||
              t.contains('<${p.email}>');
        }).firstOrNull;
        fields[name] = person?.identity() ?? {'displayName': text};
        return;
      case 'System.State':
        final type = '${fields['System.WorkItemType']}';
        if (fields[name] != v) {
          fields[name] = v;
          fields['System.Reason'] = DemoProcess.reasonFor(type, '$v');
          fields['Microsoft.VSTS.Common.StateChangeDate'] = DemoWorld.iso(
            DateTime.now().toUtc(),
          );
          if (DemoProcess.categoryOf(type, '$v') == 'Completed') {
            fields.remove('Microsoft.VSTS.Scheduling.RemainingWork');
          }
        }
        return;
    }
    if (v == null || (v is String && v.isEmpty)) {
      fields.remove(name);
      return;
    }
    fields[name] = v;
    // The Kanban extension fields mirror into the System board fields.
    for (final board in DemoBoard.all) {
      if (name == board.columnField) fields['System.BoardColumn'] = v;
      if (name == board.doneField) fields['System.BoardColumnDone'] = v;
    }
  }
}

class DemoStoredItem {
  DemoStoredItem(this.id, this.rev, this.fields);

  final int id;
  int rev;
  final Map<String, dynamic> fields;
  final List<Map<String, dynamic>> relations = [];

  String get type => '${fields['System.WorkItemType']}';
  String get state => '${fields['System.State']}';
  String? get iterationPath => fields['System.IterationPath'] as String?;
  int? get parent => fields['System.Parent'] as int?;
  double get stackRank =>
      (fields['Microsoft.VSTS.Common.StackRank'] as num?)?.toDouble() ??
      double.maxFinite;
}
