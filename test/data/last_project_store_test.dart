import 'package:boardhop/data/last_project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const last = LastProject(
  accountId: 'kelly@kammcs.com-home',
  org: 'puremedia',
  project: 'DevOps Mobile App',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LastProjectStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = LastProjectStore(prefs: await SharedPreferences.getInstance());
  });

  test('starts empty', () async {
    expect(await store.read(), isNull);
  });

  test('a round trip keeps all three ids', () async {
    await store.write(last);
    final back = await store.read();
    expect(back, isNotNull);
    expect(back!.accountId, 'kelly@kammcs.com-home');
    expect(back.org, 'puremedia');
    expect(back.project, 'DevOps Mobile App');
    expect(back, last);
  });

  test('writing again replaces the memory', () async {
    await store.write(last);
    const other = LastProject(
      accountId: 'kelly@kammcs.com-guest',
      org: 'contoso',
      project: 'Atlas',
    );
    await store.write(other);
    expect(await store.read(), other);
  });

  test('clear removes every key', () async {
    await store.write(last);
    await store.clear();
    expect(await store.read(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LastProjectStore.accountKey), isNull);
    expect(prefs.getString(LastProjectStore.orgKey), isNull);
    expect(prefs.getString(LastProjectStore.projectKey), isNull);
  });

  test('the documented keys are what is written', () async {
    await store.write(last);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('launch.last.account'), 'kelly@kammcs.com-home');
    expect(prefs.getString('launch.last.org'), 'puremedia');
    expect(prefs.getString('launch.last.project'), 'DevOps Mobile App');
  });

  test('a half-written memory is no memory', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LastProjectStore.accountKey, 'u1');
    await prefs.setString(LastProjectStore.orgKey, 'puremedia');
    // No project key: an older build, or a write that did not finish.
    expect(await store.read(), isNull);

    await prefs.setString(LastProjectStore.projectKey, '');
    expect(await store.read(), isNull);

    await prefs.setString(LastProjectStore.projectKey, 'DevOps Mobile App');
    expect((await store.read())?.project, 'DevOps Mobile App');
  });

  test('survives preferences that are not there', () async {
    // Nothing injected, so the calls resolve their own store (or answer
    // empty) rather than throwing into the launch.
    final broken = LastProjectStore();
    expect(await broken.read(), isNull);
    await broken.write(last);
    await broken.clear();
  });
}
