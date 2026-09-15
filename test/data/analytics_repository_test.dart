import 'dart:convert';
import 'dart:typed_data';

import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/core/http/ado_exceptions.dart';
import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/repositories/analytics_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const account = 'kelly@kammcs.com-home';
const org = 'puremedia';
const project = 'CloudCover 2.0';
const iterationId = 'cc106106-0000-0000-0000-000000000106';
const iterationSk = 'ffffffff-0000-0000-0000-000000000106';

class _FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];
  final Map<String, Object> answers = <String, Object>{};
  int status = 200;

  RequestOptions get last => requests.last;
  RequestOptions? firstMatching(String part) =>
      requests.where((r) => r.uri.toString().contains(part)).firstOrNull;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.uri.toString();
    final keys = answers.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final key = keys.firstWhere(path.contains, orElse: () => '');
    return ResponseBody.fromString(
      jsonEncode(answers[key] ?? const <String, dynamic>{'value': []}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Two days x three categories, the shape spike s55 saw on CloudCover 106.
Map<String, dynamic> snapshotRows() => {
  '@odata.context': 'https://analytics.dev.azure.com/$org/_odata/\$metadata',
  'value': [
    _row('2026-08-25T00:00:00Z', 'Completed', 8, 3),
    _row('2026-08-25T00:00:00Z', 'InProgress', 72, 47),
    _row('2026-08-25T00:00:00Z', 'Proposed', 39, 16),
    _row('2026-08-26T00:00:00Z', 'Completed', 11, 5),
    _row('2026-08-26T00:00:00Z', 'InProgress', 76, 49),
    _row('2026-08-26T00:00:00Z', 'Proposed', 26, 4),
    _row('2026-08-26T00:00:00Z', 'Removed', 2, 1),
  ],
};

Map<String, dynamic> _row(String date, String category, int count, num sp) => {
  'DateValue': date,
  'StateCategory': category,
  'Count': count,
  'SP': sp,
};

void main() {
  late _FakeAdapter adapter;
  late AppDatabase db;
  late AnalyticsRepository repository;

  final start = DateTime.utc(2026, 8, 25);
  final end = DateTime.utc(2026, 8, 26);

  setUp(() {
    adapter = _FakeAdapter()..answers['WorkItemSnapshot'] = snapshotRows();
    db = AppDatabase(NativeDatabase.memory());
    repository = AnalyticsRepository(
      AdoClient(
        tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
        dio: Dio()..httpClientAdapter = adapter,
      ),
      db,
      account,
    );
  });

  tearDown(() => db.close());

  test(
    r'calls the project-scoped OData host with the $apply pipeline',
    () async {
      await repository.burndown(
        org,
        project,
        iterationId,
        start: start,
        end: end,
      );

      final uri = adapter.last.uri;
      expect(uri.host, 'analytics.dev.azure.com');
      // The org-level route with no project segment is 403 for everyone.
      expect(
        uri.path,
        '/$org/CloudCover%202.0/_odata/v4.0-preview/WorkItemSnapshot',
      );
      expect(uri.query, contains('IterationSK%20eq%20$iterationId'));
      expect(uri.query, contains('DateValue%20ge%202026-08-25Z'));
      expect(uri.query, contains('DateValue%20le%202026-08-26Z'));
      expect(uri.query, contains('groupby((DateValue,StateCategory)'));
      expect(uri.query, contains(r'aggregate($count%20as%20Count'));
      expect(uri.query, contains('StoryPoints%20with%20sum%20as%20SP'));
      expect(uri.query, contains(r'$orderby=DateValue%20asc'));
      // No api-version: the version is the path segment.
      expect(uri.query, isNot(contains('api-version')));
      expect(adapter.last.headers['Authorization'], 'Bearer tok');
    },
  );

  test('groups the rows into one day each', () async {
    final days = await repository.burndown(
      org,
      project,
      iterationId,
      start: start,
      end: end,
    );

    expect(days.length, 2);
    expect(days.first.date, DateTime.utc(2026, 8, 25));
    expect(days.first.remaining, 111); // 72 InProgress + 39 Proposed
    expect(days.first.done, 8);
    expect(days.first.points, 63); // 47 + 16
    expect(days.first.scope, 119);
    // Removed counts towards neither series.
    expect(days.last.remaining, 102);
    expect(days.last.done, 11);
  });

  test('keeps the days in date order whatever the rows do', () async {
    adapter.answers['WorkItemSnapshot'] = {
      'value': [
        _row('2026-08-26T00:00:00Z', 'Proposed', 1, 1),
        _row('2026-08-25T00:00:00Z', 'Proposed', 2, 2),
      ],
    };

    final days = await repository.burndown(
      org,
      project,
      iterationId,
      start: start,
      end: end,
    );

    expect(days.map((d) => d.date.day), [25, 26]);
  });

  test('an empty answer retries through the Iterations lookup', () async {
    adapter.answers['WorkItemSnapshot'] = {'value': const []};
    adapter.answers['Iterations?'] = {
      'value': [
        {
          'IterationSK': iterationSk,
          'IterationName': 'Iteration 106',
          'StartDate': '2026-08-25T00:00:00-05:00',
          'EndDate': '2026-09-07T00:00:00-05:00',
        },
      ],
    };
    // The retry finds rows under the real SK.
    adapter.answers['IterationSK%20eq%20$iterationSk'] = snapshotRows();

    final days = await repository.burndown(
      org,
      project,
      iterationId,
      start: start,
      end: end,
    );

    expect(adapter.requests.length, 3);
    expect(
      adapter.firstMatching('Iterations?')!.uri.query,
      contains('IterationId%20eq%20$iterationId'),
    );
    expect(days.length, 2);
  });

  test('no lookup when the first call already answered', () async {
    await repository.burndown(
      org,
      project,
      iterationId,
      start: start,
      end: end,
    );

    expect(adapter.requests.length, 1);
    expect(adapter.firstMatching('Iterations?'), isNull);
  });

  test('403 is AnalyticsUnavailable, not a sign-in prompt', () async {
    adapter.status = 403;

    await expectLater(
      repository.burndown(org, project, iterationId, start: start, end: end),
      throwsA(isA<AnalyticsUnavailable>()),
    );
    // A page that catches AdoAuthException must not see this one, or it
    // would throw the user into interactive sign-in for a chart.
    expect(
      await repository
          .burndown(org, project, iterationId, start: start, end: end)
          .then<Object?>((_) => null, onError: (Object e) => e),
      isNot(isA<AdoAuthException>()),
    );
  });

  test('401 is AnalyticsUnavailable too', () async {
    adapter.status = 401;

    await expectLater(
      repository.burndown(org, project, iterationId, start: start, end: end),
      throwsA(isA<AnalyticsUnavailable>()),
    );
  });

  test('a second call is answered from the cache', () async {
    await repository.burndown(
      org,
      project,
      iterationId,
      start: start,
      end: end,
    );

    final days = await repository.burndown(
      org,
      project,
      iterationId,
      start: start,
      end: end,
    );

    expect(adapter.requests.length, 1);
    expect(days.length, 2);
  });

  test('the cache answers when the network is gone', () async {
    await repository.burndown(
      org,
      project,
      iterationId,
      start: start,
      end: end,
    );
    adapter.status = 500;

    final days = await repository.burndown(
      org,
      project,
      iterationId,
      start: start,
      end: end,
      refresh: true,
    );

    expect(days.length, 2);
  });

  test('the cache key is the last day the window covers', () {
    expect(
      AnalyticsRepository.burndownKey(
        org,
        project,
        iterationId,
        DateTime.utc(2026, 9, 7, 23),
      ),
      'analytics:burndown:$org:$project:$iterationId:2026-09-07',
    );
  });
}
