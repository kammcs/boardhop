import 'package:boardhop/core/text/plain_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('strip', () {
    test('drops tags and decodes entities', () {
      expect(
        PlainText.strip('<p>Ship <b>it</b> &amp; tell &quot;them&quot;</p>'),
        'Ship it & tell "them"',
      );
    });

    test('block ends become newlines, runs of spaces collapse', () {
      expect(
        PlainText.strip('<div>one</div><div>two</div>three  four'),
        'one\ntwo\nthree four',
      );
    });

    test('a mention anchor becomes @Name, with no doubled @', () {
      expect(
        PlainText.strip(
          '<a href="#" data-vss-mention="version:2.0">Ada Lovelace</a> look',
        ),
        '@Ada Lovelace look',
      );
      expect(
        PlainText.strip('<a data-vss-mention="v" href="#">@Ada</a>'),
        '@Ada',
      );
    });

    test('a markdown @<guid> mention becomes @someone', () {
      // The form a Boardhop-posted mention takes in a pull request comment
      // and in a work item's System.History (spike w30): there is no rendered
      // anchor to read, and no resolver here, so it reads @someone and never
      // the GUID (research/16 M9).
      expect(
        PlainText.strip('@<2f1b1a70-6d24-4c0a-9f0b-6b6d2f9a1c33> ship it?'),
        '@someone ship it?',
      );
      expect(PlainText.unknownMention, '@someone');
    });

    test('a resolver names the person behind the GUID', () {
      const guid = '2f1b1a70-6d24-4c0a-9f0b-6b6d2f9a1c33';
      expect(
        PlainText.strip(
          '<p>hi @<$guid></p>',
          nameFor: (g) => g == guid ? 'Ada Example' : null,
        ),
        'hi @Ada Example',
      );
      // A name that already carries the @ does not get a second one.
      expect(PlainText.strip('@<$guid>', nameFor: (_) => '@Ada'), '@Ada');
      // An unknown GUID still reads @someone, never the GUID.
      expect(PlainText.strip('@<$guid>', nameFor: (_) => null), '@someone');
    });

    test('the @ of a mention survives the tag pass', () {
      // Regression: `<guid>` matches the tag pattern, so replacing the
      // mention after the tags would leave a bare "@".
      expect(
        PlainText.strip('hi @<2F1B1A70-6D24-4C0A-9F0B-6B6D2F9A1C33>'),
        'hi @someone',
      );
    });

    test('text that only looks like a mention is left alone', () {
      expect(PlainText.strip('mail kelly@kammcs.com'), 'mail kelly@kammcs.com');
      // Too short to be a GUID: the tag pass eats it, as it always has.
      expect(PlainText.strip('@<not-a-guid>'), '@');
    });

    test('numeric entities, decimal and hex', () {
      expect(PlainText.strip('a&#8230;b&#x2014;c'), 'a…b—c');
    });

    test('trim: false keeps the spaces either side of a piece', () {
      // What the highlight parser relies on: trimming each piece would glue
      // "the" and "boardhop" together.
      expect(PlainText.strip('the ', trim: false), 'the ');
      expect(PlainText.strip('the '), 'the');
    });

    test('null and empty are empty', () {
      expect(PlainText.strip(null), '');
      expect(PlainText.strip(''), '');
    });
  });

  group('escape', () {
    test('is the inverse of the decoding, ampersand first', () {
      const text = 'a < b && "c" > &amp;';
      expect(PlainText.decodeEntities(PlainText.escape(text)), text);
    });

    test('escaped text carries no tags through a strip', () {
      const text = '<script>alert(1)</script>';
      expect(PlainText.strip(PlainText.escape(text)), text);
    });
  });
}
