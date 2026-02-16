import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'services/app_settings.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/external_open_service.dart';
import 'screen/home_screen.dart';
import 'screen/language_selection_screen.dart';
import 'screen/multiple_images_screen.dart';
import 'screen/privacy_policy_screen.dart';
import 'screen/report_bugs.dart';
import 'screen/result_folder_screen.dart';
import 'screen/single_image_screen.dart';
import 'screen/settings_screen.dart';
import 'screen/create_pdf_screen.dart';
import 'screen/star_imp.dart';
import 'screen/external_open_screen.dart';
import 'screen/splashscreen.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enable edge-to-edge display
  if (Platform.isAndroid) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const MyApp());

  unawaited(MobileAds.instance.initialize());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<String>? _externalOpenSub;
  String? _pendingRoute;
  Locale? _locale;
  final AppSettings _settings = const AppSettings();

  Future<void> _loadLocale() async {
    final code = await _settings.getLanguageCode();
    if (code != null) {
      setState(() {
        _locale = Locale(code);
      });
    }
  }

  void setLocale(Locale locale) {
    setState(() {
      _locale = locale;
    });
  }

  static const String _testBannerAdUnitId =
      'ca-app-pub-3645213065759243/8959837355';

  Future<void> _ensureDefaultLauncherIcon() async {
    if (!Platform.isAndroid) return;

    const channel = MethodChannel('com.sholo.imageconverter/launcher_icon');
    try {
      await channel.invokeMethod('setLauncherIcon', {'key': 'default'});
    } catch (_) {}
  }

  static const MethodChannel _routeChannel = MethodChannel(
    'com.sholo.imageconverter/deeplink',
  );

  Future<void> _initDeepLinks() async {
    _routeChannel.setMethodCallHandler((call) async {
      if (call.method == 'onRoute') {
        final route = call.arguments as String?;
        _handleRoute(route);
      }
    });

    try {
      final route = await _routeChannel.invokeMethod<String>('getInitialRoute');
      _handleRoute(route);
    } catch (_) {}
  }

  void _handleRoute(String? route) {
    if (route == null || route.isEmpty) return;

    if (route == 'results') {
      final nav = _navigatorKey.currentState;
      if (nav == null) {
        _pendingRoute = route;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final n = _navigatorKey.currentState;
          final r = _pendingRoute;
          if (n != null && r == 'results') {
            _pendingRoute = null;
            n.pushNamedAndRemoveUntil('/results', (route) => route.isFirst);
          }
        });
        return;
      }
      nav.pushNamedAndRemoveUntil('/results', (route) => route.isFirst);
    }
  }

  Future<void> _initNotifications() async {
    final messaging = FirebaseMessaging.instance;

    if (Platform.isIOS || Platform.isMacOS) {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
    } else if (Platform.isAndroid) {
      await Permission.notification.request();
    }

    try {
      await messaging.subscribeToTopic('all');
    } catch (_) {}

    try {
      await _syncVersionTopic(messaging);
    } catch (_) {}

    final token = await messaging.getToken();
    debugPrint('FCM token: $token');
  }

  Future<void> _syncVersionTopic(FirebaseMessaging messaging) async {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.replaceAll('.', '_');
    final currentTopic = 'v_$version';

    final prefs = await SharedPreferences.getInstance();
    const key = 'fcm_version_topic';
    final previousTopic = prefs.getString(key);

    if (previousTopic != null &&
        previousTopic.isNotEmpty &&
        previousTopic != currentTopic) {
      try {
        await messaging.unsubscribeFromTopic(previousTopic);
      } catch (_) {}
    }

    if (previousTopic != currentTopic) {
      await messaging.subscribeToTopic(currentTopic);
      await prefs.setString(key, currentTopic);
    }
  }

  Future<void> _checkForUpdates() async {
    if (!Platform.isAndroid) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;
      if (info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
        return;
      }
      if (info.flexibleUpdateAllowed) {
        await InAppUpdate.startFlexibleUpdate();
        await InAppUpdate.completeFlexibleUpdate();
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();

    unawaited(ExternalOpenService.instance.init());
    unawaited(_ensureDefaultLauncherIcon());
    unawaited(_checkForUpdates());
    unawaited(_initNotifications());
    unawaited(_initDeepLinks());
    unawaited(_loadLocale());

    _externalOpenSub = ExternalOpenService.instance.stream.listen((path) {
      final nav = _navigatorKey.currentState;
      if (nav == null) return;
      nav.push(
        MaterialPageRoute(builder: (_) => ExternalOpenScreen(path: path)),
      );
    });
  }

  @override
  void dispose() {
    _externalOpenSub?.cancel();
    super.dispose();
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image to File Converter – PDF, JPG & All Formats',
      navigatorKey: _navigatorKey,
      locale: _locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('hi'),
        Locale('es'),
        Locale('ps'),
        Locale('fil'),
        Locale('id'),
        Locale('my'),
        Locale('ru'),
        Locale('fa'),
        Locale('bn'),
        Locale('mr'),
        Locale('te'),
        Locale('ta'),
        Locale('ur'),
        Locale('ms'),
        Locale('pt'),
        Locale('fr'),
        Locale('de'),
        Locale('ar'),
        Locale('tr'),
        Locale('vi'),
        Locale('th'),
        Locale('ja'),
        Locale('ko'),
        Locale('it'),
        Locale('pl'),
        Locale('uk'),
        Locale('nl'),
        Locale('ro'),
        Locale('el'),
        Locale('cs'),
        Locale('hu'),
        Locale('sv'),
        Locale('zh'),
        Locale('he'),
        Locale('da'),
        Locale('fi'),
        Locale('no'),
        Locale('sk'),
        Locale('bg'),
        Locale('hr'),
        Locale('sr'),
        Locale('ca'),
      ],
      builder: (context, child) {
        return _GlobalBannerScaffold(
          backgroundColor: const Color(0xFF1B1E23),
          adUnitId: _testBannerAdUnitId,
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        useMaterial3: false,
        brightness: Brightness.dark,
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        scaffoldBackgroundColor: const Color(0xFF1B1E23),
        canvasColor: const Color(0xFF1B1E23),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4B2C83),
          brightness: Brightness.dark,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      home: const SplashScreen(),
      routes: {
        '/home': (context) => const HomeScreen(),
        '/single': (context) => const SingleImageScreen(),
        '/multiple': (context) => const MultipleImagesScreen(),
        '/create-pdf': (context) => const CreatePdfScreen(),
        '/results': (context) => const ResultFolderScreen(),
        '/star-imp': (context) => const StarImpScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/report-bugs': (context) => const ReportBugsScreen(),
        '/privacy-policy': (context) => const PrivacyPolicyScreen(),
        '/language-selection': (context) => const LanguageSelectionScreen(),
      },
    );
  }
}

class GlobalAdController {
  static final ValueNotifier<bool> showAds = ValueNotifier<bool>(false);
}

class _GlobalBannerScaffold extends StatefulWidget {
  const _GlobalBannerScaffold({
    required this.child,
    required this.adUnitId,
    required this.backgroundColor,
  });

  final Widget child;
  final String adUnitId;
  final Color backgroundColor;

  @override
  State<_GlobalBannerScaffold> createState() => _GlobalBannerScaffoldState();
}

class _GlobalBannerScaffoldState extends State<_GlobalBannerScaffold> {
  BannerAd? _bannerAd;
  bool _loaded = false;

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _hasConnection = true;
  bool _loadingAd = false;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
  }

  Future<void> _initConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    final connected = results.any((r) => r != ConnectivityResult.none);
    if (!mounted) return;
    setState(() {
      _hasConnection = connected;
    });

    if (_hasConnection) {
      _loadAd();
    }

    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final isConnected = results.any((r) => r != ConnectivityResult.none);
      if (!mounted) return;

      if (!isConnected) {
        _retryTimer?.cancel();
        _retryTimer = null;
        _disposeAd();
        setState(() {
          _hasConnection = false;
        });
        return;
      }

      final wasConnected = _hasConnection;
      setState(() {
        _hasConnection = true;
      });

      if (!wasConnected && _bannerAd == null) {
        _loadAd();
      }
    });
  }

  void _disposeAd() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _loaded = false;
    _loadingAd = false;
  }

  void _scheduleRetry() {
    if (!_hasConnection) return;
    if (_retryTimer != null) return;
    _retryTimer = Timer(const Duration(seconds: 5), () {
      _retryTimer = null;
      if (!mounted) return;
      if (_bannerAd == null && _hasConnection) {
        _loadAd();
      }
    });
  }

  void _loadAd() {
    if (_loadingAd) return;
    if (!_hasConnection) return;
    if (_bannerAd != null) return;

    _loadingAd = true;
    final ad = BannerAd(
      adUnitId: widget.adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() {
            _bannerAd = ad as BannerAd;
            _loaded = true;
            _loadingAd = false;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _bannerAd = null;
            _loaded = false;
            _loadingAd = false;
          });
          _scheduleRetry();
        },
      ),
    );

    _bannerAd = ad;
    ad.load();
  }

  @override
  void didUpdateWidget(covariant _GlobalBannerScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adUnitId != widget.adUnitId) {
      _disposeAd();
      _loadAd();
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _disposeAd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _bannerAd;

    return ValueListenableBuilder<bool>(
      valueListenable: GlobalAdController.showAds,
      builder: (context, adsVisible, _) {
        final adShowing = _loaded && ad != null && adsVisible;
        final adHeight = adShowing ? ad.size.height.toDouble() : 0.0;
        final bottomInset = MediaQuery.of(context).padding.bottom;
        final reservedHeight = adShowing ? (adHeight + bottomInset) : 0.0;

        final mq = MediaQuery.of(context);

        return ColoredBox(
          color: widget.backgroundColor,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.only(bottom: reservedHeight),
                  child: MediaQuery(
                    data: adShowing
                        ? mq.copyWith(
                            padding: mq.padding.copyWith(bottom: 0),
                            viewPadding: mq.viewPadding.copyWith(bottom: 0),
                          )
                        : mq,
                    child: widget.child,
                  ),
                ),
              ),
              if (adShowing)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SizedBox(
                    height: reservedHeight,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: bottomInset),
                      child: Center(
                        child: SizedBox(
                          width: ad.size.width.toDouble(),
                          height: adHeight,
                          child: AdWidget(ad: ad),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
