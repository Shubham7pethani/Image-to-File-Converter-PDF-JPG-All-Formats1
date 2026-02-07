import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pdfx/pdfx.dart';

class PdfBackgroundService {
  PdfBackgroundService();

  final ValueNotifier<Object?> pdfError = ValueNotifier<Object?>(null);
  final ValueNotifier<int> pagesCount = ValueNotifier<int>(0);
  final ValueNotifier<int> currentPage = ValueNotifier<int>(1);

  int _warmUpGeneration = 0;

  void onDocumentLoaded(PdfDocument document) {
    pdfError.value = null;
    pagesCount.value = document.pagesCount;
    currentPage.value = 1;
  }

  void onPageChanged(int page) {
    currentPage.value = page;
  }

  void onDocumentError(Object error) {
    pdfError.value = error;
  }

  Future<void> warmUpFromPath(
    String path, {
    int maxPages = 3,
    Duration delayBetweenPages = const Duration(milliseconds: 80),
  }) async {
    if (path.isEmpty) return;

    final gen = ++_warmUpGeneration;
    PdfDocument? doc;

    try {
      doc = await PdfDocument.openFile(path);

      final count = pagesCount.value;
      final toWarm = math.min(count, math.max(0, maxPages));

      for (var pageNumber = 1; pageNumber <= toWarm; pageNumber++) {
        if (gen != _warmUpGeneration) return;

        final page = await doc.getPage(pageNumber);
        await page.close();

        await Future<void>.delayed(delayBetweenPages);
      }
    } catch (_) {
      return;
    } finally {
      try {
        await doc?.close();
      } catch (_) {}
    }
  }

  void cancelWarmUp() {
    _warmUpGeneration++;
  }

  void dispose() {
    cancelWarmUp();
    pdfError.dispose();
    pagesCount.dispose();
    currentPage.dispose();
  }
}
