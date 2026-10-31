import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized(); // initialise libmpv (obligatoire avant tout Player)
  runApp(const AniPlayApp());
}

class AniPlayApp extends StatelessWidget {
  const AniPlayApp({super.key});

  static const _seed = Color(0xFF7C4DFF); // violet néon

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
      tertiary: const Color(0xFF64FFDA),
    );
    return MaterialApp(
      title: 'AniPlay AI',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF0E0E14),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: const HomeScreen(),
    );
  }
}
