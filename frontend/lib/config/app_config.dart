/// Configuration injectée à la compilation :
///   flutter run --dart-define=ANIPLAY_API=http://192.168.1.20:8000
///
/// Émulateur Android : utilisez http://10.0.2.2:8000 pour joindre le PC hôte.
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'ANIPLAY_API',
    defaultValue: 'http://127.0.0.1:8000',
  );

  /// Délai réseau max avant de lancer la lecture sans segments.
  static const Duration apiTimeout = Duration(seconds: 8);
}
