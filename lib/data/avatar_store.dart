import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/http/ado_client.dart';
import '../core/http/ado_exceptions.dart';
import '../core/http/ado_host.dart';
import 'models/work_item.dart';

/// Avatars need the bearer token, and the image links Azure DevOps puts on
/// identities answer 401 to it (see [IdentityRef.avatarSource]), so
/// `Image.network` cannot fetch them. This store reads the Graph
/// `Subjects/{descriptor}/avatars` JSON (base64 PNG) through [AdoClient],
/// keeps bytes in memory for the session and on disk for [ttl], and hands
/// widgets a synchronous hit when it has one.
class AvatarStore {
  AvatarStore(
    this._client, {
    Directory? directory,
    this.ttl = const Duration(days: 7),
  }) : _directory = directory; // ignore: prefer_initializing_formals

  final AdoClient _client;
  final Duration ttl;
  Directory? _directory;
  final Map<String, Uint8List> _memory = {};
  final Map<String, Future<Uint8List?>> _inFlight = {};
  final Set<String> _failed = {};

  /// Cache file name: the source key with unsafe characters replaced, so
  /// the same person at the same size maps to one file across sessions.
  @visibleForTesting
  static String fileNameFor(AvatarSource source) {
    final safe = source.key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '${safe.length > 150 ? safe.substring(safe.length - 150) : safe}.png';
  }

  /// Bytes already in memory, else null (no I/O).
  Uint8List? cached(AvatarSource source) => _memory[source.key];

  /// Loads from memory, then disk, then the service. Null when the fetch
  /// failed; failures are remembered for the session so lists do not
  /// hammer the endpoint.
  Future<Uint8List?> load(AvatarSource source) {
    final key = source.key;
    final hit = _memory[key];
    if (hit != null) return Future.value(hit);
    if (_failed.contains(key)) return Future.value(null);
    return _inFlight.putIfAbsent(key, () async {
      try {
        final fromDisk = await _readDisk(source);
        if (fromDisk != null) {
          _memory[key] = fromDisk;
          return fromDisk;
        }
        final bytes = await _fetch(source);
        if (bytes == null || bytes.isEmpty) {
          _failed.add(key);
          return null;
        }
        _memory[key] = bytes;
        unawaited(_writeDisk(source, bytes));
        return bytes;
      } on AdoException catch (e) {
        debugPrint('avatar $key: ${e.message}');
        _failed.add(key);
        return null;
      } catch (e) {
        debugPrint('avatar $key: $e');
        _failed.add(key);
        return null;
      } finally {
        _inFlight.remove(key);
      }
    });
  }

  Future<Uint8List?> _fetch(AvatarSource source) async {
    if (source.isGraph) {
      final json = await _client.getJson(
        host: AdoHost.vssps,
        org: source.org,
        path: '_apis/graph/Subjects/${source.descriptor}/avatars',
        apiVersion: '7.1-preview.1',
        query: {'size': source.size.name},
      );
      final value = json['value'];
      return value is String && value.isNotEmpty ? base64Decode(value) : null;
    }
    final url = source.url;
    return url == null ? null : _client.getBytes(Uri.parse(url));
  }

  Future<Directory?> _dir() async {
    final existing = _directory;
    if (existing != null) return existing;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(p.join(base.path, 'avatars'));
      await dir.create(recursive: true);
      return _directory = dir;
    } catch (e) {
      debugPrint('avatar cache directory unavailable: $e');
      return null;
    }
  }

  Future<Uint8List?> _readDisk(AvatarSource source) async {
    final dir = await _dir();
    if (dir == null) return null;
    final file = File(p.join(dir.path, fileNameFor(source)));
    try {
      if (!await file.exists()) return null;
      final stat = await file.stat();
      if (DateTime.now().difference(stat.modified) > ttl) return null;
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDisk(AvatarSource source, Uint8List bytes) async {
    final dir = await _dir();
    if (dir == null) return;
    try {
      await File(p.join(dir.path, fileNameFor(source)))
          .writeAsBytes(bytes, flush: true);
    } catch (e) {
      debugPrint('avatar cache write failed: $e');
    }
  }

  /// Drops everything in memory and on disk (sign-out).
  Future<void> clear() async {
    _memory.clear();
    _failed.clear();
    final dir = await _dir();
    if (dir == null) return;
    try {
      await dir.delete(recursive: true);
      _directory = null;
    } catch (_) {}
  }
}
