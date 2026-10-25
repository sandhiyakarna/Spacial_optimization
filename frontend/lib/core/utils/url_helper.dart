import 'package:flutter/foundation.dart';

String getBaseUrl() {
  if (kIsWeb) {
    final uri = Uri.base;
    final origin = '${uri.scheme}://${uri.host}${uri.hasPort ? ":${uri.port}" : ""}';
    if (kDebugMode) {
      // In Flutter Web debug mode, we run on a dev server (which has no proxy),
      // so we must send backend requests to http://localhost:8000.
      return 'http://localhost:8000';
    }
    // In release mode (Nginx), we use the exact origin of the page.
    return origin;
  }
  return 'http://localhost:8000';
}
