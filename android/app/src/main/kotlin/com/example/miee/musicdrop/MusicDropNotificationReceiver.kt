package com.example.miee.musicdrop

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Handles action button clicks from Miee Music Drop notifications.
 * Dispatches accept, decline, and service stop actions to MusicDropManager.
 */
class MusicDropNotificationReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent == null) return

        val manager = MusicDropManager.getInstance(context)
        val transferId = intent.getStringExtra(MusicDropNotificationHelper.EXTRA_TRANSFER_ID)
        val endpointId = intent.getStringExtra(MusicDropNotificationHelper.EXTRA_ENDPOINT_ID)

        when (intent.action) {
            MusicDropNotificationHelper.ACTION_ACCEPT_TRANSFER -> {
                manager.acceptTransferFromNotification(transferId, endpointId)
            }

            MusicDropNotificationHelper.ACTION_DECLINE_TRANSFER -> {
                manager.declineTransferFromNotification(transferId, endpointId)
            }

            MusicDropNotificationHelper.ACTION_STOP_SERVICE -> {
                manager.stopBackgroundService()
            }
        }
    }
}
