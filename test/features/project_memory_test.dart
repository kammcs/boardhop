import 'package:boardhop/data/last_project.dart';
import 'package:boardhop/data/models/organization.dart';
import 'package:boardhop/data/models/project.dart';
import 'package:boardhop/data/repositories/org_repository.dart';
import 'package:boardhop/data/repositories/project_repository.dart';
import 'package:boardhop/features/launch/launch_resolver.dart';
import 'package:boardhop/features/launch/project_memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Orgs extends Fake implements OrgRepository {
  final opened = <String>[];

  @override
  Stream<List<Organization>> watch() => Stream.value(const []);

  @override
  Future<void> markOpened(String name) async => opened.add(name);
}

class _Projects extends Fake implements ProjectRepository {
  @override
  Stream<List<Project>> watch(String org) => Stream.value(const []);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LastProjectStore store;
  late _Orgs orgs;
  late LaunchResolver resolver;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = LastProjectStore(prefs: await SharedPreferences.getInstance());
    orgs = _Orgs();
    resolver = LaunchResolver(
      repositoriesFor: (_) => (orgs: orgs, projects: _Projects()),
      store: store,
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    required String org,
    String? project,
    bool withResolver = true,
  }) async {
    final memory = ProjectMemory(
      accountId: 'u1',
      org: org,
      project: project,
      child: const SizedBox.shrink(),
    );
    await tester.pumpWidget(
      withResolver
          ? RepositoryProvider<LaunchResolver>.value(
              value: resolver,
              child: memory,
            )
          : memory,
    );
    await tester.pump();
  }

  testWidgets('entering a project route remembers it', (tester) async {
    await pump(tester, org: 'contoso', project: 'Atlas');
    expect(
      await store.read(),
      const LastProject(accountId: 'u1', org: 'contoso', project: 'Atlas'),
    );
    // The older per-account organization memory stays in step.
    expect(orgs.opened, ['contoso']);
  });

  testWidgets('switching tabs inside the project writes nothing more', (
    tester,
  ) async {
    await pump(tester, org: 'contoso', project: 'Atlas');
    // A tab change rebuilds the shell route with the same three ids.
    await pump(tester, org: 'contoso', project: 'Atlas');
    await pump(tester, org: 'contoso', project: 'Atlas');
    expect(orgs.opened, ['contoso']);
  });

  testWidgets('switching project writes again', (tester) async {
    await pump(tester, org: 'contoso', project: 'Atlas');
    await pump(tester, org: 'contoso', project: 'Beacon');
    expect((await store.read())?.project, 'Beacon');
    expect(orgs.opened, ['contoso', 'contoso']);
  });

  testWidgets('an organization-level route leaves the memory alone', (
    tester,
  ) async {
    await pump(tester, org: 'contoso', project: 'Atlas');
    // `/a/u1/orgs/contoso/activity` and friends carry no project.
    await pump(tester, org: 'contoso');
    expect((await store.read())?.project, 'Atlas');
    expect(orgs.opened, ['contoso']);
  });

  testWidgets('without the provider it is a plain pass-through', (
    tester,
  ) async {
    await pump(tester, org: 'contoso', project: 'Atlas', withResolver: false);
    expect(await store.read(), isNull);
  });
}
