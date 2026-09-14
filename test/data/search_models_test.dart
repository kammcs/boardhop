import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/data/models/search.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shape spike s44 recorded, with invented values: never a real title,
/// person or project from the organization.
Map<String, dynamic> workItemResult() => {
  'project': {'id': 'p-scratch', 'name': 'Scratch'},
  'fields': {
    'system.id': '15503',
    'system.workitemtype': 'Task',
    'system.title': 'Boardhop spike task',
    'system.state': 'Active',
    'system.assignedto': 'Ada Lovelace <ada@example.test>',
    'system.tags': 'spike; mobile',
    'system.changeddate': '2026-09-14T10:11:12.000Z',
    'system.rev': '7',
  },
  'hits': [
    {
      'fieldReferenceName': 'system.title',
      'highlights': ['<highlighthit>Boardhop</highlighthit> spike task'],
    },
    {
      'fieldReferenceName': 'system.description',
      'highlights': [
        '<p>The phone client for '
            '<highlighthit>boardhop</highlighthit> &amp; friends</p>',
      ],
    },
  ],
};

Map<String, dynamic> searchResponse() => {
  'count': 42,
  'results': [workItemResult()],
  'infoCode': 0,
  'facets': {
    'System.TeamProject': [
      {'name': 'Scratch', 'resultCount': 7},
      {'name': 'Atlas', 'resultCount': 9},
    ],
    'System.WorkItemType': [
      {'name': 'Task', 'resultCount': 5},
      {'name': 'Bug', 'resultCount': 5},
    ],
    'System.State': [
      {'name': 'Active', 'resultCount': 4},
    ],
    'System.AssignedTo': [
      {'name': 'Ada Lovelace <ada@example.test>', 'resultCount': 3},
    ],
  },
};

PullRequest pullRequest() => PullRequest.fromJson({
  'pullRequestId': 8348,
  'title': 'Search: the data layer',
  'status': 'active',
  'isDraft': false,
  'repository': {
    'id': 'r-1',
    'name': 'boardhop',
    'project': {'id': 'p-scratch', 'name': 'Scratch'},
  },
  'sourceRefName': 'refs/heads/feature/search',
  'targetRefName': 'refs/heads/main',
  'createdBy': {
    'displayName': 'Ada Lovelace',
    'uniqueName': 'ada@example.test',
    'id': 'u-1',
  },
  'creationDate': '2026-09-14T09:00:00.000Z',
});

void main() {
  group('SearchHighlight', () {
    test('markup becomes spans, the hit flagged', () {
      final h = SearchHighlight.parse(
        'system.title',
        'Fix the <highlighthit>boardhop</highlighthit> board',
      );
      expect(h.spans, const [
        SearchSpan('Fix the '),
        SearchSpan('boardhop', isHit: true),
        SearchSpan(' board'),
      ]);
      expect(h.plain, 'Fix the boardhop board');
      expect(h.hasHit, isTrue);
    });

    test('HTML around the hit is stripped and entities decoded', () {
      final h = SearchHighlight.parse(
        'system.description',
        '<p>The <b>phone</b> client for '
            '<highlighthit>boardhop</highlighthit> &amp; friends</p>',
      );
      expect(h.plain, 'The phone client for boardhop & friends');
      expect(h.spans.where((s) => s.isHit).single.text, 'boardhop');
    });

    test('a tag that straddles the marker cannot swallow the match', () {
      final h = SearchHighlight.parse(
        'system.description',
        '<b><highlighthit>term</highlighthit></b> after',
      );
      expect(h.plain, 'term after');
      expect(h.spans.first, const SearchSpan('term', isHit: true));
    });

    test('newlines collapse: a search row is one line', () {
      final h = SearchHighlight.parse(
        'system.history',
        '<div>first</div><div>second <highlighthit>hit</highlighthit></div>',
      );
      expect(h.plain, 'first second hit');
    });

    test('a fragment with no markup is one plain span', () {
      final h = SearchHighlight.parse('system.title', '  Nothing marked  ');
      expect(h.spans, const [SearchSpan('Nothing marked')]);
      expect(h.hasHit, isFalse);
      expect(h.isEmpty, isFalse);
    });

    test('an empty fragment has no spans', () {
      expect(SearchHighlight.parse('system.title', '').isEmpty, isTrue);
      expect(SearchHighlight.parse('system.title', '<p></p>').isEmpty, isTrue);
    });

    test('round trips through JSON, markup and all', () {
      final h = SearchHighlight.parse(
        'system.description',
        'a &lt;tag&gt; and <highlighthit>b &amp; c</highlighthit> end',
      );
      expect(h.plain, 'a <tag> and b & c end');
      final again = SearchHighlight.fromJson(h.toJson());
      expect(again, h);
      expect(again.plain, h.plain);
    });

    test('every fragment of every hit entry is kept', () {
      final all = SearchHighlight.fromHits([
        {
          'fieldReferenceName': 'system.tags',
          'highlights': ['<highlighthit>spike</highlighthit>', 'mobile'],
        },
      ]);
      expect(all, hasLength(2));
      expect(all.first.hasHit, isTrue);
      expect(all.last.hasHit, isFalse);
    });
  });

  group('WorkItemSearchHit', () {
    test('reads the lower-case field names spike s44 recorded', () {
      final hit = WorkItemSearchHit.fromJson(workItemResult());
      expect(hit.id, 15503);
      expect(hit.workItemType, 'Task');
      expect(hit.title, 'Boardhop spike task');
      expect(hit.state, 'Active');
      expect(hit.tags, ['spike', 'mobile']);
      expect(hit.changedDate, DateTime.utc(2026, 9, 14, 10, 11, 12));
      expect(hit.projectName, 'Scratch');
      expect(hit.projectId, 'p-scratch');
    });

    test('assignedTo is parsed out of "Name <email>"', () {
      final hit = WorkItemSearchHit.fromJson(workItemResult());
      expect(hit.assignedTo!.displayName, 'Ada Lovelace');
      expect(hit.assignedTo!.uniqueName, 'ada@example.test');
    });

    test('an unassigned item has no identity', () {
      final raw = workItemResult();
      (raw['fields'] as Map).remove('system.assignedto');
      expect(WorkItemSearchHit.fromJson(raw).assignedTo, isNull);
    });

    test('the shown line prefers a field other than the title', () {
      final hit = WorkItemSearchHit.fromJson(workItemResult());
      expect(hit.highlight!.fieldReferenceName, 'system.description');
    });

    test('a title-only match still shows its line', () {
      final raw = workItemResult();
      raw['hits'] = [
        {
          'fieldReferenceName': 'system.title',
          'highlights': ['<highlighthit>Boardhop</highlighthit> spike task'],
        },
      ];
      expect(
        WorkItemSearchHit.fromJson(raw).highlight!.plain,
        'Boardhop spike task',
      );
    });

    test('no hits at all leaves no line', () {
      final raw = workItemResult()..remove('hits');
      expect(WorkItemSearchHit.fromJson(raw).highlight, isNull);
    });

    test('round trips through JSON so it can be cached', () {
      final hit = WorkItemSearchHit.fromJson(workItemResult());
      final again = WorkItemSearchHit.fromJson(hit.toJson());
      expect(again, hit);
      expect(again.tags, hit.tags);
      expect(again.assignedTo, hit.assignedTo);
      expect(again.changedDate, hit.changedDate);
      expect(again.projectName, hit.projectName);
      expect(again.highlight!.plain, hit.highlight!.plain);
    });
  });

  group('SearchFacets', () {
    test('reads the four work item facets, biggest count first', () {
      final facets = SearchFacets.fromJson(searchResponse()['facets']);
      expect([for (final f in facets.projects) f.name], ['Atlas', 'Scratch']);
      expect(facets.projects.first.count, 9);
      // A tie breaks on the name, so the chips do not wobble.
      expect([for (final f in facets.types) f.name], ['Bug', 'Task']);
      expect(facets.states.single.name, 'Active');
      expect(facets.assignees.single.count, 3);
    });

    test("code search's Project facet lands in projects", () {
      final facets = SearchFacets.fromJson({
        'Project': [
          {'name': 'Atlas', 'resultCount': 2},
        ],
      });
      expect(facets.projects.single.name, 'Atlas');
      expect(facets.types, isEmpty);
    });

    test('no facets at all is empty, and round trips', () {
      expect(SearchFacets.fromJson(null), SearchFacets.empty);
      expect(SearchFacets.empty.isEmpty, isTrue);
      final facets = SearchFacets.fromJson(searchResponse()['facets']);
      expect(SearchFacets.fromJson(facets.toJson()), facets);
    });
  });

  group('SearchResults', () {
    test('carries the total, the page offset and the facets', () {
      final results = SearchResults.fromJson(
        searchResponse(),
        WorkItemSearchHit.fromJson,
        skip: 50,
      );
      expect(results.items.single.id, 15503);
      expect(results.total, 42);
      expect(results.skip, 50);
      expect(results.hasMore, isFalse);
      expect(results.facets.types, hasLength(2));
    });

    test('hasMore while the page does not reach the total', () {
      final results = SearchResults.fromJson(
        searchResponse(),
        WorkItemSearchHit.fromJson,
      );
      expect(results.skip, 0);
      expect(results.hasMore, isTrue);
    });

    test('round trips through JSON', () {
      final results = SearchResults.fromJson(
        searchResponse(),
        WorkItemSearchHit.fromJson,
      );
      final again = SearchResults.fromJson(
        results.toJson((h) => h.toJson()),
        WorkItemSearchHit.fromJson,
      );
      expect(again, results);
    });

    test('the empty result is empty, not a page of nothing', () {
      const empty = SearchResults<WorkItemSearchHit>();
      expect(empty.isEmpty, isTrue);
      expect(empty.total, 0);
      expect(empty.hasMore, isFalse);
      expect(empty.facets, SearchFacets.empty);
    });
  });

  group('PullRequestSearchHit', () {
    test('round trips through JSON with the matched field', () {
      final hit = PullRequestSearchHit(
        pullRequest: pullRequest(),
        match: PrMatchField.branch,
      );
      final again = PullRequestSearchHit.fromJson(hit.toJson());
      expect(again, hit);
      expect(again.pullRequest.sourceBranch, 'feature/search');
      expect(again.pullRequest.createdBy.displayName, 'Ada Lovelace');
      expect(again.pullRequest.projectName, 'Scratch');
      expect(again.match, PrMatchField.branch);
    });
  });
}
