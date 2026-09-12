import 'dart:typed_data';

import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/http/ado_host.dart';
import '../db/app_database.dart';
import '../db/json_cache.dart';
import '../models/work_item.dart';
import '../models/work_item_form.dart';
import 'work_item_repository.dart';

/// Everything the create and edit form reads and writes (research/11).
///
/// Reads are cached in `cache_entries` under account-namespaced keys and
/// answered from the cache first when the network fails, like the other
/// repositories. Writes go through the JSON Patch endpoints, always with a
/// `validateOnly=true` dry run in front of them (spike w16).
class WorkItemFormRepository {
  WorkItemFormRepository(
    this._client,
    this._workItems, [
    AppDatabase? db,
    String? userId,
  ]) : _cache = JsonCache(db, namespace: userId);

  final AdoClient _client;
  final WorkItemRepository _workItems;
  final JsonCache _cache;

  static const apiVersion = '7.1';

  /// Tags and the Graph subject query are preview-only.
  static const tagsApiVersion = '7.1-preview.1';
  static const graphApiVersion = '7.1-preview.1';

  /// Process metadata changes rarely; research/11 §5 settles on a day.
  static const cacheTtl = Duration(hours: 24);

  static String specKey(String org, String project, String type) =>
      'form:spec:$org:$project:$type';
  static String orgFieldsKey(String org) => 'form:fields:$org';
  static String nodesKey(String org, String project, String kind) =>
      'form:nodes:$org:$project:$kind';
  static String teamDefaultsKey(String org, String project, String team) =>
      'form:team:$org:$project:$team';
  static String tagsKey(String org, String project) =>
      'form:tags:$org:$project';
  static String templatesKey(String org, String project, String team) =>
      'form:templates:$org:$project:$team';
  static String backlogKey(String org, String project, String team) =>
      'form:backlog:$org:$project:$team';
  static String membersKey(String org, String projectId, String teamId) =>
      'form:members:$org:$projectId:$teamId';
  static String descriptorKey(String org, String projectId) =>
      'form:descriptor:$org:$projectId';
  static String draftKey(String org, String project, String type) =>
      'form:draft:$org:$project:$type';

  final Map<String, String> _defaultTeams = {};

  // ---------------------------------------------------------------- reads

  /// The form of one project and type: the type (layout and transitions),
  /// its field rules and the org's field types, assembled and cached.
  Future<FormSpec> formSpec(
    String org,
    String project,
    String typeName, {
    bool refresh = false,
  }) => _cached<FormSpec>(
    specKey(org, project, typeName),
    () async {
      final typeJson = await _client.getJson(
        org: org,
        project: project,
        path: '_apis/wit/workitemtypes/$typeName',
        apiVersion: apiVersion,
      );
      final fieldsJson = await _client.getJson(
        org: org,
        project: project,
        path: '_apis/wit/workitemtypes/$typeName/fields',
        apiVersion: apiVersion,
        query: {r'$expand': 'All'},
      );
      final orgFields = await orgFieldTypes(org, refresh: refresh);
      return buildSpec(
        typeJson: typeJson,
        typeFields: _list(fieldsJson),
        orgFields: orgFields,
      ).toJson();
    },
    (json) => FormSpec.fromJson((json as Map).cast<String, dynamic>()),
    refresh: refresh,
  );

  /// The org's field list (`type`, `isIdentity`, `isPicklist`, `readOnly`),
  /// one call per org, by reference name.
  Future<Map<String, FieldSpec>> orgFieldTypes(
    String org, {
    bool refresh = false,
  }) => _cached<Map<String, FieldSpec>>(
    orgFieldsKey(org),
    () async => _list(
      await _client.getJson(
        org: org,
        path: '_apis/wit/fields',
        apiVersion: apiVersion,
      ),
    ),
    (json) => {
      for (final f in _asMaps(json))
        (f['referenceName'] as String? ?? ''): FieldSpec.fromOrgField(f),
    },
    refresh: refresh,
  );

  /// Merges a type read, its field rules and the org field types into a
  /// [FormSpec]; falls back to the field-list layout when `xmlForm` is
  /// missing or unparsable (spike s26).
  static FormSpec buildSpec({
    required Map<String, dynamic> typeJson,
    required List<Map<String, dynamic>> typeFields,
    required Map<String, FieldSpec> orgFields,
    Map<String, String> backlogTypeFields = const {},
  }) {
    final type = WorkItemType.fromJson(typeJson);
    final fields = <String, FieldSpec>{};
    for (final raw in typeFields) {
      final spec = FieldSpec.fromTypeField(raw)
          .withOrgField(orgFields[raw['referenceName']]);
      if (spec.referenceName.isEmpty) continue;
      fields[spec.referenceName] = spec;
    }
    final layout = type.form;
    if (layout != null) {
      return FormSpec(
        type: type,
        fields: fields,
        layout: layout,
        source: FormSource.xmlForm,
      );
    }
    return FormSpec(
      type: type,
      fields: fields,
      layout: fieldListLayout(fields, backlogTypeFields: backlogTypeFields),
      source: FormSource.fieldList,
    );
  }

  /// The fallback layout: required fields first, then the well-known common
  /// fields, then the rest by prefix, skipping read-only and bookkeeping
  /// fields (research/11 §4.3).
  static FormLayout fieldListLayout(
    Map<String, FieldSpec> fields, {
    Map<String, String> backlogTypeFields = const {},
  }) {
    bool usable(FieldSpec f) =>
        !f.readOnly &&
        f.type != FieldType.history &&
        !FieldSpec.isBookkeeping(f.referenceName);

    final taken = <String>{};
    FormControl? control(String reference) {
      final field = fields[reference];
      if (field == null || !usable(field) || !taken.add(reference)) return null;
      return FormControl(
        fieldReferenceName: reference,
        label: field.name,
        controlType: controlTypeFor(field.type),
      );
    }

    final groups = <FormGroup>[];
    final required = <FormControl>[
      for (final f in fields.values)
        if (f.alwaysRequired) ?control(f.referenceName),
    ];
    if (required.isNotEmpty) {
      groups.add(FormGroup(label: 'Required', controls: required));
    }

    final commonNames = <String>[
      'System.Description',
      'Microsoft.VSTS.TCM.ReproSteps',
      'Microsoft.VSTS.Common.AcceptanceCriteria',
      'Microsoft.VSTS.Common.Priority',
      'Microsoft.VSTS.Common.Severity',
      backlogTypeFields['Effort'] ?? 'Microsoft.VSTS.Scheduling.StoryPoints',
      backlogTypeFields['RemainingWork'] ??
          'Microsoft.VSTS.Scheduling.RemainingWork',
      backlogTypeFields['Activity'] ?? 'Microsoft.VSTS.Common.Activity',
    ];
    final common = <FormControl>[
      for (final name in commonNames) ?control(name),
    ];
    if (common.isNotEmpty) {
      groups.add(FormGroup(label: 'Details', controls: common));
    }

    final byPrefix = <String, List<FormControl>>{};
    final rest = fields.values.where((f) => usable(f)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final field in rest) {
      final c = control(field.referenceName);
      if (c == null) continue;
      byPrefix.putIfAbsent(groupLabelFor(field.referenceName), () => []).add(c);
    }
    final labels = byPrefix.keys.toList()..sort(_compareGroupLabels);
    for (final label in labels) {
      groups.add(FormGroup(label: label, controls: byPrefix[label]!));
    }

    return FormLayout(
      pages: [
        FormPage(
          label: 'Details',
          kind: FormPageKind.details,
          sections: [FormSection(groups: groups)],
        ),
      ],
    );
  }

  /// `Custom.*` together, `Microsoft.VSTS.Scheduling.*` under "Scheduling",
  /// `System.*` under "System", anything else under its first segment.
  static String groupLabelFor(String referenceName) {
    final parts = referenceName.split('.');
    if (parts.first == 'Custom') return 'Custom fields';
    if (parts.first == 'System') return 'System';
    if (parts.length >= 3 && parts[0] == 'Microsoft' && parts[1] == 'VSTS') {
      return parts[2];
    }
    return parts.first;
  }

  /// Custom fields first, System last, the rest alphabetically.
  static int _compareGroupLabels(String a, String b) {
    int rank(String l) => switch (l) {
      'Custom fields' => 0,
      'System' => 2,
      _ => 1,
    };
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0 ? byRank : a.toLowerCase().compareTo(b.toLowerCase());
  }

  /// The control the field's type asks for when the layout names none.
  static FormControlType controlTypeFor(FieldType type) => switch (type) {
    FieldType.html => FormControlType.html,
    FieldType.dateTime => FormControlType.dateTime,
    FieldType.treePath => FormControlType.classification,
    FieldType.history => FormControlType.log,
    _ => FormControlType.field,
  };

  /// Areas or iterations, ten levels deep, cached for a day.
  Future<ClassificationNode?> classificationNodes(
    String org,
    String project, {
    bool areas = true,
    bool refresh = false,
  }) {
    final kind = areas ? 'areas' : 'iterations';
    return _cached<ClassificationNode?>(
      nodesKey(org, project, kind),
      () async => await _client.getJson(
        org: org,
        project: project,
        path: '_apis/wit/classificationnodes/$kind',
        apiVersion: apiVersion,
        query: {r'$depth': '10'},
      ),
      (json) {
        if (json is! Map) return null;
        return ClassificationNode.fromJson(json.cast<String, dynamic>());
      },
      refresh: refresh,
    );
  }

  /// The project's default team id (the same read `BoardRepository` makes).
  Future<String> defaultTeamId(String org, String project) async {
    final key = '$org/$project';
    final cached = _defaultTeams[key];
    if (cached != null) return cached;
    final json = await _client.getJson(
      org: org,
      path: '_apis/projects/$project',
      apiVersion: apiVersion,
    );
    final id = (json['defaultTeam'] as Map?)?['id'] as String?;
    if (id == null) {
      throw AdoServerException('Project $project has no default team');
    }
    return _defaultTeams[key] = id;
  }

  /// Area and iteration defaults for a team: `teamfieldvalues`,
  /// `teamsettings` and the current sprint (spike s25).
  Future<TeamDefaults> teamDefaults(
    String org,
    String project, {
    String? team,
    bool refresh = false,
  }) async {
    final teamId = team ?? await defaultTeamId(org, project);
    return _cached<TeamDefaults>(
      teamDefaultsKey(org, project, teamId),
      () async {
        final fieldValues = await _maybe(
          () => _client.getJson(
            org: org,
            project: project,
            team: teamId,
            path: '_apis/work/teamsettings/teamfieldvalues',
            apiVersion: apiVersion,
          ),
        );
        final settings = await _maybe(
          () => _client.getJson(
            org: org,
            project: project,
            team: teamId,
            path: '_apis/work/teamsettings',
            apiVersion: apiVersion,
          ),
        );
        final current = await _maybe(
          () => _client.getJson(
            org: org,
            project: project,
            team: teamId,
            path: '_apis/work/teamsettings/iterations',
            apiVersion: apiVersion,
            query: {r'$timeframe': 'current'},
          ),
        );
        return parseTeamDefaults(
          project: project,
          teamId: teamId,
          teamFieldValues: fieldValues,
          teamSettings: settings,
          currentIterations: current,
        ).toJson();
      },
      (json) => TeamDefaults.fromJson((json as Map).cast<String, dynamic>()),
      refresh: refresh,
    );
  }

  static TeamDefaults parseTeamDefaults({
    required String project,
    required String teamId,
    Map<String, dynamic>? teamFieldValues,
    Map<String, dynamic>? teamSettings,
    Map<String, dynamic>? currentIterations,
  }) {
    final backlog = (teamSettings?['backlogIteration'] as Map?)
        ?.cast<String, dynamic>();
    final currentList = _list(currentIterations ?? const {});
    return TeamDefaults(
      teamId: teamId,
      defaultArea: teamFieldValues?['defaultValue'] as String?,
      currentIterationPath: currentList.isEmpty
          ? null
          : iterationPath(project, currentList.first),
      backlogIterationPath: backlog == null
          ? null
          : iterationPath(project, backlog),
      bugsBehavior: teamSettings?['bugsBehavior'] as String?,
    );
  }

  /// `teamsettings` paths are relative to the project (`\Iteration 1`, or
  /// empty for the backlog root); the field value wants
  /// `DevOps Mobile App\Iteration 1`.
  static String? iterationPath(String project, Map<String, dynamic> node) {
    final path = (node['path'] as String? ?? '').replaceAll('/', r'\');
    final name = node['name'] as String?;
    if (path.isEmpty) return name == null || name == project ? project : name;
    final trimmed = path.startsWith(r'\') ? path.substring(1) : path;
    if (trimmed == project || trimmed.startsWith('$project\\')) return trimmed;
    return '$project\\$trimmed';
  }

  /// The project's tags, for the chip field's suggestions.
  Future<List<String>> tags(
    String org,
    String project, {
    bool refresh = false,
  }) => _cached<List<String>>(
    tagsKey(org, project),
    () async => _list(
      await _client.getJson(
        org: org,
        project: project,
        path: '_apis/wit/tags',
        apiVersion: tagsApiVersion,
      ),
    ),
    (json) => [
      for (final t in _asMaps(json))
        if (t['name'] is String) t['name'] as String,
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
    refresh: refresh,
  );

  /// The team's templates, optionally for one type. The list read carries
  /// no `fields` map; [template] fetches one with its values.
  Future<List<WorkItemTemplate>> templates(
    String org,
    String project,
    String team, {
    String? typeName,
    bool refresh = false,
  }) async {
    final all = await _cached<List<WorkItemTemplate>>(
      templatesKey(org, project, team),
      () async => _list(
        await _client.getJson(
          org: org,
          project: project,
          team: team,
          path: '_apis/wit/templates',
          apiVersion: apiVersion,
        ),
      ),
      (json) => [for (final t in _asMaps(json)) WorkItemTemplate.fromJson(t)],
      refresh: refresh,
    );
    if (typeName == null) return all;
    return [
      for (final t in all)
        if (t.workItemTypeName == typeName) t,
    ];
  }

  Future<WorkItemTemplate> template(
    String org,
    String project,
    String team,
    String id,
  ) async => WorkItemTemplate.fromJson(
    await _client.getJson(
      org: org,
      project: project,
      team: team,
      path: '_apis/wit/templates/$id',
      apiVersion: apiVersion,
    ),
  );

  /// The chooser's input: backlog levels top-down plus the hidden types.
  Future<BacklogTypes> backlogTypes(
    String org,
    String project, {
    String? team,
    bool refresh = false,
  }) async {
    final teamId = team ?? await defaultTeamId(org, project);
    return _cached<BacklogTypes>(
      backlogKey(org, project, teamId),
      () async {
        final config = await _client.getJson(
          org: org,
          project: project,
          team: teamId,
          path: '_apis/work/backlogconfiguration',
          apiVersion: apiVersion,
        );
        final categories = await _maybe(
          () => _client.getJson(
            org: org,
            project: project,
            path: '_apis/wit/workitemtypecategories',
            apiVersion: apiVersion,
          ),
        );
        return parseBacklogTypes(
          config: config,
          categories: categories,
        ).toJson();
      },
      (json) => BacklogTypes.fromJson((json as Map).cast<String, dynamic>()),
      refresh: refresh,
    );
  }

  static BacklogTypes parseBacklogTypes({
    required Map<String, dynamic> config,
    Map<String, dynamic>? categories,
  }) {
    final portfolio = [
      for (final b in _asMaps(config['portfolioBacklogs']))
        BacklogLevel.fromJson(b),
    ]..sort((a, b) => b.rank.compareTo(a.rank));
    final requirement = config['requirementBacklog'];
    final task = config['taskBacklog'];
    final hiddenIds = {
      for (final h in (config['hiddenBacklogs'] as List?) ?? const []) '$h',
    };
    final levels = <BacklogLevel>[
      for (final level in [
        ...portfolio,
        if (requirement is Map)
          BacklogLevel.fromJson(requirement.cast<String, dynamic>()),
        if (task is Map) BacklogLevel.fromJson(task.cast<String, dynamic>()),
      ])
        hiddenIds.contains(level.id)
            ? BacklogLevel(
                id: level.id,
                name: level.name,
                rank: level.rank,
                typeNames: level.typeNames,
                isHidden: true,
              )
            : level,
    ];
    final hiddenTypes = <String>{};
    for (final c in _asMaps(categories?['value'])) {
      if (c['referenceName'] != 'Microsoft.HiddenCategory') continue;
      for (final t in _asMaps(c['workItemTypes'])) {
        if (t['name'] is String) hiddenTypes.add(t['name'] as String);
      }
    }
    return BacklogTypes(
      levels: levels,
      hiddenTypes: hiddenTypes,
      bugsBehavior: config['bugsBehavior'] as String?,
    );
  }

  // --------------------------------------------------------------- people

  /// The team's members, the people picker's offline list (spike s25: the
  /// type's identity `allowedValues` are empty, so this replaces them).
  Future<List<IdentityRef>> teamMembers(
    String org,
    String projectId,
    String teamId, {
    bool refresh = false,
  }) => _cached<List<IdentityRef>>(
    membersKey(org, projectId, teamId),
    () async => _list(
      await _client.getJson(
        org: org,
        path: '_apis/projects/$projectId/teams/$teamId/members',
        apiVersion: apiVersion,
      ),
    ),
    (json) => [
      for (final m in _asMaps(json))
        if (m['identity'] is Map)
          IdentityRef.fromJson((m['identity'] as Map).cast<String, dynamic>()),
    ],
    refresh: refresh,
  );

  /// The project's Graph scope descriptor, for a project-scoped search.
  Future<String?> projectDescriptor(String org, String projectId) =>
      _cached<String?>(
        descriptorKey(org, projectId),
        () async => await _client.getJson(
          host: AdoHost.vssps,
          org: org,
          path: '_apis/graph/descriptors/$projectId',
          apiVersion: graphApiVersion,
        ),
        (json) => json is Map ? json['value'] as String? : null,
      );

  /// Types-as-you-go people search, scoped to the project (spike s25).
  ///
  /// A `GraphUser` has no identity id, only a descriptor, so the rows come
  /// back without one and `assignedToValue` sends
  /// `"Display Name <unique>"`; call [resolveIdentityId] when the picked
  /// person should be sent by id.
  Future<List<IdentityRef>> searchPeople(
    String org,
    String projectId,
    String query,
  ) async {
    final text = query.trim();
    if (text.isEmpty) return const [];
    final scope = await _maybeValue(() => projectDescriptor(org, projectId));
    final json = await _client.send(
      method: 'POST',
      host: AdoHost.vssps,
      org: org,
      path: '_apis/graph/subjectquery',
      apiVersion: graphApiVersion,
      body: {
        'query': text,
        'subjectKind': ['User'],
        'scopeDescriptor': ?scope,
      },
    );
    return [for (final u in _asMaps(json['value'])) identityFromGraphUser(u)];
  }

  /// `GraphUser` → [IdentityRef]: `mailAddress` (else `principalName`) is
  /// the unique name and the avatar link carries the descriptor.
  static IdentityRef identityFromGraphUser(Map<String, dynamic> json) {
    final links = json['_links'];
    final avatar = links is Map && links['avatar'] is Map
        ? (links['avatar'] as Map)['href'] as String?
        : null;
    return IdentityRef(
      displayName: json['displayName'] as String? ?? '',
      uniqueName:
          json['mailAddress'] as String? ?? json['principalName'] as String?,
      descriptor:
          json['descriptor'] as String? ??
          IdentityRef.descriptorFromAvatar(avatar),
      imageUrl: avatar,
    );
  }

  /// The identity id behind a Graph descriptor (`graph/storagekeys`), read
  /// only when the user picks someone the search found.
  Future<IdentityRef> resolveIdentityId(
    String org,
    IdentityRef person, {
    String? descriptor,
  }) async {
    final d = descriptor ?? person.descriptor;
    if (person.id != null || d == null || d.isEmpty) return person;
    final json = await _client.getJson(
      host: AdoHost.vssps,
      org: org,
      path: '_apis/graph/storagekeys/$d',
      apiVersion: graphApiVersion,
    );
    final id = json['value'] as String?;
    if (id == null || id.isEmpty) return person;
    return IdentityRef(
      displayName: person.displayName,
      uniqueName: person.uniqueName,
      id: id,
      imageUrl: person.imageUrl,
      descriptor: person.descriptor,
    );
  }

  // -------------------------------------------------------------- writes

  /// `POST workitems/${type}?validateOnly=true`: HTTP 200 answers with the
  /// whole item minus id and rev, so the form can take the server's
  /// defaults; a 400 with rule errors becomes a [WorkItemRuleException].
  Future<WorkItem> validate(
    String org,
    String project,
    String typeName,
    List<Map<String, Object?>> ops,
  ) async {
    final json = await _post(
      org: org,
      project: project,
      path: createPath(typeName),
      query: {'validateOnly': 'true'},
      ops: ops,
    );
    return _item(json);
  }

  /// The real create, with relations expanded, upserted into the work item
  /// cache so the list and board see it at once.
  Future<WorkItem> create(
    String org,
    String project,
    String typeName,
    List<Map<String, Object?>> ops,
  ) async {
    final json = await _post(
      org: org,
      project: project,
      path: createPath(typeName),
      query: {r'$expand': 'relations'},
      ops: ops,
    );
    final item = _item(json);
    await _workItems.cacheItem(org, project, item);
    return item;
  }

  /// The edit dry run: the same patch the save would send, guarded by
  /// `test /rev`.
  Future<WorkItem> validatePatch(
    String org,
    String project,
    WorkItem item,
    List<Map<String, Object?>> ops,
  ) async {
    final json = await _post(
      method: 'PATCH',
      org: org,
      project: project,
      path: '_apis/wit/workitems/${item.id}',
      query: {'validateOnly': 'true'},
      ops: [
        if (ops.isEmpty || ops.first['path'] != '/rev')
          {'op': 'test', 'path': '/rev', 'value': item.rev},
        ...ops,
      ],
    );
    return _item(json);
  }

  /// `POST wit/attachments?fileName=…&uploadType=simple` with the bytes as
  /// the body (spike w17).
  Future<AttachmentRef> uploadAttachment(
    String org,
    String project,
    String fileName,
    Uint8List bytes,
  ) async {
    final json = await _client.send(
      method: 'POST',
      org: org,
      project: project,
      path: '_apis/wit/attachments',
      apiVersion: apiVersion,
      query: {'fileName': fileName, 'uploadType': 'simple'},
      body: bytes,
      contentType: 'application/octet-stream',
    );
    return AttachmentRef.fromJson(json, fileName: fileName);
  }

  /// Link targets: an exact id when the text is a number, plus a title
  /// search through WIQL, hydrated through the work item batch read.
  Future<List<WorkItem>> searchWorkItems(
    String org,
    String project,
    String text, {
    int top = 50,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];
    final ids = <int>[];
    final exact = int.tryParse(trimmed);
    if (exact != null) ids.add(exact);
    try {
      for (final id in await _workItems.queryIds(
        org,
        project,
        titleSearchWiql(trimmed),
        top: top,
      )) {
        if (!ids.contains(id)) ids.add(id);
      }
    } on AdoException {
      if (exact == null) rethrow;
    }
    if (ids.isEmpty) return const [];
    return _workItems.batch(org, project, ids);
  }

  static String titleSearchWiql(String text) =>
      'SELECT [System.Id] FROM WorkItems '
      'WHERE [System.TeamProject] = @project '
      "AND [System.Title] CONTAINS '${text.replaceAll("'", "''")}' "
      "AND [System.State] <> 'Removed' "
      'ORDER BY [System.ChangedDate] DESC';

  // -------------------------------------------------------------- drafts

  Future<void> saveDraft(String org, WorkItemDraft draft) =>
      _cache.put(draftKey(org, draft.project, draft.type), draft.toJson());

  Future<WorkItemDraft?> draft(String org, String project, String type) async {
    final entry = await _cache.get(draftKey(org, project, type));
    if (entry == null || entry.json is! Map) return null;
    return WorkItemDraft.fromJson((entry.json as Map).cast<String, dynamic>());
  }

  Future<void> clearDraft(String org, String project, String type) =>
      _cache.remove(draftKey(org, project, type));

  // ------------------------------------------------------- patch building

  /// The create patch: field values, the Markdown format op, the parent
  /// link, any extra relations and the uploaded attachments (spike w16).
  static List<Map<String, Object?>> buildCreateOps(
    Map<String, Object?> values, {
    bool markdownDescription = false,
    Set<String> markdownFields = const {},
    String? parentUrl,
    List<Map<String, Object?>> relations = const [],
    List<AttachmentRef> attachments = const [],
  }) {
    final ops = <Map<String, Object?>>[];
    for (final entry in values.entries) {
      final value = encodeValue(entry.key, entry.value);
      if (value == null || (value is String && value.isEmpty)) continue;
      ops.add({'op': 'add', 'path': '/fields/${entry.key}', 'value': value});
    }
    final formats = <String>{
      if (markdownDescription) 'System.Description',
      ...markdownFields,
    };
    for (final field in formats) {
      ops.add({
        'op': 'add',
        'path': '/multilineFieldsFormat/$field',
        'value': 'Markdown',
      });
    }
    if (parentUrl != null && parentUrl.isNotEmpty) {
      ops.add({
        'op': 'add',
        'path': '/relations/-',
        'value': {'rel': parentRel, 'url': parentUrl},
      });
    }
    for (final relation in relations) {
      ops.add({'op': 'add', 'path': '/relations/-', 'value': relation});
    }
    for (final attachment in attachments) {
      ops.add({
        'op': 'add',
        'path': '/relations/-',
        'value': {
          'rel': attachedFileRel,
          'url': attachment.url,
          if (attachment.fileName != null)
            'attributes': {'name': attachment.fileName},
        },
      });
    }
    return ops;
  }

  /// The edit patch: `test /rev` first, then only the fields whose value
  /// actually changed, and a format op only when the format changed.
  static List<Map<String, Object?>> buildEditOps(
    WorkItem original,
    Map<String, Object?> values, {
    Map<String, String> formats = const {},
  }) {
    final ops = <Map<String, Object?>>[
      {'op': 'test', 'path': '/rev', 'value': original.rev},
    ];
    for (final entry in values.entries) {
      final value = encodeValue(entry.key, entry.value);
      if (_sameValue(original.fields[entry.key], value)) continue;
      ops.add(
        value == null || (value is String && value.isEmpty)
            ? {'op': 'add', 'path': '/fields/${entry.key}', 'value': ''}
            : {'op': 'add', 'path': '/fields/${entry.key}', 'value': value},
      );
    }
    for (final entry in formats.entries) {
      final wanted = entry.value.toLowerCase() == 'markdown'
          ? 'markdown'
          : 'html';
      if (original.formatOf(entry.key) == wanted) continue;
      ops.add({
        'op': 'add',
        'path': '/multilineFieldsFormat/${entry.key}',
        'value': wanted == 'markdown' ? 'Markdown' : 'Html',
      });
    }
    return ops;
  }

  /// Equal for patch purposes: identities by id or unique name, numbers
  /// across int and double and their string form, strings trimmed.
  static bool _sameValue(Object? original, Object? next) {
    final a = _comparable(original);
    final b = _comparable(next);
    if (a is num && b is num) return a.toDouble() == b.toDouble();
    if (a is num && b is String) return a.toString() == b;
    if (a is String && b is num) return a == b.toString();
    if (a == null || (a is String && a.isEmpty)) {
      return b == null || (b is String && b.isEmpty);
    }
    return a == b;
  }

  static Object? _comparable(Object? value) {
    if (value is IdentityRef) return assignedToValue(value);
    if (value is Map) {
      final person = IdentityRef.fromField(value);
      return person == null ? value.toString() : assignedToValue(person);
    }
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Iterable) return formatTags([for (final v in value) '$v']);
    if (value is String) return value.trim();
    return value;
  }

  /// `System.Tags` is written as `a; b; c`.
  static String formatTags(Iterable<String> tags) {
    final seen = <String>{};
    return [
      for (final t in tags)
        if (t.trim().isNotEmpty && seen.add(t.trim().toLowerCase())) t.trim(),
    ].join('; ');
  }

  static List<String> parseTags(Object? value) => [
    for (final t in (value as String? ?? '').split(';'))
      if (t.trim().isNotEmpty) t.trim(),
  ];

  /// `System.AssignedTo` takes the `"Display Name <unique>"` form, and the
  /// identity id only when the person has no unique name.
  ///
  /// The id looked like the safer value, but spike s29 (2026-09-12) found
  /// the work item store refuses it: the id `teams/{id}/members` reports —
  /// which is also what `graph/storagekeys` resolves a descriptor to — comes
  /// back as "The identity value '…' for field 'Assigned To' is an unknown
  /// identity", while both the display form and the bare unique name are
  /// accepted and echo the same person.
  static String assignedToValue(IdentityRef person) {
    final unique = person.uniqueName;
    if (unique != null && unique.isNotEmpty) {
      return person.displayName.isEmpty
          ? unique
          : '${person.displayName} <$unique>';
    }
    final id = person.id;
    if (id != null && id.isNotEmpty) return id;
    return person.displayName;
  }

  /// Values as the patch sends them: tags joined, dates in ISO 8601,
  /// identities as their id or display form.
  static Object? encodeValue(String referenceName, Object? value) {
    if (value is IdentityRef) return assignedToValue(value);
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Iterable) {
      return formatTags([for (final v in value) '$v']);
    }
    if (value is String && referenceName == 'System.Tags') {
      return formatTags(parseTags(value));
    }
    return value;
  }

  static const parentRel = 'System.LinkTypes.Hierarchy-Reverse';
  static const childRel = 'System.LinkTypes.Hierarchy-Forward';
  static const relatedRel = 'System.LinkTypes.Related';
  static const attachedFileRel = 'AttachedFile';

  /// `workitems/$Bug`; `AdoClient` percent-encodes the segment, so the type
  /// name goes in as it is.
  static String createPath(String typeName) =>
      '_apis/wit/workitems/\$$typeName';

  // ------------------------------------------------------------- plumbing

  Future<Map<String, dynamic>> _post({
    String method = 'POST',
    required String org,
    required String project,
    required String path,
    required List<Map<String, Object?>> ops,
    Map<String, String> query = const {},
  }) async {
    try {
      return await _client.send(
        method: method,
        org: org,
        project: project,
        path: path,
        apiVersion: apiVersion,
        query: query,
        body: ops,
        contentType: AdoClient.jsonPatchContentType,
      );
    } on AdoValidationException catch (e) {
      // Field rules; an unknown field has no rule errors and stays the
      // plain AdoException the client mapped (spike w16).
      throw WorkItemRuleException.fromValidation(e);
    }
  }

  /// A dry run answers without `id` and `rev`.
  static WorkItem _item(Map<String, dynamic> json) => WorkItem.fromJson({
    ...json,
    'id': (json['id'] as num?)?.toInt() ?? 0,
    'rev': (json['rev'] as num?)?.toInt() ?? 0,
  });

  Future<T> _cached<T>(
    String key,
    Future<Object> Function() fetch,
    T Function(Object? json) parse, {
    bool refresh = false,
    Duration maxAge = cacheTtl,
  }) async {
    if (!refresh) {
      final hit = await _cache.get(key);
      if (hit != null && DateTime.now().difference(hit.fetchedAt) < maxAge) {
        final parsed = _tryParse(hit.json, parse);
        if (parsed != null) return parsed.$1;
      }
    }
    try {
      final raw = await fetch();
      await _cache.put(key, raw);
      return parse(raw);
    } on AdoAuthException {
      // Sign-in is needed; never mask that with a stale copy.
      rethrow;
    } on AdoException {
      final stale = await _cache.get(key);
      final parsed = stale == null ? null : _tryParse(stale.json, parse);
      if (parsed != null) return parsed.$1;
      rethrow;
    }
  }

  static (T,)? _tryParse<T>(Object? json, T Function(Object? json) parse) {
    try {
      return (parse(json),);
    } catch (_) {
      return null;
    }
  }

  /// A 403 or 404 on an optional read (a team without settings) is not a
  /// failure of the whole form.
  Future<Map<String, dynamic>?> _maybe(
    Future<Map<String, dynamic>> Function() read,
  ) async {
    try {
      return await read();
    } on AdoForbiddenException {
      return null;
    } on AdoNotFoundException {
      return null;
    }
  }

  Future<T?> _maybeValue<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } on AdoException {
      return null;
    }
  }

  static List<Map<String, dynamic>> _list(Map<String, dynamic> json) =>
      _asMaps(json['value']);

  static List<Map<String, dynamic>> _asMaps(Object? value) => [
    for (final v in (value as List?) ?? const [])
      if (v is Map) v.cast<String, dynamic>(),
  ];
}
