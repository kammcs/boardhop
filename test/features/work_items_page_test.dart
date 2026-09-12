import 'package:boardhop/features/work_items/work_items_page.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('after a create', () {
    test('the two-pane layout opens the new item in the detail pane', () {
      expect(selectionAfterCreate(15555, Breakpoint.medium), 15555);
      expect(selectionAfterCreate(15555, Breakpoint.expanded), 15555);
    });

    test('a phone selects nothing: the form pushed the detail route', () {
      expect(selectionAfterCreate(15555, Breakpoint.compact), isNull);
    });

    test('a cancelled form leaves the selection alone', () {
      expect(selectionAfterCreate(null, Breakpoint.expanded), isNull);
      expect(selectionAfterCreate(null, Breakpoint.compact), isNull);
    });
  });
}
