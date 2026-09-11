import 'dart:ui' show Color;

/// The Azure DevOps web draws organizations and projects as colored rounded
/// squares with initials when no picture is set. Two algorithms are in play
/// (spike s16):
///
/// * Project tiles are rendered by the service (`GraphProfile/MemberAvatars/
///   {defaultTeamId}?overrideDisplayName={project}`). The color is the .NET
///   Framework string hash of the name, absolute, modulo a 12-color palette;
///   the initials are the first letters of the first and last words after
///   digits and punctuation are stripped. [serviceColor] and
///   [serviceInitials] reproduce that so the tile can be drawn before the
///   image arrives, offline, and identically when the project has no picture.
/// * Organizations have no service-side image. The web's UI kit ("Coin")
///   picks from a 19-color palette with its own hash and keeps digits in the
///   initials: [coinColor], [coinInitials].
abstract final class AdoTiles {
  /// Generated member-avatar backgrounds, indexed by the service hash.
  static const servicePalette = <Color>[
    Color(0xFFDA3A00),
    Color(0xFFAA0000),
    Color(0xFF5D005D),
    Color(0xFF32105C),
    Color(0xFF001E51),
    Color(0xFF004B51),
    Color(0xFF004C1A),
    Color(0xFFB600A0),
    Color(0xFF5C2893),
    Color(0xFF0075DA),
    Color(0xFF008272),
    Color(0xFF027D00),
  ];

  /// azure-devops-ui `Coin` initials backgrounds.
  static const coinPalette = <Color>[
    Color(0xFF750B1C),
    Color(0xFFA4262C),
    Color(0xFFD13438),
    Color(0xFFCA5010),
    Color(0xFF986F0B),
    Color(0xFF498205),
    Color(0xFF0B6A0B),
    Color(0xFF038387),
    Color(0xFF005B70),
    Color(0xFF0078D4),
    Color(0xFF4F6BED),
    Color(0xFF5C2E91),
    Color(0xFF8764B8),
    Color(0xFF881798),
    Color(0xFFC239B3),
    Color(0xFFE3008C),
    Color(0xFF8E562E),
    Color(0xFF7A7574),
    Color(0xFF69797E),
  ];

  static const _coinDefault = Color(0xFF4F6BED);
  static const _mask = 0xFFFFFFFF;

  /// .NET Framework `string.GetHashCode()` (the deterministic 32-bit one),
  /// over UTF-16 code units in pairs.
  static int netStringHash(String s) {
    var h1 = 5381;
    var h2 = 5381;
    final units = s.codeUnits;
    for (var i = 0; i < units.length; i += 2) {
      h1 = (((h1 << 5) + h1) ^ units[i]) & _mask;
      if (i + 1 < units.length) {
        h2 = (((h2 << 5) + h2) ^ units[i + 1]) & _mask;
      }
    }
    final sum = (h1 + h2 * 1566083941) & _mask;
    return sum >= 0x80000000 ? sum - 0x100000000 : sum;
  }

  /// Background the service generates for [name].
  static Color serviceColor(String name) =>
      servicePalette[netStringHash(name).abs() % servicePalette.length];

  static final _leadingParen = RegExp(r'^\s*\([^)]*\)');
  static final _nonLetter = RegExp(r'[^\p{L}\s]', unicode: true);
  static final _whitespace = RegExp(r'\s+');

  /// Initials the service draws for [name]: a parenthesized lead-in is
  /// dropped and anything from a later "(" on is ignored; digits and
  /// punctuation vanish; then the first letter of the first and of the last
  /// word, upper-cased ("CloudCover 2.0" → "C", "DevOps Mobile App" → "DA").
  static String serviceInitials(String name) {
    var s = name.replaceFirst(_leadingParen, '');
    final paren = s.indexOf('(');
    if (paren >= 0) s = s.substring(0, paren);
    final words = s
        .replaceAll(_nonLetter, '')
        .trim()
        .split(_whitespace)
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '';
    final first = _firstRune(words.first);
    final last = words.length > 1 ? _firstRune(words.last) : '';
    return (first + last).toUpperCase();
  }

  static String _firstRune(String word) =>
      String.fromCharCode(word.runes.first);

  /// azure-devops-ui `getInitialsColorFromName`.
  static Color coinColor(String name) {
    if (name.isEmpty) return _coinDefault;
    var n = 0;
    final units = name.codeUnits;
    for (var t = units.length - 1; t >= 0; t--) {
      final r = units[t];
      final o = t % 8;
      n = (n ^ ((r << o) + (r >> (8 - o)))) & _mask;
    }
    return coinPalette[n % coinPalette.length];
  }

  static final _coinLetter = RegExp(
    '[0-9]|[A-Z]|[Ѐ-Я]|[a-z]|[ά-ώ]|[ǅ]|[ῼ]|[ʰ-ˁ]|[ᴬ-ᵡ]|[א-ת]|[ء-غ]|[一-鿃]|'
    '[À-ÿ]|[Ā-ſ]|[ƀ-ɏ]',
  );

  /// azure-devops-ui `getInitialsFromName`: first character of the first
  /// and of the last word that starts with a letter or digit.
  static String coinInitials(String name) {
    var first = '';
    var last = '';
    for (final word in name.split(' ')) {
      if (word.isEmpty) continue;
      final c = word[0];
      if (!_coinLetter.hasMatch(c)) continue;
      if (first.isEmpty) {
        first = c;
      } else {
        last = c;
      }
    }
    return (first + last).toUpperCase();
  }
}
