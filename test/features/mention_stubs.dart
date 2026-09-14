import 'package:boardhop/data/mention_recents.dart';
import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/data/models/search.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/people_repository.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/data/repositories/search_repository.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';

/// The repositories a page's mention picker reads, stubbed to answer
/// nothing.
///
/// Every page that carries a composer builds a `MentionSources` in the
/// background (research/16 §4.5), so a test that pumps one of those pages
/// has to provide them or `context.read` throws. Answering with empty lists
/// keeps those tests about what they were about.
class MentionPeople extends Mock implements PeopleRepository {}

class MentionRecentsStub extends Mock implements MentionRecents {}

class MentionSearch extends Mock implements SearchRepository {}

class MentionPullRequests extends Mock implements PullRequestRepository {}

class MentionForms extends Mock implements WorkItemFormRepository {}

/// The stubs, each answering the least interesting true thing.
typedef MentionStubs = ({
  MentionPeople people,
  MentionRecentsStub recents,
  MentionSearch search,
});

/// mocktail needs a stand-in for every non-primitive argument matched with
/// `any()`. Call once from a `setUpAll`, or let [mentionStubs] do it.
void registerMentionFallbacks() {
  registerFallbackValue(const IdentityRef(displayName: 'fallback'));
  registerFallbackValue(PrListFilter.all);
}

MentionStubs mentionStubs({
  MentionPeople? people,
  MentionRecentsStub? recents,
  MentionSearch? search,
}) {
  registerMentionFallbacks();
  final p = people ?? MentionPeople();
  final r = recents ?? MentionRecentsStub();
  final s = search ?? MentionSearch();
  when(() => p.rememberIdentity(any(), any())).thenAnswer((_) async {});
  when(() => p.rememberIdentities(any(), any())).thenAnswer((_) async {});
  when(() => p.identitiesByIds(any(), any()))
      .thenAnswer((_) async => <String, IdentityRef>{});
  when(() => p.identityById(any(), any())).thenAnswer((_) async => null);
  when(() => p.teamMembers(any(), any(), any()))
      .thenAnswer((_) async => <IdentityRef>[]);
  when(() => p.searchPeople(any(), any(), any()))
      .thenAnswer((_) async => <IdentityRef>[]);
  when(() => r.list(any(), any())).thenAnswer((_) async => <IdentityRef>[]);
  when(() => r.add(any(), any(), any()))
      .thenAnswer((_) async => <IdentityRef>[]);
  when(
    () => s.cachedWorkItems(
      any(),
      project: any(named: 'project'),
      text: any(named: 'text'),
    ),
  ).thenAnswer((_) async => null);
  when(
    () => s.searchWorkItems(
      any(),
      project: any(named: 'project'),
      text: any(named: 'text'),
    ),
  ).thenAnswer((_) async => const SearchResults<WorkItemSearchHit>());
  return (people: p, recents: r, search: s);
}

/// Adds the project lookups the picker makes on a mocked form repository.
void stubMentionProject(
  MentionForms forms, {
  String org = 'o',
  String project = 'p',
  String projectId = 'proj',
  String teamId = 'team',
}) {
  when(() => forms.projectId(org, project)).thenAnswer((_) async => projectId);
  when(() => forms.defaultTeamId(org, project)).thenAnswer((_) async => teamId);
}

/// Adds the cached pull request reads the `!` picker makes.
void stubMentionPullRequests(PullRequestRepository prs, {String org = 'o'}) {
  when(
    () => prs.cachedList(
      org,
      project: any(named: 'project'),
      filter: any(named: 'filter'),
      repositoryId: any(named: 'repositoryId'),
    ),
  ).thenAnswer((_) async => null);
  when(
    () => prs.list(
      org,
      project: any(named: 'project'),
      filter: any(named: 'filter'),
      status: any(named: 'status'),
      top: any(named: 'top'),
      repositoryId: any(named: 'repositoryId'),
    ),
  ).thenAnswer((_) async => <PullRequest>[]);
}

/// The providers those stubs sit behind, ready to splice into a test's
/// `MultiRepositoryProvider`.
List<RepositoryProvider<Object>> mentionProviders(MentionStubs stubs) => [
  RepositoryProvider<PeopleRepository>.value(value: stubs.people),
  RepositoryProvider<MentionRecents>.value(value: stubs.recents),
  RepositoryProvider<SearchRepository>.value(value: stubs.search),
];
