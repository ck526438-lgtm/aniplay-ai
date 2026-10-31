import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/skip_segment.dart';

/// Résultat d'une requête au backend. Ne lève jamais : le lecteur doit
/// toujours pouvoir lire, même si le backend est éteint.
class SkipLookup {
  const SkipLookup({required this.segments, this.message});

  final List<SkipSegment> segments;
  final String? message;

  bool get found => segments.isNotEmpty;
}

class SkipApiService {
  SkipApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = (baseUrl ?? AppConfig.apiBaseUrl).replaceAll(RegExp(r'/+$'), '');

  final http.Client _client;
  final String _baseUrl;

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
    final uri = Uri.parse('$_baseUrl/api/v1/skip-times/$malId/$ep').replace(
      queryParameters: {
        'types': types.map((t) => t.wire).join(','),
        if (episodeLength != null && episodeLength > Duration.zero)
          'episode_length': (episodeLength.inMilliseconds / 1000).toStringAsFixed(1),
      },
    );

    try {
      final res = await _client.get(uri).timeout(AppConfig.apiTimeout);
      if (res.statusCode != 200) {
        return SkipLookup(segments: const [], message: 'Backend HTTP ${res.statusCode}');
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final segments = (body['segments'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SkipSegment.tryParse)
          .whereType<SkipSegment>()
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      return SkipLookup(segments: segments, message: body['message'] as String?);
    } catch (e) {
      return SkipLookup(segments: const [], message: 'Backend injoignable : $e');
    }
  }

  void dispose() => _client.close();
}
