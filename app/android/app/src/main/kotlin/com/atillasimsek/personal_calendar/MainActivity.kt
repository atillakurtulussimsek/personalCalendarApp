package com.atillasimsek.personal_calendar

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges every native entry point (share sheet, deep links, Quick Settings tile,
 * notification action, widget) to Dart through the "personal_calendar/intents" channel.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: Map<String, String?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialIntent" -> {
                        result.success(pending)
                        pending = null
                    }
                    "setCaptureNotification" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        if (enabled) ensureNotificationPermission()
                        CaptureNotification.setEnabled(this, enabled)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent?.let { handle(it, initial = true) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handle(intent, initial = false)
    }

    private fun handle(intent: Intent, initial: Boolean) {
        val payload = extract(intent) ?: return
        // consume so a configuration change does not replay it
        intent.action = Intent.ACTION_MAIN
        intent.removeExtra(Intent.EXTRA_TEXT)
        intent.data = null
        val ch = channel
        if (initial || ch == null) {
            pending = payload
        } else {
            ch.invokeMethod("intent", payload)
        }
    }

    /** Returns {uri, text} for intents we understand, else null. */
    private fun extract(intent: Intent): Map<String, String?>? {
        val data = intent.data
        if (data != null && data.scheme == SCHEME) {
            return mapOf("uri" to data.toString(), "text" to data.getQueryParameter("text"))
        }
        if (intent.action == Intent.ACTION_SEND && intent.type?.startsWith("text/") == true) {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return null
            val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
            val full = if (!subject.isNullOrBlank() && !text.contains(subject)) "$subject\n$text" else text
            return mapOf("uri" to "$SCHEME://capture", "text" to full)
        }
        // home_widget launch intents carry our scheme in data as well
        if (data != null && intent.action == "es.antonborri.home_widget.action.LAUNCH") {
            return mapOf("uri" to data.toString(), "text" to data.getQueryParameter("text"))
        }
        return null
    }

    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(this, arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    companion object {
        const val CHANNEL = "personal_calendar/intents"
        const val SCHEME = "personalcalendar"
    }
}
