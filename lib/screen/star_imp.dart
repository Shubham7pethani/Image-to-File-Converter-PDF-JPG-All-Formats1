import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../language/star_imp_screen_language.dart';
import '../services/branded_share_service.dart';
import '../services/gallery_save_service.dart';
import '../services/important_service.dart';
import '../services/output_storage_service.dart';

class StarImpScreen extends StatefulWidget {
  const StarImpScreen({super.key});

  static const Color _bg = Color(0xFF1B1E23);
  static const Color _card = Color(0xFF2B2940);
  static const Color _gold = Color(0xFFE2C078);

  @override
  State<StarImpScreen> createState() => _StarImpScreenState();
}

class _StarImpScreenState extends State<StarImpScreen> {
  final OutputStorageService _outputStorageService =
      const OutputStorageService();
  final GallerySaveService _gallerySaveService = const GallerySaveService();
  final ImportantService _importantService = const ImportantService();
  final BrandedShareService _brandedShareService = const BrandedShareService();

  bool _loading = true;
  List<_ImpItem> _items = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
    });

    try {
      final important = await _importantService.getPaths();
      final entities = await _outputStorageService.listOutputs();

      final items = <_ImpItem>[];
      for (final e in entities) {
        if (!important.contains(e.path)) continue;
        final stat = await e.stat();
        final name = e.uri.pathSegments.isEmpty
            ? e.path
            : e.uri.pathSegments.last;
        items.add(
          _ImpItem(
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
        _items = const [];
        _loading = false;
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

  Future<void> _open(_ImpItem item) async {
    await OpenFilex.open(item.path);
  }

  Future<void> _share(_ImpItem item) async {
    await _brandedShareService.shareFile(filePath: item.path);
  }

  Future<void> _downloadToPhone(_ImpItem item) async {
    final code = Localizations.localeOf(context).languageCode;
    final ok = await _gallerySaveService.saveFile(filePath: item.path);
    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(StarImpScreenLanguage.getSavedToPhoneGallery(code)),
        ),
      );
      return;
    }

    final lower = item.name.toLowerCase();
    final isPdf = lower.endsWith('.pdf');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isPdf
              ? StarImpScreenLanguage.getPdfSavedFolder(code)
              : StarImpScreenLanguage.getFailedToSaveToGallery(code),
        ),
      ),
    );
  }

  Future<void> _removeImportant(_ImpItem item) async {
    await _importantService.remove(item.path);
    await _refresh();
  }

  Future<void> _delete(_ImpItem item) async {
    final code = Localizations.localeOf(context).languageCode;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: StarImpScreen._card,
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
        title: Text(StarImpScreenLanguage.getDeleteFile(code)),
        content: Text(item.name),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(StarImpScreenLanguage.getCancel(code)),
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
            label: Text(StarImpScreenLanguage.getDelete(code)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await File(item.path).delete();
    } catch (_) {}

    await _importantService.remove(item.path);
    await _refresh();
  }

  PopupMenuItem<String> _menuItem({
    required String value,
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final c = color ?? StarImpScreen._gold;
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
    final code = Localizations.localeOf(context).languageCode;
    return Scaffold(
      backgroundColor: StarImpScreen._bg,
      appBar: AppBar(
        backgroundColor: StarImpScreen._bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          StarImpScreenLanguage.getImportant(code),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
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
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Center(
                  child: Text(
                    StarImpScreenLanguage.getNoImportantFiles(code),
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ),
              )
            else
              ..._items.map(
                (item) => Card(
                  color: StarImpScreen._card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0x38E2C078)),
                  ),
                  child: ListTile(
                    onTap: () => _open(item),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    minVerticalPadding: 0,
                    minLeadingWidth: 48,
                    horizontalTitleGap: 12,
                    titleAlignment: ListTileTitleAlignment.center,
                    leading: SizedBox(
                      width: 42,
                      height: 42,
                      child: Center(
                        child: Transform.translate(
                          offset: const Offset(0, 2),
                          child: Icon(
                            _iconForName(item.name),
                            color: const Color(0xFFE2C078),
                            size: 32,
                          ),
                        ),
                      ),
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
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _removeImportant(item),
                          icon: const Icon(Icons.workspace_premium),
                          color: StarImpScreen._gold,
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.more_vert,
                            color: StarImpScreen._gold,
                          ),
                          color: StarImpScreen._card,
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
                              label: StarImpScreenLanguage.getOpen(code),
                            ),
                            _menuItem(
                              value: 'download',
                              icon: Icons.download,
                              label: StarImpScreenLanguage.getDownloadToPhone(
                                code,
                              ),
                            ),
                            _menuItem(
                              value: 'share',
                              icon: Icons.share,
                              label: StarImpScreenLanguage.getShare(code),
                            ),
                            _menuItem(
                              value: 'delete',
                              icon: Icons.delete_outline,
                              label: StarImpScreenLanguage.getDelete(code),
                              color: const Color(0xFFFF6B6B),
                            ),
                          ],
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

class _ImpItem {
  const _ImpItem({
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
