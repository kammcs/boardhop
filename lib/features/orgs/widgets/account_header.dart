import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/util/format.dart';
import '../../../data/repositories/account_repository.dart';
import '../../../theme/theme.dart';

/// Who is signed in, above the organization list: photo on the left, the
/// email and the company stacked on the right, on a quiet container so it
/// reads as the header of what follows.
class AccountHeaderBar extends StatelessWidget {
  const AccountHeaderBar({
    super.key,
    required this.header,
    this.fallbackEmail,
    this.photo,
  });

  final AccountHeader? header;

  /// The MSAL username, shown until the header has loaded.
  final String? fallbackEmail;
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final email = header?.email.isNotEmpty == true
        ? header!.email
        : (fallbackEmail ?? '');
    final name = header?.displayName ?? '';
    final second =
        header?.organizationName ??
        (name.isNotEmpty && name != email ? name : null);
    final bytes = photo;
    return Material(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.lg,
          Spacing.lg,
          Spacing.lg,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: scheme.secondaryContainer,
              foregroundImage: bytes == null ? null : MemoryImage(bytes),
              child: Text(
                initials(name.isNotEmpty ? name : email),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
            const SizedBox(width: Spacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    email,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (second != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      second,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
