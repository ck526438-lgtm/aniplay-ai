/// Configuration de l'application.
///
/// Par défaut, l'application Windows démarre elle-même son backend embarqué
/// (voir `BackendLauncher`) sur un port libre et met à jour [apiBaseUrl].
///
/// Pour utiliser un backend externe (autre PC, Docker, développement) :
///   flutter run --dart-define=ANIPLAY_API=http://192.168.1.20:8000
///
/// Émulateur Android : utilisez http://10.0.2.2:8000 pour joindre le PC hôte.
class AppConfig {
  AppConfig._();

  /// Vrai si une URL de backend a été imposée à la compilation.
  static const bool hasCustomApi = bool.hasEnvironment('ANIPLAY_API');

  static const String _configuredApi = String.fromEnvironment(
    'ANIPLAY_API',
    defaultValue: 'http://127.0.0.1:8000',
  );

  /// URL du backend en cours d'utilisation (modifiée par le lanceur du backend embarqué).
  static String apiBaseUrl = _configuredApi;

  /// URL par défaut d'un backend lancé à la main (`uvicorn app.main:app`).
  static String get configuredApi => _configuredApi;

  /// Délai réseau max avant de lancer la lecture sans segments.
  static const Duration apiTimeout = Duration(seconds: 8);
}
