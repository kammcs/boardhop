import 'package:equatable/equatable.dart';

import 'search.dart';

/// The two kinds of wiki a project can have (research/20 §1).
///
/// A project has zero or one [projectWiki] — its own hidden git repository,
/// whose id equals the wiki id — and any number of [codeWiki]s, each one a
/// folder of an ordinary repository published per branch.
enum WikiType {
  projectWiki,
  codeWiki;

  static WikiType fromWire(Object? value) =>
      '$value'.toLowerCase() == 'codewiki' ? codeWiki : projectWiki;
}

/// One wiki of a project, as `GET wikis` answers it.
class Wiki extends Equatable {
  const Wiki({
    required this.id,
    required this.name,
    required this.type,
    this.projectId = '',
    this.repositoryId = '',
    this.mappedPath = '/',
    this.versions = const [],
    this.remoteUrl,
  });

  factory Wiki.fromJson(Map<String, dynamic> json) => Wiki(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    type: WikiType.fromWire(json['type']),
    projectId: json['projectId'] as String? ?? '',
    // A project wiki's repository is the wiki itself; the field is always
    // sent, but falling back to the id keeps a trimmed fixture usable.
    repositoryId:
        json['repositoryId'] as String? ?? json['id'] as String? ?? '',
    mappedPath: json['mappedPath'] as String? ?? '/',
    versions: _versions(json['versions']),
    remoteUrl: json['remoteUrl'] as String?,
  );

  /// `[{version: 'wikiMaster'}]` on the wire; a plain list of strings is
  /// accepted too so a hand-written fixture reads back.
  static List<String> _versions(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final v in raw) {
      final version = v is Map ? v['version'] : v;
      if (version is String && version.isNotEmpty) out.add(version);
    }
    return out;
  }

  final String id;
  final String name;
  final WikiType type;
  final String projectId;

  /// The git repository the pages live in. For a project wiki this is the
  /// wiki id; the repository is hidden from `git/repositories` but every
  /// `git/repositories/{id}` route works on it (research/20 §1).
  final String repositoryId;

  /// The folder of [repositoryId] the wiki is published from: `/` for a
  /// project wiki, the published folder for a code wiki.
  final String mappedPath;

  /// The branches this wiki is published from. A project wiki has exactly
  /// one (`wikiMaster`); a code wiki may have up to ten.
  final List<String> versions;
  final String? remoteUrl;

  /// The branch every read passes (K8). The first published version, or the
  /// project wiki's branch when a trimmed answer carried none.
  String get version => versions.isEmpty ? 'wikiMaster' : versions.first;

  bool get isProjectWiki => type == WikiType.projectWiki;

  /// A code wiki whose pages sit under a folder of its repository.
  bool get hasMappedPath => mappedPath.isNotEmpty && mappedPath != '/';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'projectId': projectId,
    'repositoryId': repositoryId,
    'mappedPath': mappedPath,
    'versions': [
      for (final v in versions) {'version': v},
    ],
    if (remoteUrl != null) 'remoteUrl': remoteUrl,
  };

  @override
  List<Object?> get props => [
    id,
    name,
    type,
    repositoryId,
    mappedPath,
    versions,
  ];
}

/// One node of a wiki's page tree.
///
/// The tree call answers `path` (the **title form**, spaces kept) and
/// `gitItemPath` (the **file form**, space → `-`, hyphen → `%2D`) and **no
/// id**; ids come from `POST pagesbatch` and are joined on `path`
/// ([withIds]). One form is never derived from the other (research/20 §1).
class WikiPageNode extends Equatable {
  const WikiPageNode({
    required this.path,
    this.id,
    this.gitItemPath = '',
    this.order = 0,
    this.isParentPage = false,
    this.isNonConformant = false,
    this.subPages = const [],
  });

  factory WikiPageNode.fromJson(Map<String, dynamic> json) => WikiPageNode(
    id: _int(json['id']),
    path: json['path'] as String? ?? '/',
    gitItemPath: json['gitItemPath'] as String? ?? '',
    order: _int(json['order']) ?? 0,
    isParentPage: json['isParentPage'] == true,
    isNonConformant: json['isNonConformant'] == true,
    subPages: childrenOf(json['subPages']),
  );

  /// The `subPages` of a tree or page answer, in the order the tree should
  /// be drawn in.
  ///
  /// The service returns siblings **alphabetically**, not by `order`: the
  /// scratch wiki answers Constructs (order 1) before Links (order 0), and
  /// a page that is not in its folder's `.order` carries `order`
  /// [unordered] (spike w37). Sorting here is what puts the `.order` run
  /// first and the rest behind it, everywhere the tree is read.
  static List<WikiPageNode> childrenOf(Object? raw) {
    if (raw is! List) return const [];
    final nodes = [
      for (final p in raw)
        if (p is Map) WikiPageNode.fromJson(p.cast<String, dynamic>()),
    ];
    nodes.sort(compare);
    return nodes;
  }

  /// `.order` position first, then title, case-insensitively, so two pages
  /// outside `.order` keep a stable order of their own.
  static int compare(WikiPageNode a, WikiPageNode b) {
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  /// The `order` of a page the folder's `.order` file does not name: the
  /// service sends `int32.max`, which sorts it behind everything listed.
  static const unordered = 2147483647;

  static int? _int(Object? value) => switch (value) {
    int() => value,
    num() => value.toInt(),
    String() => int.tryParse(value),
    _ => null,
  };

  /// The page id, or null on a node that came from the tree call alone.
  final int? id;

  /// The title-form path, `/` for the root.
  final String path;

  /// The file-form path of the markdown blob in the wiki repository.
  final String gitItemPath;
  final int order;
  final bool isParentPage;

  /// A file pushed into the wiki repository whose name the wiki cannot map
  /// back to a page (a space in the file name). It is listed but 404s by
  /// path and by id, so it is shown greyed and is not openable.
  final bool isNonConformant;
  final List<WikiPageNode> subPages;

  /// The last segment of [path], as it is: the title form keeps spaces and
  /// hyphens. Empty for the root.
  String get title => titleOf(path);

  static String titleOf(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty);
    return segments.isEmpty ? '' : segments.last;
  }

  bool get isRoot => path == '/' || path.isEmpty;

  /// This node and every descendant, depth first, in tree order.
  List<WikiPageNode> flatten() => [
    this,
    for (final child in subPages) ...child.flatten(),
  ];

  /// The node at [path] anywhere in this subtree, or null.
  ///
  /// Matching is exact first; a case-insensitive match is the fallback, so a
  /// link whose author typed `/boardhop/links` still lands on the page.
  WikiPageNode? find(String path) {
    final wanted = _normalize(path);
    final lower = wanted.toLowerCase();
    WikiPageNode? loose;
    for (final node in flatten()) {
      final have = _normalize(node.path);
      if (have == wanted) return node;
      if (loose == null && have.toLowerCase() == lower) loose = node;
    }
    return loose;
  }

  /// The chain of nodes above the page at [path], outermost first, without
  /// the page itself and without this node (which is usually the root).
  /// Empty when [path] is not in this subtree.
  List<WikiPageNode> ancestorsOf(String path) {
    final wanted = _normalize(path);
    final trail = <WikiPageNode>[];
    bool walk(WikiPageNode node) {
      if (_normalize(node.path) == wanted) return true;
      for (final child in node.subPages) {
        trail.add(child);
        if (walk(child)) return true;
        trail.removeLast();
      }
      return false;
    }

    if (!walk(this)) return const [];
    // The last entry is the page itself.
    return trail.isEmpty ? const [] : trail.sublist(0, trail.length - 1);
  }

  /// This subtree with the ids of [byPath] filled in — the join that puts
  /// `pagesbatch` ids on tree nodes. A path the batch did not carry keeps
  /// the id it had.
  WikiPageNode withIds(Map<String, int> byPath) => copyWith(
    id: byPath[path] ?? byPath[_normalize(path)] ?? id,
    subPages: [for (final child in subPages) child.withIds(byPath)],
  );

  WikiPageNode copyWith({int? id, List<WikiPageNode>? subPages}) =>
      WikiPageNode(
        id: id ?? this.id,
        path: path,
        gitItemPath: gitItemPath,
        order: order,
        isParentPage: isParentPage,
        isNonConformant: isNonConformant,
        subPages: subPages ?? this.subPages,
      );

  static String _normalize(String path) {
    var p = path.trim();
    if (p.isEmpty) return '/';
    if (!p.startsWith('/')) p = '/$p';
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'path': path,
    if (gitItemPath.isNotEmpty) 'gitItemPath': gitItemPath,
    'order': order,
    if (isParentPage) 'isParentPage': true,
    if (isNonConformant) 'isNonConformant': true,
    'subPages': [for (final child in subPages) child.toJson()],
  };

  @override
  List<Object?> get props => [
    id,
    path,
    gitItemPath,
    order,
    isParentPage,
    isNonConformant,
    subPages,
  ];
}

/// One page with its markdown, as `pages?path=…&includeContent=true` or
/// `pages/{id}?includeContent=true` answers it.
class WikiPage extends Equatable {
  const WikiPage({
    required this.path,
    this.id,
    this.gitItemPath = '',
    this.content = '',
    this.etag,
    this.order = 0,
    this.isParentPage = false,
    this.subPages = const [],
    this.remoteUrl,
  });

  /// [etag] is not a body field: the repository puts the response's `ETag`
  /// header into the map before caching it, so the cached copy carries it
  /// too.
  factory WikiPage.fromJson(Map<String, dynamic> json) => WikiPage(
    id: WikiPageNode._int(json['id']),
    path: json['path'] as String? ?? '',
    gitItemPath: json['gitItemPath'] as String? ?? '',
    content: json['content'] as String? ?? '',
    etag: _etag(json['etag'] ?? json['eTag']),
    order: WikiPageNode._int(json['order']) ?? 0,
    isParentPage: json['isParentPage'] == true,
    subPages: WikiPageNode.childrenOf(json['subPages']),
    remoteUrl: json['remoteUrl'] as String?,
  );

  /// The header arrives quoted (`"e33a90d…"`) and sometimes weak-tagged.
  static String? _etag(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    var value = raw.trim();
    if (value.startsWith('W/')) value = value.substring(2).trim();
    if (value.length > 1 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    return value.isEmpty ? null : value;
  }

  final int? id;
  final String path;
  final String gitItemPath;
  final String content;

  /// The page's git blob SHA, from the `ETag` header — the same value
  /// search calls `contentId`. `If-None-Match` is ignored by the service
  /// (it always answers 200), so this is a client-side change key only.
  final String? etag;
  final int order;
  final bool isParentPage;
  final List<WikiPageNode> subPages;
  final String? remoteUrl;

  String get title => WikiPageNode.titleOf(path);

  WikiPage copyWith({String? etag}) => WikiPage(
    id: id,
    path: path,
    gitItemPath: gitItemPath,
    content: content,
    etag: etag ?? this.etag,
    order: order,
    isParentPage: isParentPage,
    subPages: subPages,
    remoteUrl: remoteUrl,
  );

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'path': path,
    if (gitItemPath.isNotEmpty) 'gitItemPath': gitItemPath,
    'content': content,
    if (etag != null) 'etag': etag,
    'order': order,
    if (isParentPage) 'isParentPage': true,
    'subPages': [for (final child in subPages) child.toJson()],
    if (remoteUrl != null) 'remoteUrl': remoteUrl,
  };

  @override
  List<Object?> get props => [id, path, content, etag];
}

/// One hit from `POST search/wikisearchresults`.
///
/// The service answers the **git file path**, never the page path, so
/// [pagePath] converts it back (research/20 §1).
class WikiSearchHit extends Equatable {
  const WikiSearchHit({
    required this.fileName,
    required this.path,
    this.wikiId = '',
    this.wikiName = '',
    this.mappedPath = '/',
    this.version = '',
    this.projectName = '',
    this.projectId = '',
    this.contentId = '',
    this.highlights = const [],
  });

  factory WikiSearchHit.fromJson(Map<String, dynamic> json) {
    final wiki = (json['wiki'] as Map?)?.cast<String, dynamic>();
    final project = (json['project'] as Map?)?.cast<String, dynamic>();
    return WikiSearchHit(
      fileName: json['fileName'] as String? ?? '',
      path: json['path'] as String? ?? '',
      wikiId: wiki?['id'] as String? ?? '',
      wikiName: wiki?['name'] as String? ?? '',
      mappedPath: wiki?['mappedPath'] as String? ?? '/',
      version: wiki?['version'] as String? ?? '',
      projectName: project?['name'] as String? ?? '',
      projectId: project?['id'] as String? ?? '',
      contentId: json['contentId'] as String? ?? '',
      highlights: SearchHighlight.fromHits(json['hits']),
    );
  }

  final String fileName;

  /// The git file path of the markdown blob, e.g. `/Boardhop/Deep-child.md`.
  final String path;
  final String wikiId;
  final String wikiName;
  final String mappedPath;
  final String version;
  final String projectName;

  /// The project's GUID, so an organization-wide hit opens in its own
  /// project without another lookup.
  final String projectId;

  /// The page's git blob SHA — the same value `WikiPage.etag` carries.
  final String contentId;
  final List<SearchHighlight> highlights;

  /// The page path the reader opens, derived from the git file [path]:
  /// `mappedPath` dropped for a code wiki, `.md` stripped, `-` back to a
  /// space and `%2D` back to a hyphen — in that order, because a `%2D`
  /// carries no hyphen of its own to lose.
  String get pagePath => pagePathOf(path, mappedPath: mappedPath);

  static String pagePathOf(String gitPath, {String mappedPath = '/'}) {
    var p = gitPath.trim();
    if (p.isEmpty) return '';
    if (!p.startsWith('/')) p = '/$p';
    final mapped = mappedPath.trim();
    if (mapped.isNotEmpty && mapped != '/') {
      var prefix = mapped.startsWith('/') ? mapped : '/$mapped';
      while (prefix.length > 1 && prefix.endsWith('/')) {
        prefix = prefix.substring(0, prefix.length - 1);
      }
      if (p == prefix) {
        p = '/';
      } else if (p.toLowerCase().startsWith('${prefix.toLowerCase()}/')) {
        p = p.substring(prefix.length);
      }
    }
    if (p.toLowerCase().endsWith('.md')) p = p.substring(0, p.length - 3);
    return p.replaceAll('-', ' ').replaceAll('%2D', '-').replaceAll('%2d', '-');
  }

  /// The page title: the last segment of [pagePath].
  String get title => WikiPageNode.titleOf(pagePath);

  /// The one line a row shows under the title: a content match says more
  /// than the file name the title already shows.
  SearchHighlight? get highlight {
    SearchHighlight? nameHit;
    for (final h in highlights) {
      if (!h.hasHit || h.isEmpty) continue;
      if (h.fieldReferenceName.toLowerCase() == 'filenames') {
        nameHit ??= h;
        continue;
      }
      return h;
    }
    return nameHit;
  }

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'path': path,
    'wiki': {
      'id': wikiId,
      'name': wikiName,
      'mappedPath': mappedPath,
      'version': version,
    },
    'project': {'id': projectId, 'name': projectName},
    'contentId': contentId,
    'hits': [for (final h in highlights) h.toJson()],
  };

  @override
  List<Object?> get props => [wikiId, path, contentId, highlights];
}

/// The last commit that touched a page, for the K9 footer line
/// ("Last changed by A on date").
class WikiPageChange extends Equatable {
  const WikiPageChange({this.author = '', this.date, this.comment = ''});

  /// One row of `git/repositories/{id}/commits`.
  factory WikiPageChange.fromJson(Map<String, dynamic> json) {
    final author = (json['author'] as Map?)?.cast<String, dynamic>();
    final committer = (json['committer'] as Map?)?.cast<String, dynamic>();
    return WikiPageChange(
      author: author?['name'] as String? ?? committer?['name'] as String? ?? '',
      date:
          DateTime.tryParse(author?['date'] as String? ?? '') ??
          DateTime.tryParse(committer?['date'] as String? ?? ''),
      comment: json['comment'] as String? ?? '',
    );
  }

  final String author;
  final DateTime? date;
  final String comment;

  bool get isEmpty => author.isEmpty && date == null;

  Map<String, dynamic> toJson() => {
    'author': {
      'name': author,
      if (date != null) 'date': date!.toUtc().toIso8601String(),
    },
    'comment': comment,
  };

  @override
  List<Object?> get props => [author, date, comment];
}
