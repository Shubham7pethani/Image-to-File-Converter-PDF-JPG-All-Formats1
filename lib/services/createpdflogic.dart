import 'models.dart';

class PdfPageState {
  PdfPageState({
    required this.compressEnabled,
    required this.quality,
    required this.resizeEnabled,
    required this.resizeWidth,
    required this.resizeHeight,
    required this.keepExif,
    required this.done,
  });

  bool compressEnabled;
  double quality;

  bool resizeEnabled;
  int? resizeWidth;
  int? resizeHeight;

  bool keepExif;

  bool done;

  int qualityInt() {
    if (!compressEnabled) return 100;
    return quality.round().clamp(1, 100);
  }
}

class CreatePdfLogic {
  CreatePdfLogic({required List<SelectedImage> images})
    : pages = List<SelectedImage>.from(images),
      states = List<PdfPageState>.generate(images.length, (i) {
        return PdfPageState(
          compressEnabled: true,
          quality: 80,
          resizeEnabled: false,
          resizeWidth: null,
          resizeHeight: null,
          keepExif: false,
          done: false,
        );
      });

  final List<SelectedImage> pages;
  final List<PdfPageState> states;

  void removeAt(int index) {
    if (index < 0 || index >= pages.length) return;
    pages.removeAt(index);
    states.removeAt(index);
  }

  void move(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= pages.length) return;
    if (newIndex < 0 || newIndex >= pages.length) return;

    final page = pages.removeAt(oldIndex);
    final state = states.removeAt(oldIndex);

    pages.insert(newIndex, page);
    states.insert(newIndex, state);
  }

  bool get allDone {
    return states.isNotEmpty && states.every((s) => s.done);
  }
}
