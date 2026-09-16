import '../../demo_world.dart';

/// Iterations, capacity and the burndown's Analytics rows.
abstract final class DemoSprintData {
  static String _date(DateTime d) =>
      '${DateTime.utc(d.year, d.month, d.day).toIso8601String().substring(0, 19)}Z';

  static String timeFrameOf(DemoSprint s) {
    final today = DemoWorld.today;
    if (today.isBefore(s.start)) return 'future';
    if (today.isAfter(s.finish)) return 'past';
    return 'current';
  }

  static DemoSprint? sprintById(String id) {
    for (final s in DemoWorld.sprints) {
      if (s.id == id) return s;
    }
    return null;
  }

  static String _iterationUrl(DemoSprint s) =>
      '${DemoWorld.projectUrl}/${DemoWorld.teamId}/_apis/work/teamsettings/iterations/${s.id}';

  static Map<String, dynamic> teamIteration(DemoSprint s) => {
    'id': s.id,
    'name': s.name,
    'path': s.path,
    'attributes': {
      'startDate': _date(s.start),
      'finishDate': _date(s.finish),
      'timeFrame': timeFrameOf(s),
    },
    'url': _iterationUrl(s),
  };

  /// `GET {team}/_apis/work/teamsettings/iterations[?$timeframe=current]`.
  static Map<String, dynamic> teamIterations({String? timeframe}) {
    final list = [
      for (final s in DemoWorld.sprints)
        if (timeframe == null || timeFrameOf(s) == timeframe) teamIteration(s),
    ];
    return {'count': list.length, 'value': list};
  }

  /// `GET {team}/_apis/work/teamsettings`.
  static Map<String, dynamic> teamSettings() => {
    'backlogIteration': {
      'id': '0d6a1f3e-7c2b-4e58-9a14-3b6d8f0c2e71',
      'name': DemoWorld.project,
      'path': '',
      'url': '${DemoWorld.projectUrl}/_apis/wit/classificationNodes/Iterations',
    },
    'bugsBehavior': 'asRequirements',
    'workingDays': const [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
    ],
    'backlogVisibilities': const {
      'Microsoft.EpicCategory': true,
      'Microsoft.FeatureCategory': true,
      'Microsoft.RequirementCategory': true,
    },
    'defaultIteration': null,
    'defaultIterationMacro': '@currentIteration',
    'url':
        '${DemoWorld.projectUrl}/${DemoWorld.teamId}/_apis/work/teamsettings',
  };

  static Map<String, dynamic> teamFieldValues() => {
    'field': {
      'referenceName': 'System.AreaPath',
      'url': '${DemoWorld.baseUrl}/_apis/wit/fields/System.AreaPath',
    },
    'defaultValue': DemoWorld.area,
    'values': [
      {'value': DemoWorld.area, 'includeChildren': true},
    ],
    'url':
        '${DemoWorld.projectUrl}/${DemoWorld.teamId}/_apis/work/teamsettings/teamfieldvalues',
  };

  /// `wit/classificationnodes/areas|iterations?$depth=10`.
  static Map<String, dynamic> classificationNodes({required bool areas}) {
    final kind = areas ? 'Area' : 'Iteration';
    final structure = areas ? 'area' : 'iteration';
    Map<String, dynamic> node(
      int id,
      String identifier,
      String name,
      String path, {
      Map<String, dynamic>? attributes,
      List<Map<String, dynamic>> children = const [],
    }) => {
      'id': id,
      'identifier': identifier,
      'name': name,
      'structureType': structure,
      'hasChildren': children.isNotEmpty,
      'path': path,
      'attributes': ?attributes,
      if (children.isNotEmpty) 'children': children,
      'url':
          '${DemoWorld.projectUrl}/_apis/wit/classificationNodes/${kind}s${path.split(r'\').skip(3).map((s) => '/${Uri.encodeComponent(s)}').join()}',
    };
    final root = '\\${DemoWorld.project}\\$kind';
    if (areas) {
      return node(
        1100,
        '2b7e4c1a-9d3f-4a86-b5e0-1c7a3f9d2e64',
        DemoWorld.area,
        root,
        children: [
          node(
            1101,
            '4d9a6e3c-1f5b-4c08-a7d2-3e9c5b1f4a86',
            'App',
            '$root\\App',
          ),
          node(
            1102,
            '6f1c8a5e-3b7d-4e2a-9c4f-5a1e7d3b6c08',
            'Relay',
            '$root\\Relay',
          ),
          node(
            1103,
            '8b3e0c7a-5d9f-4a4c-8e6b-7c3a9f5d8e2a',
            'Extension',
            '$root\\Extension',
          ),
        ],
      );
    }
    return node(
      1200,
      '0d6a1f3e-7c2b-4e58-9a14-3b6d8f0c2e71',
      DemoWorld.project,
      root,
      children: [
        for (final s in DemoWorld.sprints)
          node(
            1200 + s.number,
            s.id,
            s.name,
            '$root\\${s.name}',
            attributes: {
              'startDate': _date(s.start),
              'finishDate': _date(s.finish),
            },
          ),
      ],
    );
  }

  // ------------------------------------------------------------ capacity

  /// (person, activity, hours a day).
  static const _capacity = <(DemoPerson, String, num)>[
    (DemoWorld.kelly, 'Development', 5),
    (DemoWorld.priya, 'Development', 6),
    (DemoWorld.marcus, 'Development', 6),
    (DemoWorld.sofia, 'Design', 2),
    (DemoWorld.sofia, 'Development', 4),
    (DemoWorld.jonah, 'Development', 6),
    (DemoWorld.aiko, 'Development', 6),
  ];

  /// `iterations/{id}/capacities`: Marcus is off on the sprint's last
  /// Thursday.
  static Map<String, dynamic> capacities(DemoSprint s) {
    final members = <Map<String, dynamic>>[];
    for (final person in DemoWorld.people) {
      final rows = [
        for (final c in _capacity)
          if (c.$1.id == person.id) c,
      ];
      if (rows.isEmpty) continue;
      final dayOff = s.finish.subtract(const Duration(days: 1));
      members.add({
        'teamMember': {
          'displayName': person.name,
          'url': person.identity()['url'],
          '_links': person.identity()['_links'],
          'id': person.id,
          'uniqueName': person.email,
          'imageUrl': person.identity()['imageUrl'],
          'descriptor': person.descriptor,
        },
        'activities': [
          for (final r in rows) {'capacityPerDay': r.$3, 'name': r.$2},
        ],
        'daysOff': [
          if (person.id == DemoWorld.marcus.id)
            {'start': _date(dayOff), 'end': _date(dayOff)},
        ],
        'url': '${_iterationUrl(s)}/capacities/${person.id}',
      });
    }
    return {
      'teamMembers': members,
      'totalCapacityPerDay': _capacity.fold<num>(0, (n, c) => n + c.$3),
      'totalDaysOff': 1,
    };
  }

  static Map<String, dynamic> teamDaysOff(DemoSprint s) => {
    'daysOff': const [],
    'url': '${_iterationUrl(s)}/teamdaysoff',
  };
}
