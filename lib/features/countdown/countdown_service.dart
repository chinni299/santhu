import 'package:shared_preferences/shared_preferences.dart';

class CountdownService {
  static const String _targetDateIdKey = 'selected_countdown_target_date_id';

  static Future<int?> getSelectedTargetDateId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_targetDateIdKey);
  }

  static Future<void> setSelectedTargetDateId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_targetDateIdKey, id);
  }
}
