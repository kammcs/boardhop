import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The project the app was last looking at, on this device (research/21 L8).
///
/// One per device rather than one per account: "whatever you had open last"
/// is device state, so the account id travels with it and the resolver only
/// uses the memory while that account is still signed in.
@immutable
class LastProject {
  const LastProject({
    required this.accountId,
    required this.org,
    required this.project,
  });

  final String accountId;
  final String org;
  final String project;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LastProject &&
          other.accountId == accountId &&
          other.org == org &&
          other.project == project;

  @override
  int get hashCode => Object.hash(accountId, org, project);

  @override
  String toString() => 'LastProject($accountId, $org, $project)';
}

/// [LastProject] over `shared_preferences`, in the style of `SearchRecents`
/// and `MentionRecents`: the store is device state, not cached API data, so
/// it lives beside the theme choice rather than in drift.
///
/// Never throws: preferences can be unavailable (a test, a fresh install),
/// and a missing memory only costs the launch its shortcut.
class LastProjectStore {
  LastProjectStore({this.prefs});

  /// Injected in tests (`SharedPreferences.setMockInitialValues` gives one);
  /// otherwise resolved once on first use.
  SharedPreferences? prefs;

  static const accountKey = 'launch.last.account';
  static const orgKey = 'launch.last.org';
  static const projectKey = 'launch.last.project';

  Future<SharedPreferences?> _preferences() async {
    final have = prefs;
    if (have != null) return have;
    try {
      return prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('LastProjectStore: preferences unavailable ($e)');
      return null;
    }
  }

  /// The remembered project, or null when nothing is stored or one of the
  /// three keys is missing (a half-written memory is no memory).
  Future<LastProject?> read() async {
    final prefs = await _preferences();
    if (prefs == null) return null;
    final accountId = prefs.getString(accountKey);
    final org = prefs.getString(orgKey);
    final project = prefs.getString(projectKey);
    if (accountId == null || accountId.isEmpty) return null;
    if (org == null || org.isEmpty) return null;
    if (project == null || project.isEmpty) return null;
    return LastProject(accountId: accountId, org: org, project: project);
  }

  Future<void> write(LastProject last) async {
    final prefs = await _preferences();
    if (prefs == null) return;
    await prefs.setString(accountKey, last.accountId);
    await prefs.setString(orgKey, last.org);
    await prefs.setString(projectKey, last.project);
  }

  Future<void> clear() async {
    final prefs = await _preferences();
    if (prefs == null) return;
    await prefs.remove(accountKey);
    await prefs.remove(orgKey);
    await prefs.remove(projectKey);
  }
}
