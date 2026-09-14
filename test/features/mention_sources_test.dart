import 'package:boardhop/core/http/ado_exceptions.dart';
import 'package:boardhop/core/text/mention.dart';
import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/data/models/search.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/pr_diff_source.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:boardhop/features/shared/mention/mention_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'mention_stubs.dart';

class _WorkItems extends Mock implements WorkItemRepository {}

const ada = IdentityRef(displayName: 'Ada Example', id: 'ada-id');
const grace = IdentityRef(displayName: 'Grace Hopper', id: 'grace-id');
const kelly = IdentityRef(
  displayName: 'Kelly Kamm',
  uniqueName: 'kelly@kammcs.com',
  id: 'kelly-id',
);

/// Somebody the Graph search found: a descriptor, no identity id, so they
/// can never be a mention until `resolve` answers (M15).
const stranger = IdentityRef(displayName: 'Radia Perlman', descriptor: 'aad.x');

WorkItem item(int id, String title, {String type = 'Task'}) => WorkItem(
  id: id,
  rev: 1,
  fields: {
    'System.WorkItemType': type,
    'System.Title': title,
    'System.State': 'Active',
  },
);

WorkItemComment comment(int id, IdentityRef by) => WorkItemComment(
  id: id,
  text: 'x',
  renderedText: '<p>x</p>',
  createdBy: by,
  createdDate: DateTime.utc(2026, 9, 14, id),
);

PullRequest pr({
  int id = 8334,
  String title = 'Scratch PR',
  String project = 'DevOps Mobile App',
  List<Map<String, dynamic>> reviewers = const [],
}) => PullRequest.fromJson({
  'pullRequestId': id,
  'title': title,
  'status': 'active',
  'sourceRefName': 'refs/heads/feature/x',
  'targetRefName': 'refs/heads/main',
  'createdBy': {'displayName': 'Kelly Kamm', 'id': 'kelly-id'},
  'reviewers': reviewers,
  'repository': {
    'id': 'repo',
    'name': 'scratch',
    'project': {'id': 'proj', 'name': project},
  },
});

PrThread thread(int id, List<IdentityRef?> authors) => PrThread(
  id: id,
  status: PrThreadStatus.active,
  filePath: null,
  rightLine: null,
  leftLine: null,
  trackedFromLine: null,
  comments: [
    for (final author in authors)
      PrComment(
        id: id,
        author: author?.displayName ?? '?',
        content: 'c',
        identity: author,
      ),
  ],
);

void main() {
  late MentionStubs stubs;
  late MentionForms forms;
  late MentionPullRequests prs;
  late _WorkItems workItems;

  MentionSources build({
    String project = 'DevOps Mobile App',
    List<WorkItem> Function()? extra,
  }) => MentionSources(
    org: 'o',
    project: project,
    people: stubs.people,
    forms: forms,
    recents: stubs.recents,
    workItems: workItems,
    pullRequests: prs,
    search: stubs.search,
    extraWorkItems: extra,
  );

  setUp(() {
    stubs = mentionStubs();
    forms = MentionForms();
    prs = MentionPullRequests();
    workItems = _WorkItems();
    stubMentionProject(forms, project: 'DevOps Mobile App');
    stubMentionPullRequests(prs);
    when(() => workItems.watchList(any(), any(), any()))
        .thenAnswer((_) => Stream<List<WorkItem>>.value(const []));
  });

  group('participants', () {
    test('a work item lists its commenters newest first, then the people '
        'on the item', () {
      final found = MentionSources.workItemParticipants(
        item: WorkItem(
          id: 1,
          rev: 1,
          fields: {
            'System.AssignedTo': {
              'displayName': 'Grace Hopper',
              'id': 'grace-id',
            },
            'System.CreatedBy': {'displayName': 'Kelly Kamm', 'id': 'kelly-id'},
          },
        ),
        comments: [comment(1, kelly), comment(2, ada)],
      );
      expect(found.map((p) => p.id), ['ada-id', 'kelly-id', 'grace-id']);
    });

    test('a person without an identity id is never offered', () {
      final found = MentionSources.workItemParticipants(
        item: WorkItem(
          id: 1,
          rev: 1,
          // The legacy `"Name <mail>"` form carries no GUID, and a mention
          // without one notifies nobody.
          fields: const {'System.CreatedBy': 'Someone Else <someone@x.test>'},
        ),
        comments: [comment(1, ada)],
      );
      expect(found.map((p) => p.id), ['ada-id']);
    });

    test('a pull request puts this thread first, then the author, the '
        'reviewers and everybody else', () {
      final found = MentionSources.pullRequestParticipants(
        pr: pr(
          reviewers: [
            {'id': 'grace-id', 'displayName': 'Grace Hopper'},
            {'id': 'team-id', 'displayName': 'A team', 'isContainer': true},
          ],
        ),
        threads: [
          thread(1, [ada]),
          thread(2, [grace]),
        ],
        thread: thread(2, [grace]),
      );
      expect(found.map((p) => p.id), ['grace-id', 'kelly-id', 'ada-id']);
      expect(found.map((p) => p.id), isNot(contains('team-id')));
    });
  });

  group('work items', () {
    test('matches the cached lists by id prefix and by title, without '
        'searching anything', () async {
      when(() => workItems.watchList('o', 'DevOps Mobile App', any()))
          .thenAnswer(
            (_) => Stream<List<WorkItem>>.value([
              item(15545, 'Mentions phase C'),
              item(9001, 'Board polish'),
            ]),
          );
      final sources = build();

      final byId = await sources.workItemMatches('15');
      expect(byId.map((a) => a.id), ['15545']);
      expect(byId.single.label, '#15545');
      expect(byId.single.typeName, 'Task');

      final byTitle = await sources.workItemMatches('me');
      expect(byTitle.map((a) => a.id), ['15545']);
      verifyNever(
        () => stubs.search.searchWorkItems(
          any(),
          project: any(named: 'project'),
          text: any(named: 'text'),
        ),
      );
    });

    test('from three characters the search hits follow the cached ones, '
        'never twice', () async {
      when(() => workItems.watchList('o', 'DevOps Mobile App', any()))
          .thenAnswer(
            (_) =>
                Stream<List<WorkItem>>.value([item(15545, 'Mentions phase C')]),
          );
      when(
        () => stubs.search.searchWorkItems(
          'o',
          project: any(named: 'project'),
          text: any(named: 'text'),
        ),
      ).thenAnswer(
        (_) async => const SearchResults<WorkItemSearchHit>(
          items: [
            // The same item the cache already offered, and a new one.
            WorkItemSearchHit(
              id: 15545,
              workItemType: 'Task',
              title: 'Mentions phase C',
              state: 'Active',
              projectName: 'DevOps Mobile App',
              projectId: 'proj',
            ),
            WorkItemSearchHit(
              id: 15550,
              workItemType: 'Bug',
              title: 'Mentions elsewhere',
              state: 'New',
              projectName: 'DevOps Mobile App',
              projectId: 'proj',
            ),
          ],
        ),
      );

      final found = await build().workItemMatches('men');
      expect(found.map((a) => a.id), ['15545', '15550']);
      expect(found.last.typeName, 'Bug');
    });

    test(
      'the stored answer for the same query is used before the API',
      () async {
        when(
          () => stubs.search.cachedWorkItems(
            'o',
            project: any(named: 'project'),
            text: any(named: 'text'),
          ),
        ).thenAnswer(
          (_) async => (
            value: const SearchResults<WorkItemSearchHit>(
              items: [
                WorkItemSearchHit(
                  id: 15551,
                  workItemType: 'Task',
                  title: 'From the cache',
                  state: 'Active',
                  projectName: 'DevOps Mobile App',
                  projectId: 'proj',
                ),
              ],
            ),
            fetchedAt: DateTime.utc(2026, 9, 14),
          ),
        );
        final found = await build().workItemMatches('men');
        expect(found.map((a) => a.id), ['15551']);
        verifyNever(
          () => stubs.search.searchWorkItems(
            any(),
            project: any(named: 'project'),
            text: any(named: 'text'),
          ),
        );
      },
    );

    test('the page\'s own items are offered first and a refused search is '
        'not an error', () async {
      when(
        () => stubs.search.searchWorkItems(
          any(),
          project: any(named: 'project'),
          text: any(named: 'text'),
        ),
      ).thenThrow(const AdoForbiddenException('no search here'));
      final found = await build(extra: () => [item(15600, 'Linked item')])
          .workItemMatches('link');
      expect(found.map((a) => a.id), ['15600']);
    });
  });

  group('pull requests', () {
    test('matches the cached active list by id and title, inside this '
        'project only', () async {
      when(
        () => prs.cachedList(
          'o',
          project: any(named: 'project'),
          filter: any(named: 'filter'),
          repositoryId: any(named: 'repositoryId'),
        ),
      ).thenAnswer(
        (_) async => (
          items: [
            pr(),
            pr(id: 8400, title: 'Another project', project: 'Elsewhere'),
          ],
          fetchedAt: DateTime.utc(2026, 9, 14),
          fromCache: true,
        ),
      );
      final sources = build();
      expect((await sources.pullRequestMatches('83')).map((a) => a.label), [
        '!8334',
      ]);
      expect((await sources.pullRequestMatches('scratch')).map((a) => a.id), [
        '8334',
      ]);
      expect(await sources.pullRequestMatches('nothing'), isEmpty);
    });

    test(
      'with nothing cached it reads the list once, and never searches',
      () async {
        when(
          () => prs.list(
            'o',
            project: any(named: 'project'),
            filter: any(named: 'filter'),
            status: any(named: 'status'),
            top: any(named: 'top'),
            repositoryId: any(named: 'repositoryId'),
          ),
        ).thenAnswer((_) async => [pr()]);
        final sources = build();
        expect((await sources.pullRequestMatches('8')).map((a) => a.id), [
          '8334',
        ]);
        expect((await sources.pullRequestMatches('83')).map((a) => a.id), [
          '8334',
        ]);
        verify(
          () => prs.list(
            'o',
            project: any(named: 'project'),
            filter: any(named: 'filter'),
            status: any(named: 'status'),
            top: any(named: 'top'),
            repositoryId: any(named: 'repositoryId'),
          ),
        ).called(1);
      },
    );
  });

  group('the source', () {
    test('reads the team once however many composers ask', () async {
      when(() => stubs.people.teamMembers('o', 'proj', 'team'))
          .thenAnswer((_) async => const [ada, kelly]);
      final sources = build();
      final source = sources.source(
        participants: () async => const [grace],
        participantReason: MentionSources.onThisItem,
      );
      expect(await source.members!(), const [ada, kelly]);
      expect(await source.members!(), const [ada, kelly]);
      verify(() => stubs.people.teamMembers('o', 'proj', 'team')).called(1);
      expect(source.participantReason, 'On this item');
      expect(await source.participants!(), const [grace]);
    });

    test('a refused team read leaves the band empty and is retried', () async {
      when(() => stubs.people.teamMembers('o', 'proj', 'team'))
          .thenThrow(const AdoForbiddenException('no team for you'));
      final sources = build();
      expect(await sources.members(), isEmpty);
      expect(await sources.members(), isEmpty);
      verify(() => stubs.people.teamMembers('o', 'proj', 'team')).called(2);
    });

    test('picking somebody remembers them for this project and for the '
        'read side', () async {
      build().remember(kelly);
      await Future<void>.delayed(Duration.zero);
      verify(() => stubs.recents.add('o', 'DevOps Mobile App', kelly))
          .called(1);
      verify(() => stubs.people.rememberIdentity('o', kelly)).called(1);
    });

    test(
      'me is the team member row, so it carries the GUID and the avatar',
      () async {
        when(() => stubs.people.teamMembers('o', 'proj', 'team'))
            .thenAnswer((_) async => const [ada, kelly]);
        expect(await build().me(uniqueName: 'KELLY@kammcs.com'), kelly);
        expect(await build().me(id: 'ada-id'), ada);
      },
    );

    test('a person the team does not carry is looked up by id', () async {
      when(() => stubs.people.identityById('o', 'someone-else'))
          .thenAnswer((_) async => grace);
      expect(await build().me(id: 'someone-else'), grace);
    });

    test(
      'the Graph search is scoped to the project id, never its name',
      () async {
        await build().searchPeople('kel');
        verify(() => stubs.people.searchPeople('o', 'proj', 'kel')).called(1);
      },
    );

    test('a suggestion with no identity id is what resolve is for', () {
      expect(stranger.id, isNull);
      final source = build().source(
        participants: () async => const [stranger],
        participantReason: MentionSources.onThisPullRequest,
      );
      expect(source.resolve, isNotNull);
      expect(source.supports(MentionKind.person), isTrue);
      expect(source.supports(MentionKind.workItem), isTrue);
      expect(source.supports(MentionKind.pullRequest), isTrue);
    });
  });

  group('names for the read side', () {
    test('every GUID in the bodies, and nothing when there are none', () async {
      when(() => stubs.people.identitiesByIds('o', any()))
          .thenAnswer((_) async => const {'kelly-id': kelly});
      expect(
        await MentionSources.namesFor(stubs.people, 'o', const [
          'plain text',
          'no mentions here',
        ]),
        isEmpty,
      );
      verifyNever(() => stubs.people.identitiesByIds(any(), any()));

      const guid = '11111111-2222-3333-4444-555555555555';
      when(() => stubs.people.identitiesByIds('o', any()))
          .thenAnswer((_) async => const {guid: kelly});
      expect(
        await MentionSources.namesFor(stubs.people, 'o', [
          'hi @<$guid>',
          'again @<${guid.toUpperCase()}>',
        ]),
        {guid: 'Kelly Kamm'},
      );
    });
  });
}
