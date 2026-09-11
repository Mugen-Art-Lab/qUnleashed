import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../services/logging.dart';
import 'models/models.dart';

/// Media controls Android may receive from a watch or fitness band.
enum MediaRemoteInput {
  previous,
  doublePrevious,
  playPause,
  doublePlayPause,
  next,
  doubleNext,
  volumeUp,
  volumeDown,
}

/// Gesture timing used by Wrist Remote mappings.
const Duration wristRemoteDoubleTapDuration = Duration(milliseconds: 400);
const Duration wristRemoteHoldDuration = Duration(milliseconds: 800);

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
  static const String _queueWhileDisconnectedPref =
      '${_prefPrefix}queueWhileDisconnected';
  static const String _notAssignedValue = '__none__';

  static const Map<MediaRemoteInput, RemoteButton?> _defaults = {
    MediaRemoteInput.previous: RemoteButton.left,
    MediaRemoteInput.doublePrevious: null,
    MediaRemoteInput.playPause: RemoteButton.ok,
    MediaRemoteInput.doublePlayPause: RemoteButton.back,
    MediaRemoteInput.next: RemoteButton.right,
    MediaRemoteInput.doubleNext: null,
    MediaRemoteInput.volumeUp: RemoteButton.up,
    MediaRemoteInput.volumeDown: RemoteButton.down,
  };

  final void Function(RemoteButton button, bool hold) onButton;
  final Map<MediaRemoteInput, RemoteButton?> _mapping = {..._defaults};
  final Map<MediaRemoteInput, bool> _holdMapping = {};
  final Map<MediaRemoteInput, Timer> _pendingSingleTaps = {};

  SharedPreferences? _preferences;
  bool _loaded = false;
  bool _started = false;
  bool _queueWhileDisconnected = false;

  bool get supported => Platform.isAndroid;
  bool get queueWhileDisconnected => _queueWhileDisconnected;

  RemoteButton? buttonFor(MediaRemoteInput input) => _mapping[input];

  bool holdFor(MediaRemoteInput input) => _holdMapping[input] ?? false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final preferences = await SharedPreferences.getInstance();
    _preferences = preferences;

    for (final input in MediaRemoteInput.values) {
      final stored = preferences.getString('$_prefPrefix${input.name}');
      if (stored == _notAssignedValue) {
        _mapping[input] = null;
      } else if (stored != null) {
        final parsed = _buttonNamed(stored);
        if (parsed != null) _mapping[input] = parsed;
      }
      _holdMapping[input] =
          preferences.getBool('$_prefPrefix${input.name}.hold') ?? false;
    }
    _queueWhileDisconnected =
        preferences.getBool(_queueWhileDisconnectedPref) ?? false;
    _loaded = true;
    LogService.debug(
      '[WristRemote] mappings loaded; queueWhileDisconnected='
      '$_queueWhileDisconnected',
    );
  }

  Future<void> setButtonFor(
    MediaRemoteInput input,
    RemoteButton? button,
  ) async {
    await ensureLoaded();
    _mapping[input] = button;
    await _preferences!.setString(
      '$_prefPrefix${input.name}',
      button?.name ?? _notAssignedValue,
    );
    LogService.debug(
      '[WristRemote] mapping ${input.name} -> ${button?.name ?? 'none'}',
    );
  }

  Future<void> setHoldFor(MediaRemoteInput input, bool hold) async {
    await ensureLoaded();
    _holdMapping[input] = hold;
    await _preferences!.setBool('$_prefPrefix${input.name}.hold', hold);
    LogService.debug('[WristRemote] mapping ${input.name} hold -> $hold');
  }

  Future<void> setQueueWhileDisconnected(bool value) async {
    await ensureLoaded();
    _queueWhileDisconnected = value;
    await _preferences!.setBool(_queueWhileDisconnectedPref, value);
    LogService.info('[WristRemote] queue while disconnected -> $value');
  }

  Future<void> resetMappings() async {
    await ensureLoaded();
    _cancelPendingTaps();
    _mapping
      ..clear()
      ..addAll(_defaults);
    _holdMapping.clear();
    _queueWhileDisconnected = false;
    for (final input in MediaRemoteInput.values) {
      await _preferences!.remove('$_prefPrefix${input.name}');
      await _preferences!.remove('$_prefPrefix${input.name}.hold');
    }
    await _preferences!.remove(_queueWhileDisconnectedPref);
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
    _cancelPendingTaps();
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

    switch (call.arguments) {
      case 'left':
      case 'previous':
        _handleTap(MediaRemoteInput.previous, MediaRemoteInput.doublePrevious);
      case 'ok':
      case 'playPause':
        _handleTap(MediaRemoteInput.playPause, MediaRemoteInput.doublePlayPause);
      case 'right':
      case 'next':
        _handleTap(MediaRemoteInput.next, MediaRemoteInput.doubleNext);
      case 'back':
      case 'doublePlayPause':
        _dispatch(MediaRemoteInput.doublePlayPause);
      case 'doublePrevious':
        _dispatch(MediaRemoteInput.doublePrevious);
      case 'doubleNext':
        _dispatch(MediaRemoteInput.doubleNext);
      case 'up':
      case 'volumeUp':
        _dispatch(MediaRemoteInput.volumeUp);
      case 'down':
      case 'volumeDown':
        _dispatch(MediaRemoteInput.volumeDown);
    }
    return null;
  }

  void _handleTap(MediaRemoteInput single, MediaRemoteInput doubleTap) {
    if (buttonFor(doubleTap) == null) {
      _dispatch(single);
      return;
    }

    final pending = _pendingSingleTaps.remove(single);
    if (pending != null) {
      pending.cancel();
      _dispatch(doubleTap);
      return;
    }

    _pendingSingleTaps[single] = Timer(wristRemoteDoubleTapDuration, () {
      _pendingSingleTaps.remove(single);
      _dispatch(single);
    });
  }

  void _dispatch(MediaRemoteInput input) {
    final button = buttonFor(input);
    if (button == null) {
      LogService.debug('[WristRemote] input ${input.name} ignored: unassigned');
      return;
    }
    final hold = holdFor(input);
    LogService.debug(
      '[WristRemote] input ${input.name} -> ${button.name}'
      '${hold ? ' (hold)' : ''}',
    );
    onButton(button, hold);
  }

  void _cancelPendingTaps() {
    for (final timer in _pendingSingleTaps.values) {
      timer.cancel();
    }
    _pendingSingleTaps.clear();
  }

  RemoteButton? _buttonNamed(String name) {
    for (final button in RemoteButton.values) {
      if (button.name == name) return button;
    }
    return null;
  }
}
