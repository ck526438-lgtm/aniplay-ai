import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/skip_segment.dart';
import 'backend_launcher.dart';

/// Résultat d'une requête au backend. Ne lève jamais : le lecteur doit
/// toujours pouvoir lire, même si le backend est éteint.
class SkipLookup {
  const SkipLookup({required this.segments, this.message});

  final List<SkipSegment> segments;
  final String? message;

  bool get found => segments.isNotEmpty;
}

/// Segments à passer : via le backend AniPlay s'il est joignable, sinon directement
/// auprès d'AniSkip (mode autonome, par ex. sur téléphone sans serveur).
class SkipApiService {
  SkipApiService({
    http.Client? client,
    String? baseUrl,
    bool Function()? backendAvailable,
    this.aniSkipBaseUrl = 'https://api.aniskip.com/v2',
  })  : _client = client ?? http.Client(),
        _baseUrl = (baseUrl ?? AppConfig.apiBaseUrl).replaceAll(RegExp(r'/+$'), ''),
        _backendAvailable = backendAvailable ??
            (baseUrl != null ? () => true : () => BackendLauncher.instance.isReady);

  final http.Client _client;
  final String _baseUrl;
  final bool Function() _backendAvailable;
  final String aniSkipBaseUrl;

  /// Tolérance (s) avant de recaler un horodatage soumis pour une version de durée différente.
  static const double episodeLengthTolerance = 3.0;

  /// Récupère les segments à passer pour [malId] / [episode].
  ///
  /// [episodeLength] (durée réelle du fichier) permet au backend de recaler
  /// les timestamps soumis sur une version de durée différente.
  Future<SkipLookup> fetchSkipTimes({
    required int malId,
    required double episode,
    Duration? episodeLength,
    List<SegmentType> types = const [
      SegmentType.opening,
      SegmentType.ending,
      SegmentType.mixedOpening,
      SegmentType.mixedEnding,
      SegmentType.recap,
    ],
  }) async {
    final ep = episode == episode.roundToDouble() ? episode.toInt().toString() : '$episode';
    if (_backendAvailable()) {
      final viaBackend = await _fromBackend(malId, ep, episodeLength, types);
      if (viaBackend != null) return viaBackend;
    }
    return fetchFromAniSkip(malId: malId, episode: ep, episodeLength: episodeLength, types: types);
  }

  /// null = backend injoignable (on bascule alors sur AniSkip en direct).
  Future<SkipLookup?> _fromBackend(
    int malId,
    String ep,
    Duration? episodeLength,
    List<SegmentType> types,
  ) async {
    final uri = Uri.parse('$_baseUrl/api/v1/skip-times/$malId/$ep').replace(
      queryParameters: {
        'types': types.map((t) => t.wire).join(','),
        if (episodeLength != null && episodeLength > Duration.zero)
          'episode_length': (episodeLength.inMilliseconds / 1000).toStringAsFixed(1),
      },
    );

    try {
      final res = await _client.get(uri).timeout(AppConfig.apiTimeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final segments = (body['segments'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SkipSegment.tryParse)
          .whereType<SkipSegment>()
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      return SkipLookup(segments: segments, message: body['message'] as String?);
    } catch (_) {
      return null;
    }
  }

  /// Appel direct de l'API publique AniSkip v2 (même logique que backend/app/services/aniskip.py).
  Future<SkipLookup> fetchFromAniSkip({
    required int malId,
    required String episode,
    Duration? episodeLength,
    required List<SegmentType> types,
  }) async {
    final len = episodeLength == null ? 0.0 : episodeLength.inMilliseconds / 1000;
    final query = [
      for (final t in types) 'types[]=${Uri.encodeQueryComponent(t.wire)}',
      'episodeLength=${len.toStringAsFixed(1)}',
    ].join('&');
    final uri = Uri.parse('$aniSkipBaseUrl/skip-times/$malId/$episode?$query');
    try {
      final res = await _client.get(uri).timeout(AppConfig.apiTimeout);
      // 404 + "found": false = aucun horodatage, ce n'est pas une erreur
      if (res.statusCode != 200 && res.statusCode != 404) {
        return SkipLookup(segments: const [], message: 'AniSkip HTTP ${res.statusCode}');
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map) return const SkipLookup(segments: [], message: 'Réponse AniSkip invalide');
      final segments = parseAniSkip(body, len)..sort((a, b) => a.start.compareTo(b.start));
      return SkipLookup(
        segments: segments,
        message: segments.isEmpty ? 'Aucun horodatage AniSkip pour cet épisode' : 'AniSkip',
      );
    } catch (e) {
      return SkipLookup(segments: const [], message: 'AniSkip injoignable : $e');
    }
  }

  /// Convertit la réponse AniSkip en segments, avec recalage si la durée diffère.
  static List<SkipSegment> parseAniSkip(Map<dynamic, dynamic> body, double episodeLength) {
    final out = <SkipSegment>[];
    for (final item in (body['results'] as List? ?? const [])) {
      if (item is! Map) continue;
      final interval = item['interval'];
      if (interval is! Map) continue;
      var start = (interval['startTime'] as num?)?.toDouble();
      var end = (interval['endTime'] as num?)?.toDouble();
      final srcLen = (item['episodeLength'] as num?)?.toDouble() ?? 0;
      if (start == null || end == null) continue;
      if (episodeLength > 0 && srcLen > 0 && (srcLen - episodeLength).abs() > episodeLengthTolerance) {
        final ratio = episodeLength / srcLen;
        start *= ratio;
        end *= ratio;
      }
      if (episodeLength > 0 && end > episodeLength) end = episodeLength;
      final seg = SkipSegment.tryParse({
        'type': item['skipType'],
        'start': start < 0 ? 0.0 : start,
        'end': end,
        'source': 'aniskip',
        'confidence': 1.0,
        'skip_id': item['skipId'],
      });
      if (seg != null) out.add(seg);
    }
    return out;
  }

  void dispose() => _client.close();
}
