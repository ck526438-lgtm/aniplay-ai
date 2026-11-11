import 'dart:convert';

import 'package:aniplay/models/skip_segment.dart';
import 'package:aniplay/services/skip_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Réponse type de l'API AniSkip v2.
final _aniskip = {
  'found': true,
  'results': [
    {
      'interval': {'startTime': 1300.0, 'endTime': 1390.0},
      'skipType': 'ed',
      'skipId': 'ed1',
      'episodeLength': 1420.0,
    },
    {
      'interval': {'startTime': 80.0, 'endTime': 170.0},
      'skipType': 'op',
      'skipId': 'op1',
      'episodeLength': 1420.0,
    },
    {'interval': {'startTime': 5}, 'skipType': 'op'}, // entrée corrompue ignorée
  ],
  'message': 'Successfully found skip times',
};

void main() {
  test('sans backend : AniSkip est interrogé directement', () async {
    Uri? called;
    final api = SkipApiService(
      client: MockClient((req) async {
        called = req.url;
        return http.Response(jsonEncode(_aniskip), 200);
      }),
      baseUrl: 'http://backend',
      backendAvailable: () => false,
    );
    final res = await api.fetchSkipTimes(malId: 21, episode: 1, episodeLength: const Duration(seconds: 1420));
    expect(called!.host, 'api.aniskip.com');
    expect(called!.path, '/v2/skip-times/21/1');
    expect(called!.query, contains('types[]=op'));
    expect(res.segments.map((s) => s.type), [SegmentType.opening, SegmentType.ending]);
    expect(res.segments.first.start, const Duration(seconds: 80));
  });

  test('backend en panne : bascule automatique sur AniSkip', () async {
    final hosts = <String>[];
    final api = SkipApiService(
      client: MockClient((req) async {
        hosts.add(req.url.host);
        if (req.url.host == 'backend') return http.Response('boom', 500);
        return http.Response(jsonEncode(_aniskip), 200);
      }),
      baseUrl: 'http://backend',
    );
    final res = await api.fetchSkipTimes(malId: 21, episode: 1);
    expect(hosts, ['backend', 'api.aniskip.com']);
    expect(res.found, isTrue);
  });

  test('recalage quand la durée du fichier diffère (version TV / BD)', () {
    final segs = SkipApiService.parseAniSkip(_aniskip, 710); // fichier deux fois plus court
    final op = segs.firstWhere((s) => s.type == SegmentType.opening);
    expect(op.start, const Duration(seconds: 40));
    expect(op.end, const Duration(seconds: 85));
  });

  test('404 « found: false » = aucun segment, sans erreur', () async {
    final api = SkipApiService(
      client: MockClient((_) async => http.Response('{"found":false,"results":[]}', 404)),
      baseUrl: 'http://backend',
      backendAvailable: () => false,
    );
    final res = await api.fetchSkipTimes(malId: 1, episode: 3);
    expect(res.found, isFalse);
    expect(res.message, contains('Aucun'));
  });
}
