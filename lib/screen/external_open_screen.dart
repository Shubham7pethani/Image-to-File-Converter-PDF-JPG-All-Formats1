import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

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
  final PdfViewerController _pdfViewerController = PdfViewerController();
  PdfTextSearchResult? _searchResult;
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _sidebarScrollController = ScrollController();

  Timer? _searchPollTimer;
  int _searchPollGeneration = 0;

  // PDF state
  int _totalPages = 0;
  int _currentPage = 0;
  bool _isReady = false;
  String _errorMessage = '';
  String? _password;
  final TextEditingController _passwordController = TextEditingController();
  bool _isPasswordDialogOpen = false;

  // Sidebar animation state
  bool _showSidebar = false;
  Timer? _sidebarTimer;

  bool _isSearching = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    // Enable ads for external opens (cold starts)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GlobalAdController.showAds.value = true;
    });

    _searchController.addListener(_onSearchTextChanged);
  }

  void _onSearchTextChanged() {
    if (!_showSearch) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _showSearch) {
        _runSearch(_searchController.text);
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _sidebarTimer?.cancel();
    _searchPollTimer?.cancel();
    _sidebarScrollController.dispose();
    _passwordController.dispose();
    _searchResult?.removeListener(_onSearchResultChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchResultChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchPollTimer?.cancel();
        _searchPollTimer = null;
        _searchController.clear();
        _searchResult?.clear();
        _searchResult = null;
      }
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _runSearch(String query) {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchPollTimer?.cancel();
        _searchPollTimer = null;
        _searchResult?.clear();
        _searchResult = null;
      });
      return;
    }

    _searchResult?.removeListener(_onSearchResultChanged);
    final result = _pdfViewerController.searchText(q);
    result.addListener(_onSearchResultChanged);
    setState(() {
      _isSearching = true;
      _searchResult = result;
    });

    _startSearchPolling(result, q);
  }

  void _startSearchPolling(PdfTextSearchResult result, String query) {
    _searchPollTimer?.cancel();

    final gen = ++_searchPollGeneration;
    var elapsedMs = 0;

    _searchPollTimer = Timer.periodic(const Duration(milliseconds: 150), (t) {
      if (!mounted || gen != _searchPollGeneration) {
        t.cancel();
        return;
      }

      elapsedMs += 150;
      final total = result.totalInstanceCount;

      if (total > 0) {
        t.cancel();
        setState(() {
          _isSearching = false;
        });
        _showSnack('Found $total results for "$query"');

        // Auto-jump to first instance
        if (result.currentInstanceIndex == 0) {
          result.nextInstance();
        }
        return;
      }

      if (elapsedMs >= 2000) {
        t.cancel();
        setState(() {
          _isSearching = false;
        });
        _showSnack('No results found for "$query"');
      }
    });
  }

  void _nextMatch() {
    final r = _searchResult;
    if (r == null) return;
    if (r.totalInstanceCount <= 0) return;
    r.nextInstance();
  }

  void _prevMatch() {
    final r = _searchResult;
    if (r == null) return;
    if (r.totalInstanceCount <= 0) return;
    r.previousInstance();
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

  Future<void> _showPasswordDialog({bool isRetry = false}) async {
    if (_isPasswordDialogOpen) return;
    _isPasswordDialogOpen = true;

    final code = Localizations.localeOf(context).languageCode;
    if (!isRetry) _passwordController.clear();

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: ExternalOpenScreen._card,
          title: Text(
            ExternalOpenScreenLanguage.getPasswordRequired(code),
            style: const TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: ExternalOpenScreenLanguage.getEnterPassword(code),
                  hintStyle: const TextStyle(color: Colors.white54),
                  errorText: isRetry
                      ? ExternalOpenScreenLanguage.getInvalidPassword(code)
                      : null,
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: ExternalOpenScreen._gold),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _isPasswordDialogOpen = false;
                Navigator.pop(context);
              },
              child: Text(
                ExternalOpenScreenLanguage.getCancel(code),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                _isPasswordDialogOpen = false;
                setState(() {
                  _password = _passwordController.text;
                  _errorMessage = '';
                  _isReady = false; // Reset ready state to show loading again
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: ExternalOpenScreen._gold,
                foregroundColor: Colors.black,
              ),
              child: Text(ExternalOpenScreenLanguage.getOpen(code)),
            ),
          ],
        ),
      ),
    ).then((_) => _isPasswordDialogOpen = false);
  }

  Future<void> _openNative() async {
    if (widget.path.isEmpty) return;
    await OpenFilex.open(widget.path);
  }

  void _jumpToPage(int page) {
    _pdfViewerController.jumpToPage(page + 1);

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
        bottom: _isSearching
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    ExternalOpenScreen._gold,
                  ),
                  minHeight: 2,
                ),
              )
            : null,
        title: _showSearch && isPdf
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  hintText: 'Search in PDF',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (val) => _runSearch(val),
                onChanged: (val) {
                  // Handled by listener
                },
              )
            : Text(
                isPdf ? name : ExternalOpenScreenLanguage.getOpenFile(code),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
        actions: [
          if (isPdf)
            IconButton(
              onPressed: _toggleSearch,
              icon: Icon(_showSearch ? Icons.close : Icons.search),
              color: ExternalOpenScreen._gold,
            ),
          if (isPdf && _showSearch)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Center(
                child: Text(
                  () {
                    final r = _searchResult;
                    if (r == null) return '';
                    final total = r.totalInstanceCount;
                    if (total <= 0) return '0/0';
                    final current = (r.currentInstanceIndex + 1).clamp(
                      1,
                      total,
                    );
                    return '$current/$total';
                  }(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          if (isPdf && _showSearch)
            IconButton(
              onPressed: _prevMatch,
              icon: const Icon(Icons.keyboard_arrow_up),
              color: ExternalOpenScreen._gold,
            ),
          if (isPdf && _showSearch)
            IconButton(
              onPressed: _nextMatch,
              icon: const Icon(Icons.keyboard_arrow_down),
              color: ExternalOpenScreen._gold,
            ),
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
      return KeyedSubtree(
        key: ValueKey('pdf_view_${_password ?? 'none'}'),
        child: Stack(
          children: [
            SfPdfViewer.file(
              File(path),
              controller: _pdfViewerController,
              password: _password,
              canShowScrollHead: false,
              canShowScrollStatus: false,
              onDocumentLoadFailed: (details) {
                final errStr = details.error.toString();
                debugPrint('PDF Error: $errStr');
                if (details.description.toLowerCase().contains('password') ||
                    errStr.toLowerCase().contains('password')) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _showPasswordDialog(isRetry: _password != null);
                  });
                } else {
                  setState(() {
                    _errorMessage = errStr;
                    _isReady = false;
                  });
                }
              },
              onDocumentLoaded: (details) {
                setState(() {
                  _totalPages = details.document.pages.count;
                  _currentPage = 0;
                  _isReady = true;
                  _errorMessage = '';
                });
              },
              onPageChanged: (details) {
                setState(() {
                  _currentPage = (details.newPageNumber - 1).clamp(0, 1000000);
                });

                _resetSidebarTimer();

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
            ),
            if (!_isReady && _errorMessage.isEmpty)
              const Center(
                child: CircularProgressIndicator(
                  color: ExternalOpenScreen._gold,
                ),
              ),
            if (_errorMessage.isNotEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    ExternalOpenScreenLanguage.getError(code, _errorMessage),
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
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
        ),
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
