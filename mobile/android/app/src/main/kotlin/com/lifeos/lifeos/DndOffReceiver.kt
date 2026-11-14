package com.lifeos.lifeos

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Turns Do Not Disturb back off when a focus session ends. */
class DndOffReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.isNotificationPolicyAccessGranted) {
            nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
        }
    }

    companion object {
        private fun intent(context: Context) = PendingIntent.getBroadcast(
            context,
            4242,
            Intent(context, DndOffReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        fun schedule(context: Context, atMillis: Long) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            // Inexact is fine: at worst DND ends a few minutes late.
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, intent(context))
        }

        fun cancel(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(intent(context))
        }
    }
}
