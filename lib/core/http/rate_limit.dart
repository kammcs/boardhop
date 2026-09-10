import 'package:flutter/foundation.dart';

/// Azure DevOps global rate limit signals, measured in TSTUs.
///
/// Headers appear only when a call is delayed or over the limit, except
/// `X-RateLimit-Cost`, which our spikes saw on ordinary 200s
/// (research/05-pitfalls-and-risks.md, spike s09).
@immutable
class RateLimitInfo {
  const RateLimitInfo({
    required this.observedAt,
    required this.statusCode,
    required this.path,
    this.resource,
    this.delaySeconds,
    this.limit,
    this.remaining,
    this.reset,
    this.retryAfter,
    this.cost,
  });

  factory RateLimitInfo.fromHeaders({
    required Map<String, List<String>> headers,
    required int statusCode,
    required String path,
  }) {
    String? first(String name) {
      final values = headers[name.toLowerCase()] ?? headers[name];
      return values == null || values.isEmpty ? null : values.first;
    }

    double? number(String name) {
      final raw = first(name);
      return raw == null ? null : double.tryParse(raw);
    }

    final resetEpoch = number('X-RateLimit-Reset');
    final retryAfterSeconds = number('Retry-After');
    return RateLimitInfo(
      observedAt: DateTime.now(),
      statusCode: statusCode,
      path: path,
      resource: first('X-RateLimit-Resource'),
      delaySeconds: number('X-RateLimit-Delay'),
      limit: number('X-RateLimit-Limit'),
      remaining: number('X-RateLimit-Remaining'),
      reset: resetEpoch == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (resetEpoch * 1000).round(),
              isUtc: true,
            ),
      retryAfter: retryAfterSeconds == null
          ? null
          : Duration(milliseconds: (retryAfterSeconds * 1000).round()),
      cost: number('X-RateLimit-Cost'),
    );
  }

  final DateTime observedAt;
  final int statusCode;
  final String path;
  final String? resource;
  final double? delaySeconds;
  final double? limit;
  final double? remaining;
  final DateTime? reset;
  final Duration? retryAfter;
  final double? cost;

  /// True when the service has started delaying or rejecting our calls.
  bool get isThrottled =>
      (delaySeconds ?? 0) > 0 || retryAfter != null || statusCode == 429;

  bool get hasAnySignal =>
      resource != null ||
      delaySeconds != null ||
      limit != null ||
      remaining != null ||
      reset != null ||
      retryAfter != null ||
      cost != null;

  @override
  String toString() =>
      'RateLimitInfo($statusCode $path resource=$resource delay=$delaySeconds '
      'limit=$limit remaining=$remaining reset=$reset retryAfter=$retryAfter '
      'cost=$cost)';
}

/// Keeps the most recent signal and a bounded log of costed calls so the UI
/// (and the diagnostics page) can show consumption without a network call.
class RateLimitTracker extends ChangeNotifier {
  RateLimitTracker({this.maxLog = 200});

  final int maxLog;
  final List<RateLimitInfo> _log = <RateLimitInfo>[];
  RateLimitInfo? _latest;

  RateLimitInfo? get latest => _latest;
  List<RateLimitInfo> get log => List.unmodifiable(_log);

  double get totalCost =>
      _log.fold<double>(0, (sum, info) => sum + (info.cost ?? 0));

  void record(RateLimitInfo info) {
    if (!info.hasAnySignal && !info.isThrottled) return;
    _latest = info;
    _log.add(info);
    if (_log.length > maxLog) _log.removeAt(0);
    notifyListeners();
  }

  void clear() {
    _log.clear();
    _latest = null;
    notifyListeners();
  }
}
