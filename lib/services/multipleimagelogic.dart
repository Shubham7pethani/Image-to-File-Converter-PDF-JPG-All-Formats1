import 'package:flutter/foundation.dart';
import 'models.dart';

class MultiImageItemState {
  MultiImageItemState({
    required this.compressEnabled,
    required this.quality,
    required this.resizeEnabled,
    required this.resizeWidth,
    required this.resizeHeight,
    required this.keepExif,
    required this.useSameAsInput,
    required this.format,
  });

  bool compressEnabled;
  double quality;

  bool resizeEnabled;
  int? resizeWidth;
  int? resizeHeight;

  bool keepExif;

  bool useSameAsInput;
  OutputFormat format;

  int qualityInt() {
    if (!compressEnabled) return 100;
    return quality.round().clamp(1, 100);
  }
}

class MultipleImageLogic {
  MultipleImageLogic({required List<SelectedImage> images})
    : images = List<SelectedImage>.from(images),
      states = List<MultiImageItemState>.generate(images.length, (i) {
        debugPrint(
          'MultipleImageLogic: Processing image ${i + 1}/${images.length}',
        );
        final input = _detectInputFormat(images[i].name);
        return MultiImageItemState(
          compressEnabled: true,
          quality: 80,
          resizeEnabled: false,
          resizeWidth: null,
          resizeHeight: null,
          keepExif: false,
          useSameAsInput: true,
          format: input,
        );
      }) {
    debugPrint(
      'MultipleImageLogic: Created with ${this.images.length} images and ${states.length} states',
    );
  }

  final List<SelectedImage> images;
  final List<MultiImageItemState> states;

  void removeAt(int index) {
    if (index < 0 || index >= images.length) return;
    images.removeAt(index);
    states.removeAt(index);
  }

  OutputFormat effectiveFormatForIndex(int index) {
    if (index < 0 || index >= images.length) {
      return OutputFormat.jpg;
    }
    final choice = states[index];
    if (choice.useSameAsInput) {
      return _detectInputFormat(images[index].name);
    }
    return choice.format;
  }

  static OutputFormat _detectInputFormat(String name) {
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
}
