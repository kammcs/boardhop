import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/features/shared/mention/mention_markdown.dart';
import 'package:boardhop/features/work_items/widgets/rich_text_view.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// research/20 K5: Azure DevOps has no wiki mention syntax, so a page is
/// referenced in a comment or a field by its **web URL**. Both forms, with
/// the wiki named by GUID or by name, open the in-app reader rather than a
/// browser — and everything else is left exactly as it was.
///
/// The two hosts are the two rendering paths: `MentionMarkdown` (pull
/// request comments, Markdown fields) and `RichTextView`'s HTML factory
/// (work item fields and comments, which the service renders).
void main() {
  const idForm =
      'https://dev.azure.com/puremedia/DevOps%20Mobile%20App/_wiki/wikis/'
      'DevOps-Mobile-App.wiki/238/Constructs';
  const pathForm =
      'https://dev.azure.com/puremedia/DevOps%20Mobile%20App/_wiki/wikis/'
      '2bd59283-17a5-4fd0-b964-cd9a4189f721'
      '?pagePath=%2FBoardhop%2FLinks&wikiVersion=GBwikiMaster';

  late List<String> opened;

  Future<void> pump(WidgetTester tester, Widget body) async {
    final router = GoRouter(
      initialLocation: '/body',
      routes: [
        GoRoute(
          path: '/body',
          builder: (_, _) => Scaffold(body: SingleChildScrollView(child: body)),
        ),
        GoRoute(
          path: '/a/:account/orgs/:org/projects/:project/wiki-page/:wiki',
          builder: (_, state) {
            opened.add(
              '${state.pathParameters['account']}|'
              '${state.pathParameters['org']}|'
              '${state.pathParameters['project']}|'
              '${state.pathParameters['wiki']}|'
              '${state.uri.queryParameters['id'] ?? ''}|'
              '${state.uri.queryParameters['path'] ?? ''}|'
              '${state.uri.queryParameters['version'] ?? ''}',
            );
            return const Scaffold(body: Text('reader'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: BoardhopTheme.light(),
        routerConfig: router,
        builder: (context, child) =>
            AccountScope(accountId: 'u1', child: child!),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Every tappable run on screen.
  List<TapGestureRecognizer> taps(WidgetTester tester) {
    final out = <TapGestureRecognizer>[];
    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
          out.add(span.recognizer! as TapGestureRecognizer);
        }
        return true;
      });
    }
    return out;
  }

  Future<void> tapOnly(WidgetTester tester) async {
    final found = taps(tester);
    expect(found, hasLength(1));
    found.single.onTap!();
    await tester.pumpAndSettle();
  }

  setUp(() => opened = []);

  group('a Markdown comment', () {
    testWidgets('the id form opens the reader by page id', (tester) async {
      await pump(
        tester,
        const MentionMarkdown(selectable: false, data: 'see [it]($idForm)'),
      );
      await tapOnly(tester);
      expect(opened, [
        'u1|puremedia|DevOps Mobile App|DevOps-Mobile-App.wiki|238||',
      ]);
    });

    testWidgets('the path form carries the page path and the branch', (
      tester,
    ) async {
      await pump(
        tester,
        const MentionMarkdown(selectable: false, data: 'see [it]($pathForm)'),
      );
      await tapOnly(tester);
      expect(opened, [
        'u1|puremedia|DevOps Mobile App|'
            '2bd59283-17a5-4fd0-b964-cd9a4189f721||/Boardhop/Links|wikiMaster',
      ]);
    });

    testWidgets('another project opens in that project', (tester) async {
      const other =
          'https://dev.azure.com/puremedia/CloudCover/_wiki/wikis/'
          'CloudCover.wiki/9/Release-notes';
      await pump(
        tester,
        const MentionMarkdown(selectable: false, data: '[notes]($other)'),
      );
      await tapOnly(tester);
      expect(opened.single, startsWith('u1|puremedia|CloudCover|'));
    });

    testWidgets('an ordinary link is left alone', (tester) async {
      await pump(
        tester,
        const MentionMarkdown(
          selectable: false,
          data: '[docs](https://example.test/docs)',
        ),
      );
      await tapOnly(tester);
      expect(opened, isEmpty);
    });
  });

  group('an HTML field', () {
    testWidgets('a wiki anchor opens the reader', (tester) async {
      await pump(
        tester,
        const RichTextView(content: '<p><a href="$idForm">Constructs</a></p>'),
      );
      await tapOnly(tester);
      expect(opened, hasLength(1));
      expect(opened.single, contains('DevOps-Mobile-App.wiki|238'));
    });

    testWidgets('a non-wiki anchor is not intercepted', (tester) async {
      await pump(
        tester,
        const RichTextView(
          content: '<p><a href="https://example.test/x">x</a></p>',
        ),
      );
      await tapOnly(tester);
      expect(opened, isEmpty);
    });
  });
}
