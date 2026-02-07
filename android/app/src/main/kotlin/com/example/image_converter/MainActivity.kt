package com.sholo.imageconverter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
  private val externalOpenChannelName = "com.sholo.imageconverter/external_open"
  private val launcherIconChannelName = "com.sholo.imageconverter/launcher_icon"
  private val routeChannelName = "com.sholo.imageconverter/deeplink"
  private val progressChannelName = "com.sholo.imageconverter/progress_notification"
  private var externalOpenChannel: MethodChannel? = null
  private var launcherIconChannel: MethodChannel? = null
  private var routeChannel: MethodChannel? = null
  private var progressChannel: MethodChannel? = null
  private var initialExternalPath: String? = null
  private var initialRoute: String? = null

  private val supportedMimeTypes = setOf(
    "application/pdf",
    "image/jpeg",
    "image/png",
    "image/gif",
    "image/bmp",
  )

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GoogleMobileAdsPlugin.registerNativeAdFactory(
      flutterEngine,
      "homeNative",
      HomeNativeAdFactory(this),
    )

    externalOpenChannel = MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      externalOpenChannelName,
    )
    externalOpenChannel?.setMethodCallHandler { call, result ->
      if (call.method == "getInitialPath") {
        val path = initialExternalPath
        initialExternalPath = null
        result.success(path)
        return@setMethodCallHandler
      }
      result.notImplemented()
    }

    launcherIconChannel = MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      launcherIconChannelName,
    )
    launcherIconChannel?.setMethodCallHandler { call, result ->
      if (call.method == "setLauncherIcon") {
        val key = call.argument<String>("key")
        result.success(setLauncherIcon(key))
        return@setMethodCallHandler
      }
      result.notImplemented()
    }

    routeChannel = MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      routeChannelName,
    )
    routeChannel?.setMethodCallHandler { call, result ->
      if (call.method == "getInitialRoute") {
        val route = initialRoute
        initialRoute = null
        result.success(route)
        return@setMethodCallHandler
      }
      result.notImplemented()
    }

    progressChannel = MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      progressChannelName,
    )
    progressChannel?.setMethodCallHandler { call, result ->
      when (call.method) {
        "start" -> {
          val total = call.argument<Int>("total") ?: 0
          val title = call.argument<String>("title")
          val body = call.argument<String>("body")
          startOrUpdateSaveService(done = 0, total = total, title = title, body = body)
          result.success(true)
          return@setMethodCallHandler
        }
        "update" -> {
          val done = call.argument<Int>("done") ?: 0
          val total = call.argument<Int>("total") ?: 0
          val title = call.argument<String>("title")
          val body = call.argument<String>("body")
          startOrUpdateSaveService(done = done, total = total, title = title, body = body)
          result.success(true)
          return@setMethodCallHandler
        }
        "complete" -> {
          val title = call.argument<String>("title")
          val body = call.argument<String>("body")
          completeSaveService(title = title, body = body)
          result.success(true)
          return@setMethodCallHandler
        }
        "cancel" -> {
          cancelSaveService()
          result.success(true)
          return@setMethodCallHandler
        }
        else -> result.notImplemented()
      }
    }

    captureInitialExternalOpen(intent)
    captureInitialRoute(intent)
  }

  override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
    GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "homeNative")
    super.cleanUpFlutterEngine(flutterEngine)
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    deliverExternalOpen(intent)
    deliverRoute(intent)
  }

  private fun captureInitialExternalOpen(intent: Intent?) {
    val path = extractPathFromIntent(intent) ?: return
    initialExternalPath = path
  }

  private fun captureInitialRoute(intent: Intent?) {
    val route = extractRouteFromIntent(intent) ?: return
    initialRoute = route
  }

  private fun deliverExternalOpen(intent: Intent?) {
    val path = extractPathFromIntent(intent) ?: return
    val channel = externalOpenChannel
    if (channel == null) {
      initialExternalPath = path
      return
    }
    channel.invokeMethod("onOpenFile", path)
  }

  private fun deliverRoute(intent: Intent?) {
    val route = extractRouteFromIntent(intent) ?: return
    val channel = routeChannel
    if (channel == null) {
      initialRoute = route
      return
    }
    channel.invokeMethod("onRoute", route)
  }

  private fun extractPathFromIntent(intent: Intent?): String? {
    if (intent == null) return null
    if (intent.action != Intent.ACTION_VIEW) return null
    val uri = intent.data ?: return null
    val scheme = uri.scheme
    if (scheme != null && scheme != "content" && scheme != "file") return null
    val mime = intent.type
    if (mime == "image/webp") return null
    if (mime != null && !supportedMimeTypes.contains(mime)) return null
    return copyUriToCache(uri, mime)
  }

  private fun extractRouteFromIntent(intent: Intent?): String? {
    if (intent == null) return null
    if (intent.action != Intent.ACTION_VIEW) return null
    val uri = intent.data ?: return null
    if (uri.scheme != "imageconverter") return null
    if (uri.host != "open") return null
    val route = uri.getQueryParameter("route")?.trim()
    if (route.isNullOrEmpty()) return null
    return route
  }

  private fun ensureNotificationChannel(channelId: String, name: String, importance: Int) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val nm = getSystemService(NotificationManager::class.java)
    val existing = nm?.getNotificationChannel(channelId)
    if (existing != null) return
    val channel = NotificationChannel(channelId, name, importance)
    nm?.createNotificationChannel(channel)
  }

  private fun startOrUpdateSaveService(done: Int, total: Int, title: String?, body: String?) {
    val intent = Intent(this, SaveForegroundService::class.java).apply {
      action = if (done <= 0) SaveForegroundService.ACTION_START else SaveForegroundService.ACTION_UPDATE
      putExtra(SaveForegroundService.EXTRA_DONE, done)
      putExtra(SaveForegroundService.EXTRA_TOTAL, total)
      if (!title.isNullOrEmpty()) putExtra(SaveForegroundService.EXTRA_TITLE, title)
      if (!body.isNullOrEmpty()) putExtra(SaveForegroundService.EXTRA_BODY, body)
    }

    ContextCompat.startForegroundService(this, intent)
  }

  private fun completeSaveService(title: String?, body: String?) {
    val intent = Intent(this, SaveForegroundService::class.java).apply {
      action = SaveForegroundService.ACTION_COMPLETE
      if (!title.isNullOrEmpty()) putExtra(SaveForegroundService.EXTRA_TITLE, title)
      if (!body.isNullOrEmpty()) putExtra(SaveForegroundService.EXTRA_BODY, body)
    }
    startService(intent)
  }

  private fun cancelSaveService() {
    val intent = Intent(this, SaveForegroundService::class.java).apply {
      action = SaveForegroundService.ACTION_CANCEL
    }
    startService(intent)
  }

  private fun showSaveProgressNotification(done: Int, total: Int, title: String?) {
    val channelId = "save_progress"
    ensureNotificationChannel(channelId, "Saving", NotificationManager.IMPORTANCE_LOW)

    val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
      ?: Intent(this, MainActivity::class.java)

    val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
    val pending = PendingIntent.getActivity(this, 3001, launchIntent, pendingFlags)

    val safeTotal = if (total < 0) 0 else total
    val safeDone = if (done < 0) 0 else done
    val shownTitle = title?.takeIf { it.isNotBlank() } ?: "Saving"
    val shownBody = if (safeTotal > 0) "${safeDone.coerceAtMost(safeTotal)}/$safeTotal" else "Working"

    val builder = NotificationCompat.Builder(this, channelId)
      .setSmallIcon(R.drawable.ic_stat_notify)
      .setContentTitle(shownTitle)
      .setContentText(shownBody)
      .setOnlyAlertOnce(true)
      .setOngoing(true)
      .setAutoCancel(false)
      .setContentIntent(pending)
      .setPriority(NotificationCompat.PRIORITY_LOW)

    if (safeTotal > 0) {
      builder.setProgress(safeTotal, safeDone.coerceAtMost(safeTotal), false)
    } else {
      builder.setProgress(0, 0, true)
    }

    NotificationManagerCompat.from(this).notify(3001, builder.build())
  }

  private fun showSaveCompletedNotification(title: String?, body: String?) {
    val channelId = "save_complete"
    ensureNotificationChannel(channelId, "Completed", NotificationManager.IMPORTANCE_DEFAULT)

    NotificationManagerCompat.from(this).cancel(3001)

    val intent = Intent(Intent.ACTION_VIEW, Uri.parse("imageconverter://open?route=results")).apply {
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    }

    val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
    val pending = PendingIntent.getActivity(this, 3002, intent, pendingFlags)

    val notification = NotificationCompat.Builder(this, channelId)
      .setSmallIcon(R.drawable.ic_stat_notify)
      .setContentTitle(title?.takeIf { it.isNotBlank() } ?: "Completed")
      .setContentText(body?.takeIf { it.isNotBlank() } ?: "Tap to see results")
      .setAutoCancel(true)
      .setContentIntent(pending)
      .setPriority(NotificationCompat.PRIORITY_DEFAULT)
      .build()

    NotificationManagerCompat.from(this).notify(3002, notification)
  }

  private fun cancelSaveProgressNotification() {
    NotificationManagerCompat.from(this).cancel(3001)
  }

  private fun copyUriToCache(uri: Uri, mime: String?): String? {
    return try {
      val displayName = queryDisplayName(uri) ?: "external_${System.currentTimeMillis()}"
      val sanitized = displayName.replace(Regex("[^a-zA-Z0-9._-]"), "_")

      val lower = sanitized.lowercase()
      if (lower.endsWith(".webp")) return null

      val extFromMime = when (mime) {
        "application/pdf" -> "pdf"
        "image/jpeg" -> "jpg"
        "image/png" -> "png"
        "image/gif" -> "gif"
        "image/bmp" -> "bmp"
        else -> null
      }

      val hasExt = lower.contains('.') && lower.substringAfterLast('.').isNotBlank()
      val safeName = if (hasExt || extFromMime == null) sanitized else "$sanitized.$extFromMime"
      val outFile = File(cacheDir, safeName)

      contentResolver.openInputStream(uri)?.use { input ->
        FileOutputStream(outFile).use { output ->
          input.copyTo(output)
          output.flush()
          try {
            output.fd.sync()
          } catch (_: Throwable) {
          }
        }
      } ?: return null

      // Basic validation: avoid returning empty / truncated files.
      if (!outFile.exists()) return null
      if (outFile.length() < 16) return null

      outFile.absolutePath
    } catch (_: Throwable) {
      null
    }
  }

  private fun queryDisplayName(uri: Uri): String? {
    return try {
      contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
        if (index < 0) return@use null
        if (!cursor.moveToFirst()) return@use null
        cursor.getString(index)
      }
    } catch (_: Throwable) {
      null
    }
  }

  private fun setLauncherIcon(key: String?): Boolean {
    return try {
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
      true
    } catch (_: Throwable) {
      false
    }
  }
}

private class HomeNativeAdFactory(private val context: Context) :
  GoogleMobileAdsPlugin.NativeAdFactory {
  override fun createNativeAd(
    nativeAd: NativeAd,
    customOptions: MutableMap<String, Any>?,
  ): NativeAdView {
    val adView = LayoutInflater.from(context).inflate(R.layout.native_ad, null) as NativeAdView

    val headline = adView.findViewById<TextView>(R.id.ad_headline)
    val body = adView.findViewById<TextView>(R.id.ad_body)
    val icon = adView.findViewById<ImageView>(R.id.ad_app_icon)
    val cta = adView.findViewById<Button>(R.id.ad_call_to_action)

    headline.text = nativeAd.headline
    adView.headlineView = headline

    if (nativeAd.body == null) {
      body.visibility = View.GONE
    } else {
      body.text = nativeAd.body
      body.visibility = View.VISIBLE
      adView.bodyView = body
    }

    val iconDrawable = nativeAd.icon?.drawable
    if (iconDrawable == null) {
      icon.visibility = View.GONE
    } else {
      icon.setImageDrawable(iconDrawable)
      icon.visibility = View.VISIBLE
      adView.iconView = icon
    }

    if (nativeAd.callToAction == null) {
      cta.visibility = View.GONE
    } else {
      cta.text = nativeAd.callToAction
      cta.visibility = View.VISIBLE
      adView.callToActionView = cta
    }

    adView.setNativeAd(nativeAd)
    return adView
  }
}
