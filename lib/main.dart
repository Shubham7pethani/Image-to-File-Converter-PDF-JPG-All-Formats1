import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'screen/splashscreen.dart';
import 'screen/home_screen.dart';
import 'screen/multiple_images_screen.dart';
import 'screen/privacy_policy_screen.dart';
import 'screen/report_bugs.dart';
import 'screen/result_folder_screen.dart';
import 'screen/single_image_screen.dart';
import 'screen/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image to File Converter – PDF, JPG & All Formats',
      theme: ThemeData(
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4B2C83)),
      ),
      home: const SplashScreen(),
      routes: {
        '/home': (context) => const HomeScreen(),
        '/single': (context) => const SingleImageScreen(),
        '/multiple': (context) => const MultipleImagesScreen(),
        '/results': (context) => const ResultFolderScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/report-bugs': (context) => const ReportBugsScreen(),
        '/privacy-policy': (context) => const PrivacyPolicyScreen(),
      },
    );
  }
}
