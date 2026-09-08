package com.dmgworkshop.transcript_app

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Receives a recording shared into the app from somewhere else — Files, Drive, a
 * conferencing app's export — and hands its path to Dart.
 *
 * Shares arrive as `content://` URIs, which are permission-scoped handles rather than
 * paths: the bytes are copied into the app's cache here, because the grant can be revoked
 * the moment the sending app's task finishes and a path captured from it would then read
 * as an empty file.
 */
class SharedFilePlugin(
    private val context: android.content.Context,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "kallanotes/shared_file"
    }

    /**
     * A share that arrived before Dart was ready to hear about it.
     *
     * A cold launch runs the intent through here well before the Flutter widget tree
     * exists, so it is held until the first `takeSharedFile` asks for it.
     */
    private var pending: String? = null

    /**
     * Whether Dart has asked for a pending share yet.
     *
     * The first ask is what proves the Flutter side is up and listening, which decides
     * how a share is delivered: held for collection before that, pushed after. A share
     * that was both held *and* pushed would be imported twice — a duplicate note, and the
     * transcription billed twice.
     */
    private var dartIsListening = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Read-and-clear: importing the same file every time the app resumes would be
            // worse than missing one.
            "takeSharedFile" -> {
                dartIsListening = true
                result.success(pending)
                pending = null
            }
            else -> result.notImplemented()
        }
    }

    /** Returns true when the intent carried something worth importing. */
    fun handleIntent(intent: Intent?): Boolean {
        val incoming = intent ?: return false
        val uri = when (incoming.action) {
            Intent.ACTION_SEND ->
                incoming.getParcelableExtraCompat<Uri>(Intent.EXTRA_STREAM)
            Intent.ACTION_VIEW -> incoming.data
            else -> null
        } ?: return false

        val path = try {
            copyToCache(uri)
        } catch (e: Exception) {
            // A share that cannot be read is not worth crashing the launch over; the user
            // still gets a working app and can import through the picker.
            null
        } ?: return false

        if (dartIsListening) {
            channel.invokeMethod("onSharedFile", path)
        } else {
            pending = path
        }
        return true
    }

    private fun copyToCache(uri: Uri): String? {
        val name = displayName(uri) ?: "shared"
        val extension = extensionFor(uri, name)

        val directory = File(context.cacheDir, "shared").apply { mkdirs() }
        val target = File(
            directory,
            "${System.currentTimeMillis()}_${name.substringBeforeLast('.').take(64)}$extension",
        )

        context.contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        } ?: return null

        return if (target.length() > 0) target.absolutePath else null
    }

    private fun displayName(uri: Uri): String? =
        context.contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst() && cursor.columnCount > 0) cursor.getString(0) else null
            }

    /**
     * The extension the Dart side matches on, with a leading dot, or "" when it cannot be
     * determined — an unnamed share is then refused by name rather than half-imported.
     */
    private fun extensionFor(uri: Uri, name: String): String {
        val fromName = name.substringAfterLast('.', "")
        if (fromName.isNotEmpty() && fromName.length <= 5) return ".$fromName"

        val mime = context.contentResolver.getType(uri) ?: return ""
        val fromMime = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)
        return if (fromMime.isNullOrEmpty()) "" else ".$fromMime"
    }
}
