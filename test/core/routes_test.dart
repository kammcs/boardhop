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

  group('the Work tab\'s three views (research/18 S1)', () {
    const account = 'u1';
    const org = 'puremedia';
    const project = 'DevOps Mobile App';
    const base = '/a/u1/orgs/puremedia/projects/DevOps%20Mobile%20App';

    test('items and board have helpers now, not concatenated strings', () {
      expect(Routes.workItems(account, org, project), '$base/work-items');
      expect(Routes.board(account, org, project), '$base/boards');
    });

    test('the plain sprint route is the current sprint on the default tab', () {
      expect(Routes.sprint(account, org, project), '$base/sprint');
    });

    test('a named sprint and tab ride in the query', () {
      expect(
        Routes.sprint(account, org, project, iteration: 'abc-123'),
        '$base/sprint?iteration=abc-123',
      );
      expect(
        Routes.sprint(account, org, project, tab: 'burndown'),
        '$base/sprint?tab=burndown',
      );
      expect(
        Routes.sprint(
          account,
          org,
          project,
          iteration: 'abc-123',
          tab: 'taskboard',
        ),
        '$base/sprint?iteration=abc-123&tab=taskboard',
      );
    });

    test('an empty anchor is left out, like every other route', () {
      expect(
        Routes.sprint(account, org, project, iteration: ''),
        '$base/sprint',
      );
    });
  });

  group('the work item routes carry the tab (Kelly, 2026-09-14)', () {
    test('no tab is the plain route, which opens Details', () {
      expect(
        Routes.workItem('u1', 'puremedia', 'DevOps Mobile App', '15545'),
        '/a/u1/orgs/puremedia/projects/DevOps%20Mobile%20App'
        '/work-items/15545',
      );
      expect(
        Routes.workItemStandalone(
          'u1',
          'puremedia',
          'DevOps Mobile App',
          '15545',
        ),
        '/a/u1/orgs/puremedia/projects/DevOps%20Mobile%20App'
        '/work-item/15545',
      );
    });

    test('a tab rides in the query on both routes', () {
      expect(
        Routes.workItem(
          'u1',
          'puremedia',
          'DevOps Mobile App',
          '15545',
          tab: 'related',
        ),
        endsWith('/work-items/15545?tab=related'),
      );
      expect(
        Routes.workItemStandalone(
          'u1',
          'puremedia',
          'DevOps Mobile App',
          '15545',
          tab: 'comments',
        ),
        endsWith('/work-item/15545?tab=comments'),
      );
    });

    test('a comment anchor and a tab travel together', () {
      expect(
        Routes.workItemStandalone(
          'u1',
          'puremedia',
          'DevOps Mobile App',
          '15545',
          comment: '6068143',
          tab: 'comments',
        ),
        endsWith('/work-item/15545?comment=6068143&tab=comments'),
      );
      // The anchor alone is spelled exactly as it was before the tab
      // parameter existed, so pushed notifications are unchanged.
      expect(
        Routes.workItemStandalone(
          'u1',
          'puremedia',
          'DevOps Mobile App',
          '15545',
          comment: '6068143',
        ),
        endsWith('/work-item/15545?comment=6068143'),
      );
    });
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
