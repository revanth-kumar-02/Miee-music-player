package com.example.miee.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.*
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.widget.RemoteViews
import com.example.miee.MainActivity
import com.example.miee.R
import org.json.JSONArray
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.Collections
import java.util.concurrent.Executors

object MieeWidgetManager {
    private const val PREFS_NAME = "miee_widget_prefs"
    private const val KEY_TRACK_ID = "now_playing_track_id"
    private const val KEY_TITLE = "now_playing_title"
    private const val KEY_ARTIST = "now_playing_artist"
    private const val KEY_ART_PATH = "now_playing_art_path"
    private const val KEY_ART_URL = "now_playing_art_url"
    private const val KEY_AUDIO_PATH = "now_playing_audio_path"
    private const val KEY_IS_PLAYING = "now_playing_is_playing"
    private const val KEY_IS_FAV = "now_playing_is_fav"
    private const val KEY_PROGRESS = "now_playing_progress"
    private const val KEY_POSITION_MS = "now_playing_pos_ms"
    private const val KEY_DURATION_MS = "now_playing_dur_ms"
    private const val KEY_RECENT_JSON = "recent_tracks_json"
    private const val KEY_FAV_JSON = "fav_tracks_json"
    private const val KEY_PLAYLIST_JSON = "playlists_json"

    private const val MAX_CACHE_FILES = 40
    private const val MAX_CACHE_BYTES = 15L * 1024L * 1024L
    private const val WIDGET_ART_USER_AGENT =
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"

    const val ACTION_PLAY_TRACK = "com.example.miee.widget.PLAY_TRACK"
    const val ACTION_OPEN_PLAYLIST = "com.example.miee.widget.OPEN_PLAYLIST"
    const val ACTION_NAVIGATE = "com.example.miee.widget.NAVIGATE"
    const val ACTION_TOGGLE_FAVORITE = "com.example.miee.widget.TOGGLE_FAVORITE"
    const val EXTRA_TRACK_ID = "extra_track_id"
    const val EXTRA_PLAYLIST_ID = "extra_playlist_id"
    const val EXTRA_ROUTE = "extra_route"

    private val executor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val inFlightArtKeys = Collections.synchronizedSet(mutableSetOf<String>())

    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun updateNowPlaying(
        context: Context,
        trackId: String?,
        title: String?,
        artist: String?,
        artPath: String?,
        artUrl: String?,
        audioFilePath: String?,
        isPlaying: Boolean,
        isFav: Boolean,
        progress: Double,
        positionMs: Long,
        durationMs: Long
    ) {
        val safeTrackId = trackId ?: ""
        val safeArtPath = artPath ?: ""
        val safeArtUrl = artUrl ?: ""
        val safeAudioPath = audioFilePath ?: ""

        val editor = getPrefs(context).edit()
        editor.putString(KEY_TRACK_ID, safeTrackId)
        editor.putString(KEY_TITLE, title ?: "Miee Music")
        editor.putString(KEY_ARTIST, artist ?: "Ready to play")
        editor.putString(KEY_ART_PATH, safeArtPath)
        editor.putString(KEY_ART_URL, safeArtUrl)
        editor.putString(KEY_AUDIO_PATH, safeAudioPath)
        editor.putBoolean(KEY_IS_PLAYING, isPlaying)
        editor.putBoolean(KEY_IS_FAV, isFav)
        editor.putFloat(KEY_PROGRESS, progress.toFloat())
        editor.putLong(KEY_POSITION_MS, positionMs)
        editor.putLong(KEY_DURATION_MS, durationMs)
        editor.apply()

        // Immediately render with any already-available local or cached bitmap.
        updateNowPlayingWidgets(context)

        val hasLocalArtFile = safeArtPath.isNotBlank() && File(safeArtPath).let { it.exists() && it.length() > 0 }

        if (!hasLocalArtFile && safeAudioPath.isNotBlank()) {
            val extractedFile = getExtractedLocalArtFile(context, safeTrackId, safeAudioPath)
            if (!extractedFile.exists() || extractedFile.length() == 0L) {
                extractEmbeddedArtwork(context, safeTrackId, safeAudioPath) {
                    val currentTrack = getPrefs(context).getString(KEY_TRACK_ID, "") ?: ""
                    if (currentTrack == safeTrackId) {
                        updateNowPlayingWidgets(context)
                    }
                }
            }
        }

        if (safeArtUrl.isNotBlank() && !hasLocalArtFile) {
            val cachedFile = getCachedArtFile(context, safeTrackId, safeArtUrl)
            if (!cachedFile.exists() || cachedFile.length() == 0L) {
                cacheArtworkUrl(context, safeTrackId, safeArtUrl) {
                    val prefs = getPrefs(context)
                    val currentTrack = prefs.getString(KEY_TRACK_ID, "") ?: ""
                    val currentUrl = prefs.getString(KEY_ART_URL, "") ?: ""
                    if (currentTrack == safeTrackId && currentUrl == safeArtUrl) {
                        updateNowPlayingWidgets(context)
                    }
                }
            }
        }
    }

    fun updateRecentlyPlayed(context: Context, itemsJson: String) {
        getPrefs(context).edit().putString(KEY_RECENT_JSON, itemsJson).apply()
        updateWidgetsOfClass(context, RecentlyPlayedWidgetProvider::class.java)
        prefetchItemsArtwork(context, itemsJson, RecentlyPlayedWidgetProvider::class.java)
    }

    fun updateFavourites(context: Context, itemsJson: String) {
        getPrefs(context).edit().putString(KEY_FAV_JSON, itemsJson).apply()
        updateWidgetsOfClass(context, FavouritesWidgetProvider::class.java)
        prefetchItemsArtwork(context, itemsJson, FavouritesWidgetProvider::class.java)
    }

    fun updatePlaylists(context: Context, itemsJson: String) {
        getPrefs(context).edit().putString(KEY_PLAYLIST_JSON, itemsJson).apply()
        updateWidgetsOfClass(context, PlaylistsWidgetProvider::class.java)
        prefetchItemsArtwork(context, itemsJson, PlaylistsWidgetProvider::class.java)
    }

    private fun updateNowPlayingWidgets(context: Context) {
        updateWidgetsOfClass(context, MiniArtworkWidgetProvider::class.java)
        updateWidgetsOfClass(context, NowPlayingCompactWidgetProvider::class.java)
        updateWidgetsOfClass(context, NowPlayingExpandedWidgetProvider::class.java)
        updateWidgetsOfClass(context, NowPlayingTallWidgetProvider::class.java)
    }

    fun updateAllWidgets(context: Context) {
        updateWidgetsOfClass(context, MiniArtworkWidgetProvider::class.java)
        updateWidgetsOfClass(context, NowPlayingCompactWidgetProvider::class.java)
        updateWidgetsOfClass(context, NowPlayingExpandedWidgetProvider::class.java)
        updateWidgetsOfClass(context, NowPlayingTallWidgetProvider::class.java)
        updateWidgetsOfClass(context, RecentlyPlayedWidgetProvider::class.java)
        updateWidgetsOfClass(context, FavouritesWidgetProvider::class.java)
        updateWidgetsOfClass(context, PlaylistsWidgetProvider::class.java)
    }

    private fun updateWidgetsOfClass(context: Context, cls: Class<*>) {
        val appWidgetManager = AppWidgetManager.getInstance(context) ?: return
        val ids = appWidgetManager.getAppWidgetIds(ComponentName(context, cls))
        for (id in ids) {
            when (cls) {
                MiniArtworkWidgetProvider::class.java -> buildMiniArtworkView(context, appWidgetManager, id)
                NowPlayingCompactWidgetProvider::class.java -> buildCompactView(context, appWidgetManager, id)
                NowPlayingExpandedWidgetProvider::class.java -> buildExpandedView(context, appWidgetManager, id)
                NowPlayingTallWidgetProvider::class.java -> buildTallView(context, appWidgetManager, id)
                RecentlyPlayedWidgetProvider::class.java -> buildRecentlyPlayedView(context, appWidgetManager, id)
                FavouritesWidgetProvider::class.java -> buildFavouritesView(context, appWidgetManager, id)
                PlaylistsWidgetProvider::class.java -> buildPlaylistsView(context, appWidgetManager, id)
            }
        }
    }

    // --- WIDGET 1: Mini Artwork (2x2) ---
    fun buildMiniArtworkView(context: Context, manager: AppWidgetManager, widgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_mini_artwork)
        val prefs = getPrefs(context)
        val isPlaying = prefs.getBoolean(KEY_IS_PLAYING, false)
        val trackId = prefs.getString(KEY_TRACK_ID, "") ?: ""
        val artPath = prefs.getString(KEY_ART_PATH, "") ?: ""
        val artUrl = prefs.getString(KEY_ART_URL, "") ?: ""
        val audioPath = prefs.getString(KEY_AUDIO_PATH, "") ?: ""

        // Artwork
        val bmp = loadArtworkBitmap(context, trackId, artPath, artUrl, audioPath, 28f, 320)
        if (bmp != null) {
            views.setImageViewBitmap(R.id.widget_art_image, bmp)
        } else {
            views.setImageViewResource(R.id.widget_art_image, R.drawable.ic_widget_album_placeholder)
        }

        // Play/Pause icon (on white button, cobalt icon)
        val playIcon = if (isPlaying) R.drawable.ic_widget_pause_cobalt else R.drawable.ic_widget_play_cobalt
        views.setImageViewResource(R.id.widget_btn_play_pause, playIcon)

        // Clicks
        views.setOnClickPendingIntent(R.id.widget_root, createOpenAppPendingIntent(context, "/now-playing", 201))
        views.setOnClickPendingIntent(
            R.id.widget_btn_play_pause,
            createMediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 202)
        )

        manager.updateAppWidget(widgetId, views)
    }

    // --- WIDGET 2: Now Playing Compact (4x2) ---
    fun buildCompactView(context: Context, manager: AppWidgetManager, widgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_now_playing_compact)
        val prefs = getPrefs(context)
        val title = prefs.getString(KEY_TITLE, "The Night We Met")
        val artist = prefs.getString(KEY_ARTIST, "Lord Huron")
        val isPlaying = prefs.getBoolean(KEY_IS_PLAYING, false)
        val isFav = prefs.getBoolean(KEY_IS_FAV, false)
        val progress = (prefs.getFloat(KEY_PROGRESS, 0.42f) * 100).toInt()
        val trackId = prefs.getString(KEY_TRACK_ID, "") ?: ""
        val artPath = prefs.getString(KEY_ART_PATH, "") ?: ""
        val artUrl = prefs.getString(KEY_ART_URL, "") ?: ""
        val audioPath = prefs.getString(KEY_AUDIO_PATH, "") ?: ""

        views.setTextViewText(R.id.widget_title, title)
        views.setTextViewText(R.id.widget_artist, artist)
        views.setProgressBar(R.id.widget_progress_bar, 100, progress.coerceIn(0, 100), false)

        val bmp = loadArtworkBitmap(context, trackId, artPath, artUrl, audioPath, 16f, 320)
        if (bmp != null) {
            views.setImageViewBitmap(R.id.widget_art_image, bmp)
        } else {
            views.setImageViewResource(R.id.widget_art_image, R.drawable.ic_widget_album_placeholder)
        }

        val playIcon = if (isPlaying) R.drawable.ic_widget_pause else R.drawable.ic_widget_play
        views.setImageViewResource(R.id.widget_btn_play_pause, playIcon)

        val favIcon = if (isFav) R.drawable.ic_widget_heart_filled else R.drawable.ic_widget_heart
        views.setImageViewResource(R.id.widget_btn_favorite, favIcon)

        // Clicks
        views.setOnClickPendingIntent(R.id.widget_root, createOpenAppPendingIntent(context, "/now-playing", 301))
        views.setOnClickPendingIntent(
            R.id.widget_btn_play_pause,
            createMediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 302)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_next,
            createMediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_NEXT, 303)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_prev,
            createMediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS, 304)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_favorite,
            createToggleFavPendingIntent(context, 305)
        )

        manager.updateAppWidget(widgetId, views)
    }

    // --- WIDGET 3: Now Playing Expanded (4x3) ---
    fun buildExpandedView(context: Context, manager: AppWidgetManager, widgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_now_playing_expanded)
        val prefs = getPrefs(context)
        val title = prefs.getString(KEY_TITLE, "The Night We Met")
        val artist = prefs.getString(KEY_ARTIST, "Lord Huron")
        val isPlaying = prefs.getBoolean(KEY_IS_PLAYING, false)
        val isFav = prefs.getBoolean(KEY_IS_FAV, false)
        val progress = (prefs.getFloat(KEY_PROGRESS, 0.42f) * 100).toInt()
        val posMs = prefs.getLong(KEY_POSITION_MS, 134000L) // 2:14
        val durMs = prefs.getLong(KEY_DURATION_MS, 208000L) // 3:28
        val trackId = prefs.getString(KEY_TRACK_ID, "") ?: ""
        val artPath = prefs.getString(KEY_ART_PATH, "") ?: ""
        val artUrl = prefs.getString(KEY_ART_URL, "") ?: ""
        val audioPath = prefs.getString(KEY_AUDIO_PATH, "") ?: ""

        views.setTextViewText(R.id.widget_title, title)
        views.setTextViewText(R.id.widget_artist, artist)
        views.setProgressBar(R.id.widget_progress_bar, 100, progress.coerceIn(0, 100), false)
        views.setTextViewText(R.id.widget_time_current, formatDuration(posMs))
        views.setTextViewText(R.id.widget_time_total, formatDuration(durMs))

        val bmp = loadArtworkBitmap(context, trackId, artPath, artUrl, audioPath, 16f, 320)
        if (bmp != null) {
            views.setImageViewBitmap(R.id.widget_art_image, bmp)
        } else {
            views.setImageViewResource(R.id.widget_art_image, R.drawable.ic_widget_album_placeholder)
        }

        val playIcon = if (isPlaying) R.drawable.ic_widget_pause else R.drawable.ic_widget_play
        views.setImageViewResource(R.id.widget_btn_play_pause, playIcon)

        val favIcon = if (isFav) R.drawable.ic_widget_heart_filled else R.drawable.ic_widget_heart
        views.setImageViewResource(R.id.widget_btn_favorite, favIcon)

        // Clicks
        views.setOnClickPendingIntent(R.id.widget_root, createOpenAppPendingIntent(context, "/now-playing", 401))
        views.setOnClickPendingIntent(
            R.id.widget_btn_play_pause,
            createMediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 402)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_next,
            createMediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_NEXT, 403)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_prev,
            createMediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS, 404)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_favorite,
            createToggleFavPendingIntent(context, 405)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_shuffle,
            createOpenAppPendingIntent(context, "/now-playing", 406)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_repeat,
            createOpenAppPendingIntent(context, "/now-playing", 407)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_overflow,
            createOpenAppPendingIntent(context, "/now-playing", 408)
        )

        manager.updateAppWidget(widgetId, views)
    }

    // --- WIDGET 4: Now Playing Tall (3.5x4 or 4x4) ---
    fun buildTallView(context: Context, manager: AppWidgetManager, widgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_now_playing_tall)
        val prefs = getPrefs(context)
        val title = prefs.getString(KEY_TITLE, "The Night We Met")
        val artist = prefs.getString(KEY_ARTIST, "Lord Huron")
        val isPlaying = prefs.getBoolean(KEY_IS_PLAYING, false)
        val isFav = prefs.getBoolean(KEY_IS_FAV, false)
        val trackId = prefs.getString(KEY_TRACK_ID, "") ?: ""
        val artPath = prefs.getString(KEY_ART_PATH, "") ?: ""
        val artUrl = prefs.getString(KEY_ART_URL, "") ?: ""
        val audioPath = prefs.getString(KEY_AUDIO_PATH, "") ?: ""

        views.setTextViewText(R.id.widget_title, title)
        views.setTextViewText(R.id.widget_artist, artist)

        val bmp = loadArtworkBitmap(context, trackId, artPath, artUrl, audioPath, 18f, 320)
        if (bmp != null) {
            views.setImageViewBitmap(R.id.widget_art_image, bmp)
        } else {
            views.setImageViewResource(R.id.widget_art_image, R.drawable.ic_widget_album_placeholder)
        }

        val playIcon = if (isPlaying) R.drawable.ic_widget_pause else R.drawable.ic_widget_play
        views.setImageViewResource(R.id.widget_btn_play_pause, playIcon)

        val favIcon = if (isFav) R.drawable.ic_widget_heart_filled else R.drawable.ic_widget_heart
        views.setImageViewResource(R.id.widget_btn_favorite, favIcon)

        // Clicks
        views.setOnClickPendingIntent(R.id.widget_root, createOpenAppPendingIntent(context, "/now-playing", 501))
        views.setOnClickPendingIntent(
            R.id.widget_btn_play_pause,
            createMediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 502)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_next,
            createMediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_NEXT, 503)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_prev,
            createMediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS, 504)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_favorite,
            createToggleFavPendingIntent(context, 505)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_overflow,
            createOpenAppPendingIntent(context, "/now-playing", 506)
        )

        manager.updateAppWidget(widgetId, views)
    }

    // --- WIDGET 5: Recently Played (4x2) ---
    fun buildRecentlyPlayedView(context: Context, manager: AppWidgetManager, widgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_recently_played)
        val prefs = getPrefs(context)
        val jsonStr = prefs.getString(KEY_RECENT_JSON, null)

        views.setOnClickPendingIntent(R.id.widget_header, createOpenAppPendingIntent(context, "/recently-played", 601))
        views.setOnClickPendingIntent(R.id.widget_root, createOpenAppPendingIntent(context, "/recently-played", 602))

        val defaultTitles = listOf("Midnight", "Alai", "Iraiva", "Space Song")
        val itemRoots = listOf(R.id.widget_item1_root, R.id.widget_item2_root, R.id.widget_item3_root, R.id.widget_item4_root)
        val itemArts = listOf(R.id.widget_item1_art, R.id.widget_item2_art, R.id.widget_item3_art, R.id.widget_item4_art)
        val itemTitles = listOf(R.id.widget_item1_title, R.id.widget_item2_title, R.id.widget_item3_title, R.id.widget_item4_title)

        var itemsArray: JSONArray? = null
        if (!jsonStr.isNullOrBlank()) {
            try { itemsArray = JSONArray(jsonStr) } catch (_: Exception) {}
        }

        for (i in 0 until 4) {
            var title = defaultTitles[i]
            var trackId = ""
            var artPath = ""
            var artUrl = ""
            var audioPath = ""

            if (itemsArray != null && i < itemsArray.length()) {
                val obj = itemsArray.optJSONObject(i)
                if (obj != null) {
                    title = obj.optString("title", title)
                    trackId = obj.optString("trackId", "")
                    artPath = obj.optString("artworkPath", "")
                    artUrl = obj.optString("artworkUrl", "")
                    audioPath = obj.optString("audioFilePath", "")
                }
            }

            views.setTextViewText(itemTitles[i], title)
            val bmp = loadArtworkBitmap(context, trackId, artPath, artUrl, audioPath, 14f, 160)
            if (bmp != null) {
                views.setImageViewBitmap(itemArts[i], bmp)
            } else {
                views.setImageViewResource(itemArts[i], R.drawable.ic_widget_album_placeholder)
            }

            val clickIntent = if (trackId.isNotBlank()) {
                createPlayTrackPendingIntent(context, trackId, 610 + i)
            } else {
                createOpenAppPendingIntent(context, "/recently-played", 610 + i)
            }
            views.setOnClickPendingIntent(itemRoots[i], clickIntent)
        }

        manager.updateAppWidget(widgetId, views)
    }

    // --- WIDGET 6: Favourites (4x2) ---
    fun buildFavouritesView(context: Context, manager: AppWidgetManager, widgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_favourites)
        val prefs = getPrefs(context)
        val jsonStr = prefs.getString(KEY_FAV_JSON, null)

        views.setOnClickPendingIntent(R.id.widget_header, createOpenAppPendingIntent(context, "/favorites", 701))
        views.setOnClickPendingIntent(R.id.widget_root, createOpenAppPendingIntent(context, "/favorites", 702))

        val defaultTitles = listOf("Song 1", "Song 2", "Song 3", "Song 4")
        val itemRoots = listOf(R.id.widget_item1_root, R.id.widget_item2_root, R.id.widget_item3_root, R.id.widget_item4_root)
        val itemArts = listOf(R.id.widget_item1_art, R.id.widget_item2_art, R.id.widget_item3_art, R.id.widget_item4_art)
        val itemTitles = listOf(R.id.widget_item1_title, R.id.widget_item2_title, R.id.widget_item3_title, R.id.widget_item4_title)

        var itemsArray: JSONArray? = null
        if (!jsonStr.isNullOrBlank()) {
            try { itemsArray = JSONArray(jsonStr) } catch (_: Exception) {}
        }

        for (i in 0 until 4) {
            var title = defaultTitles[i]
            var trackId = ""
            var artPath = ""
            var artUrl = ""
            var audioPath = ""

            if (itemsArray != null && i < itemsArray.length()) {
                val obj = itemsArray.optJSONObject(i)
                if (obj != null) {
                    title = obj.optString("title", title)
                    trackId = obj.optString("trackId", "")
                    artPath = obj.optString("artworkPath", "")
                    artUrl = obj.optString("artworkUrl", "")
                    audioPath = obj.optString("audioFilePath", "")
                }
            }

            views.setTextViewText(itemTitles[i], title)
            val bmp = loadArtworkBitmap(context, trackId, artPath, artUrl, audioPath, 14f, 160)
            if (bmp != null) {
                views.setImageViewBitmap(itemArts[i], bmp)
            } else {
                views.setImageViewResource(itemArts[i], R.drawable.ic_widget_album_placeholder)
            }

            val clickIntent = if (trackId.isNotBlank()) {
                createPlayTrackPendingIntent(context, trackId, 710 + i)
            } else {
                createOpenAppPendingIntent(context, "/favorites", 710 + i)
            }
            views.setOnClickPendingIntent(itemRoots[i], clickIntent)
        }

        manager.updateAppWidget(widgetId, views)
    }

    // --- WIDGET 7: Playlists (4x2) ---
    fun buildPlaylistsView(context: Context, manager: AppWidgetManager, widgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_playlists)
        val prefs = getPrefs(context)
        val jsonStr = prefs.getString(KEY_PLAYLIST_JSON, null)

        views.setOnClickPendingIntent(R.id.widget_header, createOpenAppPendingIntent(context, "/playlists", 801))
        views.setOnClickPendingIntent(R.id.widget_root, createOpenAppPendingIntent(context, "/playlists", 802))

        val defaultPlaylists = listOf(
            Triple("Chill", "42 songs", ""),
            Triple("Focus", "28 songs", ""),
            Triple("Workout", "36 songs", "")
        )
        val roots = listOf(R.id.widget_playlist1_root, R.id.widget_playlist2_root, R.id.widget_playlist3_root)
        val arts = listOf(R.id.widget_playlist1_art, R.id.widget_playlist2_art, R.id.widget_playlist3_art)
        val titles = listOf(R.id.widget_playlist1_title, R.id.widget_playlist2_title, R.id.widget_playlist3_title)
        val counts = listOf(R.id.widget_playlist1_count, R.id.widget_playlist2_count, R.id.widget_playlist3_count)

        var itemsArray: JSONArray? = null
        if (!jsonStr.isNullOrBlank()) {
            try { itemsArray = JSONArray(jsonStr) } catch (_: Exception) {}
        }

        for (i in 0 until 3) {
            var title = defaultPlaylists[i].first
            var countStr = defaultPlaylists[i].second
            var playlistId = ""
            var artPath = ""
            var artUrl = ""
            var audioPath = ""

            if (itemsArray != null && i < itemsArray.length()) {
                val obj = itemsArray.optJSONObject(i)
                if (obj != null) {
                    title = obj.optString("title", title)
                    val count = obj.optInt("trackCount", 0)
                    countStr = if (count > 0) "$count songs" else "0 songs"
                    playlistId = obj.optString("playlistId", "")
                    artPath = obj.optString("artworkPath", "")
                    artUrl = obj.optString("artworkUrl", "")
                    audioPath = obj.optString("audioFilePath", "")
                }
            }

            views.setTextViewText(titles[i], title)
            views.setTextViewText(counts[i], countStr)

            val bmp = loadArtworkBitmap(context, playlistId, artPath, artUrl, audioPath, 14f, 160)
            if (bmp != null) {
                views.setImageViewBitmap(arts[i], bmp)
            } else {
                views.setImageViewResource(arts[i], R.drawable.ic_widget_album_placeholder)
            }

            val clickIntent = if (playlistId.isNotBlank()) {
                createOpenPlaylistPendingIntent(context, playlistId, 810 + i)
            } else {
                createOpenAppPendingIntent(context, "/playlists", 810 + i)
            }
            views.setOnClickPendingIntent(roots[i], clickIntent)
        }

        // New Playlist button
        views.setOnClickPendingIntent(
            R.id.widget_playlist_new_root,
            createOpenAppPendingIntent(context, "/create-playlist", 820)
        )

        manager.updateAppWidget(widgetId, views)
    }

    // --- Helpers: Bitmap Loading & Caching ---
    private fun loadArtworkBitmap(
        context: Context,
        trackId: String?,
        path: String?,
        url: String?,
        audioFilePath: String?,
        cornerRadiusDp: Float,
        maxDim: Int
    ): Bitmap? {
        try {
            var raw: Bitmap? = null
            if (!path.isNullOrBlank()) {
                val file = File(path)
                if (file.exists() && file.length() > 0) {
                    raw = decodeSampledBitmapFromFile(file.absolutePath, maxDim)
                }
            }

            if (raw == null && !audioFilePath.isNullOrBlank()) {
                val extracted = getExtractedLocalArtFile(context, trackId, audioFilePath)
                if (extracted.exists() && extracted.length() > 0) {
                    raw = decodeSampledBitmapFromFile(extracted.absolutePath, maxDim)
                }
            }

            if (raw == null && !url.isNullOrBlank()) {
                val cachedFile = getCachedArtFile(context, trackId, url)
                if (cachedFile.exists() && cachedFile.length() > 0) {
                    raw = decodeSampledBitmapFromFile(cachedFile.absolutePath, maxDim)
                }
            }

            if (raw == null) return null

            val scaled = if (raw.width > maxDim || raw.height > maxDim) {
                val ratio = minOf(maxDim.toFloat() / raw.width, maxDim.toFloat() / raw.height)
                val targetW = (raw.width * ratio).toInt().coerceAtLeast(1)
                val targetH = (raw.height * ratio).toInt().coerceAtLeast(1)
                Bitmap.createScaledBitmap(raw, targetW, targetH, true)
            } else {
                raw
            }

            val rounded = getRoundedBitmap(context, scaled, cornerRadiusDp)
            if (scaled !== raw && !raw.isRecycled) raw.recycle()
            if (rounded !== scaled && !scaled.isRecycled) scaled.recycle()
            return rounded
        } catch (_: Exception) {
            return null
        }
    }

    private fun decodeSampledBitmapFromFile(filePath: String, maxDim: Int): Bitmap? {
        val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(filePath, boundsOpts)
        if (boundsOpts.outWidth <= 0 || boundsOpts.outHeight <= 0) return null

        var inSampleSize = 1
        val halfH = boundsOpts.outHeight / 2
        val halfW = boundsOpts.outWidth / 2
        while ((halfH / inSampleSize) >= maxDim && (halfW / inSampleSize) >= maxDim) {
            inSampleSize *= 2
        }

        val decodeOpts = BitmapFactory.Options().apply {
            this.inSampleSize = inSampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        return BitmapFactory.decodeFile(filePath, decodeOpts)
    }

    private fun getRoundedBitmap(context: Context, src: Bitmap, cornerRadiusDp: Float): Bitmap {
        val radiusPx = cornerRadiusDp * context.resources.displayMetrics.density
        val output = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint().apply {
            isAntiAlias = true
            shader = BitmapShader(src, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        }
        val rect = RectF(0f, 0f, src.width.toFloat(), src.height.toFloat())
        canvas.drawRoundRect(rect, radiusPx, radiusPx, paint)
        return output
    }

    private fun getWidgetArtDir(context: Context): File {
        val dir = File(context.filesDir, "widget_art")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun sha256Hex(input: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }.take(32)
    }

    private fun getCachedArtFile(context: Context, trackId: String?, url: String): File {
        val key = "${trackId.orEmpty()}|$url"
        return File(getWidgetArtDir(context), "art_${sha256Hex(key)}.img")
    }

    private fun getExtractedLocalArtFile(context: Context, trackId: String?, audioFilePath: String): File {
        val key = "local|${trackId.orEmpty()}|$audioFilePath"
        return File(getWidgetArtDir(context), "loc_${sha256Hex(key)}.img")
    }

    private fun cacheArtworkUrl(
        context: Context,
        trackId: String?,
        urlStr: String,
        onComplete: () -> Unit
    ) {
        val cachedFile = getCachedArtFile(context, trackId, urlStr)
        val lockKey = cachedFile.name
        if (!inFlightArtKeys.add(lockKey)) return

        executor.execute {
            try {
                if (!cachedFile.exists() || cachedFile.length() == 0L) {
                    val partFile = File(cachedFile.parentFile, "${cachedFile.name}.part")
                    if (partFile.exists()) partFile.delete()
                    val downloaded = downloadUrlToPartFile(urlStr, partFile)
                    if (downloaded && isValidImageFile(partFile)) {
                        if (cachedFile.exists()) cachedFile.delete()
                        if (!partFile.renameTo(cachedFile)) {
                            partFile.copyTo(cachedFile, overwrite = true)
                            partFile.delete()
                        }
                        pruneWidgetArtCache(context)
                    } else {
                        partFile.delete()
                    }
                }
                if (cachedFile.exists() && cachedFile.length() > 0L) {
                    mainHandler.post { onComplete() }
                }
            } catch (_: Exception) {
            } finally {
                inFlightArtKeys.remove(lockKey)
            }
        }
    }

    private fun extractEmbeddedArtwork(
        context: Context,
        trackId: String?,
        audioFilePath: String,
        onComplete: () -> Unit
    ) {
        val outFile = getExtractedLocalArtFile(context, trackId, audioFilePath)
        val lockKey = outFile.name
        if (!inFlightArtKeys.add(lockKey)) return

        executor.execute {
            val retriever = MediaMetadataRetriever()
            try {
                if (!outFile.exists() || outFile.length() == 0L) {
                    val audioFile = File(audioFilePath)
                    if (audioFile.exists() && audioFile.length() > 0L) {
                        retriever.setDataSource(audioFile.absolutePath)
                        val bytes = retriever.embeddedPicture
                        if (bytes != null && bytes.isNotEmpty()) {
                            val partFile = File(outFile.parentFile, "${outFile.name}.part")
                            FileOutputStream(partFile).use { it.write(bytes) }
                            if (isValidImageFile(partFile)) {
                                if (outFile.exists()) outFile.delete()
                                if (!partFile.renameTo(outFile)) {
                                    partFile.copyTo(outFile, overwrite = true)
                                    partFile.delete()
                                }
                                pruneWidgetArtCache(context)
                            } else {
                                partFile.delete()
                            }
                        }
                    }
                }
                if (outFile.exists() && outFile.length() > 0L) {
                    mainHandler.post { onComplete() }
                }
            } catch (_: Exception) {
            } finally {
                try {
                    retriever.release()
                } catch (_: Exception) {}
                inFlightArtKeys.remove(lockKey)
            }
        }
    }

    private fun prefetchItemsArtwork(context: Context, itemsJson: String, providerCls: Class<*>) {
        if (itemsJson.isBlank()) return
        val itemsArray = try {
            JSONArray(itemsJson)
        } catch (_: Exception) {
            return
        }
        for (i in 0 until itemsArray.length()) {
            val obj = itemsArray.optJSONObject(i) ?: continue
            val itemKey = obj.optString("trackId", obj.optString("playlistId", ""))
            val artPath = obj.optString("artworkPath", "")
            val artUrl = obj.optString("artworkUrl", "")
            val audioPath = obj.optString("audioFilePath", "")

            val hasLocalArt = artPath.isNotBlank() && File(artPath).let { it.exists() && it.length() > 0L }
            if (hasLocalArt) continue

            if (audioPath.isNotBlank()) {
                val extracted = getExtractedLocalArtFile(context, itemKey, audioPath)
                if (!extracted.exists() || extracted.length() == 0L) {
                    extractEmbeddedArtwork(context, itemKey, audioPath) {
                        updateWidgetsOfClass(context, providerCls)
                    }
                }
            }
            if (artUrl.isNotBlank()) {
                val cached = getCachedArtFile(context, itemKey, artUrl)
                if (!cached.exists() || cached.length() == 0L) {
                    cacheArtworkUrl(context, itemKey, artUrl) {
                        updateWidgetsOfClass(context, providerCls)
                    }
                }
            }
        }
    }

    private fun downloadUrlToPartFile(urlStr: String, partFile: File): Boolean {
        var currentUrl = urlStr
        for (hop in 0 until 5) {
            val conn = (URL(currentUrl).openConnection() as HttpURLConnection).apply {
                connectTimeout = 6000
                readTimeout = 8000
                instanceFollowRedirects = true
                doInput = true
                setRequestProperty("User-Agent", WIDGET_ART_USER_AGENT)
            }
            try {
                conn.connect()
                val code = conn.responseCode
                if (code in 300..399) {
                    val location = conn.getHeaderField("Location")
                    if (location.isNullOrBlank()) return false
                    currentUrl = URL(URL(currentUrl), location).toString()
                    continue
                }
                if (code !in 200..299) return false
                conn.inputStream.use { input ->
                    FileOutputStream(partFile).use { output ->
                        input.copyTo(output)
                    }
                }
                return partFile.exists() && partFile.length() > 0L
            } finally {
                conn.disconnect()
            }
        }
        return false
    }

    private fun isValidImageFile(file: File): Boolean {
        if (!file.exists() || file.length() <= 0L) return false
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, opts)
        return opts.outWidth > 0 && opts.outHeight > 0
    }

    private fun pruneWidgetArtCache(context: Context) {
        val dir = getWidgetArtDir(context)
        val files = dir.listFiles()?.filter { !it.name.endsWith(".part") } ?: return
        var totalBytes = files.sumOf { it.length() }
        if (files.size <= MAX_CACHE_FILES && totalBytes <= MAX_CACHE_BYTES) return

        val sorted = files.sortedBy { it.lastModified() }
        var remainingCount = files.size
        for (f in sorted) {
            if (remainingCount <= MAX_CACHE_FILES && totalBytes <= MAX_CACHE_BYTES) break
            val len = f.length()
            if (f.delete()) {
                remainingCount--
                totalBytes -= len
            }
        }
    }

    private fun formatDuration(ms: Long): String {
        if (ms <= 0) return "0:00"
        val totalSec = ms / 1000
        val min = totalSec / 60
        val sec = totalSec % 60
        return "%d:%02d".format(min, sec)
    }

    // --- Intent Builders ---
    private fun createMediaButtonPendingIntent(context: Context, keyCode: Int, reqCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            setComponent(ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver"))
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        return PendingIntent.getBroadcast(
            context,
            reqCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun createOpenAppPendingIntent(context: Context, route: String, reqCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(ACTION_NAVIGATE, true)
            putExtra(EXTRA_ROUTE, route)
        }
        return PendingIntent.getActivity(
            context,
            reqCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun createPlayTrackPendingIntent(context: Context, trackId: String, reqCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(ACTION_PLAY_TRACK, true)
            putExtra(EXTRA_TRACK_ID, trackId)
        }
        return PendingIntent.getActivity(
            context,
            reqCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun createOpenPlaylistPendingIntent(context: Context, playlistId: String, reqCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(ACTION_OPEN_PLAYLIST, true)
            putExtra(EXTRA_PLAYLIST_ID, playlistId)
        }
        return PendingIntent.getActivity(
            context,
            reqCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun createToggleFavPendingIntent(context: Context, reqCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(ACTION_TOGGLE_FAVORITE, true)
        }
        return PendingIntent.getActivity(
            context,
            reqCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}

