import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  @override
  void initState() {
    super.initState();

    unawaited(ExternalOpenService.instance.init());
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
