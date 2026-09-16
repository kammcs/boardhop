import 'db/app_database.dart';
import 'db/json_cache.dart';
import 'repositories/pr_diff_source.dart';

/// What was known about a file when it was marked as viewed: the iteration
/// on screen and, when the changes carried one, the blob id of the version
/// that was read.
typedef ViewedMark = ({int iterationId, String? objectId});

/// Local "I have read this file" marks for a pull request's Files tab (R8).
///
/// Azure DevOps has **no server-side viewed state** — neither the settings
/// entries nor the web's data provider carry one (spike s64) — so the marks
/// live on the device. They are one JSON document per pull request in the
/// same account-namespaced [JsonCache] every other cached read uses, rather
/// than a drift table of their own: the shape is a small map, it is always
/// read and written whole, it survives a restart because `cache_entries`
/// does, and it needs no schema migration.
///
/// A mark is only as good as the version it was made against, so [prune]
/// drops the ones whose file has moved since.
class ViewedFilesStore {
  ViewedFilesStore(AppDatabase? db, {String? userId})
    : _cache = JsonCache(db, namespace: userId);

  final JsonCache _cache;

  /// Decoded documents by cache key, so the Files tab and the diff app bar
  /// do not decode the same blob twice per frame.
  final Map<String, Map<String, ViewedMark>> _memo = {};

  static String key(String org, int pullRequestId) =>
      'pr:viewed:$org:$pullRequestId';

  /// Every mark of this pull request, keyed by file path.
  Future<Map<String, ViewedMark>> marks(String org, int pullRequestId) async {
    final k = key(org, pullRequestId);
    final memo = _memo[k];
    if (memo != null) return memo;
    final hit = await _cache.get(k);
    final decoded = hit?.json;
    final out = <String, ViewedMark>{};
    if (decoded is Map) {
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        out['${entry.key}'] = (
          iterationId: (value['iterationId'] as num?)?.toInt() ?? 0,
          objectId: value['objectId'] as String?,
        );
      }
    }
    return _memo[k] = out;
  }

  Future<bool> isViewed(String org, int pullRequestId, String path) async =>
      (await marks(org, pullRequestId)).containsKey(path);

  Future<void> markViewed(
    String org,
    int pullRequestId,
    String path, {
    required int iterationId,
    String? objectId,
  }) async {
    final current = await marks(org, pullRequestId);
    current[path] = (iterationId: iterationId, objectId: objectId);
    await _write(org, pullRequestId, current);
  }

  /// Unmarks one file, or the whole pull request when [path] is null.
  Future<void> clear(String org, int pullRequestId, {String? path}) async {
    final k = key(org, pullRequestId);
    if (path == null) {
      _memo.remove(k);
      await _cache.remove(k);
      return;
    }
    final current = await marks(org, pullRequestId);
    if (current.remove(path) == null) return;
    await _write(org, pullRequestId, current);
  }

  /// Drops the marks whose file has moved since it was read, and returns
  /// how many went.
  ///
  /// The blob id decides it when both sides know one; a change list without
  /// `objectId` falls back to the iteration the file was last touched in,
  /// which is the coarser half of R8's rule ("a later iteration that
  /// touches the file clears the mark"). Files absent from [changes] keep
  /// their mark: they are unchanged in this comparison, not re-read.
  Future<int> prune(
    String org,
    int pullRequestId,
    Iterable<PrFileChange> changes, {
    required int iterationId,
  }) async {
    final current = await marks(org, pullRequestId);
    if (current.isEmpty) return 0;
    var dropped = 0;
    for (final change in changes) {
      final mark = current[change.path];
      if (mark == null) continue;
      final moved = mark.objectId != null && change.objectId != null
          ? mark.objectId != change.objectId
          : mark.iterationId != iterationId;
      if (!moved) continue;
      current.remove(change.path);
      dropped++;
    }
    if (dropped > 0) await _write(org, pullRequestId, current);
    return dropped;
  }

  Future<void> _write(
    String org,
    int pullRequestId,
    Map<String, ViewedMark> marks,
  ) async {
    final k = key(org, pullRequestId);
    _memo[k] = marks;
    if (marks.isEmpty) {
      await _cache.remove(k);
      return;
    }
    await _cache.put(k, {
      for (final e in marks.entries)
        e.key: {
          'iterationId': e.value.iterationId,
          if (e.value.objectId != null) 'objectId': e.value.objectId,
        },
    });
  }
}
