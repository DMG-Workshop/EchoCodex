package com.dmgworkshop.echo_codex_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class EchoCodexWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        widgetIds: IntArray,
    ) {
        val openIntent = launchIntent(context, ACTION_OPEN)
        val recordIntent = launchIntent(context, ACTION_RECORD)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val openPending = PendingIntent.getActivity(context, 1, openIntent, flags)
        val recordPending = PendingIntent.getActivity(context, 2, recordIntent, flags)

        for (widgetId in widgetIds) {
            val views = RemoteViews(context.packageName, R.layout.echo_codex_widget).apply {
                setOnClickPendingIntent(R.id.widget_open, openPending)
                setOnClickPendingIntent(R.id.widget_record, recordPending)
            }
            manager.updateAppWidget(widgetId, views)
        }
    }

    private fun launchIntent(context: Context, action: String): Intent =
        Intent(context, MainActivity::class.java).apply {
            this.action = action
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

    companion object {
        const val ACTION_OPEN = "com.dmgworkshop.echo_codex_app.WIDGET_OPEN"
        const val ACTION_RECORD = "com.dmgworkshop.echo_codex_app.WIDGET_RECORD"
    }
}
