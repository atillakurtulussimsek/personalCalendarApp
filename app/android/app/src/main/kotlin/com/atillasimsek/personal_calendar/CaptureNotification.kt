package com.atillasimsek.personal_calendar

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.app.NotificationCompat

/** Optional persistent notification with a "quick note" action (toggled from settings). */
object CaptureNotification {
    private const val CHANNEL_ID = "capture"
    private const val ID = 7001
    private const val PREFS = "capture_notification"
    private const val KEY_ENABLED = "enabled"

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ENABLED, enabled).apply()
        if (enabled) show(context) else hide(context)
    }

    fun show(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, context.getString(R.string.capture_channel), NotificationManager.IMPORTANCE_MIN).apply {
                setShowBadge(false)
            }
        )
        val capture = pendingUri(context, "$SCHEME://capture", 1)
        val note = pendingUri(context, "$SCHEME://note", 2)
        val event = pendingUri(context, "$SCHEME://event", 3)
        val n = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_capture)
            .setContentTitle(context.getString(R.string.capture_title))
            .setContentText(context.getString(R.string.capture_hint))
            .setContentIntent(capture)
            .addAction(0, context.getString(R.string.capture_action_note), note)
            .addAction(0, context.getString(R.string.capture_action_event), event)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
        try {
            nm.notify(ID, n)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS denied
        }
    }

    fun hide(context: Context) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(ID)
    }

    private fun pendingUri(context: Context, uri: String, code: Int): PendingIntent {
        val i = Intent(Intent.ACTION_VIEW, Uri.parse(uri), context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(context, code, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private const val SCHEME = MainActivity.SCHEME
}

/** Re-shows the notification after reboot when enabled. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED && CaptureNotification.isEnabled(context)) {
            CaptureNotification.show(context)
        }
    }
}
