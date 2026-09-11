import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/notifications/notification_service.dart';
import '../../theme/theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeScope.of(context);
    final notifications = context.read<NotificationService>();
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ContentColumn(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.lg,
                Spacing.lg,
                Spacing.sm,
              ),
              child: Text(
                'Appearance',
                style: textTheme.titleSmall?.copyWith(color: scheme.primary),
              ),
            ),
            RadioGroup<ThemeMode>(
              groupValue: controller.mode,
              onChanged: (m) => controller.setMode(m ?? ThemeMode.system),
              child: const Column(
                children: [
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.system,
                    title: Text('Match system'),
                    secondary: Icon(Icons.brightness_auto),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.light,
                    title: Text('Light'),
                    secondary: Icon(Icons.light_mode_outlined),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.dark,
                    title: Text('Dark'),
                    secondary: Icon(Icons.dark_mode_outlined),
                  ),
                ],
              ),
            ),
            if (!context.breakpoint.isCompact && _hasGlassRail(context))
              SwitchListTile(
                value: controller.railSide == RailSide.right,
                onChanged: (v) =>
                    controller.setRailSide(v ? RailSide.right : RailSide.left),
                title: const Text('Tab rail on the right'),
                subtitle: const Text(
                  'In landscape. Portrait keeps the rail along the bottom.',
                ),
                secondary: const Icon(Icons.view_sidebar_outlined),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.xl,
                Spacing.lg,
                Spacing.sm,
              ),
              child: Text(
                'Notifications',
                style: textTheme.titleSmall?.copyWith(color: scheme.primary),
              ),
            ),
            ListenableBuilder(
              listenable: notifications.enabledNotifier,
              builder: (context, _) => SwitchListTile(
                value: notifications.enabled,
                onChanged: (v) => notifications.setEnabled(v),
                title: const Text('New activity'),
                subtitle: Text(
                  notifications.permissionDenied && !notifications.enabled
                      ? 'Allow notifications for Boardhop in system settings, then try again.'
                      : 'Pull requests waiting for you, changes to your work items and build results, checked every few minutes while Boardhop is open.',
                ),
                secondary: const Icon(Icons.notifications_outlined),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The floating glass rail exists on Apple tablets only (see ProjectShell).
bool _hasGlassRail(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
}
