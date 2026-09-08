package com.dmgworkshop.transcript_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import androidx.annotation.RequiresApi
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread

/**
 * Records what the device is playing — a webinar, a lecture recording, a podcast — into the
 * 16 kHz mono WAV the transcription pipeline expects.
 *
 * This is NOT call recording and cannot become it. Android's playback capture only ever
 * yields streams whose usage is MEDIA, GAME or UNKNOWN; VOICE_COMMUNICATION, which every
 * conferencing app uses for calls, is excluded by the platform, and an app that opts out
 * with `allowAudioPlaybackCapture="false"` is silent here too. What comes back for a Zoom
 * call is silence, not audio, which is why the UI says so plainly rather than letting a
 * user discover it after an hour of "recording".
 *
 * Lives in a foreground service because Android 14+ requires one of type `mediaProjection`
 * to be *already running* before `getMediaProjection` is called — the projection is
 * refused otherwise.
 */
@RequiresApi(Build.VERSION_CODES.Q)
class DeviceAudioCaptureService : Service() {

    companion object {
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_RESULT_DATA = "resultData"
        const val EXTRA_TARGET_PATH = "targetPath"

        private const val NOTIFICATION_ID = 0x4B4E01
        private const val CHANNEL_ID = "kallanotes_device_audio"

        const val SAMPLE_RATE = 16000

        /**
         * How the capture ended, read by the plugin once the service stops.
         *
         * Static because the service is started with an Intent rather than bound: binding
         * would add a connection lifecycle to manage for what is one path and one error.
         */
        @Volatile
        var outcome: Result<String>? = null
            private set

        @Volatile
        private var running = false

        fun isRunning() = running

        fun clearOutcome() {
            outcome = null
        }

        fun intent(context: Context, resultCode: Int, data: Intent, targetPath: String) =
            Intent(context, DeviceAudioCaptureService::class.java).apply {
                putExtra(EXTRA_RESULT_CODE, resultCode)
                putExtra(EXTRA_RESULT_DATA, data)
                putExtra(EXTRA_TARGET_PATH, targetPath)
            }
    }

    private var projection: MediaProjection? = null
    private var record: AudioRecord? = null
    private var capture: Thread? = null

    @Volatile
    private var stopping = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, 0) ?: 0
        val data = intent?.getParcelableExtraCompat<Intent>(EXTRA_RESULT_DATA)
        val targetPath = intent?.getStringExtra(EXTRA_TARGET_PATH)

        if (data == null || targetPath == null) {
            finishWith(Result.failure(IllegalStateException("capture was not configured")))
            stopSelf()
            return START_NOT_STICKY
        }

        // Must be foreground, with this exact type, BEFORE getMediaProjection is called.
        startForeground(
            NOTIFICATION_ID,
            buildNotification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
        )

        try {
            start(resultCode, data, targetPath)
        } catch (e: Exception) {
            finishWith(Result.failure(e))
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun start(resultCode: Int, data: Intent, targetPath: String) {
        val manager =
            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val projection = manager.getMediaProjection(resultCode, data)
            ?: throw IllegalStateException("Screen capture consent was not granted.")
        this.projection = projection

        // Mandatory since Android 14: without a registered callback the projection is
        // refused. It also covers the user revoking the cast from the system UI mid-capture.
        projection.registerCallback(
            object : MediaProjection.Callback() {
                override fun onStop() {
                    stopCapture()
                }
            },
            null,
        )

        val config = AudioPlaybackCaptureConfiguration.Builder(projection)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()

        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(SAMPLE_RATE)
            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
            .build()

        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        ).coerceAtLeast(SAMPLE_RATE) // at least half a second of headroom

        val record = AudioRecord.Builder()
            .setAudioFormat(format)
            .setBufferSizeInBytes(minBuffer * 2)
            .setAudioPlaybackCaptureConfig(config)
            .build()
        this.record = record

        running = true
        stopping = false
        record.startRecording()

        capture = thread(name = "kallanotes-device-audio") {
            writeWav(record, File(targetPath), minBuffer)
        }
    }

    /** Reads until stopped, leaving a complete WAV behind whichever way it ends. */
    private fun writeWav(record: AudioRecord, target: File, bufferSize: Int) {
        val buffer = ByteArray(bufferSize)
        var written = 0

        try {
            RandomAccessFile(target, "rw").use { out ->
                out.setLength(0)
                out.write(ByteArray(44)) // placeholder, rewritten below

                while (!stopping) {
                    val read = record.read(buffer, 0, buffer.size)
                    if (read > 0) {
                        out.write(buffer, 0, read)
                        written += read
                    } else if (read < 0) {
                        break // the record was invalidated; keep what we have
                    }
                }

                out.seek(0)
                out.write(wavHeader(written))
            }
            finishWith(
                if (written > 0) {
                    Result.success(target.path)
                } else {
                    // Every app playing was either using a call stream or had opted out.
                    Result.failure(SilentCaptureException())
                }
            )
        } catch (e: Exception) {
            finishWith(Result.failure(e))
        }
    }

    /** Distinguishes "captured nothing" from "failed", because the remedy differs. */
    class SilentCaptureException : Exception("No capturable audio was playing.")

    private fun stopCapture() {
        if (stopping) return
        stopping = true
        try {
            record?.stop()
        } catch (_: IllegalStateException) {
            // Already stopped; releasing is what matters.
        }
        capture?.join(2000)
        record?.release()
        record = null
        projection?.stop()
        projection = null
        running = false
    }

    private fun finishWith(result: Result<String>) {
        outcome = result
        running = false
    }

    override fun onDestroy() {
        stopCapture()
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Device audio recording",
                    NotificationManager.IMPORTANCE_LOW,
                )
            )
        }

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Recording device audio")
            .setContentText("KallaNotes is recording what this device is playing.")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .build()
    }

    /** The canonical 44-byte RIFF/WAVE header for 16 kHz mono PCM16. */
    private fun wavHeader(dataLength: Int): ByteArray {
        val bytesPerFrame = 2
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray(Charsets.US_ASCII))
        header.putInt(36 + dataLength)
        header.put("WAVE".toByteArray(Charsets.US_ASCII))
        header.put("fmt ".toByteArray(Charsets.US_ASCII))
        header.putInt(16)
        header.putShort(1.toShort()) // PCM
        header.putShort(1.toShort()) // mono
        header.putInt(SAMPLE_RATE)
        header.putInt(SAMPLE_RATE * bytesPerFrame)
        header.putShort(bytesPerFrame.toShort())
        header.putShort(16.toShort())
        header.put("data".toByteArray(Charsets.US_ASCII))
        header.putInt(dataLength)
        return header.array()
    }
}

/** `getParcelableExtra` is deprecated from API 33; one call site covers both. */
@Suppress("DEPRECATION")
internal inline fun <reified T : android.os.Parcelable> Intent.getParcelableExtraCompat(
    key: String,
): T? =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        getParcelableExtra(key, T::class.java)
    } else {
        getParcelableExtra(key)
    }
