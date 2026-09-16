import '../demo_backend.dart';
import '../demo_world.dart';
import 'work/boards.dart';
import 'work/process.dart';
import 'work/sprint_data.dart';
import 'work/wiql.dart';
import 'work/work_store.dart';

/// Work items, boards, sprints and the people behind them: every read the
/// Work, Boards and Sprint pages make, the work item detail and form, and
/// the shared work item endpoints other areas lean on (WIQL, the batch
/// read, comments, types, team members).
void registerWorkFixtures(DemoBackend b) {
  final store = DemoWorkStore();

  const org = r'dev\.azure\.com/kammcs';
  final project = '(?:${DemoWorld.project}|${DemoWorld.projectId})';
  final team =
      '(?:Boardhop%20Team|Boardhop Team|${DemoWorld.teamId}|${DemoWorld.team.replaceAll(' ', '%20')})';

  /// `{org}/{project}/_apis/{rest}`.
  String p(String rest) => '$org/$project/_apis/$rest';

  /// `{org}/{project}[/{team}]/_apis/{rest}`.
  String t(String rest) => '$org/$project(?:/$team)?/_apis/$rest';

  /// `{org}[/{project}[/{team}]]/_apis/{rest}`.
  String any(String rest) => '$org(?:/$project(?:/$team)?)?/_apis/$rest';

  List<String>? fieldsParam(Object? raw) {
    if (raw is List) return [for (final f in raw) '$f'];
    if (raw is String && raw.isNotEmpty) return raw.split(',');
    return null;
  }

  bool expands(DemoRequest r, String what) {
    final e = (r.query[r'$expand'] ?? '').toLowerCase();
    return e == 'all' || e == what;
  }

  // ------------------------------------------------------------ WIQL

  Map<String, dynamic> wiqlAnswer(String text, int top) {
    final wiql = DemoWiql(text);
    final rows = wiql.run([for (final i in store.items) i.fields]);
    return {
      'queryType': 'flat',
      'queryResultType': 'workItem',
      'asOf': DemoWorld.iso(DateTime.now().toUtc()),
      'columns': [
        {
          'referenceName': 'System.Id',
          'name': 'ID',
          'url': DemoProcess.fieldUrl('System.Id'),
        },
      ],
      'sortColumns': [
        for (final (field, desc) in wiql.order)
          {
            'field': {
              'referenceName': field,
              'url': DemoProcess.fieldUrl(field),
            },
            'descending': desc,
          },
      ],
      'workItems': [
        for (final f in rows.take(top))
          {
            'id': f['System.Id'],
            'url': DemoWorkStore.itemUrl(f['System.Id'] as int),
          },
      ],
    };
  }

  b.post(any('wit/wiql'), (r) {
    final body = r.body;
    final text = body is Map ? '${body['query'] ?? ''}' : '$body';
    final top = int.tryParse(r.query[r'$top'] ?? '') ?? 20000;
    return wiqlAnswer(text, top);
  });

  // Saved queries.
  final queries = <(String, String, String, String)>[
    // (id, name, folder, wiql)
    (
      '3f6b1d8e-2a4c-4e97-b5d0-8c1e3a6f9b24',
      'Assigned to me',
      'My Queries',
      "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project AND [System.AssignedTo] = @Me AND [System.State] NOT IN ('Closed', 'Done', 'Removed') ORDER BY [System.ChangedDate] DESC",
    ),
    (
      '5a8d3f0b-4c6e-4a19-8d7f-0e3a5c8b1d46',
      'Current sprint',
      'Shared Queries',
      'SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project AND [System.IterationPath] = @CurrentIteration ORDER BY [Microsoft.VSTS.Common.StackRank] ASC',
    ),
    (
      '7c0f5b2d-6e8a-4c3b-9f1a-2b5c7e0d3f68',
      'Active bugs',
      'Shared Queries',
      "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project AND [System.WorkItemType] = 'Bug' AND [System.State] <> 'Closed' AND [System.State] <> 'Removed' ORDER BY [Microsoft.VSTS.Common.Priority] ASC, [System.ChangedDate] DESC",
    ),
    (
      '9e2b7d4f-8a0c-4e5d-8b3c-4d7e9a2f5b8a',
      'Closed this sprint',
      'Shared Queries',
      "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project AND [System.IterationPath] = @CurrentIteration AND [System.State] IN ('Closed', 'Done') ORDER BY [System.ChangedDate] DESC",
    ),
  ];

  String queryUrl(String id) => '${DemoWorld.projectUrl}/_apis/wit/queries/$id';

  Map<String, dynamic> queryJson(
    (String, String, String, String) q, {
    bool withWiql = false,
  }) => {
    'id': q.$1,
    'name': q.$2,
    'path': '${q.$3}/${q.$2}',
    'createdDate': DemoWorld.iso(DemoWorld.daysAgo(60)),
    'lastModifiedBy': DemoWorld.kelly.identity(),
    'lastModifiedDate': DemoWorld.iso(DemoWorld.daysAgo(20)),
    'isPublic': q.$3 == 'Shared Queries',
    'isFolder': false,
    'hasChildren': false,
    if (withWiql) ...{
      'queryType': 'flat',
      'wiql': q.$4,
      'columns': [
        for (final f in const [
          'System.Id',
          'System.WorkItemType',
          'System.Title',
          'System.AssignedTo',
          'System.State',
          'System.Tags',
        ])
          {'referenceName': f, 'url': DemoProcess.fieldUrl(f)},
      ],
    },
    '_links': {
      'self': {'href': queryUrl(q.$1)},
      'wiql': {'href': '${DemoWorld.projectUrl}/_apis/wit/wiql/${q.$1}'},
    },
    'url': queryUrl(q.$1),
  };

  b.get(p('wit/queries'), (r) {
    Map<String, dynamic> folder(String id, String name) => {
      'id': id,
      'name': name,
      'path': name,
      'isFolder': true,
      'hasChildren': true,
      'isPublic': name == 'Shared Queries',
      'children': [
        for (final q in queries)
          if (q.$3 == name) queryJson(q),
      ],
      'url': queryUrl(id),
    };
    final value = [
      folder('1b4e8c2a-0d6f-4a73-9e5b-7c2a4f6d8e10', 'My Queries'),
      folder('2c5f9d3b-1e7a-4b84-8f6c-8d3b5a7e9f21', 'Shared Queries'),
    ];
    return {'count': value.length, 'value': value};
  });

  (String, String, String, String)? queryById(String id) {
    for (final q in queries) {
      if (q.$1 == id) return q;
    }
    return null;
  }

  // Only this area's own query ids: the dashboard fixtures serve the
  // queries behind their widgets on the same routes, and a handler that
  // answered null for those would end the routing with a miss.
  final ours = '(${[for (final q in queries) q.$1].join('|')})';

  b.get(p('wit/queries/$ours'), (r) {
    final q = queryById(r.group(1));
    return q == null ? null : queryJson(q, withWiql: true);
  });
  b.get(p('wit/wiql/$ours'), (r) {
    final q = queryById(r.group(1));
    if (q == null) return null;
    final top = int.tryParse(r.query[r'$top'] ?? '') ?? 20000;
    return wiqlAnswer(q.$4, top);
  });
  // No X-Total-Count from the demo: the repository falls back to the GET.
  b.on('HEAD', p('wit/wiql/$ours'), (_) => const DemoResponse(200));

  // ---------------------------------------------------------- work items

  List<int> idsParam(Object? raw) => [
    for (final s in '${raw ?? ''}'.split(','))
      if (int.tryParse(s.trim()) != null) int.parse(s.trim()),
  ];

  b.post(any('wit/workitemsbatch'), (r) {
    final body = (r.body as Map?) ?? const {};
    final ids = [
      for (final id in (body['ids'] as List?) ?? const [])
        if (id is int && store[id] != null) id,
    ];
    final expand = '${body[r'$expand'] ?? ''}'.toLowerCase();
    final value = [
      for (final id in ids)
        store.json(
          id,
          fields: fieldsParam(body['fields']),
          relations: expand == 'all' || expand == 'relations',
        ),
    ];
    return {'count': value.length, 'value': value};
  });

  b.get(any('wit/workitems'), (r) {
    final ids = idsParam(r.query['ids']);
    final value = [
      for (final id in ids)
        if (store[id] != null)
          store.json(
            id,
            fields: fieldsParam(r.query['fields']),
            relations: expands(r, 'relations'),
            links: expands(r, 'links'),
          ),
    ];
    return {'count': value.length, 'value': value};
  });

  b.get(any('wit/work[Ii]tems/(\\d+)'), (r) {
    final id = int.parse(r.group(1));
    if (store[id] == null) {
      return DemoResponse(404, {
        'message':
            'TF401232: Work item $id does not exist, or you do not have '
            'permissions to read it.',
        'typeKey': 'WorkItemUnauthorizedAccessException',
      });
    }
    return store.json(
      id,
      fields: fieldsParam(r.query['fields']),
      relations: expands(r, 'relations'),
      links: expands(r, 'links'),
    );
  });

  b.patch(any('wit/work[Ii]tems/(\\d+)'), (r) {
    final ops = r.body is List ? r.body as List : const [];
    return store.patch(
      int.parse(r.group(1)),
      ops,
      validateOnly: r.query['validateOnly'] == 'true',
    );
  });

  b.post(any(r'wit/work[Ii]tems/(?:\$|%24)([^/]+)'), (r) {
    final type = r.group(1);
    if (DemoProcess.type(type) == null) return null;
    final ops = r.body is List ? r.body as List : const [];
    return store.create(
      type,
      ops,
      validateOnly: r.query['validateOnly'] == 'true',
    );
  });

  b.get(any('wit/work[Ii]tems/(\\d+)/comments'), (r) {
    final id = int.parse(r.group(1));
    if (store[id] == null) return null;
    final newestFirst = store.comments(id);
    final list = (r.query['order'] ?? 'desc').toLowerCase() == 'asc'
        ? newestFirst.reversed.toList()
        : newestFirst;
    final top = int.tryParse(r.query[r'$top'] ?? '') ?? 200;
    final page = list.take(top).toList();
    return {
      'totalCount': list.length,
      'count': page.length,
      'comments': page,
      'url': '${DemoWorkStore.itemUrl(id)}/comments',
    };
  });

  b.post(any('wit/work[Ii]tems/(\\d+)/comments'), (r) {
    final body = r.body;
    final text = body is Map ? '${body['text'] ?? ''}' : '$body';
    return store.addComment(
      int.parse(r.group(1)),
      text,
      (r.query['format'] ?? 'markdown').toLowerCase(),
    );
  });

  // Nothing in the demo has history beyond its current revision.
  b.get(any('wit/work[Ii]tems/(\\d+)/updates'), (r) {
    final id = int.parse(r.group(1));
    final item = store[id];
    if (item == null) return null;
    return {
      'count': 1,
      'value': [
        {
          'id': 1,
          'workItemId': id,
          'rev': item.rev,
          'revisedBy': item.fields['System.ChangedBy'],
          'revisedDate': item.fields['System.ChangedDate'],
          'fields': {
            for (final e in item.fields.entries) e.key: {'newValue': e.value},
          },
        },
      ],
    };
  });

  // ------------------------------------------------ types, fields, process

  b.get(p('wit/workitemtypes'), (_) => DemoProcess.typeList());
  b.get(p('wit/workitemtypes/([^/]+)'), (r) => DemoProcess.type(r.group(1)));
  b.get(
    p('wit/workitemtypes/([^/]+)/states'),
    (r) => DemoProcess.states(r.group(1)),
  );
  b.get(p('wit/workitemtypes/([^/]+)/fields'), (r) {
    if (DemoProcess.type(r.group(1)) == null) return null;
    final value = DemoProcess.typeFields(r.group(1));
    return {'count': value.length, 'value': value};
  });
  b.get(p('wit/workitemtypecategories'), (_) => DemoProcess.typeCategories());
  b.get(any('wit/fields'), (_) => DemoProcess.orgFields());

  b.get(p('wit/classificationnodes/areas'), (_) {
    return DemoSprintData.classificationNodes(areas: true);
  });
  b.get(p('wit/classificationnodes/iterations'), (_) {
    return DemoSprintData.classificationNodes(areas: false);
  });

  b.get(p('wit/tags'), (_) {
    final names = <String>{
      for (final w in DemoWorld.workItems) ...w.tags,
    }.toList()..sort();
    return {
      'count': names.length,
      'value': [
        for (final (i, n) in names.indexed)
          {
            'id': '7a1e0c3b-5d2f-4b6a-9c8e-${(100000000000 + i).toString()}',
            'name': n,
            'url': '${DemoWorld.projectUrl}/_apis/wit/tags/$n',
          },
      ],
    };
  });

  const bugTemplateId = 'c3e7a9d1-6b2f-4f80-a4c5-9d1e3b7f5a28';
  Map<String, dynamic> bugTemplate({bool withFields = false}) => {
    'id': bugTemplateId,
    'name': 'Crash report',
    'description': 'A bug from a TestFlight crash report',
    'workItemTypeName': 'Bug',
    if (withFields)
      'fields': {
        'System.Tags': 'crash; testflight',
        'Microsoft.VSTS.Common.Priority': '1',
        'Microsoft.VSTS.Common.Severity': '2 - High',
        'Microsoft.VSTS.TCM.SystemInfo':
            '<div>Build: </div><div>Device: </div>',
      },
    'url':
        '${DemoWorld.projectUrl}/${DemoWorld.teamId}/_apis/wit/templates/$bugTemplateId',
  };
  b.get(
    t('wit/templates'),
    (_) => {
      'count': 1,
      'value': [bugTemplate()],
    },
  );
  b.get(
    t('wit/templates/$bugTemplateId'),
    (_) => bugTemplate(withFields: true),
  );

  // ---------------------------------------------------------- team settings

  b.get(
    t('work/backlogconfiguration'),
    (_) => DemoProcess.backlogConfiguration(),
  );
  b.get(t('work/teamsettings'), (_) => DemoSprintData.teamSettings());
  b.get(
    t('work/teamsettings/teamfieldvalues'),
    (_) => DemoSprintData.teamFieldValues(),
  );
  b.get(
    t('work/teamsettings/iterations'),
    (r) => DemoSprintData.teamIterations(timeframe: r.query[r'$timeframe']),
  );
  b.get(t('work/teamsettings/iterations/([0-9a-fA-F-]{36})'), (r) {
    final s = DemoSprintData.sprintById(r.group(1));
    return s == null ? null : DemoSprintData.teamIteration(s);
  });

  b.get(t('work/teamsettings/iterations/([0-9a-fA-F-]{36})/workitems'), (r) {
    final s = DemoSprintData.sprintById(r.group(1));
    if (s == null) return null;
    final inSprint = [
      for (final i in store.items)
        if (i.iterationPath == s.path) i,
    ]..sort((a, b) => a.stackRank.compareTo(b.stackRank));
    final ids = {for (final i in inSprint) i.id};
    Map<String, dynamic> ref(int id) => {
      'id': id,
      'url': DemoWorkStore.itemUrl(id),
    };
    final relations = <Map<String, dynamic>>[];
    for (final item in inSprint) {
      final parent = item.parent;
      if (item.type == 'Task' && parent != null && ids.contains(parent)) {
        continue;
      }
      relations.add({'rel': null, 'source': null, 'target': ref(item.id)});
      for (final child in inSprint) {
        if (child.type == 'Task' && child.parent == item.id) {
          relations.add({
            'rel': 'System.LinkTypes.Hierarchy-Forward',
            'source': ref(item.id),
            'target': ref(child.id),
          });
        }
      }
    }
    return {
      'workItemRelations': relations,
      'url':
          '${DemoWorld.projectUrl}/${DemoWorld.teamId}/_apis/work/teamsettings/iterations/${s.id}/workitems',
      '_links': {
        'self': {
          'href':
              '${DemoWorld.projectUrl}/${DemoWorld.teamId}/_apis/work/teamsettings/iterations/${s.id}/workitems',
        },
      },
    };
  });

  b.get(t('work/teamsettings/iterations/([0-9a-fA-F-]{36})/capacities'), (r) {
    final s = DemoSprintData.sprintById(r.group(1));
    return s == null ? null : DemoSprintData.capacities(s);
  });
  b.get(t('work/teamsettings/iterations/([0-9a-fA-F-]{36})/teamdaysoff'), (r) {
    final s = DemoSprintData.sprintById(r.group(1));
    return s == null ? null : DemoSprintData.teamDaysOff(s);
  });

  // The team never customized its taskboard, like most teams: columns come
  // from the state categories.
  b.get(
    t('work/taskboardcolumns'),
    (_) => {
      'columns': const [],
      'isCustomized': false,
      'isValid': true,
      'validationMesssage': '',
    },
  );
  b.patch(
    t('work/taskboardworkitems/([0-9a-fA-F-]{36})/(\\d+)'),
    (_) => const DemoResponse(204),
  );

  b.patch(t('work/workitemsorder'), (r) {
    final body = (r.body as Map?) ?? const {};
    final ids = [
      for (final id in (body['ids'] as List?) ?? const [])
        if (id is int) id,
    ];
    final previous = store[body['previousId'] as int? ?? 0]?.stackRank;
    final next = store[body['nextId'] as int? ?? 0]?.stackRank;
    final low = previous ?? ((next ?? 1000) - 1000);
    final high = next ?? (low + 1000);
    final step = (high - low) / (ids.length + 1);
    final value = <Map<String, dynamic>>[];
    for (final (i, id) in ids.indexed) {
      final order = low + step * (i + 1);
      final item = store[id];
      if (item != null) {
        item.fields['Microsoft.VSTS.Common.StackRank'] = order;
      }
      value.add({'id': id, 'order': order});
    }
    return {'count': value.length, 'value': value};
  });

  // ------------------------------------------------------------- boards

  b.get(
    t('work/boards'),
    (_) => {
      'count': DemoBoard.all.length,
      'value': [for (final board in DemoBoard.all) board.summary()],
    },
  );
  b.get(
    t('work/boards/([^/]+)'),
    (r) => DemoBoard.byIdOrName(r.group(1))?.json(),
  );
  b.get(t('work/boards/([^/]+)/columns'), (r) {
    final columns = DemoBoard.byIdOrName(r.group(1))?.columnsJson();
    return columns == null ? null : {'count': columns.length, 'value': columns};
  });
  b.get(t('work/boards/([^/]+)/rows'), (r) {
    final rows = DemoBoard.byIdOrName(r.group(1))?.rowsJson();
    return rows == null ? null : {'count': rows.length, 'value': rows};
  });
  b.get(
    t('work/boards/([^/]+)/cardsettings'),
    (r) => DemoBoard.byIdOrName(r.group(1))?.cardSettings(),
  );
  b.get(t('work/boards/([^/]+)/cardrulesettings'), (r) {
    if (DemoBoard.byIdOrName(r.group(1)) == null) return null;
    return {
      'rules': {
        'fill': [
          {
            'name': 'Priority 1',
            'isEnabled': 'true',
            'filter': '[Microsoft.VSTS.Common.Priority] = 1',
            'clauses': [
              {
                'fieldName': 'Microsoft.VSTS.Common.Priority',
                'index': 1,
                'logicalOperator': '',
                'operator': '=',
                'value': '1',
              },
            ],
            'settings': {
              'title-color': '#000000',
              'background-color': '#FBE9E7',
            },
          },
        ],
        'tagStyle': [
          {
            'name': 'tablet',
            'isEnabled': 'true',
            'settings': {
              'background-color': '#E3F2FD',
              'title-color': '#0D47A1',
            },
          },
        ],
      },
      '_links': const {},
    };
  });

  // ------------------------------------------------------------- people

  Map<String, dynamic> teamRef() => {
    'id': DemoWorld.teamId,
    'name': DemoWorld.team,
    'url':
        '${DemoWorld.baseUrl}/_apis/projects/${DemoWorld.projectId}/teams/${DemoWorld.teamId}',
    'description': 'The Boardhop team.',
    'identityUrl':
        'https://spsprodcus5.vssps.visualstudio.com/_apis/Identities/${DemoWorld.teamId}',
    'projectName': DemoWorld.project,
    'projectId': DemoWorld.projectId,
  };

  b.get(
    '$org/_apis/projects/$project/teams',
    (_) => {
      'count': 1,
      'value': [teamRef()],
    },
  );
  b.get('$org/_apis/projects/$project/teams/$team', (_) => teamRef());
  b.get(
    '$org/_apis/projects/$project/teams/$team/members',
    (_) => {
      'count': DemoWorld.people.length,
      'value': [
        for (final person in DemoWorld.people)
          {
            'isTeamAdmin': person.id == DemoWorld.kelly.id,
            'identity': person.identity(),
          },
      ],
    },
  );

  const vssps = r'vssps\.dev\.azure\.com/kammcs/_apis';
  b.get(
    '$vssps/graph/descriptors/${DemoWorld.projectId}',
    (_) => {'value': 'scp.${DemoWorld.projectId.replaceAll('-', '')}'},
  );

  Map<String, dynamic> graphUser(DemoPerson person) => {
    'subjectKind': 'user',
    'domain': 'AgileDevOps',
    'principalName': person.email,
    'mailAddress': person.email,
    'origin': 'aad',
    'originId': person.id.split('').reversed.join(),
    'displayName': person.name,
    'descriptor': person.descriptor,
    '_links': {
      'avatar': {
        'href':
            'https://vssps.dev.azure.com/kammcs/_apis/GraphProfile/MemberAvatars/${person.descriptor}',
      },
    },
  };

  b.post('$vssps/graph/subjectquery', (r) {
    final body = (r.body as Map?) ?? const {};
    final q = '${body['query'] ?? ''}'.toLowerCase();
    final value = [
      for (final person in DemoWorld.people)
        if (person.name.toLowerCase().contains(q) ||
            person.email.toLowerCase().contains(q))
          graphUser(person),
    ];
    return {'count': value.length, 'value': value};
  });
  b.get('$vssps/graph/storagekeys/([^/]+)', (r) {
    final descriptor = r.group(1);
    for (final person in DemoWorld.people) {
      if (person.descriptor == descriptor) return {'value': person.id};
    }
    return null;
  });
}
