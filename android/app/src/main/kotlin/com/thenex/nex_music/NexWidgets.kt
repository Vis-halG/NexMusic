package com.thenex.nex_music

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.SystemClock
import android.provider.AlarmClock
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject

/** Songs and playback state the app last handed to the home screen widgets. */
object NexWidgets {
    private const val PREFS = "nexmusic_widgets"
    private const val DATA = "data"
    private val providers = listOf(
        NowPlayingWidget::class.java,
        MiniPlayerWidget::class.java,
        SquarePlayerWidget::class.java,
        BigPlayerWidget::class.java,
        TallPlayerWidget::class.java,
        PlayButtonWidget::class.java,
        ClockPlayerWidget::class.java,
        QuickActionsWidget::class.java,
        LatestSongsWidget::class.java,
        RecentSongsWidget::class.java,
        LikedSongsWidget::class.java,
    )

    fun save(context: Context, json: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(DATA, json).apply()
        refreshAll(context)
    }

    fun data(context: Context): JSONObject = try {
        JSONObject(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(DATA, null) ?: "{}")
    } catch (error: Exception) {
        JSONObject()
    }

    private fun refreshAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        for (provider in providers) {
            val ids = manager.getAppWidgetIds(ComponentName(context, provider))
            if (ids.isEmpty()) continue
            context.sendBroadcast(
                Intent(context, provider)
                    .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids),
            )
        }
    }
}

/**
 * A music player widget. Each design has its own layout and play/pause
 * icons; views a layout leaves out are skipped by RemoteViews.
 */
abstract class PlayerWidget(
    private val layoutRes: Int,
    private val playRes: Int,
    private val pauseRes: Int,
) : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        val now = NexWidgets.data(context).optJSONObject("now")
        val playing = now?.optBoolean("playing") == true
        val next = now?.optString("next").orEmpty()
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, layoutRes)
            views.setTextViewText(
                R.id.now_title,
                now?.optString("title") ?: context.getString(R.string.widget_nothing_playing),
            )
            views.setTextViewText(
                R.id.now_subtitle,
                now?.optString("subtitle") ?: context.getString(R.string.widget_tap_to_open),
            )
            views.setTextViewText(
                R.id.now_status,
                context.getString(
                    when {
                        now == null -> R.string.widget_status_idle
                        playing -> R.string.widget_status_playing
                        else -> R.string.widget_status_paused
                    },
                ),
            )
            views.setTextViewText(R.id.now_up_next, context.getString(R.string.widget_up_next, next))
            views.setViewVisibility(R.id.now_up_next, if (next.isEmpty()) View.GONE else View.VISIBLE)
            views.setImageViewResource(R.id.now_play, if (playing) pauseRes else playRes)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                NexPhone.openAppIntent(context, if (now == null) null else "player", 1),
            )
            views.setOnClickPendingIntent(R.id.now_previous, WidgetMediaReceiver.intent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
            views.setOnClickPendingIntent(R.id.now_play, WidgetMediaReceiver.intent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
            views.setOnClickPendingIntent(R.id.now_next, WidgetMediaReceiver.intent(context, KeyEvent.KEYCODE_MEDIA_NEXT))
            views.setOnClickPendingIntent(R.id.clock_area, clockAppIntent(context))
            manager.updateAppWidget(widgetId, views)
        }
    }
}

/** Opens the phone's Clock app on its alarms. */
private fun clockAppIntent(context: Context): PendingIntent = PendingIntent.getActivity(
    context,
    40,
    Intent(AlarmClock.ACTION_SHOW_ALARMS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
)

/**
 * A clock widget. TextClock and AnalogClock keep the time themselves, so the
 * app never has to update these; tapping one opens the Clock app.
 */
abstract class ClockWidget(private val layoutRes: Int) : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, layoutRes)
            views.setOnClickPendingIntent(R.id.widget_root, clockAppIntent(context))
            manager.updateAppWidget(widgetId, views)
        }
    }
}

/** 4×2 violet card with the time and date. */
class BigClockWidget : ClockWidget(R.layout.widget_clock_big)

/** 2×2 round clock face. */
class AnalogClockWidget : ClockWidget(R.layout.widget_clock_analog)

/** 2×3 hours over minutes. */
class StackedClockWidget : ClockWidget(R.layout.widget_clock_stacked)

/** 3×1 date and time pill. */
class DateClockWidget : ClockWidget(R.layout.widget_clock_date)

/** 4×1 time beside the playing song; the song side works like a player. */
class ClockPlayerWidget : PlayerWidget(R.layout.widget_clock_player, R.drawable.widget_play_accent, R.drawable.widget_pause_accent)

/** 4×1 white card: art, title, category, previous, play/pause, next. */
class NowPlayingWidget : PlayerWidget(R.layout.widget_now_playing, R.drawable.widget_play, R.drawable.widget_pause)

/** 2×1 violet pill. */
class MiniPlayerWidget : PlayerWidget(R.layout.widget_player_mini, R.drawable.widget_play_accent, R.drawable.widget_pause_accent)

/** 2×2 dark-to-violet card. */
class SquarePlayerWidget : PlayerWidget(R.layout.widget_player_square, R.drawable.widget_play_accent, R.drawable.widget_pause_accent)

/** 4×2 card with art tile and what plays next. */
class BigPlayerWidget : PlayerWidget(R.layout.widget_player_big, R.drawable.widget_play, R.drawable.widget_pause)

/** 2×3 vertical violet card. */
class TallPlayerWidget : PlayerWidget(R.layout.widget_player_tall, R.drawable.widget_play_accent, R.drawable.widget_pause_accent)

/** 1×1 round play/pause button. */
class PlayButtonWidget : PlayerWidget(R.layout.widget_player_button, R.drawable.widget_play, R.drawable.widget_pause)

/** Upload, search, browser and downloads shortcuts. */
class QuickActionsWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_quick_actions)
            views.setOnClickPendingIntent(R.id.quick_upload, NexPhone.openAppIntent(context, "upload", 11))
            views.setOnClickPendingIntent(R.id.quick_search, NexPhone.openAppIntent(context, "search", 12))
            views.setOnClickPendingIntent(R.id.quick_browser, NexPhone.openAppIntent(context, "browser", 13))
            views.setOnClickPendingIntent(R.id.quick_downloads, NexPhone.openAppIntent(context, "downloads", 14))
            manager.updateAppWidget(widgetId, views)
        }
    }
}

/** Up to three songs from one list; tapping a song plays it. */
abstract class SongListWidget(
    private val key: String,
    private val labelRes: Int,
    private val emptyRes: Int,
) : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        val songs = NexWidgets.data(context).optJSONArray(key)
        val rows = listOf(
            Triple(R.id.row1, R.id.row1_title, R.id.row1_subtitle),
            Triple(R.id.row2, R.id.row2_title, R.id.row2_subtitle),
            Triple(R.id.row3, R.id.row3_title, R.id.row3_subtitle),
        )
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_song_list)
            views.setTextViewText(R.id.widget_title, context.getString(labelRes))
            views.setTextViewText(R.id.widget_empty, context.getString(emptyRes))
            views.setViewVisibility(R.id.widget_empty, if ((songs?.length() ?: 0) == 0) View.VISIBLE else View.GONE)
            views.setOnClickPendingIntent(R.id.widget_root, NexPhone.openAppIntent(context, null, 0))
            rows.forEachIndexed { index, (row, title, subtitle) ->
                val song = songs?.optJSONObject(index)
                if (song == null) {
                    views.setViewVisibility(row, View.GONE)
                    return@forEachIndexed
                }
                views.setViewVisibility(row, View.VISIBLE)
                views.setTextViewText(title, song.optString("title"))
                views.setTextViewText(subtitle, song.optString("subtitle"))
                views.setOnClickPendingIntent(
                    row,
                    NexPhone.openAppIntent(context, "play:${song.optString("id")}", widgetId * 10 + index + 20),
                )
            }
            manager.updateAppWidget(widgetId, views)
        }
    }
}

class LatestSongsWidget : SongListWidget("latest", R.string.widget_latest_label, R.string.widget_latest_empty)

class RecentSongsWidget : SongListWidget("recent", R.string.widget_recent_label, R.string.widget_recent_empty)

class LikedSongsWidget : SongListWidget("liked", R.string.widget_liked_label, R.string.widget_liked_empty)

/** Play/pause and skip buttons on the Now playing widget. */
class WidgetMediaReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val keyCode = intent.getIntExtra(EXTRA_KEY, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
        if (NexPhone.sessionActive) {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val time = SystemClock.uptimeMillis()
            audio.dispatchMediaKeyEvent(KeyEvent(time, time, KeyEvent.ACTION_DOWN, keyCode, 0))
            audio.dispatchMediaKeyEvent(KeyEvent(time, time, KeyEvent.ACTION_UP, keyCode, 0))
            return
        }
        // nexMusic is not running: open it on the song the widget shows.
        val id = NexWidgets.data(context).optJSONObject("now")?.optString("id")
        try {
            NexPhone.openAppIntent(context, if (id.isNullOrEmpty()) null else "play:$id", 2).send()
        } catch (error: PendingIntent.CanceledException) {
            // The app is being updated or removed.
        }
    }

    companion object {
        private const val EXTRA_KEY = "key"

        fun intent(context: Context, keyCode: Int): PendingIntent = PendingIntent.getBroadcast(
            context,
            keyCode,
            Intent(context, WidgetMediaReceiver::class.java).putExtra(EXTRA_KEY, keyCode),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
