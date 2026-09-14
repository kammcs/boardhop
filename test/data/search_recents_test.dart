import 'package:boardhop/data/search_recents.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const account = 'kelly@kammcs.com-home';
const other = 'kelly@kammcs.com-guest';
const org = 'contoso';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SearchRecents recents;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    recents = SearchRecents(
      accountId: account,
      prefs: await SharedPreferences.getInstance(),
    );
  });

  test('starts empty and keeps the newest first', () async {
    expect(await recents.list(org), isEmpty);
    await recents.add(org, 'board');
    await recents.add(org, 'pipeline');
    expect(await recents.list(org), ['pipeline', 'board']);
  });

  test('re-running a query moves it up instead of doubling it', () async {
    await recents.add(org, 'board');
    await recents.add(org, 'pipeline');
    final after = await recents.add(org, '  BOARD ');
    expect(after, ['BOARD', 'pipeline']);
  });

  test('keeps the last ten', () async {
    for (var i = 0; i < 14; i++) {
      await recents.add(org, 'query $i');
    }
    final list = await recents.list(org);
    expect(list, hasLength(SearchRecents.max));
    expect(list.first, 'query 13');
    expect(list.last, 'query 4');
  });

  test('empty text is not remembered', () async {
    await recents.add(org, '   ');
    expect(await recents.list(org), isEmpty);
  });

  test('remove drops one entry, clear drops the organization', () async {
    await recents.add(org, 'board');
    await recents.add(org, 'pipeline');
    expect(await recents.remove(org, 'BOARD '), ['pipeline']);
    await recents.clear(org);
    expect(await recents.list(org), isEmpty);
  });

  test('each organization has its own list', () async {
    await recents.add(org, 'board');
    await recents.add('fabrikam', 'pipeline');
    expect(await recents.list(org), ['board']);
    expect(await recents.list('fabrikam'), ['pipeline']);
  });

  test('signing one account out leaves the other account alone', () async {
    final guest = SearchRecents(
      accountId: other,
      prefs: await SharedPreferences.getInstance(),
    );
    await recents.add(org, 'board');
    await recents.add('fabrikam', 'pipeline');
    await guest.add(org, 'theirs');

    await SearchRecents.clearAccount(
      account,
      prefs: await SharedPreferences.getInstance(),
    );

    expect(await recents.list(org), isEmpty);
    expect(await recents.list('fabrikam'), isEmpty);
    expect(await guest.list(org), ['theirs']);
  });

  test('survives preferences that are not there', () async {
    final broken = SearchRecents(accountId: account);
    // No binding-backed store in this construction path: the calls answer
    // empty rather than throwing into the search page.
    expect(await broken.list(org), isNotNull);
  });
}
