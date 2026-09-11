import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user's light/dark preference. Defaults to following the system
/// setting; Settings lets the user pin light or dark. Loaded in `main`
/// before the first frame so there is no flash of the wrong mode.
/// Which side of the screen the tablet rail floats on in landscape.
enum RailSide { left, right }

class ThemeController extends ChangeNotifier {
  ThemeController._(this._prefs, this._mode, this._railSide);

  static const _key = 'theme_mode';
  static const _railKey = 'tablet_rail_side';

  /// In-memory only; for tests and for a bootstrap that must not touch disk.
  @visibleForTesting
  ThemeController.inMemory([
    ThemeMode mode = ThemeMode.system,
    RailSide railSide = RailSide.right,
  ]) : _prefs = null,
       _mode = mode,
       _railSide = railSide;

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
    final storedSide = prefs?.getString(_railKey);
    final side = RailSide.values.firstWhere(
      (r) => r.name == storedSide,
      orElse: () => RailSide.right,
    );
    return ThemeController._(prefs, mode, side);
  }

  final SharedPreferences? _prefs;
  ThemeMode _mode;
  RailSide _railSide;

  ThemeMode get mode => _mode;

  /// Side of the floating rail on Apple tablets in landscape (Settings >
  /// Appearance). Right by default, Kelly's preference.
  RailSide get railSide => _railSide;

  Future<void> setRailSide(RailSide side) async {
    if (side == _railSide) return;
    _railSide = side;
    notifyListeners();
    await _prefs?.setString(_railKey, side.name);
  }

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
