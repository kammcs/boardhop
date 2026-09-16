import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The diff viewer's one remembered choice: wrap long lines or scroll them
/// sideways (R16), per signed-in account like every other preference.
///
/// Cloned from `DashboardPrefs`, including its rule that it never throws:
/// preferences can be unavailable (a test, a fresh install) and a remembered
/// toggle is not worth failing the page over.
abstract final class DiffPrefs {
  static const _wrapKey = 'diff_wrap';

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('DiffPrefs: preferences unavailable ($e)');
      return null;
    }
  }

  static String _k(String key, String account) => '$key:$account';

  /// Whether long lines wrap; off by default, which is what the diff does
  /// today.
  static Future<bool> wrap(String account) async =>
      (await _prefs())?.getBool(_k(_wrapKey, account)) ?? false;

  static Future<void> setWrap(String account, bool wrap) async {
    if (account.isEmpty) return;
    await (await _prefs())?.setBool(_k(_wrapKey, account), wrap);
  }
}
