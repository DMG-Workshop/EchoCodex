package com.dmgworkshop.transcript_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var sharedFiles: SharedFilePlugin? = null
    private var deviceAudio: DeviceAudioCapturePlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AudioDecoderPlugin.CHANNEL_NAME,
        ).setMethodCallHandler(AudioDecoderPlugin())

        val sharedFileChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SharedFilePlugin.CHANNEL_NAME,
        )
        val plugin = SharedFilePlugin(applicationContext, sharedFileChannel)
        sharedFileChannel.setMethodCallHandler(plugin)
        sharedFiles = plugin

        val deviceAudioChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DeviceAudioCapturePlugin.CHANNEL_NAME,
        )
        val capture = DeviceAudioCapturePlugin(applicationContext, deviceAudioChannel)
        capture.activity = this
        deviceAudioChannel.setMethodCallHandler(capture)
        deviceAudio = capture

        // The launch intent is read here rather than in onCreate: the channel has to exist
        // before a share can be handed over, and configureFlutterEngine is the first point
        // at which it does.
        plugin.handleIntent(intent)
    }

    /** A share arriving while the app is already open. `launchMode` is singleTop. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        sharedFiles?.handleIntent(intent)
    }

    /** The screen-capture consent dialog reports back here. */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (deviceAudio?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        deviceAudio?.activity = null
        super.onDestroy()
    }
}
