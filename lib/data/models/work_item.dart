import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart' show IconData, Icons;

import '../../core/util/format.dart';
import 'work_item_form.dart';

/// Graph avatar sizes: small 32 px, medium 64 px, large 256 px.
enum AvatarSize { small, medium, large }

/// Where an avatar comes from; [key] is stable per person and size and
/// names the cache entry.
class AvatarSource extends Equatable {
  const AvatarSource._({
    required this.key,
    this.org,
    this.descriptor,
    this.url,
    this.size = AvatarSize.medium,
    this.picturesOnly = false,
  });

  /// With [picturesOnly] the service's auto-generated initials avatar
  /// counts as "no image", for tiles the app draws itself.
  factory AvatarSource.graph({
    required String org,
    required String descriptor,
    AvatarSize size = AvatarSize.medium,
    bool picturesOnly = false,
  }) => AvatarSource._(
    key:
        'graph:$org:$descriptor:${size.name}${picturesOnly ? ':pictures' : ''}',
    org: org,
    descriptor: descriptor,
    size: size,
    picturesOnly: picturesOnly,
  );

  factory AvatarSource.url(String url) =>
      AvatarSource._(key: 'url:$url', url: url);

  final String key;
  final String? org;
  final String? descriptor;
  final String? url;
  final AvatarSize size;
  final bool picturesOnly;

  bool get isGraph => descriptor != null;

  @override
  List<Object?> get props => [key];
}

/// A person as Azure DevOps returns it inside a field or a comment.
class IdentityRef extends Equatable {
  const IdentityRef({
    required this.displayName,
    this.uniqueName,
    this.id,
    this.imageUrl,
    this.descriptor,
  });

  factory IdentityRef.fromJson(Map<String, dynamic> json) {
    final links = json['_links'];
    String? avatar;
    if (links is Map && links['avatar'] is Map) {
      avatar = (links['avatar'] as Map)['href'] as String?;
    }
    return IdentityRef(
      displayName: json['displayName'] as String? ?? '',
      uniqueName: json['uniqueName'] as String?,
      id: json['id'] as String?,
      // The Graph avatar link takes a size and answers with the token;
      // `imageUrl` may be the legacy identityImage form.
      imageUrl: avatar ?? json['imageUrl'] as String?,
      descriptor: json['descriptor'] as String? ?? descriptorFromAvatar(avatar),
    );
  }

  /// Pull request reviewers and pipeline approvers carry no `descriptor`
  /// field (spike s23), only an avatar link that ends with one:
  /// `…/_apis/GraphProfile/MemberAvatars/aad.Njg…`. Without it the app
  /// falls back to that link, which the Entra token cannot fetch (401),
  /// and the person shows as initials next to their own photo elsewhere.
  static String? descriptorFromAvatar(String? href) {
    if (href == null || href.isEmpty) return null;
    final segments = Uri.tryParse(href)?.pathSegments ?? const <String>[];
    final at = segments.indexOf('MemberAvatars');
    if (at < 0 || at + 1 >= segments.length) return null;
    final descriptor = segments[at + 1];
    return descriptor.isEmpty ? null : descriptor;
  }

  /// Fields carry an object; older payloads carry `"Name <email>"`.
  static IdentityRef? fromField(Object? value) {
    if (value is Map) {
      return IdentityRef.fromJson(value.cast<String, dynamic>());
    }
    if (value is String && value.isNotEmpty) {
      final m = RegExp(r'^(.*?)\s*<([^>]+)>$').firstMatch(value);
      return m == null
          ? IdentityRef(displayName: value)
          : IdentityRef(displayName: m.group(1)!, uniqueName: m.group(2));
    }
    return null;
  }

  final String displayName;
  final String? uniqueName;
  final String? id;
  final String? imageUrl;

  /// Graph subject descriptor (`aad.…`), the key for avatars.
  final String? descriptor;

  String get initialsLabel => initials(displayName);

  /// Organization the identity's links point at (`dev.azure.com/{org}/…`).
  String? get org {
    final url = imageUrl;
    if (url == null || url.isEmpty) return null;
    final segments = Uri.parse(url).pathSegments;
    return segments.isEmpty || segments.first.startsWith('_')
        ? null
        : segments.first;
  }

  /// How to fetch this person's picture, or null when nothing is known.
  /// The Graph `Subjects/{descriptor}/avatars` endpoint on vssps answers
  /// JSON (base64) to the app's bearer token; the image links on
  /// dev.azure.com (`GraphProfile/MemberAvatars`, `_api/_common/
  /// identityImage`) return 401 to it although a PAT can read them.
  AvatarSource? avatarSource({AvatarSize size = AvatarSize.medium}) {
    final o = org;
    final d = descriptor;
    if (o != null && d != null && d.isNotEmpty) {
      return AvatarSource.graph(org: o, descriptor: d, size: size);
    }
    final url = imageUrl;
    if (url != null && url.isNotEmpty) return AvatarSource.url(url);
    return null;
  }

  @override
  List<Object?> get props => [displayName, uniqueName, id];
}

/// One work item as returned by `wit/workitems` or `workitemsbatch`. Keeps
/// the raw field map so every screen can read what it needs.
/// One entry of a work item's `relations[]`: a link to another item, an
/// attachment or a hyperlink. Only present on a read made with
/// `$expand=all` or `$expand=relations` (the detail read and a create).
class WorkItemRelation extends Equatable {
  const WorkItemRelation({
    required this.rel,
    required this.url,
    this.attributes = const {},
  });

  factory WorkItemRelation.fromJson(Map<String, dynamic> json) =>
      WorkItemRelation(
        rel: json['rel'] as String? ?? '',
        url: json['url'] as String? ?? '',
        attributes:
            (json['attributes'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  final String rel;
  final String url;
  final Map<String, dynamic> attributes;

  Map<String, dynamic> toJson() => {
    'rel': rel,
    'url': url,
    if (attributes.isNotEmpty) 'attributes': attributes,
  };

  static const parentRel = 'System.LinkTypes.Hierarchy-Reverse';
  static const childRel = 'System.LinkTypes.Hierarchy-Forward';
  static const relatedRel = 'System.LinkTypes.Related';
  static const predecessorRel = 'System.LinkTypes.Dependency-Reverse';
  static const successorRel = 'System.LinkTypes.Dependency-Forward';
  static const duplicateRel = 'System.LinkTypes.Duplicate-Forward';
  static const duplicateOfRel = 'System.LinkTypes.Duplicate-Reverse';
  static const attachedFileRel = 'AttachedFile';
  static const hyperlinkRel = 'Hyperlink';
  static const artifactLinkRel = 'ArtifactLink';

  bool get isParent => rel == parentRel;
  bool get isChild => rel == childRel;
  bool get isRelated => rel == relatedRel;

  /// An uploaded file (research/01 §2.5).
  bool get isAttachment => rel == attachedFileRel;

  /// A link to another work item, rather than to a file, a hyperlink or a
  /// Git artifact.
  bool get isWorkItemLink => targetId != null;

  /// `attributes.name`: the file name of an attachment, and the label of a
  /// hyperlink or an artifact link.
  String? get name {
    final value = attributes['name'];
    return value is String && value.isNotEmpty ? value : null;
  }

  String? get comment {
    final value = attributes['comment'];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// `attributes.resourceSize`: an attachment's size in bytes.
  int? get resourceSize => (attributes['resourceSize'] as num?)?.toInt();

  /// The attachment guid of an `AttachedFile` relation, which is the last
  /// path segment of its `_apis/wit/attachments/{guid}` URL.
  String? get attachmentId {
    if (!isAttachment) return null;
    final segments = Uri.parse(url).pathSegments;
    return segments.isEmpty ? null : segments.last;
  }

  /// The work item this link points at, or null when it points at anything
  /// else (an attachment, a commit, a hyperlink).
  int? get targetId {
    if (!url.contains('/_apis/wit/workItems/') &&
        !url.contains('/_apis/wit/workitems/')) {
      return null;
    }
    return int.tryParse(Uri.parse(url).pathSegments.last);
  }

  /// The relation's identity, independent of how its URL is spelled.
  ///
  /// Azure DevOps removes a relation by position, so a removal is
  /// remembered by what it points at and resolved to an index against a
  /// freshly read item (research/01 §2.6) — and the URL itself cannot carry
  /// that identity: the service **rewrites it with the project GUID**
  /// (`…/puremedia/98720989-…/_apis/wit/attachments/{guid}`, spike s37)
  /// while the app sends the project by name, so a literal comparison never
  /// matches what comes back.
  String get key {
    final target = targetId;
    if (target != null) return '$rel|workitem:$target';
    final attachment = attachmentId;
    if (attachment != null && attachment.isNotEmpty) {
      return '$rel|attachment:$attachment';
    }
    return '$rel|$url';
  }

  @override
  List<Object?> get props => [rel, url];
}

class WorkItem extends Equatable {
  const WorkItem({
    required this.id,
    required this.rev,
    required this.fields,
    this.url,
    this.multilineFieldsFormat = const {},
    this.relations = const [],
  });

  factory WorkItem.fromJson(Map<String, dynamic> json) => WorkItem(
    id: json['id'] as int,
    rev: json['rev'] as int? ?? 0,
    url: json['url'] as String?,
    fields: (json['fields'] as Map?)?.cast<String, dynamic>() ?? const {},
    multilineFieldsFormat:
        (json['multilineFieldsFormat'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ) ??
        const {},
    relations: [
      for (final r in (json['relations'] as List?) ?? const [])
        if (r is Map) WorkItemRelation.fromJson(r.cast<String, dynamic>()),
    ],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'rev': rev,
    if (url != null) 'url': url,
    'fields': fields,
    'multilineFieldsFormat': multilineFieldsFormat,
    if (relations.isNotEmpty)
      'relations': [for (final r in relations) r.toJson()],
  };

  final int id;
  final int rev;
  final String? url;
  final Map<String, dynamic> fields;

  /// `System.Description` → `html` | `markdown`, only present on reads made
  /// without a `fields` filter (spike S5b).
  final Map<String, String> multilineFieldsFormat;

  /// Links to other items, attachments and hyperlinks; empty on a list read
  /// (only `$expand` brings them back).
  final List<WorkItemRelation> relations;

  /// The parent link, when the item has one.
  WorkItemRelation? get parentRelation =>
      relations.where((r) => r.isParent).firstOrNull;

  List<WorkItemRelation> get childRelations => [
    for (final r in relations)
      if (r.isChild) r,
  ];

  /// The links to other work items, in wire order: what the Links page
  /// groups by kind (research/11 §4.3).
  List<WorkItemRelation> get linkRelations => [
    for (final r in relations)
      if (r.isWorkItemLink) r,
  ];

  /// The `AttachedFile` relations, in wire order: the Attachments page.
  List<WorkItemRelation> get attachmentRelations => [
    for (final r in relations)
      if (r.isAttachment) r,
  ];

  /// How many files are attached. `System.AttachedFileCount` is not in
  /// the item read, not even with `$expand=all` (spike s36), so the
  /// `AttachedFile` relations are the count.
  int get attachedFileCount => attachmentRelations.length;

  T? field<T>(String referenceName) {
    final v = fields[referenceName];
    return v is T ? v : null;
  }

  String get type => field<String>('System.WorkItemType') ?? '';
  String get title => field<String>('System.Title') ?? '';
  String get state => field<String>('System.State') ?? '';
  String? get reason => field<String>('System.Reason');
  String get teamProject => field<String>('System.TeamProject') ?? '';
  String? get areaPath => field<String>('System.AreaPath');
  String? get iterationPath => field<String>('System.IterationPath');
  int? get priority => field<num>('Microsoft.VSTS.Common.Priority')?.toInt();
  IdentityRef? get assignedTo =>
      IdentityRef.fromField(fields['System.AssignedTo']);
  IdentityRef? get createdBy =>
      IdentityRef.fromField(fields['System.CreatedBy']);
  IdentityRef? get changedBy =>
      IdentityRef.fromField(fields['System.ChangedBy']);
  DateTime? get changedDate =>
      DateTime.tryParse(field<String>('System.ChangedDate') ?? '');
  DateTime? get createdDate =>
      DateTime.tryParse(field<String>('System.CreatedDate') ?? '');
  List<String> get tags => (field<String>('System.Tags') ?? '')
      .split(';')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();
  String? get description => field<String>('System.Description');
  String? get boardColumn => field<String>('System.BoardColumn');
  bool get boardColumnDone => field<bool>('System.BoardColumnDone') ?? false;

  /// `markdown` or `html`; a missing map means HTML (spike S5b).
  String formatOf(String referenceName) =>
      (multilineFieldsFormat[referenceName] ?? 'html').toLowerCase() ==
          'markdown'
      ? 'markdown'
      : 'html';

  WorkItem copyWithFields(Map<String, dynamic> updates, {int? rev}) => WorkItem(
    id: id,
    rev: rev ?? this.rev,
    url: url,
    fields: {...fields, ...updates},
    multilineFieldsFormat: multilineFieldsFormat,
    relations: relations,
  );

  @override
  List<Object?> get props => [id, rev, fields];
}

class WorkItemState extends Equatable {
  const WorkItemState({required this.name, this.color, this.category});

  factory WorkItemState.fromJson(Map<String, dynamic> json) => WorkItemState(
    name: json['name'] as String? ?? '',
    color: json['color'] as String?,
    category: json['category'] as String?,
  );

  final String name;
  final String? color;
  final String? category;

  @override
  List<Object?> get props => [name, color, category];
}

/// From `GET {org}/{project}/_apis/wit/workitemtypes`: the team's colors and
/// icons for each type, which DESIGN.md §3 says to prefer over our palette.
/// A single-type read adds `transitions` and `xmlForm`; the raw XML is
/// parsed into [form] and dropped, never cached (research/01 §2.7).
class WorkItemType extends Equatable {
  const WorkItemType({
    required this.name,
    required this.referenceName,
    this.color,
    this.iconId,
    this.states = const [],
    this.isDisabled = false,
    this.transitions = const {},
    this.form,
  });

  factory WorkItemType.fromJson(Map<String, dynamic> json) => WorkItemType(
    name: json['name'] as String? ?? '',
    referenceName: json['referenceName'] as String? ?? '',
    color: json['color'] as String?,
    iconId: (json['icon'] as Map?)?['id'] as String?,
    states: ((json['states'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => WorkItemState.fromJson(m.cast<String, dynamic>()))
        .toList(),
    isDisabled: json['isDisabled'] as bool? ?? false,
    transitions: parseTransitions(json['transitions']),
    // `xmlForm` on a fresh read, `layout` when read back from the cache.
    form:
        FormLayout.tryParse(json['xmlForm'] as String?) ??
        (json['layout'] is Map
            ? FormLayout.fromJson(
                (json['layout'] as Map).cast<String, dynamic>(),
              )
            : null),
  );

  final String name;
  final String referenceName;
  final String? color;
  final String? iconId;
  final List<WorkItemState> states;
  final bool isDisabled;

  /// `fromState` → the states it may move to. The empty key is the
  /// pre-creation state: what a new item may start in (spike s25).
  final Map<String, List<String>> transitions;

  /// The form tree parsed from `xmlForm`, when the type was read on its own.
  final FormLayout? form;

  /// `{"New": [{"to": "Active"}, …]}` flattened to target state names.
  static Map<String, List<String>> parseTransitions(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, List<String>>{};
    for (final entry in raw.entries) {
      final targets = <String>[];
      for (final t in (entry.value as List?) ?? const []) {
        if (t is Map && t['to'] is String) {
          targets.add(t['to'] as String);
        } else if (t is String) {
          targets.add(t);
        }
      }
      out[entry.key.toString()] = targets;
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'referenceName': referenceName,
    if (color != null) 'color': color,
    if (iconId != null) 'icon': {'id': iconId},
    'states': [
      for (final s in states)
        {
          'name': s.name,
          if (s.color != null) 'color': s.color,
          if (s.category != null) 'category': s.category,
        },
    ],
    if (isDisabled) 'isDisabled': true,
    if (transitions.isNotEmpty)
      'transitions': {
        for (final e in transitions.entries)
          e.key: [
            for (final t in e.value) {'to': t},
          ],
      },
    if (form != null) 'layout': form!.toJson(),
  };

  /// Legal target states from [state], in the type's own state order (New,
  /// Active, Resolved, Closed, Removed): the transition map answers in an
  /// order of its own, which read as unsorted in the picker.
  List<String> transitionsFrom(String state) {
    final targets = transitions[state] ?? const <String>[];
    if (targets.length < 2 || states.isEmpty) return targets;
    final rank = <String, int>{
      for (final (index, s) in states.indexed) s.name: index,
    };
    final ordered = [...targets.indexed];
    ordered.sort((a, b) {
      final byState = (rank[a.$2] ?? states.length).compareTo(
        rank[b.$2] ?? states.length,
      );
      // A state the type does not list keeps the order it came in.
      return byState != 0 ? byState : a.$1.compareTo(b.$1);
    });
    return [for (final entry in ordered) entry.$2];
  }

  WorkItemState? stateNamed(String name) {
    for (final s in states) {
      if (s.name == name) return s;
    }
    return null;
  }

  IconData get icon => iconFor(iconId);

  /// Azure DevOps icon ids mapped to Material glyphs.
  static IconData iconFor(String? iconId) => switch (iconId) {
    'icon_bug' || 'icon_insect' => Icons.bug_report_outlined,
    'icon_task' ||
    'icon_clipboard' ||
    'icon_check_box' => Icons.check_box_outlined,
    'icon_book' => Icons.auto_stories_outlined,
    'icon_crown' => Icons.emoji_events_outlined,
    'icon_trophy' => Icons.workspace_premium_outlined,
    'icon_list' => Icons.list_alt_outlined,
    'icon_test_case' ||
    'icon_test_beaker' ||
    'icon_test_plan' => Icons.science_outlined,
    'icon_test_suite' || 'icon_test_step' => Icons.checklist_outlined,
    'icon_traffic_cone' => Icons.warning_amber_outlined,
    'icon_chat_bubble' => Icons.chat_bubble_outline,
    'icon_review' => Icons.rate_review_outlined,
    'icon_diamond' => Icons.diamond_outlined,
    'icon_flame' => Icons.local_fire_department_outlined,
    'icon_asterisk' => Icons.star_border,
    'icon_sticky_note' => Icons.sticky_note_2_outlined,
    'icon_person' => Icons.person_outline,
    'icon_gear' => Icons.settings_outlined,
    'icon_flag' => Icons.flag_outlined,
    'icon_star' => Icons.star_outline,
    'icon_government' => Icons.account_balance_outlined,
    'icon_car' || 'icon_airplane' => Icons.flight_outlined,
    _ => Icons.circle_outlined,
  };

  @override
  List<Object?> get props => [
    referenceName,
    name,
    color,
    iconId,
    states,
    transitions,
    form,
  ];
}

/// A saved query or folder from `GET _apis/wit/queries?$depth=2`.
class SavedQuery extends Equatable {
  const SavedQuery({
    required this.id,
    required this.name,
    required this.path,
    required this.isFolder,
    this.children = const [],
  });

  factory SavedQuery.fromJson(Map<String, dynamic> json) => SavedQuery(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    path: json['path'] as String? ?? '',
    isFolder: json['isFolder'] as bool? ?? false,
    children: ((json['children'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => SavedQuery.fromJson(m.cast<String, dynamic>()))
        .toList(),
  );

  final String id;
  final String name;
  final String path;
  final bool isFolder;
  final List<SavedQuery> children;

  /// Folder part of [path], e.g. `Shared Queries/Bugs`.
  String get folder {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  /// Every query (not folder) under this node, depth first.
  Iterable<SavedQuery> get leaves sync* {
    if (!isFolder) {
      yield this;
      return;
    }
    for (final c in children) {
      yield* c.leaves;
    }
  }

  @override
  List<Object?> get props => [id];
}

/// From the preview Comments API with `$expand=renderedText`.
class WorkItemComment extends Equatable {
  const WorkItemComment({
    required this.id,
    required this.text,
    required this.renderedText,
    required this.createdBy,
    this.createdDate,
    this.modifiedDate,
    this.format,
  });

  factory WorkItemComment.fromJson(Map<String, dynamic> json) =>
      WorkItemComment(
        id: json['id'] as int,
        text: json['text'] as String? ?? '',
        renderedText:
            json['renderedText'] as String? ?? json['text'] as String? ?? '',
        createdBy:
            IdentityRef.fromField(json['createdBy']) ??
            const IdentityRef(displayName: '?'),
        createdDate: DateTime.tryParse(json['createdDate'] as String? ?? ''),
        modifiedDate: DateTime.tryParse(json['modifiedDate'] as String? ?? ''),
        format: json['format'] as String?,
      );

  final int id;
  final String text;

  /// Server-rendered HTML; render this, never re-implement the dialect
  /// (spike w01).
  final String renderedText;
  final IdentityRef createdBy;
  final DateTime? createdDate;
  final DateTime? modifiedDate;
  final String? format;

  @override
  List<Object?> get props => [id, modifiedDate];
}
