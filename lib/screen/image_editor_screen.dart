import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'crop_image_screen.dart';
import '../services/app_settings.dart';
import '../services/image_processing_service.dart';
import '../services/gallery_save_service.dart';
import '../services/models.dart';
import '../services/output_storage_service.dart';
import '../services/pdf_export_service.dart';

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

  bool _compressEnabled = true;
  bool _resizeEnabled = false;
  bool _keepExif = false;

  double _quality = 80;

  final Map<int, _FormatChoice> _formatByIndex = <int, _FormatChoice>{};

  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();

  final Map<int, _ResizeDims> _dimsByIndex = <int, _ResizeDims>{};

  Uint8List? _afterBytes;
  int? _afterWidth;
  int? _afterHeight;
  bool _isPreviewLoading = false;
  String? _previewError;
  bool _previewDirty = true;
  bool _isSaving = false;

  bool _photoSpeedUp = false;

  _EditorStage _stage = _EditorStage.edit;

  int _previewRequestId = 0;
  bool _previewInFlight = false;

  img.Image? _beforeDecoded;

  SelectedImage get _activeImage =>
      _images[_activeIndex.clamp(0, _images.length - 1)];

  OutputFormat _effectiveFormatForIndex(int index) {
    final imgItem = _images[index];
    final choice = _formatByIndex[index];
    if (choice == null || choice.useSameAsInput) {
      return _detectInputFormat(imgItem.name);
    }
    return choice.format;
  }

  OutputFormat _previewFormatForIndex(int index) {
    final effective = _effectiveFormatForIndex(index);
    if (effective == OutputFormat.pdf) {
      return OutputFormat.jpg;
    }
    return effective;
  }

  @override
  void initState() {
    super.initState();
    _images = List<SelectedImage>.from(widget.images);
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
    for (var i = 0; i < _images.length; i++) {
      _formatByIndex[i] = _FormatChoice(
        useSameAsInput: true,
        format: _detectInputFormat(_images[i].name),
      );
    }

    _dimsByIndex.clear();

    _beforeDecoded = img.decodeImage(_activeImage.bytes);
    if (_beforeDecoded != null) {
      _widthController.text = _beforeDecoded!.width.toString();
      _heightController.text = _beforeDecoded!.height.toString();
      _dimsByIndex[_activeIndex] = _ResizeDims(
        width: _beforeDecoded!.width,
        height: _beforeDecoded!.height,
      );
    }
    _afterBytes = null;
    _afterWidth = null;
    _afterHeight = null;
    _previewError = null;
    _previewDirty = true;
    _stage = _EditorStage.edit;
  }

  void _markPreviewDirty() {
    setState(() {
      _previewDirty = true;
      _afterBytes = null;
      _afterWidth = null;
      _afterHeight = null;
      _previewError = null;
      if (_stage == _EditorStage.preview) {
        _stage = _EditorStage.edit;
      }
    });
  }

  void _goToPreviewStage() {
    if (!mounted) return;
    setState(() {
      _stage = _EditorStage.preview;
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

  Future<void> _saveActiveImage() async {
    final index = _activeIndex;
    final image = _images[index];
    final effectiveFormat = _effectiveFormatForIndex(index);

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
        _keepExif && !_cropped && effectiveFormat != OutputFormat.pdf;

    if (effectiveFormat == OutputFormat.pdf) {
      final pdfBytes = await _pdfExportService.buildPdf(
        images: [image],
        options: options,
      );

      final stamp = _timestamp();
      final fileName = 'PDF_${stamp}.pdf';
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

    Uint8List bytes;
    if (canPreserveExif) {
      final exifBytes = await _imageProcessingService
          .encodeFromSourceBytesPreservingExif(
            sourceBytes: image.bytes,
            options: options,
          );
      if (exifBytes != null) {
        bytes = exifBytes;
      } else {
        bytes = await _imageProcessingService.encodeFromSourceBytes(
          sourceBytes: image.bytes,
          options: options,
        );
      }
    } else {
      bytes = await _imageProcessingService.encodeFromSourceBytes(
        sourceBytes: image.bytes,
        options: options,
      );
    }

    final stamp = _timestamp();
    final label = _formatLabel(effectiveFormat);
    final ext = _formatExt(effectiveFormat);
    final suffix = _images.length == 1 ? '' : '_${index + 1}';
    final fileName = '${label}_${stamp}${suffix}.$ext';

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

  void _saveActiveDimsFromControllers() {
    final w = _tryParseDim(_widthController.text);
    final h = _tryParseDim(_heightController.text);
    if (w == null || h == null) return;
    _dimsByIndex[_activeIndex] = _ResizeDims(width: w, height: h);
  }

  void _applyDimsForIndex({required int index, required img.Image? decoded}) {
    final existing = _dimsByIndex[index];
    if (existing != null) {
      _widthController.text = existing.width.toString();
      _heightController.text = existing.height.toString();
      return;
    }
    if (decoded == null) return;
    _dimsByIndex[index] = _ResizeDims(
      width: decoded.width,
      height: decoded.height,
    );
    _widthController.text = decoded.width.toString();
    _heightController.text = decoded.height.toString();
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
    final decoded = _beforeDecoded;
    if (decoded == null) return base;

    final maxSide = _photoSpeedUp ? 900 : 1400;
    final currentW = base.resizeEnabled && base.resizeWidth != null
        ? base.resizeWidth!
        : decoded.width;
    final currentH = base.resizeEnabled && base.resizeHeight != null
        ? base.resizeHeight!
        : decoded.height;

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

    final beforeDecoded = _beforeDecoded;
    if (beforeDecoded == null) return;

    final requestId = ++_previewRequestId;

    _previewInFlight = true;

    setState(() {
      _isPreviewLoading = true;
      _previewError = null;
    });

    try {
      final out = await _processOne(
        _activeImage,
        format: _previewFormatForIndex(_activeIndex),
      );
      if (!mounted || requestId != _previewRequestId) return;
      setState(() {
        _afterBytes = out.bytes;
        _afterWidth = out.width ?? beforeDecoded.width;
        _afterHeight = out.height ?? beforeDecoded.height;
        _isPreviewLoading = false;
        _previewDirty = false;
      });
    } catch (e) {
      if (!mounted || requestId != _previewRequestId) return;
      debugPrint('Preview generation failed: $e');
      setState(() {
        _afterBytes = null;
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
    if (!_compressEnabled) return 100;
    return _quality.round().clamp(1, 100);
  }

  ImageProcessOptions _optionsForCurrentState({required OutputFormat format}) {
    final w = _tryParseDim(_widthController.text);
    final h = _tryParseDim(_heightController.text);
    return ImageProcessOptions(
      compressEnabled: _compressEnabled,
      quality: _qualityInt(),
      resizeEnabled: _resizeEnabled,
      resizeWidth: w,
      resizeHeight: h,
      keepExif: _keepExif,
      format: format,
    );
  }

  ImageProcessOptions _optionsForIndex({
    required int index,
    required OutputFormat format,
  }) {
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

  Future<_Processed> _processOne(
    SelectedImage input, {
    required OutputFormat format,
  }) async {
    final options = _previewOptionsForCurrentState(format: format);
    final processed = await _imageProcessingService.processForPreview(
      input: input,
      options: options,
    );
    return _Processed(
      bytes: processed.bytes,
      width: processed.width,
      height: processed.height,
    );
  }

  void _setActiveIndex(int index) {
    if (index < 0 || index >= _images.length) return;

    _saveActiveDimsFromControllers();

    setState(() {
      _activeIndex = index;
      _activeInputFormat = _detectInputFormat(_activeImage.name);
      _beforeDecoded = img.decodeImage(_activeImage.bytes);
      _afterBytes = null;
      _afterWidth = null;
      _afterHeight = null;
      _previewError = null;
      _previewDirty = true;
      _stage = _EditorStage.edit;

      _applyDimsForIndex(index: _activeIndex, decoded: _beforeDecoded);
    });
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

    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (context) => CropImageScreen(bytes: _images.first.bytes),
      ),
    );

    if (cropped == null) return;

    setState(() {
      _cropped = true;
      _images = [SelectedImage(name: _images.first.name, bytes: cropped)];
      _activeIndex = 0;
      _activeInputFormat = _detectInputFormat(_images.first.name);
      _dimsByIndex.clear();
      _beforeDecoded = img.decodeImage(cropped);
      _afterBytes = null;
      _afterWidth = null;
      _afterHeight = null;
      _previewError = null;
      _previewDirty = true;
      _stage = _EditorStage.edit;
      if (_beforeDecoded != null) {
        _widthController.text = _beforeDecoded!.width.toString();
        _heightController.text = _beforeDecoded!.height.toString();
        _dimsByIndex[0] = _ResizeDims(
          width: _beforeDecoded!.width,
          height: _beforeDecoded!.height,
        );
      }
    });
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
      if (_previewDirty) {
        setState(() {
          _isSaving = true;
        });

        try {
          await _buildPreview();
          if (!mounted) return;
          if (_afterBytes != null) {
            _goToPreviewStage();
            return;
          }
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Preview failed.')));
        } finally {
          if (mounted) {
            setState(() {
              _isSaving = false;
            });
          }
        }
        return;
      }

      _goToPreviewStage();
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _outputStorageService.getOutputDirectory();

      if (_keepExif && _cropped) {
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
    final before = _activeImage.bytes;
    final after = _afterBytes;
    final afterError = _previewError;

    final beforeDecoded = _beforeDecoded;
    final afterWidth = _afterWidth;
    final afterHeight = _afterHeight;

    return Scaffold(
      backgroundColor: ImageEditorScreen.bg,
      appBar: AppBar(
        backgroundColor: ImageEditorScreen.bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _images.length == 1
              ? _images.first.name
              : 'Image ${_activeIndex + 1}/${_images.length}',
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
              if (_stage == _EditorStage.preview)
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
                        : (_stage == _EditorStage.preview ? 'Save' : 'Done'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          if (_images.length > 1) ...[
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
          if (_stage == _EditorStage.preview)
            _PreviewCard(
              title: 'After',
              bytes: after,
              width: afterWidth,
              height: afterHeight,
              sizeLabel: after == null ? '--' : _bytesLabel(after.length),
              loading: _isPreviewLoading,
              errorText: afterError,
            )
          else
            _PreviewCard(
              title: 'Before',
              bytes: before,
              width: beforeDecoded?.width,
              height: beforeDecoded?.height,
              sizeLabel: _bytesLabel(before.length),
            ),
          const SizedBox(height: 16),
          if (_stage == _EditorStage.preview) ...[
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
          if (_stage == _EditorStage.preview)
            ...[]
          else ...[
            _SectionCard(
              title: 'Compress Photo',
              icon: Icons.compress,
              trailing: Switch(
                value: _compressEnabled,
                activeColor: ImageEditorScreen.gold,
                onChanged: (v) {
                  setState(() => _compressEnabled = v);
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
                    value: _quality,
                    min: 1,
                    max: 100,
                    activeColor: ImageEditorScreen.gold,
                    inactiveColor: Colors.white24,
                    onChanged: _compressEnabled
                        ? (v) {
                            setState(() => _quality = v);
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
                value: _resizeEnabled,
                activeColor: ImageEditorScreen.gold,
                onChanged: (v) {
                  _saveActiveDimsFromControllers();
                  setState(() => _resizeEnabled = v);
                  _markPreviewDirty();
                },
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _widthController,
                      enabled: _resizeEnabled,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Width',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: ImageEditorScreen.gold),
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
                      enabled: _resizeEnabled,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Height',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: ImageEditorScreen.gold),
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
                        selected:
                            _formatByIndex[_activeIndex]?.useSameAsInput ??
                            true,
                        label: const Text('SAME'),
                        labelStyle: TextStyle(
                          color:
                              (_formatByIndex[_activeIndex]?.useSameAsInput ??
                                  true)
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
                            _formatByIndex[_activeIndex] = _FormatChoice(
                              useSameAsInput: true,
                              format: _activeInputFormat,
                            );
                          });
                          _markPreviewDirty();
                        },
                      ),
                    ),
                    ...OutputFormat.values
                        .where(
                          (f) => _images.length == 1 || f != OutputFormat.pdf,
                        )
                        .where((f) => !_isSameFamily(f, _activeInputFormat))
                        .map((f) {
                          final choice = _formatByIndex[_activeIndex];
                          final selected =
                              (choice != null &&
                              !choice.useSameAsInput &&
                              choice.format == f);
                          return Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: ChoiceChip(
                              selected: selected,
                              label: Text(_formatLabel(f)),
                              labelStyle: TextStyle(
                                color: selected ? Colors.black : Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                              selectedColor: ImageEditorScreen.gold,
                              backgroundColor: const Color(0xFF1F1D2F),
                              side: const BorderSide(color: Color(0x38E2C078)),
                              onSelected: (_) {
                                setState(() {
                                  _formatByIndex[_activeIndex] = _FormatChoice(
                                    useSameAsInput: false,
                                    format: f,
                                  );
                                });
                                _markPreviewDirty();
                              },
                            ),
                          );
                        })
                        .toList(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Keep Exif Data',
              icon: Icons.info_outline,
              trailing: Checkbox(
                value: _keepExif,
                activeColor: ImageEditorScreen.gold,
                onChanged: (v) {
                  setState(() => _keepExif = v ?? false);
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
    );
  }
}

enum _EditorStage { edit, preview }

class _Processed {
  const _Processed({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
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
