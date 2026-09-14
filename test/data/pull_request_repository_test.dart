import 'dart:convert';
import 'dart:typed_data';

import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const org = 'contoso';
const projectGuid = '98720989-1234-4321-8888-aaaabbbbcccc';
const repoGuid = '9a8b7c6d-5555-4444-8333-222211110000';

/// Canned-response adapter: the repository is exercised through the real
/// `AdoClient`, so the URL, the method and the body it builds are what the
/// tests read.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter([this.answer = const <String, dynamic>{}]);

  final Map<String, dynamic> answer;
  final List<RequestOptions> requests = <RequestOptions>[];
  int status = 201;

  RequestOptions get last => requests.last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(answer),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

PullRequestRepository _repo(_FakeAdapter adapter) => PullRequestRepository(
  AdoClient(
    tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
    dio: Dio()..httpClientAdapter = adapter,
  ),
);

PullRequest _pr() => PullRequest.fromJson({
  'pullRequestId': 8334,
  'title': 'Scratch',
  'status': 'active',
  'repository': {
    'id': repoGuid,
    'name': 'scratch',
    'project': {'id': projectGuid, 'name': 'DevOps Mobile App'},
  },
  'createdBy': {'displayName': 'Kelly Kamm', 'id': 'k'},
});

/// What the store really answers (spike w32 §4): an int id counting from 1
/// per pull request, and a `displayName` that is the file name.
Map<String, dynamic> _attachment(String name) => {
  'id': 1,
  'displayName': name,
  'contentHash': 'abc',
  'url':
      'https://dev.azure.com/$org/$projectGuid/_apis/git/repositories/'
      '$repoGuid/pullRequests/8334/attachments/$name',
};

void main() {
  group('uploadAttachment', () {
    test('POSTs the bytes to the file name in the path', () async {
      final adapter = _FakeAdapter(_attachment('shot.png'));
      final bytes = Uint8List.fromList([1, 2, 3, 4]);

      final ref = await _repo(adapter)
          .uploadAttachment(org, _pr(), 'shot.png', bytes);

      expect(adapter.last.method, 'POST');
      expect(
        adapter.last.uri.toString(),
        'https://dev.azure.com/$org/$projectGuid/_apis/git/repositories/'
        '$repoGuid/pullRequests/8334/attachments/shot.png?api-version=7.1',
      );
      // Any other content type is HTTP 400 on both stores (w32 §5).
      expect(
        adapter.last.headers[Headers.contentTypeHeader],
        contains('octet-stream'),
      );
      expect(adapter.last.data, bytes);
      expect(ref.url, endsWith('/attachments/shot.png'));
    });

    test('the int id the store answers is kept as a string', () async {
      final adapter = _FakeAdapter(_attachment('shot.png'));

      final ref = await _repo(adapter)
          .uploadAttachment(org, _pr(), 'shot.png', Uint8List(1));

      expect(ref.id, '1');
      expect(ref.fileName, 'shot.png');
    });

    test('a name with a space is encoded exactly once', () async {
      final adapter = _FakeAdapter(_attachment('my note.txt'));

      await _repo(adapter)
          .uploadAttachment(org, _pr(), 'my note.txt', Uint8List(1));

      expect(adapter.last.uri.path, endsWith('/attachments/my%20note.txt'));
      expect(adapter.last.uri.path.contains('%2520'), isFalse);
    });
  });

  group('AttachmentRef.fromJson', () {
    test('reads the pull request store shape', () {
      final ref = AttachmentRef.fromJson(_attachment('shot.png'));
      expect(ref.id, '1');
      expect(ref.fileName, 'shot.png');
    });

    test('still reads the work item store shape', () {
      final ref = AttachmentRef.fromJson({
        'id': 'c50b0d6e-1111-4222-8333-444455556666',
        'url':
            'https://dev.azure.com/$org/$projectGuid/_apis/wit/attachments/x',
      }, fileName: 'notes.txt');
      expect(ref.id, 'c50b0d6e-1111-4222-8333-444455556666');
      expect(ref.fileName, 'notes.txt');
    });

    test('an empty answer does not throw', () {
      final ref = AttachmentRef.fromJson(const {});
      expect(ref.id, '');
      expect(ref.url, '');
      expect(ref.fileName, isNull);
    });
  });

  group('listAttachments', () {
    test('GETs the store and names every row', () async {
      final adapter = _FakeAdapter({
        'count': 2,
        'value': [_attachment('shot.png'), _attachment('notes.txt')],
      })..status = 200;

      final refs = await _repo(adapter).listAttachments(org, _pr());

      expect(adapter.last.method, 'GET');
      expect(adapter.last.uri.path, endsWith('/pullRequests/8334/attachments'));
      expect(refs.map((r) => r.fileName), ['shot.png', 'notes.txt']);
    });
  });

  group('attachmentBytes', () {
    test('fetches the absolute URL with the bearer token', () async {
      final adapter = _FakeAdapter()..status = 200;
      const url =
          'https://dev.azure.com/$org/$projectGuid/_apis/git/repositories/'
          '$repoGuid/pullRequests/8334/attachments/shot.png';

      await _repo(adapter).attachmentBytes(url);

      expect(adapter.last.uri.toString(), url);
      expect(adapter.last.headers['Authorization'], 'Bearer tok');
    });
  });
}
