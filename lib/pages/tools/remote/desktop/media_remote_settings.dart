import 'package:flutter/material.dart';

import 'media_remote.dart';
import 'models/models.dart';

Future<void> showMediaRemoteSettingsDialog(
  BuildContext context,
  MediaRemoteBridge bridge,
) async {
  await bridge.ensureLoaded();
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> setMapping(
            MediaRemoteInput input,
            RemoteButton? button,
          ) async {
            await bridge.setButtonFor(input, button);
            if (context.mounted) setState(() {});
          }

          Future<void> setHold(MediaRemoteInput input, bool hold) async {
            await bridge.setHoldFor(input, hold);
            if (context.mounted) setState(() {});
          }

          Future<void> setQueueWhileDisconnected(bool value) async {
            await bridge.setQueueWhileDisconnected(value);
            if (context.mounted) setState(() {});
          }

          Future<void> reset() async {
            await bridge.resetMappings();
            if (context.mounted) setState(() {});
          }

          return AlertDialog(
            title: const Text('Wrist remote mapping'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose which Flipper button each media gesture sends. '
                      'Double-tap rows can be left unassigned for instant '
                      'single-tap response.',
                    ),
                    const SizedBox(height: 16),
                    for (final input in MediaRemoteInput.values) ...[
                      _MappingRow(
                        input: input,
                        value: bridge.buttonFor(input),
                        hold: bridge.holdFor(input),
                        onChanged: (button) => setMapping(input, button),
                        onHoldChanged: (hold) => setHold(input, hold),
                      ),
                      if (input != MediaRemoteInput.values.last)
                        const Divider(height: 20),
                    ],
                    const Divider(height: 28),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Queue wrist inputs while disconnected',
                      ),
                      subtitle: const Text(
                        'Off drops commands during BLE recovery. On may replay '
                        'them after reconnect.',
                      ),
                      value: bridge.queueWhileDisconnected,
                      onChanged: setQueueWhileDisconnected,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Hold (beta) keeps the selected Flipper button pressed '
                      'for 800 ms. Double taps use a 400 ms gesture window only '
                      'when the matching double-tap action is assigned.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Note: some bands change Android system volume directly '
                      'instead of sending Volume +/- to the media session.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: reset, child: const Text('Reset defaults')),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          );
        },
      );
    },
  );
}

class _MappingRow extends StatelessWidget {
  const _MappingRow({
    required this.input,
    required this.value,
    required this.hold,
    required this.onChanged,
    required this.onHoldChanged,
  });

  final MediaRemoteInput input;
  final RemoteButton? value;
  final bool hold;
  final ValueChanged<RemoteButton?> onChanged;
  final ValueChanged<bool> onHoldChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _inputLabel(input),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButton<RemoteButton?>(
                isExpanded: true,
                value: value,
                onChanged: onChanged,
                items: [
                  const DropdownMenuItem<RemoteButton?>(
                    value: null,
                    child: Text('Not assigned'),
                  ),
                  for (final button in RemoteButton.values)
                    DropdownMenuItem<RemoteButton?>(
                      value: button,
                      child: Text(_buttonLabel(button)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<bool>(
              value: hold,
              onChanged: value == null
                  ? null
                  : (next) {
                      if (next != null) onHoldChanged(next);
                    },
              items: const [
                DropdownMenuItem(value: false, child: Text('Tap')),
                DropdownMenuItem(value: true, child: Text('Hold (beta)')),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

String _inputLabel(MediaRemoteInput input) => switch (input) {
  MediaRemoteInput.previous => '⏮  Previous',
  MediaRemoteInput.doublePrevious => '⏮×2  Double Previous',
  MediaRemoteInput.playPause => '⏯  Play / Pause',
  MediaRemoteInput.doublePlayPause => '⏯×2  Double Play / Pause',
  MediaRemoteInput.next => '⏭  Next',
  MediaRemoteInput.doubleNext => '⏭×2  Double Next',
  MediaRemoteInput.volumeUp => '🔊  Volume +',
  MediaRemoteInput.volumeDown => '🔉  Volume −',
};

String _buttonLabel(RemoteButton button) => switch (button) {
  RemoteButton.up => '↑  Up',
  RemoteButton.down => '↓  Down',
  RemoteButton.left => '←  Left',
  RemoteButton.right => '→  Right',
  RemoteButton.ok => 'OK',
  RemoteButton.back => 'Back',
};
