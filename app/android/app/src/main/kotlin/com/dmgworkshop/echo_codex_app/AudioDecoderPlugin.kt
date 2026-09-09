package com.dmgworkshop.echo_codex_app

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread

/**
 * Decodes any container Android can open into the 16 kHz mono PCM16 WAV the transcription
 * pipeline expects.
 *
 * Uses the platform's own codecs rather than bundling decoders: MP3, AAC, FLAC, Vorbis and
 * the MP4 family are all already on the device, and shipping copies would add tens of
 * megabytes to reproduce what is there.
 */
class AudioDecoderPlugin : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "com.echocodex/audio_decoder"

        private const val TARGET_SAMPLE_RATE = 16000
        private const val TARGET_CHANNELS = 1

        /** Long enough that a slow codec is not mistaken for a stall, short enough to notice one. */
        private const val DEQUEUE_TIMEOUT_US = 10_000L
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "decodeToWav" -> {
                val sourcePath = call.argument<String>("sourcePath")
                val targetPath = call.argument<String>("targetPath")
                if (sourcePath == null || targetPath == null) {
                    result.error("bad_arguments", "sourcePath and targetPath are required", null)
                    return
                }

                // Decoding an hour of audio takes long enough to drop frames on the main
                // thread; the result is posted back on it, which is where Flutter needs it.
                thread(name = "echocodex-decode") {
                    try {
                        decodeToWav(sourcePath, targetPath)
                        postSuccess(result)
                    } catch (e: DecodeException) {
                        postError(result, e.code, e.message ?: "decode failed")
                    } catch (e: Exception) {
                        postError(result, "decode_failed", e.message ?: e.toString())
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun postSuccess(result: MethodChannel.Result) {
        android.os.Handler(android.os.Looper.getMainLooper()).post { result.success(null) }
    }

    private fun postError(result: MethodChannel.Result, code: String, message: String) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            result.error(code, message, null)
        }
    }

    private class DecodeException(val code: String, message: String) : Exception(message)

    private fun decodeToWav(sourcePath: String, targetPath: String) {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        val target = File(targetPath)

        try {
            extractor.setDataSource(sourcePath)

            val trackIndex = (0 until extractor.trackCount).firstOrNull { index ->
                extractor.getTrackFormat(index)
                    .getString(MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            } ?: throw DecodeException("no_audio_track", "The file contains no audio track.")

            extractor.selectTrack(trackIndex)
            val inputFormat = extractor.getTrackFormat(trackIndex)
            val mime = inputFormat.getString(MediaFormat.KEY_MIME)
                ?: throw DecodeException("no_audio_track", "The audio track has no type.")

            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(inputFormat, null, null, 0)
            codec.start()

            RandomAccessFile(target, "rw").use { out ->
                out.setLength(0)
                // Placeholder header, rewritten once the sample count is known.
                out.write(ByteArray(44))

                val written = drain(extractor, codec, inputFormat, out)

                out.seek(0)
                out.write(wavHeader(written))
            }
        } finally {
            try {
                codec?.stop()
            } catch (_: Exception) {
                // Already in an error state; releasing is what matters.
            }
            codec?.release()
            extractor.release()
        }
    }

    /** Pumps the extractor through the codec, converting each output buffer as it lands. */
    private fun drain(
        extractor: MediaExtractor,
        codec: MediaCodec,
        inputFormat: MediaFormat,
        out: RandomAccessFile,
    ): Int {
        val info = MediaCodec.BufferInfo()
        var sawInputEnd = false
        var sawOutputEnd = false
        var bytesWritten = 0

        // Seeded from the container and then corrected by INFO_OUTPUT_FORMAT_CHANGED, which
        // is what a decoder actually outputs and can differ from what the track declared.
        // Seeded rather than left at zero so a codec that emits a buffer before announcing
        // its format does not have that audio silently dropped.
        var sourceRate = inputFormat.optionalInt(MediaFormat.KEY_SAMPLE_RATE)
        var sourceChannels = inputFormat.optionalInt(MediaFormat.KEY_CHANNEL_COUNT)

        while (!sawOutputEnd) {
            if (!sawInputEnd) {
                val inputIndex = codec.dequeueInputBuffer(DEQUEUE_TIMEOUT_US)
                if (inputIndex >= 0) {
                    val buffer = codec.getInputBuffer(inputIndex)!!
                    val size = extractor.readSampleData(buffer, 0)
                    if (size < 0) {
                        codec.queueInputBuffer(
                            inputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                        )
                        sawInputEnd = true
                    } else {
                        codec.queueInputBuffer(inputIndex, 0, size, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }

            when (val outputIndex = codec.dequeueOutputBuffer(info, DEQUEUE_TIMEOUT_US)) {
                MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val format = codec.outputFormat
                    sourceRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    sourceChannels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                }
                MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                else -> {
                    if (outputIndex >= 0) {
                        if (info.size > 0 && sourceRate > 0 && sourceChannels > 0) {
                            val buffer = codec.getOutputBuffer(outputIndex)!!
                            buffer.position(info.offset)
                            buffer.limit(info.offset + info.size)
                            val pcm = convert(buffer, sourceRate, sourceChannels)
                            out.write(pcm)
                            bytesWritten += pcm.size
                        }
                        codec.releaseOutputBuffer(outputIndex, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            sawOutputEnd = true
                        }
                    }
                }
            }
        }

        if (bytesWritten == 0) {
            throw DecodeException("no_audio", "The file decoded to no audio.")
        }
        return bytesWritten
    }

    /**
     * Downmixes to mono and resamples to 16 kHz.
     *
     * Channels are averaged rather than dropped: a meeting recorded in stereo often has one
     * speaker louder on each side, and taking the left channel loses a participant.
     */
    private fun convert(buffer: ByteBuffer, sourceRate: Int, sourceChannels: Int): ByteArray {
        val shorts = buffer.order(ByteOrder.nativeOrder()).asShortBuffer()
        val frames = shorts.remaining() / sourceChannels.coerceAtLeast(1)
        if (frames <= 0) return ByteArray(0)

        val mono = ShortArray(frames)
        for (frame in 0 until frames) {
            var sum = 0
            for (channel in 0 until sourceChannels) {
                sum += shorts.get(frame * sourceChannels + channel).toInt()
            }
            mono[frame] = (sum / sourceChannels).coerceIn(-32768, 32767).toShort()
        }

        val resampled = if (sourceRate == TARGET_SAMPLE_RATE) mono else resample(mono, sourceRate)

        val out = ByteBuffer.allocate(resampled.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (sample in resampled) out.putShort(sample)
        return out.array()
    }

    /**
     * Linear resampling, matching what the Dart side does for WAV imports.
     *
     * Not a windowed-sinc filter on purpose: this feeds speech recognition, which
     * band-limits to speech content anyway. What has to be right is the sample count — a
     * rate error stretches the audio and every timestamp in the transcript with it.
     */
    private fun resample(input: ShortArray, fromRate: Int): ShortArray {
        if (input.isEmpty() || fromRate <= 0) return ShortArray(0)

        val outLength = (input.size.toLong() * TARGET_SAMPLE_RATE / fromRate).toInt()
        if (outLength <= 0) return ShortArray(0)

        val out = ShortArray(outLength)
        val step = fromRate.toDouble() / TARGET_SAMPLE_RATE
        for (i in 0 until outLength) {
            val position = i * step
            val left = position.toInt().coerceIn(0, input.size - 1)
            val right = (left + 1).coerceIn(0, input.size - 1)
            val fraction = position - position.toInt()
            val value = input[left] + (input[right] - input[left]) * fraction
            out[i] = value.toInt().coerceIn(-32768, 32767).toShort()
        }
        return out
    }

    /** `getInteger` throws when a key is absent, and not every container declares both. */
    private fun MediaFormat.optionalInt(key: String): Int =
        if (containsKey(key)) getInteger(key) else 0

    /** The canonical 44-byte RIFF/WAVE header for [dataLength] bytes of 16 kHz mono PCM16. */
    private fun wavHeader(dataLength: Int): ByteArray {
        val bytesPerFrame = TARGET_CHANNELS * 2
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray(Charsets.US_ASCII))
        header.putInt(36 + dataLength)
        header.put("WAVE".toByteArray(Charsets.US_ASCII))
        header.put("fmt ".toByteArray(Charsets.US_ASCII))
        header.putInt(16)
        header.putShort(1.toShort()) // PCM
        header.putShort(TARGET_CHANNELS.toShort())
        header.putInt(TARGET_SAMPLE_RATE)
        header.putInt(TARGET_SAMPLE_RATE * bytesPerFrame)
        header.putShort(bytesPerFrame.toShort())
        header.putShort(16.toShort())
        header.put("data".toByteArray(Charsets.US_ASCII))
        header.putInt(dataLength)
        return header.array()
    }
}
