package com.sholo.imageconverter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class SaveForegroundService : Service() {
  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_START, ACTION_UPDATE -> {
        val done = intent.getIntExtra(EXTRA_DONE, 0)
        val total = intent.getIntExtra(EXTRA_TOTAL, 0)
        val title = intent.getStringExtra(EXTRA_TITLE)
        showProgress(done = done, total = total, title = title, alert = intent.action == ACTION_START)
      }
      ACTION_COMPLETE -> {
        val title = intent.getStringExtra(EXTRA_TITLE)
        val body = intent.getStringExtra(EXTRA_BODY)
        stopProgressForeground()
        showCompleted(title = title, body = body)
        stopSelf()
      }
      ACTION_CANCEL -> {
        stopProgressForeground()
        stopSelf()
      }
    }

    return START_NOT_STICKY
  }

  private fun ensureChannel(channelId: String, name: String, importance: Int) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val nm = getSystemService(NotificationManager::class.java)
    val existing = nm?.getNotificationChannel(channelId)
    if (existing != null) return

    val channel = NotificationChannel(channelId, name, importance)
    if (channelId == CHANNEL_PROGRESS) {
      channel.setSound(null, null)
      channel.enableVibration(false)
      channel.enableLights(false)
      channel.setShowBadge(false)
    }
    nm?.createNotificationChannel(channel)
  }

  private fun showProgress(done: Int, total: Int, title: String?, alert: Boolean) {
    val channelId = CHANNEL_PROGRESS
    ensureChannel(channelId, "Saving", NotificationManager.IMPORTANCE_HIGH)

    val safeTotal = if (total < 0) 0 else total
    val safeDone = if (done < 0) 0 else done

    val shownTitle = title?.takeIf { it.isNotBlank() } ?: "Saving"
    val shownBody = if (safeTotal > 0) "${safeDone.coerceAtMost(safeTotal)}/$safeTotal" else "Working"

    val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
      ?: Intent(this, MainActivity::class.java)

    val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
    val pending = PendingIntent.getActivity(this, 3001, launchIntent, pendingFlags)

    val large = BitmapFactory.decodeResource(resources, R.drawable.onlylogo)

    val builder = NotificationCompat.Builder(this, channelId)
      .setSmallIcon(R.mipmap.ic_launcher)
      .setLargeIcon(large)
      .setContentTitle(shownTitle)
      .setContentText(shownBody)
      .setOnlyAlertOnce(!alert)
      .setOngoing(true)
      .setAutoCancel(false)
      .setContentIntent(pending)
      .setPriority(NotificationCompat.PRIORITY_HIGH)

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      builder.setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
    }

    if (safeTotal > 0) {
      builder.setProgress(safeTotal, safeDone.coerceAtMost(safeTotal), false)
    } else {
      builder.setProgress(0, 0, true)
    }

    startForeground(NOTIFICATION_PROGRESS_ID, builder.build())
  }

  private fun stopProgressForeground() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      stopForeground(STOP_FOREGROUND_REMOVE)
    } else {
      @Suppress("DEPRECATION")
      stopForeground(true)
    }
    NotificationManagerCompat.from(this).cancel(NOTIFICATION_PROGRESS_ID)
  }

  private fun showCompleted(title: String?, body: String?) {
    val channelId = CHANNEL_COMPLETE
    ensureChannel(channelId, "Completed", NotificationManager.IMPORTANCE_DEFAULT)

    val intent = Intent(Intent.ACTION_VIEW, Uri.parse("imageconverter://open?route=results")).apply {
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    }

    val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
    val pending = PendingIntent.getActivity(this, 3002, intent, pendingFlags)

    val large = BitmapFactory.decodeResource(resources, R.drawable.onlylogo)

    val notification = NotificationCompat.Builder(this, channelId)
      .setSmallIcon(R.mipmap.ic_launcher)
      .setLargeIcon(large)
      .setContentTitle(title?.takeIf { it.isNotBlank() } ?: "Completed")
      .setContentText(body?.takeIf { it.isNotBlank() } ?: "Tap to see results")
      .setAutoCancel(true)
      .setContentIntent(pending)
      .setPriority(NotificationCompat.PRIORITY_DEFAULT)
      .build()

    NotificationManagerCompat.from(this).notify(NOTIFICATION_COMPLETE_ID, notification)
  }

  companion object {
    const val ACTION_START = "com.sholo.imageconverter.SAVE_PROGRESS_START"
    const val ACTION_UPDATE = "com.sholo.imageconverter.SAVE_PROGRESS_UPDATE"
    const val ACTION_COMPLETE = "com.sholo.imageconverter.SAVE_PROGRESS_COMPLETE"
    const val ACTION_CANCEL = "com.sholo.imageconverter.SAVE_PROGRESS_CANCEL"

    const val EXTRA_DONE = "done"
    const val EXTRA_TOTAL = "total"
    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"

    private const val CHANNEL_PROGRESS = "save_progress_v2"
    private const val CHANNEL_COMPLETE = "save_complete"

    private const val NOTIFICATION_PROGRESS_ID = 3001
    private const val NOTIFICATION_COMPLETE_ID = 3002
  }
}
