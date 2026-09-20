import 'package:flutter/widgets.dart';

/// Non-color design tokens. Screens use these instead of literal numbers so
/// the rhythm of the app can be tuned in one place.
abstract final class Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal page gutter on phones.
  static const double gutter = lg;

  static const EdgeInsets page = EdgeInsets.all(lg);
  static const EdgeInsets pageHorizontal = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets card = EdgeInsets.all(md);
}

abstract final class Radii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;

  /// Floating glass containers (the iOS tablet rail).
  static const double xl = 28;
  static const double pill = 999;

  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
  static const BorderRadius chip = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(lg),
  );
}

abstract final class Durations {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 360);
}

/// How motion eases, beside how long it takes.
abstract final class Motion {
  /// The curve a piece of chrome moves on when the window itself changes
  /// shape — the glass rail sliding from the bottom of the screen to the
  /// edge iOS asks for as an iPhone Duo is folded or turned (research/23
  /// D7). Symmetric, so the same move back reads as a reversal.
  static const Curve standard = Curves.easeInOutCubic;
}

/// Minimum touch target on both platforms.
const double kMinTapTarget = 48;

/// Content column width cap on wide screens (tablets, desktop, landscape).
const double kMaxContentWidth = 840;
