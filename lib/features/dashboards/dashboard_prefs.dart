import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Dashboards hub's one per-project memory, kept in `shared_preferences`
/// beside `SprintPrefs`: the dashboard last opened (decision D6).
///
/// Like the sprint's, this is what lets a cold, offline open draw anything at
/// all. The default dashboard is "the default team's Overview", and resolving
/// that is two network reads; with a remembered id the page has a cache key to
/// look up before the network answers.
///
/// Never throws: preferences can be unavailable (a test, a fresh install),
/// and the memory is not worth failing the page over.
abstract final class DashboardPrefs {
  static const _dashboardKey = 'dashboard_last_id';

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('DashboardPrefs: preferences unavailable ($e)');
      return null;
    }
  }

  static String _scope(String org, String project) => '$org/$project';

  /// The dashboard id last opened in this project, or null when the project
  /// has not been opened on this device.
  static Future<String?> lastDashboard(String org, String project) async =>
      (await _prefs())?.getString('$_dashboardKey:${_scope(org, project)}');

  static Future<void> setLastDashboard(
    String org,
    String project,
    String dashboardId,
  ) async {
    if (dashboardId.isEmpty) return;
    await (await _prefs())?.setString(
      '$_dashboardKey:${_scope(org, project)}',
      dashboardId,
    );
  }

  /// Forgets the project's dashboard — for the Team overview, which is not a
  /// dashboard of the service and has no id to deep link to.
  static Future<void> clearLastDashboard(String org, String project) async {
    await (await _prefs())?.remove('$_dashboardKey:${_scope(org, project)}');
  }
}
