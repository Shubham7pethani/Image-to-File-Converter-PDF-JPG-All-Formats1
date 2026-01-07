import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:saver_gallery/saver_gallery.dart';

class GallerySaveService {
  const GallerySaveService();

  bool _isImageFileName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp');
  }

  Future<bool> saveImage({
    required Uint8List bytes,
    required String name,
  }) async {
    if (kIsWeb) return false;

    if (!_isImageFileName(name)) {
      return false;
    }

    try {
      final result = await SaverGallery.saveImage(
        bytes,
        quality: 100,
        fileName: name,
        androidRelativePath: 'Pictures/ImageConverter',
        skipIfExists: false,
      );

      return _isSuccess(result);
    } catch (_) {
      return false;
    }
  }

  Future<bool> saveFile({required String filePath}) async {
    if (kIsWeb) return false;

    final fileName = filePath.split(RegExp(r'[\\/]')).last;

    if (!_isImageFileName(fileName)) {
      return false;
    }

    try {
      final result = await SaverGallery.saveFile(
        filePath: filePath,
        fileName: fileName,
        androidRelativePath: 'Pictures/ImageConverter',
        skipIfExists: false,
      );
      return _isSuccess(result);
    } catch (_) {
      return false;
    }
  }

  bool _isSuccess(dynamic result) {
    if (result is SaveResult) {
      return result.isSuccess;
    }
    return result == true;
  }
}
