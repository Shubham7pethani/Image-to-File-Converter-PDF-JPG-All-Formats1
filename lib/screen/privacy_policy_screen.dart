import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../language/privacy_policy_screen_language.dart';

class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  static const Color bg = Color(0xFF1B1E23);
  static const Color card = Color(0xFF2B2940);
  static const Color gold = Color(0xFFE2C078);

  static const String assetPath = 'assets/privacy_policy/index.html';

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  String? _lastError;

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(PrivacyPolicyScreen.bg)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = request.url;
            if (url.startsWith('mailto:')) {
              _openExternalUrl(url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onProgress: (p) {
            if (!mounted) return;
            setState(() {
              _progress = p.clamp(0, 100);
            });
          },
          onWebResourceError: (e) {
            if (!mounted) return;
            setState(() {
              _lastError = e.description;
            });
          },
        ),
      )
      ..loadFlutterAsset(PrivacyPolicyScreen.assetPath);
  }

  @override
  Widget build(BuildContext context) {
    final showProgress = _progress < 100;
    final code = Localizations.localeOf(context).languageCode;

    return Scaffold(
      backgroundColor: PrivacyPolicyScreen.bg,
      appBar: AppBar(
        backgroundColor: PrivacyPolicyScreen.bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          PrivacyPolicyScreenLanguage.getPrivacyPolicy(code),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: PrivacyPolicyScreenLanguage.getReload(code),
            onPressed: () {
              setState(() {
                _progress = 0;
                _lastError = null;
              });
              _controller.reload();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: showProgress
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: _progress / 100.0,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    PrivacyPolicyScreen.gold,
                  ),
                ),
              )
            : null,
      ),
      body: _lastError == null
          ? WebViewWidget(controller: _controller)
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: PrivacyPolicyScreen.card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0x38E2C078)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          PrivacyPolicyScreenLanguage.getUnableToLoad(code),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _lastError ?? 'Unknown error',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: PrivacyPolicyScreen.gold,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              _progress = 0;
                              _lastError = null;
                            });
                            _controller.reload();
                          },
                          icon: const Icon(Icons.refresh),
                          label: Text(
                            PrivacyPolicyScreenLanguage.getTryAgain(code),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
