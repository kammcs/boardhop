import 'package:flutter/material.dart';

/// The "swipe the list to put the keyboard away" gesture for a scroll view
/// that has no `keyboardDismissBehavior` of its own (`SuperListView` in the
/// diff view). Same rule `ScrollView` applies for
/// [ScrollViewKeyboardDismissBehavior.onDrag]: a scroll that starts from a
/// drag, not from a programmatic jump, takes focus off the field.
class DismissKeyboardOnDrag extends StatelessWidget {
  const DismissKeyboardOnDrag({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollStartNotification>(
        onNotification: (n) {
          if (n.dragDetails != null) {
            final focus = FocusManager.instance.primaryFocus;
            if (focus != null && focus.hasPrimaryFocus) focus.unfocus();
          }
          return false;
        },
        child: child,
      );
}
