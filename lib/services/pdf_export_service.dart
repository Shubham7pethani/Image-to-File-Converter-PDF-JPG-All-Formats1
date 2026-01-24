import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import 'image_processing_service.dart';
import 'models.dart';

class PdfExportService {
  const PdfExportService({required this.imageProcessingService});

  final ImageProcessingService imageProcessingService;

  Future<Uint8List> buildPdf({
    required List<SelectedImage> images,
    required ImageProcessOptions options,
  }) async {
    final pdf = pw.Document();

    for (final image in images) {
      final decoded = imageProcessingService.decode(image.bytes);
      final resized = imageProcessingService.applyResize(
        image: decoded,
        options: options,
      );
      final jpgBytes = await imageProcessingService.encode(
        resized,
        ImageProcessOptions(
          compressEnabled: options.compressEnabled,
          quality: options.quality,
          resizeEnabled: options.resizeEnabled,
          resizeWidth: options.resizeWidth,
          resizeHeight: options.resizeHeight,
          keepExif: options.keepExif,
          format: OutputFormat.jpg,
        ),
      );

      final mem = pw.MemoryImage(jpgBytes);
      pdf.addPage(pw.Page(build: (context) => pw.Center(child: pw.Image(mem))));
    }

    return pdf.save();
  }

  Future<Uint8List> buildPdfPerPage({
    required List<SelectedImage> images,
    required List<ImageProcessOptions> optionsByPage,
  }) async {
    if (images.length != optionsByPage.length) {
      throw ArgumentError('images and optionsByPage must be same length');
    }

    final pdf = pw.Document();

    for (var i = 0; i < images.length; i++) {
      final image = images[i];
      final options = optionsByPage[i];

      final jpgOptions = ImageProcessOptions(
        compressEnabled: options.compressEnabled,
        quality: options.quality,
        resizeEnabled: options.resizeEnabled,
        resizeWidth: options.resizeWidth,
        resizeHeight: options.resizeHeight,
        keepExif: options.keepExif,
        format: OutputFormat.jpg,
      );

      final fromSource = await imageProcessingService
          .encodeFromSourceBytesPreservingExif(
            sourceBytes: image.bytes,
            options: jpgOptions,
          );

      final jpgBytes =
          fromSource ??
          await (() async {
            final decoded = imageProcessingService.decode(image.bytes);
            final resized = imageProcessingService.applyResize(
              image: decoded,
              options: jpgOptions,
            );
            return imageProcessingService.encode(resized, jpgOptions);
          })();

      final mem = pw.MemoryImage(jpgBytes);
      pdf.addPage(pw.Page(build: (context) => pw.Center(child: pw.Image(mem))));
    }

    return pdf.save();
  }
}
