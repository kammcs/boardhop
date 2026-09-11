import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// One thread as the Threads API returns it.
Map<String, dynamic> thread({
  required int id,
  required String status,
  String? filePath,
  int? line,
  String published = '2026-09-01T10:00:00Z',
  bool deleted = false,
  bool systemOnly = false,
}) => {
  'id': id,
  'status': status,
  'isDeleted': deleted,
  if (filePath != null)
    'threadContext': {
      'filePath': filePath,
      'rightFileStart': {'line': line ?? 1},
    },
  'comments': [
    {
      'id': 1,
      'content': systemOnly ? 'voted' : 'a human comment',
      'commentType': systemOnly ? 'system' : 'text',
      'publishedDate': published,
      'author': {'displayName': 'Kelly Kamm'},
    },
  ],
};

void main() {
  test('the conversation keeps file threads, drops system and deleted', () {
    final threads = PullRequestRepository.conversation([
      thread(
        id: 3,
        status: 'active',
        filePath: '/src/a.js',
        line: 38,
        published: '2026-09-03T10:00:00Z',
      ),
      thread(id: 9, status: 'active', systemOnly: true),
      thread(id: 4, status: 'fixed', filePath: '/src/b.js', deleted: true),
      thread(id: 1, status: 'fixed', published: '2026-09-01T10:00:00Z'),
      thread(
        id: 2,
        status: 'fixed',
        filePath: '/src/c.js',
        published: '2026-09-02T10:00:00Z',
      ),
    ]);
    // Oldest first, file threads included, no system or deleted rows.
    expect(threads.map((t) => t.id), [1, 2, 3]);
    expect(threads[1].isFileThread, isTrue);
    expect(threads[0].isFileThread, isFalse);
  });

  test('filters split the conversation by resolution', () {
    final threads = PullRequestRepository.conversation([
      thread(id: 1, status: 'active', filePath: '/a.js'),
      thread(id: 2, status: 'fixed', filePath: '/b.js'),
      thread(id: 3, status: 'wontFix'),
      thread(id: 4, status: 'pending', filePath: '/c.js'),
      thread(id: 5, status: 'byDesign'),
      thread(id: 6, status: 'closed'),
    ]);
    List<int> ids(PrConversationFilter f) =>
        PullRequestRepository.filterConversation(
          threads,
          f,
        ).map((t) => t.id).toList();
    expect(ids(PrConversationFilter.all).length, 6);
    // Pending is still awaiting an answer, so it counts as active.
    expect(ids(PrConversationFilter.active), [1, 4]);
    expect(ids(PrConversationFilter.resolved), [2, 3, 5, 6]);
  });

  test('a review that lives entirely in files is not empty', () {
    // Spike s22: ServiceDelivery !8261 has 52 file threads and no others.
    final raw = [
      for (var i = 0; i < 52; i++)
        thread(
          id: i + 1,
          status: i < 14 ? 'active' : 'fixed',
          filePath: '/src/file$i.js',
          line: i + 1,
        ),
    ];
    final threads = PullRequestRepository.conversation(raw);
    expect(threads.length, 52);
    expect(
      PullRequestRepository.filterConversation(
        threads,
        PrConversationFilter.active,
      ).length,
      14,
    );
  });
}
