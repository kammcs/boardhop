import 'package:flutter/material.dart';

/// What runs when the app cannot be built at all: `AuthService.create` (the
/// MSAL client) failed before the first frame.
///
/// Without this the phone shows the launch screen for ever, which is what a
/// Play-installed build did on 2026-09-14 when its MSAL redirect URI named
/// the upload key while the app was signed with Google's app signing key.
/// A frozen splash tells nobody anything; the message does. The text is
/// MSAL's own and carries no token, account or organization.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Boardhop',
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Boardhop cannot start',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Sign-in could not be set up on this install. '
                  'Reinstalling from the store usually fixes it; if not, '
                  'send the text below to support.',
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(child: SelectableText('$error')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
