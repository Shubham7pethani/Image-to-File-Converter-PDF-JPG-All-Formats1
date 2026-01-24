import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_settings.dart';
import '../services/output_storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const Color bg = Color(0xFF1B1E23);
  static const Color card = Color(0xFF2B2940);
  static const Color gold = Color(0xFFE2C078);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _ComingSoonCard extends StatelessWidget {
  const _ComingSoonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SettingsScreen.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x38E2C078)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Coming Soon',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'New featured apps will appear here in future updates.',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsScreenState extends State<SettingsScreen> {
  final OutputStorageService _outputStorageService =
      const OutputStorageService();
  final AppSettings _settings = const AppSettings();

  bool _loading = true;
  bool _photoSpeedUp = false;
  bool _preventDuplicates = true;

  String? _versionLabel;
  String? _packageName;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _photoSpeedUp = prefs.getBool(AppSettings.prefPhotoSpeedUp) ?? false;
      _preventDuplicates =
          prefs.getBool(AppSettings.prefPreventDuplicates) ?? true;
      _versionLabel = 'v${info.version}+${info.buildNumber}';
      _packageName = info.packageName;
      _loading = false;
    });
  }

  Future<void> _setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _togglePhotoSpeedUp() async {
    final v = !_photoSpeedUp;
    setState(() => _photoSpeedUp = v);
    await _settings.setPhotoSpeedUp(v);
  }

  Future<void> _togglePreventDuplicates() async {
    final v = !_preventDuplicates;
    setState(() => _preventDuplicates = v);
    await _settings.setPreventDuplicates(v);
  }

  String _storeListingUrl() {
    final pkg = _packageName;
    if (pkg == null || pkg.isEmpty) {
      return 'https://play.google.com/store';
    }
    return 'https://play.google.com/store/apps/details?id=$pkg';
  }

  Future<void> _showSavedPath() async {
    final rootContext = context;
    final navigator = Navigator.of(rootContext);
    final messenger = ScaffoldMessenger.of(rootContext);

    final dir = await _outputStorageService.getOutputDirectory();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: SettingsScreen.card,
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
          title: const Text('Saved Path'),
          content: SelectableText(dir.path),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: dir.path));
                if (!mounted) return;
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Path copied')),
                );
              },
              child: const Text('Copy'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: SettingsScreen.gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                navigator.pop();
                navigator.pushNamed('/results');
              },
              child: const Text('Open'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _clearExportPaths() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SettingsScreen.card,
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
        title: const Text('Clear Result Folder?'),
        content: const Text('This will delete all saved images and PDFs.'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: SettingsScreen.gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final items = await _outputStorageService.listOutputs();
      var deleted = 0;
      for (final e in items) {
        try {
          await e.delete();
          deleted++;
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Deleted $deleted file(s)')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to clear files.')));
    }
  }

  Future<void> _resetDefaults() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SettingsScreen.card,
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
        title: const Text('Reset to default?'),
        content: const Text('This will reset settings to default values.'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: SettingsScreen.gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await _setBool(AppSettings.prefPhotoSpeedUp, false);
    await _setBool(AppSettings.prefPreventDuplicates, true);

    if (!mounted) return;
    setState(() {
      _photoSpeedUp = false;
      _preventDuplicates = true;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Defaults restored')));
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot open link on this device.')),
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _shareApp() async {
    await Share.share(
      'Image to File Converter – PDF, JPG & All Formats\n${_storeListingUrl()}',
    );
  }

  Future<void> _showMoreAppsComingSoon() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SettingsScreen.card,
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
        title: const Text('Coming Soon'),
        content: const Text('More apps will be available in the next version.'),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: SettingsScreen.gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SettingsScreen.bg,
      appBar: AppBar(
        backgroundColor: SettingsScreen.bg,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(SettingsScreen.gold),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                const _SectionHeader(title: 'Tools Related'),
                _SettingsCard(
                  children: [
                    _SettingsTile(
                      icon: Icons.save_outlined,
                      title: 'Saved Path',
                      onTap: _showSavedPath,
                    ),
                    _SettingsTile(
                      icon: Icons.speed,
                      title: 'Photo Speed Up',
                      onTap: _togglePhotoSpeedUp,
                      trailing: Switch(
                        value: _photoSpeedUp,
                        activeThumbColor: SettingsScreen.gold,
                        onChanged: (v) async {
                          setState(() => _photoSpeedUp = v);
                          await _settings.setPhotoSpeedUp(v);
                        },
                      ),
                    ),
                    _SettingsTile(
                      icon: Icons.delete_outline,
                      title: 'Clear Export Paths',
                      onTap: _clearExportPaths,
                    ),
                    _SettingsTile(
                      icon: Icons.copy_all_outlined,
                      title: 'Prevent Duplicate Photos',
                      onTap: _togglePreventDuplicates,
                      trailing: Switch(
                        value: _preventDuplicates,
                        activeThumbColor: SettingsScreen.gold,
                        onChanged: (v) async {
                          setState(() => _preventDuplicates = v);
                          await _settings.setPreventDuplicates(v);
                        },
                      ),
                    ),
                    _SettingsTile(
                      icon: Icons.settings_backup_restore,
                      title: 'Default Configurations',
                      onTap: _resetDefaults,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const _SectionHeader(title: 'Feature App'),
                _ComingSoonCard(),
                const SizedBox(height: 16),
                const _SectionHeader(title: 'App Related'),
                _SettingsCard(
                  children: [
                    _SettingsTile(
                      icon: Icons.bug_report_outlined,
                      title: 'Report bugs',
                      onTap: () {
                        Navigator.of(context).pushNamed('/report-bugs');
                      },
                    ),
                    _SettingsTile(
                      icon: Icons.share_outlined,
                      title: 'Share',
                      onTap: _shareApp,
                    ),
                    _SettingsTile(
                      icon: Icons.thumb_up_outlined,
                      title: 'Rate Us',
                      onTap: () async {
                        await _openUrl(_storeListingUrl());
                      },
                    ),
                    _SettingsTile(
                      icon: Icons.contact_support_outlined,
                      title: 'Contact us',
                      onTap: () async {
                        await _openUrl('mailto:imagefileconverter@gmail.com');
                      },
                    ),
                    _SettingsTile(
                      icon: Icons.apps_outlined,
                      title: 'More apps',
                      onTap: _showMoreAppsComingSoon,
                    ),
                    _SettingsTile(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy Policy',
                      onTap: () {
                        Navigator.of(context).pushNamed('/privacy-policy');
                      },
                    ),
                  ],
                ),
                if (_versionLabel != null) ...[
                  const SizedBox(height: 18),
                  Center(
                    child: Text(
                      _versionLabel!,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Text(
        title,
        style: const TextStyle(
          color: SettingsScreen.gold,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2B2940),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x38E2C078)),
      ),
      child: Column(children: _withDividers(children)),
    );
  }

  List<Widget> _withDividers(List<Widget> children) {
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      out.add(children[i]);
      if (i != children.length - 1) {
        out.add(const Divider(height: 1, color: Colors.white12));
      }
    }
    return out;
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: Colors.white70),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
