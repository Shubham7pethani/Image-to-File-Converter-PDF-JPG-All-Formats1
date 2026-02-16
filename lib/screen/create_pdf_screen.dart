import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../language/create_pdf_screen_language.dart';
import 'home_screen.dart';
import '../services/app_settings.dart';
import '../services/models.dart';
import 'pdf_pages_editor.dart';

class CreatePdfScreen extends StatefulWidget {
  const CreatePdfScreen({super.key});

  static const Color bg = Color(0xFF1B1E23);
  static const Color card = Color(0xFF2B2940);

  @override
  State<CreatePdfScreen> createState() => _CreatePdfScreenState();
}

class _CreatePdfScreenState extends State<CreatePdfScreen> {
  final ImagePicker _picker = ImagePicker();
  final AppSettings _settings = const AppSettings();
  bool _isLoading = false;

  static const int _maxPdfImages = 1000;

  List<SelectedImage> _dedupeImages(List<SelectedImage> images) {
    final seen = <String>{};
    final out = <SelectedImage>[];
    for (final img in images) {
      final fp = _fingerprint(img);
      if (seen.add(fp)) {
        out.add(img);
      }
    }
    return out;
  }

  String _fingerprint(SelectedImage img) {
    return '${img.name}_${img.bytes.length}';
  }

  Future<void> _withLoader(Future<void> Function() action) async {
    setState(() => _isLoading = true);
    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openEditor(List<SelectedImage> images) {
    unawaited(
      Future<void>.delayed(Duration.zero, () {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PdfPagesEditor(images: images),
          ),
        );
      }),
    );
  }

  Future<void> _pickFromCamera() async {
    await _withLoader(() async {
      final file = await _picker.pickImage(source: ImageSource.camera);
      if (!mounted) return;
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      _openEditor([SelectedImage(name: file.name, bytes: bytes)]);
    });
  }

  Future<void> _pickFromGallery() async {
    await _withLoader(() async {
      final files = await _picker.pickMultiImage(limit: _maxPdfImages);
      if (!mounted) return;
      if (files.isEmpty) return;

      final images = <SelectedImage>[];
      var i = 0;
      for (final f in files) {
        images.add(SelectedImage(name: f.name, bytes: await f.readAsBytes()));
        i++;
        if (i % 5 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      if (!mounted) return;
      final preventDuplicates = await _settings.getPreventDuplicates();
      if (!mounted) return;
      _openEditor(preventDuplicates ? _dedupeImages(images) : images);
    });
  }

  Future<void> _pickWithFilePicker() async {
    await _withLoader(() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) return;

      final images = <SelectedImage>[];
      var i = 0;
      for (final f in result.files) {
        final bytes = f.bytes;
        if (bytes == null) continue;
        images.add(SelectedImage(name: f.name, bytes: bytes));
        i++;
        if (i % 8 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      if (images.isEmpty) {
        if (!mounted) return;
        final code = Localizations.localeOf(context).languageCode;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(CreatePdfScreenLanguage.getUnableToReadFile(code)),
          ),
        );
        return;
      }

      if (!mounted) return;
      final preventDuplicates = await _settings.getPreventDuplicates();
      if (!mounted) return;
      _openEditor(preventDuplicates ? _dedupeImages(images) : images);
    });
  }

  @override
  Widget build(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return Scaffold(
      backgroundColor: CreatePdfScreen.bg,
      appBar: AppBar(
        backgroundColor: CreatePdfScreen.bg,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          CreatePdfScreenLanguage.getChoosePhotosForPdf(code),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 26,
                  crossAxisSpacing: 26,
                  padding: const EdgeInsets.all(24),
                  children: [
                    _ChooseTile(
                      icon: Icons.photo_camera_rounded,
                      label: CreatePdfScreenLanguage.getCamera(code),
                      onTap: _pickFromCamera,
                    ),
                    _ChooseTile(
                      icon: Icons.folder_rounded,
                      label: CreatePdfScreenLanguage.getPickImage(code),
                      onTap: _pickWithFilePicker,
                    ),
                    _ChooseTile(
                      icon: Icons.photo_library_rounded,
                      label: CreatePdfScreenLanguage.getPhotos(code),
                      onTap: _pickFromGallery,
                    ),
                    _ChooseTile(
                      icon: Icons.collections_rounded,
                      label: CreatePdfScreenLanguage.getGallery(code),
                      onTap: _pickFromGallery,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final h = (w * 0.85).clamp(280.0, 360.0);
                    return ConnectivityAdWrapper(
                      child: Container(
                        height: h,
                        decoration: BoxDecoration(
                          color: CreatePdfScreen.card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0x38E2C078)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: const NativeAdBox(adKey: 'pdf'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          if (_isLoading)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE2C078)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChooseTile extends StatelessWidget {
  const _ChooseTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF5D28B),
                    Color(0xFFE2C078),
                    Color(0xFFB8903C),
                  ],
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF2B2940),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Icon(icon, color: const Color(0xFFE2C078), size: 34),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
