import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/http/ado_client.dart';
import '../../core/http/ado_host.dart';
import '../../core/http/ado_exceptions.dart';
import '../db/app_database.dart';
import '../db/json_cache.dart';
import '../models/git_repository.dart';
import 'pipeline_repository.dart' show CachedList;

typedef CachedFile = ({String? objectId, String content, DateTime fetchedAt});

/// Repositories of a project and what the Repos tab shows about them:
/// language breakdown, the user's favorites (the web star, per account),
/// local recents, the remembered branch per repository, branch stats and
/// the README. Everything read is cached as JSON so the list opens offline.
class RepoRepository {
  RepoRepository(this._client, [AppDatabase? db, String? userId])
    : _cache = JsonCache(db, namespace: userId);

  final AdoClient _client;
  final JsonCache _cache;

  static const apiVersion = '7.1';
  static const favoritesApiVersion = '7.1-preview.1';
  static const languagesApiVersion = '7.1-preview.1';
  static const favoriteArtifactType = 'Microsoft.TeamFoundation.Git.Repository';
  static const maxRecents = 5;

  static String listKey(String org, String project) => 'repos:$org:$project';
  static String languagesKey(String org, String project) =>
      'repos:languages:$org:$project';
  static String favoritesKey(String org, String projectId) =>
      'repos:favorites:$org:$projectId';
  static String recentsKey(String org, String project) =>
      'repos:recent:$org:$project';
  static String branchKey(String repoId) => 'repos:branch:$repoId';
  static String readmeKey(String repoId, String branch) =>
      'repos:readme:$repoId:$branch';
  static String treeKey(String repoId, String ref, String path) =>
      'repos:tree:$repoId:$ref:$path';
  static const fileKeyPrefix = 'repos:file:';
  static String fileKey(String repoId, String ref, String path) =>
      '$fileKeyPrefix$repoId:$ref:$path';

  /// Files kept for offline reopening, newest first; older ones are dropped.
  static const maxCachedFiles = 20;

  /// Text files above this size open only on request (research/10 §3.3).
  static const largeFileBytes = 1024 * 1024;

  /// Hard ceiling for text and images loaded into memory on a phone.
  static const maxFileBytes = 20 * 1024 * 1024;

  List<Map<String, dynamic>> _value(Map<String, dynamic> json) =>
      ((json['value'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();

  static List<GitRepository> parseList(List<Map<String, dynamic>> raw) =>
      raw.map(GitRepository.fromJson).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Future<List<GitRepository>> list(String org, String project) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/git/repositories',
      apiVersion: apiVersion,
    );
    final raw = _value(json);
    await _cache.put(listKey(org, project), raw);
    return parseList(raw);
  }

  Future<CachedList<GitRepository>?> cachedList(
    String org,
    String project,
  ) async {
    final cached = await _cache.get(listKey(org, project));
    if (cached == null || cached.json is! List) return null;
    return (
      items: parseList(_value({'value': cached.json})),
      fetchedAt: cached.fetchedAt,
    );
  }

  /// Language breakdown by repository name, biggest share first.
  static Map<String, List<RepoLanguage>> parseLanguages(
    Map<String, dynamic> json,
  ) {
    final out = <String, List<RepoLanguage>>{};
    for (final repo in (json['repositoryLanguageAnalytics'] as List? ?? [])) {
      if (repo is! Map) continue;
      final name = repo['name'] as String?;
      if (name == null) continue;
      final langs =
          ((repo['languageBreakdown'] as List?) ?? const [])
              .whereType<Map>()
              .map((m) => RepoLanguage.fromJson(m.cast<String, dynamic>()))
              .where((l) => l.isLanguage)
              .toList()
            ..sort((a, b) => b.percentage.compareTo(a.percentage));
      out[name] = langs;
    }
    return out;
  }

  Future<Map<String, List<RepoLanguage>>> languages(
    String org,
    String project,
  ) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/projectanalysis/languagemetrics',
      apiVersion: languagesApiVersion,
    );
    await _cache.put(languagesKey(org, project), json);
    return parseLanguages(json);
  }

  Future<Map<String, List<RepoLanguage>>?> cachedLanguages(
    String org,
    String project,
  ) async {
    final cached = await _cache.get(languagesKey(org, project));
    final json = cached?.json;
    return json is Map ? parseLanguages(json.cast<String, dynamic>()) : null;
  }

  /// Favorite repositories of the signed-in user in this project:
  /// repository id → favorite id (needed to remove it).
  Future<Map<String, String>> favorites(String org, String projectId) async {
    final json = await _client.getJson(
      org: org,
      path: '_apis/Favorite/Favorites',
      apiVersion: favoritesApiVersion,
      query: {
        'artifactType': favoriteArtifactType,
        'artifactScopeType': 'Project',
        'artifactScopeId': projectId,
      },
    );
    final map = <String, String>{
      for (final f in _value(json))
        if (f['artifactId'] is String && f['id'] is String)
          f['artifactId'] as String: f['id'] as String,
    };
    await _cache.put(favoritesKey(org, projectId), map);
    return map;
  }

  Future<Map<String, String>?> cachedFavorites(
    String org,
    String projectId,
  ) async {
    final cached = await _cache.get(favoritesKey(org, projectId));
    final json = cached?.json;
    return json is Map ? json.cast<String, String>() : null;
  }

  /// Stars or unstars a repository (spike w11): the same favorite the web
  /// shows, so it follows the person to other devices.
  Future<void> setFavorite({
    required String org,
    required GitRepository repo,
    required bool favorite,
  }) async {
    final current =
        await cachedFavorites(org, repo.projectId) ??
        await favorites(org, repo.projectId);
    final existing = current[repo.id];
    if (favorite && existing == null) {
      final json = await _client.send(
        method: 'POST',
        org: org,
        path: '_apis/Favorite/Favorites',
        apiVersion: favoritesApiVersion,
        body: {
          'artifactId': repo.id,
          'artifactName': repo.name,
          'artifactType': favoriteArtifactType,
          'artifactScope': {
            'id': repo.projectId,
            'type': 'Project',
            'name': repo.projectName,
          },
        },
      );
      final id = json['id'] as String?;
      if (id != null) current[repo.id] = id;
    } else if (!favorite && existing != null) {
      await _client.send(
        method: 'DELETE',
        org: org,
        path: '_apis/Favorite/Favorites/$existing',
        apiVersion: favoritesApiVersion,
        query: {
          'artifactType': favoriteArtifactType,
          'artifactScopeType': 'Project',
          'artifactScopeId': repo.projectId,
        },
      );
      current.remove(repo.id);
    }
    await _cache.put(favoritesKey(org, repo.projectId), current);
  }

  /// Repository ids opened most recently in this project, newest first.
  Future<List<String>> recents(String org, String project) async {
    final cached = await _cache.get(recentsKey(org, project));
    final json = cached?.json;
    return json is List ? json.map((e) => e.toString()).toList() : const [];
  }

  Future<void> markOpened(String org, String project, String repoId) async {
    final list = [
      repoId,
      ...(await recents(org, project)).where((r) => r != repoId),
    ];
    await _cache.put(recentsKey(org, project), list.take(maxRecents).toList());
  }

  /// The branch last chosen for a repository on this device.
  Future<String?> lastBranch(String repoId) async {
    final cached = await _cache.get(branchKey(repoId));
    final json = cached?.json;
    return json is String ? json : null;
  }

  Future<void> setLastBranch(String repoId, String branch) =>
      _cache.put(branchKey(repoId), branch);

  /// Every branch with ahead/behind against the default branch and its
  /// tip commit, default first, then newest activity first.
  Future<List<GitBranch>> branches(
    String org,
    String project,
    String repoId, {
    String? defaultBranch,
  }) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/git/repositories/$repoId/stats/branches',
      apiVersion: apiVersion,
    );
    final list =
        _value(json)
            .map((m) => GitBranch.fromJson(m, defaultBranch: defaultBranch))
            .toList()
          ..sort((a, b) {
            if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
            final ta = a.date?.millisecondsSinceEpoch ?? 0;
            final tb = b.date?.millisecondsSinceEpoch ?? 0;
            return tb.compareTo(ta);
          });
    return list;
  }

  /// One branch's stats; null when the branch no longer exists.
  Future<GitBranch?> branch(
    String org,
    String project,
    String repoId,
    String name, {
    String? defaultBranch,
  }) async {
    try {
      final json = await _client.getJson(
        org: org,
        project: project,
        path: '_apis/git/repositories/$repoId/stats/branches',
        apiVersion: apiVersion,
        query: {'name': name},
      );
      return GitBranch.fromJson(json, defaultBranch: defaultBranch);
    } on AdoNotFoundException {
      return null;
    }
  }

  /// Number of active pull requests targeting the repository, capped at
  /// [top] (the list call is the only way to count).
  Future<int> activePullRequests(
    String org,
    String project,
    String repoId, {
    int top = 100,
  }) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/git/repositories/$repoId/pullrequests',
      apiVersion: apiVersion,
      query: {'searchCriteria.status': 'active', r'$top': '$top'},
    );
    return _value(json).length;
  }

  static const readmeNames = ['README.md', 'readme.md', 'Readme.md', 'README'];

  /// The README at the root of [branch], probing the usual names; empty
  /// string when there is none. Cached per repository and branch.
  Future<String> readme(
    String org,
    String project,
    String repoId,
    String branch,
  ) async {
    for (final name in readmeNames) {
      try {
        final json = await _client.getJson(
          org: org,
          project: project,
          path: '_apis/git/repositories/$repoId/items',
          apiVersion: apiVersion,
          query: {
            'path': '/$name',
            'includeContent': 'true',
            r'$format': 'json',
            'versionDescriptor.version': branch,
            'versionDescriptor.versionType': 'branch',
          },
        );
        final content = json['content'];
        if (content is String) {
          await _cache.put(readmeKey(repoId, branch), content);
          return content;
        }
      } on AdoNotFoundException {
        continue;
      } on AdoException catch (e) {
        debugPrint('readme $name: ${e.message}');
        rethrow;
      }
    }
    await _cache.put(readmeKey(repoId, branch), '');
    return '';
  }

  Future<String?> cachedReadme(String repoId, String branch) async {
    final cached = await _cache.get(readmeKey(repoId, branch));
    final json = cached?.json;
    return json is String ? json : null;
  }

  Map<String, String> _version(String ref) => {
    'versionDescriptor.version': ref,
    'versionDescriptor.versionType': 'branch',
  };

  static List<GitItem> parseTree(List<Map<String, dynamic>> raw, String path) {
    final folder = RepoPaths.normalize(path);
    return raw
        .map(GitItem.fromJson)
        .where((i) => RepoPaths.normalize(i.path) != folder)
        .toList()
      ..sort(GitItem.compare);
  }

  /// One level of the tree at [path] on branch [ref], folders first. The
  /// service has no paging here, so one call is the whole level.
  Future<List<GitItem>> tree(
    String org,
    String project,
    String repoId, {
    required String ref,
    String path = '/',
  }) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/git/repositories/$repoId/items',
      apiVersion: apiVersion,
      query: {
        'scopePath': RepoPaths.normalize(path),
        'recursionLevel': 'OneLevel',
        ..._version(ref),
      },
    );
    final raw = _value(json);
    await _cache.put(treeKey(repoId, ref, RepoPaths.normalize(path)), raw);
    return parseTree(raw, path);
  }

  Future<List<GitItem>?> cachedTree(
    String repoId, {
    required String ref,
    String path = '/',
  }) async {
    final cached = await _cache.get(
      treeKey(repoId, ref, RepoPaths.normalize(path)),
    );
    final json = cached?.json;
    return json is List ? parseTree(_value({'value': json}), path) : null;
  }

  /// Metadata of one file (object id, binary and image flags) without its
  /// content; null when the path does not exist on the branch.
  Future<GitItem?> fileMetadata(
    String org,
    String project,
    String repoId, {
    required String ref,
    required String path,
  }) async {
    try {
      final json = await _client.getJson(
        org: org,
        project: project,
        path: '_apis/git/repositories/$repoId/items',
        apiVersion: apiVersion,
        query: {
          'path': RepoPaths.normalize(path),
          'includeContentMetadata': 'true',
          r'$format': 'json',
          ..._version(ref),
        },
      );
      return GitItem.fromJson(json);
    } on AdoNotFoundException {
      return null;
    }
  }

  /// Size in bytes of a blob, the gate before downloading its content.
  Future<int?> blobSize(
    String org,
    String project,
    String repoId,
    String objectId,
  ) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/git/repositories/$repoId/blobs/$objectId',
      apiVersion: apiVersion,
    );
    return (json['size'] as num?)?.toInt();
  }

  /// Text content of a file on [ref]; cached with its object id so a file
  /// reopens offline and is not downloaded again while unchanged.
  Future<String> fileContent(
    String org,
    String project,
    String repoId, {
    required String ref,
    required String path,
    String? objectId,
  }) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/git/repositories/$repoId/items',
      apiVersion: apiVersion,
      query: {
        'path': RepoPaths.normalize(path),
        'includeContent': 'true',
        r'$format': 'json',
        ..._version(ref),
      },
    );
    final content = json['content'] as String? ?? '';
    await _cache.put(fileKey(repoId, ref, RepoPaths.normalize(path)), {
      'objectId': objectId ?? json['objectId'],
      'content': content,
    });
    await _trimFiles();
    return content;
  }

  Future<CachedFile?> cachedFile(
    String repoId, {
    required String ref,
    required String path,
  }) async {
    final cached = await _cache.get(
      fileKey(repoId, ref, RepoPaths.normalize(path)),
    );
    final json = cached?.json;
    if (json is! Map || json['content'] is! String) return null;
    return (
      objectId: json['objectId'] as String?,
      content: json['content'] as String,
      fetchedAt: cached!.fetchedAt,
    );
  }

  Future<void> _trimFiles() async {
    final keys = await _cache.keysWithPrefix(fileKeyPrefix);
    for (final key in keys.skip(maxCachedFiles)) {
      await _cache.remove(key);
    }
  }

  /// Raw bytes of a file (images) on [ref].
  Future<Uint8List> fileBytes(
    String org,
    String project,
    String repoId, {
    required String ref,
    required String path,
  }) {
    final uri = AdoClient.buildUri(
      host: AdoHost.core,
      org: org,
      project: project,
      path: '_apis/git/repositories/$repoId/items',
      apiVersion: apiVersion,
      query: {
        'path': RepoPaths.normalize(path),
        r'$format': 'octetStream',
        'download': 'false',
        ..._version(ref),
      },
    );
    return _client.getBytes(uri);
  }

  /// Text decoded from [fileBytes], for the rare content the JSON form
  /// cannot carry.
  static String decodeText(Uint8List bytes) =>
      utf8.decode(bytes, allowMalformed: true);
}
