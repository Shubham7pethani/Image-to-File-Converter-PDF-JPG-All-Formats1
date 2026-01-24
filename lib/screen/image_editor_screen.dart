import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'crop_image_screen.dart';
import '../services/app_settings.dart';
import '../services/image_processing_service.dart';
import '../services/gallery_save_service.dart';
import '../services/multipleimagelogic.dart';
import '../services/models.dart';
import '../services/output_storage_service.dart';
import '../services/pdf_export_service.dart';

List<int> _decodeImageSize(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return const [0, 0];
    return <int>[decoded.width, decoded.height];
  } catch (_) {
    return const [0, 0];
  }
}

class ImageEditorScreen extends StatefulWidget {
  const ImageEditorScreen({super.key, required this.images});

  final List<SelectedImage> images;

  static const Color bg = Color(0xFF1B1E23);
  static const Color card = Color(0xFF2B2940);
  static const Color gold = Color(0xFFE2C078);

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  final ImageProcessingService _imageProcessingService =
      const ImageProcessingService();
  final OutputStorageService _outputStorageService =
      const OutputStorageService();
  final GallerySaveService _gallerySaveService = const GallerySaveService();
  final AppSettings _settings = const AppSettings();

  final ScrollController _scrollController = ScrollController();
  late final PdfExportService _pdfExportService = PdfExportService(
    imageProcessingService: _imageProcessingService,
  );

  late List<SelectedImage> _images;
  int _activeIndex = 0;
  OutputFormat _activeInputFormat = OutputFormat.jpg;
  bool _cropped = false;

  late final bool _isMultiSession;
  MultipleImageLogic? _multiLogic;

  bool _compressEnabled = true;
  bool _resizeEnabled = false;
  bool _keepExif = false;

  double _quality = 80;

  final Map<int, _FormatChoice> _formatByIndex = <int, _FormatChoice>{};

  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();

  final Map<int, _ResizeDims> _dimsByIndex = <int, _ResizeDims>{};

  Uint8List? _afterBytes;
  Uint8List? _afterSaveBytes;
  OutputFormat? _afterSaveFormat;
  int? _afterSaveIndex;
  int? _afterWidth;
  int? _afterHeight;
  final Map<int, _PreviewOut> _previewByIndex = <int, _PreviewOut>{};
  bool _isPreviewLoading = false;
  String? _previewError;
  bool _previewDirty = true;
  bool _isSaving = false;

  bool _photoSpeedUp = false;

  _EditorStage _stage = _EditorStage.edit;

  int _previewRequestId = 0;
  bool _previewInFlight = false;

  int? _beforeWidth;
  int? _beforeHeight;

  SelectedImage get _activeImage =>
      _images[_activeIndex.clamp(0, _images.length - 1)];

  bool get _isMulti => _isMultiSession;

  MultiImageItemState? get _activeMultiState {
    if (!_isMultiSession) return null;
    final idx = _activeIndex;
    if (idx < 0 || idx >= (_multiLogic?.states.length ?? 0)) return null;
    return _multiLogic!.states[idx];
  }

  OutputFormat _effectiveFormatForIndex(int index) {
    if (_isMultiSession) {
      return _multiLogic?.effectiveFormatForIndex(index) ?? OutputFormat.jpg;
    }
    final imgItem = _images[index];
    final choice = _formatByIndex[index];
    if (choice == null || choice.useSameAsInput) {
      return _detectInputFormat(imgItem.name);
    }
    return choice.format;
  }

  Future<_PreviewOut> _buildPreviewOnly() async {
    if (_beforeWidth == null || _beforeHeight == null) {
      await _loadActiveImageMeta();
    }

    final index = _activeIndex;
    final image = _images[index];
    final effectiveFormat = _effectiveFormatForIndex(index);

    final previewFormat = effectiveFormat == OutputFormat.pdf
        ? OutputFormat.jpg
        : effectiveFormat;

    final preview = await _imageProcessingService.processForPreview(
      input: image,
      options: _previewOptionsForCurrentState(format: previewFormat),
    );

    final options = _optionsForIndex(index: index, format: effectiveFormat);
    final w =
        (options.resizeEnabled ? options.resizeWidth : null) ?? _beforeWidth;
    final h =
        (options.resizeEnabled ? options.resizeHeight : null) ?? _beforeHeight;

    return _PreviewOut(
      bytes: preview.bytes,
      saveBytes: null,
      saveFormat: effectiveFormat,
      width: w,
      height: h,
    );
  }

  Future<Uint8List> _encodeFinalImageBytes({
    required SelectedImage image,
    required ImageProcessOptions options,
    required bool canPreserveExif,
  }) async {
    if (canPreserveExif) {
      final exifBytes = await _imageProcessingService
          .encodeFromSourceBytesPreservingExif(
            sourceBytes: image.bytes,
            options: options,
          );
      if (exifBytes != null) {
        return exifBytes;
      }
    }

    return _imageProcessingService.encodeFromSourceBytes(
      sourceBytes: image.bytes,
      options: options,
    );
  }

  @override
  void initState() {
    super.initState();
    _isMultiSession = widget.images.length > 1;
    if (_isMultiSession) {
      _multiLogic = MultipleImageLogic(images: widget.images);
      _images = _multiLogic!.images;
    } else {
      _images = List<SelectedImage>.from(widget.images);
    }
    _init();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    final speedUp = await _settings.getPhotoSpeedUp();
    if (!mounted) return;
    if (_photoSpeedUp == speedUp) return;
    setState(() {
      _photoSpeedUp = speedUp;
    });
    _markPreviewDirty();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _init() {
    _activeIndex = 0;
    _activeInputFormat = _detectInputFormat(_images.first.name);

    _formatByIndex.clear();
    if (!_isMultiSession) {
      for (var i = 0; i < _images.length; i++) {
        _formatByIndex[i] = _FormatChoice(
          useSameAsInput: true,
          format: _detectInputFormat(_images[i].name),
        );
      }
    }

    _dimsByIndex.clear();

    _beforeWidth = null;
    _beforeHeight = null;
    unawaited(_loadActiveImageMeta());

    _widthController.text = '';
    _heightController.text = '';

    _afterBytes = null;
    _afterSaveBytes = null;
    _afterSaveFormat = null;
    _afterSaveIndex = null;
    _afterWidth = null;
    _afterHeight = null;
    _previewByIndex.clear();
    _previewError = null;
    _previewDirty = true;
    _stage = _EditorStage.edit;
  }

  Future<void> _loadActiveImageMeta() async {
    final index = _activeIndex;
    final bytes = _activeImage.bytes;
    final wh = await compute(_decodeImageSize, bytes);
    if (!mounted) return;
    if (index != _activeIndex) return;

    final w = wh[0];
    final h = wh[1];
    setState(() {
      _beforeWidth = w > 0 ? w : null;
      _beforeHeight = h > 0 ? h : null;
    });

    _applyDimsForIndex(index: _activeIndex);
  }

  void _markPreviewDirty() {
    setState(() {
      _previewDirty = true;
      _afterBytes = null;
      _afterSaveBytes = null;
      _afterSaveFormat = null;
      _afterSaveIndex = null;
      _afterWidth = null;
      _afterHeight = null;
      _previewByIndex.remove(_activeIndex);
      _previewError = null;
      if (_stage != _EditorStage.edit) {
        _stage = _EditorStage.edit;
      }
    });
  }

  void _goToPreviewStage() {
    if (!mounted) return;
    setState(() {
      _stage = _EditorStage.previewOne;
    });
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _goToEditStage() {
    if (!mounted) return;
    setState(() {
      _stage = _EditorStage.edit;
    });
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _onSaveAll() async {
    if (!_isMultiSession) return;
    if (_isSaving) return;
    if (_images.isEmpty) return;

    setState(() {
      _isSaving = true;
    });

    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    try {
      final baseStamp = _timestamp();
      for (var i = 0; i < _images.length; i++) {
        final effectiveFormat = _effectiveFormatForIndex(i);
        if (effectiveFormat == OutputFormat.pdf) {
          throw StateError('PDF is available for single image only.');
        }

        final options = _optionsForIndex(index: i, format: effectiveFormat);
        final bytes = await _encodeFinalImageBytes(
          image: _images[i],
          options: options,
          canPreserveExif:
              options.keepExif &&
              !_cropped &&
              effectiveFormat != OutputFormat.pdf,
        );

        final label = _formatLabel(effectiveFormat);
        final ext = _formatExt(effectiveFormat);
        final fileName = '${label}_${baseStamp}_${i + 1}.$ext';

        await _outputStorageService.saveBytes(fileName: fileName, bytes: bytes);
        await _gallerySaveService.saveImage(bytes: bytes, name: fileName);
      }

      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/results', (route) => route.isFirst);
    } catch (e, st) {
      debugPrint('Save all failed: $e');
      debugPrint('$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to save: ${e.toString().length > 120 ? e.toString().substring(0, 120) : e.toString()}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _saveActiveImage() async {
    final index = _activeIndex;
    final image = _images[index];
    final effectiveFormat = _effectiveFormatForIndex(index);

    final cachedBytes =
        (_afterSaveIndex == index && _afterSaveFormat == effectiveFormat)
        ? _afterSaveBytes
        : null;

    if (_images.length > 1 && effectiveFormat == OutputFormat.pdf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF is available for single image only.'),
        ),
      );
      return;
    }

    final options = _optionsForIndex(index: index, format: effectiveFormat);
    final canPreserveExif =
        options.keepExif && !_cropped && effectiveFormat != OutputFormat.pdf;

    if (effectiveFormat == OutputFormat.pdf) {
      final pdfBytes =
          cachedBytes ??
          await _pdfExportService.buildPdf(images: [image], options: options);

      final stamp = _timestamp();
      final fileName = 'PDF_$stamp.pdf';
      final saved = await _outputStorageService.saveBytes(
        fileName: fileName,
        bytes: pdfBytes,
      );

      final ok = await _gallerySaveService.saveFile(filePath: saved.path);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'PDF saved in Result Folder. Gallery save supports images only.',
            ),
          ),
        );
      }
      return;
    }

    final bytes =
        cachedBytes ??
        await _encodeFinalImageBytes(
          image: image,
          options: options,
          canPreserveExif: canPreserveExif,
        );

    final stamp = _timestamp();
    final label = _formatLabel(effectiveFormat);
    final ext = _formatExt(effectiveFormat);
    final suffix = _images.length == 1 ? '' : '_${index + 1}';
    final fileName = '${label}_$stamp$suffix.$ext';

    await _outputStorageService.saveBytes(fileName: fileName, bytes: bytes);

    final ok = await _gallerySaveService.saveImage(
      bytes: bytes,
      name: fileName,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved, but failed to add to gallery.')),
      );
    }
  }

  Future<void> _saveAllImages() async {
    final baseStamp = _timestamp();
    for (var i = 0; i < _images.length; i++) {
      final out = _previewByIndex[i];
      if (out == null) {
        throw StateError('Missing preview for image ${i + 1}');
      }

      if (out.saveFormat == OutputFormat.pdf) {
        throw StateError('PDF is available for single image only.');
      }

      final bytesToSave =
          out.saveBytes ??
          await _encodeFinalImageBytes(
            image: _images[i],
            options: _optionsForIndex(index: i, format: out.saveFormat),
            canPreserveExif:
                _optionsForIndex(index: i, format: out.saveFormat).keepExif &&
                !_cropped,
          );

      final label = _formatLabel(out.saveFormat);
      final ext = _formatExt(out.saveFormat);
      final fileName = '${label}_${baseStamp}_${i + 1}.$ext';

      await _outputStorageService.saveBytes(
        fileName: fileName,
        bytes: bytesToSave,
      );
      await _gallerySaveService.saveImage(bytes: bytesToSave, name: fileName);
    }
  }

  void _saveActiveDimsFromControllers() {
    final w = _tryParseDim(_widthController.text);
    final h = _tryParseDim(_heightController.text);
    if (w == null || h == null) return;
    if (_isMultiSession) {
      final st = _activeMultiState;
      if (st == null) return;
      st.resizeWidth = w;
      st.resizeHeight = h;
      return;
    }
    _dimsByIndex[_activeIndex] = _ResizeDims(width: w, height: h);
  }

  void _applyDimsForIndex({required int index}) {
    if (_isMultiSession) {
      final st = (index >= 0 && index < (_multiLogic?.states.length ?? 0))
          ? _multiLogic!.states[index]
          : null;
      if (st != null && st.resizeWidth != null && st.resizeHeight != null) {
        _widthController.text = st.resizeWidth.toString();
        _heightController.text = st.resizeHeight.toString();
        return;
      }
    } else {
      final existing = _dimsByIndex[index];
      if (existing != null) {
        _widthController.text = existing.width.toString();
        _heightController.text = existing.height.toString();
        return;
      }
    }

    final w = _beforeWidth;
    final h = _beforeHeight;
    if (w == null || h == null) return;

    if (_isMultiSession) {
      final st = (index >= 0 && index < (_multiLogic?.states.length ?? 0))
          ? _multiLogic!.states[index]
          : null;
      if (st != null) {
        st.resizeWidth = w;
        st.resizeHeight = h;
      }
      _widthController.text = w.toString();
      _heightController.text = h.toString();
      return;
    }

    _dimsByIndex[index] = _ResizeDims(width: w, height: h);
    _widthController.text = w.toString();
    _heightController.text = h.toString();
  }

  OutputFormat _detectInputFormat(String name) {
    final dotIndex = name.lastIndexOf('.');
    final ext = dotIndex > 0 ? name.substring(dotIndex + 1).toLowerCase() : '';

    switch (ext) {
      case 'jpg':
        return OutputFormat.jpg;
      case 'jpeg':
        return OutputFormat.jpeg;
      case 'png':
        return OutputFormat.png;
      case 'webp':
        return OutputFormat.webp;
      case 'gif':
        return OutputFormat.gif;
      case 'bmp':
        return OutputFormat.bmp;
      case 'pdf':
        return OutputFormat.pdf;
      default:
        return OutputFormat.jpg;
    }
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}_${three(now.millisecond)}';
  }

  bool _isJpegFamily(OutputFormat f) {
    return f == OutputFormat.jpg || f == OutputFormat.jpeg;
  }

  bool _isSameFamily(OutputFormat a, OutputFormat b) {
    if (_isJpegFamily(a) && _isJpegFamily(b)) return true;
    return a == b;
  }

  ImageProcessOptions _previewOptionsForCurrentState({
    required OutputFormat format,
  }) {
    final base = _optionsForCurrentState(format: format);
    final w = _beforeWidth;
    final h = _beforeHeight;
    if (w == null || h == null) return base;

    final maxSide = _photoSpeedUp ? 900 : 1400;
    final currentW = base.resizeEnabled && base.resizeWidth != null
        ? base.resizeWidth!
        : w;
    final currentH = base.resizeEnabled && base.resizeHeight != null
        ? base.resizeHeight!
        : h;

    final maxCurrent = currentW > currentH ? currentW : currentH;
    if (maxCurrent <= maxSide) return base;

    final scale = maxSide / maxCurrent;
    final nextW = (currentW * scale).round().clamp(1, maxSide);
    final nextH = (currentH * scale).round().clamp(1, maxSide);

    return ImageProcessOptions(
      compressEnabled: base.compressEnabled,
      quality: base.quality,
      resizeEnabled: true,
      resizeWidth: nextW,
      resizeHeight: nextH,
      keepExif: base.keepExif,
      format: base.format,
    );
  }

  int? _tryParseDim(String value) {
    final v = int.tryParse(value.trim());
    if (v == null || v <= 0) return null;
    return v;
  }

  Future<void> _buildPreview() async {
    if (_previewInFlight) {
      return;
    }

    _saveActiveDimsFromControllers();

    if (_beforeWidth == null || _beforeHeight == null) {
      await _loadActiveImageMeta();
    }

    final beforeW = _beforeWidth;
    final beforeH = _beforeHeight;
    if (beforeW == null || beforeH == null) return;

    final requestId = ++_previewRequestId;

    _previewInFlight = true;

    setState(() {
      _isPreviewLoading = true;
      _previewError = null;
    });

    try {
      final out = await _buildPreviewOnly();
      if (!mounted || requestId != _previewRequestId) return;
      setState(() {
        _afterBytes = out.bytes;
        _afterSaveBytes = null;
        _afterSaveFormat = out.saveFormat;
        _afterSaveIndex = _activeIndex;
        _afterWidth = out.width ?? beforeW;
        _afterHeight = out.height ?? beforeH;
        _isPreviewLoading = false;
        _previewDirty = false;
        if (_isMulti) {
          _previewByIndex[_activeIndex] = out;
        }
      });
    } catch (e) {
      if (!mounted || requestId != _previewRequestId) return;
      debugPrint('Preview generation failed: $e');
      setState(() {
        _afterBytes = null;
        _afterSaveBytes = null;
        _afterSaveFormat = null;
        _afterSaveIndex = null;
        _afterWidth = null;
        _afterHeight = null;
        _isPreviewLoading = false;
        _previewError = 'Preview failed';
        _previewDirty = true;
      });
    } finally {
      _previewInFlight = false;
    }
  }

  int _qualityInt() {
    if (_isMultiSession) {
      final st = _activeMultiState;
      return st?.qualityInt() ?? 80;
    }
    if (!_compressEnabled) return 100;
    return _quality.round().clamp(1, 100);
  }

  ImageProcessOptions _optionsForCurrentState({required OutputFormat format}) {
    final w = _tryParseDim(_widthController.text);
    final h = _tryParseDim(_heightController.text);
    if (_isMultiSession) {
      final st = _activeMultiState;
      return ImageProcessOptions(
        compressEnabled: st?.compressEnabled ?? true,
        quality: st?.qualityInt() ?? 80,
        resizeEnabled: st?.resizeEnabled ?? false,
        resizeWidth: w,
        resizeHeight: h,
        keepExif: st?.keepExif ?? false,
        format: format == OutputFormat.pdf ? OutputFormat.jpg : format,
      );
    }
    return ImageProcessOptions(
      compressEnabled: _compressEnabled,
      quality: _qualityInt(),
      resizeEnabled: _resizeEnabled,
      resizeWidth: w,
      resizeHeight: h,
      keepExif: _keepExif,
      format: format == OutputFormat.pdf ? OutputFormat.jpg : format,
    );
  }

  ImageProcessOptions _optionsForIndex({
    required int index,
    required OutputFormat format,
  }) {
    if (_isMultiSession) {
      final st = (index >= 0 && index < (_multiLogic?.states.length ?? 0))
          ? _multiLogic!.states[index]
          : null;
      return ImageProcessOptions(
        compressEnabled: st?.compressEnabled ?? true,
        quality: st?.qualityInt() ?? 80,
        resizeEnabled: st?.resizeEnabled ?? false,
        resizeWidth: st?.resizeWidth,
        resizeHeight: st?.resizeHeight,
        keepExif: st?.keepExif ?? false,
        format: format,
      );
    }

    final dims = _dimsByIndex[index];
    return ImageProcessOptions(
      compressEnabled: _compressEnabled,
      quality: _qualityInt(),
      resizeEnabled: _resizeEnabled,
      resizeWidth: dims?.width,
      resizeHeight: dims?.height,
      keepExif: _keepExif,
      format: format,
    );
  }

  void _setActiveIndex(int index) {
    if (index < 0 || index >= _images.length) return;

    _saveActiveDimsFromControllers();

    setState(() {
      _activeIndex = index;
      _activeInputFormat = _detectInputFormat(_activeImage.name);
      _beforeWidth = null;
      _beforeHeight = null;
      _afterBytes = null;
      _afterSaveBytes = null;
      _afterSaveFormat = null;
      _afterSaveIndex = null;
      _afterWidth = null;
      _afterHeight = null;
      _previewError = null;
      _previewDirty = true;
      _stage = _EditorStage.edit;
    });

    unawaited(_loadActiveImageMeta());
  }

  Future<void> _onCrop() async {
    if (_images.length != 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Crop is available for single image only.'),
        ),
      );
      return;
    }

    final original = _images.first;
    final originalFormat = _detectInputFormat(original.name);
    final originalMaxBytes = original.bytes.length;

    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (context) => CropImageScreen(bytes: _images.first.bytes),
      ),
    );

    if (cropped == null) return;

    Uint8List nextBytes = cropped;
    try {
      final decoded = img.decodeImage(cropped);
      if (decoded != null) {
        if (originalFormat == OutputFormat.jpg ||
            originalFormat == OutputFormat.jpeg) {
          const minQ = 30;
          const maxQ = 95;
          var lo = minQ;
          var hi = maxQ;
          Uint8List? best;
          var bestQ = minQ;

          while (lo <= hi) {
            final mid = (lo + hi) >> 1;
            final bytes = Uint8List.fromList(
              img.encodeJpg(decoded, quality: mid),
            );
            if (bytes.length <= originalMaxBytes) {
              best = bytes;
              bestQ = mid;
              lo = mid + 1;
            } else {
              hi = mid - 1;
            }
          }

          if (best != null) {
            nextBytes = best;
          } else {
            nextBytes = Uint8List.fromList(
              img.encodeJpg(decoded, quality: bestQ),
            );
          }
        } else if (originalFormat == OutputFormat.png) {
          nextBytes = Uint8List.fromList(img.encodePng(decoded, level: 9));
        }
      }
    } catch (_) {
      // Keep cropped bytes as-is.
    }

    setState(() {
      _cropped = true;
      _images = [SelectedImage(name: _images.first.name, bytes: nextBytes)];
      _activeIndex = 0;
      _activeInputFormat = _detectInputFormat(_images.first.name);
      _dimsByIndex.clear();
      _beforeWidth = null;
      _beforeHeight = null;
      _afterBytes = null;
      _afterSaveBytes = null;
      _afterSaveFormat = null;
      _afterSaveIndex = null;
      _afterWidth = null;
      _afterHeight = null;
      _previewError = null;
      _previewDirty = true;
      _stage = _EditorStage.edit;
      _widthController.text = '';
      _heightController.text = '';
    });

    unawaited(_loadActiveImageMeta());
  }

  String _formatLabel(OutputFormat f) {
    switch (f) {
      case OutputFormat.jpg:
        return 'JPG';
      case OutputFormat.jpeg:
        return 'JPEG';
      case OutputFormat.png:
        return 'PNG';
      case OutputFormat.webp:
        return 'WEBP';
      case OutputFormat.gif:
        return 'GIF';
      case OutputFormat.bmp:
        return 'BMP';
      case OutputFormat.pdf:
        return 'PDF';
    }
  }

  String _formatExt(OutputFormat f) {
    switch (f) {
      case OutputFormat.jpg:
        return 'jpg';
      case OutputFormat.jpeg:
        return 'jpeg';
      case OutputFormat.png:
        return 'png';
      case OutputFormat.webp:
        return 'webp';
      case OutputFormat.gif:
        return 'gif';
      case OutputFormat.bmp:
        return 'bmp';
      case OutputFormat.pdf:
        return 'pdf';
    }
  }

  String _bytesLabel(int bytes) {
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  Future<void> _onDone() async {
    if (_isSaving) return;

    if (_stage == _EditorStage.edit) {
      if (_isMulti) {
        setState(() {
          _isPreviewLoading = true;
          _previewError = null;
        });
        _goToPreviewStage();
        unawaited(_buildPreview());
        return;
      }

      if (_previewDirty) {
        setState(() {
          _isPreviewLoading = true;
          _previewError = null;
        });
        _goToPreviewStage();
        unawaited(_buildPreview());
        return;
      }

      _goToPreviewStage();
      return;
    }

    if (_stage == _EditorStage.previewOne && _isMulti) {
      setState(() {
        _isSaving = true;
      });

      await Future<void>.delayed(Duration.zero);
      await WidgetsBinding.instance.endOfFrame;

      try {
        await _saveActiveImage();
        if (!mounted) return;

        setState(() {
          _multiLogic?.removeAt(_activeIndex);
          _previewByIndex.clear();
          _beforeWidth = null;
          _beforeHeight = null;
          _afterBytes = null;
          _afterSaveBytes = null;
          _afterSaveFormat = null;
          _afterSaveIndex = null;
          _afterWidth = null;
          _afterHeight = null;
          _previewError = null;
          _previewDirty = true;
          _stage = _EditorStage.edit;
          _widthController.text = '';
          _heightController.text = '';
          if (_activeIndex >= _images.length && _images.isNotEmpty) {
            _activeIndex = _images.length - 1;
          }
          if (_images.isNotEmpty) {
            _activeInputFormat = _detectInputFormat(_activeImage.name);
          }
        });

        if (!mounted) return;
        if (_images.isEmpty) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/results', (route) => route.isFirst);
          return;
        }

        unawaited(_loadActiveImageMeta());
        return;
      } catch (e, st) {
        debugPrint('Save failed: $e');
        debugPrint('$st');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to save: ${e.toString().length > 120 ? e.toString().substring(0, 120) : e.toString()}',
            ),
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
        }
      }
    }

    if (_stage == _EditorStage.previewAll) {
      setState(() {
        _isSaving = true;
      });

      await Future<void>.delayed(Duration.zero);
      await WidgetsBinding.instance.endOfFrame;

      try {
        await _saveAllImages();
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/results', (route) => route.isFirst);
        return;
      } catch (e, st) {
        debugPrint('Save failed: $e');
        debugPrint('$st');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to save: ${e.toString().length > 120 ? e.toString().substring(0, 120) : e.toString()}',
            ),
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
        }
      }
      return;
    }

    setState(() {
      _isSaving = true;
    });

    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;

    if (!mounted) return;

    try {
      if (_optionsForCurrentState(format: OutputFormat.jpg).keepExif &&
          _cropped) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Keep EXIF works only without crop for now.'),
          ),
        );
      }

      await _saveActiveImage();
      if (!mounted) return;

      if (_images.length == 1) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/results', (route) => route.isFirst);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved Image ${_activeIndex + 1}/${_images.length}'),
        ),
      );

      if (_activeIndex < _images.length - 1) {
        _setActiveIndex(_activeIndex + 1);
        return;
      }

      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/results', (route) => route.isFirst);
    } catch (e, st) {
      debugPrint('Save failed: $e');
      debugPrint('$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to save: ${e.toString().length > 120 ? e.toString().substring(0, 120) : e.toString()}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_images.isEmpty) {
      return const Scaffold(
        backgroundColor: ImageEditorScreen.bg,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(ImageEditorScreen.gold),
          ),
        ),
      );
    }

    final before = _activeImage.bytes;
    final after = _afterBytes;
    final afterSave = _afterSaveBytes;
    final afterError = _previewError;

    final multiState = _activeMultiState;
    final compressEnabled = _isMultiSession
        ? (multiState?.compressEnabled ?? true)
        : _compressEnabled;
    final resizeEnabled = _isMultiSession
        ? (multiState?.resizeEnabled ?? false)
        : _resizeEnabled;
    final keepExif = _isMultiSession
        ? (multiState?.keepExif ?? false)
        : _keepExif;
    final qualityValue = _isMultiSession
        ? (multiState?.quality ?? 80)
        : _quality;

    final beforeW = _beforeWidth;
    final beforeH = _beforeHeight;
    final afterWidth = _afterWidth;
    final afterHeight = _afterHeight;

    return Scaffold(
      backgroundColor: ImageEditorScreen.bg,
      appBar: AppBar(
        backgroundColor: ImageEditorScreen.bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _isMultiSession
              ? 'Image ${_activeIndex + 1}/${_images.length}'
              : _images.first.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            color: Color(0xFF14161A),
            border: Border(top: BorderSide(color: Color(0x22111111))),
          ),
          child: Row(
            children: [
              if (_stage != _EditorStage.edit)
                TextButton.icon(
                  onPressed: _goToEditStage,
                  icon: const Icon(
                    Icons.arrow_back,
                    color: ImageEditorScreen.gold,
                  ),
                  label: const Text(
                    'Back',
                    style: TextStyle(color: Colors.white),
                  ),
                )
              else ...[
                if (_images.length == 1) ...[
                  TextButton.icon(
                    onPressed: _onCrop,
                    icon: const Icon(Icons.crop, color: ImageEditorScreen.gold),
                    label: const Text(
                      'Crop',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.image, color: ImageEditorScreen.gold),
                  label: const Text(
                    'Change',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
              const Spacer(),
              if (_isMultiSession && _stage == _EditorStage.edit) ...[
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _onDone,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ImageEditorScreen.gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: const Text(
                      'Save',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _onSaveAll,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F1D2F),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: Color(0x38E2C078)),
                      ),
                    ),
                    icon: const Icon(Icons.done_all),
                    label: const Text(
                      'Save All',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ] else
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _onDone,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ImageEditorScreen.gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      _isSaving
                          ? 'Saving'
                          : (_stage == _EditorStage.previewOne
                                ? 'Save'
                                : (_stage == _EditorStage.previewAll
                                      ? 'Save All'
                                      : (_isMulti ? 'Save' : 'Done'))),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              if (_images.length > 1 && _stage == _EditorStage.edit) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(_images.length, (i) {
                      final selected = i == _activeIndex;
                      return Padding(
                        padding: EdgeInsets.only(
                          right: i == _images.length - 1 ? 0 : 10,
                        ),
                        child: ChoiceChip(
                          selected: selected,
                          label: Text('Image ${i + 1}'),
                          labelStyle: TextStyle(
                            color: selected ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                          selectedColor: ImageEditorScreen.gold,
                          backgroundColor: const Color(0xFF1F1D2F),
                          side: const BorderSide(color: Color(0x38E2C078)),
                          onSelected: (_) => _setActiveIndex(i),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_stage == _EditorStage.previewAll)
                ...List.generate(_images.length, (i) {
                  final out = _previewByIndex[i];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: i == _images.length - 1 ? 0 : 12,
                    ),
                    child: _PreviewCard(
                      title: 'Image ${i + 1}',
                      bytes: out?.bytes,
                      width: out?.width,
                      height: out?.height,
                      sizeLabel: out == null
                          ? '--'
                          : (out.saveBytes == null
                                ? '--'
                                : _bytesLabel(out.saveBytes!.length)),
                      errorText: out == null ? 'Preview missing' : null,
                    ),
                  );
                })
              else if (_stage == _EditorStage.previewOne)
                _PreviewCard(
                  title: 'After',
                  bytes: after,
                  width: afterWidth,
                  height: afterHeight,
                  sizeLabel: afterSave == null
                      ? '--'
                      : _bytesLabel(afterSave.length),
                  loading: _isPreviewLoading,
                  errorText: afterError,
                )
              else
                _PreviewCard(
                  title: 'Before',
                  bytes: before,
                  width: beforeW,
                  height: beforeH,
                  sizeLabel: _bytesLabel(before.length),
                ),
              const SizedBox(height: 16),
              if (_stage != _EditorStage.edit) ...[
                _SectionCard(
                  title: 'Preview',
                  icon: Icons.visibility,
                  child: const Text(
                    'If you want to change settings, tap Back.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_stage != _EditorStage.edit)
                ...[]
              else ...[
                _SectionCard(
                  title: 'Compress Photo',
                  icon: Icons.compress,
                  trailing: Switch(
                    value: compressEnabled,
                    activeThumbColor: ImageEditorScreen.gold,
                    onChanged: (v) {
                      if (_isMultiSession) {
                        final st = _activeMultiState;
                        if (st != null) {
                          setState(() => st.compressEnabled = v);
                        }
                      } else {
                        setState(() => _compressEnabled = v);
                      }
                      _markPreviewDirty();
                    },
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Quality',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_qualityInt()}%',
                            style: const TextStyle(
                              color: ImageEditorScreen.gold,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: qualityValue,
                        min: 1,
                        max: 100,
                        activeColor: ImageEditorScreen.gold,
                        inactiveColor: Colors.white24,
                        onChanged: compressEnabled
                            ? (v) {
                                if (_isMultiSession) {
                                  final st = _activeMultiState;
                                  if (st != null) {
                                    setState(() => st.quality = v);
                                  }
                                } else {
                                  setState(() => _quality = v);
                                }
                                _markPreviewDirty();
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Resize Resolution',
                  icon: Icons.photo_size_select_large,
                  trailing: Switch(
                    value: resizeEnabled,
                    activeThumbColor: ImageEditorScreen.gold,
                    onChanged: (v) {
                      _saveActiveDimsFromControllers();
                      if (_isMultiSession) {
                        final st = _activeMultiState;
                        if (st != null) {
                          setState(() => st.resizeEnabled = v);
                        }
                      } else {
                        setState(() => _resizeEnabled = v);
                      }
                      _markPreviewDirty();
                    },
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _widthController,
                          enabled: resizeEnabled,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Width',
                            labelStyle: TextStyle(color: Colors.white70),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: ImageEditorScreen.gold,
                              ),
                            ),
                          ),
                          onChanged: (_) {
                            _saveActiveDimsFromControllers();
                            _markPreviewDirty();
                          },
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TextField(
                          controller: _heightController,
                          enabled: resizeEnabled,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Height',
                            labelStyle: TextStyle(color: Colors.white70),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: ImageEditorScreen.gold,
                              ),
                            ),
                          ),
                          onChanged: (_) {
                            _saveActiveDimsFromControllers();
                            _markPreviewDirty();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Convert Format',
                  icon: Icons.autorenew,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: ChoiceChip(
                            selected: _isMultiSession
                                ? (_activeMultiState?.useSameAsInput ?? true)
                                : (_formatByIndex[_activeIndex]
                                          ?.useSameAsInput ??
                                      true),
                            label: const Text('SAME'),
                            labelStyle: TextStyle(
                              color:
                                  (_isMultiSession
                                      ? (_activeMultiState?.useSameAsInput ??
                                            true)
                                      : (_formatByIndex[_activeIndex]
                                                ?.useSameAsInput ??
                                            true))
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                            selectedColor: ImageEditorScreen.gold,
                            backgroundColor: const Color(0xFF1F1D2F),
                            side: const BorderSide(color: Color(0x38E2C078)),
                            onSelected: (_) {
                              setState(() {
                                _activeInputFormat = _detectInputFormat(
                                  _activeImage.name,
                                );
                                if (_isMultiSession) {
                                  final st = _activeMultiState;
                                  if (st != null) {
                                    st.useSameAsInput = true;
                                    st.format = _activeInputFormat;
                                  }
                                } else {
                                  _formatByIndex[_activeIndex] = _FormatChoice(
                                    useSameAsInput: true,
                                    format: _activeInputFormat,
                                  );
                                }
                              });
                              _markPreviewDirty();
                            },
                          ),
                        ),
                        ...OutputFormat.values
                            .where(
                              (f) =>
                                  _images.length == 1 || f != OutputFormat.pdf,
                            )
                            .where((f) => !_isSameFamily(f, _activeInputFormat))
                            .map((f) {
                              final choice = _isMultiSession
                                  ? null
                                  : _formatByIndex[_activeIndex];
                              final selected = _isMultiSession
                                  ? ((_activeMultiState != null) &&
                                        !(_activeMultiState!.useSameAsInput) &&
                                        _activeMultiState!.format == f)
                                  : (choice != null &&
                                        !choice.useSameAsInput &&
                                        choice.format == f);
                              return Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: ChoiceChip(
                                  selected: selected,
                                  label: Text(_formatLabel(f)),
                                  labelStyle: TextStyle(
                                    color: selected
                                        ? Colors.black
                                        : Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  selectedColor: ImageEditorScreen.gold,
                                  backgroundColor: const Color(0xFF1F1D2F),
                                  side: const BorderSide(
                                    color: Color(0x38E2C078),
                                  ),
                                  onSelected: (_) {
                                    setState(() {
                                      if (_isMultiSession) {
                                        final st = _activeMultiState;
                                        if (st != null) {
                                          st.useSameAsInput = false;
                                          st.format = f;
                                        }
                                      } else {
                                        _formatByIndex[_activeIndex] =
                                            _FormatChoice(
                                              useSameAsInput: false,
                                              format: f,
                                            );
                                      }
                                    });
                                    _markPreviewDirty();
                                  },
                                ),
                              );
                            }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Keep Exif Data',
                  icon: Icons.info_outline,
                  trailing: Checkbox(
                    value: keepExif,
                    activeColor: ImageEditorScreen.gold,
                    onChanged: (v) {
                      if (_isMultiSession) {
                        final st = _activeMultiState;
                        if (st != null) {
                          setState(() => st.keepExif = v ?? false);
                        }
                      } else {
                        setState(() => _keepExif = v ?? false);
                      }
                      _markPreviewDirty();
                    },
                  ),
                  child: const Text(
                    'Best effort: works reliably only without crop.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Saved to Phone',
                  icon: Icons.photo_library_outlined,
                  trailing: const Icon(
                    Icons.check_circle,
                    color: ImageEditorScreen.gold,
                  ),
                  child: const Text(
                    'Automatically saves to Result Folder and also to Gallery (Pictures/ImageConverter).',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (_isSaving && _stage != _EditorStage.edit)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(
                  color: const Color(0xAA000000),
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: ImageEditorScreen.gold,
                    ),
                  ),
                ),
              ),
            ),
          if (_isPreviewLoading && _stage != _EditorStage.edit)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(
                  color: const Color(0x66000000),
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: ImageEditorScreen.gold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _EditorStage { edit, previewOne, previewAll }

class _PreviewOut {
  const _PreviewOut({
    required this.bytes,
    required this.saveBytes,
    required this.saveFormat,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final Uint8List? saveBytes;
  final OutputFormat saveFormat;
  final int? width;
  final int? height;
}

class _ResizeDims {
  const _ResizeDims({required this.width, required this.height});

  final int width;
  final int height;
}

class _FormatChoice {
  const _FormatChoice({required this.useSameAsInput, required this.format});

  final bool useSameAsInput;
  final OutputFormat format;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ImageEditorScreen.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x38E2C078)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF1F1D2F),
                ),
                child: Icon(icon, color: ImageEditorScreen.gold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: child),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.title,
    required this.bytes,
    required this.sizeLabel,
    this.width,
    this.height,
    this.loading = false,
    this.errorText,
  });

  final String title;
  final Uint8List? bytes;
  final int? width;
  final int? height;
  final String sizeLabel;
  final bool loading;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ImageEditorScreen.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x38E2C078)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F1D2F),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0x38E2C078)),
                ),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      ImageEditorScreen.gold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          AspectRatio(
            aspectRatio: 1.35,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Color(0xFF14161A)),
                child: bytes == null
                    ? Center(
                        child: Text(
                          (errorText != null && errorText!.trim().isNotEmpty)
                              ? errorText!
                              : '—',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    : Image.memory(
                        bytes!,
                        fit: BoxFit.contain,
                        cacheWidth: 900,
                        cacheHeight: 900,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Flexible(
                flex: 3,
                child: Text(
                  width != null && height != null
                      ? '${width}x$height px'
                      : '--',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: Text(
                  sizeLabel,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
