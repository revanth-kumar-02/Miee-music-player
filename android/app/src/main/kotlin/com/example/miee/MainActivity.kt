package com.example.miee

import android.content.Intent
import android.os.Bundle
import com.example.miee.musicdrop.MusicDropManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var musicDropManager: MusicDropManager? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val manager = MusicDropManager.getInstance(this)
        manager.attachActivity(this)
        musicDropManager = manager
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val manager = MusicDropManager.getInstance(this)
        manager.attachActivity(this)
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        if (intent.getBooleanExtra("open_music_drop", false)) {
            val transferId = intent.getStringExtra("transfer_id")
            musicDropManager?.notifyOpenDropRequested(transferId)
        }
    }

    override fun onResume() {
        super.onResume()
        musicDropManager?.attachActivity(this)
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
        musicDropManager?.detachActivity(this)
        super.onDestroy()
    }
}
