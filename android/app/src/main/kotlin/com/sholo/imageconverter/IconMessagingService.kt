package com.sholo.imageconverter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService
import java.util.Calendar

class IconMessagingService : FlutterFirebaseMessagingService() {
  override fun onMessageReceived(remoteMessage: RemoteMessage) {
    super.onMessageReceived(remoteMessage)

    val raw = remoteMessage.data["icon"]
    val key = resolveIconKey(raw)
    setLauncherIcon(key)

    maybeShowUpdateNotification(remoteMessage)
  }

  private fun maybeShowUpdateNotification(remoteMessage: RemoteMessage) {
    val rawUpdate = remoteMessage.data["update"] ?: return
    val update = rawUpdate.trim().lowercase()
    if (update != "1" && update != "true" && update != "yes") return

    val title = remoteMessage.data["title"]?.takeIf { it.isNotBlank() }
      ?: "Update available"
    val body = remoteMessage.data["body"]?.takeIf { it.isNotBlank() }
      ?: "A new version is ready. Tap to update."

    val packageName = applicationContext.packageName
    val defaultUrl = "market://details?id=$packageName"
    val url = remoteMessage.data["update_url"]?.takeIf { it.isNotBlank() } ?: defaultUrl

    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
    val pending = PendingIntent.getActivity(applicationContext, 0, intent, flags)

    val channelId = "updates"
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val channel = NotificationChannel(
        channelId,
        "Updates",
        NotificationManager.IMPORTANCE_HIGH,
      )
      val nm = getSystemService(NotificationManager::class.java)
      nm?.createNotificationChannel(channel)
    }

    val large = BitmapFactory.decodeResource(resources, R.drawable.onlylogo)
    val notification = NotificationCompat.Builder(applicationContext, channelId)
      .setSmallIcon(R.mipmap.ic_launcher)
      .setLargeIcon(large)
      .setContentTitle(title)
      .setContentText(body)
      .setPriority(NotificationCompat.PRIORITY_HIGH)
      .setAutoCancel(true)
      .setContentIntent(pending)
      .addAction(0, "Update now", pending)
      .build()

    NotificationManagerCompat.from(applicationContext).notify(2001, notification)
  }

  private fun resolveIconKey(value: String?): String {
    if (value == null) return monthKey()

    val v = value.trim().lowercase()
    if (v.isEmpty()) return monthKey()
    if (v == "auto") return monthKey()

    return when (v) {
      "january", "jan" -> "jan"
      "february", "feb" -> "feb"
      "march", "mar" -> "mar"
      "default" -> "default"
      else -> monthKey()
    }
  }

  private fun monthKey(): String {
    val month = Calendar.getInstance().get(Calendar.MONTH) + 1
    return when (month) {
      1 -> "jan"
      2 -> "feb"
      3 -> "mar"
      else -> "default"
    }
  }

  private fun setLauncherIcon(key: String) {
    try {
      val aliases = linkedMapOf(
        "default" to "com.sholo.imageconverter.LauncherDefault",
        "jan" to "com.sholo.imageconverter.LauncherJan",
        "feb" to "com.sholo.imageconverter.LauncherFeb",
        "mar" to "com.sholo.imageconverter.LauncherMar",
      )
      val desired = aliases[key] ?: aliases["default"]!!

      val pm = applicationContext.packageManager
      for ((_, className) in aliases) {
        val state = if (className == desired) {
          PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
          PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        pm.setComponentEnabledSetting(
          ComponentName(applicationContext, className),
          state,
          PackageManager.DONT_KILL_APP,
        )
      }
    } catch (_: Throwable) {
    }
  }
}
