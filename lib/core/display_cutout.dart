import 'package:flutter/services.dart';

/// Which side of the screen carries the display cutout (the Dynamic
/// Island or notch) while a phone is in landscape.
enum CutoutSide { left, right, none, unknown }

/// Asks iOS where the display cutout is. Flutter's safe-area insets are
/// the same on both sides in landscape (59 pt on a Dynamic Island phone,
/// for the island and the corners alike), so nothing on the Dart side can
/// tell which side actually holds the island; the interface orientation
/// from the Runner's AppDelegate can (`com.kammcs.boardhop/display`).
/// Elsewhere (Android, tests) the answer is [CutoutSide.unknown].
class DisplayCutout {
  DisplayCutout._();

  static const _channel = MethodChannel('com.kammcs.boardhop/display');

  static Future<CutoutSide> side() async {
    final String? orientation;
    try {
      orientation = await _channel.invokeMethod<String>('interfaceOrientation');
    } on MissingPluginException {
      return CutoutSide.unknown;
    } on PlatformException {
      return CutoutSide.unknown;
    }
    return switch (orientation) {
      // UIInterfaceOrientation is named after the side the home button
      // (indicator) is on; the island is at the opposite end.
      'landscapeLeft' => CutoutSide.right,
      'landscapeRight' => CutoutSide.left,
      'portrait' || 'portraitUpsideDown' => CutoutSide.none,
      _ => CutoutSide.unknown,
    };
  }
}
