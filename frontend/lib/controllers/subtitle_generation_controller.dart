import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/subtitle_job.dart';
import '../services/subtitle_api_service.dart';

/// Appelé quand un fichier de sous-titres est prêt : le lecteur le charge.
typedef SubtitleReadyCallback = Future<void> Function(String url, String langCode, String title);

/// Lance une génération côté backend et suit sa progression (polling).
/// Indépendant de media_kit, comme SkipController.
class SubtitleGenerationController extends ChangeNotifier {
  SubtitleGenerationController({
    required this.api,
    required this.onReady,
    this.pollInterval = const Duration(milliseconds: 1500),
  });

  final SubtitleApiService api;
  final SubtitleReadyCallback onReady;
  final Duration pollInterval;

  SubtitleJob? _job;
  String? _error;
  bool _starting = false;
  Timer? _timer;
  bool _disposed = false;

  /// Langues déjà générées pour ce média (code → URL), pour éviter les doublons.
  final Map<String, String> generated = {};

  SubtitleJob? get job => _job;
  String? get error => _error;
  bool get isRunning => _starting || (_job != null && !_job!.status.finished);

  Future<void> start({
    required String source,
    required String targetLang,
    required String languageName,
    int? audioTrack,
  }) async {
    if (isRunning) return;
    _starting = true;
    _error = null;
    _job = null;
    _notify();
    try {
      _job = await api.create(source: source, targetLang: targetLang, audioTrack: audioTrack);
    } on SubtitleApiException catch (e) {
      _error = e.message;
    } finally {
      _starting = false;
      _notify();
    }
    if (_job != null) await _handle(_job!, languageName);
  }

  Future<void> _handle(SubtitleJob job, String languageName) async {
    if (job.status == SubtitleJobStatus.done && job.downloadUrl != null) {
      generated[job.targetLang] = job.downloadUrl!;
      await onReady(job.downloadUrl!, job.targetLang, '$languageName (IA)');
      return;
    }
    if (job.status == SubtitleJobStatus.error) {
      _error = job.error ?? 'Échec de la génération';
      _notify();
      return;
    }
    _timer?.cancel();
    _timer = Timer(pollInterval, () async {
      if (_disposed) return;
      try {
        _job = await api.status(job.id);
        _notify();
        await _handle(_job!, languageName);
      } on SubtitleApiException catch (e) {
        _error = e.message;
        _notify();
      }
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
