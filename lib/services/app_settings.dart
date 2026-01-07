import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  const AppSettings();

  static const String prefPhotoSpeedUp = 'settings.photo_speed_up';
  static const String prefPreventDuplicates = 'settings.prevent_duplicates';

  Future<bool> getPhotoSpeedUp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefPhotoSpeedUp) ?? false;
  }

  Future<bool> getPreventDuplicates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefPreventDuplicates) ?? true;
  }

  Future<void> setPhotoSpeedUp(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefPhotoSpeedUp, value);
  }

  Future<void> setPreventDuplicates(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefPreventDuplicates, value);
  }
}
