import 'package:boardhop/startup_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a startup failure shows its message instead of a splash', (
    tester,
  ) async {
    await tester.pumpWidget(
      const StartupFailureApp(
        error: 'MsalClientException redirect_uri_validation_error',
      ),
    );
    expect(find.text('Boardhop cannot start'), findsOneWidget);
    expect(
      find.textContaining('redirect_uri_validation_error'),
      findsOneWidget,
    );
    expect(find.byType(SelectableText), findsOneWidget);
  });
}
