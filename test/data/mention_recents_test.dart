import 'package:boardhop/data/mention_recents.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const account = 'kelly@kammcs.com-home';
const other = 'kelly@kammcs.com-guest';
const org = 'contoso';
const project = 'Scratch';
const otherProject = 'Atlas';

/// Synthetic identities only.
const adaId = '2f1b1a70-6d24-4c0a-9f0b-6b6d2f9a1c33';
const bayId = '8c4d5e6f-1122-4333-8444-55556666aaaa';

const ada = IdentityRef(
  displayName: 'Ada Example',
  uniqueName: 'ada@example.test',
  id: adaId,
  descriptor: 'aad.QWRh',
);
const bay = IdentityRef(
  displayName: 'Bay Wilkins',
  uniqueName: 'bay@example.test',
  id: bayId,
);

IdentityRef _person(int n) =>
    IdentityRef(displayName: 'Person $n', id: 'id-$n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MentionRecents recents;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    recents = MentionRecents(
      accountId: account,
      prefs: await SharedPreferences.getInstance(),
    );
  });

  test('starts empty and keeps the newest first', () async {
    expect(await recents.list(org, project), isEmpty);
    await recents.add(org, project, ada);
    await recents.add(org, project, bay);
    expect((await recents.list(org, project)).map((p) => p.displayName), [
      'Bay Wilkins',
      'Ada Example',
    ]);
  });

  test('a round trip keeps every field the picker draws', () async {
    await recents.add(org, project, ada);
    final back = (await recents.list(org, project)).single;
    expect(back.displayName, 'Ada Example');
    expect(back.uniqueName, 'ada@example.test');
    expect(back.id, adaId);
    expect(back.descriptor, 'aad.QWRh');
  });

  test('mentioning the same person again moves them up, once', () async {
    await recents.add(org, project, ada);
    await recents.add(org, project, bay);
    await recents.add(org, project, ada);
    expect((await recents.list(org, project)).map((p) => p.id), [adaId, bayId]);
  });

  test('the same GUID under a new display name replaces the old row', () async {
    await recents.add(org, project, ada);
    await recents.add(
      org,
      project,
      const IdentityRef(displayName: 'Ada E.', id: adaId),
    );
    final list = await recents.list(org, project);
    expect(list, hasLength(1));
    expect(list.single.displayName, 'Ada E.');
  });

  test('a person with no GUID dedups on the address, case-folded', () async {
    const lower = IdentityRef(
      displayName: 'Ada Example',
      uniqueName: 'ada@example.test',
    );
    const upper = IdentityRef(
      displayName: 'Ada Example',
      uniqueName: 'ADA@EXAMPLE.TEST',
    );
    await recents.add(org, project, lower);
    await recents.add(org, project, upper);
    expect(await recents.list(org, project), hasLength(1));
  });

  test('only the last five are kept', () async {
    for (var n = 1; n <= 8; n++) {
      await recents.add(org, project, _person(n));
    }
    final list = await recents.list(org, project);
    expect(list, hasLength(MentionRecents.max));
    expect(list.first.displayName, 'Person 8');
    expect(list.last.displayName, 'Person 4');
  });

  test('projects, organizations and accounts do not share a list', () async {
    await recents.add(org, project, ada);
    expect(await recents.list(org, otherProject), isEmpty);
    expect(await recents.list('other-org', project), isEmpty);

    final guest = MentionRecents(
      accountId: other,
      prefs: await SharedPreferences.getInstance(),
    );
    expect(await guest.list(org, project), isEmpty);
    await guest.add(org, project, bay);
    expect((await recents.list(org, project)).single.id, adaId);
  });

  test('clear empties one project, clearAccount every one', () async {
    await recents.add(org, project, ada);
    await recents.add(org, otherProject, bay);
    await recents.clear(org, project);
    expect(await recents.list(org, project), isEmpty);
    expect(await recents.list(org, otherProject), hasLength(1));

    await recents.add(org, project, ada);
    await MentionRecents.clearAccount(
      account,
      prefs: await SharedPreferences.getInstance(),
    );
    expect(await recents.list(org, project), isEmpty);
    expect(await recents.list(org, otherProject), isEmpty);
  });

  test('a nameless person without a GUID is not remembered', () async {
    await recents.add(org, project, const IdentityRef(displayName: '  '));
    expect(await recents.list(org, project), isEmpty);
  });

  test('a row that cannot be decoded is skipped, not fatal', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(MentionRecents.keyFor(account, org, project), [
      'not json',
      '{"displayName":"Ada Example","id":"$adaId"}',
    ]);
    expect((await recents.list(org, project)).single.id, adaId);
  });

  test('survives preferences that are not there', () async {
    // Nothing is injected on this construction path, so the calls resolve
    // their own store (or answer empty) rather than throwing into a composer.
    final broken = MentionRecents(accountId: account);
    expect(await broken.list(org, project), isNotNull);
    expect(await broken.add(org, project, ada), isNotNull);
    await broken.clear(org, project);
  });
}
