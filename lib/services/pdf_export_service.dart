import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

import 'image_processing_service.dart';
import 'models.dart';

class PdfExportService {
  const PdfExportService({required this.imageProcessingService});

  final ImageProcessingService imageProcessingService;

  Future<Uint8List> _encodeJpgForPdf({
    required Uint8List sourceBytes,
    required ImageProcessOptions options,
    required int maxSide,
  }) {
    return compute(_pdfEncodeJpgForPdf, <String, Object?>{
      'bytes': sourceBytes,
      'quality': options.quality,
      'resizeEnabled': options.resizeEnabled,
      'resizeWidth': options.resizeWidth,
      'resizeHeight': options.resizeHeight,
      'maxSide': maxSide,
    });
  }

  Future<Uint8List> encodeJpgForPdfPage({
    required SelectedImage image,
    required ImageProcessOptions options,
    int maxSide = 1400,
  }) {
    return _encodeJpgForPdf(
      sourceBytes: image.bytes,
      options: options,
      maxSide: maxSide,
    );
  }

  Future<Uint8List> buildPdfFromJpgBytes({
    required List<Uint8List> jpgBytesByPage,
  }) async {
    final pdf = pw.Document();
    for (var i = 0; i < jpgBytesByPage.length; i++) {
      final jpgBytes = jpgBytesByPage[i];
      final mem = pw.MemoryImage(jpgBytes);
      pdf.addPage(pw.Page(build: (context) => pw.Center(child: pw.Image(mem))));

      if (i % 3 == 2) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return pdf.save();
  }

  Future<Uint8List> buildPdfFromJpgBytesInIsolate({
    required List<Uint8List> jpgBytesByPage,
  }) {
    return compute(_pdfBuildFromJpgBytesIsolate, jpgBytesByPage);
  }

  Future<Uint8List> buildPdf({
    required List<SelectedImage> images,
    required ImageProcessOptions options,
    int maxSide = 1400,
  }) async {
    final jpgs = <Uint8List>[];
    for (final image in images) {
      jpgs.add(
        await encodeJpgForPdfPage(
          image: image,
          options: options,
          maxSide: maxSide,
        ),
      );
    }
    return buildPdfFromJpgBytes(jpgBytesByPage: jpgs);
  }

  Future<Uint8List> buildPdfPerPage({
    required List<SelectedImage> images,
    required List<ImageProcessOptions> optionsByPage,
    int maxSide = 1400,
  }) async {
    if (images.length != optionsByPage.length) {
      throw ArgumentError('images and optionsByPage must be same length');
    }

    final jpgs = <Uint8List>[];
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

      jpgs.add(
        await encodeJpgForPdfPage(
          image: image,
          options: jpgOptions,
          maxSide: maxSide,
        ),
      );
    }

    return buildPdfFromJpgBytes(jpgBytesByPage: jpgs);
  }
}

Uint8List _pdfEncodeJpgForPdf(Map<String, Object?> args) {
  final bytes = args['bytes'] as Uint8List;
  final quality = (args['quality'] as int?) ?? 80;
  final resizeEnabled = (args['resizeEnabled'] as bool?) ?? false;
  final resizeWidth = args['resizeWidth'] as int?;
  final resizeHeight = args['resizeHeight'] as int?;
  final maxSide = (args['maxSide'] as int?) ?? 1400;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('Unable to decode image');
  }

  var out = decoded;

  if (resizeEnabled && (resizeWidth != null || resizeHeight != null)) {
    final w0 = out.width;
    final h0 = out.height;
    int? w = resizeWidth;
    int? h = resizeHeight;
    if (w != null && (h == null || h <= 0)) {
      h = ((w * h0) / w0).round().clamp(1, 1000000);
    }
    if (h != null && (w == null || w <= 0)) {
      w = ((h * w0) / h0).round().clamp(1, 1000000);
    }
    if (w != null && h != null && w > 0 && h > 0) {
      out = img.copyResize(out, width: w, height: h);
    }
  }

  final w1 = out.width;
  final h1 = out.height;
  final maxCurrent = w1 > h1 ? w1 : h1;
  if (maxCurrent > maxSide) {
    final scale = maxSide / maxCurrent;
    final nextW = (w1 * scale).round().clamp(1, maxSide);
    final nextH = (h1 * scale).round().clamp(1, maxSide);
    out = img.copyResize(out, width: nextW, height: nextH);
  }

  final q = quality.clamp(10, 95);
  return Uint8List.fromList(img.encodeJpg(out, quality: q));
}

Future<Uint8List> _pdfBuildFromJpgBytesIsolate(List<Uint8List> payload) async {
  final pdf = pw.Document();
  for (final jpgBytes in payload) {
    final mem = pw.MemoryImage(jpgBytes);
    pdf.addPage(pw.Page(build: (context) => pw.Center(child: pw.Image(mem))));
  }
  return pdf.save();
}
