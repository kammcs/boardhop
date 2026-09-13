import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:intl/intl.dart';

import 'push_registrar.dart';

/// The Activity feed's push row: whether this phone is registered with the
/// relay, and a button that asks the relay to wake it.
///
/// It sits under the feed's notification section rather than in Settings
/// because registration is per organization and Settings is not inside an
/// account's shell.
class PushStatusTile extends StatefulWidget {
  const PushStatusTile({super.key, required this.org});

  final String org;

  @override
  State<PushStatusTile> createState() => _PushStatusTileState();
}

class _PushStatusTileState extends State<PushStatusTile> {
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final registrar = context.read<PushRegistrar>();
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: registrar.registration,
      builder: (context, _) {
        final registration = registrar.registration.value;
        final registered =
            registration != null && registration.org == widget.org;
        return ListTile(
          leading: Icon(
            registered ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            color: registered ? scheme.primary : scheme.onSurfaceVariant,
          ),
          title: Text(
            registered
                ? 'Push: registered on ${DateFormat.yMMMd().format(registration.registeredAt.toLocal())}'
                : 'Push: not registered',
          ),
          subtitle: Text(
            registered
                ? 'The relay can wake Boardhop for ${widget.org} even when it is closed.'
                : 'Turn notifications on to let the relay wake Boardhop for ${widget.org}.',
          ),
          trailing: registered
              ? TextButton(
                  onPressed: _sending ? null : () => _sendTest(registrar),
                  child: Text(_sending ? 'Sending…' : 'Send test'),
                )
              : null,
        );
      },
    );
  }

  Future<void> _sendTest(PushRegistrar registrar) async {
    setState(() => _sending = true);
    final sent = await registrar.sendTestPush(org: widget.org);
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent == null
              ? 'The relay could not send a test notification.'
              : sent == 0
              ? 'The relay has no device to send to. Turn notifications off and on again.'
              : 'Test notification sent to $sent ${sent == 1 ? 'device' : 'devices'}.',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
