import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? _version;
  String? _error;
  bool _isLoading = true;

  static const Color _bgColor = Color(0xFF4B2C83);

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final info = await PackageInfo.fromPlatform();
      _version = 'v${info.version}+${info.buildNumber}';

      final allowed = await _requestPermissions();
      if (!mounted) return;

      if (!allowed) {
        setState(() {
          _isLoading = false;
          _error = 'Permission required to continue.';
        });
        return;
      }

      Navigator.of(context).pushReplacementNamed('/home');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  Future<bool> _requestPermissions() async {
    if (kIsWeb) {
      return true;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final camera = await Permission.camera.request();
      final photos = await Permission.photos.request();
      final storage = await Permission.storage.request();
      return camera.isGranted && (photos.isGranted || storage.isGranted);
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final camera = await Permission.camera.request();
      final photos = await Permission.photos.request();
      final addOnly = await Permission.photosAddOnly.request();
      return camera.isGranted &&
          ((photos.isGranted || photos.isLimited) || addOnly.isGranted);
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/logo.png', width: 280, fit: BoxFit.contain),
                const SizedBox(height: 32),
                if (_version != null)
                  Text(
                    _version!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                const SizedBox(height: 18),
                if (_isLoading)
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                if (!_isLoading && _error != null) ...[
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _start,
                        child: const Text('Try Again'),
                      ),
                      OutlinedButton(
                        onPressed: openAppSettings,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                        ),
                        child: const Text('Open Settings'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
