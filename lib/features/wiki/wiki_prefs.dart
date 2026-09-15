import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One entry of a wiki's recent list (K11): the page path the reader opens
/// and the title it shows before the page has been read.
class WikiRecent extends Equatable {
  const WikiRecent({required this.path, required this.title});

  factory WikiRecent.fromJson(Map<String, dynamic> json) => WikiRecent(
    path: json['path'] as String? ?? '',
    title: json['title'] as String? ?? '',
  );

  final String path;
  final String title;

  bool get isEmpty => path.isEmpty;

  Map<String, dynamic> toJson() => {'path': path, 'title': title};

  @override
  List<Object?> get props => [path, title];
}

/// The Wiki hub's per-device memory, kept in `shared_preferences` beside
/// `DashboardPrefs`: the wiki last opened in a project, the page last read
/// in a wiki, and that wiki's five most recent pages (K1, K11).
///
/// Like the dashboard's, this is what lets a cold, offline open draw
/// anything at all: with a remembered wiki id and path the reader has a
/// cache key to look up before the network answers.
///
/// Never throws: preferences can be unavailable (a test, a fresh install),
/// and the memory is not worth failing the page over.
abstract final class WikiPrefs {
  static const _wikiKey = 'wiki_last_id';
  static const _pathKey = 'wiki_last_path';
  static const _recentsKey = 'wiki_recents';

  /// Recent pages kept per wiki (K11: five, on the device, no starring).
  static const maxRecents = 5;

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('WikiPrefs: preferences unavailable ($e)');
      return null;
    }
  }

  static String _project(String org, String project) => '$org/$project';

  static String _wiki(String org, String project, String wikiId) =>
      '$org/$project/$wikiId';

  // ------------------------------------------------------------ last wiki

  /// The wiki last opened in this project, or null when the project has not
  /// been opened on this device.
  static Future<String?> lastWiki(String org, String project) async =>
      (await _prefs())?.getString('$_wikiKey:${_project(org, project)}');

  static Future<void> setLastWiki(
    String org,
    String project,
    String wikiId,
  ) async {
    if (wikiId.isEmpty) return;
    await (await _prefs())?.setString(
      '$_wikiKey:${_project(org, project)}',
      wikiId,
    );
  }

  // ------------------------------------------------------------ last path

  /// The page last read in this wiki, or null — in which case the reader
  /// opens the wiki's home page (K1).
  static Future<String?> lastPath(
    String org,
    String project,
    String wikiId,
  ) async =>
      (await _prefs())?.getString('$_pathKey:${_wiki(org, project, wikiId)}');

  static Future<void> setLastPath(
    String org,
    String project,
    String wikiId,
    String path,
  ) async {
    if (path.isEmpty) return;
    await (await _prefs())?.setString(
      '$_pathKey:${_wiki(org, project, wikiId)}',
      path,
    );
  }

  // -------------------------------------------------------------- recents

  /// The wiki's recent pages, most recent first.
  static Future<List<WikiRecent>> recents(
    String org,
    String project,
    String wikiId,
  ) async {
    final raw = (await _prefs())?.getString(
      '$_recentsKey:${_wiki(org, project, wikiId)}',
    );
    return _decode(raw);
  }

  /// Puts [recent] at the front, dropping an older entry for the same path
  /// and anything past [maxRecents]. Returns the list as it now stands, so
  /// the caller can draw it without reading back.
  static Future<List<WikiRecent>> addRecent(
    String org,
    String project,
    String wikiId,
    WikiRecent recent,
  ) async {
    if (recent.isEmpty) return recents(org, project, wikiId);
    final prefs = await _prefs();
    final key = '$_recentsKey:${_wiki(org, project, wikiId)}';
    final kept = _decode(prefs?.getString(key))
      ..removeWhere((r) => r.path == recent.path)
      ..insert(0, recent);
    while (kept.length > maxRecents) {
      kept.removeLast();
    }
    try {
      await prefs?.setString(
        key,
        jsonEncode([for (final r in kept) r.toJson()]),
      );
    } catch (e) {
      debugPrint('WikiPrefs: could not store recents ($e)');
    }
    return kept;
  }

  /// Forgets one wiki's recents — for a wiki that has gone, and for tests.
  static Future<void> clearRecents(
    String org,
    String project,
    String wikiId,
  ) async {
    await (await _prefs())?.remove(
      '$_recentsKey:${_wiki(org, project, wikiId)}',
    );
  }

  static List<WikiRecent> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <WikiRecent>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <WikiRecent>[];
      return [
        for (final r in decoded)
          if (r is Map) WikiRecent.fromJson(r.cast<String, dynamic>()),
      ]..removeWhere((r) => r.isEmpty);
    } catch (e) {
      debugPrint('WikiPrefs: unreadable recents ($e)');
      return <WikiRecent>[];
    }
  }
}
