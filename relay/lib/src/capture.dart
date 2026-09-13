import 'dart:convert';
import 'dart:io';

/// Stores raw service-hook posts as one JSON file each, for spike 3
/// (research/06 §Spikes item 3: what a "Minimal" payload actually contains).
///
/// This is a scratch recorder, not relay storage: it is capped in both
/// directions so a runaway hook cannot fill the disk.
class CaptureStore {
  CaptureStore(this.root, {this.maxBodyBytes = 1024 * 1024, this.maxFilesPerName = 200});

  /// `RELAY_CAPTURE_DIR`, one subdirectory per capture name.
  final Directory root;

  /// A body longer than this is truncated; the file records that it was.
  final int maxBodyBytes;

  /// Oldest files are dropped beyond this many per capture name.
  final int maxFilesPerName;

  static final _safeName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$');

  /// Capture names come from the URL, so they must not walk the filesystem.
  static bool isValidName(String name) => _safeName.hasMatch(name) && !name.contains('..');

  /// The headers worth keeping: the content type, everything Azure DevOps
  /// stamps on a hook post (`X-VSS-*`), and the user agent.
  static Map<String, String> headerSubset(Map<String, String> headers) {
    final kept = <String, String>{};
    headers.forEach((key, value) {
      final k = key.toLowerCase();
      if (k == 'content-type' || k == 'user-agent' || k.startsWith('x-vss-') || k.startsWith('x-request-')) {
        kept[k] = value;
      }
    });
    return kept;
  }

  /// Writes one capture file and returns it.
  File write(String name, String body, Map<String, String> headers) {
    final dir = Directory('${root.path}${Platform.pathSeparator}$name')..createSync(recursive: true);
    final truncated = body.length > maxBodyBytes;
    final kept = truncated ? body.substring(0, maxBodyBytes) : body;

    final eventType = _eventTypeOf(body);
    final now = DateTime.now().toUtc();
    final stamp = now.toIso8601String().replaceAll(':', '-');
    var file = File('${dir.path}${Platform.pathSeparator}$stamp-$eventType.json');
    for (var n = 1; file.existsSync(); n++) {
      file = File('${dir.path}${Platform.pathSeparator}$stamp-$eventType-$n.json');
    }

    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'capturedAt': now.toIso8601String(),
        'eventType': eventType,
        'headers': headerSubset(headers),
        'bodyBytes': body.length,
        'truncated': truncated,
        'body': _tryDecode(kept) ?? kept,
      }),
    );

    _trim(dir);
    return file;
  }

  /// Newest first, with the size and event type of each file.
  List<Map<String, Object?>> list(String name) {
    final dir = Directory('${root.path}${Platform.pathSeparator}$name');
    if (!dir.existsSync()) return const [];
    final files = _files(dir)..sort((a, b) => b.path.compareTo(a.path));
    return [
      for (final f in files)
        {
          'file': f.uri.pathSegments.last,
          'bytes': f.lengthSync(),
          'eventType': _eventTypeOfFile(f),
          'modified': f.lastModifiedSync().toUtc().toIso8601String(),
        },
    ];
  }

  List<File> _files(Directory dir) => dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();

  void _trim(Directory dir) {
    final files = _files(dir);
    if (files.length <= maxFilesPerName) return;
    // Names start with a UTC timestamp, so lexical order is chronological.
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final f in files.take(files.length - maxFilesPerName)) {
      try {
        f.deleteSync();
      } catch (_) {
        // A concurrent capture may have removed it already.
      }
    }
  }

  static String _eventTypeOf(String body) {
    final decoded = _tryDecode(body);
    if (decoded is Map && decoded['eventType'] is String) {
      return _slug(decoded['eventType'] as String);
    }
    return 'unknown';
  }

  static String _eventTypeOfFile(File f) {
    try {
      final decoded = jsonDecode(f.readAsStringSync());
      if (decoded is Map && decoded['eventType'] is String) return decoded['eventType'] as String;
    } catch (_) {
      // fall through
    }
    return 'unknown';
  }

  static Object? _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static String _slug(String s) {
    final slug = s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return slug.isEmpty ? 'unknown' : (slug.length > 80 ? slug.substring(0, 80) : slug);
  }
}
