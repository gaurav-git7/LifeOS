package com.lifeos.lifeos

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/** Home-screen "Today" widget. The app renders the picture (lib/data/widget/). */
class TodayWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.today_widget)
            val path = widgetData.getString("today_image", null)
            val bitmap = path?.takeIf { File(it).exists() }?.let { BitmapFactory.decodeFile(it) }
            if (bitmap != null) {
                views.setImageViewBitmap(R.id.today_image, bitmap)
                views.setViewVisibility(R.id.today_empty, View.GONE)
            } else {
                views.setViewVisibility(R.id.today_empty, View.VISIBLE)
            }
            views.setOnClickPendingIntent(
                R.id.today_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("lifeos://home")),
            )
            views.setOnClickPendingIntent(
                R.id.today_add,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("lifeos://quickadd")),
            )
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
