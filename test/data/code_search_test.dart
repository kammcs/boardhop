import 'package:boardhop/data/models/git_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('code search hits parse repository, branch and match counts', () {
    final page = CodeSearchResults.fromJson({
      'count': 2,
      'infoCode': 0,
      'results': [
        {
          'fileName': 'app.ts',
          'path': '/frontend/src/app.ts',
          'repository': {'name': 'MonitorIT', 'id': 'r1'},
          'project': {'name': 'CloudCover 2.0'},
          'versions': [
            {'branchName': 'main', 'changeId': 'abc'},
          ],
          'matches': {
            'content': [
              {'charOffset': 1, 'length': 4},
              {'charOffset': 9, 'length': 4},
            ],
            'fileName': [],
          },
        },
        {
          'fileName': 'TODO.md',
          'path': '/TODO.md',
          'repository': {'name': 'Portal', 'id': 'r2'},
          'project': {'name': 'CloudCover 2.0'},
          'versions': [],
          'matches': {'content': 3, 'fileName': 1},
        },
      ],
    });
    expect(page.count, 2);
    expect(page.problem, isNull);
    final a = page.hits[0];
    expect(a.repositoryName, 'MonitorIT');
    expect(a.branch, 'main');
    expect(a.folder, '/frontend/src');
    expect(a.contentMatches, 2);
    final b = page.hits[1];
    expect(b.branch, isNull);
    expect(b.contentMatches, 3);
    expect(b.fileNameMatches, 1);
  });

  test('infoCode maps to a plain message', () {
    expect(
      CodeSearchResults.fromJson({'infoCode': 1}).problem,
      contains('still being built'),
    );
    expect(CodeSearchResults.fromJson({'infoCode': 3}).problem, isNotNull);
    // Undocumented codes (15 came back for a young scratch project) get a
    // plain fallback that names the likely cause.
    expect(
      CodeSearchResults.fromJson({'infoCode': 15}).problem,
      allOf(contains('status 15'), contains('indexed')),
    );
    expect(CodeSearchResults.fromJson({}).problem, isNull);
  });
}
