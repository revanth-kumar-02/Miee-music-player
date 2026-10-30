package com.example.miee.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.KeyEvent
import android.widget.RemoteViews
import com.example.miee.MainActivity
import com.example.miee.R

/**
 * 4x1 Compact Homescreen Widget for Miee.
 * Provides instant Play/Pause, Next, and Previous controls connected
 * directly to the foreground MediaSession MediaButtonReceiver.
 */
class MieeCompactWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_WIDGET_UPDATE_STATE = "com.example.miee.widget.UPDATE_STATE"
        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_ARTIST = "extra_artist"
        const val EXTRA_IS_PLAYING = "extra_is_playing"

        fun updateAllWidgets(
            context: Context,
            title: String? = null,
            artist: String? = null,
            isPlaying: Boolean = false
        ) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisWidget = ComponentName(context, MieeCompactWidgetProvider::class.java)
            val allWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
            for (widgetId in allWidgetIds) {
                updateWidgetView(context, appWidgetManager, widgetId, title, artist, isPlaying)
            }
        }

        private fun updateWidgetView(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            title: String?,
            artist: String?,
            isPlaying: Boolean
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_compact_player)

            views.setTextViewText(R.id.widget_title, title ?: "Miee Music")
            views.setTextViewText(R.id.widget_artist, artist ?: "Tap to play")

            val playIcon = if (isPlaying) {
                android.R.drawable.ic_media_pause
            } else {
                android.R.drawable.ic_media_play
            }
            views.setImageViewResource(R.id.widget_btn_play_pause, playIcon)

            // Open app on body click
            val openAppIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val openAppPendingIntent = PendingIntent.getActivity(
                context,
                0,
                openAppIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, openAppPendingIntent)

            // Media control intents sent to AudioService's MediaButtonReceiver
            views.setOnClickPendingIntent(
                R.id.widget_btn_play_pause,
                createMediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 101)
            )
            views.setOnClickPendingIntent(
                R.id.widget_btn_next,
                createMediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_NEXT, 102)
            )
            views.setOnClickPendingIntent(
                R.id.widget_btn_prev,
                createMediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS, 103)
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun createMediaButtonPendingIntent(
            context: Context,
            keyCode: Int,
            requestCode: Int
        ): PendingIntent {
            val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                setComponent(ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver"))
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            }
            return PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidgetView(context, appWidgetManager, appWidgetId, null, null, false)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_WIDGET_UPDATE_STATE) {
            val title = intent.getStringExtra(EXTRA_TITLE)
            val artist = intent.getStringExtra(EXTRA_ARTIST)
            val isPlaying = intent.getBooleanExtra(EXTRA_IS_PLAYING, false)
            updateAllWidgets(context, title, artist, isPlaying)
        }
    }
}

