import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme/app_theme.dart';
import 'screens/chat_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock to portrait for consistent mobile UX
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  // Dark status bar to match theme
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const OragApp());
}

class OragApp extends StatelessWidget {
  const OragApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'O-RAG',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const ChatScreen(),
    );
  }
}
