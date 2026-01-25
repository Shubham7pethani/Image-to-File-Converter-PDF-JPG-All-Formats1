package com.sholo.imageconverter

import android.content.Intent
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
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
  private var externalOpenChannel: MethodChannel? = null
  private var initialExternalPath: String? = null

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

    captureInitialExternalOpen(intent)
  }

  override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
    GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "homeNative")
    super.cleanUpFlutterEngine(flutterEngine)
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    deliverExternalOpen(intent)
  }

  private fun captureInitialExternalOpen(intent: Intent?) {
    val path = extractPathFromIntent(intent) ?: return
    initialExternalPath = path
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
