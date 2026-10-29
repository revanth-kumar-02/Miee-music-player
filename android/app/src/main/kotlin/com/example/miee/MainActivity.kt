package com.example.miee

import com.example.miee.musicdrop.MusicDropManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var musicDropManager: MusicDropManager? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val manager = MusicDropManager(this)
        musicDropManager = manager

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MusicDropManager.CHANNEL_METHODS
        ).setMethodCallHandler(manager)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MusicDropManager.CHANNEL_EVENTS
        ).setStreamHandler(manager)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        musicDropManager?.handlePermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        musicDropManager?.destroy()
        musicDropManager = null
        super.onDestroy()
    }
}
