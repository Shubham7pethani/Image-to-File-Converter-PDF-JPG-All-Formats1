import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/update_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static const Color _bg = Color(0xFF1B1E23);
  static const Color _card = Color(0xFF2B2940);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final UpdateService _updateService = UpdateService();

  @override
  void initState() {
    super.initState();
    unawaited(_checkForShorebirdPatch());
  }

  Future<void> _checkForShorebirdPatch() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    final decision = await _updateService.checkAndMaybeApplyUpdates(
      platformIsAndroid:
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      allowShorebirdDownload: true,
    );
    if (!mounted) return;

    if (decision.shorebirdRestartRequired) {
      await _showRestartRequiredDialog();
    }
  }

  Future<void> _showRestartRequiredDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Update Ready'),
          content: const Text(
            'A new update has been downloaded. Please restart the app to apply it.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                if (!kIsWeb &&
                    defaultTargetPlatform == TargetPlatform.android) {
                  SystemNavigator.pop();
                  exit(0);
                }
                SystemNavigator.pop();
              },
              child: const Text('Restart'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeScreen._bg,
      appBar: AppBar(
        backgroundColor: HomeScreen._bg,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/onlylogo.png', fit: BoxFit.contain),
        ),
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Image to File Converter',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).pushNamed('/star-imp'),
            icon: const Icon(Icons.workspace_premium_outlined),
            color: const Color(0xFFE2C078),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
            icon: const Icon(Icons.settings_outlined),
            color: Colors.white,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        children: [
          _FeatureCard(
            background: HomeScreen._card,
            icon: Icons.image_rounded,
            title: 'Single Image',
            subtitle: 'Convert, Compress, Resize, Crop, Create PDF',
            onTap: () => Navigator.of(context).pushNamed('/single'),
          ),
          const SizedBox(height: 16),
          _FeatureCard(
            background: HomeScreen._card,
            icon: Icons.collections_rounded,
            title: 'Multiple Images',
            subtitle: 'Convert, Compress, Resize, Crop, Create PDF',
            onTap: () => Navigator.of(context).pushNamed('/multiple'),
          ),
          const SizedBox(height: 16),
          _FeatureCard(
            background: HomeScreen._card,
            icon: Icons.picture_as_pdf_rounded,
            title: 'Create PDF',
            subtitle: 'Select multiple images and build a PDF with pages',
            onTap: () => Navigator.of(context).pushNamed('/create-pdf'),
          ),
          const SizedBox(height: 16),
          _FeatureCard(
            background: HomeScreen._card,
            icon: Icons.folder_rounded,
            title: 'Result Folder',
            subtitle: 'View & manage all saved images and PDFs',
            onTap: () => Navigator.of(context).pushNamed('/results'),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = (w * 0.82).clamp(290.0, 380.0);
              return Container(
                height: h,
                decoration: BoxDecoration(
                  color: HomeScreen._card,
                  borderRadius: BorderRadius.circular(18),
                ),
                clipBehavior: Clip.antiAlias,
                child: const _HomeNativeAdBox(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HomeNativeAdBox extends StatefulWidget {
  const _HomeNativeAdBox();

  @override
  State<_HomeNativeAdBox> createState() => _HomeNativeAdBoxState();
}

class _HomeNativeAdBoxState extends State<_HomeNativeAdBox>
    with WidgetsBindingObserver {
  static const String _testNativeAdUnitId =
      'ca-app-pub-3645213065759243/6086262009';

  NativeAd? _ad;
  bool _loaded = false;

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _hasConnection = true;
  bool _loadingAd = false;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initConnectivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _stopRefreshTimer();
    } else if (state == AppLifecycleState.resumed) {
      _startRefreshTimer();
    }
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
        debugPrint('Connectivity Lost: Keeping current ad if exists.');
        _retryTimer?.cancel();
        _retryTimer = null;
        _stopRefreshTimer();
        setState(() {
          _hasConnection = false;
        });
        return;
      }

      final wasConnected = _hasConnection;
      setState(() {
        _hasConnection = true;
      });

      if (!wasConnected && _ad == null) {
        _loadAd();
      }
    });
  }

  void _disposeAd() {
    _ad?.dispose();
    _ad = null;
    _loaded = false;
    _loadingAd = false;
  }

  Timer? _refreshTimer;

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    if (!_hasConnection) return;
    // Increased to 90s for better stability with AdMob
    _refreshTimer = Timer.periodic(const Duration(seconds: 90), (timer) {
      _loadAd(force: true);
    });
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _scheduleRetry() {
    if (!_hasConnection) return;
    if (_retryTimer != null) return;
    _retryTimer = Timer(const Duration(seconds: 5), () {
      _retryTimer = null;
      if (!mounted) return;
      if (_ad == null && _hasConnection) {
        _loadAd();
      }
    });
  }

  void _loadAd({bool force = false}) {
    if (_loadingAd) return;
    if (!_hasConnection) return;
    if (_ad != null && !force) return;

    _loadingAd = true;
    final ad = NativeAd(
      adUnitId: _testNativeAdUnitId,
      factoryId: 'homeNative',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          debugPrint('Native Ad Loaded: ${ad.adUnitId}');
          if (!mounted) {
            ad.dispose();
            return;
          }
          final oldAd = _ad;
          setState(() {
            _ad = ad as NativeAd;
            _loaded = true;
            _loadingAd = false;
          });

          // Delay disposal of the old ad significantly to ensure the new one is fully rendered
          if (oldAd != null && oldAd != ad) {
            Future.delayed(const Duration(seconds: 15), () {
              if (mounted) {
                oldAd.dispose();
                debugPrint('Old Native Ad Disposed after 15s delay');
              }
            });
          }
          _startRefreshTimer();
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint(
            'Native Ad Failed to Load: ${error.message} (Code: ${error.code})',
          );
          if (error.code == 3) {
            debugPrint(
              'TIP: No Fill error (Code 3) usually means you need to add your test device ID or wait for AdMob to serve ads.',
            );
          }
          ad.dispose();
          if (!mounted) return;

          setState(() {
            _loadingAd = false;
          });

          if (_ad == null) {
            _scheduleRetry();
          }
        },
      ),
    );

    ad.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopRefreshTimer();
    _retryTimer?.cancel();
    _retryTimer = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _disposeAd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad != null && _loaded) {
      return SizedBox.expand(
        child: AdWidget(key: ValueKey(ad.hashCode), ad: ad),
      );
    }

    return const Center(
      child: SizedBox(
        width: 56,
        height: 56,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFFE2C078),
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          child: Center(
            child: Text(
              'Ad',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF5D28B), Color(0xFFE2C078), Color(0xFFB8903C)],
        ),
      ),
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF1F1D2F),
        ),
        child: Icon(icon, color: Color(0xFFE2C078), size: 26),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.background,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Color background;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      elevation: 1,
      shadowColor: const Color(0x22000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0x38E2C078)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              _IconBadge(icon: icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFFD4CCB7),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
