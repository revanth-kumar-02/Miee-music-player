package com.example.miee.musicdrop

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat

/**
 * Foreground service providing an active Android connectedDevice execution context
 * for Miee Music Drop peer-to-peer receiving when the application is backgrounded or screen locked.
 */
class MusicDropService : Service() {

    companion object {
        const val ACTION_START = "com.example.miee.musicdrop.START_SERVICE"
        const val ACTION_STOP = "com.example.miee.musicdrop.STOP_SERVICE"
        const val EXTRA_DEVICE_NAME = "extra_device_name"
        const val EXTRA_IS_DISCOVERABLE = "extra_is_discoverable"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_START, null -> {
                val isDiscoverable = intent?.getBooleanExtra(EXTRA_IS_DISCOVERABLE, true) ?: true
                val deviceName = intent?.getStringExtra(EXTRA_DEVICE_NAME)

                val helper = MusicDropNotificationHelper.getInstance(this)
                val notification = helper.buildServiceNotification(isDiscoverable, deviceName)

                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val fgsType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                        } else {
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                        }
                        ServiceCompat.startForeground(
                            this,
                            MusicDropNotificationHelper.SERVICE_NOTIFICATION_ID,
                            notification,
                            fgsType
                        )
                    } else {
                        startForeground(MusicDropNotificationHelper.SERVICE_NOTIFICATION_ID, notification)
                    }
                } catch (_: Exception) {
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
    }
}
