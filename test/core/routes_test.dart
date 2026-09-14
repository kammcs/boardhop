import 'package:boardhop/core/routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('routes are account-scoped and encoded', () {
    expect(Routes.account('a.b'), '/a/a.b');
    expect(Routes.org('u1', 'my org'), '/a/u1/orgs/my%20org');
    expect(
      Routes.project('u1', 'puremedia', 'DevOps Mobile App'),
      '/a/u1/orgs/puremedia/projects/DevOps%20Mobile%20App',
    );
  });

  group('the search route (research/15 §4)', () {
    test('plain, it is the grouped view of the project', () {
      expect(
        Routes.search('u1', 'puremedia', 'DevOps Mobile App'),
        '/a/u1/orgs/puremedia/projects/DevOps%20Mobile%20App/search',
      );
    });

    test('the default scope and an empty term are left out', () {
      expect(
        Routes.search('u1', 'o', 'P', q: '   ', scope: 'project'),
        '/a/u1/orgs/o/projects/P/search',
      );
    });

    test('the term, the scope and the kind travel in the query', () {
      expect(
        Routes.search(
          'u1',
          'o',
          'P',
          q: ' drag and drop ',
          scope: 'org',
          kind: 'wi',
        ),
        // Uri.encodeQueryComponent spells a space '+', which
        // Uri.queryParameters (and so go_router) reads back as one.
        '/a/u1/orgs/o/projects/P/search?q=drag+and+drop&scope=org&kind=wi',
      );
    });
  });
}
