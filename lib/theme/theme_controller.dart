import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user's light/dark preference. Defaults to following the system
/// setting; Settings lets the user pin light or dark. Loaded in `main`
/// before the first frame so there is no flash of the wrong mode.
class ThemeController extends ChangeNotifier {
  ThemeController._(this._prefs, this._mode);

  static const _key = 'theme_mode';

  /// In-memory only; for tests and for a bootstrap that must not touch disk.
  @visibleForTesting
  ThemeController.inMemory([ThemeMode mode = ThemeMode.system])
    : _prefs = null,
      _mode = mode;

  static Future<ThemeController> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('ThemeController: preferences unavailable ($e)');
    }
    final stored = prefs?.getString(_key);
    final mode = ThemeMode.values.firstWhere(
      (m) => m.name == stored,
      orElse: () => ThemeMode.system,
    );
    return ThemeController._(prefs, mode);
  }

  final SharedPreferences? _prefs;
  ThemeMode _mode;

  ThemeMode get mode => _mode;

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _prefs?.setString(_key, mode.name);
  }
}

/// Makes the [ThemeController] available below `MaterialApp` and rebuilds
/// dependents when the mode changes. Read it with `ThemeScope.of(context)`.
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'No ThemeScope above this widget');
    return scope!.notifier!;
  }
}
