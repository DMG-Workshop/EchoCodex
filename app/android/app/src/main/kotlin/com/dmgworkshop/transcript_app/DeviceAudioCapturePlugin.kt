package com.dmgworkshop.transcript_app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Records what the device is playing, for a webinar or lecture the user is listening to
 * rather than speaking in.
 *
 * Deliberately narrow, because the platform is: Android's playback capture yields only
 * MEDIA, GAME and UNKNOWN usages. Call audio — every conferencing app, including Zoom,
 * Teams and Meet — is excluded by the OS and always will be, and an app can opt out of
 * being captured at all. This is honest about that rather than promising call recording it
 * cannot deliver.
 */
class DeviceAudioCapturePlugin(
    private val context: Context,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "kallanotes/device_audio"

        /** Distinct enough not to collide with anything the Flutter plugins use. */
        const val CONSENT_REQUEST_CODE = 0x4B4E

        /** Playback capture arrived in Android 10. */
        val isSupported: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
    }

    /** Set while a consent dialog is up, so its result can be answered on the channel. */
    private var pendingStart: MethodChannel.Result? = null
    private var targetPath: String? = null

    var activity: Activity? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(isSupported)
            "start" -> start(call.argument<String>("targetPath"), result)
            "stop" -> stop(result)
            else -> result.notImplemented()
        }
    }

    private fun start(path: String?, result: MethodChannel.Result) {
        if (!isSupported) {
            result.error(
                "unsupported",
                "Recording device audio needs Android 10 or newer.",
                null,
            )
            return
        }
        if (path == null) {
            result.error("bad_arguments", "targetPath is required", null)
            return
        }
        val activity = this.activity
        if (activity == null) {
            result.error("no_activity", "The app is not in the foreground.", null)
            return
        }
        if (pendingStart != null) {
            result.error("busy", "A recording is already starting.", null)
            return
        }

        pendingStart = result
        targetPath = path
        DeviceAudioCaptureService.clearOutcome()

        // Consent is single-use on Android 14+: a fresh intent for every session, never a
        // stored token.
        val manager =
            context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        activity.startActivityForResult(
            manager.createScreenCaptureIntent(),
            CONSENT_REQUEST_CODE,
        )
    }

    /** Returns true when this was the consent result, so the activity can stop looking. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != CONSENT_REQUEST_CODE) return false

        val result = pendingStart ?: return true
        val path = targetPath
        pendingStart = null
        targetPath = null

        if (resultCode != Activity.RESULT_OK || data == null || path == null) {
            result.error("denied", "Screen capture was not allowed.", null)
            return true
        }

        try {
            // The service must be foreground before it touches the projection, so it is
            // started here and does the rest itself.
            val intent = DeviceAudioCaptureService.intent(context, resultCode, data, path)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("start_failed", e.message ?: e.toString(), null)
        }
        return true
    }

    private fun stop(result: MethodChannel.Result) {
        context.stopService(Intent(context, DeviceAudioCaptureService::class.java))

        // The capture thread finalises the WAV header as it unwinds, so the outcome may
        // land a moment after stopService returns.
        waitForOutcome { outcome ->
            when {
                outcome == null -> result.error(
                    "no_result",
                    "The recording did not finish cleanly.",
                    null,
                )
                outcome.isSuccess -> result.success(outcome.getOrNull())
                outcome.exceptionOrNull()
                    is DeviceAudioCaptureService.SilentCaptureException -> result.error(
                    "silent",
                    "Nothing capturable was playing.",
                    null,
                )
                else -> result.error(
                    "capture_failed",
                    outcome.exceptionOrNull()?.message ?: "Recording failed.",
                    null,
                )
            }
        }
    }

    /** Polls briefly rather than blocking the platform thread outright. */
    private fun waitForOutcome(onDone: (Result<String>?) -> Unit) {
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        val deadline = System.currentTimeMillis() + 3000

        fun poll() {
            val outcome = DeviceAudioCaptureService.outcome
            if (outcome != null || System.currentTimeMillis() > deadline) {
                onDone(outcome)
            } else {
                handler.postDelayed(::poll, 50)
            }
        }
        handler.post(::poll)
    }
}
