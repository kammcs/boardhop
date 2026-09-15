import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small per-project memories of the Sprint view, kept in
/// `shared_preferences` beside the create form's (`FormPrefs`): the tab last
/// looked at (decision S2) and the sprint last opened.
///
/// The sprint memory is not a decision from the interview; it is what lets a
/// cold, offline open draw anything at all. Resolving "which sprint is
/// current" is itself a network read, so without a remembered id the page
/// has nothing to look up in the snapshot cache and shows a spinner on a
/// phone that has opened the same sprint every day for a fortnight.
///
/// Never throws: preferences can be unavailable (a test, a fresh install),
/// and neither memory is worth failing the page over.
abstract final class SprintPrefs {
  static const _tabKey = 'sprint_last_tab';
  static const _iterationKey = 'sprint_last_iteration';

  /// The tab names the route also uses, so a remembered tab and a deep link
  /// spell the same thing.
  static const tabs = ['backlog', 'taskboard', 'burndown'];

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('SprintPrefs: preferences unavailable ($e)');
      return null;
    }
  }

  static String _scope(String org, String project) => '$org/$project';

  /// The remembered tab as an index into [tabs], or null when there is
  /// none (or the stored value is no longer a tab).
  static Future<int?> lastTab(String org, String project) async {
    final name = (await _prefs())?.getString(
      '$_tabKey:${_scope(org, project)}',
    );
    final index = tabs.indexOf(name ?? '');
    return index < 0 ? null : index;
  }

  static Future<void> setLastTab(String org, String project, int index) async {
    if (index < 0 || index >= tabs.length) return;
    await (await _prefs())?.setString(
      '$_tabKey:${_scope(org, project)}',
      tabs[index],
    );
  }

  static Future<String?> lastIteration(String org, String project) async =>
      (await _prefs())?.getString('$_iterationKey:${_scope(org, project)}');

  static Future<void> setLastIteration(
    String org,
    String project,
    String iterationId,
  ) async {
    await (await _prefs())?.setString(
      '$_iterationKey:${_scope(org, project)}',
      iterationId,
    );
  }
}
