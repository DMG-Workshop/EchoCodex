package com.dmgworkshop.transcript_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var sharedFiles: SharedFilePlugin? = null

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
}
