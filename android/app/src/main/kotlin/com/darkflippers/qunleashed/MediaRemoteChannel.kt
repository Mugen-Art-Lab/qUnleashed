package com.darkflippers.qunleashed

import android.content.Context
import android.content.Intent
import android.media.MediaMetadata
import android.media.VolumeProvider
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Android MediaSession bridge used by the Remote Control page.
 *
 * A watch can keep talking to Android as if it were controlling music while
 * qUnleashed turns those transport/volume commands into Flipper button names
 * and forwards them to Dart over a MethodChannel.
 */
class MediaRemoteChannel(
    context: Context,
    flutterEngine: FlutterEngine,
) {
    companion object {
        private const val CHANNEL = "qunleashed/media_remote"
        private const val DOUBLE_TAP_MS = 400L

        private const val ACTIONS =
            PlaybackState.ACTION_PLAY or
                PlaybackState.ACTION_PAUSE or
                PlaybackState.ACTION_PLAY_PAUSE or
                PlaybackState.ACTION_SKIP_TO_NEXT or
                PlaybackState.ACTION_SKIP_TO_PREVIOUS
    }

    private val appContext = context.applicationContext
    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var mediaSession: MediaSession? = null
    private var pendingCenterTap: Runnable? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    start()
                    result.success(null)
                }
                "stop" -> {
                    stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        stop()
        channel.setMethodCallHandler(null)
    }

    private fun start() {
        if (mediaSession != null) return

        val session = MediaSession(appContext, "qUnleashed Flipper Remote")
        session.setCallback(
            object : MediaSession.Callback() {
                override fun onPlay() = centerTap()

                override fun onPause() = centerTap()

                override fun onSkipToPrevious() = sendButton("left")

                override fun onSkipToNext() = sendButton("right")

                override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                    @Suppress("DEPRECATION")
                    val event = mediaButtonIntent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT)
                        ?: return super.onMediaButtonEvent(mediaButtonIntent)
                    if (event.action != KeyEvent.ACTION_DOWN || event.repeatCount != 0) return true

                    return when (event.keyCode) {
                        KeyEvent.KEYCODE_MEDIA_PREVIOUS -> {
                            sendButton("left")
                            true
                        }
                        KeyEvent.KEYCODE_MEDIA_NEXT -> {
                            sendButton("right")
                            true
                        }
                        KeyEvent.KEYCODE_MEDIA_PLAY,
                        KeyEvent.KEYCODE_MEDIA_PAUSE,
                        KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
                        -> {
                            centerTap()
                            true
                        }
                        else -> super.onMediaButtonEvent(mediaButtonIntent)
                    }
                }
            },
            mainHandler,
        )

        session.setPlaybackState(
            PlaybackState.Builder()
                .setActions(ACTIONS)
                // Keep the fake player "playing" so it remains the preferred
                // media-button target while Remote Control is open.
                .setState(
                    PlaybackState.STATE_PLAYING,
                    PlaybackState.PLAYBACK_POSITION_UNKNOWN,
                    1.0f,
                )
                .build(),
        )
        session.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, "Flipper Remote")
                .putString(MediaMetadata.METADATA_KEY_ARTIST, "qUnleashed · Mi Band")
                .putString(MediaMetadata.METADATA_KEY_ALBUM, "Mugen Art Lab")
                .build(),
        )
        session.setPlaybackToRemote(
            object : VolumeProvider(VOLUME_CONTROL_RELATIVE, 100, 50) {
                override fun onAdjustVolume(direction: Int) {
                    when {
                        direction > 0 -> sendButton("up")
                        direction < 0 -> sendButton("down")
                    }
                }
            },
        )
        session.isActive = true
        mediaSession = session
    }

    private fun stop() {
        pendingCenterTap?.let(mainHandler::removeCallbacks)
        pendingCenterTap = null

        mediaSession?.let { session ->
            session.isActive = false
            session.release()
        }
        mediaSession = null
    }

    /**
     * Single play/pause is OK. A second tap inside the small gesture window
     * cancels the pending OK and becomes BACK instead.
     */
    private fun centerTap() {
        val pending = pendingCenterTap
        if (pending != null) {
            mainHandler.removeCallbacks(pending)
            pendingCenterTap = null
            sendButton("back")
            return
        }

        val singleTap = Runnable {
            pendingCenterTap = null
            sendButton("ok")
        }
        pendingCenterTap = singleTap
        mainHandler.postDelayed(singleTap, DOUBLE_TAP_MS)
    }

    private fun sendButton(button: String) {
        mainHandler.post {
            channel.invokeMethod("button", button)
        }
    }
}
