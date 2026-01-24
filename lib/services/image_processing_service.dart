import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import 'models.dart';

Uint8List _pureDartEncodeFromSource(Map<String, Object?> args) {
  final bytes = args['bytes'] as Uint8List;
  final compressEnabled = (args['compressEnabled'] as bool?) ?? true;
  final quality = (args['quality'] as int?) ?? 80;
  final resizeEnabled = (args['resizeEnabled'] as bool?) ?? false;
  final resizeWidth = args['resizeWidth'] as int?;
  final resizeHeight = args['resizeHeight'] as int?;
  final formatIndex = (args['format'] as int?) ?? 0;
  final safeIndex = formatIndex.clamp(0, OutputFormat.values.length - 1);
  final format = OutputFormat.values[safeIndex];

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('Invalid image');
  }

  img.Image outImage = decoded;
  if (resizeEnabled && resizeWidth != null && resizeHeight != null) {
    outImage = img.copyResize(
      outImage,
      width: resizeWidth,
      height: resizeHeight,
    );
  }

  final q = compressEnabled ? quality.clamp(1, 100) : 100;

  switch (format) {
    case OutputFormat.jpg:
    case OutputFormat.jpeg:
      return Uint8List.fromList(img.encodeJpg(outImage, quality: q));
    case OutputFormat.png:
      return Uint8List.fromList(img.encodePng(outImage));
    case OutputFormat.gif:
      return Uint8List.fromList(img.encodeGif(outImage));
    case OutputFormat.bmp:
      return Uint8List.fromList(img.encodeBmp(outImage));
    case OutputFormat.webp:
      return Uint8List.fromList(img.encodePng(outImage));
    case OutputFormat.pdf:
      return Uint8List.fromList(img.encodeJpg(outImage, quality: q));
  }
}

Map<String, Object?> _pureDartPreviewFromSource(Map<String, Object?> args) {
  final bytes = args['bytes'] as Uint8List;
  final compressEnabled = (args['compressEnabled'] as bool?) ?? true;
  final quality = (args['quality'] as int?) ?? 80;
  final resizeEnabled = (args['resizeEnabled'] as bool?) ?? false;
  final resizeWidth = args['resizeWidth'] as int?;
  final resizeHeight = args['resizeHeight'] as int?;
  final formatIndex = (args['format'] as int?) ?? 0;
  final safeIndex = formatIndex.clamp(0, OutputFormat.values.length - 1);
  final format = OutputFormat.values[safeIndex];

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('Invalid image');
  }

  img.Image outImage = decoded;
  if (resizeEnabled && resizeWidth != null && resizeHeight != null) {
    outImage = img.copyResize(
      outImage,
      width: resizeWidth,
      height: resizeHeight,
    );
  }

  final q = compressEnabled ? quality.clamp(1, 100) : 100;

  Uint8List outBytes;
  switch (format) {
    case OutputFormat.jpg:
    case OutputFormat.jpeg:
      outBytes = Uint8List.fromList(img.encodeJpg(outImage, quality: q));
      break;
    case OutputFormat.png:
      outBytes = Uint8List.fromList(img.encodePng(outImage));
      break;
    case OutputFormat.gif:
      outBytes = Uint8List.fromList(img.encodeGif(outImage));
      break;
    case OutputFormat.bmp:
      outBytes = Uint8List.fromList(img.encodeBmp(outImage));
      break;
    case OutputFormat.webp:
      outBytes = Uint8List.fromList(img.encodePng(outImage));
      break;
    case OutputFormat.pdf:
      outBytes = Uint8List.fromList(img.encodeJpg(outImage, quality: q));
      break;
  }

  return <String, Object?>{
    'bytes': outBytes,
    'width': outImage.width,
    'height': outImage.height,
  };
}

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

    return compute(_pureDartEncodeFromSource, <String, Object?>{
      'bytes': sourceBytes,
      'compressEnabled': options.compressEnabled,
      'quality': options.quality,
      'resizeEnabled': options.resizeEnabled,
      'resizeWidth': options.resizeWidth,
      'resizeHeight': options.resizeHeight,
      'format': options.format.index,
    });
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

    final out = await compute(_pureDartPreviewFromSource, <String, Object?>{
      'bytes': input.bytes,
      'compressEnabled': options.compressEnabled,
      'quality': options.quality,
      'resizeEnabled': options.resizeEnabled,
      'resizeWidth': options.resizeWidth,
      'resizeHeight': options.resizeHeight,
      'format': options.format.index,
    });

    return ProcessedImage(
      bytes: out['bytes'] as Uint8List,
      width: out['width'] as int,
      height: out['height'] as int,
    );
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
