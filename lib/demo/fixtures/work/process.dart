import '../../demo_world.dart';

/// The Boardhop project's process, an Agile inheritance whose Task type
/// uses To Do / In Progress / Done: work item types with their states,
/// colors, transitions, fields and the legacy `xmlForm` the form reads.
abstract final class DemoProcess {
  static const base = DemoWorld.baseUrl;
  static const projectUrl = DemoWorld.projectUrl;

  static const typeNames = ['Epic', 'Feature', 'User Story', 'Bug', 'Task'];

  static const _proposed = 'b2b2b2';
  static const _active = '007acc';
  static const _resolved = 'ff9d00';
  static const _closed = '339933';

  static const _requirementStates = [
    ('New', _proposed, 'Proposed'),
    ('Active', _active, 'InProgress'),
    ('Resolved', _resolved, 'Resolved'),
    ('Closed', _closed, 'Completed'),
    ('Removed', 'ffffff', 'Removed'),
  ];

  static const _taskStates = [
    ('To Do', _proposed, 'Proposed'),
    ('In Progress', _active, 'InProgress'),
    ('Done', _closed, 'Completed'),
    ('Removed', 'ffffff', 'Removed'),
  ];

  static List<(String, String, String)> statesOf(String type) =>
      type == 'Task' ? _taskStates : _requirementStates;

  /// State → category (`Proposed`, `InProgress`, `Resolved`, `Completed`).
  static String categoryOf(String type, String state) {
    for (final s in statesOf(type)) {
      if (s.$1 == state) return s.$3;
    }
    return 'InProgress';
  }

  static const _types = <String, (String, String, String, String)>{
    // name: (referenceName, color, icon, description)
    'Epic': (
      'Microsoft.VSTS.WorkItemTypes.Epic',
      'FF7B00',
      'icon_crown',
      'Epics help teams effectively manage and groom their product backlog',
    ),
    'Feature': (
      'Microsoft.VSTS.WorkItemTypes.Feature',
      '773B93',
      'icon_trophy',
      'Tracks a feature that will be released with the product',
    ),
    'User Story': (
      'Microsoft.VSTS.WorkItemTypes.UserStory',
      '009CCC',
      'icon_book',
      'Tracks an activity the user will be able to perform with the product',
    ),
    'Bug': (
      'Microsoft.VSTS.WorkItemTypes.Bug',
      'CC293D',
      'icon_insect',
      'Describes a divergence between required and actual behavior',
    ),
    'Task': (
      'Microsoft.VSTS.WorkItemTypes.Task',
      'F2CB1D',
      'icon_clipboard',
      'Tracks work that needs to be done',
    ),
  };

  static String typeUrl(String type) =>
      '$projectUrl/_apis/wit/workItemTypes/${Uri.encodeComponent(type)}';

  static String colorOf(String type) => _types[type]?.$2 ?? '009CCC';

  /// The reason a state carries when an item arrives in it.
  static String reasonFor(String type, String state) => switch ((type, state)) {
    ('Task', 'To Do') => 'Added to backlog',
    ('Task', 'In Progress') => 'Started',
    ('Task', 'Done') => 'Completed',
    ('Bug', 'New') => 'New',
    ('Bug', 'Active') => 'Approved',
    ('Bug', 'Resolved') => 'Fixed',
    ('Bug', 'Closed') => 'Verified',
    (_, 'New') => 'New',
    (_, 'Active') => 'Implementation started',
    (_, 'Resolved') => 'Code complete and unit tests pass',
    (_, 'Closed') => 'Acceptance tests pass',
    _ => 'Moved',
  };

  /// `GET wit/workitemtypes`: the list, without forms or fields.
  static Map<String, dynamic> typeList() => {
    'count': typeNames.length,
    'value': [for (final t in typeNames) typeSummary(t)],
  };

  static Map<String, dynamic> typeSummary(String type) {
    final t = _types[type]!;
    return {
      'name': type,
      'referenceName': t.$1,
      'description': t.$4,
      'color': t.$2,
      'icon': {
        'id': t.$3,
        'url': '$base/_apis/wit/workItemIcons/${t.$3}?color=${t.$2}&v=2',
      },
      'isDisabled': false,
      'states': [
        for (final s in statesOf(type))
          {'name': s.$1, 'color': s.$2, 'category': s.$3},
      ],
      'url': typeUrl(type),
    };
  }

  /// `GET wit/workitemtypes/{type}`: the summary plus transitions, the
  /// field list and the legacy form.
  static Map<String, dynamic>? type(String type) {
    if (!_types.containsKey(type)) return null;
    final names = [for (final s in statesOf(type)) s.$1];
    return {
      ...typeSummary(type),
      'transitions': {
        '': [
          {'to': names.first, 'actions': null},
        ],
        for (final from in names)
          from: [
            {'to': from, 'actions': null},
            for (final to in names)
              if (to != from) {'to': to, 'actions': null},
          ],
      },
      'fields': [
        for (final f in typeFields(type))
          {
            'defaultValue': f['defaultValue'],
            'alwaysRequired': f['alwaysRequired'],
            'referenceName': f['referenceName'],
            'name': f['name'],
            'url': f['url'],
          },
      ],
      'xmlForm': xmlForm(type),
    };
  }

  static Map<String, dynamic>? states(String type) {
    if (!_types.containsKey(type)) return null;
    final list = [
      for (final s in statesOf(type))
        {'name': s.$1, 'color': s.$2, 'category': s.$3},
    ];
    return {'count': list.length, 'value': list};
  }

  // ------------------------------------------------------------- fields

  /// The organization's fields: (reference, name, type, identity, picklist,
  /// read only).
  static const _orgFields = <(String, String, String, bool, bool, bool)>[
    ('System.Id', 'ID', 'integer', false, false, true),
    ('System.Title', 'Title', 'string', false, false, false),
    ('System.WorkItemType', 'Work Item Type', 'string', false, false, true),
    ('System.State', 'State', 'string', false, false, false),
    ('System.Reason', 'Reason', 'string', false, false, false),
    ('System.AssignedTo', 'Assigned To', 'string', true, false, false),
    ('System.AreaPath', 'Area Path', 'treePath', false, false, false),
    ('System.AreaId', 'Area ID', 'integer', false, false, true),
    ('System.IterationPath', 'Iteration Path', 'treePath', false, false, false),
    ('System.IterationId', 'Iteration ID', 'integer', false, false, true),
    ('System.TeamProject', 'Team Project', 'string', false, false, true),
    ('System.Description', 'Description', 'html', false, false, false),
    ('System.History', 'History', 'history', false, false, false),
    ('System.Tags', 'Tags', 'plainText', false, false, false),
    ('System.CreatedDate', 'Created Date', 'dateTime', false, false, true),
    ('System.CreatedBy', 'Created By', 'string', true, false, true),
    ('System.ChangedDate', 'Changed Date', 'dateTime', false, false, true),
    ('System.ChangedBy', 'Changed By', 'string', true, false, true),
    ('System.Rev', 'Rev', 'integer', false, false, true),
    ('System.Parent', 'Parent', 'integer', false, false, true),
    ('System.CommentCount', 'Comment Count', 'integer', false, false, true),
    ('System.BoardColumn', 'Board Column', 'string', false, false, true),
    (
      'System.BoardColumnDone',
      'Board Column Done',
      'boolean',
      false,
      false,
      true,
    ),
    ('System.BoardLane', 'Board Lane', 'string', false, false, true),
    (
      'Microsoft.VSTS.Common.Priority',
      'Priority',
      'integer',
      false,
      true,
      false,
    ),
    (
      'Microsoft.VSTS.Common.Severity',
      'Severity',
      'string',
      false,
      true,
      false,
    ),
    (
      'Microsoft.VSTS.Common.StackRank',
      'Stack Rank',
      'double',
      false,
      false,
      false,
    ),
    (
      'Microsoft.VSTS.Common.ValueArea',
      'Value Area',
      'string',
      false,
      true,
      false,
    ),
    ('Microsoft.VSTS.Common.Risk', 'Risk', 'string', false, true, false),
    (
      'Microsoft.VSTS.Common.Activity',
      'Activity',
      'string',
      false,
      true,
      false,
    ),
    (
      'Microsoft.VSTS.Common.AcceptanceCriteria',
      'Acceptance Criteria',
      'html',
      false,
      false,
      false,
    ),
    (
      'Microsoft.VSTS.Common.BusinessValue',
      'Business Value',
      'integer',
      false,
      false,
      false,
    ),
    (
      'Microsoft.VSTS.Common.TimeCriticality',
      'Time Criticality',
      'double',
      false,
      false,
      false,
    ),
    (
      'Microsoft.VSTS.Common.StateChangeDate',
      'State Change Date',
      'dateTime',
      false,
      false,
      true,
    ),
    (
      'Microsoft.VSTS.Common.ActivatedDate',
      'Activated Date',
      'dateTime',
      false,
      false,
      true,
    ),
    (
      'Microsoft.VSTS.Common.ActivatedBy',
      'Activated By',
      'string',
      true,
      false,
      true,
    ),
    (
      'Microsoft.VSTS.Common.ResolvedDate',
      'Resolved Date',
      'dateTime',
      false,
      false,
      true,
    ),
    (
      'Microsoft.VSTS.Common.ResolvedBy',
      'Resolved By',
      'string',
      true,
      false,
      true,
    ),
    (
      'Microsoft.VSTS.Common.ResolvedReason',
      'Resolved Reason',
      'string',
      false,
      false,
      false,
    ),
    (
      'Microsoft.VSTS.Common.ClosedDate',
      'Closed Date',
      'dateTime',
      false,
      false,
      true,
    ),
    (
      'Microsoft.VSTS.Common.ClosedBy',
      'Closed By',
      'string',
      true,
      false,
      true,
    ),
    (
      'Microsoft.VSTS.Scheduling.StoryPoints',
      'Story Points',
      'double',
      false,
      false,
      false,
    ),
    (
      'Microsoft.VSTS.Scheduling.Effort',
      'Effort',
      'double',
      false,
      false,
      false,
    ),
    (
      'Microsoft.VSTS.Scheduling.OriginalEstimate',
      'Original Estimate',
      'double',
      false,
      false,
      false,
    ),
    (
      'Microsoft.VSTS.Scheduling.RemainingWork',
      'Remaining Work',
      'double',
      false,
      false,
      false,
    ),
    (
      'Microsoft.VSTS.Scheduling.CompletedWork',
      'Completed Work',
      'double',
      false,
      false,
      false,
    ),
    (
      'Microsoft.VSTS.Scheduling.StartDate',
      'Start Date',
      'dateTime',
      false,
      false,
      false,
    ),
    (
      'Microsoft.VSTS.Scheduling.TargetDate',
      'Target Date',
      'dateTime',
      false,
      false,
      false,
    ),
    (
      'Microsoft.VSTS.TCM.ReproSteps',
      'Repro Steps',
      'html',
      false,
      false,
      false,
    ),
    (
      'Microsoft.VSTS.TCM.SystemInfo',
      'System Info',
      'html',
      false,
      false,
      false,
    ),
    ('Microsoft.VSTS.Build.FoundIn', 'Found In', 'string', false, true, false),
    (
      'Microsoft.VSTS.Build.IntegrationBuild',
      'Integration Build',
      'string',
      false,
      true,
      false,
    ),
  ];

  static String fieldUrl(String reference) =>
      '$base/_apis/wit/fields/$reference';

  /// `GET {org}/_apis/wit/fields`.
  static Map<String, dynamic> orgFields() => {
    'count': _orgFields.length,
    'value': [
      for (final f in _orgFields)
        {
          'referenceName': f.$1,
          'name': f.$2,
          'type': f.$3,
          'isIdentity': f.$4,
          'isPicklist': f.$5,
          'readOnly': f.$6,
          'usage': 'workItem',
          'canSortBy': f.$3 != 'html' && f.$3 != 'history',
          'isQueryable': true,
          'description': null,
          'url': fieldUrl(f.$1),
        },
    ],
  };

  static const _common = [
    'System.Id',
    'System.Title',
    'System.WorkItemType',
    'System.State',
    'System.Reason',
    'System.AssignedTo',
    'System.AreaPath',
    'System.AreaId',
    'System.IterationPath',
    'System.IterationId',
    'System.TeamProject',
    'System.Description',
    'System.History',
    'System.Tags',
    'System.CreatedDate',
    'System.CreatedBy',
    'System.ChangedDate',
    'System.ChangedBy',
    'System.Rev',
    'System.Parent',
    'System.CommentCount',
    'System.BoardColumn',
    'System.BoardColumnDone',
    'System.BoardLane',
    'Microsoft.VSTS.Common.StateChangeDate',
    'Microsoft.VSTS.Common.Priority',
    'Microsoft.VSTS.Common.StackRank',
  ];

  static const _byType = <String, List<String>>{
    'Epic': [
      'Microsoft.VSTS.Common.ValueArea',
      'Microsoft.VSTS.Common.Risk',
      'Microsoft.VSTS.Common.BusinessValue',
      'Microsoft.VSTS.Common.TimeCriticality',
      'Microsoft.VSTS.Common.AcceptanceCriteria',
      'Microsoft.VSTS.Scheduling.Effort',
      'Microsoft.VSTS.Scheduling.StartDate',
      'Microsoft.VSTS.Scheduling.TargetDate',
      'Microsoft.VSTS.Common.ActivatedDate',
      'Microsoft.VSTS.Common.ActivatedBy',
      'Microsoft.VSTS.Common.ResolvedDate',
      'Microsoft.VSTS.Common.ResolvedBy',
      'Microsoft.VSTS.Common.ClosedDate',
      'Microsoft.VSTS.Common.ClosedBy',
    ],
    'Feature': [
      'Microsoft.VSTS.Common.ValueArea',
      'Microsoft.VSTS.Common.Risk',
      'Microsoft.VSTS.Common.BusinessValue',
      'Microsoft.VSTS.Common.TimeCriticality',
      'Microsoft.VSTS.Common.AcceptanceCriteria',
      'Microsoft.VSTS.Scheduling.Effort',
      'Microsoft.VSTS.Scheduling.StartDate',
      'Microsoft.VSTS.Scheduling.TargetDate',
      'Microsoft.VSTS.Common.ActivatedDate',
      'Microsoft.VSTS.Common.ActivatedBy',
      'Microsoft.VSTS.Common.ResolvedDate',
      'Microsoft.VSTS.Common.ResolvedBy',
      'Microsoft.VSTS.Common.ClosedDate',
      'Microsoft.VSTS.Common.ClosedBy',
    ],
    'User Story': [
      'Microsoft.VSTS.Scheduling.StoryPoints',
      'Microsoft.VSTS.Common.ValueArea',
      'Microsoft.VSTS.Common.Risk',
      'Microsoft.VSTS.Common.AcceptanceCriteria',
      'Microsoft.VSTS.Common.ActivatedDate',
      'Microsoft.VSTS.Common.ActivatedBy',
      'Microsoft.VSTS.Common.ResolvedDate',
      'Microsoft.VSTS.Common.ResolvedBy',
      'Microsoft.VSTS.Common.ClosedDate',
      'Microsoft.VSTS.Common.ClosedBy',
      'Microsoft.VSTS.Build.IntegrationBuild',
    ],
    'Bug': [
      'Microsoft.VSTS.Scheduling.StoryPoints',
      'Microsoft.VSTS.Common.Severity',
      'Microsoft.VSTS.Common.Activity',
      'Microsoft.VSTS.Common.ResolvedReason',
      'Microsoft.VSTS.TCM.ReproSteps',
      'Microsoft.VSTS.TCM.SystemInfo',
      'Microsoft.VSTS.Scheduling.OriginalEstimate',
      'Microsoft.VSTS.Scheduling.RemainingWork',
      'Microsoft.VSTS.Scheduling.CompletedWork',
      'Microsoft.VSTS.Build.FoundIn',
      'Microsoft.VSTS.Build.IntegrationBuild',
      'Microsoft.VSTS.Common.ActivatedDate',
      'Microsoft.VSTS.Common.ActivatedBy',
      'Microsoft.VSTS.Common.ResolvedDate',
      'Microsoft.VSTS.Common.ResolvedBy',
      'Microsoft.VSTS.Common.ClosedDate',
      'Microsoft.VSTS.Common.ClosedBy',
    ],
    'Task': [
      'Microsoft.VSTS.Common.Activity',
      'Microsoft.VSTS.Scheduling.OriginalEstimate',
      'Microsoft.VSTS.Scheduling.RemainingWork',
      'Microsoft.VSTS.Scheduling.CompletedWork',
      'Microsoft.VSTS.Build.IntegrationBuild',
      'Microsoft.VSTS.Common.ActivatedDate',
      'Microsoft.VSTS.Common.ActivatedBy',
      'Microsoft.VSTS.Common.ClosedDate',
      'Microsoft.VSTS.Common.ClosedBy',
    ],
  };

  static String _nameOf(String reference) {
    for (final f in _orgFields) {
      if (f.$1 == reference) return f.$2;
    }
    return reference;
  }

  /// `GET wit/workitemtypes/{type}/fields?$expand=All`.
  static List<Map<String, dynamic>> typeFields(String type) {
    final states = [for (final s in statesOf(type)) s.$1];
    Map<String, dynamic> field(
      String reference, {
      bool required = false,
      Object? defaultValue,
      List<String> allowed = const [],
      String? help,
      List<String> dependent = const [],
    }) => {
      'defaultValue': defaultValue,
      'allowedValues': allowed,
      'helpText': help,
      'alwaysRequired': required,
      'dependentFields': [
        for (final d in dependent)
          {'referenceName': d, 'name': _nameOf(d), 'url': fieldUrl(d)},
      ],
      'referenceName': reference,
      'name': _nameOf(reference),
      'url': '$projectUrl/_apis/wit/fields/$reference',
    };

    final out = <Map<String, dynamic>>[];
    for (final reference in [..._common, ...?_byType[type]]) {
      out.add(switch (reference) {
        'System.Title' => field(
          reference,
          required: true,
          help: type == 'Task'
              ? 'The nature of the work'
              : 'What the user will be able to do when this is implemented',
        ),
        'System.State' => field(
          reference,
          required: true,
          defaultValue: states.first,
          allowed: [...states]..sort(),
          dependent: const [
            'System.State',
            'System.Reason',
            'System.AssignedTo',
          ],
        ),
        'System.Reason' => field(
          reference,
          allowed: [for (final s in states) reasonFor(type, s)],
          dependent: const ['System.State'],
        ),
        'System.AssignedTo' => field(
          reference,
          help: 'The person currently working on this item',
          dependent: const ['System.State'],
        ),
        'System.AreaPath' || 'System.IterationPath' => field(
          reference,
          required: reference == 'System.AreaPath',
        ),
        'Microsoft.VSTS.Common.Priority' => field(
          reference,
          defaultValue: '2',
          allowed: const ['1', '2', '3', '4'],
          help: 'Business importance. 1=must fix; 4=unimportant.',
        ),
        'Microsoft.VSTS.Common.Severity' => field(
          reference,
          defaultValue: '3 - Medium',
          allowed: const ['1 - Critical', '2 - High', '3 - Medium', '4 - Low'],
          help: 'Assessment of the effect of the bug on the product',
        ),
        'Microsoft.VSTS.Common.ValueArea' => field(
          reference,
          required: true,
          defaultValue: 'Business',
          allowed: const ['Architectural', 'Business'],
        ),
        'Microsoft.VSTS.Common.Risk' => field(
          reference,
          allowed: const ['1 - High', '2 - Medium', '3 - Low'],
          help: 'Uncertainty in the work',
        ),
        'Microsoft.VSTS.Common.Activity' => field(
          reference,
          allowed: const [
            'Deployment',
            'Design',
            'Development',
            'Documentation',
            'Requirements',
            'Testing',
          ],
          help: 'Type of work involved',
        ),
        'Microsoft.VSTS.Common.ResolvedReason' => field(
          reference,
          allowed: const [
            'As Designed',
            'Cannot Reproduce',
            'Copied to Backlog',
            'Deferred',
            'Duplicate',
            'Fixed',
            'Fixed and verified',
            'Obsolete',
          ],
        ),
        'Microsoft.VSTS.Scheduling.StoryPoints' => field(
          reference,
          help: 'The size of work estimated for implementing this story',
        ),
        'Microsoft.VSTS.Scheduling.RemainingWork' => field(
          reference,
          help: 'An estimate of the number of hours of work remaining',
        ),
        _ => field(reference),
      });
    }
    return out;
  }

  // ------------------------------------------------------------ the form

  static String _control(
    String field,
    String label, {
    String type = 'FieldControl',
    String position = 'Top',
    String extra = '',
  }) =>
      '<Control Label="$label" LabelPosition="$position" FieldName="$field" '
      'Type="$type"$extra />';

  static String _group(String label, List<String> controls) =>
      '<Group Label="$label"><Column PercentWidth="100">'
      '${controls.join()}</Column></Group>';

  static const _developmentLinks =
      '<Group Label="Development"><Column PercentWidth="100">'
      '<Control Label="" LabelPosition="Top" FieldName="Development" '
      'Type="LinksControl"><LinksControlOptions>'
      '<WorkItemLinkFilters FilterType="excludeAll" />'
      '<ExternalLinkFilters FilterType="include">'
      '<Filter LinkType="Build" /><Filter LinkType="Pull Request" />'
      '<Filter LinkType="Branch" /><Filter LinkType="Fixed in Commit" />'
      '</ExternalLinkFilters></LinksControlOptions></Control>'
      '</Column></Group>';

  static const _relatedWork =
      '<Group Label="Related Work"><Column PercentWidth="100">'
      '<Control Label="" LabelPosition="Top" FieldName="Related Work" '
      'Type="LinksControl"><LinksControlOptions>'
      '<WorkItemLinkFilters FilterType="include">'
      '<Filter LinkType="System.LinkTypes.Duplicate" />'
      '<Filter LinkType="System.LinkTypes.Hierarchy" />'
      '<Filter LinkType="System.LinkTypes.Dependency" />'
      '<Filter LinkType="System.LinkTypes.Related" />'
      '</WorkItemLinkFilters></LinksControlOptions></Control>'
      '</Column></Group>';

  /// The legacy `xmlForm` the web still answers for every type, shaped like
  /// the Agile process's own: header controls, then Details, History, Links
  /// and Attachments tabs.
  static String xmlForm(String type) {
    final html = switch (type) {
      'Bug' => [
        _group('Repro Steps', [
          _control(
            'Microsoft.VSTS.TCM.ReproSteps',
            '',
            type: 'HtmlFieldControl',
          ),
        ]),
        _group('System Info', [
          _control(
            'Microsoft.VSTS.TCM.SystemInfo',
            '',
            type: 'HtmlFieldControl',
          ),
        ]),
      ],
      'Task' => [
        _group('Description', [
          _control('System.Description', '', type: 'HtmlFieldControl'),
        ]),
      ],
      _ => [
        _group('Description', [
          _control('System.Description', '', type: 'HtmlFieldControl'),
        ]),
        _group('Acceptance Criteria', [
          _control(
            'Microsoft.VSTS.Common.AcceptanceCriteria',
            '',
            type: 'HtmlFieldControl',
          ),
        ]),
      ],
    };
    final planning = switch (type) {
      'Task' => [
        _group('Planning', [
          _control('Microsoft.VSTS.Common.Priority', 'Priority'),
          _control('Microsoft.VSTS.Common.Activity', 'Activity'),
        ]),
        _group('Effort (Hours)', [
          _control(
            'Microsoft.VSTS.Scheduling.OriginalEstimate',
            'Original Estimate',
          ),
          _control('Microsoft.VSTS.Scheduling.RemainingWork', 'Remaining'),
          _control('Microsoft.VSTS.Scheduling.CompletedWork', 'Completed'),
        ]),
      ],
      'Bug' => [
        _group('Planning', [
          _control('Microsoft.VSTS.Scheduling.StoryPoints', 'Story Points'),
          _control('Microsoft.VSTS.Common.Priority', 'Priority'),
          _control('Microsoft.VSTS.Common.Severity', 'Severity'),
          _control('Microsoft.VSTS.Common.Activity', 'Activity'),
        ]),
        _group('Effort (Hours)', [
          _control(
            'Microsoft.VSTS.Scheduling.OriginalEstimate',
            'Original Estimate',
          ),
          _control('Microsoft.VSTS.Scheduling.RemainingWork', 'Remaining'),
          _control('Microsoft.VSTS.Scheduling.CompletedWork', 'Completed'),
        ]),
      ],
      'User Story' => [
        _group('Planning', [
          _control('Microsoft.VSTS.Scheduling.StoryPoints', 'Story Points'),
          _control('Microsoft.VSTS.Common.Priority', 'Priority'),
          _control('Microsoft.VSTS.Common.Risk', 'Risk'),
        ]),
        _group('Classification', [
          _control('Microsoft.VSTS.Common.ValueArea', 'Value area'),
        ]),
      ],
      _ => [
        _group('Planning', [
          _control('Microsoft.VSTS.Common.Priority', 'Priority'),
          _control('Microsoft.VSTS.Scheduling.Effort', 'Effort'),
          _control('Microsoft.VSTS.Common.BusinessValue', 'Business Value'),
          _control('Microsoft.VSTS.Common.TimeCriticality', 'Time Criticality'),
          _control(
            'Microsoft.VSTS.Scheduling.StartDate',
            'Start Date',
            type: 'DateTimeControl',
          ),
          _control(
            'Microsoft.VSTS.Scheduling.TargetDate',
            'Target Date',
            type: 'DateTimeControl',
          ),
        ]),
        _group('Classification', [
          _control('Microsoft.VSTS.Common.ValueArea', 'Value area'),
        ]),
      ],
    };
    return '<FORM><Layout HideReadOnlyEmptyFields="true" '
        'HideControlBorders="true">'
        '<Group Margin="(10,0,0,0)"><Column PercentWidth="94">'
        '<Control Label="" LabelPosition="Top" FieldName="System.Title" '
        'Type="FieldControl" EmptyText="Enter title here" '
        'ControlFontSize="large" /></Column><Column PercentWidth="6">'
        '<Control Label="" LabelPosition="Top" FieldName="System.Id" '
        'Type="FieldControl" ControlFontSize="large" /></Column></Group>'
        '<Group Margin="(10,10,0,0)"><Column PercentWidth="30">'
        '${_control('System.AssignedTo', 'Assi&amp;gned To', position: 'Left', extra: ' EmptyText="Unassigned"')}'
        '${_control('System.State', 'Stat&amp;e', position: 'Left')}'
        '${_control('System.Reason', 'Reason', position: 'Left')}'
        '</Column><Column PercentWidth="40">'
        '${_control('System.AreaPath', '&amp;Area', position: 'Left', type: 'WorkItemClassificationControl')}'
        '${_control('System.IterationPath', 'Ite&amp;ration', position: 'Left', type: 'WorkItemClassificationControl')}'
        '</Column><Column PercentWidth="30">'
        '${_control('System.ChangedDate', 'Last Updated Date', position: 'Left', type: 'DateTimeControl', extra: ' ReadOnly="True"')}'
        '</Column></Group>'
        '<TabGroup Margin="(0,10,0,0)"><Tab Label="Details"><Group>'
        '<Column PercentWidth="50"><Group><Column PercentWidth="100">'
        '${html.join()}</Column></Group></Column>'
        '<Column PercentWidth="50"><Group Margin="(20,0,0,0)">'
        '<Column PercentWidth="50"><Group><Column PercentWidth="100">'
        '${planning.join()}</Column></Group></Column>'
        '<Column PercentWidth="50"><Group><Column PercentWidth="100">'
        '$_developmentLinks$_relatedWork</Column></Group></Column>'
        '</Group></Column></Group></Tab>'
        '<Tab Label="History"><Group><Column PercentWidth="100">'
        '<Control Label="" LabelPosition="Top" FieldName="System.History" '
        'Type="WorkItemLogControl" /></Column></Group></Tab>'
        '<Tab Label="Links"><Group><Column PercentWidth="100">'
        '<Control Label="" LabelPosition="Top" Type="LinksControl" />'
        '</Column></Group></Tab>'
        '<Tab Label="Attachments"><Group><Column PercentWidth="100">'
        '<Control Label="Attachments" LabelPosition="Top" '
        'Type="AttachmentsControl" /></Column></Group></Tab>'
        '</TabGroup></Layout></FORM>';
  }

  // ------------------------------------------------------------ backlogs

  static Map<String, dynamic> _level(
    String id,
    String name,
    int rank,
    String type,
    List<String> types,
    String color,
  ) => {
    'id': id,
    'name': name,
    'rank': rank,
    'workItemCountLimit': 1000,
    'addPanelFields': [
      {
        'referenceName': 'System.Title',
        'name': 'Title',
        'url': fieldUrl('System.Title'),
      },
    ],
    'columnFields': const [],
    'workItemTypes': [
      for (final t in types) {'name': t, 'url': typeUrl(t)},
    ],
    'defaultWorkItemType': {'name': types.first, 'url': typeUrl(types.first)},
    'color': color,
    'isHidden': false,
    'type': type,
  };

  /// `GET {team}/_apis/work/backlogconfiguration`. Bugs are managed with
  /// requirements, so they are rows on the taskboard, not cards.
  static Map<String, dynamic> backlogConfiguration() => {
    'taskBacklog': _level('Microsoft.TaskCategory', 'Tasks', 1, 'task', const [
      'Task',
    ], 'FFA4880A'),
    'requirementBacklog': _level(
      'Microsoft.RequirementCategory',
      'Stories',
      2,
      'requirement',
      const ['User Story', 'Bug'],
      'FF0098C7',
    ),
    'portfolioBacklogs': [
      _level('Microsoft.EpicCategory', 'Epics', 4, 'portfolio', const [
        'Epic',
      ], 'FFFF7B00'),
      _level('Microsoft.FeatureCategory', 'Features', 3, 'portfolio', const [
        'Feature',
      ], 'FF773B93'),
    ],
    'hiddenBacklogs': const <String>[],
    'workItemTypeMappedStates': [
      for (final t in typeNames)
        {
          'workItemTypeName': t,
          'states': {for (final s in statesOf(t)) s.$1: s.$3},
        },
    ],
    'backlogFields': {
      'typeFields': {
        'Order': 'Microsoft.VSTS.Common.StackRank',
        'Effort': 'Microsoft.VSTS.Scheduling.StoryPoints',
        'RemainingWork': 'Microsoft.VSTS.Scheduling.RemainingWork',
        'Activity': 'Microsoft.VSTS.Common.Activity',
      },
    },
    'bugsBehavior': 'asRequirements',
    'url': '$projectUrl/${DemoWorld.teamId}/_apis/work/backlogconfiguration',
  };

  static Map<String, dynamic> _category(
    String reference,
    String name,
    List<String> types,
  ) => {
    'name': name,
    'referenceName': reference,
    'defaultWorkItemType': types.isEmpty
        ? null
        : {'name': types.first, 'url': typeUrl(types.first)},
    'workItemTypes': [
      for (final t in types) {'name': t, 'url': typeUrl(t)},
    ],
    'url': '$projectUrl/_apis/wit/workItemTypeCategories/$reference',
  };

  static Map<String, dynamic> typeCategories() {
    final value = [
      _category('Microsoft.EpicCategory', 'Epic Category', const ['Epic']),
      _category('Microsoft.FeatureCategory', 'Feature Category', const [
        'Feature',
      ]),
      _category('Microsoft.RequirementCategory', 'Requirement Category', const [
        'User Story',
      ]),
      _category('Microsoft.BugCategory', 'Bug Category', const ['Bug']),
      _category('Microsoft.TaskCategory', 'Task Category', const ['Task']),
      _category('Microsoft.HiddenCategory', 'Hidden Types Category', const []),
    ];
    return {'count': value.length, 'value': value};
  }
}
