import 'dart:ui' show Color;

/// "just now", "5m", "3h", "2d", "Sep 3", "Sep 3, 2025".
String relativeTime(DateTime? time, {DateTime? now}) {
  if (time == null) return '';
  final ref = now ?? DateTime.now();
  final d = ref.difference(time.toLocal());
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = time.toLocal();
  final md = '${months[local.month - 1]} ${local.day}';
  return local.year == ref.year ? md : '$md, ${local.year}';
}

/// "Kelly Kamm" → "KK", "kelly" → "K", "" → "?".
String initials(String name) {
  final parts = name
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

/// Azure DevOps colors come as `CC293D`, `#CC293D` or `FFCC293D`.
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

/// Last segment of an area or iteration path.
String pathLeaf(String? path) {
  if (path == null || path.isEmpty) return '';
  final i = path.lastIndexOf('\\');
  return i < 0 ? path : path.substring(i + 1);
}
