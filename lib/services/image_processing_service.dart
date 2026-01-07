import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import 'models.dart';

class ImageProcessingService {
  const ImageProcessingService();

  CompressFormat? _compressFormatFor(OutputFormat f) {
    switch (f) {
      case OutputFormat.jpg:
      case OutputFormat.jpeg:
        return CompressFormat.jpeg;
      case OutputFormat.png:
        return CompressFormat.png;
      case OutputFormat.webp:
        return CompressFormat.webp;
      case OutputFormat.gif:
      case OutputFormat.bmp:
      case OutputFormat.pdf:
        return null;
    }
  }

  img.Image decode(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Invalid image');
    }
    return decoded;
  }

  Future<Uint8List?> encodeFromSourceBytesPreservingExif({
    required Uint8List sourceBytes,
    required ImageProcessOptions options,
  }) async {
    if (kIsWeb) return null;
    if (!options.keepExif) return null;

    final format = _compressFormatFor(options.format);
    if (format == null) return null;

    final q = effectiveQuality(options);
    final targetW = options.resizeEnabled ? (options.resizeWidth ?? 0) : 0;
    final targetH = options.resizeEnabled ? (options.resizeHeight ?? 0) : 0;
    return FlutterImageCompress.compressWithList(
      sourceBytes,
      format: format,
      quality: q,
      minWidth: targetW,
      minHeight: targetH,
      keepExif: true,
    );
  }

  Future<Uint8List> encodeFromSourceBytes({
    required Uint8List sourceBytes,
    required ImageProcessOptions options,
  }) async {
    if (!kIsWeb) {
      final format = _compressFormatFor(options.format);
      if (format != null) {
        try {
          final targetW = options.resizeEnabled
              ? (options.resizeWidth ?? 0)
              : 0;
          final targetH = options.resizeEnabled
              ? (options.resizeHeight ?? 0)
              : 0;
          final q = effectiveQuality(options);
          final out = await FlutterImageCompress.compressWithList(
            sourceBytes,
            format: format,
            quality: q,
            minWidth: targetW,
            minHeight: targetH,
            keepExif: options.keepExif,
          );
          if (out.isNotEmpty) {
            return out;
          }
        } catch (_) {
          // Fall back to pure Dart encode below.
        }
      }
    }

    final decoded = decode(sourceBytes);
    final resized = applyResize(image: decoded, options: options);
    return encode(resized, options);
  }

  img.Image applyResize({
    required img.Image image,
    required ImageProcessOptions options,
  }) {
    if (!options.resizeEnabled) return image;
    final w = options.resizeWidth;
    final h = options.resizeHeight;
    if (w == null || h == null) return image;
    return img.copyResize(image, width: w, height: h);
  }

  int effectiveQuality(ImageProcessOptions options) {
    if (!options.compressEnabled) return 100;
    return options.quality.clamp(1, 100);
  }

  Future<ProcessedImage> processForPreview({
    required SelectedImage input,
    required ImageProcessOptions options,
  }) async {
    if (!kIsWeb) {
      final format = _compressFormatFor(options.format);
      if (format != null) {
        try {
          final targetW = options.resizeEnabled
              ? (options.resizeWidth ?? 0)
              : 0;
          final targetH = options.resizeEnabled
              ? (options.resizeHeight ?? 0)
              : 0;
          final q = effectiveQuality(options);

          final out = await FlutterImageCompress.compressWithList(
            input.bytes,
            format: format,
            quality: q,
            minWidth: targetW,
            minHeight: targetH,
            keepExif: false,
          );

          if (out.isNotEmpty) {
            return ProcessedImage(
              bytes: out,
              width: options.resizeEnabled ? options.resizeWidth : null,
              height: options.resizeEnabled ? options.resizeHeight : null,
            );
          }
        } catch (_) {
          // Fall back to pure Dart preview below.
        }
      }
    }

    final decoded = decode(input.bytes);
    return processDecodedForPreview(decoded: decoded, options: options);
  }

  Future<ProcessedImage> processDecodedForPreview({
    required img.Image decoded,
    required ImageProcessOptions options,
  }) async {
    final resized = applyResize(image: decoded, options: options);
    final bytes = await encode(resized, options);
    return ProcessedImage(
      bytes: bytes,
      width: resized.width,
      height: resized.height,
    );
  }

  Future<Uint8List> encode(img.Image image, ImageProcessOptions options) async {
    final q = effectiveQuality(options);

    switch (options.format) {
      case OutputFormat.jpg:
      case OutputFormat.jpeg:
        return Uint8List.fromList(img.encodeJpg(image, quality: q));
      case OutputFormat.png:
        return Uint8List.fromList(img.encodePng(image));
      case OutputFormat.gif:
        return Uint8List.fromList(img.encodeGif(image));
      case OutputFormat.bmp:
        return Uint8List.fromList(img.encodeBmp(image));
      case OutputFormat.webp:
        if (kIsWeb) {
          throw UnsupportedError('WEBP is not supported on web in this build');
        }
        final pngBytes = Uint8List.fromList(img.encodePng(image));
        try {
          final out = await FlutterImageCompress.compressWithList(
            pngBytes,
            format: CompressFormat.webp,
            quality: q,
            keepExif: options.keepExif,
          );
          if (out.isNotEmpty) {
            return out;
          }
        } catch (_) {}
        return pngBytes;
      case OutputFormat.pdf:
        return Uint8List.fromList(img.encodeJpg(image, quality: q));
    }
  }
}
