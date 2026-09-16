import 'dart:convert';
import 'dart:typed_data';

import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/repositories/pr_diff_source.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
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

PullRequestRepository _repo(_FakeAdapter adapter, [AppDatabase? db]) =>
    PullRequestRepository(
      AdoClient(
        tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
        dio: Dio()..httpClientAdapter = adapter,
      ),
      db,
      'kelly@kammcs.com-home',
    );

/// The scratch pull request the writes were verified against (spike w39).
const meGuid = '5ed61bee-579a-69a3-8d5b-295951b461b4';
const teamGuid = '8c08e1e1-7afd-411e-b414-4f9e1d14d8d6';
const prBase =
    'https://dev.azure.com/$org/$projectGuid/_apis/git/repositories/'
    '$repoGuid/pullRequests/8334';

/// `connectionData`, which every call that needs the signed-in identity
/// reaches for first.
Map<String, dynamic> _connection() => {
  'authorizedUser': {'id': meGuid, 'displayName': 'Kelly Kamm'},
};

Map<String, dynamic> _body(RequestOptions r) =>
    (r.data as Map).cast<String, dynamic>();

PullRequest _pr() => PullRequest.fromJson(_prAnswer());

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

  group('completion and auto-complete (spike w39 §2)', () {
    test('complete sends the status, the tip and the full options', () async {
      final adapter = _FakeAdapter({..._prAnswer(), 'status': 'completed'})
        ..status = 200;

      await _repo(adapter).complete(
        org,
        _prWithTip(),
        const PrCompletionOptions(
          mergeStrategy: MergeStrategy.squash,
          deleteSourceBranch: true,
          transitionWorkItems: true,
          mergeCommitMessage: 'Squashed',
        ),
      );

      expect(adapter.last.method, 'PATCH');
      expect(adapter.last.uri.toString(), '$prBase?api-version=7.1');
      final body = _body(adapter.last);
      expect(body['status'], 'completed');
      expect((body['lastMergeSourceCommit'] as Map)['commitId'], 'f4af1039');
      expect(body['completionOptions'], {
        'mergeStrategy': 'squash',
        'deleteSourceBranch': true,
        'transitionWorkItems': true,
        'mergeCommitMessage': 'Squashed',
      });
    });

    test('setAutoComplete names the signed-in identity', () async {
      final adapter = _FakeAdapter({..._prAnswer(), ..._connection()})
        ..status = 200;

      await _repo(adapter).setAutoComplete(
        org,
        _pr(),
        const PrCompletionOptions(mergeStrategy: MergeStrategy.noFastForward),
      );

      // connectionData first, then the patch.
      expect(adapter.requests.first.uri.path, endsWith('_apis/connectionData'));
      expect(adapter.last.method, 'PATCH');
      expect(_body(adapter.last)['autoCompleteSetBy'], {'id': meGuid});
      expect(
        (_body(adapter.last)['completionOptions'] as Map)['mergeStrategy'],
        'noFastForward',
      );
    });

    test('cancelAutoComplete writes the null GUID and nothing else', () async {
      final adapter = _FakeAdapter(_prAnswer())..status = 200;

      await _repo(adapter).cancelAutoComplete(org, _pr());

      expect(_body(adapter.last), {
        'autoCompleteSetBy': {'id': '00000000-0000-0000-0000-000000000000'},
      });
      expect(PullRequestRepository.nullGuid, hasLength(36));
    });

    test(
      'setDraft, retarget, restartMerge and update each patch once',
      () async {
        final adapter = _FakeAdapter(_prAnswer())..status = 200;
        final repo = _repo(adapter);

        await repo.setDraft(org, _pr(), true);
        expect(_body(adapter.last), {'isDraft': true});

        await repo.retarget(org, _pr(), 'refs/heads/main');
        expect(_body(adapter.last), {'targetRefName': 'refs/heads/main'});

        // There is no restart-merge route: the default merge options are
        // what the web writes, and they re-queue the merge.
        await repo.restartMerge(org, _pr());
        expect(_body(adapter.last)['mergeOptions'], {
          'detectRenameFalsePositives': false,
          'disableRenames': false,
          'conflictAuthorshipCommits': false,
        });

        await repo.update(org, _pr(), title: 'Retitled');
        expect(_body(adapter.last), {'title': 'Retitled'});

        expect(adapter.requests.every((r) => r.method == 'PATCH'), isTrue);
      },
    );
  });

  group('reviewers (spike w39 §3)', () {
    test('addReviewer PUTs the identity with a zero vote', () async {
      final adapter = _FakeAdapter({
        'id': meGuid,
        'displayName': 'Kelly Kamm',
        'vote': 0,
        'isRequired': true,
      })..status = 200;

      final reviewer = await _repo(adapter)
          .addReviewer(org, _pr(), meGuid, isRequired: true);

      expect(adapter.last.method, 'PUT');
      expect(
        adapter.last.uri.toString(),
        '$prBase/reviewers/$meGuid'
        '?api-version=7.1',
      );
      expect(_body(adapter.last), {
        'id': meGuid,
        'vote': 0,
        'isRequired': true,
      });
      expect(reviewer.isRequired, isTrue);
    });

    test('setRequired is the same idempotent PUT', () async {
      final adapter = _FakeAdapter({'id': meGuid, 'vote': 0})..status = 200;

      await _repo(adapter).setRequired(org, _pr(), meGuid, false);

      expect(adapter.last.method, 'PUT');
      expect(_body(adapter.last)['isRequired'], isFalse);
    });

    test('removeReviewer DELETEs the team', () async {
      final adapter = _FakeAdapter()..status = 200;

      await _repo(adapter).removeReviewer(org, _pr(), teamGuid);

      expect(adapter.last.method, 'DELETE');
      expect(adapter.last.uri.path, endsWith('/reviewers/$teamGuid'));
    });

    test('resetVote uses the batch route, not a vote as that person', () async {
      final adapter = _FakeAdapter()..status = 204;

      await _repo(adapter).resetVote(org, _pr(), teamGuid);

      expect(adapter.last.method, 'PATCH');
      expect(adapter.last.uri.path, endsWith('/reviewers'));
      expect(adapter.last.data, [
        {'id': teamGuid, 'vote': 0},
      ]);
    });

    test('flag and decline patch the one reviewer', () async {
      final adapter = _FakeAdapter({'id': meGuid, 'vote': 0, 'isFlagged': true})
        ..status = 200;
      final repo = _repo(adapter);

      final flagged = await repo.flag(org, _pr(), meGuid);
      expect(adapter.last.method, 'PATCH');
      expect(adapter.last.uri.path, endsWith('/reviewers/$meGuid'));
      expect(_body(adapter.last), {'isFlagged': true});
      expect(flagged.isFlagged, isTrue);

      await repo.decline(org, _pr(), meGuid);
      expect(_body(adapter.last), {'hasDeclined': true});

      await repo.flag(org, _pr(), meGuid, isFlagged: false);
      expect(_body(adapter.last), {'isFlagged': false});
    });
  });

  group('labels (spikes w40, s65 §A)', () {
    test(
      'labels are read from the sub-resource the get never carries',
      () async {
        final adapter = _FakeAdapter({
          'count': 2,
          'value': [
            {'id': 'c2e3426f', 'name': 'boardhop-spike', 'active': true},
            {'id': '65176f7a', 'name': 'boardhop-spike-2', 'active': true},
          ],
        })..status = 200;

        final labels = await _repo(adapter).labels(org, _pr());

        expect(adapter.last.method, 'GET');
        expect(adapter.last.uri.toString(), '$prBase/labels?api-version=7.1');
        expect(labels.map((l) => l.name), [
          'boardhop-spike',
          'boardhop-spike-2',
        ]);
      },
    );

    test('addLabel posts the name, removeLabel deletes by name', () async {
      final adapter = _FakeAdapter({
        'id': 'c2e3426f',
        'name': 'boardhop-spike',
        'active': true,
      })..status = 200;
      final repo = _repo(adapter);

      final label = await repo.addLabel(org, _pr(), 'boardhop-spike');
      expect(adapter.last.method, 'POST');
      expect(_body(adapter.last), {'name': 'boardhop-spike'});
      expect(label.id, 'c2e3426f');

      await repo.removeLabel(org, _pr(), 'boardhop-spike');
      expect(adapter.last.method, 'DELETE');
      expect(adapter.last.uri.path, endsWith('/labels/boardhop-spike'));
    });

    test('a label name is encoded exactly once', () async {
      final adapter = _FakeAdapter()..status = 200;

      await _repo(adapter).removeLabel(org, _pr(), 'needs docs');

      expect(adapter.last.uri.path, endsWith('/labels/needs%20docs'));
      expect(adapter.last.uri.path.contains('%2520'), isFalse);
    });
  });

  group('comment tools (spike w39 §4)', () {
    test('editComment patches the content of one comment', () async {
      final adapter = _FakeAdapter({
        'id': 2,
        'content': 'edited',
        'publishedDate': '2026-09-16T04:36:00Z',
        'lastContentUpdatedDate': '2026-09-16T04:41:00Z',
        'author': {'displayName': 'Kelly Kamm'},
      })..status = 200;

      final comment = await _repo(adapter)
          .editComment(org, _pr(), 42975, 2, 'edited');

      expect(adapter.last.method, 'PATCH');
      expect(
        adapter.last.uri.toString(),
        '$prBase/threads/42975/comments/2?api-version=7.1',
      );
      expect(_body(adapter.last), {'content': 'edited'});
      expect(comment.isEdited, isTrue);
    });

    test('deleteComment, like and unlike hit the right verbs', () async {
      final adapter = _FakeAdapter()..status = 200;
      final repo = _repo(adapter);

      await repo.deleteComment(org, _pr(), 42975, 2);
      expect(adapter.last.method, 'DELETE');
      expect(adapter.last.uri.path, endsWith('/threads/42975/comments/2'));

      await repo.like(org, _pr(), 42975, 1);
      expect(adapter.last.method, 'POST');
      expect(adapter.last.uri.path, endsWith('/comments/1/likes'));

      await repo.unlike(org, _pr(), 42975, 1);
      expect(adapter.last.method, 'DELETE');
      expect(adapter.last.uri.path, endsWith('/comments/1/likes'));
    });
  });

  group('threadBody', () {
    test('a conversation comment carries no context at all', () {
      final body = PullRequestRepository.threadBody(content: 'hello');
      expect(body.containsKey('threadContext'), isFalse);
      expect(body.containsKey('pullRequestThreadContext'), isFalse);
      expect((body['comments'] as List).single, {
        'parentCommentId': 0,
        'content': 'hello',
        'commentType': 1,
      });
    });

    test('file-level is a path and nothing else', () {
      final body = PullRequestRepository.threadBody(
        content: 'on the file',
        filePath: '/src/app.ts',
        fileLevel: true,
        iteration: 1,
        changeTrackingId: 4,
      );

      expect(body['threadContext'], {'filePath': '/src/app.ts'});
      expect((body['pullRequestThreadContext'] as Map)['changeTrackingId'], 4);
    });

    test('a right-side line is unchanged from the first pass', () {
      final body = PullRequestRepository.threadBody(
        content: 'x',
        filePath: '/src/app.ts',
        line: 7,
        iteration: 1,
      );

      expect(body['threadContext'], {
        'filePath': '/src/app.ts',
        'rightFileStart': {'line': 7, 'offset': 1},
        'rightFileEnd': {'line': 7, 'offset': 1},
      });
    });

    test('leftSide anchors on the original side', () {
      final body = PullRequestRepository.threadBody(
        content: 'x',
        filePath: '/src/app.ts',
        line: 5,
        leftSide: true,
      );

      expect(body['threadContext'], {
        'filePath': '/src/app.ts',
        'leftFileStart': {'line': 5, 'offset': 1},
        'leftFileEnd': {'line': 5, 'offset': 1},
      });
    });

    test('a range ends at the end of its last line', () {
      final body = PullRequestRepository.threadBody(
        content: 'x',
        filePath: '/src/app.ts',
        line: 5,
        endLine: 6,
      );

      expect((body['threadContext'] as Map)['rightFileEnd'], {
        'line': 6,
        'offset': PullRequestRepository.endOfLineOffset,
      });
    });

    test('an end line before the start collapses to one line', () {
      final body = PullRequestRepository.threadBody(
        content: 'x',
        filePath: '/src/app.ts',
        line: 9,
        endLine: 4,
      );

      expect((body['threadContext'] as Map)['rightFileEnd'], {
        'line': 9,
        'offset': 1,
      });
    });
  });

  group('conflicts, share and commits', () {
    test('conflicts reads the undocumented sub-resource', () async {
      final adapter = _FakeAdapter({
        'count': 2,
        'value': [
          {
            'conflictId': 1,
            'conflictType': 'editEdit',
            'conflictPath': '/src/app.ts',
          },
          {
            'conflictId': 2,
            'conflictType': 'addAdd',
            'conflictPath': '/spike/w39/both.txt',
          },
        ],
      })..status = 200;

      final conflicts = await _repo(adapter)
          .conflicts(org, _pr(), excludeResolved: true);

      expect(adapter.last.method, 'GET');
      expect(adapter.last.uri.path, endsWith('/pullRequests/8334/conflicts'));
      expect(adapter.last.uri.queryParameters['excludeResolved'], 'true');
      expect(conflicts.map((c) => c.path), [
        '/src/app.ts',
        '/spike/w39/both.txt',
      ]);
    });

    test('share posts the receivers and the message', () async {
      final adapter = _FakeAdapter()..status = 200;

      await _repo(adapter).share(org, _pr(), [meGuid], 'Take a look');

      expect(adapter.last.method, 'POST');
      expect(adapter.last.uri.path, endsWith('/pullRequests/8334/share'));
      expect(_body(adapter.last), {
        'receivers': [
          {'id': meGuid},
        ],
        'message': 'Take a look',
      });
    });
  });

  group('policies', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Map<String, dynamic> answer() => {
      'count': 2,
      'value': [
        {
          'id': 192,
          'isBlocking': true,
          'isEnabled': true,
          'type': {
            'id': PrPolicy.minimumReviewersType,
            'displayName': 'Minimum number of reviewers',
          },
          'settings': {
            'minimumApproverCount': 1,
            'scope': [
              {
                'refName': 'refs/heads/scratch/policy-target',
                'matchKind': 'exact',
                'repositoryId': repoGuid,
              },
            ],
          },
        },
        {
          'id': 193,
          'isBlocking': true,
          'isEnabled': true,
          'type': {
            'id': PrPolicy.mergeStrategyType,
            'displayName': 'Require a merge strategy',
          },
          'settings': {
            'allowNoFastForward': true,
            'allowSquash': true,
            'scope': [
              {
                'refName': 'refs/heads/scratch/policy-target',
                'matchKind': 'exact',
                'repositoryId': repoGuid,
              },
            ],
          },
        },
      ],
    };

    test('reads the git-scoped route for the target ref', () async {
      final adapter = _FakeAdapter(answer())..status = 200;

      final set = await _repo(adapter, db).policies(
        org,
        'DevOps Mobile App',
        repoGuid,
        'refs/heads/scratch/policy-target',
      );

      expect(adapter.last.method, 'GET');
      expect(
        adapter.last.uri.path,
        '/$org/DevOps%20Mobile%20App/_apis/git/policy/configurations',
      );
      expect(adapter.last.uri.queryParameters, {
        'repositoryId': repoGuid,
        'refName': 'refs/heads/scratch/policy-target',
        'api-version': '7.1',
      });
      expect(set.hasBlocking, isTrue);
      expect(set.allowedStrategies, {
        MergeStrategy.noFastForward,
        MergeStrategy.squash,
      });
      expect(set.minimumApproverCount, 1);
    });

    test('is cached for an hour under its own key', () async {
      const target = 'refs/heads/scratch/policy-target';
      final adapter = _FakeAdapter(answer())..status = 200;
      final repo = _repo(adapter, db);

      await repo.policies(org, 'p', repoGuid, target);
      final second = await repo.policies(org, 'p', repoGuid, target);

      expect(adapter.requests.length, 1);
      expect(second.policies, hasLength(2));
      expect(second.allowedStrategies, {
        MergeStrategy.noFastForward,
        MergeStrategy.squash,
      });
      expect(
        PullRequestRepository.policiesKey(org, repoGuid, target),
        'pr:policies:$org:$repoGuid:$target',
      );
      expect(PullRequestRepository.policiesTtl, const Duration(hours: 1));
    });

    test('refresh goes back to the service', () async {
      final adapter = _FakeAdapter(answer())..status = 200;
      final repo = _repo(adapter, db);

      await repo.policies(org, 'p', repoGuid, 'refs/heads/main');
      await repo.policies(org, 'p', repoGuid, 'refs/heads/main', refresh: true);

      expect(adapter.requests.length, 2);
    });

    test('a cached blob is filtered for the branch it is read for', () async {
      final adapter = _FakeAdapter(answer())..status = 200;
      final repo = _repo(adapter, db);

      // Cached under one branch, read back for another: the scope guard
      // keeps the first branch's exact-match policies out.
      await repo.policies(org, 'p', repoGuid, 'refs/heads/other');
      final cached = await repo.policies(
        org,
        'p',
        repoGuid,
        'refs/heads/other',
      );

      expect(adapter.requests.length, 1);
      expect(cached.policies, isEmpty);
      expect(cached.hasBlocking, isFalse);
      expect(cached.allowedStrategies, MergeStrategy.values.toSet());
    });
  });

  group('conversation', () {
    List<Map<String, dynamic>> raw() => [
      {
        'id': 1,
        'status': 'active',
        'publishedDate': '2026-09-16T04:00:00Z',
        'comments': [
          {
            'id': 1,
            'content': 'a human comment',
            'commentType': 'text',
            'publishedDate': '2026-09-16T04:00:00Z',
            'author': {'displayName': 'Kelly Kamm'},
          },
        ],
      },
      {
        'id': 2,
        'properties': {'CodeReviewThreadType': 'VoteUpdate'},
        'publishedDate': '2026-09-16T04:10:00Z',
        'comments': [
          {
            'id': 1,
            'content': 'Kelly Kamm voted 10',
            'commentType': 'system',
            'publishedDate': '2026-09-16T04:10:00Z',
            'author': {'displayName': 'Kelly Kamm'},
          },
        ],
      },
    ];

    test('still drops system threads by default', () {
      final threads = PullRequestRepository.conversation(raw());
      expect(threads.map((t) => t.id), [1]);
    });

    test('includeSystem adds them as the Activity chip needs', () {
      final threads = PullRequestRepository.conversation(
        raw(),
        includeSystem: true,
      );
      expect(threads.map((t) => t.id), [1, 2]);
      expect(threads.last.systemKind, 'VoteUpdate');
      expect(threads.last.systemText, 'Kelly Kamm voted 10');
    });
  });

  group('ViewedFilesStore fixtures', () {
    test('a change carries the blob id a viewed mark is keyed on', () {
      const change = PrFileChange(
        path: '/src/app.ts',
        changeType: 'edit',
        changeTrackingId: 4,
        objectId: 'c0d1a230',
      );
      expect(change.objectId, 'c0d1a230');
    });
  });
}

/// The scratch pull request, with the merge tip `complete` sends.
PullRequest _prWithTip() => PullRequest.fromJson({
  ..._prAnswer(),
  'lastMergeSourceCommit': {'commitId': 'f4af1039'},
});

Map<String, dynamic> _prAnswer() => {
  'pullRequestId': 8334,
  'title': 'Scratch',
  'status': 'active',
  'repository': {
    'id': repoGuid,
    'name': 'scratch',
    'project': {'id': projectGuid, 'name': 'DevOps Mobile App'},
  },
  'createdBy': {'displayName': 'Kelly Kamm', 'id': meGuid},
};
