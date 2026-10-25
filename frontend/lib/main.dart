import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';

void main() {
  // Catch errors in the Flutter Framework layer (rendering, layout, widget builders)
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // Custom logic can be injected here for logging (e.g. Sentry/Crashlytics)
    debugPrint('Global Flutter Error caught: ${details.exceptionAsString()}');
  };

  // Catch errors outside the Flutter Framework layer (async, background, platform channels)
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('Global Platform Dispatcher Error caught: $error\n$stack');
    return true; // Error has been handled
  };

  runApp(
    const ProviderScope(
      child: FlowSpaceApp(),
    ),
  );
}
