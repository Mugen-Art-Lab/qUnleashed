import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../services/logging.dart';
import 'models/models.dart';

/// Media controls Android may receive from a watch or fitness band.
enum MediaRemoteInput {
  previous,
  playPause,
  next,
  doublePlayPause,
  volumeUp,
  volumeDown,
}

/// Dart half of the Android MediaSession bridge used by Wrist Remote.
///
/// It is intentionally page-scoped from the user's point of view:
/// RemoteControlPage starts it when mounted and stops it on dispose, so watches
/// only hijack media controls while the user is actively using the Flipper
/// remote. The native bridge itself is engine-scoped and survives Activity
/// recreation.
class MediaRemoteBridge {
  MediaRemoteBridge({required this.onButton});

  static const MethodChannel _channel = MethodChannel(
    'qunleashed/media_remote',
  );

  static const String _prefPrefix = 'remote.media.';

  static const Map<MediaRemoteInput, RemoteButton> _defaults = {
    MediaRemoteInput.previous: RemoteButton.left,
    MediaRemoteInput.playPause: RemoteButton.ok,
    MediaRemoteInput.next: RemoteButton.right,
    MediaRemoteInput.doublePlayPause: RemoteButton.back,
    MediaRemoteInput.volumeUp: RemoteButton.up,
    MediaRemoteInput.volumeDown: RemoteButton.down,
  };

  final void Function(RemoteButton button) onButton;
  final Map<MediaRemoteInput, RemoteButton> _mapping = {..._defaults};

  SharedPreferences? _preferences;
  bool _loaded = false;
  bool _started = false;

  bool get supported => Platform.isAndroid;

  RemoteButton buttonFor(MediaRemoteInput input) =>
      _mapping[input] ?? _defaults[input]!;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final preferences = await SharedPreferences.getInstance();
    _preferences = preferences;

    for (final input in MediaRemoteInput.values) {
      final stored = preferences.getString('$_prefPrefix${input.name}');
      if (stored == null) continue;
      final parsed = _buttonNamed(stored);
      if (parsed != null) _mapping[input] = parsed;
    }
    _loaded = true;
    LogService.debug('[WristRemote] mappings loaded');
  }

  Future<void> setButtonFor(
    MediaRemoteInput input,
    RemoteButton button,
  ) async {
    await ensureLoaded();
    _mapping[input] = button;
    await _preferences!.setString('$_prefPrefix${input.name}', button.name);
    LogService.debug('[WristRemote] mapping ${input.name} -> ${button.name}');
  }

  Future<void> resetMappings() async {
    await ensureLoaded();
    _mapping
      ..clear()
      ..addAll(_defaults);
    for (final input in MediaRemoteInput.values) {
      await _preferences!.remove('$_prefPrefix${input.name}');
    }
    LogService.debug('[WristRemote] mappings reset');
  }

  Future<void> start() async {
    if (!supported || _started) return;
    await ensureLoaded();
    _started = true;
    _channel.setMethodCallHandler(_handleCall);
    LogService.info('[WristRemote] start requested');
    try {
      await _channel.invokeMethod<void>('start');
      LogService.info('[WristRemote] started');
    } catch (e) {
      _started = false;
      _channel.setMethodCallHandler(null);
      LogService.error('[WristRemote] start failed: $e');
    }
  }

  Future<void> stop() async {
    if (!supported || !_started) return;
    _started = false;
    LogService.info('[WristRemote] stop requested');
    try {
      await _channel.invokeMethod<void>('stop');
      LogService.info('[WristRemote] stopped');
    } catch (e) {
      LogService.warn('[WristRemote] stop failed: $e');
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    if (call.method != 'button') {
      throw MissingPluginException('${call.method} is not implemented');
    }

    final input = switch (call.arguments) {
      'left' => MediaRemoteInput.previous,
      'ok' => MediaRemoteInput.playPause,
      'right' => MediaRemoteInput.next,
      'back' => MediaRemoteInput.doublePlayPause,
      'up' => MediaRemoteInput.volumeUp,
      'down' => MediaRemoteInput.volumeDown,
      'previous' => MediaRemoteInput.previous,
      'playPause' => MediaRemoteInput.playPause,
      'next' => MediaRemoteInput.next,
      'doublePlayPause' => MediaRemoteInput.doublePlayPause,
      'volumeUp' => MediaRemoteInput.volumeUp,
      'volumeDown' => MediaRemoteInput.volumeDown,
      _ => null,
    };
    if (input != null) {
      final button = buttonFor(input);
      LogService.debug(
        '[WristRemote] input ${input.name} -> ${button.name}',
      );
      onButton(button);
    }
    return null;
  }

  RemoteButton? _buttonNamed(String name) {
    for (final button in RemoteButton.values) {
      if (button.name == name) return button;
    }
    return null;
  }
}
