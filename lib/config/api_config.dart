import 'package:flutter/foundation.dart';

class ApiConfig {
  // Production backend deployed on Render
  static const String _productionUrl = 'https://santhu-qkn9.onrender.com';

  // Render production host (no protocol, no trailing slash) — used for URL rewriting
  static const String _productionHost = 'santhu-qkn9.onrender.com';

  static String get baseUrl => _productionUrl;

  static String get formattedHost {
    if (kIsWeb) {
      return _productionHost;
    } else {
      return _productionHost;
    }
  }
}
