import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/createpdflogic.dart';
import '../services/image_processing_service.dart';
import '../services/models.dart';
import '../services/output_storage_service.dart';
import '../services/pdf_export_service.dart';

class PdfPagesEditor extends StatefulWidget {
  const PdfPagesEditor({super.key, required this.images});

  final List<SelectedImage> images;

  static const Color bg = Color(0xFF1B1E23);
  static const Color card = Color(0xFF2B2940);
  static const Color gold = Color(0xFFE2C078);

  @override
  State<PdfPagesEditor> createState() => _PdfPagesEditorState();
}

enum _PdfEditorStage { edit, reorder }

class _PdfPagesEditorState extends State<PdfPagesEditor> {
  final ImageProcessingService _imageProcessingService =
      const ImageProcessingService();
  final OutputStorageService _outputStorageService =
      const OutputStorageService();

  late final PdfExportService _pdfExportService = PdfExportService(
    imageProcessingService: _imageProcessingService,
  );

  late final CreatePdfLogic _logic = CreatePdfLogic(images: widget.images);

  int _activeIndex = 0;
  _PdfEditorStage _stage = _PdfEditorStage.edit;
  bool _isSaving = false;

  int _saveDone = 0;
  int _saveTotal = 0;

  static const MethodChannel _progressChannel = MethodChannel(
    'com.sholo.imageconverter/progress_notification',
  );

  final TextEditingController _wController = TextEditingController();
  final TextEditingController _hController = TextEditingController();

  Uint8List? _previewBytes;
  bool _previewLoading = false;

  SelectedImage get _activeImage => _logic.pages[_activeIndex];
  PdfPageState get _activeState => _logic.states[_activeIndex];

  @override
  void initState() {
    super.initState();
    _applyDimsForActive();
    unawaited(_buildPreview());
  }

  @override
  void dispose() {
    _wController.dispose();
    _hController.dispose();
    super.dispose();
  }

  void _applyDimsForActive() {
    final w = _activeState.resizeWidth;
    final h = _activeState.resizeHeight;
    _wController.text = w == null ? '' : w.toString();
    _hController.text = h == null ? '' : h.toString();
  }

  void _saveDimsFromControllers() {
    if (!_activeState.resizeEnabled) {
      _activeState.resizeWidth = null;
      _activeState.resizeHeight = null;
      return;
    }

    final w = int.tryParse(_wController.text.trim());
    final h = int.tryParse(_hController.text.trim());
    _activeState.resizeWidth = w;
    _activeState.resizeHeight = h;
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}_${three(now.millisecond)}';
  }

  ImageProcessOptions _optionsForIndex(int index) {
    final s = _logic.states[index];
    return ImageProcessOptions(
      compressEnabled: s.compressEnabled,
      quality: s.qualityInt(),
      resizeEnabled: s.resizeEnabled,
      resizeWidth: s.resizeWidth,
      resizeHeight: s.resizeHeight,
      keepExif: s.keepExif,
      format: OutputFormat.pdf,
    );
  }

  Future<void> _buildPreview() async {
    if (_previewLoading) return;
    if (_logic.pages.isEmpty) return;

    setState(() {
      _previewLoading = true;
    });

    try {
      final options = _optionsForIndex(_activeIndex);
      final out = await _imageProcessingService.processForPreview(
        input: _activeImage,
        options: ImageProcessOptions(
          compressEnabled: options.compressEnabled,
          quality: options.quality,
          resizeEnabled: options.resizeEnabled,
          resizeWidth: options.resizeWidth,
          resizeHeight: options.resizeHeight,
          keepExif: false,
          format: OutputFormat.jpg,
        ),
      );

      if (!mounted) return;
      setState(() {
        _previewBytes = out.bytes;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _previewBytes = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _previewLoading = false;
        });
      }
    }
  }

  void _setActiveIndex(int index) {
    if (index < 0 || index >= _logic.pages.length) return;
    _saveDimsFromControllers();

    setState(() {
      _activeIndex = index;
      _previewBytes = null;
    });

    _applyDimsForActive();
    unawaited(_buildPreview());
  }

  void _markActiveDone() {
    if (_logic.pages.isEmpty) return;

    _saveDimsFromControllers();

    setState(() {
      _logic.states[_activeIndex].done = true;
    });

    final nextIndex = _logic.states.indexWhere((s) => !s.done);
    if (nextIndex >= 0) {
      _setActiveIndex(nextIndex);
      return;
    }

    setState(() {
      _stage = _PdfEditorStage.reorder;
    });
  }

  void _markAllDone() {
    if (_logic.pages.isEmpty) return;

    _saveDimsFromControllers();

    setState(() {
      for (final s in _logic.states) {
        s.done = true;
      }
      _stage = _PdfEditorStage.reorder;
    });
  }

  void _removePage(int index) {
    if (index < 0 || index >= _logic.pages.length) return;

    setState(() {
      _logic.removeAt(index);
      if (_logic.pages.isEmpty) {
        _activeIndex = 0;
        _previewBytes = null;
        return;
      }
      if (_activeIndex >= _logic.pages.length) {
        _activeIndex = _logic.pages.length - 1;
      } else if (index <= _activeIndex && _activeIndex > 0) {
        _activeIndex -= 1;
      }
      _previewBytes = null;
    });

    if (_logic.pages.isNotEmpty) {
      _applyDimsForActive();
      unawaited(_buildPreview());
    }
  }

  Future<void> _savePdf() async {
    if (_isSaving) return;
    if (_logic.pages.isEmpty) return;

    _saveDimsFromControllers();

    setState(() {
      _isSaving = true;
      _saveDone = 0;
      _saveTotal = _logic.pages.length;
    });

    if (!kIsWeb) {
      try {
        unawaited(
          _progressChannel.invokeMethod('start', {
            'total': _logic.pages.length,
            'title': 'Saving PDF',
          }),
        );
      } catch (_) {}
    }

    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    try {
      final totalPages = _logic.pages.length;
      final stamp = _timestamp();

      final pagesPerPart = totalPages <= 150
          ? totalPages
          : (totalPages > 200
                ? 20
                : (totalPages > 80 ? 25 : (totalPages > 40 ? 40 : 60)));
      final parts = (totalPages / pagesPerPart).ceil();
      final maxSide = totalPages > 200
          ? 900
          : (totalPages > 150
                ? 1200
                : (totalPages > 80 ? 1500 : (totalPages > 40 ? 1800 : 2200)));

      var processed = 0;

      for (var part = 0; part < parts; part++) {
        final start = part * pagesPerPart;
        final end = (start + pagesPerPart).clamp(0, totalPages);
        if (start >= end) break;

        final jpgBytesByPage = <Uint8List>[];
        for (var i = start; i < end; i++) {
          final options = _optionsForIndex(i);
          final q = options.quality < 85 ? 85 : options.quality;
          final jpgBytes = await _pdfExportService.encodeJpgForPdfPage(
            image: _logic.pages[i],
            options: ImageProcessOptions(
              compressEnabled: options.compressEnabled,
              quality: q,
              resizeEnabled: options.resizeEnabled,
              resizeWidth: options.resizeWidth,
              resizeHeight: options.resizeHeight,
              keepExif: false,
              format: OutputFormat.jpg,
            ),
            maxSide: maxSide,
          );

          // Replace original large bytes with the smaller JPG to release memory.
          _logic.pages[i] = SelectedImage(
            name: _logic.pages[i].name,
            bytes: jpgBytes,
          );
          jpgBytesByPage.add(jpgBytes);

          processed++;
          if (mounted && (processed == totalPages || processed % 2 == 0)) {
            setState(() {
              _saveDone = processed;
            });
            if (!kIsWeb) {
              try {
                unawaited(
                  _progressChannel.invokeMethod('update', {
                    'done': processed,
                    'total': totalPages,
                    'title': 'Saving PDF',
                  }),
                );
              } catch (_) {}
            }
          }
          if (processed % 2 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }

        final pdfBytes = await _pdfExportService.buildPdfFromJpgBytesInIsolate(
          jpgBytesByPage: jpgBytesByPage,
        );

        final fileName = parts <= 1
            ? 'PDF_$stamp.pdf'
            : 'PDF_${stamp}_part${part + 1}of$parts.pdf';

        await _outputStorageService.saveBytes(
          fileName: fileName,
          bytes: pdfBytes,
        );

        await Future<void>.delayed(Duration.zero);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            parts <= 1
                ? 'PDF saved in Result Folder. Gallery save supports images only.'
                : 'Saved $parts PDF parts in Result Folder.',
          ),
        ),
      );

      if (!kIsWeb) {
        try {
          unawaited(
            _progressChannel.invokeMethod('complete', {
              'title': 'Process completed',
              'body': 'Tap to see results',
            }),
          );
        } catch (_) {}
      }

      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/results', (route) => route.isFirst);
    } catch (e, st) {
      debugPrint('PDF save failed: $e');
      debugPrint('$st');
      if (!kIsWeb) {
        try {
          unawaited(_progressChannel.invokeMethod('cancel'));
        } catch (_) {}
      }
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

  Widget _buildEditBody() {
    if (_logic.pages.isEmpty) {
      return const Center(
        child: Text(
          'No pages selected.',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
        ),
      );
    }

    final s = _activeState;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List<Widget>.generate(_logic.pages.length, (i) {
              final selected = i == _activeIndex;
              final done = _logic.states[i].done;
              return Padding(
                padding: EdgeInsets.only(
                  right: i == _logic.pages.length - 1 ? 0 : 10,
                ),
                child: ChoiceChip(
                  selected: selected,
                  onSelected: (_) => _setActiveIndex(i),
                  selectedColor: PdfPagesEditor.gold,
                  backgroundColor: const Color(0xFF1F1D2F),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Page ${i + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: selected ? Colors.black : Colors.white,
                        ),
                      ),
                      if (done) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: selected ? Colors.black : PdfPagesEditor.gold,
                        ),
                      ],
                    ],
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                    side: const BorderSide(color: Color(0x38E2C078)),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: PdfPagesEditor.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x38E2C078)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Preview (Page ${_activeIndex + 1})',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              AspectRatio(
                aspectRatio: 1.1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ColoredBox(
                    color: const Color(0xFF1F1D2F),
                    child: _previewLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                PdfPagesEditor.gold,
                              ),
                            ),
                          )
                        : (_previewBytes == null
                              ? const Center(
                                  child: Text(
                                    'Preview unavailable',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                )
                              : Image.memory(
                                  _previewBytes!,
                                  fit: BoxFit.contain,
                                )),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _activeImage.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: PdfPagesEditor.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x38E2C078)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Compression',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.compressEnabled,
                activeThumbColor: PdfPagesEditor.gold,
                onChanged: (v) {
                  setState(() {
                    s.compressEnabled = v;
                  });
                  unawaited(_buildPreview());
                },
                title: const Text('Enable compression'),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text(
                    'Quality',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const Spacer(),
                  Text(
                    '${s.qualityInt()}%',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              Slider(
                value: s.quality,
                min: 1,
                max: 100,
                divisions: 99,
                onChanged: s.compressEnabled
                    ? (v) {
                        setState(() {
                          s.quality = v;
                        });
                      }
                    : null,
                onChangeEnd: (_) => unawaited(_buildPreview()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: PdfPagesEditor.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x38E2C078)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Resize',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.resizeEnabled,
                activeThumbColor: PdfPagesEditor.gold,
                onChanged: (v) {
                  setState(() {
                    s.resizeEnabled = v;
                    if (!v) {
                      s.resizeWidth = null;
                      s.resizeHeight = null;
                      _wController.text = '';
                      _hController.text = '';
                    }
                  });
                  unawaited(_buildPreview());
                },
                title: const Text('Enable resize'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _wController,
                      keyboardType: TextInputType.number,
                      enabled: s.resizeEnabled,
                      decoration: const InputDecoration(
                        labelText: 'Width',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        setState(() {
                          _saveDimsFromControllers();
                        });
                      },
                      onEditingComplete: () {
                        _saveDimsFromControllers();
                        unawaited(_buildPreview());
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _hController,
                      keyboardType: TextInputType.number,
                      enabled: s.resizeEnabled,
                      decoration: const InputDecoration(
                        labelText: 'Height',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        setState(() {
                          _saveDimsFromControllers();
                        });
                      },
                      onEditingComplete: () {
                        _saveDimsFromControllers();
                        unawaited(_buildPreview());
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: PdfPagesEditor.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x38E2C078)),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Keep EXIF (if supported)',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Checkbox(
                value: s.keepExif,
                activeColor: PdfPagesEditor.gold,
                onChanged: (v) {
                  setState(() {
                    s.keepExif = v ?? false;
                  });
                  unawaited(_buildPreview());
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReorderBody() {
    if (_logic.pages.isEmpty) {
      return const Center(
        child: Text(
          'No pages selected.',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      itemCount: _logic.pages.length,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex -= 1;
        setState(() {
          _logic.move(oldIndex, newIndex);
          if (_activeIndex == oldIndex) {
            _activeIndex = newIndex;
          } else if (oldIndex < _activeIndex && newIndex >= _activeIndex) {
            _activeIndex -= 1;
          } else if (oldIndex > _activeIndex && newIndex <= _activeIndex) {
            _activeIndex += 1;
          }
        });
      },
      itemBuilder: (context, index) {
        final page = _logic.pages[index];
        return Container(
          key: ValueKey('reorder_${index}_${page.name}'),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: PdfPagesEditor.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x38E2C078)),
          ),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 44,
                height: 44,
                child: ColoredBox(
                  color: const Color(0xFF1F1D2F),
                  child: Image.memory(
                    page.bytes,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    cacheWidth: 96,
                    cacheHeight: 96,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: Colors.white54,
                          size: 20,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            title: Text(
              'Page ${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              page.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => _removePage(index),
                  icon: const Icon(Icons.delete_outline),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PdfPagesEditor.bg,
      appBar: AppBar(
        backgroundColor: PdfPagesEditor.bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _stage == _PdfEditorStage.reorder
              ? 'Reorder Pages'
              : 'Create PDF (${_logic.pages.isEmpty ? 0 : _activeIndex + 1}/${_logic.pages.length})',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _stage == _PdfEditorStage.reorder
          ? _buildReorderBody()
          : _buildEditBody(),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            color: Color(0xFF14161A),
            border: Border(top: BorderSide(color: Color(0x22111111))),
          ),
          child: Row(
            children: [
              if (_stage == _PdfEditorStage.edit) ...[
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () {
                              Navigator.of(context).maybePop();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1F1D2F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: Color(0x38E2C078)),
                        ),
                      ),
                      icon: const Icon(Icons.image),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Change',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: (_logic.pages.isEmpty || _isSaving)
                          ? null
                          : _markActiveDone,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PdfPagesEditor.gold,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.check),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Save',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: (_logic.pages.isEmpty || _isSaving)
                          ? null
                          : _markAllDone,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1F1D2F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: Color(0x38E2C078)),
                        ),
                      ),
                      icon: const Icon(Icons.done_all),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Save All',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () {
                              setState(() {
                                _stage = _PdfEditorStage.edit;
                              });
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1F1D2F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: Color(0x38E2C078)),
                        ),
                      ),
                      icon: const Icon(Icons.edit),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Back',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: (_isSaving || _logic.pages.isEmpty)
                          ? null
                          : _savePdf,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PdfPagesEditor.gold,
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
                          : const Icon(Icons.picture_as_pdf),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _isSaving && _saveTotal > 0
                              ? 'Saving ${_saveDone.clamp(0, _saveTotal)}/$_saveTotal'
                              : (_isSaving ? 'Saving' : 'Save PDF'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
