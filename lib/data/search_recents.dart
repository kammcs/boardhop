import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The last queries typed in one organization, on the device (decision D5).
///
/// Nothing leaves the phone: the queries live in `shared_preferences` like
/// the theme choice, keyed by the signed-in account and the organization, and
/// go with the account on sign-out ([clearAccount], called from
/// `AppDependencies.removeAccount`).
///
/// Never throws: preferences can be unavailable (a test, a fresh install),
/// and a missing memory is not worth failing a search over.
class SearchRecents {
  SearchRecents({required this.accountId, this.prefs});

  final String accountId;

  /// Injected in tests (`SharedPreferences.setMockInitialValues` gives one);
  /// otherwise resolved once on first use.
  SharedPreferences? prefs;

  /// Decision D5: the last ten.
  static const max = 10;

  static const keyPrefix = 'search_recents:';

  static String keyFor(String accountId, String org) =>
      '$keyPrefix$accountId:$org';

  Future<SharedPreferences?> _preferences() async {
    final have = prefs;
    if (have != null) return have;
    try {
      return prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('SearchRecents: preferences unavailable ($e)');
      return null;
    }
  }

  /// Newest first.
  Future<List<String>> list(String org) async =>
      (await _preferences())?.getStringList(keyFor(accountId, org)) ??
      const <String>[];

  /// Puts [text] at the front, dropping an earlier spelling of the same query
  /// (the comparison ignores case and surrounding spaces, the stored copy
  /// keeps what was typed). Returns the new list.
  Future<List<String>> add(String org, String text) async {
    final query = text.trim();
    if (query.isEmpty) return list(org);
    final prefs = await _preferences();
    if (prefs == null) return const [];
    final key = keyFor(accountId, org);
    final existing = prefs.getStringList(key) ?? const <String>[];
    final needle = query.toLowerCase();
    final kept = <String>[
      query,
      for (final e in existing)
        if (e.trim().toLowerCase() != needle) e,
    ].take(max).toList();
    await prefs.setStringList(key, kept);
    return kept;
  }

  /// Removes one entry (the swipe on a recent row). Returns the new list.
  Future<List<String>> remove(String org, String text) async {
    final prefs = await _preferences();
    if (prefs == null) return const [];
    final key = keyFor(accountId, org);
    final needle = text.trim().toLowerCase();
    final kept = <String>[
      for (final e in prefs.getStringList(key) ?? const <String>[])
        if (e.trim().toLowerCase() != needle) e,
    ];
    await prefs.setStringList(key, kept);
    return kept;
  }

  Future<void> clear(String org) async =>
      (await _preferences())?.remove(keyFor(accountId, org));

  /// Every organization's recents for one account, on sign-out.
  static Future<void> clearAccount(
    String accountId, {
    SharedPreferences? prefs,
  }) async {
    SharedPreferences? store = prefs;
    if (store == null) {
      try {
        store = await SharedPreferences.getInstance();
      } catch (e) {
        debugPrint('SearchRecents: preferences unavailable ($e)');
        return;
      }
    }
    final mine = '$keyPrefix$accountId:';
    for (final key in store.getKeys().toList()) {
      if (key.startsWith(mine)) await store.remove(key);
    }
  }
}
