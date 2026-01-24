import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../services/gallery_save_service.dart';
import '../services/output_storage_service.dart';

class ResultFolderScreen extends StatefulWidget {
  const ResultFolderScreen({super.key});

  static const Color _bg = Color(0xFF1B1E23);

  @override
  State<ResultFolderScreen> createState() => _ResultFolderScreenState();
}

class _ResultFolderScreenState extends State<ResultFolderScreen> {
  final OutputStorageService _outputStorageService =
      const OutputStorageService();
  final GallerySaveService _gallerySaveService = const GallerySaveService();

  static const Color _card = Color(0xFF2B2940);
  static const Color _gold = Color(0xFFE2C078);

  bool _loading = true;
  List<_OutputItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
    });

    try {
      final entities = await _outputStorageService.listOutputs();
      final items = <_OutputItem>[];
      for (final e in entities) {
        final stat = await e.stat();
        final name = e.uri.pathSegments.isEmpty
            ? e.path
            : e.uri.pathSegments.last;
        items.add(
          _OutputItem(
            path: e.path,
            name: name,
            bytes: stat.size,
            modified: stat.modified,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = const [];
      });
    }
  }

  String _bytesLabel(int bytes) {
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  IconData _iconForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (lower.endsWith('.png')) return Icons.image;
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return Icons.image;
    if (lower.endsWith('.webp')) return Icons.image;
    if (lower.endsWith('.gif')) return Icons.gif_box;
    if (lower.endsWith('.bmp')) return Icons.image;
    return Icons.insert_drive_file;
  }

  Future<void> _open(_OutputItem item) async {
    await OpenFilex.open(item.path);
  }

  Future<void> _share(_OutputItem item) async {
    await Share.shareXFiles([XFile(item.path)]);
  }

  Future<void> _downloadToPhone(_OutputItem item) async {
    final ok = await _gallerySaveService.saveFile(filePath: item.path);
    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to phone (Gallery).')),
      );
      return;
    }

    final lower = item.name.toLowerCase();
    final isPdf = lower.endsWith('.pdf');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isPdf
              ? 'PDF is saved in Result Folder. Gallery save supports images only.'
              : 'Failed to save to Gallery. Please allow storage/photos permission.',
        ),
      ),
    );
  }

  Future<void> _delete(_OutputItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0x38E2C078)),
        ),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
        contentTextStyle: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        title: const Text('Delete file?'),
        content: Text(item.name),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF4D4D),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await File(item.path).delete();
    } catch (_) {}

    await _refresh();
  }

  PopupMenuItem<String> _menuItem({
    required String value,
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final c = color ?? _gold;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: c, size: 18),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ResultFolderScreen._bg,
      appBar: AppBar(
        backgroundColor: ResultFolderScreen._bg,
        foregroundColor: Colors.white,
        title: const Text('Result Folder'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Your exports are saved here inside the app.\nAlso saved to Gallery: Pictures/ImageConverter',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFE2C078),
                    ),
                  ),
                ),
              )
            else if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(
                  child: Text(
                    'No files yet.',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ),
              )
            else
              ..._items.map(
                (item) => Card(
                  color: _card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0x38E2C078)),
                  ),
                  child: ListTile(
                    onTap: () => _open(item),
                    leading: Icon(
                      _iconForName(item.name),
                      color: const Color(0xFFE2C078),
                    ),
                    title: Text(
                      item.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${_bytesLabel(item.bytes)}  •  ${item.modified}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: _gold),
                      color: _card,
                      elevation: 12,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: Color(0x38E2C078)),
                      ),
                      onSelected: (v) async {
                        if (v == 'open') await _open(item);
                        if (v == 'download') await _downloadToPhone(item);
                        if (v == 'share') await _share(item);
                        if (v == 'delete') await _delete(item);
                      },
                      itemBuilder: (context) => [
                        _menuItem(
                          value: 'open',
                          icon: Icons.open_in_new,
                          label: 'Open',
                        ),
                        _menuItem(
                          value: 'download',
                          icon: Icons.download,
                          label: 'Download to Phone',
                        ),
                        _menuItem(
                          value: 'share',
                          icon: Icons.share,
                          label: 'Share',
                        ),
                        _menuItem(
                          value: 'delete',
                          icon: Icons.delete_outline,
                          label: 'Delete',
                          color: const Color(0xFFFF6B6B),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OutputItem {
  const _OutputItem({
    required this.path,
    required this.name,
    required this.bytes,
    required this.modified,
  });

  final String path;
  final String name;
  final int bytes;
  final DateTime modified;
}
