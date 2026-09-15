import 'package:boardhop/core/routes.dart';
import 'package:boardhop/data/last_project.dart';
import 'package:boardhop/data/models/organization.dart';
import 'package:boardhop/data/models/project.dart';
import 'package:boardhop/data/repositories/org_repository.dart';
import 'package:boardhop/data/repositories/project_repository.dart';
import 'package:boardhop/features/launch/launch_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msal_auth/msal_auth.dart' show Account;
import 'package:shared_preferences/shared_preferences.dart';

/// One account's organizations. `remote` null means `refresh()` fails, the
/// way an offline launch or a revoked token does.
class _Orgs extends Fake implements OrgRepository {
  _Orgs(this.cached, {this.remote});

  List<Organization> cached;
  final List<Organization>? remote;
  int refreshes = 0;
  final opened = <String>[];

  @override
  Stream<List<Organization>> watch() => Stream.value(cached);

  @override
  Future<List<Organization>> refresh() async {
    refreshes++;
    final remote = this.remote;
    if (remote == null) throw StateError('organizations unreachable');
    return cached = remote;
  }

  @override
  Future<void> markOpened(String name) async => opened.add(name);
}

class _Projects extends Fake implements ProjectRepository {
  _Projects(this.cached, {this.remote});

  Map<String, List<Project>> cached;
  final Map<String, List<Project>>? remote;
  int refreshes = 0;

  @override
  Stream<List<Project>> watch(String org) =>
      Stream.value(cached[org] ?? const []);

  @override
  Future<List<Project>> refresh(String org, {String? tenantId}) async {
    refreshes++;
    final remote = this.remote;
    if (remote == null) throw StateError('projects unreachable');
    return cached[org] = remote[org] ?? const [];
  }
}

typedef _Account = ({_Orgs orgs, _Projects projects});

Organization _org(String name) => Organization(
  name: name,
  uri: 'https://dev.azure.com/$name/',
  accountId: 'org-$name',
);

Project _project(String name) => Project(id: 'id-$name', name: name);

Account _signedIn(String id) =>
    Account(id: id, username: '$id@example.test', name: id);

/// An account whose organizations and projects are all in the cache.
_Account _cached(Map<String, List<String>> orgsToProjects) => (
  orgs: _Orgs([for (final name in orgsToProjects.keys) _org(name)]),
  projects: _Projects({
    for (final entry in orgsToProjects.entries)
      entry.key: [for (final name in entry.value) _project(name)],
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LastProjectStore store;
  late LaunchNotice notice;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = LastProjectStore(prefs: await SharedPreferences.getInstance());
    notice = LaunchNotice();
  });

  tearDown(() => notice.dispose());

  LaunchResolver resolver(Map<String, _Account> accounts) => LaunchResolver(
    repositoriesFor: (id) {
      final account = accounts[id];
      if (account == null) throw StateError('no repositories for $id');
      return (orgs: account.orgs, projects: account.projects);
    },
    store: store,
    notice: notice,
    cacheTimeout: const Duration(milliseconds: 200),
  );

  test('the remembered project opens, without a network call', () async {
    final u1 = _cached({
      'contoso': ['Atlas', 'Beacon'],
    });
    await store.write(
      const LastProject(
        accountId: 'u1',
        org: 'puremedia',
        project: 'DevOps Mobile App',
      ),
    );

    final target = await resolver({'u1': u1}).resolve([_signedIn('u1')]);

    expect(target.route, Routes.home('u1', 'puremedia', 'DevOps Mobile App'));
    expect(target.fallback, isNull);
    expect(notice.value, isNull);
    // L8: the memory is taken as it is; nothing is verified or fetched.
    expect(u1.orgs.refreshes, 0);
    expect(u1.projects.refreshes, 0);
  });

  test(
    'a remembered account that signed out falls back, and says so',
    () async {
      final u1 = _cached({
        'contoso': ['Atlas', 'Beacon'],
      });
      await store.write(
        const LastProject(accountId: 'gone', org: 'puremedia', project: 'Old'),
      );

      final target = await resolver({'u1': u1}).resolve([_signedIn('u1')]);

      expect(target.route, Routes.home('u1', 'contoso', 'Atlas'));
      expect(target.fallback, const LaunchFallback.accountGone('Atlas'));
      expect(target.fallback!.reason, LaunchFallbackReason.accountGone);
      expect(notice.value, target.fallback);
      // The shell shows it once.
      expect(notice.take(), target.fallback);
      expect(notice.take(), isNull);
    },
  );

  test('a first launch with no memory says nothing', () async {
    final u1 = _cached({
      'contoso': ['Atlas'],
    });
    final target = await resolver({'u1': u1}).resolve([_signedIn('u1')]);

    expect(target.route, Routes.home('u1', 'contoso', 'Atlas'));
    expect(target.fallback, isNull);
    expect(notice.value, isNull);
  });

  test('preferAccountId wins over the memory (L6, add account)', () async {
    final u1 = _cached({
      'contoso': ['Atlas'],
    });
    final u2 = _cached({
      'fabrikam': ['Zephyr'],
    });
    await store.write(
      const LastProject(accountId: 'u1', org: 'contoso', project: 'Atlas'),
    );

    final target = await resolver({'u1': u1, 'u2': u2})
        .resolve([_signedIn('u1'), _signedIn('u2')], preferAccountId: 'u2');

    expect(target.route, Routes.home('u2', 'fabrikam', 'Zephyr'));
    expect(target.fallback, isNull);
  });

  test('an unknown preferAccountId is ignored', () async {
    final u1 = _cached({
      'contoso': ['Atlas'],
    });
    final target = await resolver({'u1': u1})
        .resolve([_signedIn('u1')], preferAccountId: 'not-signed-in');

    expect(target.route, Routes.home('u1', 'contoso', 'Atlas'));
  });

  test('empty caches fall through to the network, once each', () async {
    final u1 = (
      orgs: _Orgs(const [], remote: [_org('contoso')]),
      projects: _Projects(
        {},
        remote: {
          'contoso': [_project('Atlas')],
        },
      ),
    );

    final target = await resolver({'u1': u1}).resolve([_signedIn('u1')]);

    expect(target.route, Routes.home('u1', 'contoso', 'Atlas'));
    expect(u1.orgs.refreshes, 1);
    expect(u1.projects.refreshes, 1);
  });

  test('a refresh that throws degrades to the next account', () async {
    final u1 = (
      orgs: _Orgs(const []), // refresh throws
      projects: _Projects({}),
    );
    final u2 = _cached({
      'fabrikam': ['Zephyr'],
    });

    final target = await resolver({'u1': u1, 'u2': u2})
        .resolve([_signedIn('u1'), _signedIn('u2')]);

    expect(u1.orgs.refreshes, 1);
    expect(target.route, Routes.home('u2', 'fabrikam', 'Zephyr'));
  });

  test('an organization with no projects is skipped', () async {
    final u1 = (
      orgs: _Orgs([_org('empty'), _org('fabrikam')]),
      projects: _Projects(
        {
          'empty': <Project>[],
          'fabrikam': [_project('Zephyr')],
        },
        // `empty` has nothing in the cache, so the network is asked and
        // answers with nothing either.
        remote: {'empty': <Project>[]},
      ),
    );

    final target = await resolver({'u1': u1}).resolve([_signedIn('u1')]);
    expect(target.route, Routes.home('u1', 'fabrikam', 'Zephyr'));
  });

  test('organizations and projects are alphabetical, ignoring case', () async {
    final u1 = _cached({
      'beta': ['Anything'],
      'Alpha': ['zeta', 'Apple', 'beta'],
    });

    final target = await resolver({'u1': u1}).resolve([_signedIn('u1')]);
    expect(target.route, Routes.home('u1', 'Alpha', 'Apple'));
  });

  test('accounts keep the order AuthSignedIn gave them', () async {
    final second = _cached({
      'aaa': ['First alphabetically'],
    });
    final first = _cached({
      'zzz': ['Only this one'],
    });

    final target = await resolver({'first': first, 'second': second})
        .resolve([_signedIn('first'), _signedIn('second')]);
    expect(target.route, Routes.home('first', 'zzz', 'Only this one'));
  });

  test('nothing to open lands on the Accounts page', () async {
    final empty = (
      orgs: _Orgs(const [], remote: const []),
      projects: _Projects({}, remote: const {}),
    );
    expect(
      (await resolver({'u1': empty}).resolve([_signedIn('u1')])).route,
      Routes.orgs,
    );
    expect(
      (await resolver({'u1': empty}).resolve(const [])).route,
      Routes.orgs,
    );
  });

  test('the resolver never throws', () async {
    // Repositories that cannot even be built (an account the app has no
    // bundle for) still answer with a route.
    final target = await resolver(const {}).resolve([_signedIn('u1')]);
    expect(target.route, Routes.orgs);
    expect(target.fallback, isNull);
  });

  test('remember writes the store and the organization, once', () async {
    final u1 = _cached({
      'contoso': ['Atlas'],
    });
    final launch = resolver({'u1': u1});

    await launch.remember('u1', 'contoso', 'Atlas');
    expect(
      await store.read(),
      const LastProject(accountId: 'u1', org: 'contoso', project: 'Atlas'),
    );
    expect(u1.orgs.opened, ['contoso']);

    // Switching tabs inside the same project writes nothing more.
    await launch.remember('u1', 'contoso', 'Atlas');
    expect(u1.orgs.opened, ['contoso']);

    await launch.remember('u1', 'contoso', 'Beacon');
    expect((await store.read())?.project, 'Beacon');
    expect(u1.orgs.opened, ['contoso', 'contoso']);
  });

  test('a resolved memory is not written back again', () async {
    final u1 = _cached({
      'contoso': ['Atlas'],
    });
    await store.write(
      const LastProject(accountId: 'u1', org: 'contoso', project: 'Atlas'),
    );
    final launch = resolver({'u1': u1});
    await launch.resolve([_signedIn('u1')]);

    // The shell enters the project the resolver just named; the store and
    // `lastOpenedAt` are already right.
    await launch.remember('u1', 'contoso', 'Atlas');
    expect(u1.orgs.opened, isEmpty);
  });

  test('forget clears the memory', () async {
    final u1 = _cached({
      'contoso': ['Atlas'],
    });
    final launch = resolver({'u1': u1});
    await launch.remember('u1', 'contoso', 'Atlas');
    await launch.forget();
    expect(await store.read(), isNull);
  });
}
