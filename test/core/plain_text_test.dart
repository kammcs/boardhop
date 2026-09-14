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
