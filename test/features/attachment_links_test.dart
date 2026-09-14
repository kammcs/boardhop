import 'package:boardhop/features/shared/attachments/attachment_links.dart';
import 'package:flutter_test/flutter_test.dart';

/// Synthetic ids only; the shapes are the ones spikes w32/s50 measured.
const guid = 'c50b0d6e-1111-4222-8333-444455556666';
const repoGuid = '9a8b7c6d-5555-4444-8333-222211110000';
const projectGuid = '98720989-1234-4321-8888-aaaabbbbcccc';

const witUrl =
    'https://dev.azure.com/contoso/$projectGuid'
    '/_apis/wit/attachments/$guid?fileName=shot.png';
const legacyUrl =
    'https://contoso.visualstudio.com/$projectGuid'
    '/_apis/wit/attachments/$guid?fileName=shot.png';
const prUrl =
    'https://dev.azure.com/contoso/$projectGuid'
    '/_apis/git/repositories/$repoGuid/pullRequests/8334/attachments/shot.png';

void main() {
  group('isAttachmentUrl', () {
    test('both stores, both hosts, either scheme', () {
      expect(isAttachmentUrl(witUrl), isTrue);
      expect(isAttachmentUrl(legacyUrl), isTrue);
      expect(isAttachmentUrl(prUrl), isTrue);
      expect(isAttachmentUrl(witUrl.replaceFirst('https', 'http')), isTrue);
    });

    test('the host and the path are matched case-insensitively', () {
      expect(isAttachmentUrl(witUrl.toUpperCase()), isTrue);
      expect(
        isAttachmentUrl(
          'https://DEV.AZURE.COM/contoso/$projectGuid'
          '/_APIS/WIT/ATTACHMENTS/$guid',
        ),
        isTrue,
      );
    });

    test('anything else is not an attachment', () {
      expect(isAttachmentUrl(null), isFalse);
      expect(isAttachmentUrl(''), isFalse);
      expect(isAttachmentUrl('https://example.com/image.png'), isFalse);
      // Right path, wrong host: an unknown host cannot be handed the token.
      expect(
        isAttachmentUrl('https://evil.test/_apis/wit/attachments/$guid'),
        isFalse,
      );
      // Right host, not an attachment.
      expect(
        isAttachmentUrl('https://dev.azure.com/contoso/_apis/wit/workItems/1'),
        isFalse,
      );
      // The store itself, with nothing addressed in it.
      expect(
        isAttachmentUrl('https://dev.azure.com/contoso/_apis/wit/attachments'),
        isFalse,
      );
      expect(isAttachmentUrl('boardhop-mention:workItem/15545'), isFalse);
    });
  });

  group('witAttachmentId', () {
    test('the guid of a work item attachment, and nothing for a PR one', () {
      expect(witAttachmentId(witUrl), guid);
      expect(witAttachmentId(legacyUrl), guid);
      // Keyed by file name inside one PR, so it must never key a cache.
      expect(witAttachmentId(prUrl), isNull);
      expect(witAttachmentId('https://example.com/a.png'), isNull);
    });
  });

  group('attachmentFileName', () {
    test('?fileName= first, then the last path segment', () {
      expect(attachmentFileName(witUrl), 'shot.png');
      expect(attachmentFileName(prUrl), 'shot.png');
      expect(
        attachmentFileName(
          'https://dev.azure.com/contoso/$projectGuid'
          '/_apis/wit/attachments/$guid',
        ),
        guid,
      );
      expect(
        attachmentFileName(
          witUrl.replaceFirst('fileName=shot.png', 'fileName=my%20note.txt'),
        ),
        'my note.txt',
      );
      expect(attachmentFileName(''), 'File');
    });
  });

  group('attachmentMarkdown', () {
    test('image and file forms', () {
      expect(
        attachmentMarkdown(name: 'shot.png', url: witUrl, isImage: true),
        '![shot.png]($witUrl)',
      );
      expect(
        attachmentMarkdown(name: 'notes.txt', url: witUrl, isImage: false),
        '[notes.txt]($witUrl)',
      );
    });

    test('brackets in the name are escaped', () {
      expect(
        attachmentMarkdown(name: 'a[1]b).png', url: witUrl, isImage: true),
        r'![a\[1\]b\).png]'
        '($witUrl)',
      );
    });

    test('a destination with parentheses goes in angle brackets', () {
      const url =
          'https://dev.azure.com/contoso/$projectGuid/_apis/git/repositories/'
          '$repoGuid/pullRequests/8334/attachments/report(1).pdf';
      expect(
        attachmentMarkdown(name: 'report(1).pdf', url: url, isImage: false),
        r'[report(1\).pdf]'
        '(<$url>)',
      );
    });
  });

  group('uniqueAttachmentName', () {
    final now = DateTime(2026, 9, 14, 17, 30, 45);

    test('the stamp goes before the extension', () {
      expect(
        uniqueAttachmentName('image.jpg', now: now),
        'image-20260914-173045.jpg',
      );
      expect(
        uniqueAttachmentName('my.notes.txt', now: now),
        'my.notes-20260914-173045.txt',
      );
    });

    test('a name with no extension, and a dotfile', () {
      expect(
        uniqueAttachmentName('README', now: now),
        'README-20260914-173045',
      );
      expect(uniqueAttachmentName('.env', now: now), '.env-20260914-173045');
    });

    test('two calls a second apart cannot collide', () {
      final a = uniqueAttachmentName('image.jpg', now: now);
      final b = uniqueAttachmentName(
        'image.jpg',
        now: now.add(const Duration(seconds: 1)),
      );
      expect(a, isNot(b));
    });
  });

  group('the U+0006 sentinel (spike w32 §3)', () {
    const base =
        'https://dev.azure.com/contoso/$projectGuid/_apis/wit/attachments';
    const commentUrl =
        'https://dev.azure.com/contoso/$projectGuid'
        '/_apis/wit/workItems/15545/comments/123';
    const broken = '$attachmentSentinel/$guid?fileName=shot.png';

    test('the base comes off the comment\'s own url', () {
      expect(witAttachmentBase(commentUrl), base);
      expect(witAttachmentBase('https://example.com/nope'), isNull);
      expect(witAttachmentBase(null), isNull);
    });

    test('a sentinel url is put back together', () {
      expect(
        normalizeAttachmentUrl(broken, base: base),
        '$base/$guid?fileName=shot.png',
      );
    });

    test('without a base the src is left alone rather than guessed', () {
      expect(normalizeAttachmentUrl(broken), broken);
    });

    test('an ordinary url is untouched', () {
      expect(normalizeAttachmentUrl(witUrl, base: base), witUrl);
    });

    test('a whole body is repaired, src and href alike', () {
      const html =
          '<p>look</p><p><img src="$broken" alt="x"></p>'
          '<p><a href="$attachmentSentinel/$guid?fileName=n.txt">n.txt</a></p>';
      final fixed = normalizeAttachmentHtml(html, base: base);
      expect(fixed.contains(attachmentSentinel), isFalse);
      expect(fixed, contains('src="$base/$guid?fileName=shot.png"'));
      expect(fixed, contains('href="$base/$guid?fileName=n.txt"'));
    });

    test('a body with no sentinel is returned as it is', () {
      const html = '<p><img src="$witUrl"></p>';
      expect(normalizeAttachmentHtml(html, base: base), same(html));
    });
  });
}
