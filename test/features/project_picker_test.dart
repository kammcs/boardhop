import 'package:boardhop/app.dart';
import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/routes.dart';
import 'package:boardhop/data/avatar_store.dart';
import 'package:boardhop/data/models/organization.dart';
import 'package:boardhop/data/models/project.dart';
import 'package:boardhop/data/repositories/account_repository.dart';
import 'package:boardhop/data/repositories/activity_repository.dart';
import 'package:boardhop/data/repositories/org_repository.dart';
import 'package:boardhop/data/repositories/project_repository.dart';
import 'package:boardhop/features/launch/launch_hooks.dart';
import 'package:boardhop/features/projects/widgets/project_picker.dart';
import 'package:boardhop/features/projects/widgets/project_picker_button.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/features/shared/widgets/ado_tile.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:msal_auth/msal_auth.dart';

import 'root_tab_stubs.dart';

class _Deps extends Mock implements AppDependencies {}

class _AccountDeps extends Mock implements AccountDeps {}

class _Orgs extends Mock implements OrgRepository {}

class _Projects extends Mock implements ProjectRepository {}

class _AccountRepo extends Mock implements AccountRepository {}

class _Avatars extends Mock implements AvatarStore {}

class _Activity extends Mock implements ActivityRepository {}

class _AuthService extends Mock implements AuthService {}

Account _account(String id) =>
    Account(id: id, username: '$id@kammcs.com', name: id);

Project _project(String name) => Project(id: 'p-$name', name: name);

Organization _organization(String name) => Organization(
  name: name,
  uri: 'https://dev.azure.com/$name/',
  accountId: 'a-$name',
);

/// What the signed-in accounts can see: account id → organization → projects.
typedef World = Map<String, Map<String, List<String>>>;

/// The whole per-account dependency bundle the picker reads, mocked.
_Deps _buildDeps(World world, {int unread = 0}) {
  final deps = _Deps();
  for (final entry in world.entries) {
    final orgs = _Orgs();
    when(orgs.watch).thenAnswer(
      (_) => Stream.value([for (final o in entry.value.keys) _organization(o)]),
    );
    when(orgs.refresh).thenAnswer((_) async => const <Organization>[]);

    final projects = _Projects();
    when(() => projects.watch(any())).thenAnswer((invocation) {
      final org = invocation.positionalArguments.first as String;
      return Stream.value([
        for (final name in entry.value[org] ?? const <String>[]) _project(name),
      ]);
    });
    when(() => projects.refresh(any(), tenantId: any(named: 'tenantId')))
        .thenAnswer((_) async => const <Project>[]);

    final account = _AccountRepo();
    when(account.cached).thenAnswer((_) async => null);
    when(account.cachedPhoto).thenReturn(null);
    when(account.photo).thenAnswer((_) async => null);

    final activity = _Activity();
    when(() => activity.unread(any())).thenAnswer((_) => Stream.value(unread));

    final bundle = _AccountDeps();
    when(() => bundle.orgs).thenReturn(orgs);
    when(() => bundle.projects).thenReturn(projects);
    when(() => bundle.account).thenReturn(account);
    when(() => bundle.avatars).thenReturn(_Avatars());
    when(() => bundle.activity).thenReturn(activity);
    when(() => deps.forAccount(entry.key)).thenReturn(bundle);
  }
  return deps;
}

/// An `AuthService` signed in with [accounts], whose list follows sign-out
/// and add-account the way MSAL's does.
_AuthService _authService(List<Account> accounts) {
  final service = _AuthService();
  final remaining = [...accounts];
  when(() => service.isConfigured).thenReturn(true);
  when(service.accounts).thenAnswer((_) async => [...remaining]);
  when(() => service.knownAccounts).thenReturn(remaining);
  when(() => service.removeAccount(any())).thenAnswer((invocation) async {
    final id = invocation.positionalArguments.first as String;
    remaining.removeWhere((a) => a.id == id);
  });
  return service;
}

void main() {
  final gone = <String>[];
  final pushed = <String>[];
  var closed = 0;
  String? preferred;

  setUp(() {
    gone.clear();
    pushed.clear();
    closed = 0;
    preferred = null;
  });

  /// The picker's body, pumped straight (no sheet) with the navigation and
  /// the landing resolver replaced by recorders.
  Future<AuthBloc> pumpPicker(
    WidgetTester tester, {
    required World world,
    List<String> accountIds = const ['u1'],
    String currentAccount = 'u1',
    String org = 'contoso',
    String project = 'Scratch',
    bool showDiagnostics = true,
    int unread = 0,
    String landing = '/landed',
    AuthService? service,
    Size size = const Size(402, 2400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final accounts = [for (final id in accountIds) _account(id)];
    final auth = AuthBloc(service ?? _authService(accounts))
      ..add(const AuthStarted());
    addTearDown(auth.close);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AppDependencies>.value(
            value: _buildDeps(world, unread: unread),
          ),
        ],
        child: BlocProvider<AuthBloc>.value(
          value: auth,
          child: MaterialApp(
            theme: BoardhopTheme.light(),
            home: Scaffold(
              body: BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) => state is AuthSignedIn
                    ? ProjectPickerContent(
                        currentAccountId: currentAccount,
                        org: org,
                        project: project,
                        showDiagnostics: showDiagnostics,
                        onClose: () => closed++,
                        go: gone.add,
                        push: pushed.add,
                        resolveLanding: (accounts, {preferAccountId}) async {
                          preferred = preferAccountId;
                          return landing;
                        },
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  group('the picker lists what is signed in (L1)', () {
    testWidgets('accounts, then organizations and projects by name', (
      tester,
    ) async {
      await pumpPicker(
        tester,
        world: {
          'u1': {
            'zulu': ['Widgets'],
            'contoso': ['zeta', 'Alpha', 'Scratch'],
          },
        },
      );

      // The account's own row carries its email and a way out.
      expect(find.text('u1@kammcs.com'), findsOneWidget);
      expect(find.byTooltip('Sign out'), findsOneWidget);

      // Organizations by name, case-insensitively, whatever order the
      // repository emitted them in.
      expect(
        tester.getTopLeft(find.text('contoso')).dy,
        lessThan(tester.getTopLeft(find.text('zulu')).dy),
      );
      // And the projects under each, the same way.
      expect(
        tester.getTopLeft(find.text('Alpha')).dy,
        lessThan(tester.getTopLeft(find.text('Scratch')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Scratch')).dy,
        lessThan(tester.getTopLeft(find.text('zeta')).dy),
      );
      // Every project row carries the tile Azure DevOps draws for it.
      expect(find.byType(AdoTile), findsNWidgets(6));
    });

    testWidgets('only the current account, org and project is ticked', (
      tester,
    ) async {
      await pumpPicker(
        tester,
        accountIds: const ['u1', 'u2'],
        world: {
          'u1': {
            'contoso': ['Scratch', 'Other'],
          },
          // The same project name under another account is not the one.
          'u2': {
            'contoso': ['Scratch'],
          },
        },
      );

      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(
        find.descendant(
          of: find
              .ancestor(
                of: find.byIcon(Icons.check),
                matching: find.byType(ListTile),
              )
              .first,
          matching: find.text('Scratch'),
        ),
        findsOneWidget,
      );
      expect(find.text('u2@kammcs.com'), findsOneWidget);
    });

    testWidgets('a project row closes the picker and opens its Home', (
      tester,
    ) async {
      await pumpPicker(
        tester,
        world: {
          'u1': {
            'contoso': ['Scratch', 'Other'],
          },
        },
      );

      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();

      expect(closed, 1);
      expect(gone, [Routes.home('u1', 'contoso', 'Other')]);
    });
  });

  group('the filter', () {
    testWidgets('stays away at eight projects', (tester) async {
      await pumpPicker(
        tester,
        world: {
          'u1': {
            'contoso': [for (var i = 1; i <= 8; i++) 'Project $i'],
          },
        },
      );
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('appears at nine', (tester) async {
      await pumpPicker(
        tester,
        world: {
          'u1': {
            'contoso': [for (var i = 1; i <= 9; i++) 'Project $i'],
          },
        },
      );
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('narrows the rows by name and keeps the org as a header', (
      tester,
    ) async {
      await pumpPicker(
        tester,
        world: {
          'u1': {
            'contoso': [
              'Scratch',
              for (var i = 1; i <= 8; i++) 'Project $i',
              'Borrowed',
            ],
          },
        },
      );

      await tester.enterText(find.byType(TextField), 'scratch');
      await tester.pumpAndSettle();

      expect(find.text('Scratch'), findsOneWidget);
      expect(find.text('Borrowed'), findsNothing);
      expect(find.text('Project 1'), findsNothing);
      // The organization is still the heading over what is left.
      expect(find.text('contoso'), findsOneWidget);
    });
  });

  group('the bottom rows', () {
    testWidgets('are all there, Diagnostics only in a local build', (
      tester,
    ) async {
      await pumpPicker(
        tester,
        world: {
          'u1': {
            'contoso': ['Scratch'],
          },
        },
      );

      expect(find.text('Add account'), findsOneWidget);
      // L3 revised: no Manage accounts row and no link to the project list.
      expect(find.text('Manage accounts'), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      await tester.tap(find.text('contoso'));
      await tester.pumpAndSettle();
      expect(gone, isEmpty);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Diagnostics'), findsOneWidget);

      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      expect(pushed, [Routes.activity('u1', 'contoso')]);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(pushed.last, '/settings');
    });

    testWidgets('a store build has no Diagnostics row', (tester) async {
      await pumpPicker(
        tester,
        showDiagnostics: false,
        world: {
          'u1': {
            'contoso': ['Scratch'],
          },
        },
      );

      expect(find.text('Diagnostics'), findsNothing);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('Activity carries the unread dot', (tester) async {
      await pumpPicker(
        tester,
        unread: 3,
        world: {
          'u1': {
            'contoso': ['Scratch'],
          },
        },
      );

      final badge = tester.widget<Badge>(
        find
            .ancestor(
              of: find.byIcon(Icons.notifications_outlined),
              matching: find.byType(Badge),
            )
            .first,
      );
      expect(badge.isLabelVisible, isTrue);
      expect(find.text('3 new'), findsOneWidget);
    });
  });

  group('account changes (L6)', () {
    testWidgets('signing one out lands on what the resolver answers', (
      tester,
    ) async {
      final service = _authService([_account('u1'), _account('u2')]);
      await pumpPicker(
        tester,
        service: service,
        accountIds: const ['u1', 'u2'],
        landing: '/a/u2/orgs/contoso/projects/Other/home',
        world: {
          'u1': {
            'contoso': ['Scratch'],
          },
          'u2': {
            'contoso': ['Other'],
          },
        },
      );

      await tester.tap(find.byTooltip('Sign out').first);
      await tester.pumpAndSettle();

      verify(() => service.removeAccount('u1')).called(1);
      expect(closed, 1);
      expect(gone, ['/a/u2/orgs/contoso/projects/Other/home']);
    });

    testWidgets('the last account signing out leaves the router alone', (
      tester,
    ) async {
      final service = _authService([_account('u1')]);
      await pumpPicker(
        tester,
        service: service,
        world: {
          'u1': {
            'contoso': ['Scratch'],
          },
        },
      );

      await tester.tap(find.byTooltip('Sign out'));
      await tester.pumpAndSettle();

      verify(() => service.removeAccount('u1')).called(1);
      // AuthSignedOut redirects to sign-in on its own (research/21 L6).
      expect(gone, isEmpty);
    });

    testWidgets('adding an account lands on that account', (tester) async {
      final accounts = [_account('u1')];
      final service = _authService(accounts);
      when(() => service.signIn(loginHint: any(named: 'loginHint')))
          .thenAnswer((_) async {
            service.knownAccounts.add(_account('u3'));
            return AuthenticationResult(
              accessToken: 'token',
              authenticationScheme: 'Bearer',
              expiresOn: DateTime.utc(2026, 9, 15),
              idToken: null,
              authority: 'https://login.microsoftonline.com/organizations',
              tenantId: null,
              scopes: const [],
              correlationId: null,
              account: _account('u3'),
            );
          });
      await pumpPicker(
        tester,
        service: service,
        landing: '/a/u3/orgs/fabrikam/projects/First/home',
        world: {
          'u1': {
            'contoso': ['Scratch'],
          },
        },
      );

      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();

      expect(closed, 1);
      expect(preferred, 'u3');
      expect(gone, ['/a/u3/orgs/fabrikam/projects/First/home']);
    });
  });

  group('the button in the leading slot (L4)', () {
    Future<void> pumpTab(WidgetTester tester, {required Size size}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final auth = AuthBloc(_authService([_account('u1')]))
        ..add(const AuthStarted());
      addTearDown(auth.close);
      final router = GoRouter(
        initialLocation: '/a/u1/orgs/contoso/projects/Scratch/home',
        routes: [
          GoRoute(
            path: '/a/:account/orgs/:org/projects/:project/home',
            builder: (_, state) => Scaffold(
              appBar: AppBar(
                leadingWidth: ProjectPickerButton.leadingWidth,
                leading: ProjectPickerButton(
                  org: state.pathParameters['org']!,
                  project: state.pathParameters['project']!,
                ),
                title: const Text('Scratch'),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<AppDependencies>.value(
              value: _buildDeps({
                'u1': {
                  'contoso': ['Scratch', 'Other'],
                },
              }),
            ),
            ...rootChromeProviders(
              projects: stubProjects([_project('Scratch')]),
            ),
          ],
          child: BlocProvider<AuthBloc>.value(
            value: auth,
            child: MaterialApp.router(
              theme: BoardhopTheme.light(),
              routerConfig: router,
              builder: (context, child) =>
                  AccountScope(accountId: 'u1', child: child!),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('is the project tile with a chevron and opens the sheet', (
      tester,
    ) async {
      await pumpTab(tester, size: const Size(402, 874));

      expect(find.byType(AdoTile), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
      // The hit target is a full 48 dp even though the tile is 28.
      final size = tester.getSize(find.byTooltip('Switch project'));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));

      await tester.tap(find.byTooltip('Switch project'));
      await tester.pumpAndSettle();

      expect(find.byType(ProjectPickerContent), findsOneWidget);
      // A phone gets the draggable sheet (L2).
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
    });

    testWidgets('registers the picker with the shell L7 hook', (tester) async {
      LaunchHooks.onChooseAnotherProject = null;
      addTearDown(() => LaunchHooks.onChooseAnotherProject = null);
      await pumpTab(tester, size: const Size(402, 874));

      expect(LaunchHooks.canChooseProject, isTrue);
      // "Choose another project" hands the shell's own context back.
      LaunchHooks.chooseAnotherProject(
        tester.element(find.byType(ProjectPickerButton)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProjectPickerContent), findsOneWidget);
    });

    testWidgets('a tablet gets the panel anchored under the tile (L2)', (
      tester,
    ) async {
      await pumpTab(tester, size: const Size(1280, 800));

      await tester.tap(find.byTooltip('Switch project'));
      await tester.pumpAndSettle();

      expect(find.byType(DraggableScrollableSheet), findsNothing);
      final panel = find.byType(ProjectPickerContent);
      expect(panel, findsOneWidget);
      final box = tester.getRect(panel);
      expect(box.width, lessThanOrEqualTo(kProjectPickerPanelWidth));
      expect(box.height, lessThanOrEqualTo(800 * 0.7));
      // Under the leading slot, not centred on the window.
      final button = tester.getRect(find.byTooltip('Switch project'));
      expect(box.top, greaterThanOrEqualTo(button.bottom));
      expect(box.left, lessThan(button.right));

      // Escape closes it, and so does a tap on the scrim.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ProjectPickerContent), findsNothing);

      await tester.tap(find.byTooltip('Switch project'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(1200, 700));
      await tester.pumpAndSettle();
      expect(find.byType(ProjectPickerContent), findsNothing);
    });
  });
}
