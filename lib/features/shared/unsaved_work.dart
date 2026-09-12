import 'package:flutter/material.dart';

/// One open page that would lose something if it were thrown away, and the
/// question it asks before that happens.
class UnsavedWorkGuard {
  UnsavedWorkGuard({required this.isDirty, required this.confirmLeave});

  /// True while the page holds changes the user has not saved.
  final bool Function() isDirty;

  /// The page's own discard confirmation; true when the user agreed to
  /// leave.
  final Future<bool> Function() confirmLeave;
}

/// The open forms that hold unsaved changes.
///
/// Navigation inside a page's own navigator goes through `PopScope`, which
/// the form already uses. A tab re-tap does not: the shell rebuilds the
/// branch with `go`, which drops the branch's stack without ever asking
/// (found in the phase 2 review). Pages that can lose work register here so
/// the shell can ask first.
abstract final class UnsavedWork {
  static final List<UnsavedWorkGuard> _guards = [];

  static void register(UnsavedWorkGuard guard) => _guards.add(guard);

  static void unregister(UnsavedWorkGuard guard) => _guards.remove(guard);

  static bool get hasUnsaved => _guards.any((g) => g.isDirty());

  /// True when nothing is dirty, or when the user confirmed the discard of
  /// everything that is. Asks each dirty page in turn with its own dialog.
  static Future<bool> confirmLeave() async {
    for (final guard in [..._guards]) {
      if (!guard.isDirty()) continue;
      if (!await guard.confirmLeave()) return false;
    }
    return true;
  }

  @visibleForTesting
  static void clear() => _guards.clear();
}
