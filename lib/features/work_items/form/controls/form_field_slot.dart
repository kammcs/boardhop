import 'package:flutter/material.dart';

import '../../../../theme/theme.dart';

/// Label, control, help text and the error slot every form control has.
///
/// The error line is what the local checks and the server's
/// `RuleValidationErrors` write into (research/11 §4.3); it carries a
/// `GlobalKey` so the page can scroll the first failing control into view.
class FormFieldSlot extends StatelessWidget {
  const FormFieldSlot({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.helpText,
    this.error,
  });

  final String label;
  final Widget child;
  final bool required;
  final String? helpText;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.xs),
              child: Text.rich(
                TextSpan(
                  text: label,
                  children: [
                    if (required)
                      TextSpan(
                        text: ' *',
                        style: TextStyle(color: scheme.error),
                      ),
                  ],
                ),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          child,
          if (helpText != null && helpText!.isNotEmpty && error == null)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.xs),
              child: Text(
                helpText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 16, color: scheme.error),
                  const SizedBox(width: Spacing.xs),
                  Expanded(
                    child: Text(
                      error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The tappable box a picker control shows: the current value or its
/// placeholder, with a trailing glyph. Looks like an `InputDecorator` so a
/// picker row and a text field sit on the same rhythm.
class PickerTile extends StatelessWidget {
  const PickerTile({
    super.key,
    required this.text,
    required this.onTap,
    this.placeholder = false,
    this.leading,
    this.icon = Icons.arrow_drop_down,
    this.enabled = true,
    this.hasError = false,
  });

  final String text;
  final VoidCallback? onTap;
  final bool placeholder;
  final Widget? leading;
  final IconData icon;
  final bool enabled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: Radii.card,
      child: InputDecorator(
        isEmpty: false,
        decoration: InputDecoration(
          isDense: true,
          enabled: enabled,
          errorText: hasError ? '' : null,
          errorStyle: const TextStyle(height: 0, fontSize: 0),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.md,
          ),
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: Spacing.sm),
            ],
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: placeholder || !enabled
                      ? scheme.onSurfaceVariant
                      : scheme.onSurface,
                ),
              ),
            ),
            Icon(icon, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
