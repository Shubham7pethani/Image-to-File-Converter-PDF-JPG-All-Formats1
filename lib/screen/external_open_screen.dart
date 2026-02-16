import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:open_filex/open_filex.dart';

import '../language/external_open_screen_language.dart';
import '../main.dart';
import '../services/branded_share_service.dart';

class ExternalOpenScreen extends StatefulWidget {
  const ExternalOpenScreen({super.key, required this.path});

  final String path;

  static const Color _bg = Color(0xFF1B1E23);
  static const Color _gold = Color(0xFFE2C078);
  static const Color _card = Color(0xFF2B2940);

  @override
  State<ExternalOpenScreen> createState() => _ExternalOpenScreenState();
}

class _ExternalOpenScreenState extends State<ExternalOpenScreen> {
  final BrandedShareService _brandedShareService = const BrandedShareService();
  PDFViewController? _pdfViewController;
  final ScrollController _sidebarScrollController = ScrollController();

  // PDF state
  int _totalPages = 0;
  int _currentPage = 0;
  bool _isReady = false;
  String _errorMessage = '';

  // Sidebar animation state
  bool _showSidebar = false;
  Timer? _sidebarTimer;

  @override
  void initState() {
    super.initState();
    // Enable ads for external opens (cold starts)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GlobalAdController.showAds.value = true;
    });
  }

  @override
  void dispose() {
    _sidebarTimer?.cancel();
    _sidebarScrollController.dispose();
    super.dispose();
  }

  String _fileName(String p) {
    try {
      return File(p).uri.pathSegments.last;
    } catch (_) {
      return p;
    }
  }

  bool _isPdf(String p) {
    return p.toLowerCase().trim().endsWith('.pdf');
  }

  bool _isSupportedImage(String p) {
    final lower = p.toLowerCase().trim();
    if (lower.endsWith('.webp')) return false;
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp');
  }

  IconData _iconForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg'))
      return Icons.image;
    if (lower.endsWith('.gif')) return Icons.gif_box;
    return Icons.insert_drive_file;
  }

  Future<void> _share() async {
    if (widget.path.isEmpty) return;
    await _brandedShareService.shareFile(filePath: widget.path);
  }

  Future<void> _openNative() async {
    if (widget.path.isEmpty) return;
    await OpenFilex.open(widget.path);
  }

  void _jumpToPage(int page) {
    _pdfViewController?.setPage(page);

    // Restart timer when user manually jumps to page
    _resetSidebarTimer();
  }

  void _resetSidebarTimer() {
    setState(() {
      _showSidebar = true;
    });
    _sidebarTimer?.cancel();
    _sidebarTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) {
        setState(() {
          _showSidebar = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.path;
    final name = _fileName(path);
    final isPdf = path.isNotEmpty && _isPdf(path);
    final isImage = path.isNotEmpty && _isSupportedImage(path);
    final exists = path.isNotEmpty && File(path).existsSync();

    final code = Localizations.localeOf(context).languageCode;
    return Scaffold(
      backgroundColor: ExternalOpenScreen._bg,
      appBar: AppBar(
        backgroundColor: ExternalOpenScreen._bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          isPdf ? name : ExternalOpenScreenLanguage.getOpenFile(code),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _share,
            icon: const Icon(Icons.share),
            color: ExternalOpenScreen._gold,
          ),
          if (!isPdf)
            IconButton(
              onPressed: _openNative,
              icon: const Icon(Icons.open_in_new),
              color: ExternalOpenScreen._gold,
            ),
        ],
      ),
      body: _buildBody(exists, isPdf, isImage, path, name),
    );
  }

  Widget _buildBody(
    bool exists,
    bool isPdf,
    bool isImage,
    String path,
    String name,
  ) {
    final code = Localizations.localeOf(context).languageCode;
    if (!exists) {
      return Center(
        child: Text(
          ExternalOpenScreenLanguage.getFileNotFound(code),
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    if (isPdf) {
      return Stack(
        children: [
          PDFView(
            filePath: path,
            autoSpacing: true,
            enableSwipe: true,
            pageSnap: true,
            swipeHorizontal: false,
            nightMode: false,
            onError: (error) {
              setState(() {
                _errorMessage = error.toString();
              });
            },
            onRender: (pages) {
              setState(() {
                _totalPages = pages ?? 0;
                _isReady = true;
              });
            },
            onViewCreated: (controller) {
              _pdfViewController = controller;
            },
            onPageChanged: (page, total) {
              setState(() {
                _currentPage = page ?? 0;
              });

              _resetSidebarTimer();

              // Auto-scroll sidebar to the current page
              if (_sidebarScrollController.hasClients) {
                _sidebarScrollController.animateTo(
                  (_currentPage * 40.0).clamp(
                    0.0,
                    _sidebarScrollController.position.maxScrollExtent,
                  ),
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                );
              }
            },
            onPageError: (page, error) {
              debugPrint('Page $page error: $error');
            },
          ),
          if (!_isReady && _errorMessage.isEmpty)
            const Center(
              child: CircularProgressIndicator(color: ExternalOpenScreen._gold),
            ),
          if (_errorMessage.isNotEmpty)
            Center(
              child: Text(
                ExternalOpenScreenLanguage.getError(code, _errorMessage),
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),

          // FAST SCROLL BAR ON THE RIGHT (WITH AUTO-HIDE ANIMATION)
          if (_isReady && _totalPages > 1)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              right: _showSidebar ? 8 : -60,
              top: 40,
              bottom: 80,
              child: Container(
                width: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: ListView.builder(
                  controller: _sidebarScrollController,
                  itemCount: _totalPages,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (context, index) {
                    final isCurrent = index == _currentPage;
                    return GestureDetector(
                      onTap: () => _jumpToPage(index),
                      child: Container(
                        height: 34,
                        margin: const EdgeInsets.symmetric(
                          vertical: 3,
                          horizontal: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? ExternalOpenScreen._gold
                              : Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: isCurrent ? Colors.black : Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          if (_isReady && _totalPages > 0)
            Positioned(
              bottom: 20,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_currentPage + 1} / $_totalPages',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    if (isImage) {
      return Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Text(
                ExternalOpenScreenLanguage.getCouldNotLoadImage(code),
                style: const TextStyle(color: Colors.white70),
              );
            },
          ),
        ),
      );
    }

    // Default for other files
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_iconForName(name), size: 100, color: ExternalOpenScreen._gold),
          const SizedBox(height: 24),
          Card(
            color: ExternalOpenScreen._card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    path,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _openNative,
              icon: const Icon(Icons.open_in_new),
              label: Text(
                ExternalOpenScreenLanguage.getOpenWithAnotherApp(code),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: ExternalOpenScreen._gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.share),
              label: Text(ExternalOpenScreenLanguage.getShareFile(code)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: ExternalOpenScreen._gold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/home', (route) => false),
            child: Text(
              ExternalOpenScreenLanguage.getGoToHome(code),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}
