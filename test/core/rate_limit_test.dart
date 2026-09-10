import 'package:boardhop/core/http/rate_limit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses throttling headers', () {
    final info = RateLimitInfo.fromHeaders(
      statusCode: 200,
      path: '/x',
      headers: {
        'x-ratelimit-resource': ['wit'],
        'x-ratelimit-delay': ['1.5'],
        'x-ratelimit-limit': ['200'],
        'x-ratelimit-remaining': ['12'],
        'x-ratelimit-reset': ['1700000000'],
        'retry-after': ['30'],
      },
    );
    expect(info.resource, 'wit');
    expect(info.delaySeconds, 1.5);
    expect(info.limit, 200);
    expect(info.remaining, 12);
    expect(info.reset, DateTime.utc(2023, 11, 14, 22, 13, 20));
    expect(info.retryAfter, const Duration(seconds: 30));
    expect(info.isThrottled, isTrue);
  });

  test('tracker ignores responses without signals', () {
    final tracker = RateLimitTracker();
    tracker.record(
      RateLimitInfo.fromHeaders(statusCode: 200, path: '/x', headers: const {}),
    );
    expect(tracker.latest, isNull);
    expect(tracker.log, isEmpty);
  });

  test('tracker keeps a bounded log', () {
    final tracker = RateLimitTracker(maxLog: 2);
    for (var i = 0; i < 3; i++) {
      tracker.record(
        RateLimitInfo.fromHeaders(
          statusCode: 200,
          path: '/$i',
          headers: {
            'x-ratelimit-cost': ['1'],
          },
        ),
      );
    }
    expect(tracker.log.length, 2);
    expect(tracker.log.first.path, '/1');
    expect(tracker.totalCost, 2);
  });
}
