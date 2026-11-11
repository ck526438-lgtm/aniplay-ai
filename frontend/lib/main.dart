import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AppExitResponse;
import 'package:media_kit/media_kit.dart';

import 'screens/home_screen.dart';
import 'services/backend_launcher.dart';

/// [args] : sous Windows, « Ouvrir avec AniPlay AI » passe le chemin du fichier vidéo.
void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized(); // initialise libmpv (obligatoire avant tout Player)
  // Le moteur IA démarre en arrière-plan : l'interface s'affiche immédiatement.
  BackendLauncher.instance.start();
  final initial = args.where((a) => a.trim().isNotEmpty && !a.startsWith('--')).firstOrNull;
  runApp(AniPlayApp(initialSource: initial));
}

class AniPlayApp extends StatefulWidget {
  const AniPlayApp({super.key, this.initialSource});

  final String? initialSource;

  @override
  State<AniPlayApp> createState() => _AniPlayAppState();
}

class _AniPlayAppState extends State<AniPlayApp> {
  /// Arrête proprement le backend embarqué quand l'utilisateur ferme la fenêtre.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await BackendLauncher.instance.stop();
        return AppExitResponse.exit;
      },
      onDetach: BackendLauncher.instance.stop,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

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
      home: HomeScreen(initialSource: widget.initialSource),
    );
  }
}
