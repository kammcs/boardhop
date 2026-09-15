import 'package:boardhop/app.dart';
import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/routes.dart';
import 'package:boardhop/data/last_project.dart';
import 'package:boardhop/data/models/organization.dart';
import 'package:boardhop/data/models/project.dart';
import 'package:boardhop/data/repositories/org_repository.dart';
import 'package:boardhop/data/repositories/project_repository.dart';
import 'package:boardhop/features/launch/launch_redirect.dart';
import 'package:boardhop/features/launch/launch_resolver.dart';
import 'package:boardhop/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:msal_auth/msal_auth.dart' show Account;
import 'package:shared_preferences/shared_preferences.dart';

class _AuthService extends Mock implements AuthService {}

class _Deps extends Mock implements AppDependencies {}

class _Orgs extends Fake implements OrgRepository {
  @override
  Stream<List<Organization>> watch() => Stream.value([
    const Organization(
      name: 'contoso',
      uri: 'https://dev.azure.com/contoso/',
      accountId: 'org-contoso',
    ),
  ]);
}

class _Projects extends Fake implements ProjectRepository {
  @override
  Stream<List<Project>> watch(String org) =>
      Stream.value(const [Project(id: 'p1', name: 'Atlas')]);
}

Account _signedIn(String id) =>
    Account(id: id, username: '$id@example.test', name: id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LaunchResolver resolver;
  late LaunchRedirect redirect;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resolver = LaunchResolver(
      repositoriesFor: (_) => (orgs: _Orgs(), projects: _Projects()),
      store: LastProjectStore(prefs: await SharedPreferences.getInstance()),
      cacheTimeout: const Duration(milliseconds: 200),
    );
    redirect = LaunchRedirect(resolver);
  });

  // research/21 L8: signed in, the splash no longer lands on `/orgs` but on
  // the project the launch resolves.
  test('a signed-in splash redirects to the resolved project', () async {
    final to = await launchRedirect(
      AuthSignedIn([_signedIn('u1')]),
      '/',
      redirect,
    );
    expect(to, Routes.home('u1', 'contoso', 'Atlas'));
  });

  test('the sign-in page redirects the same way once signed in', () async {
    expect(
      await launchRedirect(
        AuthSignedIn([_signedIn('u1')]),
        '/sign-in',
        redirect,
      ),
      Routes.home('u1', 'contoso', 'Atlas'),
    );
  });

  test('the remembered project wins on the splash', () async {
    await resolver.store.write(
      const LastProject(
        accountId: 'u1',
        org: 'puremedia',
        project: 'DevOps Mobile App',
      ),
    );
    expect(
      await launchRedirect(AuthSignedIn([_signedIn('u1')]), '/', redirect),
      Routes.home('u1', 'puremedia', 'DevOps Mobile App'),
    );
  });

  test('a deep link into a project is left alone', () async {
    final project = Routes.home('u1', 'puremedia', 'DevOps Mobile App');
    expect(
      await launchRedirect(AuthSignedIn([_signedIn('u1')]), project, redirect),
      isNull,
    );
    expect(
      await launchRedirect(
        AuthSignedIn([_signedIn('u1')]),
        Routes.orgs,
        redirect,
      ),
      isNull,
    );
    // Nothing was resolved for a route that was never going to move.
    expect(redirect.resolves, 0);
  });

  test('the other auth states are unchanged', () async {
    expect(await launchRedirect(const AuthUnknown(), '/', redirect), isNull);
    expect(await launchRedirect(const AuthUnknown(), '/orgs', redirect), '/');
    expect(await launchRedirect(const AuthBusy(), '/orgs', redirect), isNull);
    expect(
      await launchRedirect(const AuthSignedOut(), '/orgs', redirect),
      '/sign-in',
    );
    expect(
      await launchRedirect(const AuthSignedOut(), '/sign-in', redirect),
      isNull,
    );
  });

  // go_router calls `redirect` several times for one navigation, and again
  // on every `refreshListenable` tick; the launch is resolved once per set
  // of signed-in accounts, not once per call.
  test('the launch resolves once per auth state change', () async {
    final accounts = [_signedIn('u1')];
    for (var i = 0; i < 4; i++) {
      expect(
        await launchRedirect(AuthSignedIn(accounts), '/', redirect),
        Routes.home('u1', 'contoso', 'Atlas'),
      );
    }
    expect(redirect.resolves, 1);

    // A second account signs in: the answer may change, so it is asked
    // again.
    await launchRedirect(
      AuthSignedIn([_signedIn('u1'), _signedIn('u2')]),
      '/',
      redirect,
    );
    expect(redirect.resolves, 2);

    redirect.invalidate();
    await launchRedirect(
      AuthSignedIn([_signedIn('u1'), _signedIn('u2')]),
      '/',
      redirect,
    );
    expect(redirect.resolves, 3);
  });

  // The route the launch hands go_router has to be one the table can match,
  // or a cold start opens the error page.
  test('the resolved route matches the route table', () async {
    final auth = AuthBloc(_AuthService());
    addTearDown(auth.close);
    final router = buildRouter(auth, _Deps(), launch: resolver);
    addTearDown(router.dispose);

    final to = await launchRedirect(
      AuthSignedIn([_signedIn('u1')]),
      '/',
      redirect,
    );
    final match = router.configuration.findMatch(Uri.parse(to!));
    expect(match.isError, isFalse);
    expect(match.pathParameters['account'], 'u1');
    expect(match.pathParameters['org'], 'contoso');
    expect(match.pathParameters['project'], 'Atlas');
  });
}
