package com.example.miee

import android.content.Intent
import android.nfc.NdefMessage
import android.nfc.NfcAdapter
import android.nfc.tech.Ndef
import android.os.Bundle
import com.example.miee.musicdrop.MusicDropManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var musicDropManager: MusicDropManager? = null
    private var nfcAdapter: NfcAdapter? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        nfcAdapter = try { NfcAdapter.getDefaultAdapter(this) } catch (_: Exception) { null }
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
        super.onDestroy()
    }
}
