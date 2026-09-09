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
            RemoteButton button,
          ) async {
            await bridge.setButtonFor(input, button);
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
                      'Choose which Flipper button each media control sends. '
                      'Available controls depend on the watch or band UI.',
                    ),
                    const SizedBox(height: 16),
                    for (final input in MediaRemoteInput.values) ...[
                      _MappingRow(
                        input: input,
                        value: bridge.buttonFor(input),
                        onChanged: (button) => setMapping(input, button),
                      ),
                      if (input != MediaRemoteInput.values.last)
                        const Divider(height: 20),
                    ],
                    const SizedBox(height: 8),
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
    required this.onChanged,
  });

  final MediaRemoteInput input;
  final RemoteButton value;
  final ValueChanged<RemoteButton> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _inputLabel(input),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        DropdownButton<RemoteButton>(
          value: value,
          onChanged: (button) {
            if (button != null) onChanged(button);
          },
          items: [
            for (final button in RemoteButton.values)
              DropdownMenuItem(
                value: button,
                child: Text(_buttonLabel(button)),
              ),
          ],
        ),
      ],
    );
  }
}

String _inputLabel(MediaRemoteInput input) => switch (input) {
  MediaRemoteInput.previous => '⏮  Previous',
  MediaRemoteInput.playPause => '⏯  Play / Pause',
  MediaRemoteInput.next => '⏭  Next',
  MediaRemoteInput.doublePlayPause => '⏯×2  Double tap',
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
