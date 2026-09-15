import 'package:equatable/equatable.dart';

/// What a wiki-relative href in a page resolves to (research/20 §4.2).
enum WikiHrefKind {
  /// Another page of the same wiki, possibly with an anchor.
  page,

  /// An anchor on the page the href was written on.
  anchor,

  /// A file under `/.attachments/` in the wiki's git repository.
  attachment,
}

/// A wiki-relative href resolved against the page it was written on.
class WikiHref extends Equatable {
  const WikiHref._(this.kind, {this.path = '', this.anchor});

  const WikiHref.page(String path, {String? anchor})
    : this._(WikiHrefKind.page, path: path, anchor: anchor);

  const WikiHref.anchor(String anchor)
    : this._(WikiHrefKind.anchor, anchor: anchor);

  const WikiHref.attachment(String path)
    : this._(WikiHrefKind.attachment, path: path);

  final WikiHrefKind kind;

  /// The page path (title form) for [WikiHrefKind.page], the repository
  /// path for [WikiHrefKind.attachment], empty for an anchor.
  final String path;

  /// The heading anchor, already in [WikiLink.anchorId] form when the href
  /// carried one.
  final String? anchor;

  bool get isPage => kind == WikiHrefKind.page;
  bool get isAnchor => kind == WikiHrefKind.anchor;
  bool get isAttachment => kind == WikiHrefKind.attachment;

  @override
  List<Object?> get props => [kind, path, anchor];

  @override
  String toString() =>
      'WikiHref(${kind.name}, $path${anchor == null ? '' : ' #$anchor'})';
}

/// Every wiki URL form the app has to understand, and the two it writes.
///
/// Pure Dart, no Flutter: the same parsing is wanted by the reader, the
/// comment views, the Related tab and the composer picker (K5, K12).
///
/// Three web forms and one artifact URI (research/20 §1, spikes s62/s63/w37):
///
/// * the **id form**, what the web's *Copy page URL* writes —
///   `…/{project}/_wiki/wikis/{wikiIdOrName}/{pageId}/{Page-Title}`;
/// * the **path form**, what the REST `remoteUrl` carries —
///   `…/_wiki/wikis/{wikiIdOrName}?pagePath=%2F…[&wikiVersion=GB…]`;
/// * the **wiki root**, the same without a page;
/// * the **artifact URI** a work item's `ArtifactLink` relation carries —
///   `vstfs:///Wiki/WikiPage/{projectId}%2F{wikiId}%2F{Page%2FPath}`.
class WikiLink extends Equatable {
  const WikiLink({
    required this.wikiIdOrName,
    this.org,
    this.project,
    this.pageId,
    this.path,
    this.version,
    this.anchor,
    this.title,
  });

  /// The organization, when the form carried one (the artifact URI does
  /// not).
  final String? org;

  /// The project name or GUID. `remoteUrl` uses the GUID, the web the name.
  final String? project;

  /// The wiki's GUID or its name (`DevOps-Mobile-App.wiki`); both work on
  /// every `_apis/wiki/wikis/{wikiIdOrName}` route (spike w37).
  final String wikiIdOrName;

  /// The page id, set by the id form only.
  final int? pageId;

  /// The title-form page path, set by the path form and the artifact URI.
  /// Null on the id form and on a wiki root.
  final String? path;

  /// The branch, from `wikiVersion=GB{branch}`.
  final String? version;

  /// The heading anchor, from `#fragment` or `&anchor=`.
  final String? anchor;

  /// The title slug of the id form, with its hyphens read back as spaces —
  /// something to show before the page has been read. Null otherwise.
  final String? title;

  /// True when the link names the wiki but no page.
  bool get isWikiRoot => pageId == null && (path == null || path == '/');

  @override
  List<Object?> get props => [
    org,
    project,
    wikiIdOrName,
    pageId,
    path,
    version,
    anchor,
  ];

  @override
  String toString() =>
      'WikiLink($org/$project wiki=$wikiIdOrName'
      '${pageId == null ? '' : ' id=$pageId'}'
      '${path == null ? '' : ' path=$path'}'
      '${version == null ? '' : ' version=$version'}'
      '${anchor == null ? '' : ' #$anchor'})';

  static const _artifactPrefix = 'vstfs:///Wiki/WikiPage/';

  /// Parses any of the four forms, or null when [href] is not a wiki link.
  static WikiLink? parse(String href) {
    final raw = href.trim();
    if (raw.isEmpty) return null;
    if (raw.toLowerCase().startsWith(_artifactPrefix.toLowerCase())) {
      return _parseArtifact(raw);
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return _parseWeb(uri);
  }

  /// `vstfs:///Wiki/WikiPage/{projectId}%2F{wikiId}%2F{seg%2Fseg}` — the
  /// segments are URL-encoded and joined by `%2F`, and the path's leading
  /// slash is dropped (spike w37 §7).
  static WikiLink? _parseArtifact(String raw) {
    final body = raw.substring(_artifactPrefix.length);
    if (body.isEmpty) return null;
    final parts = body
        .split(RegExp('%2F', caseSensitive: false))
        .map(_decode)
        .toList();
    if (parts.length < 2 || parts[1].isEmpty) return null;
    final segments = parts.sublist(2).where((s) => s.isNotEmpty);
    return WikiLink(
      project: parts[0].isEmpty ? null : parts[0],
      wikiIdOrName: parts[1],
      path: segments.isEmpty ? null : '/${segments.join('/')}',
    );
  }

  static WikiLink? _parseWeb(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final at = segments.indexOf('_wiki');
    if (at < 0 || at + 2 >= segments.length) return null;
    if (segments[at + 1] != 'wikis') return null;

    final host = uri.host.toLowerCase();
    final legacy = host.endsWith('.visualstudio.com');
    final org = legacy
        ? host.substring(0, host.indexOf('.'))
        : (at >= 1 ? segments[0] : null);
    // The segment right before `_wiki` is the project, unless it is the
    // organization itself (`dev.azure.com/{org}/_wiki/…`).
    final projectAt = at - 1;
    final project = projectAt >= (legacy ? 0 : 1) ? segments[projectAt] : null;

    final wiki = segments[at + 2];
    if (wiki.isEmpty) return null;
    final pageId = at + 3 < segments.length
        ? int.tryParse(segments[at + 3])
        : null;
    final slug = pageId != null && at + 4 < segments.length
        ? _titleFromSlug(segments[at + 4])
        : null;

    final query = uri.queryParameters;
    final pagePath = query['pagePath'] ?? query['path'];
    final version = _version(query['wikiVersion'] ?? query['version']);
    final fragment = uri.fragment.isEmpty ? null : uri.fragment;
    final anchor = query['anchor'] ?? fragment;

    return WikiLink(
      org: org,
      project: project,
      wikiIdOrName: wiki,
      pageId: pageId,
      path: pagePath == null || pagePath.isEmpty ? null : pagePath,
      version: version,
      anchor: anchor == null || anchor.isEmpty ? null : anchor,
      title: slug == null || slug.isEmpty ? null : slug,
    );
  }

  /// The title behind an id-form slug: `-` back to a space and every `%XX`
  /// back to its character, the same rule a git file name follows
  /// ([WikiSearchHit.decodeGitName], which this repeats so `wiki_link.dart`
  /// stays free of the models).
  ///
  /// Best effort only. Dart's `Uri` normalises `%2D` to a plain hyphen
  /// (it is an unreserved character), so a title whose own text contains a
  /// hyphen reads back with a space there. That costs nothing: the id form
  /// carries the page id, which is what the page is read by — the slug is
  /// only something to show while it loads.
  static String _titleFromSlug(String slug) {
    final spaced = slug.replaceAll('-', ' ');
    try {
      return Uri.decodeComponent(spaced);
    } on ArgumentError {
      return spaced;
    } on FormatException {
      return spaced;
    }
  }

  /// `GBwikiMaster` → `wikiMaster`; a version without the branch prefix is
  /// taken as it is.
  static String? _version(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.length > 2 && raw.startsWith('GB')) return raw.substring(2);
    return raw;
  }

  static String _decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } on ArgumentError {
      return value;
    } on FormatException {
      return value;
    }
  }

  // ------------------------------------------------------------- relative

  /// Resolves a wiki-relative [href] against the page it was written on.
  ///
  /// `/A/B` is absolute from the wiki root, `./C` and `../D` resolve against
  /// the page's own folder, `#anchor` stays on the page, `A/B#anchor`
  /// carries both, and anything under `/.attachments/` is a file in the
  /// wiki repository. A trailing `.md` is dropped: a page path never has
  /// one. Returns null for an empty href or one with a scheme — those go
  /// through [parse] or to the browser.
  static WikiHref? resolve(String href, {required String pagePath}) {
    var raw = href.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('#')) {
      final anchor = raw.substring(1).trim();
      return anchor.isEmpty ? null : WikiHref.anchor(anchorId(anchor));
    }
    if (Uri.tryParse(raw)?.hasScheme ?? false) return null;

    String? anchor;
    final hash = raw.indexOf('#');
    if (hash >= 0) {
      final tail = raw.substring(hash + 1).trim();
      if (tail.isNotEmpty) anchor = anchorId(tail);
      raw = raw.substring(0, hash);
    }
    final question = raw.indexOf('?');
    if (question >= 0) raw = raw.substring(0, question);
    raw = raw.trim();
    if (raw.isEmpty) {
      return anchor == null ? null : WikiHref.anchor(anchor);
    }

    final absolute = raw.startsWith('/');
    final base = absolute ? const <String>[] : _segments(_parent(pagePath));
    final out = List<String>.of(base);
    for (final segment in raw.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      out.add(_decode(segment));
    }
    if (out.isEmpty) return anchor == null ? null : WikiHref.anchor(anchor);
    // `/.attachments/x.png` is how the wiki writes them; a relative
    // `.attachments/x.png` from a nested page means the same file.
    final attachments = out.indexWhere(
      (s) => s.toLowerCase() == '.attachments',
    );
    if (attachments >= 0) {
      return WikiHref.attachment('/${out.sublist(attachments).join('/')}');
    }
    var last = out.last;
    if (last.toLowerCase().endsWith('.md')) {
      last = last.substring(0, last.length - 3);
      out[out.length - 1] = last;
    }
    return WikiHref.page('/${out.join('/')}', anchor: anchor);
  }

  static List<String> _segments(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();

  static String _parent(String path) {
    final segments = _segments(path);
    if (segments.length <= 1) return '/';
    return '/${segments.sublist(0, segments.length - 1).join('/')}';
  }

  // --------------------------------------------------------------- anchors

  /// Everything that is not a letter, a digit, a space, a hyphen or an
  /// underscore. Unicode-aware, so an accented or CJK heading keeps its
  /// letters instead of losing them all.
  static final _dropped = RegExp(r'[^\p{L}\p{N} \-_]', unicode: true);

  /// The anchor id the wiki gives a heading: lower-cased, punctuation
  /// dropped, spaces turned into hyphens — and **no collapsing**, so the
  /// documented example `Team #1 : Release Wiki!` becomes
  /// `team-1--release-wiki` (research/20 §1).
  static String anchorId(String headingText) => headingText
      .trim()
      .toLowerCase()
      .replaceAll(_dropped, '')
      .replaceAll(' ', '-');

  /// True when two anchors name the same heading.
  ///
  /// Exact first; the fallback collapses runs of hyphens, which is what
  /// catches a link an author typed as `#team-1-release-wiki` for a heading
  /// whose id keeps the double hyphen.
  static bool anchorMatches(String a, String b) {
    final left = a.trim().toLowerCase();
    final right = b.trim().toLowerCase();
    if (left == right) return true;
    return _collapse(left) == _collapse(right);
  }

  static final _runs = RegExp(r'-+');

  static String _collapse(String value) {
    final collapsed = value.replaceAll(_runs, '-');
    return collapsed.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  // ---------------------------------------------------------------- build

  /// The id form, the URL the web's *Copy page URL* writes and the one the
  /// composer's picker inserts (K12).
  static String webUrl(
    String org,
    String project,
    String wikiName,
    int pageId,
    String title,
  ) {
    final slug = title.trim().replaceAll(' ', '-');
    return 'https://dev.azure.com/${Uri.encodeComponent(org)}'
        '/${Uri.encodeComponent(project)}/_wiki/wikis'
        '/${Uri.encodeComponent(wikiName)}/$pageId'
        '/${Uri.encodeComponent(slug)}';
  }

  /// The path form, which needs no page id — what a link to a page whose id
  /// is not known has to use.
  static String pageUrl(
    String org,
    String project,
    String wikiIdOrName,
    String path, {
    String? version,
  }) {
    final query = StringBuffer('?pagePath=${Uri.encodeComponent(path)}');
    if (version != null && version.isNotEmpty) {
      query.write('&wikiVersion=GB${Uri.encodeComponent(version)}');
    }
    return 'https://dev.azure.com/${Uri.encodeComponent(org)}'
        '/${Uri.encodeComponent(project)}/_wiki/wikis'
        '/${Uri.encodeComponent(wikiIdOrName)}$query';
  }

  /// The `ArtifactLink` URI a work item's Wiki Page relation carries. Read
  /// only in v1: nothing in the app writes one (research/20 §6).
  static String artifactUri(String projectId, String wikiId, String path) {
    final segments = _segments(path).map(Uri.encodeComponent);
    final tail = segments.isEmpty ? '' : '%2F${segments.join('%2F')}';
    return '$_artifactPrefix$projectId%2F$wikiId$tail';
  }
}
