import 'dart:convert';
import 'dart:io';

import 'package:boardhop_relay/src/capture.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('relay_capture_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  List<File> filesIn(String name) =>
      Directory('${tmp.path}${Platform.pathSeparator}$name').listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('caps a single file at the body limit and records the truncation', () {
    final store = CaptureStore(tmp, maxBodyBytes: 100);
    final big = '{"eventType":"workitem.updated","pad":"${'x' * 5000}"}';
    store.write('scratch', big, const {'content-type': 'application/json'});

    final stored = jsonDecode(filesIn('scratch').single.readAsStringSync()) as Map<String, Object?>;
    expect(stored['truncated'], isTrue);
    expect(stored['bodyBytes'], big.length);
    // The body could not be parsed once cut, so it is kept as the raw prefix.
    expect(stored['body'], isA<String>());
    expect((stored['body'] as String).length, 100);
    expect(stored['eventType'], 'workitem.updated');
  });

  test('keeps a body under the limit whole', () {
    final store = CaptureStore(tmp, maxBodyBytes: 1024);
    store.write('scratch', '{"eventType":"build.complete","a":1}', const {});
    final stored = jsonDecode(filesIn('scratch').single.readAsStringSync()) as Map<String, Object?>;
    expect(stored['truncated'], isFalse);
    expect((stored['body'] as Map)['a'], 1);
  });

  test('caps the directory at maxFilesPerName, dropping the oldest', () {
    final store = CaptureStore(tmp, maxFilesPerName: 5);
    for (var i = 0; i < 12; i++) {
      store.write('scratch', '{"eventType":"workitem.created","n":$i}', const {});
    }
    final files = filesIn('scratch');
    expect(files, hasLength(5));

    final ns = [for (final f in files) ((jsonDecode(f.readAsStringSync()) as Map)['body'] as Map)['n'] as int]..sort();
    expect(ns, [7, 8, 9, 10, 11], reason: 'the five newest survive');
  });

  test('each capture name has its own directory and its own cap', () {
    final store = CaptureStore(tmp, maxFilesPerName: 2);
    for (var i = 0; i < 4; i++) {
      store.write('scratch', '{"eventType":"a"}', const {});
      store.write('other', '{"eventType":"b"}', const {});
    }
    expect(filesIn('scratch'), hasLength(2));
    expect(filesIn('other'), hasLength(2));
  });

  test('listing is newest first with size and event type', () {
    final store = CaptureStore(tmp);
    store.write('scratch', '{"eventType":"first"}', const {});
    store.write('scratch', '{"eventType":"second"}', const {});
    final list = store.list('scratch');
    expect(list, hasLength(2));
    expect(list.first['eventType'], 'second');
    expect(list.last['eventType'], 'first');
    expect(list.first['bytes'], greaterThan(0));
  });

  test('listing an unseen name is empty, not an error', () {
    expect(CaptureStore(tmp).list('never-used'), isEmpty);
  });

  test('valid names exclude path traversal and empty strings', () {
    expect(CaptureStore.isValidName('scratch'), isTrue);
    expect(CaptureStore.isValidName('scratch-2026_09.13'), isTrue);
    expect(CaptureStore.isValidName(''), isFalse);
    expect(CaptureStore.isValidName('..'), isFalse);
    expect(CaptureStore.isValidName('../etc'), isFalse);
    expect(CaptureStore.isValidName('a/b'), isFalse);
    expect(CaptureStore.isValidName('x' * 65), isFalse);
  });

  test('an event type with slashes cannot escape the directory', () {
    final store = CaptureStore(tmp);
    final f = store.write('scratch', '{"eventType":"../../evil"}', const {});
    expect(f.parent.path, endsWith('scratch'));
    expect(f.uri.pathSegments.last, contains('.._.._evil'));
  });

  test('only the whitelisted headers are kept', () {
    final kept = CaptureStore.headerSubset({
      'Content-Type': 'application/json',
      'Authorization': 'Basic abc',
      'X-VSS-ActivityId': '1',
      'x-vss-subscriptionid': '2',
      'User-Agent': 'VSServices',
      'Cookie': 'nope',
    });
    expect(kept.keys.toSet(), {'content-type', 'x-vss-activityid', 'x-vss-subscriptionid', 'user-agent'});
  });
}
