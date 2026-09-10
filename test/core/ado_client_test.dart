import 'dart:convert';
import 'dart:typed_data';

import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/core/http/ado_exceptions.dart';
import 'package:boardhop/core/http/ado_host.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Canned-response adapter so the client can be exercised without a network.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions) handler;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(
  int status,
  Object body, {
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    ...headers,
  },
);

AdoClient _client(_FakeAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return AdoClient(
    tokenProvider: ({String? tenantId}) async => 'tok-${tenantId ?? 'home'}',
    dio: dio,
  );
}

void main() {
  group('buildUri', () {
    test('core host puts org, project and team before _apis', () {
      final uri = AdoClient.buildUri(
        host: AdoHost.core,
        org: 'puremedia',
        project: 'CloudCover 2.0',
        team: 'Team A',
        path: '_apis/wit/workitems/15503',
        apiVersion: '7.1',
        query: {'\$expand': 'all'},
      );
      expect(
        uri.toString(),
        'https://dev.azure.com/puremedia/CloudCover%202.0/Team%20A/_apis/wit/workitems/15503?%24expand=all&api-version=7.1',
      );
    });

    test('app.vssps host has no org segment', () {
      final uri = AdoClient.buildUri(
        host: AdoHost.appVssps,
        path: '_apis/accounts',
        apiVersion: '7.1',
        query: {'memberId': 'abc'},
      );
      expect(
        uri.toString(),
        'https://app.vssps.visualstudio.com/_apis/accounts?memberId=abc&api-version=7.1',
      );
    });
  });

  group('parseClaimsChallenge', () {
    test('returns claims for insufficient_claims', () {
      const header =
          'Bearer authorization_uri="https://login.microsoftonline.com/common/oauth2/authorize", error="insufficient_claims", claims="eyJhY2Nlc3NfdG9rZW4iOnt9fQ=="';
      expect(
        AdoClient.parseClaimsChallenge(header),
        'eyJhY2Nlc3NfdG9rZW4iOnt9fQ==',
      );
    });

    test('returns null for a plain bearer challenge', () {
      expect(AdoClient.parseClaimsChallenge('Bearer realm="x"'), isNull);
    });
  });

  group('send', () {
    test('adds bearer token, suppress header and api-version', () async {
      final adapter = _FakeAdapter(
        (_) => _json(200, {'count': 0, 'value': []}),
      );
      final client = _client(adapter);
      final json = await client.getJson(
        org: 'puremedia',
        path: '_apis/projects',
        apiVersion: '7.1',
        tenantId: 't1',
      );
      expect(json['count'], 0);
      final req = adapter.last!;
      expect(req.headers['Authorization'], 'Bearer tok-t1');
      expect(req.headers['X-TFS-FedAuthRedirect'], 'Suppress');
      expect(req.uri.queryParameters['api-version'], '7.1');
    });

    test('maps 412 to AdoStaleRevisionException', () async {
      final adapter = _FakeAdapter(
        (_) => _json(412, {
          'message': 'VS403351: The revision has changed',
          'typeKey': 'WorkItemRevisionMismatchException',
        }),
      );
      final client = _client(adapter);
      expect(
        () => client.send(
          method: 'PATCH',
          org: 'puremedia',
          path: '_apis/wit/workitems/1',
          apiVersion: '7.1',
          body: const [],
          contentType: AdoClient.jsonPatchContentType,
        ),
        throwsA(
          isA<AdoStaleRevisionException>().having(
            (e) => e.typeKey,
            'typeKey',
            'WorkItemRevisionMismatchException',
          ),
        ),
      );
    });

    test(
      'maps 401 with insufficient_claims to ClaimsChallengeException',
      () async {
        final adapter = _FakeAdapter(
          (_) => _json(
            401,
            {'message': 'CAE'},
            headers: {
              'www-authenticate': [
                'Bearer error="insufficient_claims", claims="abc"',
              ],
            },
          ),
        );
        final client = _client(adapter);
        expect(
          () => client.getJson(
            org: 'o',
            path: '_apis/projects',
            apiVersion: '7.1',
          ),
          throwsA(
            isA<ClaimsChallengeException>().having(
              (e) => e.claims,
              'claims',
              'abc',
            ),
          ),
        );
      },
    );

    test('maps 400 RuleValidationErrors to AdoValidationException', () async {
      final adapter = _FakeAdapter(
        (_) => _json(400, {
          'message': 'TF401320: Rule Error',
          'typeKey': 'RuleValidationException',
          'customProperties': {
            'RuleValidationErrors': [
              {
                'fieldReferenceName': 'System.Title',
                'errorCode': '0x1',
                'errorMessage': 'Title required',
              },
            ],
          },
        }),
      );
      final client = _client(adapter);
      expect(
        () => client.getJson(org: 'o', path: '_apis/x', apiVersion: '7.1'),
        throwsA(
          isA<AdoValidationException>().having(
            (e) => e.ruleErrors.single.fieldReferenceName,
            'field',
            'System.Title',
          ),
        ),
      );
    });

    test('records X-RateLimit-Cost on a 200', () async {
      final adapter = _FakeAdapter(
        (_) => _json(
          200,
          {'value': []},
          headers: {
            'x-ratelimit-cost': ['0.013'],
          },
        ),
      );
      final client = _client(adapter);
      await client.getJson(org: 'o', path: '_apis/x', apiVersion: '7.1');
      expect(client.rateLimits.latest?.cost, 0.013);
      expect(client.rateLimits.totalCost, 0.013);
    });

    test('treats 203 as not authenticated', () async {
      final adapter = _FakeAdapter(
        (_) => ResponseBody.fromString(
          '<html>sign in</html>',
          203,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          },
        ),
      );
      final client = _client(adapter);
      expect(
        () => client.getJson(org: 'o', path: '_apis/x', apiVersion: '7.1'),
        throwsA(isA<AdoAuthException>()),
      );
    });
  });
}
