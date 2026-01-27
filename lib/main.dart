import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/external_open_service.dart';
import 'screen/splashscreen.dart';
import 'screen/home_screen.dart';
import 'screen/multiple_images_screen.dart';
import 'screen/privacy_policy_screen.dart';
import 'screen/report_bugs.dart';
import 'screen/result_folder_screen.dart';
import 'screen/single_image_screen.dart';
import 'screen/settings_screen.dart';
import 'screen/create_pdf_screen.dart';
import 'screen/star_imp.dart';
import 'screen/external_open_screen.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const MyApp());

  unawaited(MobileAds.instance.initialize());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<String>? _externalOpenSub;
  String? _pendingRoute;

  static const MethodChannel _routeChannel = MethodChannel(
    'com.sholo.imageconverter/deeplink',
  );

  Future<void> _syncLauncherIcon() async {
    if (!Platform.isAndroid) return;

    const channel = MethodChannel('com.sholo.imageconverter/launcher_icon');
    final month = DateTime.now().month;

    final key = switch (month) {
      1 => 'jan',
      2 => 'feb',
      3 => 'mar',
      _ => 'default',
    };

    try {
      await channel.invokeMethod('setLauncherIcon', {'key': key});
    } catch (_) {}
  }

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
    unawaited(_syncLauncherIcon());
    unawaited(_checkForUpdates());
    unawaited(_initNotifications());
    unawaited(_initDeepLinks());
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
      builder: (context, child) {
        return ColoredBox(
          color: const Color(0xFF1B1E23),
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
      },
    );
  }
}
