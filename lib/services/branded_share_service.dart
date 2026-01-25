import 'dart:io';
import 'dart:async';

import 'package:share_plus/share_plus.dart';


class BrandedShareService {
  const BrandedShareService();

  static const String _packageName = 'com.sholo.imageconverter';
  static const String _appName =
      'Image to File Converter – PDF, JPG & All Formats';

  String _storeUrl() {
    return 'https://play.google.com/store/apps/details?id=$_packageName';
  }

  String _fileTypeLabel(String filePath) {
    try {
      final name = File(filePath).uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      if (dot <= 0 || dot >= name.length - 1) return 'file';
      return name.substring(dot + 1).toUpperCase();
    } catch (_) {
      return 'file';
    }
  }

  String buildCaption({required String filePath}) {
    final type = _fileTypeLabel(filePath);
    return 'This $type was converted by $_appName\nTo open: tap the file → Open with → Image Converter\nIf not installed, download: ${_storeUrl()}';
  }

  Future<void> shareFile({required String filePath}) async {
    final f = File(filePath);
    if (!await f.exists()) return;

    final lower = filePath.toLowerCase().trim();
    final isPdf = lower.endsWith('.pdf');
    final caption = buildCaption(filePath: filePath);

    if (isPdf) {
      await Share.shareXFiles([XFile(filePath)]);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await Share.share(caption);
      return;
    }

    await Share.shareXFiles([XFile(filePath)], text: caption);
  }
}
