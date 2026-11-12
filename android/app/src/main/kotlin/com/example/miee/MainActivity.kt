package com.example.miee

import android.content.Intent
import android.nfc.NdefMessage
import android.nfc.NfcAdapter
import android.nfc.tech.Ndef
import android.os.Bundle
import com.example.miee.audio.AudioOutputManager
import com.example.miee.musicdrop.MusicDropManager
import com.example.miee.widget.MieeWidgetManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var musicDropManager: MusicDropManager? = null
    private var audioOutputManager: AudioOutputManager? = null
    private var widgetChannel: MethodChannel? = null
    private var pendingIntentToHandle: Intent? = null
    private var nfcAdapter: NfcAdapter? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        nfcAdapter = try { NfcAdapter.getDefaultAdapter(this) } catch (_: Exception) { null }
        val manager = MusicDropManager.getInstance(this)
        manager.attachActivity(this)
        musicDropManager = manager

        val audioManager = AudioOutputManager(this)
        audioManager.attachActivity(this)
        audioOutputManager = audioManager

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

        val audioManager = AudioOutputManager(this)
        audioManager.attachActivity(this)
        audioOutputManager = audioManager

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AudioOutputManager.CHANNEL_NAME
        ).setMethodCallHandler(audioManager)

        val wChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.miee/widget"
        )
        wChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateNowPlaying" -> {
                    val trackId = call.argument<String>("trackId")
                    val title = call.argument<String>("title")
                    val artist = call.argument<String>("artist")
                    val artPath = call.argument<String>("artworkPath")
                    val artUrl = call.argument<String>("artworkUrl")
                    val audioFilePath = call.argument<String>("audioFilePath")
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    val isFav = call.argument<Boolean>("isFavorited") ?: false
                    val progress = call.argument<Double>("progress") ?: 0.0
                    val positionMs = (call.argument<Number>("positionMs")?.toLong()) ?: 0L
                    val durationMs = (call.argument<Number>("durationMs")?.toLong()) ?: 0L
                    MieeWidgetManager.updateNowPlaying(
                        this, trackId, title, artist, artPath, artUrl, audioFilePath, isPlaying, isFav, progress, positionMs, durationMs
                    )
                    result.success(true)
                }
                "updateRecentlyPlayed" -> {
                    val json = call.argument<String>("itemsJson") ?: "[]"
                    MieeWidgetManager.updateRecentlyPlayed(this, json)
                    result.success(true)
                }
                "updateFavourites" -> {
                    val json = call.argument<String>("itemsJson") ?: "[]"
                    MieeWidgetManager.updateFavourites(this, json)
                    result.success(true)
                }
                "updatePlaylists" -> {
                    val json = call.argument<String>("itemsJson") ?: "[]"
                    MieeWidgetManager.updatePlaylists(this, json)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        widgetChannel = wChannel

        pendingIntentToHandle?.let {
            handleIntent(it)
            pendingIntentToHandle = null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return

        if (widgetChannel == null) {
            pendingIntentToHandle = intent
        } else {
            if (intent.getBooleanExtra(MieeWidgetManager.ACTION_PLAY_TRACK, false)) {
                val trackId = intent.getStringExtra(MieeWidgetManager.EXTRA_TRACK_ID)
                if (!trackId.isNullOrBlank()) {
                    widgetChannel?.invokeMethod("onPlayTrack", trackId)
                }
            } else if (intent.getBooleanExtra(MieeWidgetManager.ACTION_OPEN_PLAYLIST, false)) {
                val playlistId = intent.getStringExtra(MieeWidgetManager.EXTRA_PLAYLIST_ID)
                if (!playlistId.isNullOrBlank()) {
                    widgetChannel?.invokeMethod("onOpenPlaylist", playlistId)
                }
            } else if (intent.getBooleanExtra(MieeWidgetManager.ACTION_NAVIGATE, false)) {
                val route = intent.getStringExtra(MieeWidgetManager.EXTRA_ROUTE)
                if (!route.isNullOrBlank()) {
                    widgetChannel?.invokeMethod("onNavigate", route)
                }
            } else if (intent.getBooleanExtra(MieeWidgetManager.ACTION_TOGGLE_FAVORITE, false)) {
                widgetChannel?.invokeMethod("onToggleFavorite", null)
            }
        }

        if (intent.getBooleanExtra("open_music_drop", false)) {
            val transferId = intent.getStringExtra("transfer_id")
            musicDropManager?.notifyOpenDropRequested(transferId)
        }

        // Handle incoming NDEF NFC intent
        if (NfcAdapter.ACTION_NDEF_DISCOVERED == intent.action ||
            NfcAdapter.ACTION_TAG_DISCOVERED == intent.action) {
            handleNdefIntent(intent)
        }
    }

    private fun handleNdefIntent(intent: Intent) {
        try {
            val rawMsgs = intent.getParcelableArrayExtra(NfcAdapter.EXTRA_NDEF_MESSAGES)
            if (rawMsgs != null && rawMsgs.isNotEmpty()) {
                val msg = rawMsgs[0] as? NdefMessage
                val record = msg?.records?.firstOrNull()
                val payload = record?.payload?.let { String(it, Charsets.UTF_8) }
                if (!payload.isNullOrBlank()) {
                    musicDropManager?.handleNfcTrigger(payload)
                }
            }
        } catch (_: Exception) {}
    }

    override fun onResume() {
        super.onResume()
        musicDropManager?.attachActivity(this)
        audioOutputManager?.attachActivity(this)
        enableNfcReaderMode()
    }

    override fun onPause() {
        disableNfcReaderMode()
        super.onPause()
    }

    private fun enableNfcReaderMode() {
        val adapter = nfcAdapter ?: return
        if (!adapter.isEnabled) return

        try {
            val flags = NfcAdapter.FLAG_READER_NFC_A or
                    NfcAdapter.FLAG_READER_NFC_B or
                    NfcAdapter.FLAG_READER_NFC_F or
                    NfcAdapter.FLAG_READER_NFC_V or
                    NfcAdapter.FLAG_READER_NO_PLATFORM_SOUNDS

            adapter.enableReaderMode(this, { tag ->
                try {
                    val ndef = Ndef.get(tag)
                    if (ndef != null) {
                        ndef.connect()
                        val msg = ndef.ndefMessage
                        val record = msg?.records?.firstOrNull()
                        val text = record?.payload?.let { String(it, Charsets.UTF_8) }
                        if (!text.isNullOrBlank()) {
                            runOnUiThread {
                                musicDropManager?.handleNfcTrigger(text)
                            }
                        }
                        try { ndef.close() } catch (_: Exception) {}
                    }
                } catch (_: Exception) {}
            }, flags, null)
        } catch (_: Exception) {}
    }

    private fun disableNfcReaderMode() {
        val adapter = nfcAdapter ?: return
        try {
            adapter.disableReaderMode(this)
        } catch (_: Exception) {}
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
        audioOutputManager?.detachActivity()
        super.onDestroy()
    }
}
