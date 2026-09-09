import 'dart:async';

import 'package:flipperlib/flipperlib.dart';

import '../logging.dart';

/// Keeps trying a previously connected BLE Flipper after flipperlib's immediate
/// in-place reconnect attempt has been exhausted.
///
/// This deliberately lives above flipperlib: the library still owns the fast
/// single reconnect that preserves the live session, while this service handles
/// the slower "device is still unavailable" case by opening a fresh session.
class BleRecoveryService {
  BleRecoveryService._();

  static final BleRecoveryService instance = BleRecoveryService._();

  static const List<Duration> _retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
  ];

  FlipperClient? _client;
  StreamSubscription<FlipperConnectionState>? _subscription;
  Timer? _retryTimer;
  FlipperDevice? _target;
  int _attempt = 0;
  bool _connectInFlight = false;

  Future<void> start(FlipperClient client) async {
    if (_subscription != null) return;

    _client = client;
    final connected = client.connectedDevice;
    if (connected != null && connected.isBle) {
      _target = connected;
    }

    _subscription = client.connectionStream.listen(_onConnectionState);
    LogService.info('[BleRecovery] started');
  }

  void _onConnectionState(FlipperConnectionState state) {
    final device = state.device;
    if (state.connected && device != null) {
      final wasRecovering = _attempt > 0 || _retryTimer != null;
      if (device.isBle) {
        _target = device;
      } else {
        _target = null;
      }
      _attempt = 0;
      _connectInFlight = false;
      _cancelRetry();
      if (wasRecovering) {
        LogService.info(
          '[BleRecovery] recovered ${device.name} (${device.id})',
        );
      }
      return;
    }

    if (_isManualDisconnect(state.closeReason)) {
      LogService.info('[BleRecovery] manual disconnect; retries cancelled');
      _target = null;
      _attempt = 0;
      _connectInFlight = false;
      _cancelRetry();
      return;
    }

    // flipperlib owns the immediate in-place reconnect. Only step in after it
    // emits the terminal disconnected state.
    if (state.reconnecting || state.connecting) return;

    final target = _target;
    if (target == null || !target.isBle) return;
    _scheduleRetry();
  }

  bool _isManualDisconnect(Object? reason) {
    return reason?.toString().contains('disconnect requested') ?? false;
  }

  void _scheduleRetry() {
    if (_retryTimer != null || _connectInFlight) return;

    final target = _target;
    if (target == null) return;

    final delayIndex = _attempt < _retryDelays.length
        ? _attempt
        : _retryDelays.length - 1;
    final delay = _retryDelays[delayIndex];
    final attemptNumber = _attempt + 1;

    LogService.info(
      '[BleRecovery] retry $attemptNumber for ${target.name} '
      'in ${delay.inSeconds}s',
    );

    _retryTimer = Timer(delay, () async {
      _retryTimer = null;

      final client = _client;
      final currentTarget = _target;
      if (client == null || currentTarget == null) return;
      if (client.isConnected) {
        _attempt = 0;
        return;
      }
      if (client.isConnecting) {
        LogService.debug(
          '[BleRecovery] retry $attemptNumber deferred: connect in progress',
        );
        _scheduleRetry();
        return;
      }

      _attempt = attemptNumber;
      _connectInFlight = true;
      LogService.info(
        '[BleRecovery] retry $attemptNumber connecting to '
        '${currentTarget.name}',
      );

      try {
        await client.connect(currentTarget);
      } catch (error) {
        LogService.warn(
          '[BleRecovery] retry $attemptNumber failed: $error',
        );
      } finally {
        _connectInFlight = false;
      }

      if (!client.isConnected && identical(_target, currentTarget)) {
        _scheduleRetry();
      }
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}
