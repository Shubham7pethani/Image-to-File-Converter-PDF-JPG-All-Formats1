import 'package:flutter/material.dart';
import '../language/language_selection_screen_language.dart';
import '../main.dart';
import '../services/app_settings.dart';

class LanguageSelectionScreen extends StatelessWidget {
  const LanguageSelectionScreen({super.key});

  static const Color bg = Color(0xFF1B1E23);
  static const Color card = Color(0xFF2B2940);
  static const Color gold = Color(0xFFE2C078);

  @override
  Widget build(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    final currentLocale = Localizations.localeOf(context);
    final AppSettings settings = const AppSettings();

    final List<Map<String, String>> languages = [
      {
        'code': 'en',
        'name': 'English',
        'englishName': 'English',
        'flag': '🇺🇸',
      },
      {'code': 'hi', 'name': 'हिंदी', 'englishName': 'Hindi', 'flag': '🇮🇳'},
      {
        'code': 'es',
        'name': 'Español',
        'englishName': 'Spanish',
        'flag': '🇪🇸',
      },
      {'code': 'ps', 'name': 'پښتو', 'englishName': 'Pashto', 'flag': '🇦🇫'},
      {
        'code': 'fil',
        'name': 'Filipino',
        'englishName': 'Filipino',
        'flag': '🇵🇭',
      },
      {
        'code': 'id',
        'name': 'Indonesia',
        'englishName': 'Indonesian',
        'flag': '🇮🇩',
      },
      {
        'code': 'my',
        'name': 'မြန်မာ',
        'englishName': 'Burmese',
        'flag': '🇲🇲',
      },
      {
        'code': 'ru',
        'name': 'Русский',
        'englishName': 'Russian',
        'flag': '🇷🇺',
      },
      {'code': 'fa', 'name': 'فارسی', 'englishName': 'Persian', 'flag': '🇮🇷'},
      {'code': 'bn', 'name': 'বাংলা', 'englishName': 'Bengali', 'flag': '🇧🇩'},
      {'code': 'mr', 'name': 'मराठी', 'englishName': 'Marathi', 'flag': '🇮🇳'},
      {'code': 'te', 'name': 'తెలుగు', 'englishName': 'Telugu', 'flag': '🇮🇳'},
      {'code': 'ta', 'name': 'தமிழ்', 'englishName': 'Tamil', 'flag': '🇮🇳'},
      {'code': 'ur', 'name': 'اردو', 'englishName': 'Urdu', 'flag': '🇵🇰'},
      {
        'code': 'ms',
        'name': 'Bahasa Melayu',
        'englishName': 'Malay',
        'flag': '🇲🇾',
      },
      {
        'code': 'pt',
        'name': 'Português',
        'englishName': 'Portuguese',
        'flag': '🇧🇷',
      },
      {
        'code': 'fr',
        'name': 'Français',
        'englishName': 'French',
        'flag': '🇫🇷',
      },
      {
        'code': 'de',
        'name': 'Deutsch',
        'englishName': 'German',
        'flag': '🇩🇪',
      },
      {
        'code': 'ar',
        'name': 'العربية',
        'englishName': 'Arabic',
        'flag': '🇸🇦',
      },
      {
        'code': 'tr',
        'name': 'Türkçe',
        'englishName': 'Turkish',
        'flag': '🇹🇷',
      },
      {
        'code': 'vi',
        'name': 'Tiếng Việt',
        'englishName': 'Vietnamese',
        'flag': '🇻🇳',
      },
      {'code': 'th', 'name': 'ไทย', 'englishName': 'Thai', 'flag': '🇹🇭'},
      {'code': 'ja', 'name': '日本語', 'englishName': 'Japanese', 'flag': '🇯🇵'},
      {'code': 'ko', 'name': '한국어', 'englishName': 'Korean', 'flag': '🇰🇷'},
      {
        'code': 'it',
        'name': 'Italiano',
        'englishName': 'Italian',
        'flag': '🇮🇹',
      },
      {'code': 'pl', 'name': 'Polski', 'englishName': 'Polish', 'flag': '🇵🇱'},
      {
        'code': 'uk',
        'name': 'Українська',
        'englishName': 'Ukrainian',
        'flag': '🇺🇦',
      },
      {
        'code': 'nl',
        'name': 'Nederlands',
        'englishName': 'Dutch',
        'flag': '🇳🇱',
      },
      {
        'code': 'ro',
        'name': 'Română',
        'englishName': 'Romanian',
        'flag': '🇷🇴',
      },
      {
        'code': 'el',
        'name': 'Ελληνικά',
        'englishName': 'Greek',
        'flag': '🇬🇷',
      },
      {'code': 'cs', 'name': 'Čeština', 'englishName': 'Czech', 'flag': '🇨🇿'},
      {
        'code': 'hu',
        'name': 'Magyar',
        'englishName': 'Hungarian',
        'flag': '🇭🇺',
      },
      {
        'code': 'sv',
        'name': 'Svenska',
        'englishName': 'Swedish',
        'flag': '🇸🇪',
      },
      {
        'code': 'zh',
        'name': '简体中文',
        'englishName': 'Chinese (Simplified)',
        'flag': '🇨🇳',
      },
      {'code': 'he', 'name': 'עברית', 'englishName': 'Hebrew', 'flag': '🇮🇱'},
      {'code': 'da', 'name': 'Dansk', 'englishName': 'Danish', 'flag': '🇩🇰'},
      {'code': 'fi', 'name': 'Suomi', 'englishName': 'Finnish', 'flag': '🇫🇮'},
      {
        'code': 'no',
        'name': 'Norsk',
        'englishName': 'Norwegian',
        'flag': '🇳🇴',
      },
      {
        'code': 'sk',
        'name': 'Slovenčina',
        'englishName': 'Slovak',
        'flag': '🇸🇰',
      },
      {
        'code': 'bg',
        'name': 'Български',
        'englishName': 'Bulgarian',
        'flag': '🇧🇬',
      },
      {
        'code': 'hr',
        'name': 'Hrvatski',
        'englishName': 'Croatian',
        'flag': '🇭🇷',
      },
      {
        'code': 'sr',
        'name': 'Српски',
        'englishName': 'Serbian',
        'flag': '🇷🇸',
      },
      {
        'code': 'ca',
        'name': 'Català',
        'englishName': 'Catalan',
        'flag': '🇪🇸',
      },
    ];

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text(
          LanguageSelectionScreenLanguage.getSelectLanguage(code),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: languages.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final lang = languages[index];
          final isSelected = currentLocale.languageCode == lang['code'];

          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                final selectedLocale = Locale(lang['code']!);
                await settings.setLanguageCode(selectedLocale.languageCode);
                if (context.mounted) {
                  final rootState = context
                      .findRootAncestorStateOfType<MyAppState>();
                  if (rootState != null) {
                    rootState.setLocale(selectedLocale);
                  }
                  Navigator.pop(context);
                }
              },
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSelected ? gold : const Color(0x38E2C078),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Text(lang['flag']!, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lang['name']!,
                            style: TextStyle(
                              color: isSelected ? gold : Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '(${lang['englishName']})',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle, color: gold, size: 28),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
