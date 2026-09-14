import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/work_item.dart';

/// The people most recently mentioned in one project, on the device
/// (research/16 M2 and M5: the bare `@` lists participants, then these, then
/// the team, before anything is searched).
///
/// The twin of `SearchRecents` and of `FormPrefs.recentAssignees`: nothing
/// leaves the phone, the list lives in `shared_preferences` keyed by the
/// signed-in account, the organization *and the project* (mentions are
/// project-scoped, M2), and it goes with the account on sign-out
/// ([clearAccount], called from `AppDependencies.removeAccount`).
///
/// Only people who carry an identity GUID are worth remembering — a person
/// without one cannot be mentioned at all (M15) — but the GUID is not
/// required here, so a row saved by an older build still reads back.
///
/// Never throws: preferences can be unavailable (a test, a fresh install),
/// and a missing memory is not worth failing a comment over.
class MentionRecents {
  MentionRecents({required this.accountId, this.prefs});

  final String accountId;

  /// Injected in tests (`SharedPreferences.setMockInitialValues` gives one);
  /// otherwise resolved once on first use.
  SharedPreferences? prefs;

  /// Research/16 M5: five rows, so the band never pushes the team out of a
  /// five-row list.
  static const max = 5;

  static const keyPrefix = 'mention_recents:';

  static String keyFor(String accountId, String org, String project) =>
      '$keyPrefix$accountId:$org:$project';

  /// The same identity key the form's recent assignees and the mention
  /// picker's dedup use: the GUID when there is one, else the address, else
  /// the name, always case-folded.
  static String identityKey(IdentityRef person) =>
      (person.id ?? person.uniqueName ?? person.displayName).toLowerCase();

  Future<SharedPreferences?> _preferences() async {
    final have = prefs;
    if (have != null) return have;
    try {
      return prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('MentionRecents: preferences unavailable ($e)');
      return null;
    }
  }

  /// Newest first. A row that cannot be decoded is skipped, not fatal.
  Future<List<IdentityRef>> list(String org, String project) async {
    final stored =
        (await _preferences())?.getStringList(
          keyFor(accountId, org, project),
        ) ??
        const <String>[];
    return [for (final row in stored) ?_decode(row)];
  }

  /// Puts [person] at the front, dropping an earlier copy of the same person
  /// ([identityKey]) and anything past [max]. Returns the new list.
  Future<List<IdentityRef>> add(
    String org,
    String project,
    IdentityRef person,
  ) async {
    if (person.displayName.trim().isEmpty && person.id == null) {
      return list(org, project);
    }
    final prefs = await _preferences();
    if (prefs == null) return const [];
    final key = keyFor(accountId, org, project);
    final needle = identityKey(person);
    final kept = <IdentityRef>[
      person,
      for (final row in prefs.getStringList(key) ?? const <String>[])
        if (_decode(row) case final other?)
          if (identityKey(other) != needle) other,
    ].take(max).toList();
    await prefs.setStringList(key, [
      for (final p in kept) jsonEncode(p.toJson()),
    ]);
    return kept;
  }

  Future<void> clear(String org, String project) async =>
      (await _preferences())?.remove(keyFor(accountId, org, project));

  /// Every project's recents for one account, on sign-out.
  static Future<void> clearAccount(
    String accountId, {
    SharedPreferences? prefs,
  }) async {
    SharedPreferences? store = prefs;
    if (store == null) {
      try {
        store = await SharedPreferences.getInstance();
      } catch (e) {
        debugPrint('MentionRecents: preferences unavailable ($e)');
        return;
      }
    }
    final mine = '$keyPrefix$accountId:';
    for (final key in store.getKeys().toList()) {
      if (key.startsWith(mine)) await store.remove(key);
    }
  }

  static IdentityRef? _decode(String row) {
    try {
      final json = jsonDecode(row);
      if (json is! Map) return null;
      return IdentityRef.fromJson(json.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }
}
