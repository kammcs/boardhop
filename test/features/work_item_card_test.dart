import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/features/work_items/widgets/work_item_visuals.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The card the Kanban board and the sprint taskboard both draw.
///
/// P-B found its footer `Row` overflowing by 46 px at AX XXXL on a phone
/// whenever the card carried a badge — the swimlane on the board, the
/// parent id or the remaining work on the taskboard. The footer is a `Wrap`
/// now, the title drops to two lines and the tags go, so this is what those
/// three rules have to keep true.
void main() {
  WorkItem item({List<String> tags = const []}) => WorkItem.fromJson({
    'id': 15550,
    'rev': 3,
    'fields': {
      'System.Id': 15550,
      'System.WorkItemType': 'Task',
      'System.Title':
          'A title long enough to want three lines at an ordinary size',
      'System.State': 'In Progress',
      'System.Tags': tags.join('; '),
    },
  });

  Future<void> pump(
    WidgetTester tester, {
    required double textScale,
    String? badge,
    List<String> tags = const [],
  }) async {
    // A phone, which is where the overflow happened.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                // `kanbanColumnWidth` on a 390 dp phone.
                width: 320,
                child: WorkItemCard(
                  item: item(tags: tags),
                  visuals: const WorkItemVisuals({}),
                  badge: badge,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a badged card does not overflow at AX XXXL (3.1x)', (
    tester,
  ) async {
    await pump(tester, textScale: 3.1, badge: '#15503', tags: ['api', 'ui']);

    expect(tester.takeException(), isNull);
    expect(find.text('#15503'), findsOneWidget);
  });

  testWidgets('the tags go at 1.6x and above; the badge stays', (tester) async {
    await pump(tester, textScale: 1.6, badge: '4 h', tags: ['api', 'ui']);

    // The badge carries the meaning — the parent, the lane, the hours —
    // so the tags are what the card sheds first.
    expect(find.text('4 h'), findsOneWidget);
    expect(find.text('api · ui'), findsNothing);
  });

  testWidgets('at the ordinary size nothing is dropped', (tester) async {
    await pump(tester, textScale: 1, badge: '#15503', tags: ['api', 'ui']);

    expect(tester.takeException(), isNull);
    expect(find.text('#15503'), findsOneWidget);
    expect(find.text('api · ui'), findsOneWidget);
    final title = tester.widget<Text>(
      find.text('A title long enough to want three lines at an ordinary size'),
    );
    expect(title.maxLines, 3);
  });

  testWidgets('the title drops to two lines at accessibility sizes', (
    tester,
  ) async {
    await pump(tester, textScale: 2, badge: '#15503');

    final title = tester.widget<Text>(
      find.text('A title long enough to want three lines at an ordinary size'),
    );
    expect(title.maxLines, 2);
  });
}
