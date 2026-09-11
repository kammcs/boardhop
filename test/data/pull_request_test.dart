import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final json = <String, dynamic>{
    'pullRequestId': 8319,
    'title': 'Spike PR',
    'description': 'Body',
    'status': 'active',
    'isDraft': false,
    'creationDate': '2026-09-10T10:00:00Z',
    'sourceRefName': 'refs/heads/feature/x',
    'targetRefName': 'refs/heads/main',
    'createdBy': {'displayName': 'Kelly Kamm', 'id': 'me'},
    'repository': {
      'id': 'repo',
      'name': 'spike-repo',
      'project': {'id': 'proj', 'name': 'DevOps Mobile App'},
    },
    'lastMergeSourceCommit': {'commitId': 'abc'},
    'reviewers': [
      {'id': 'r1', 'displayName': 'A', 'vote': 10},
      {'id': 'r2', 'displayName': 'B', 'vote': -5, 'isRequired': true},
      {'id': 'g', 'displayName': 'Team', 'vote': -10, 'isContainer': true},
    ],
  };

  test('parses a pull request and summarises votes', () {
    final pr = PullRequest.fromJson(json);
    expect(pr.id, 8319);
    expect(pr.sourceBranch, 'feature/x');
    expect(pr.targetBranch, 'main');
    expect(pr.projectName, 'DevOps Mobile App');
    expect(pr.createdBy.displayName, 'Kelly Kamm');
    expect(pr.lastMergeSourceCommit, 'abc');
    // The container's rejection is ignored; the waiting vote wins.
    expect(pr.overallVote, PrVote.waitingForAuthor);
    expect(pr.reviewer('r1')?.vote, PrVote.approved);
    expect(pr.reviewer('nope'), isNull);
    expect(PrVote.fromValue(5), PrVote.approvedWithSuggestions);
  });

  test('thread bodies for conversation and anchored line comments', () {
    final plain = PullRequestRepository.threadBody(content: 'hi');
    expect(plain['threadContext'], isNull);
    expect((plain['comments'] as List).single['content'], 'hi');

    final anchored = PullRequestRepository.threadBody(
      content: 'fix',
      filePath: '/src/app.ts',
      line: 6,
      changeTrackingId: 3,
      iteration: 2,
    );
    expect(anchored['threadContext'], {
      'filePath': '/src/app.ts',
      'rightFileStart': {'line': 6, 'offset': 1},
      'rightFileEnd': {'line': 6, 'offset': 1},
    });
    expect(anchored['pullRequestThreadContext'], {
      'changeTrackingId': 3,
      'iterationContext': {
        'firstComparingIteration': 2,
        'secondComparingIteration': 2,
      },
    });
  });

  test('conversation drops system and deleted, keeps file threads', () {
    final threads = PullRequestRepository.conversation([
      {
        'id': 1,
        'status': 'active',
        'comments': [
          {'commentType': 'system', 'content': 'Vote changed'},
        ],
      },
      {
        'id': 2,
        'status': 'active',
        'threadContext': {'filePath': '/a'},
        'comments': [
          {
            'commentType': 'text',
            'content': 'on a line',
            'author': {'displayName': 'A'},
          },
        ],
      },
      {
        'id': 3,
        'status': 'fixed',
        'comments': [
          {
            'commentType': 'text',
            'content': 'general',
            'author': {'displayName': 'B'},
          },
          {'commentType': 'text', 'content': 'gone', 'isDeleted': true},
        ],
      },
    ]);
    // The file thread stays: most reviews happen on lines (spike s22).
    expect(threads.map((t) => t.id), [2, 3]);
    expect(threads.last.comments.single.author, 'B');
    expect(threads.last.status, 'fixed');
    expect(threads.first.isFileThread, isTrue);
  });
}
