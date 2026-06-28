import 'package:shared_preferences/shared_preferences.dart';

class LookupCounter {
  static const freeLimit = 5;
  static const _countKey = 'pr_lookup_count';
  static const _monthKey = 'pr_lookup_month';

  static String _currentMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  static Future<int> getCount() async {
    final prefs = await SharedPreferences.getInstance();
    final month = _currentMonth();
    if (prefs.getString(_monthKey) != month) {
      await prefs.setString(_monthKey, month);
      await prefs.setInt(_countKey, 0);
      return 0;
    }
    return prefs.getInt(_countKey) ?? 0;
  }

  static Future<void> increment() async {
    final prefs = await SharedPreferences.getInstance();
    final month = _currentMonth();
    if (prefs.getString(_monthKey) != month) {
      await prefs.setString(_monthKey, month);
      await prefs.setInt(_countKey, 1);
    } else {
      final current = prefs.getInt(_countKey) ?? 0;
      await prefs.setInt(_countKey, current + 1);
    }
  }
}
