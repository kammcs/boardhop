import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/models/work_item.dart';

/// Small per-user memories of the create form, kept in `shared_preferences`
/// like the theme choice: the type last created in a project and the people
/// last assigned there.
///
/// Never throws: preferences can be unavailable (a test, a fresh install),
/// and neither memory is worth failing a form over.
abstract final class FormPrefs {
  static const _typeKey = 'form_last_type';
  static const _assigneeKey = 'form_recent_assignees';
  static const maxRecentAssignees = 5;

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('FormPrefs: preferences unavailable ($e)');
      return null;
    }
  }

  static String _scope(String org, String project) => '$org/$project';

  static Future<String?> lastType(String org, String project) async =>
      (await _prefs())?.getString('$_typeKey:${_scope(org, project)}');

  static Future<void> setLastType(
    String org,
    String project,
    String typeName,
  ) async {
    await (await _prefs())?.setString(
      '$_typeKey:${_scope(org, project)}',
      typeName,
    );
  }

  /// Most recently assigned first.
  static Future<List<IdentityRef>> recentAssignees(
    String org,
    String project,
  ) async {
    final raw = (await _prefs())?.getStringList(
      '$_assigneeKey:${_scope(org, project)}',
    );
    if (raw == null) return const [];
    final out = <IdentityRef>[];
    for (final entry in raw) {
      try {
        final json = (jsonDecode(entry) as Map).cast<String, dynamic>();
        out.add(IdentityRef.fromJson(json));
      } catch (_) {
        // A stored row from an older shape: skip it.
      }
    }
    return out;
  }

  static Future<void> rememberAssignee(
    String org,
    String project,
    IdentityRef person,
  ) async {
    final prefs = await _prefs();
    if (prefs == null) return;
    final key = '$_assigneeKey:${_scope(org, project)}';
    final existing = await recentAssignees(org, project);
    String identity(IdentityRef p) =>
        (p.id ?? p.uniqueName ?? p.displayName).toLowerCase();
    final kept = [
      person,
      for (final p in existing)
        if (identity(p) != identity(person)) p,
    ].take(maxRecentAssignees);
    await prefs.setStringList(key, [
      for (final p in kept)
        jsonEncode({
          'displayName': p.displayName,
          if (p.uniqueName != null) 'uniqueName': p.uniqueName,
          if (p.id != null) 'id': p.id,
          if (p.imageUrl != null) 'imageUrl': p.imageUrl,
          if (p.descriptor != null) 'descriptor': p.descriptor,
        }),
    ]);
  }
}
