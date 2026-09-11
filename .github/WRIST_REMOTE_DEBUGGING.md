# Wrist Remote diagnostics

This note is for future development and regression testing of the Wrist Remote / background BLE path.

## Diagnostic build

Dart-side qUnleashed, flipperlib and BLE logs are compiled out of a normal release build. For a diagnostic release build, enable the logging defines explicitly:

```sh
flutter build apk --release --target-platform android-arm64 --split-per-abi \
  --dart-define=QLOG=true \
  --dart-define=QLOG_LEVEL=trace
```

`trace` is intentionally the maximum level. Use `debug` when the full transport noise is not needed.

The Android MediaSession bridge uses the `WristRemote` logcat tag. Enable its debug messages on the test device when needed:

```sh
adb shell setprop log.tag.WristRemote DEBUG
```

The property is for diagnostics only and can be cleared with:

```sh
adb shell setprop log.tag.WristRemote ""
```

## Focused live log

On Windows cmd.exe:

```bat
adb logcat -c
adb logcat -v time | findstr /i /c:"WristRemote(" /c:"[WristRemote]" /c:"[RemoteInput]" /c:"[BleRecovery]" /c:"[ForegroundService]"
```

The exact markers avoid matching Android's unrelated `RemoteInput` notification API.

Useful markers:

- `WristRemote` — native MediaSession commands and Dart gesture mapping.
- `RemoteInput` — low-level GUI RPC input sequence (`PRESS`, `SHORT`/`LONG`, `RELEASE`).
- `BleRecovery` — app-layer reconnect backoff and recovery.
- `ForegroundService` — recovery hold and foreground-service state changes.

For a hold, the expected RPC sequence is `PRESS`, `LONG` at about +500 ms, then `RELEASE` at the configured 1/2/3 second duration.

## State snapshots

When a failure happens after backgrounding, screen-off, Doze, Activity recreation, or a BLE drop, capture these before reopening qUnleashed if possible:

```bat
adb shell dumpsys media_session > media_session.txt
adb shell dumpsys activity services com.darkflippers.qunleashed > services.txt
adb shell dumpsys bluetooth_manager > bluetooth.txt
adb shell dumpsys deviceidle > deviceidle.txt
adb shell dumpsys package com.darkflippers.qunleashed > package.txt
adb shell dumpsys activity processes | findstr /i "qunleashed" > process.txt
```

Also save the focused logcat output with timestamps. The most useful evidence is whether the same process survived, whether the foreground service remained active, whether the MediaSession remained active, and whether BLE recovery emitted a disconnect/retry/recovered sequence.

## Regression checks

Before changing the wrist-control path, keep these behaviors intact:

- Single tap dispatches immediately when the matching double-tap action is unassigned.
- When a double-tap action is assigned, the single waits only for the 400 ms double-tap window.
- A recognized double tap dispatches only the double action, not a stray single.
- `Tap`, `Hold 1 s`, `Hold 2 s`, and `Hold 3 s` produce the expected RPC input sequence.
- Remote Control visuals may pause in background, but control RPC and the MediaSession remain usable.
- BLE recovery keeps the already-running foreground service alive until reconnect succeeds or the user manually disconnects.
