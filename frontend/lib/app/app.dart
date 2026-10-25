import 'package:flutter/material.dart';
import 'router.dart';
import 'themes/app_theme.dart';

class FlowSpaceApp extends StatelessWidget {
  const FlowSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'FlowSpace',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system, // Supports both Light and Dark modes
      routerConfig: appRouter,
    );
  }
}
