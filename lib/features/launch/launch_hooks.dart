import 'package:flutter/widgets.dart';

/// The one seam between the launch machinery (phase LA) and the project
/// picker (phase LB).
///
/// `ProjectShell` offers "Choose another project" when the project it is
/// showing has gone (research/21 L7), which means opening the picker — a
/// widget LA knows nothing about. The picker sets [onChooseAnotherProject]
/// once, from where it is registered, and the shell calls it if it is there;
/// with nothing registered the shell simply leaves the action off, so LA
/// stands on its own and neither phase imports the other.
abstract final class LaunchHooks {
  /// Opens the project picker over [context]. Set by LB
  /// (`showProjectPicker`); null until then.
  ///
  /// Takes the context rather than being a bare `VoidCallback` because a
  /// sheet needs one, and the shell is the only sensible anchor.
  static void Function(BuildContext context)? onChooseAnotherProject;

  static bool get canChooseProject => onChooseAnotherProject != null;

  static void chooseAnotherProject(BuildContext context) =>
      onChooseAnotherProject?.call(context);
}
