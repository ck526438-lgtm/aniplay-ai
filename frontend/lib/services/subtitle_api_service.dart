import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/subtitle_job.dart';

class SubtitleApiException implements Exception {
  SubtitleApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Client des routes /api/v1/subtitles du backend.
class SubtitleApiService {
  SubtitleApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _base = (baseUrl ?? AppConfig.apiBaseUrl).replaceAll(RegExp(r'/+$'), '');

  final http.Client _client;
  final String _base;

  Future<List<SubtitleLanguage>> languages() async {
    try {
      final res = await _client
          .get(Uri.parse('$_base/api/v1/subtitles/languages'))
          .timeout(AppConfig.apiTimeout);
      if (res.statusCode != 200) return SubtitleLanguage.fallback;
      return (jsonDecode(utf8.decode(res.bodyBytes)) as List)
          .cast<Map<String, dynamic>>()
          .map((m) => SubtitleLanguage(m['code'] as String, m['name'] as String))
          .toList();
    } catch (_) {
      return SubtitleLanguage.fallback;
    }
  }

  Future<SubtitleJob> create({
    required String source,
    String targetLang = 'fr',
    String? sourceLang,
    int? audioTrack,
  }) async {
    final res = await _send(
      () => _client.post(
        Uri.parse('$_base/api/v1/subtitles'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'source': source,
          'target_lang': targetLang,
          if (sourceLang != null) 'source_lang': sourceLang,
          if (audioTrack != null) 'audio_track': audioTrack,
          'format': 'srt',
        }),
      ),
    );
    return SubtitleJob.fromJson(res);
  }

  Future<SubtitleJob> status(String jobId) async =>
      SubtitleJob.fromJson(await _send(() => _client.get(Uri.parse('$_base/api/v1/subtitles/jobs/$jobId'))));

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() call) async {
    final http.Response res;
    try {
      res = await call().timeout(AppConfig.apiTimeout);
    } catch (e) {
      throw SubtitleApiException('Backend injoignable ($e)');
    }
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode >= 400) {
      String detail = 'Erreur ${res.statusCode}';
      try {
        detail = (jsonDecode(body) as Map)['detail']?.toString() ?? detail;
      } catch (_) {}
      throw SubtitleApiException(detail);
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  void dispose() => _client.close();
}
