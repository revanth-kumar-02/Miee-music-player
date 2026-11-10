package com.example.miee.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context

class MiniArtworkWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) {
            MieeWidgetManager.buildMiniArtworkView(context, appWidgetManager, id)
        }
    }
}

class NowPlayingCompactWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) {
            MieeWidgetManager.buildCompactView(context, appWidgetManager, id)
        }
    }
}

class NowPlayingExpandedWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) {
            MieeWidgetManager.buildExpandedView(context, appWidgetManager, id)
        }
    }
}

class NowPlayingTallWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) {
            MieeWidgetManager.buildTallView(context, appWidgetManager, id)
        }
    }
}

class RecentlyPlayedWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) {
            MieeWidgetManager.buildRecentlyPlayedView(context, appWidgetManager, id)
        }
    }
}

class FavouritesWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) {
            MieeWidgetManager.buildFavouritesView(context, appWidgetManager, id)
        }
    }
}

class PlaylistsWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) {
            MieeWidgetManager.buildPlaylistsView(context, appWidgetManager, id)
        }
    }
}

