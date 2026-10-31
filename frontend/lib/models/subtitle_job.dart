/// État d'une génération de sous-titres côté backend.
enum SubtitleJobStatus {
  queued,
  extracting,
  transcribing,
  translating,
  done,
  error;

  static SubtitleJobStatus parse(String? v) =>
      values.firstWhere((s) => s.name == v, orElse: () => SubtitleJobStatus.error);

  bool get finished => this == done || this == error;

  String get label => switch (this) {
        SubtitleJobStatus.queued => 'En attente…',
        SubtitleJobStatus.extracting => "Extraction de l'audio…",
        SubtitleJobStatus.transcribing => 'Transcription (IA)…',
        SubtitleJobStatus.translating => 'Traduction (IA)…',
        SubtitleJobStatus.done => 'Sous-titres prêts',
        SubtitleJobStatus.error => 'Échec',
      };
}

class SubtitleLanguage {
  const SubtitleLanguage(this.code, this.name);

  final String code;
  final String name;

  static const fallback = [
    SubtitleLanguage('fr', 'Français'),
    SubtitleLanguage('en', 'Anglais'),
    SubtitleLanguage('es', 'Espagnol'),
    SubtitleLanguage('pt', 'Portugais'),
    SubtitleLanguage('ar', 'Arabe'),
  ];
}

class SubtitleJob {
  const SubtitleJob({
    required this.id,
    required this.status,
    required this.progress,
    required this.targetLang,
    this.detectedLanguage,
    this.error,
    this.downloadUrl,
    this.originalUrl,
  });

  final String id;
  final SubtitleJobStatus status;
  final double progress;
  final String targetLang;
  final String? detectedLanguage;
  final String? error;
  final String? downloadUrl;
  final String? originalUrl;

  factory SubtitleJob.fromJson(Map<String, dynamic> j) => SubtitleJob(
        id: j['id'] as String,
        status: SubtitleJobStatus.parse(j['status'] as String?),
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        targetLang: j['target_lang'] as String? ?? 'fr',
        detectedLanguage: j['detected_language'] as String?,
        error: j['error'] as String?,
        downloadUrl: j['download_url'] as String?,
        originalUrl: j['original_url'] as String?,
      );
}
