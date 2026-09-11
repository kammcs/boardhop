import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart' show IconData, Icons;

import '../../core/util/format.dart';

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
      descriptor: json['descriptor'] as String?,
    );
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
class WorkItem extends Equatable {
  const WorkItem({
    required this.id,
    required this.rev,
    required this.fields,
    this.url,
    this.multilineFieldsFormat = const {},
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
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'rev': rev,
    if (url != null) 'url': url,
    'fields': fields,
    'multilineFieldsFormat': multilineFieldsFormat,
  };

  final int id;
  final int rev;
  final String? url;
  final Map<String, dynamic> fields;

  /// `System.Description` → `html` | `markdown`, only present on reads made
  /// without a `fields` filter (spike S5b).
  final Map<String, String> multilineFieldsFormat;

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
class WorkItemType extends Equatable {
  const WorkItemType({
    required this.name,
    required this.referenceName,
    this.color,
    this.iconId,
    this.states = const [],
    this.isDisabled = false,
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
  );

  final String name;
  final String referenceName;
  final String? color;
  final String? iconId;
  final List<WorkItemState> states;
  final bool isDisabled;

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
  List<Object?> get props => [referenceName, name, color, iconId];
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
