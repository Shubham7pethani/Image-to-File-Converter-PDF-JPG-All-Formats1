import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfx/pdfx.dart';

import '../services/branded_share_service.dart';

class ExternalOpenScreen extends StatefulWidget {
  const ExternalOpenScreen({super.key, required this.path});

  static const Color _bg = Color(0xFF1B1E23);
  static const Color _card = Color(0xFF2B2940);
  static const Color _gold = Color(0xFFE2C078);

  final String path;

  @override
  State<ExternalOpenScreen> createState() => _ExternalOpenScreenState();
}

class _ExternalOpenScreenState extends State<ExternalOpenScreen> {
  PdfDocument? _pdfDocument;
  int _pagesCount = 0;

  Future<void> _renderQueue = Future<void>.value();

  bool _pdfScrollEnabled = true;

  final TransformationController _imageTransform = TransformationController();

  final Map<int, Future<PdfPageImage>> _pageImages =
      <int, Future<PdfPageImage>>{};
  final Map<int, Future<Size>> _pageSizes = <int, Future<Size>>{};

  final BrandedShareService _brandedShareService = const BrandedShareService();

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
    if (lower.endsWith('.png')) return Icons.image;
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return Icons.image;
    if (lower.endsWith('.webp')) return Icons.image;
    if (lower.endsWith('.gif')) return Icons.gif_box;
    if (lower.endsWith('.bmp')) return Icons.image;
    return Icons.insert_drive_file;
  }

  Future<void> _open() async {
    final path = widget.path;
    if (path.isEmpty) return;
    await OpenFilex.open(path);
  }

  Future<void> _share() async {
    final path = widget.path;
    if (path.isEmpty) return;
    await _brandedShareService.shareFile(filePath: path);
  }

  @override
  void initState() {
    super.initState();

    final path = widget.path;
    if (path.isNotEmpty && _isPdf(path)) {
      unawaited(_openPdf(path));
    }
  }

  Future<void> _openPdf(String path) async {
    try {
      final doc = await PdfDocument.openFile(path);
      if (!mounted) {
        await doc.close();
        return;
      }
      setState(() {
        _pdfDocument = doc;
        _pagesCount = doc.pagesCount;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pdfDocument = null;
        _pagesCount = 0;
      });
    }
  }

  Future<Size> _getPageSize({
    required PdfDocument doc,
    required int pageNumber,
  }) {
    return _pageSizes.putIfAbsent(pageNumber, () async {
      final page = await doc.getPage(pageNumber);
      final size = Size(page.width, page.height);
      await page.close();
      return size;
    });
  }

  Future<PdfPageImage> _renderPageImage({
    required PdfDocument doc,
    required int pageNumber,
    required double targetWidth,
  }) {
    final cached = _pageImages[pageNumber];
    if (cached != null) return cached;

    final future = _enqueueRender<PdfPageImage>(() async {
      PdfPage? page;
      try {
        page = await doc.getPage(pageNumber);

        final ratio = page.height / page.width;

        Future<PdfPageImage?> tryRender({
          required double width,
          required PdfPageImageFormat format,
          String? backgroundColor,
          int quality = 85,
          bool forPrint = false,
        }) {
          final widthPx = width.floorToDouble().clamp(1, 800).toDouble();
          final heightPx = (widthPx * ratio)
              .floorToDouble()
              .clamp(1, 1400)
              .toDouble();
          return page!.render(
            width: widthPx,
            height: heightPx,
            format: format,
            backgroundColor: backgroundColor,
            quality: quality,
            forPrint: forPrint,
          );
        }

        // Attempt 1: JPEG, normal render
        PdfPageImage? image = await tryRender(
          width: (targetWidth * 0.85).clamp(200.0, 650.0),
          format: PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
          quality: 75,
          forPrint: true,
        );

        // Attempt 2: Smaller JPEG
        image ??= await tryRender(
          width: (targetWidth * 0.60).clamp(180.0, 520.0),
          format: PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
          quality: 70,
        );

        // Attempt 3: PNG + forPrint (some PDFs render better)
        image ??= await tryRender(
          width: (targetWidth * 0.55).clamp(170.0, 480.0),
          format: PdfPageImageFormat.png,
          backgroundColor: null,
          forPrint: true,
        );

        if (image == null) {
          throw StateError('Failed to render PDF page');
        }
        return image;
      } catch (e, st) {
        debugPrint('PDF render failed page=$pageNumber: $e');
        debugPrint('$st');
        rethrow;
      } finally {
        if (page != null) {
          await page.close();
        }
      }
    });

    _pageImages[pageNumber] = future;
    // If it fails, remove from cache so scrolling can retry.
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {
          _pageImages.remove(pageNumber);
        },
      ),
    );
    return future;
  }

  Future<T> _enqueueRender<T>(Future<T> Function() job) {
    final run = _renderQueue.catchError((_) {}).then((_) => job());
    _renderQueue = run.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return run;
  }

  void _invalidatePageImage(int pageNumber) {
    _pageImages.remove(pageNumber);
  }

  void _setPdfScrollEnabled(bool enabled) {
    if (_pdfScrollEnabled == enabled) return;
    setState(() {
      _pdfScrollEnabled = enabled;
    });
  }

  @override
  void dispose() {
    final doc = _pdfDocument;
    _pdfDocument = null;
    if (doc != null) {
      unawaited(doc.close());
    }
    _imageTransform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.path;
    final name = _fileName(path);
    final isPdf = path.isNotEmpty && _isPdf(path);
    final isImage = path.isNotEmpty && _isSupportedImage(path);
    final exists = path.isNotEmpty && File(path).existsSync();
    final doc = _pdfDocument;

    return Scaffold(
      backgroundColor: ExternalOpenScreen._bg,
      appBar: AppBar(
        backgroundColor: ExternalOpenScreen._bg,
        foregroundColor: Colors.white,
        title: Text(isPdf ? name : 'Open File'),
        actions: [
          IconButton(
            onPressed: _share,
            icon: const Icon(Icons.share),
            color: ExternalOpenScreen._gold,
          ),
          if (!isPdf)
            IconButton(
              onPressed: _open,
              icon: const Icon(Icons.open_in_new),
              color: ExternalOpenScreen._gold,
            ),
        ],
      ),
      body: isPdf
          ? (!exists
                ? const Center(
                    child: Text(
                      'File not found.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : (doc == null
                      ? const Center(
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : ListView.builder(
                          physics: _pdfScrollEnabled
                              ? const ClampingScrollPhysics()
                              : const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                          itemCount: _pagesCount + 1,
                          itemBuilder: (context, index) {
                            if (index >= _pagesCount) {
                              return Container(
                                height: 240,
                                margin: const EdgeInsets.only(top: 16),
                                decoration: BoxDecoration(
                                  color: ExternalOpenScreen._card,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: const _ExternalNativeAdBox(),
                              );
                            }

                            final pageNumber = index + 1;
                            return _PdfPageTile(
                              doc: doc,
                              path: path,
                              pageNumber: pageNumber,
                              getPageSize: _getPageSize,
                              renderPageImage: _renderPageImage,
                              invalidatePageImage: _invalidatePageImage,
                              setScrollEnabled: _setPdfScrollEnabled,
                            );
                          },
                        )))
          : (isImage
                ? (!exists
                      ? const Center(
                          child: Text(
                            'File not found.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : GestureDetector(
                          onDoubleTap: () {
                            _imageTransform.value = Matrix4.identity();
                          },
                          child: Center(
                            child: InteractiveViewer(
                              transformationController: _imageTransform,
                              minScale: 1.0,
                              maxScale: 4.0,
                              clipBehavior: Clip.none,
                              child: Image.file(
                                File(path),
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.low,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Text(
                                    'Failed to open image.',
                                    style: TextStyle(color: Colors.white70),
                                  );
                                },
                              ),
                            ),
                          ),
                        ))
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Card(
                          color: ExternalOpenScreen._card,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: Color(0x38E2C078)),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 0,
                            ),
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            minVerticalPadding: 0,
                            minLeadingWidth: 48,
                            horizontalTitleGap: 12,
                            titleAlignment: ListTileTitleAlignment.center,
                            leading: SizedBox(
                              width: 42,
                              height: 42,
                              child: Center(
                                child: Transform.translate(
                                  offset: const Offset(0, 2),
                                  child: Icon(
                                    _iconForName(name),
                                    color: ExternalOpenScreen._gold,
                                    size: 32,
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              path.isEmpty ? 'No file received.' : path,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: ExternalOpenScreen._gold,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () async {
                                  await _open();
                                },
                                icon: const Icon(Icons.open_in_new, size: 18),
                                label: const Text(
                                  'Open',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                    color: Color(0x38E2C078),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () async {
                                  await _share();
                                },
                                icon: const Icon(Icons.share, size: 18),
                                label: const Text(
                                  'Share',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white70,
                            ),
                            onPressed: () {
                              Navigator.of(context).pushNamedAndRemoveUntil(
                                '/home',
                                (route) => false,
                              );
                            },
                            child: const Text('Go to Home'),
                          ),
                        ),
                      ],
                    ),
                  )),
    );
  }
}

class _PdfPageTile extends StatefulWidget {
  const _PdfPageTile({
    required this.doc,
    required this.path,
    required this.pageNumber,
    required this.getPageSize,
    required this.renderPageImage,
    required this.invalidatePageImage,
    required this.setScrollEnabled,
  });

  final PdfDocument doc;
  final String path;
  final int pageNumber;

  final Future<Size> Function({
    required PdfDocument doc,
    required int pageNumber,
  })
  getPageSize;
  final Future<PdfPageImage> Function({
    required PdfDocument doc,
    required int pageNumber,
    required double targetWidth,
  })
  renderPageImage;

  final void Function(int pageNumber) invalidatePageImage;

  final void Function(bool enabled) setScrollEnabled;

  @override
  State<_PdfPageTile> createState() => _PdfPageTileState();
}

class _PdfPageTileState extends State<_PdfPageTile> {
  int _autoRetries = 0;
  final TransformationController _transform = TransformationController();

  double get _currentScale => _transform.value.getMaxScaleOnAxis();

  void _resetZoom() {
    _transform.value = Matrix4.identity();
    widget.setScrollEnabled(true);
  }

  void _onInteractionStart(ScaleStartDetails _) {
    widget.setScrollEnabled(false);
  }

  void _onInteractionEnd(ScaleEndDetails _) {
    final scale = _currentScale;
    widget.setScrollEnabled(scale <= 1.01);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rawTargetWidth = constraints.maxWidth * dpr;
          final targetWidth = rawTargetWidth.clamp(200.0, 650.0);
          return FutureBuilder<Size>(
            future: widget.getPageSize(
              doc: widget.doc,
              pageNumber: widget.pageNumber,
            ),
            builder: (context, snap) {
              final size = snap.data;
              final aspect = (size == null || size.width == 0)
                  ? 1.414
                  : (size.height / size.width);
              final logicalHeight = constraints.maxWidth * aspect;

              final imageFuture = widget.renderPageImage(
                doc: widget.doc,
                pageNumber: widget.pageNumber,
                targetWidth: targetWidth,
              );

              return Stack(
                children: [
                  SizedBox(
                    width: constraints.maxWidth,
                    height: logicalHeight,
                    child: FutureBuilder<PdfPageImage>(
                      future: imageFuture,
                      builder: (context, imgSnap) {
                        final image = imgSnap.data;
                        if (image != null) {
                          return GestureDetector(
                            onDoubleTap: _resetZoom,
                            child: InteractiveViewer(
                              transformationController: _transform,
                              minScale: 1.0,
                              maxScale: 4.0,
                              clipBehavior: Clip.none,
                              onInteractionStart: _onInteractionStart,
                              onInteractionEnd: _onInteractionEnd,
                              child: Image.memory(
                                image.bytes,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.low,
                                gaplessPlayback: true,
                              ),
                            ),
                          );
                        }

                        if (imgSnap.hasError) {
                          if (_autoRetries < 1) {
                            _autoRetries++;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              widget.invalidatePageImage(widget.pageNumber);
                              setState(() {});
                            });
                            return const Center(
                              child: SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }

                          final raw = imgSnap.error.toString();
                          final msg = raw.length > 120
                              ? raw.substring(0, 120)
                              : raw;
                          String diag = '';
                          try {
                            final f = File(widget.path);
                            final len = f.lengthSync();
                            final raf = f.openSync(mode: FileMode.read);
                            final headerBuf = <int>[0, 0, 0, 0, 0, 0, 0, 0];
                            final read = raf.readIntoSync(headerBuf, 0, 8);
                            raf.closeSync();

                            final header = read >= 4
                                ? String.fromCharCodes(headerBuf.take(4))
                                : '';
                            diag = 'size=$len, header=$header';
                          } catch (_) {
                            diag = '';
                          }
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Failed to render page',
                                  style: TextStyle(
                                    color: Colors.black54,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  msg,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.black38,
                                    fontSize: 11,
                                  ),
                                ),
                                if (diag.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    diag,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.black38,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        widget.invalidatePageImage(
                                          widget.pageNumber,
                                        );
                                        setState(() {
                                          _autoRetries = 0;
                                        });
                                      },
                                      icon: const Icon(Icons.refresh, size: 16),
                                      label: const Text('Retry'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () async {
                                        await OpenFilex.open(widget.path);
                                      },
                                      icon: const Icon(
                                        Icons.open_in_new,
                                        size: 16,
                                      ),
                                      label: const Text('Open'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }

                        return const Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Color(0x99000000),
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          '${widget.pageNumber}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ExternalNativeAdBox extends StatefulWidget {
  const _ExternalNativeAdBox();

  @override
  State<_ExternalNativeAdBox> createState() => _ExternalNativeAdBoxState();
}

class _ExternalNativeAdBoxState extends State<_ExternalNativeAdBox> {
  static const String _testNativeAdUnitId =
      'ca-app-pub-3940256099942544/2247696110';

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

  void _loadAd() {
    if (_loadingAd) return;
    if (!_hasConnection) return;
    if (_ad != null) return;

    _loadingAd = true;
    final ad = NativeAd(
      adUnitId: _testNativeAdUnitId,
      factoryId: 'homeNative',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _ad = ad as NativeAd;
            _loaded = true;
            _loadingAd = false;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _ad = null;
            _loaded = false;
            _loadingAd = false;
          });
          _scheduleRetry();
        },
      ),
    );

    ad.load();
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
    final ad = _ad;
    if (ad != null && _loaded) {
      return AdWidget(ad: ad);
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
