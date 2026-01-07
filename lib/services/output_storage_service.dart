import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class OutputStorageService {
  const OutputStorageService();

  Future<Directory> getOutputDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(dir.path, 'image_converter'));
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
    return outDir;
  }

  Future<File> saveBytes({
    required String fileName,
    required List<int> bytes,
  }) async {
    final outDir = await getOutputDirectory();
    final outPath = p.join(outDir.path, fileName);
    final file = File(outPath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<List<FileSystemEntity>> listOutputs() async {
    final outDir = await getOutputDirectory();
    final entities = await outDir.list().toList();
    entities.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return entities;
  }
}
