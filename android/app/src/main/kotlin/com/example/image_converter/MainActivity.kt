package com.example.image_converter

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GoogleMobileAdsPlugin.registerNativeAdFactory(
      flutterEngine,
      "homeNative",
      HomeNativeAdFactory(this),
    )
  }

  override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
    GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "homeNative")
    super.cleanUpFlutterEngine(flutterEngine)
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
