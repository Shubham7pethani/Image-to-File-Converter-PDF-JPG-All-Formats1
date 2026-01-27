import 'dart:typed_data';

enum OutputFormat { jpg, jpeg, png, webp, gif, bmp, pdf }

class SelectedImage {
  const SelectedImage({required this.name, required this.bytes});

  final String name;

  final Uint8List bytes;
}

class ImageProcessOptions {
  const ImageProcessOptions({
    required this.compressEnabled,
    required this.quality,
    required this.resizeEnabled,
    required this.resizeWidth,
    required this.resizeHeight,
    required this.keepExif,
    required this.format,
  });

  final bool compressEnabled;
  final int quality;

  final bool resizeEnabled;
  final int? resizeWidth;
  final int? resizeHeight;

  final bool keepExif;
  final OutputFormat format;
}

class ProcessedImage {
  const ProcessedImage({required this.bytes, this.width, this.height});

  final Uint8List bytes;
  final int? width;
  final int? height;
}
