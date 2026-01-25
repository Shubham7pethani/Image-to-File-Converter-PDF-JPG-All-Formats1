import 'package:shared_preferences/shared_preferences.dart';

class ImportantService {
  const ImportantService();

  static const String _key = 'important_paths';

  Future<Set<String>> getPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? const <String>[];
    return list.toSet();
  }

  Future<bool> isImportant(String path) async {
    final set = await getPaths();
    return set.contains(path);
  }

  Future<void> add(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    if (!list.contains(path)) {
      list.add(path);
      await prefs.setStringList(_key, list);
    }
  }

  Future<void> remove(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    list.remove(path);
    await prefs.setStringList(_key, list);
  }

  Future<bool> toggle(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    if (list.contains(path)) {
      list.remove(path);
      await prefs.setStringList(_key, list);
      return false;
    }
    list.add(path);
    await prefs.setStringList(_key, list);
    return true;
  }

  Future<void> setAll(Set<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, paths.toList());
  }
}
