import 'package:flutter/foundation.dart';

class ApiConfig {
  // Current active local IP address for physical devices on your Wi-Fi network
  static const String localIp = '10.94.54.53';
  static const String port = '5000';

  static String get baseUrl {
    if (kIsWeb) {
      // On Web platform (Chrome browser), use localhost
      return 'http://localhost:$port';
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      // On Android devices/emulators
      return 'http://$localIp:$port';
    } else {
      return 'http://localhost:$port';
    }
  }

  static String get formattedHost {
    if (kIsWeb) {
      return 'localhost:$port';
    } else {
      return '$localIp:$port';
    }
  }
}
