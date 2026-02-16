import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../language/report_bugs_screen_language.dart';

class ReportBugsScreen extends StatefulWidget {
  const ReportBugsScreen({super.key});

  static const Color bg = Color(0xFF1B1E23);
  static const Color card = Color(0xFF2B2940);
  static const Color gold = Color(0xFFE2C078);

  @override
  State<ReportBugsScreen> createState() => _ReportBugsScreenState();
}

class _ReportBugsScreenState extends State<ReportBugsScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();
  final TextEditingController _stepsController = TextEditingController();

  bool _submitting = false;
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _appVersion = '${info.version}+${info.buildNumber}';
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() => _submitting = true);

    try {
      final title = _titleController.text.trim();
      final details = _detailsController.text.trim();
      final steps = _stepsController.text.trim();

      final version = _appVersion ?? 'unknown';
      final os = kIsWeb ? 'web' : 'android/ios';
      final osVersion = kIsWeb ? 'web' : '';

      final subject = title.isEmpty ? 'Bug Report' : 'Bug Report: $title';

      final body = <String>[
        'Bug details:',
        details,
        '',
        'Steps to reproduce:',
        steps.isEmpty ? '-' : steps,
        '',
        '---',
        'App version: $version',
        'OS: $os',
        if (osVersion.isNotEmpty) 'OS version: $osVersion',
      ].join('\n');

      final uri = Uri(
        scheme: 'mailto',
        path: 'imagefileconverter@gmail.com',
        queryParameters: <String, String>{'subject': subject, 'body': body},
      );

      bool launched = false;
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        launched = false;
      }

      if (!launched) {
        await Clipboard.setData(ClipboardData(text: body));
        if (!mounted) return;
        final code = Localizations.localeOf(context).languageCode;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ReportBugsScreenLanguage.getUnableToOpenEmail(code)),
          ),
        );
        return;
      }

      if (!mounted) return;
      final code = Localizations.localeOf(context).languageCode;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ReportBugsScreenLanguage.getEmailOpened(code))),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: const Color(0xFF1F1D2F),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0x38E2C078)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ReportBugsScreen.gold, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return Scaffold(
      backgroundColor: ReportBugsScreen.bg,
      appBar: AppBar(
        backgroundColor: ReportBugsScreen.bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          ReportBugsScreenLanguage.getReportBugs(code),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          children: [
            Container(
              decoration: BoxDecoration(
                color: ReportBugsScreen.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x38E2C078)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ReportBugsScreenLanguage.getTellUsWhatWentWrong(code),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _appVersion == null
                            ? ReportBugsScreenLanguage.getReportSentToEmail(
                                code,
                              )
                            : '${ReportBugsScreenLanguage.getReportSentToEmail(code)} (v$_appVersion)',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _titleController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: _inputDecoration(
                          ReportBugsScreenLanguage.getShortTitleOptional(code),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _detailsController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        minLines: 4,
                        maxLines: 8,
                        decoration: _inputDecoration(
                          ReportBugsScreenLanguage.getWhatHappened(code),
                        ),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty)
                            return ReportBugsScreenLanguage.getDescribeIssue(
                              code,
                            );
                          if (t.length < 8)
                            return ReportBugsScreenLanguage.getAddMoreDetails(
                              code,
                            );
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _stepsController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        minLines: 3,
                        maxLines: 7,
                        decoration: _inputDecoration(
                          ReportBugsScreenLanguage.getStepsToReproduce(code),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ReportBugsScreen.gold,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                          label: Text(
                            _submitting
                                ? ReportBugsScreenLanguage.getOpeningEmail(code)
                                : ReportBugsScreenLanguage.getSubmit(code),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
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
