import 'package:boardhop/features/shared/mention/mention_controller.dart';
import 'package:boardhop/core/text/mention.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The controller behind the mention picker: where a trigger is legal, what
/// survives an edit, and what goes on the wire (research/16 M6, M7, M14).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MentionController at(String text, [int? caret]) {
    final controller = MentionController(text: text);
    controller.selection = TextSelection.collapsed(
      offset: caret ?? text.length,
    );
    return controller;
  }

  void edit(MentionController controller, String text, int caret) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  group('activeTrigger', () {
    test(
      'opens at the start of the text, after a space and after a bracket',
      () {
        expect(at('@').activeTrigger?.character, '@');
        expect(at('hi @').activeTrigger?.character, '@');
        expect(at('(@').activeTrigger?.character, '@');
        expect(at('[@').activeTrigger?.character, '@');
        expect(at('hi\n@').activeTrigger?.character, '@');
      },
    );

    test('never opens inside an e-mail address', () {
      expect(at('kelly@kammcs.com').activeTrigger, isNull);
      expect(at('kelly@').activeTrigger, isNull);
      expect(at('kelly@kam', 9).activeTrigger, isNull);
    });

    test('carries the query and the range the pick will replace', () {
      final trigger = at('hi @kel').activeTrigger!;
      expect(trigger.query, 'kel');
      expect(trigger.range, const TextRange(start: 3, end: 7));
      expect(trigger.kind, MentionKind.person);
    });

    test('allows spaces inside the query but not one straight after', () {
      expect(at('@kel ka').activeTrigger?.query, 'kel ka');
      expect(at('@ kel').activeTrigger, isNull);
      expect(at('@ ').activeTrigger, isNull);
    });

    test('a newline or a dot ends the query', () {
      expect(at('@kel\nmore').activeTrigger, isNull);
      expect(at('@kel.ka').activeTrigger, isNull);
      // A dot before the trigger is none of its business.
      expect(at('v1.2 @kel').activeTrigger?.query, 'kel');
    });

    test('# and ! open the artifact pickers', () {
      expect(at('see #155').activeTrigger?.kind, MentionKind.workItem);
      expect(at('see !83').activeTrigger?.kind, MentionKind.pullRequest);
      expect(at('see !83').activeTrigger?.query, '83');
    });

    test('a query longer than the cap gives up rather than scanning on', () {
      final long = '@${'x' * 60}';
      expect(at(long).activeTrigger, isNull);
    });

    test('nothing opens when the selection is a range', () {
      final controller = MentionController(text: 'hi @kel');
      controller.selection = const TextSelection(
        baseOffset: 3,
        extentOffset: 7,
      );
      expect(controller.activeTrigger, isNull);
    });

    test('the caret inside a token offers nothing to pick', () {
      final controller = at('hi @kel');
      controller.insertToken(
        MentionKind.person,
        'guid-1',
        '@Kelly Kamm',
        replacing: controller.activeTrigger!.range,
      );
      // Caret in the middle of "@Kelly Kamm".
      controller.selection = const TextSelection.collapsed(offset: 8);
      expect(controller.activeTrigger, isNull);
      // And at the end of the inserted run, past the space.
      controller.selection = const TextSelection.collapsed(offset: 15);
      expect(controller.activeTrigger, isNull);
    });
  });

  group('insertToken', () {
    test(
      'replaces the trigger and its query, adds one space, moves the caret',
      () {
        final controller = at('hi @kel');
        controller.insertToken(
          MentionKind.person,
          'guid-1',
          '@Kelly Kamm',
          replacing: controller.activeTrigger!.range,
        );
        expect(controller.text, 'hi @Kelly Kamm ');
        expect(controller.selection.baseOffset, 15);
        expect(controller.selection.isCollapsed, isTrue);
        final token = controller.tokens.single;
        expect(token.start, 3);
        expect(token.end, 14);
        expect(token.id, 'guid-1');
        expect(token.kind, MentionKind.person);
      },
    );

    test('does not double the space when one already follows', () {
      final controller = at('hi @kel done', 7);
      controller.insertToken(
        MentionKind.person,
        'guid-1',
        '@Kelly Kamm',
        replacing: controller.activeTrigger!.range,
      );
      expect(controller.text, 'hi @Kelly Kamm done');
      expect(controller.selection.baseOffset, 14);
    });

    test('an artifact keeps its plain id, which the service links itself', () {
      final controller = at('see #155');
      controller.insertToken(
        MentionKind.workItem,
        '15545',
        '#15545',
        replacing: controller.activeTrigger!.range,
      );
      expect(controller.text, 'see #15545 ');
      expect(controller.toWire(MentionWire.markdown), 'see #15545 ');
    });

    test('a second mention lands beside the first', () {
      final controller = at('@kel');
      controller.insertToken(
        MentionKind.person,
        'guid-1',
        '@Kelly Kamm',
        replacing: controller.activeTrigger!.range,
      );
      edit(controller, '@Kelly Kamm and @gr', 19);
      controller.insertToken(
        MentionKind.person,
        'guid-2',
        '@Grace Hopper',
        replacing: controller.activeTrigger!.range,
      );
      expect(controller.text, '@Kelly Kamm and @Grace Hopper ');
      expect(controller.tokens.map((t) => t.id), ['guid-1', 'guid-2']);
      expect(
        controller.toWire(MentionWire.markdown),
        '@<guid-1> and @<guid-2> ',
      );
    });
  });

  group('tokens survive the right edits and break on the wrong ones', () {
    MentionController withToken() {
      final controller = at('hi @kel');
      controller.insertToken(
        MentionKind.person,
        'guid-1',
        '@Kelly Kamm',
        replacing: controller.activeTrigger!.range,
      );
      return controller;
    }

    test('an edit before the token shifts it', () {
      final controller = withToken();
      edit(controller, 'Hey hi @Kelly Kamm ', 4);
      final token = controller.tokens.single;
      expect(token.start, 7);
      expect(token.end, 18);
      expect(controller.text.substring(token.start, token.end), '@Kelly Kamm');
    });

    test('an edit after the token leaves it alone', () {
      final controller = withToken();
      edit(controller, 'hi @Kelly Kamm please look', 26);
      expect(controller.tokens.single.start, 3);
      expect(controller.tokens.single.end, 14);
    });

    test('an edit inside the run turns it back into plain text (M6)', () {
      final controller = withToken();
      // Delete the "y" of Kelly.
      edit(controller, 'hi @Kell Kamm ', 8);
      expect(controller.tokens, isEmpty);
      expect(controller.toWire(MentionWire.markdown), 'hi @Kell Kamm ');
    });

    test('backspacing the last character of the run breaks it', () {
      final controller = withToken();
      edit(controller, 'hi @Kelly Kam ', 13);
      expect(controller.tokens, isEmpty);
    });

    test('pasting the token text verbatim does not make a second mention', () {
      final controller = withToken();
      edit(controller, 'hi @Kelly Kamm @Kelly Kamm ', 27);
      expect(controller.tokens, hasLength(1));
      expect(controller.tokens.single.start, 3);
      expect(
        controller.toWire(MentionWire.markdown),
        'hi @<guid-1> @Kelly Kamm ',
      );
    });

    test('clearing the field clears the tokens', () {
      final controller = withToken();
      controller.clear();
      expect(controller.tokens, isEmpty);
      expect(controller.toWire(MentionWire.markdown), '');
    });
  });

  group('toWire', () {
    test('markdown emits the angle form Azure DevOps parses', () {
      final controller = at('@kel');
      controller.insertToken(
        MentionKind.person,
        '9f1d6d44-0000-4000-8000-000000000001',
        '@Kelly Kamm',
        replacing: controller.activeTrigger!.range,
      );
      expect(
        controller.toWire(MentionWire.markdown),
        '@<9f1d6d44-0000-4000-8000-000000000001> ',
      );
    });

    test('html emits the data-vss-mention anchor, escaped', () {
      final controller = at('@k');
      controller.insertToken(
        MentionKind.person,
        'guid-1',
        '@A & B <c>',
        replacing: controller.activeTrigger!.range,
      );
      expect(
        controller.toWire(MentionWire.html),
        '<a href="#" data-vss-mention="version:2.0,guid-1">'
        '@A &amp; B &lt;c&gt;</a> ',
      );
    });

    test('a person with no id degrades to the plain label', () {
      final controller = at('@k');
      controller.insertToken(
        MentionKind.person,
        null,
        '@Kelly Kamm',
        replacing: controller.activeTrigger!.range,
      );
      expect(controller.toWire(MentionWire.markdown), '@Kelly Kamm ');
    });
  });

  group('unresolvedAtWords', () {
    test('finds a hand-typed @word and skips a picked one', () {
      final controller = at('hi @kel');
      controller.insertToken(
        MentionKind.person,
        'guid-1',
        '@Kelly Kamm',
        replacing: controller.activeTrigger!.range,
      );
      edit(controller, 'hi @Kelly Kamm and @grace too', 29);
      expect(controller.unresolvedAtWords, ['@grace']);
    });

    test('an e-mail address is not an @word', () {
      expect(at('mail kelly@kammcs.com now').unresolvedAtWords, isEmpty);
    });

    test('a bare @ is not one either: the list is open at that point', () {
      expect(at('hi @').unresolvedAtWords, isEmpty);
    });

    test('each word is reported once, in order', () {
      expect(at('@ada and @grace and @ada').unresolvedAtWords, [
        '@ada',
        '@grace',
      ]);
    });
  });

  group('buildTextSpan', () {
    testWidgets('styles the token run and keeps the plain text equal', (
      tester,
    ) async {
      final controller = at('hi @kel');
      controller.insertToken(
        MentionKind.person,
        'guid-1',
        '@Kelly Kamm',
        replacing: controller.activeTrigger!.range,
      );
      late TextSpan span;
      late ColorScheme scheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Builder(
            builder: (context) {
              scheme = Theme.of(context).colorScheme;
              span = controller.buildTextSpan(
                context: context,
                style: const TextStyle(fontSize: 16),
                withComposing: false,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      expect(span.toPlainText(), controller.text);
      final children = span.children!.cast<TextSpan>();
      final token = children.firstWhere((s) => s.text == '@Kelly Kamm');
      expect(token.style?.color, scheme.primary);
      expect(token.style?.fontWeight, FontWeight.w500);
      // Three framework bugs say never do any of these in buildTextSpan.
      expect(token.style?.fontSize, isNull);
      expect(token.recognizer, isNull);
      expect(span.children!.whereType<WidgetSpan>(), isEmpty);
    });

    testWidgets('a composing range keeps its underline beside a token', (
      tester,
    ) async {
      final controller = at('hi @kel');
      controller.insertToken(
        MentionKind.person,
        'guid-1',
        '@Kelly Kamm',
        replacing: controller.activeTrigger!.range,
      );
      controller.value = const TextEditingValue(
        text: 'hi @Kelly Kamm kel',
        selection: TextSelection.collapsed(offset: 18),
        composing: TextRange(start: 15, end: 18),
      );
      late TextSpan span;
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Builder(
            builder: (context) {
              span = controller.buildTextSpan(
                context: context,
                style: const TextStyle(fontSize: 16),
                withComposing: true,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      expect(span.toPlainText(), 'hi @Kelly Kamm kel');
      final children = span.children!.cast<TextSpan>();
      expect(controller.tokens, hasLength(1));
      final composing = children.firstWhere((s) => s.text == 'kel');
      expect(composing.style?.decoration, TextDecoration.underline);
      final token = children.firstWhere((s) => s.text == '@Kelly Kamm');
      expect(token.style?.decoration, isNot(TextDecoration.underline));
    });

    testWidgets('plain text with no tokens is one span', (tester) async {
      final controller = at('nothing special here');
      late TextSpan span;
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Builder(
            builder: (context) {
              span = controller.buildTextSpan(
                context: context,
                style: null,
                withComposing: true,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      expect(span.text, 'nothing special here');
      expect(span.children, isNull);
    });
  });
}
