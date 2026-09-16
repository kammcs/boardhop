import '../../demo_world.dart';

/// One Kanban column: (id, name, type, split, state per work item type).
typedef DemoBoardColumn = (String, String, String, bool, Map<String, String>);

/// A team board and the per-board `WEF_*_Kanban.*` fields its cards carry.
class DemoBoard {
  const DemoBoard({
    required this.id,
    required this.name,
    required this.wef,
    required this.types,
    required this.columns,
    this.backlogLevel = 'Microsoft.RequirementCategory',
  });

  final String id;
  final String name;

  /// The extension field prefix (`WEF_{guid}`), stable per board.
  final String wef;
  final List<String> types;
  final List<DemoBoardColumn> columns;
  final String backlogLevel;

  String get columnField => '${wef}_Kanban.Column';
  String get doneField => '${wef}_Kanban.Column.Done';
  String get laneField => '${wef}_Kanban.Lane';

  String get url =>
      '${DemoWorld.projectUrl}/${DemoWorld.teamId}/_apis/work/boards/$id';

  Map<String, dynamic> summary() => {'id': id, 'name': name, 'url': url};

  List<Map<String, dynamic>> columnsJson() => [
    for (final c in columns)
      {
        'id': c.$1,
        'name': c.$2,
        'itemLimit': switch (c.$3) {
          'inProgress' => c.$4 ? 5 : 4,
          _ => 0,
        },
        'stateMappings': c.$5,
        'columnType': c.$3,
        'isSplit': c.$4,
        'description': c.$2 == 'Ready'
            ? 'Refined, estimated and small enough for one sprint.'
            : c.$2 == 'Review'
            ? 'Pull request open and the build is green.'
            : '',
      },
  ];

  static const _defaultRowId = '00000000-0000-0000-0000-000000000000';

  List<Map<String, dynamic>> rowsJson() => [
    {'id': _defaultRowId, 'name': null, 'color': null},
  ];

  /// `GET {team}/_apis/work/boards/{id}`.
  Map<String, dynamic> json() => {
    'id': id,
    'name': name,
    'url': url,
    'revision': 7,
    'columns': columnsJson(),
    'rows': rowsJson(),
    'isValid': true,
    'allowedMappings': {
      for (final kind in const ['incoming', 'inProgress', 'outgoing'])
        kind: {
          for (final t in types)
            t: <String>{
              for (final c in columns)
                if (c.$3 == kind && c.$5[t] != null) c.$5[t]!,
            }.toList(),
        },
    },
    'canEdit': true,
    'fields': {
      'columnField': {
        'referenceName': columnField,
        'url': '${DemoWorld.baseUrl}/_apis/wit/fields/$columnField',
      },
      'rowField': {
        'referenceName': laneField,
        'url': '${DemoWorld.baseUrl}/_apis/wit/fields/$laneField',
      },
      'doneField': {
        'referenceName': doneField,
        'url': '${DemoWorld.baseUrl}/_apis/wit/fields/$doneField',
      },
    },
    '_links': {
      'self': {'href': url},
      'project': {
        'href': '${DemoWorld.baseUrl}/_apis/projects/${DemoWorld.projectId}',
      },
      'team': {
        'href':
            '${DemoWorld.baseUrl}/_apis/projects/${DemoWorld.projectId}/teams/${DemoWorld.teamId}',
      },
    },
  };

  /// `cardsettings`: the fields a card shows per type.
  Map<String, dynamic> cardSettings() => {
    'cards': {
      for (final t in types)
        t: [
          {'fieldIdentifier': 'System.Id'},
          {'fieldIdentifier': 'System.Title'},
          {
            'fieldIdentifier': 'System.AssignedTo',
            'displayFormat': 'AvatarAndFullName',
          },
          if (t != 'Task')
            {'fieldIdentifier': 'Microsoft.VSTS.Scheduling.StoryPoints'},
          {'fieldIdentifier': 'System.Tags'},
          {'showEmptyFields': 'false'},
        ],
    },
  };

  /// The column a type in [state] lands in when no column value is known.
  String columnForState(String type, String state) {
    for (final c in columns) {
      if (c.$5[type] == state) return c.$2;
    }
    return columns.first.$2;
  }

  static const stories = DemoBoard(
    id: 'd4b7e2a9-3c1f-4e86-9a0b-5f2c7d8e1a36',
    name: 'Stories',
    wef: 'WEF_8C3E1B5A6D2F4A7E9B0C1D2E3F4A5B6C',
    types: ['User Story', 'Bug'],
    columns: [
      (
        '5e1a9c3d-0b2f-4d7e-8a6c-1f3b5d7e9a02',
        'New',
        'incoming',
        false,
        {'User Story': 'New', 'Bug': 'New'},
      ),
      (
        '7c2b4e6f-1a3d-4f58-9b0e-2d4f6a8c0e13',
        'Ready',
        'inProgress',
        false,
        {'User Story': 'New', 'Bug': 'New'},
      ),
      (
        '9e3d5f7a-2b4c-4a69-8c1f-3e5a7b9d1f24',
        'In Progress',
        'inProgress',
        true,
        {'User Story': 'Active', 'Bug': 'Active'},
      ),
      (
        '1f4e6a8b-3c5d-4b7a-9d2a-4f6b8c0e2a35',
        'Review',
        'inProgress',
        false,
        {'User Story': 'Resolved', 'Bug': 'Resolved'},
      ),
      (
        '3a5f7b9c-4d6e-4c8b-8e3b-5a7c9d1f3b46',
        'Done',
        'outgoing',
        false,
        {'User Story': 'Closed', 'Bug': 'Closed'},
      ),
    ],
  );

  static const features = DemoBoard(
    id: 'e5c8f3b0-4d2a-4f97-8b1c-6a3d8e9f2b47',
    name: 'Features',
    wef: 'WEF_2D7F9A1C3E5B4D6F8A0B2C4D6E8F0A1B',
    types: ['Feature'],
    backlogLevel: 'Microsoft.FeatureCategory',
    columns: [
      (
        '6b8d0f2a-5e7c-4d9a-8f4c-6b8d0f2a4c57',
        'New',
        'incoming',
        false,
        {'Feature': 'New'},
      ),
      (
        '8d0f2b4c-6f8e-4eab-9a5d-7c9e1b3d5e68',
        'Active',
        'inProgress',
        false,
        {'Feature': 'Active'},
      ),
      (
        '0f2b4d6e-7a9f-4fbc-8b6e-8d0f2c4e6f79',
        'Resolved',
        'inProgress',
        false,
        {'Feature': 'Resolved'},
      ),
      (
        '2b4d6f8a-8bae-4acd-9c7f-9e1a3d5f7a8a',
        'Closed',
        'outgoing',
        false,
        {'Feature': 'Closed'},
      ),
    ],
  );

  static const epics = DemoBoard(
    id: 'f6d9a4c1-5e3b-4a08-9c2d-7b4e9fa03c58',
    name: 'Epics',
    wef: 'WEF_4F9B3D5A7C1E4F8B9D2A3C5E7F9B1D3E',
    types: ['Epic'],
    backlogLevel: 'Microsoft.EpicCategory',
    columns: [
      (
        '4d6f8a0b-9cbf-4bde-8d8a-0f2b4e6a8b9b',
        'New',
        'incoming',
        false,
        {'Epic': 'New'},
      ),
      (
        '6f8a0b2c-adc0-4cef-9e9b-1a3c5f7b9cac',
        'Active',
        'inProgress',
        false,
        {'Epic': 'Active'},
      ),
      (
        '8a0b2c4d-bed1-4df0-8fac-2b4d6a8cadbd',
        'Resolved',
        'inProgress',
        false,
        {'Epic': 'Resolved'},
      ),
      (
        'a0b2c4d6-cfe2-4e01-9abd-3c5e7b9dbece',
        'Closed',
        'outgoing',
        false,
        {'Epic': 'Closed'},
      ),
    ],
  );

  /// Stories first: the board the page opens on.
  static const all = [stories, features, epics];

  static DemoBoard? byIdOrName(String key) {
    final wanted = Uri.decodeComponent(key).toLowerCase();
    for (final b in all) {
      if (b.id == wanted || b.name.toLowerCase() == wanted) return b;
    }
    return null;
  }

  static DemoBoard? forType(String type) {
    for (final b in all) {
      if (b.types.contains(type)) return b;
    }
    return null;
  }
}
