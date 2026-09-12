import 'package:boardhop/features/shared/reload_on_return.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Page extends StatefulWidget {
  const _Page({required this.onReload, required this.stale});

  final VoidCallback onReload;
  final Duration stale;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> with ReloadOnReturn {
  @override
  Duration get staleAfter => widget.stale;

  @override
  void initState() {
    super.initState();
    markLoaded();
  }

  @override
  Future<void> reload() async {
    widget.onReload();
    markLoaded();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Mimics how the shell parks an inactive branch.
Widget host({required bool visible, required Widget child}) => MaterialApp(
  home: TickerMode(enabled: visible, child: child),
);

void main() {
  testWidgets('returning to a stale tab reloads it once', (tester) async {
    var reloads = 0;
    final page = _Page(onReload: () => reloads++, stale: Duration.zero);

    await tester.pumpWidget(host(visible: true, child: page));
    expect(reloads, 0, reason: 'the first build is the page own load');

    await tester.pumpWidget(host(visible: false, child: page));
    await tester.pumpWidget(host(visible: true, child: page));
    await tester.pump();
    expect(reloads, 1);

    // Staying on the tab does not reload again.
    await tester.pump(const Duration(seconds: 1));
    expect(reloads, 1);
  });

  testWidgets('a tab seen moments ago is left alone', (tester) async {
    var reloads = 0;
    final page = _Page(
      onReload: () => reloads++,
      stale: const Duration(minutes: 5),
    );
    await tester.pumpWidget(host(visible: true, child: page));
    await tester.pumpWidget(host(visible: false, child: page));
    await tester.pumpWidget(host(visible: true, child: page));
    await tester.pump();
    expect(reloads, 0);
  });
}
