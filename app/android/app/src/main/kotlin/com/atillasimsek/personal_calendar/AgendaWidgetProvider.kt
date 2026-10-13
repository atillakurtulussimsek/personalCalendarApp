package com.atillasimsek.personal_calendar

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/** Home screen widget: today's agenda + a quick-add button. Data comes from Dart via home_widget. */
class AgendaWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        val date = widgetData.getString("today_date", "") ?: ""
        val lines = widgetData.getString("today_lines", "[]") ?: "[]"
        val text = buildString {
            val arr = try { JSONArray(lines) } catch (_: Exception) { JSONArray() }
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                if (i > 0) append('\n')
                append(o.optString("time")).append("  ").append(o.optString("title"))
            }
            if (arr.length() == 0) append(context.getString(R.string.widget_no_events))
        }
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.agenda_widget).apply {
                setTextViewText(R.id.widget_date, if (date.isEmpty()) context.getString(R.string.widget_today) else date)
                setTextViewText(R.id.widget_lines, text)
                setOnClickPendingIntent(R.id.widget_add, pendingUri(context, "${MainActivity.SCHEME}://capture", 21))
                setOnClickPendingIntent(R.id.widget_root, pendingUri(context, "${MainActivity.SCHEME}://today", 22))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun pendingUri(context: Context, uri: String, code: Int): PendingIntent {
        val i = Intent(Intent.ACTION_VIEW, Uri.parse(uri), context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(context, code, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}
