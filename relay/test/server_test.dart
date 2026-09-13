import 'dart:convert';
import 'dart:io';

import 'package:boardhop_relay/src/auth.dart';
import 'package:boardhop_relay/src/capture.dart';
import 'package:boardhop_relay/src/server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

const secret = 's3cr3t-capture-key';

String basic(String user, String pass) => 'Basic ${base64.encode(utf8.encode('$user:$pass'))}';

void main() {
  late Directory tmp;
  late RelayServer server;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('relay_test_');
    server = RelayServer(
      version: 'test-sha',
      captureSecret: secret,
      captures: CaptureStore(tmp, maxBodyBytes: 64, maxFilesPerName: 3),
      startedAt: DateTime.now().subtract(const Duration(seconds: 7)),
      dbStatus: 'ok',
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Response> call(String method, String path, {String? auth, String? body}) async => server.handler(
    Request(
      method,
      Uri.parse('http://localhost:8080$path'),
      headers: {
        if (auth != null) 'authorization': auth,
        'content-type': 'application/json',
        'user-agent': 'VSServices/1.0',
        'X-VSS-ActivityId': 'abc-123',
        'x-secret-header': 'should not be kept',
      },
      body: body,
    ),
  );

  group('healthz', () {
    test('answers 200 with version and uptime', () async {
      final r = await call('GET', '/healthz');
      expect(r.statusCode, 200);
      final json = jsonDecode(await r.readAsString()) as Map<String, Object?>;
      expect(json['ok'], isTrue);
      expect(json['version'], 'test-sha');
      expect(json['uptime'], greaterThanOrEqualTo(7));
      expect(json['db'], 'ok');
    });

    test('needs no authentication', () async {
      expect((await call('GET', '/healthz')).statusCode, 200);
    });
  });

  group('capture auth', () {
    test('401 without credentials', () async {
      final r = await call('POST', '/capture/scratch', body: '{}');
      expect(r.statusCode, 401);
      expect(r.headers['www-authenticate'], contains('Basic'));
      expect(tmp.listSync(), isEmpty);
    });

    test('401 with the wrong password', () async {
      final r = await call('POST', '/capture/scratch', auth: basic(captureUsername, 'nope'), body: '{}');
      expect(r.statusCode, 401);
    });

    test('401 with the wrong username', () async {
      final r = await call('POST', '/capture/scratch', auth: basic('admin', secret), body: '{}');
      expect(r.statusCode, 401);
    });

    test('401 on a malformed header', () async {
      expect((await call('POST', '/capture/scratch', auth: 'Bearer $secret', body: '{}')).statusCode, 401);
      expect((await call('POST', '/capture/scratch', auth: 'Basic !!!not-base64', body: '{}')).statusCode, 401);
    });

    test('401 on GET as well', () async {
      expect((await call('GET', '/capture/scratch')).statusCode, 401);
    });

    test('rejects everything when no secret is configured', () async {
      final locked = RelayServer(version: 'v', captureSecret: '', captures: CaptureStore(tmp));
      final r = await Future.value(
        locked.handler(
          Request(
            'POST',
            Uri.parse('http://localhost/capture/scratch'),
            headers: {'authorization': basic(captureUsername, '')},
            body: '{}',
          ),
        ),
      );
      expect(r.statusCode, 401);
    });
  });

  group('capture round trip', () {
    test('POST stores the body and headers, GET lists it', () async {
      const payload = '{"eventType":"git.pullrequest.updated","id":"42"}';
      final post = await call('POST', '/capture/scratch', auth: basic(captureUsername, secret), body: payload);
      expect(post.statusCode, 200);

      final dir = Directory('${tmp.path}${Platform.pathSeparator}scratch');
      final files = dir.listSync().whereType<File>().toList();
      expect(files, hasLength(1));
      expect(files.single.path, endsWith('-git.pullrequest.updated.json'));

      final stored = jsonDecode(files.single.readAsStringSync()) as Map<String, Object?>;
      expect(stored['eventType'], 'git.pullrequest.updated');
      expect(stored['truncated'], isFalse);
      expect((stored['body'] as Map)['id'], '42');
      final headers = stored['headers'] as Map<String, Object?>;
      expect(headers['x-vss-activityid'], 'abc-123');
      expect(headers['user-agent'], 'VSServices/1.0');
      expect(headers['content-type'], contains('application/json'));
      expect(headers.keys, isNot(contains('x-secret-header')));
      expect(headers.keys, isNot(contains('authorization')));

      final list = await call('GET', '/capture/scratch', auth: basic(captureUsername, secret));
      expect(list.statusCode, 200);
      final json = jsonDecode(await list.readAsString()) as Map<String, Object?>;
      expect(json['count'], 1);
      final entry = (json['files'] as List).single as Map<String, Object?>;
      expect(entry['eventType'], 'git.pullrequest.updated');
      expect(entry['bytes'], greaterThan(0));
    });

    test('a body that is not JSON is still captured', () async {
      final r = await call('POST', '/capture/scratch', auth: basic(captureUsername, secret), body: 'not json');
      expect(r.statusCode, 200);
      final files = Directory('${tmp.path}${Platform.pathSeparator}scratch').listSync().whereType<File>();
      expect(files.single.path, endsWith('-unknown.json'));
      final stored = jsonDecode(files.single.readAsStringSync()) as Map<String, Object?>;
      expect(stored['body'], 'not json');
    });

    test('an unknown path is 404', () async {
      expect((await call('GET', '/nope')).statusCode, 404);
    });

    test('a capture name that walks the filesystem is 400', () async {
      final r = await call('POST', '/capture/..', auth: basic(captureUsername, secret), body: '{}');
      expect(r.statusCode, anyOf(400, 404));
      expect(tmp.listSync().whereType<Directory>(), isEmpty);
    });
  });
}
