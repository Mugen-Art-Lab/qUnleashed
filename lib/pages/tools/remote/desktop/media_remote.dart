import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'models/models.dart';

/// Dart half of the Android MediaSession bridge used by Remote Control.
///
/// It is intentionally page-scoped: RemoteControlPage starts it when mounted
/// and stops it on dispose, so watches only hijack media controls while the
/// user is actively using the Flipper remote.
class MediaRemoteBridge {
  MediaRemoteBridge({required this.onButton});

  static const MethodChannel _channel = MethodChannel(
    'qunleashed/media_remote',
  );

  final void Function(RemoteButton button) onButton;

  bool _started = false;

  bool get supported => Platform.isAndroid;

  Future<void> start() async {
    if (!supported || _started) return;
    _started = true;
    _channel.setMethodCallHandler(_handleCall);
    try {
      await _channel.invokeMethod<void>('start');
    } catch (_) {
      _started = false;
      _channel.setMethodCallHandler(null);
    }
  }

  Future<void> stop() async {
    if (!supported || !_started) return;
    _started = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {
      // Native cleanup is best-effort; losing the Activity tears it down too.
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    if (call.method != 'button') {
      throw MissingPluginException('${call.method} is not implemented');
    }

    final button = switch (call.arguments) {
      'up' => RemoteButton.up,
      'down' => RemoteButton.down,
      'left' => RemoteButton.left,
      'right' => RemoteButton.right,
      'ok' => RemoteButton.ok,
      'back' => RemoteButton.back,
      _ => null,
    };
    if (button != null) onButton(button);
    return null;
  }
}
