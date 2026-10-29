package com.example.miee.musicdrop

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.example.miee.MainActivity
import com.example.miee.R

/**
 * Handles creation and presentation of Miee Music Drop system notifications.
 * Respects Android 13+ POST_NOTIFICATIONS, enforces user consent boundaries,
 * and maintains dedicated foreground service and transfer notification channels.
 */
class MusicDropNotificationHelper private constructor(private val context: Context) {

    companion object {
        const val CHANNEL_SERVICE = "miee_music_drop_service"
        const val CHANNEL_TRANSFERS = "miee_music_drop_transfers"

        const val SERVICE_NOTIFICATION_ID = 41291
        const val INCOMING_NOTIFICATION_ID = 41292
        const val PROGRESS_NOTIFICATION_ID = 41293
        const val COMPLETION_NOTIFICATION_ID = 41294
        const val FAILURE_NOTIFICATION_ID = 41295

        const val ACTION_ACCEPT_TRANSFER = "com.example.miee.musicdrop.ACTION_ACCEPT_TRANSFER"
        const val ACTION_DECLINE_TRANSFER = "com.example.miee.musicdrop.ACTION_DECLINE_TRANSFER"
        const val ACTION_STOP_SERVICE = "com.example.miee.musicdrop.ACTION_STOP_SERVICE"

        const val EXTRA_TRANSFER_ID = "extra_transfer_id"
        const val EXTRA_ENDPOINT_ID = "extra_endpoint_id"

        @Volatile
        private var instance: MusicDropNotificationHelper? = null

        fun getInstance(context: Context): MusicDropNotificationHelper {
            return instance ?: synchronized(this) {
                instance ?: MusicDropNotificationHelper(context.applicationContext).also {
                    instance = it
                }
            }
        }
    }

    private val notificationManager = NotificationManagerCompat.from(context)

    init {
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_SERVICE,
                "Music Drop Background Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Miee discoverable for nearby music sharing"
                setShowBadge(false)
            }

            val transferChannel = NotificationChannel(
                CHANNEL_TRANSFERS,
                "Music Drop Transfers",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alerts and progress for nearby music transfers"
                enableVibration(true)
                setShowBadge(true)
            }

            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.createNotificationChannel(serviceChannel)
            manager?.createNotificationChannel(transferChannel)
        }
    }

    fun areNotificationsEnabled(): Boolean {
        return notificationManager.areNotificationsEnabled()
    }

    private fun getNotificationIcon(): Int {
        return try {
            R.drawable.ic_notification
        } catch (_: Exception) {
            android.R.drawable.stat_sys_download_done
        }
    }

    private fun createOpenAppPendingIntent(transferId: String?): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("open_music_drop", true)
            if (transferId != null) {
                putExtra("transfer_id", transferId)
            }
        }
        val requestCode = transferId?.hashCode() ?: 1001
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun buildServiceNotification(isDiscoverable: Boolean, deviceName: String?): Notification {
        val stopIntent = Intent(context, MusicDropNotificationReceiver::class.java).apply {
            action = ACTION_STOP_SERVICE
        }
        val stopPendingIntent = PendingIntent.getBroadcast(
            context,
            2001,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val bodyText = if (isDiscoverable) {
            "Discoverable as ${deviceName ?: "Miee"} • Ready to receive"
        } else {
            "Music Drop active"
        }

        return NotificationCompat.Builder(context, CHANNEL_SERVICE)
            .setSmallIcon(getNotificationIcon())
            .setContentTitle("Miee Music Drop")
            .setContentText(bodyText)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(createOpenAppPendingIntent(null))
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Turn Off", stopPendingIntent)
            .build()
    }

    fun buildIncomingRequestNotification(
        transferId: String,
        endpointId: String,
        deviceName: String,
        trackTitle: String,
        artist: String
    ): Notification {
        val acceptIntent = Intent(context, MusicDropNotificationReceiver::class.java).apply {
            action = ACTION_ACCEPT_TRANSFER
            putExtra(EXTRA_TRANSFER_ID, transferId)
            putExtra(EXTRA_ENDPOINT_ID, endpointId)
        }
        val acceptPendingIntent = PendingIntent.getBroadcast(
            context,
            (transferId + "_acc").hashCode(),
            acceptIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val declineIntent = Intent(context, MusicDropNotificationReceiver::class.java).apply {
            action = ACTION_DECLINE_TRANSFER
            putExtra(EXTRA_TRANSFER_ID, transferId)
            putExtra(EXTRA_ENDPOINT_ID, endpointId)
        }
        val declinePendingIntent = PendingIntent.getBroadcast(
            context,
            (transferId + "_dec").hashCode(),
            declineIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(context, CHANNEL_TRANSFERS)
            .setSmallIcon(getNotificationIcon())
            .setContentTitle("Incoming Song: $trackTitle")
            .setContentText("$artist • From $deviceName")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setAutoCancel(true)
            .setContentIntent(createOpenAppPendingIntent(transferId))
            .addAction(android.R.drawable.ic_media_play, "Accept", acceptPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Decline", declinePendingIntent)
            .build()
    }

    fun buildProgressNotification(
        transferId: String,
        trackTitle: String,
        percent: Int,
        bytesTransferred: Long,
        totalBytes: Long
    ): Notification {
        val cancelIntent = Intent(context, MusicDropNotificationReceiver::class.java).apply {
            action = ACTION_DECLINE_TRANSFER
            putExtra(EXTRA_TRANSFER_ID, transferId)
        }
        val cancelPendingIntent = PendingIntent.getBroadcast(
            context,
            (transferId + "_cancel").hashCode(),
            cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val mbTransferred = bytesTransferred.toDouble() / (1024.0 * 1024.0)
        val mbTotal = totalBytes.toDouble() / (1024.0 * 1024.0)
        val progressText = if (totalBytes > 0) {
            "$percent% (%.1f / %.1f MB)".format(mbTransferred, mbTotal)
        } else {
            "%.1f MB received".format(mbTransferred)
        }

        return NotificationCompat.Builder(context, CHANNEL_TRANSFERS)
            .setSmallIcon(getNotificationIcon())
            .setContentTitle("Receiving $trackTitle")
            .setContentText(progressText)
            .setSubText("Miee Drop")
            .setProgress(100, percent.coerceIn(0, 100), totalBytes <= 0)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(createOpenAppPendingIntent(transferId))
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", cancelPendingIntent)
            .build()
    }

    fun buildCompletionNotification(
        transferId: String,
        trackTitle: String,
        artist: String
    ): Notification {
        return NotificationCompat.Builder(context, CHANNEL_TRANSFERS)
            .setSmallIcon(getNotificationIcon())
            .setContentTitle("Song Received: $trackTitle")
            .setContentText("$artist • Tap to review and save to library")
            .setSubText("Consent required")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(createOpenAppPendingIntent(transferId))
            .build()
    }

    fun buildFailureNotification(trackTitle: String, reason: String): Notification {
        return NotificationCompat.Builder(context, CHANNEL_TRANSFERS)
            .setSmallIcon(getNotificationIcon())
            .setContentTitle("Drop Transfer Failed")
            .setContentText("$trackTitle: $reason")
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(createOpenAppPendingIntent(null))
            .build()
    }

    fun postNotification(id: Int, notification: Notification) {
        try {
            if (areNotificationsEnabled()) {
                notificationManager.notify(id, notification)
            }
        } catch (_: SecurityException) {}
    }

    fun cancelNotification(id: Int) {
        try {
            notificationManager.cancel(id)
        } catch (_: Exception) {}
    }

    fun cancelAllDropNotifications() {
        try {
            notificationManager.cancel(INCOMING_NOTIFICATION_ID)
            notificationManager.cancel(PROGRESS_NOTIFICATION_ID)
            notificationManager.cancel(COMPLETION_NOTIFICATION_ID)
            notificationManager.cancel(FAILURE_NOTIFICATION_ID)
        } catch (_: Exception) {}
    }
}

