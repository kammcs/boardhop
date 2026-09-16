import 'package:boardhop/features/pull_requests/diff/diff_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const account = 'kelly@kammcs.com-home';
const other = 'kelly@kammcs.com-work';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('wrapping is off until it is turned on', () async {
    expect(await DiffPrefs.wrap(account), isFalse);
  });

  test('the toggle is remembered', () async {
    await DiffPrefs.setWrap(account, true);
    expect(await DiffPrefs.wrap(account), isTrue);

    await DiffPrefs.setWrap(account, false);
    expect(await DiffPrefs.wrap(account), isFalse);
  });

  test('it is per account', () async {
    await DiffPrefs.setWrap(account, true);
    expect(await DiffPrefs.wrap(other), isFalse);

    await DiffPrefs.setWrap(other, true);
    expect(await DiffPrefs.wrap(account), isTrue);
  });

  test('an empty account writes nothing rather than a shared key', () async {
    await DiffPrefs.setWrap('', true);
    expect(await DiffPrefs.wrap(''), isFalse);
  });
}
