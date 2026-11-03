package com.example.miee.audio

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AudioOutputManager(private val context: Context) : MethodChannel.MethodCallHandler {
    private var activity: Activity? = null

    companion object {
        const val CHANNEL_NAME = "com.example.miee/audio_output"
    }

    fun attachActivity(activity: Activity) {
        this.activity = activity
    }

    fun detachActivity() {
        this.activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getConnectedAudioDevices" -> {
                try {
                    val devices = getConnectedDevices()
                    result.success(devices)
                } catch (e: Exception) {
                    result.error("ERROR", e.localizedMessage, null)
                }
            }
            "openMediaOutputSwitcher" -> {
                val opened = openMediaOutputSwitcher()
                result.success(opened)
            }
            "openBluetoothSettings" -> {
                val opened = openBluetoothSettings()
                result.success(opened)
            }
            "openCastSettings" -> {
                val opened = openCastSettings()
                result.success(opened)
            }
            else -> result.notImplemented()
        }
    }

    private fun getConnectedDevices(): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return list
            val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            for (dev in devices) {
                val typeName = getDeviceTypeName(dev.type)
                val productName = if (dev.productName.isNullOrBlank()) typeName else dev.productName.toString()
                list.add(
                    mapOf(
                        "id" to dev.id.toString(),
                        "name" to productName,
                        "type" to typeName,
                        "type_id" to dev.type,
                        "is_sink" to dev.isSink
                    )
                )
            }
        }
        return list
    }

    private fun getDeviceTypeName(type: Int): String {
        return when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Phone Speaker"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth Audio"
            AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Wired Headphones"
            AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET -> "USB Audio"
            AudioDeviceInfo.TYPE_HDMI, AudioDeviceInfo.TYPE_HDMI_ARC -> "HDMI Audio"
            else -> "Audio Output"
        }
    }

    private fun openMediaOutputSwitcher(): Boolean {
        val act = activity ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val intent = Intent("com.android.settings.panel.action.MEDIA_OUTPUT").apply {
                    putExtra("com.android.settings.panel.extra.PACKAGE_NAME", act.packageName)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                act.startActivity(intent)
                return true
            } catch (_: Exception) {}
        }
        return openBluetoothSettings()
    }

    private fun openBluetoothSettings(): Boolean {
        val act = activity ?: return false
        return try {
            val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            act.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openCastSettings(): Boolean {
        val act = activity ?: return false
        return try {
            val intent = Intent(Settings.ACTION_CAST_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            act.startActivity(intent)
            true
        } catch (_: Exception) {
            openBluetoothSettings()
        }
    }
}

