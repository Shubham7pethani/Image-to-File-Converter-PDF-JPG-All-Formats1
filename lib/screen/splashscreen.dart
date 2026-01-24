import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? _version;
  String? _patch;
  String? _error;
  bool _isLoading = true;

  final UpdateService _updateService = UpdateService();

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
      final info = await PackageInfo.fromPlatform().timeout(
        const Duration(seconds: 1),
      );
      final versionLabel = 'v${info.version}+${info.buildNumber}';
      final patchLabel = await _updateService.readCurrentPatchLabel();
      if (!mounted) return;
      setState(() {
        _version = versionLabel;
        _patch = patchLabel;
      });

      final decision = await _updateService
          .checkAndMaybeApplyUpdates(
            platformIsAndroid:
                !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
            allowShorebirdDownload: false,
          )
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              return AppUpdateDecision.none;
            },
          );
      if (!mounted) return;

      if (decision.mustUpdateFromStore) {
        final updated = await _tryInAppUpdateOrStore(info.packageName);
        if (!mounted) return;
        if (!updated) {
          setState(() {
            _isLoading = false;
            _error = 'Update required to continue.';
          });
          return;
        }
      }

      if (decision.shorebirdRestartRequired) {
        await _showRestartRequiredDialog();
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        return;
      }

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

  Future<bool> _tryInAppUpdateOrStore(String packageName) async {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    if (isAndroid) {
      final ok = await _showForceUpdateDialog(
        onUpdateNow: () async {
          final started = await _updateService.performImmediateAndroidUpdate();
          if (started) {
            return;
          }
          await _openPlayStore(packageName);
        },
        onExit: () {
          SystemNavigator.pop();
        },
      );

      return ok;
    }

    return _openPlayStore(packageName);
  }

  Future<bool> _openPlayStore(String packageName) async {
    final uri = Uri.parse(
      'https://play.google.com/store/apps/details?id=$packageName',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    return ok;
  }

  Future<bool> _showForceUpdateDialog({
    required Future<void> Function() onUpdateNow,
    required VoidCallback onExit,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Update Required'),
          content: const Text(
            'A newer version is available. Please update to continue.',
          ),
          actions: [
            TextButton(onPressed: onExit, child: const Text('Exit')),
            ElevatedButton(
              onPressed: () async {
                await onUpdateNow();
                if (context.mounted) {
                  Navigator.of(context).pop(true);
                }
              },
              child: const Text('Update Now'),
            ),
          ],
        );
      },
    );
    return result ?? false;
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
                if (_patch != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _patch!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
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
