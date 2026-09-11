import 'package:flutter/material.dart';

/// The brand splash (assets/brand/splash.png) scaled to cover the screen, so
/// the logo in its center stays centered on phones and tablets in either
/// orientation. Flutter's first frame while sign-in state is unknown; the
/// native launch screens show the same artwork before the engine is up.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  /// Edge color of the artwork; matches `splash_background` on Android and
  /// the storyboard background on iOS.
  static const background = Color(0xFF1D2739);

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: background,
      child: SizedBox.expand(
        child: Image(
          image: AssetImage('assets/brand/splash.png'),
          fit: BoxFit.cover,
          alignment: Alignment.center,
          gaplessPlayback: true,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
