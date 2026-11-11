import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

enum BackendStatus {
  /// Démarrage du backend embarqué / recherche d'un backend.
  starting,

  /// Backend joignable : skip IA et sous-titres disponibles.
  ready,

  /// Aucun backend : la lecture fonctionne, sans skip ni sous-titres IA.
  unavailable,
}

/// Démarre et surveille le backend Python embarqué de l'application bureau.
///
/// Ordre de recherche :
/// 1. URL imposée par `--dart-define=ANIPLAY_API=…` → on l'utilise telle quelle ;
///    sinon URL d'un serveur enregistrée dans les réglages de l'app (ex. le PC de la
///    maison depuis le téléphone Android) ;
/// 2. exécutable embarqué `backend/aniplay-backend.exe` à côté de l'application
///    (version installée) → lancé sur un port libre, arrêté à la fermeture ;
/// 3. backend de développement déjà lancé sur http://127.0.0.1:8000.
///
/// Le lecteur ne dépend jamais du backend : en cas d'échec, l'état passe à
/// [BackendStatus.unavailable] et la vidéo se lit normalement.
class BackendLauncher extends ChangeNotifier {
  BackendLauncher({
    http.Client? client,
    this.startupTimeout = const Duration(seconds: 90),
    String? executableOverride,
    Future<String?> Function()? loadServerUrl,
    Future<void> Function(String? url)? saveServerUrl,
  })  : _client = client ?? http.Client(),
        _executableOverride = executableOverride,
        _loadServerUrl = loadServerUrl ?? _prefsLoad,
        _saveServerUrl = saveServerUrl ?? _prefsSave;

  static const _prefsKey = 'aniplay.server_url';

  static Future<String?> _prefsLoad() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_prefsKey);
    } catch (_) {
      return null; // stockage indisponible (tests, plateforme exotique)
    }
  }

  static Future<void> _prefsSave(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, url);
    }
  }

  final Future<String?> Function() _loadServerUrl;
  final Future<void> Function(String? url) _saveServerUrl;
  String? _serverUrl;

  /// Serveur AniPlay choisi par l'utilisateur (null = automatique).
  String? get serverUrl => _serverUrl;

  /// Vrai sur Android / iOS : pas de moteur IA embarqué possible.
  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Normalise une URL saisie : « 192.168.1.20:8000 » → « http://192.168.1.20:8000 ».
  static String? normalizeUrl(String? input) {
    var url = input?.trim() ?? '';
    if (url.isEmpty) return null;
    if (!url.contains('://')) url = 'http://$url';
    url = url.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }
    return url;
  }

  /// Enregistre (ou efface avec null) le serveur choisi, puis s'y reconnecte.
  Future<void> setServerUrl(String? url) async {
    _serverUrl = normalizeUrl(url);
    try {
      await _saveServerUrl(_serverUrl);
    } catch (_) {}
    await restart();
  }

  /// Instance partagée par toute l'application.
  static final BackendLauncher instance = BackendLauncher();

  final http.Client _client;
  final Duration startupTimeout;
  final String? _executableOverride;

  BackendStatus _status = BackendStatus.starting;
  String _message = 'Démarrage du moteur IA…';
  bool _subtitlesAvailable = true;
  bool _embedded = false;
  Process? _process;
  Future<void>? _starting;
  final List<String> _lastOutput = [];

  BackendStatus get status => _status;
  String get message => _message;
  bool get isReady => _status == BackendStatus.ready;

  /// Faux si le backend ne contient pas les moteurs de sous-titres (édition « standard »).
  bool get subtitlesAvailable => _subtitlesAvailable;

  /// Vrai si le backend a été lancé par l'application (et sera arrêté avec elle).
  bool get isEmbedded => _embedded;

  /// Lance (une seule fois) la recherche / le démarrage du backend.
  Future<void> start() => _starting ??= _start().whenComplete(() => _starting = null);

  /// Attend que le backend soit prêt (vrai) ou définitivement indisponible (faux).
  Future<bool> waitUntilReady({Duration timeout = const Duration(seconds: 30)}) async {
    if (_status != BackendStatus.starting) return isReady;
    final done = Completer<bool>();
    void listener() {
      if (_status != BackendStatus.starting && !done.isCompleted) done.complete(isReady);
    }

    addListener(listener);
    try {
      return await done.future.timeout(timeout, onTimeout: () => isReady);
    } finally {
      removeListener(listener);
    }
  }

  /// Relance après un échec (bouton « Réessayer »).
  Future<void> restart() async {
    await stop();
    return start();
  }

  Future<void> _start() async {
    _set(BackendStatus.starting, 'Démarrage du moteur IA…');

    if (AppConfig.hasCustomApi) {
      AppConfig.apiBaseUrl = AppConfig.configuredApi;
      return _probe(AppConfig.configuredApi, attempts: 3);
    }

    _serverUrl ??= normalizeUrl(await _loadServerUrl());
    final server = _serverUrl;
    if (server != null) {
      AppConfig.apiBaseUrl = server;
      return _probe(server, attempts: 3);
    }

    if (isMobile) {
      // Téléphone sans serveur configuré : mode autonome (AniSkip en direct)
      _subtitlesAvailable = false;
      _set(
        BackendStatus.unavailable,
        'Mode autonome : skip via AniSkip. Sous-titres IA : connectez un serveur AniPlay.',
      );
      return;
    }

    final exe = embeddedExecutable();
    if (exe != null) return _launch(exe);

    // Mode développement : backend lancé à la main avec scripts/run_backend.*
    AppConfig.apiBaseUrl = AppConfig.configuredApi;
    return _probe(AppConfig.configuredApi, attempts: 2);
  }

  /// Chemin de l'exécutable embarqué, ou null s'il n'existe pas (dev, mobile, web).
  String? embeddedExecutable() {
    if (_executableOverride != null) {
      return File(_executableOverride).existsSync() ? _executableOverride : null;
    }
    if (kIsWeb || !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return null;
    final fromEnv = Platform.environment['ANIPLAY_BACKEND_EXE'];
    if (fromEnv != null && File(fromEnv).existsSync()) return fromEnv;

    final appDir = File(Platform.resolvedExecutable).parent.path;
    final name = Platform.isWindows ? 'aniplay-backend.exe' : 'aniplay-backend';
    final sep = Platform.pathSeparator;
    for (final candidate in [
      '$appDir${sep}backend$sep$name',
      '$appDir$sep$name',
    ]) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  Future<void> _launch(String exe) async {
    final int port;
    try {
      port = await _freePort();
    } on SocketException catch (e) {
      _set(BackendStatus.unavailable, 'Aucun port local disponible : ${e.message}');
      return;
    }
    final url = 'http://127.0.0.1:$port';
    AppConfig.apiBaseUrl = url;

    try {
      _process = await Process.start(
        exe,
        ['--host', '127.0.0.1', '--port', '$port', '--parent-pid', '$pid'],
        workingDirectory: File(exe).parent.path,
      );
    } on ProcessException catch (e) {
      _set(BackendStatus.unavailable, 'Impossible de lancer le moteur IA : ${e.message}');
      return;
    }
    _embedded = true;
    final proc = _process!;
    // Les flux doivent être vidés, sinon le processus se bloque quand le tampon est plein.
    for (final stream in [proc.stdout, proc.stderr]) {
      stream.transform(utf8.decoder).transform(const LineSplitter()).listen(_remember);
    }

    var exited = false;
    int? exitStatus;
    void onExit(int code) {
      exited = true;
      exitStatus = code;
      if (identical(_process, proc)) {
        _process = null;
        _embedded = false;
        if (_status == BackendStatus.ready) {
          _set(BackendStatus.unavailable, 'Le moteur IA s\'est arrêté (code $code)');
        }
      }
    }

    unawaited(proc.exitCode.then(onExit));

    final deadline = DateTime.now().add(startupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (exited) {
        final detail = _lastOutput.isEmpty ? '' : ' — ${_lastOutput.last}';
        _set(BackendStatus.unavailable, 'Le moteur IA a quitté (code $exitStatus)$detail');
      return;
      }
      if (await _health(url)) return;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    await stop();
    _set(BackendStatus.unavailable, 'Le moteur IA ne répond pas (délai dépassé)');
  }

  Future<void> _probe(String url, {required int attempts}) async {
    for (var i = 0; i < attempts; i++) {
      if (await _health(url)) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    _subtitlesAvailable = false;
    _set(
      BackendStatus.unavailable,
      'Serveur IA introuvable ($url) — skip via AniSkip, sans IA locale',
    );
  }

  /// Interroge /health ; passe à [BackendStatus.ready] si le backend répond.
  Future<bool> _health(String url) async {
    try {
      final res = await _client.get(Uri.parse('$url/health')).timeout(const Duration(seconds: 2));
      if (res.statusCode != 200) return false;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map || body['status'] != 'ok') return false;
      // Anciennes versions du backend : le champ n'existe pas → on suppose disponible.
      _subtitlesAvailable = body['subtitles'] != false;
      final version = body['version'] ?? '?';
      _set(
        BackendStatus.ready,
        _embedded ? 'Moteur IA prêt (v$version)' : 'Backend connecté : $url (v$version)',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  void _remember(String line) {
    if (line.trim().isEmpty) return;
    _lastOutput.add(line);
    if (_lastOutput.length > 20) _lastOutput.removeAt(0);
  }

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  /// Arrête le backend embarqué (appelé à la fermeture de la fenêtre).
  /// Le backend surveille aussi le PID de l'application et s'arrête seul si elle plante.
  Future<void> stop() async {
    final proc = _process;
    _process = null;
    _embedded = false;
    if (proc == null) return;
    proc.kill();
    await proc.exitCode.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        proc.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }

  void _set(BackendStatus status, String message) {
    _status = status;
    _message = message;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stop());
    _client.close();
    super.dispose();
  }
}
