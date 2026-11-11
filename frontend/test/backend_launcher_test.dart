import 'dart:convert';

import 'package:aniplay/screens/home_screen.dart';
import 'package:aniplay/services/backend_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

BackendLauncher _launcher(MockClient client, {String? saved, List<String?>? store}) =>
    BackendLauncher(
      client: client,
      // Chemin inexistant : pas d'exécutable embarqué → recherche d'un backend de dev
      executableOverride: '/nexiste/pas/aniplay-backend',
      loadServerUrl: () async => saved,
      saveServerUrl: (url) async => store?.add(url),
    );

void main() {
  test('backend de développement joignable : prêt, sous-titres selon /health', () async {
    Future<http.Response> health(http.Request req) async {
      expect(req.url.path, '/health');
      return http.Response(jsonEncode({'status': 'ok', 'version': '0.2.0', 'subtitles': false}), 200);
    }

    final launcher = _launcher(MockClient(health));
    await launcher.start();
    expect(launcher.status, BackendStatus.ready);
    expect(launcher.subtitlesAvailable, isFalse);
    expect(launcher.isEmbedded, isFalse);
    expect(await launcher.waitUntilReady(), isTrue);
  });

  test('ancien backend sans champ « subtitles » : supposé disponible', () async {
    final launcher = _launcher(MockClient((_) async => http.Response('{"status":"ok"}', 200)));
    await launcher.start();
    expect(launcher.subtitlesAvailable, isTrue);
  });

  test('aucun backend : indisponible, sans lever d\'exception', () async {
    final launcher = _launcher(MockClient((_) async => throw http.ClientException('refusé')));
    await launcher.start();
    expect(launcher.status, BackendStatus.unavailable);
    expect(launcher.message, contains('AniSkip'));
    expect(launcher.subtitlesAvailable, isFalse);
    expect(await launcher.waitUntilReady(), isFalse);
  });

  test('serveur enregistré dans les réglages : utilisé en priorité', () async {
    final hosts = <String>[];
    final launcher = _launcher(
      MockClient((req) async {
        hosts.add('${req.url.host}:${req.url.port}');
        return http.Response('{"status":"ok","version":"1.1.0","subtitles":true}', 200);
      }),
      saved: '192.168.1.20:8000',
    );
    await launcher.start();
    expect(launcher.isReady, isTrue);
    expect(launcher.serverUrl, 'http://192.168.1.20:8000');
    expect(hosts.first, '192.168.1.20:8000');
  });

  test('setServerUrl normalise, enregistre et se reconnecte', () async {
    final store = <String?>[];
    final launcher = _launcher(
      MockClient((_) async => http.Response('{"status":"ok"}', 200)),
      store: store,
    );
    await launcher.setServerUrl(' http://10.0.0.5:8000/ ');
    expect(store, ['http://10.0.0.5:8000']);
    expect(launcher.isReady, isTrue);
    await launcher.setServerUrl('');
    expect(store.last, isNull);
  });

  test('normalizeUrl', () {
    expect(BackendLauncher.normalizeUrl('pc.local:8000'), 'http://pc.local:8000');
    expect(BackendLauncher.normalizeUrl('https://ia.exemple.ci/'), 'https://ia.exemple.ci');
    expect(BackendLauncher.normalizeUrl('ftp://x'), isNull);
    expect(BackendLauncher.normalizeUrl('   '), isNull);
  });

  testWidgets('la barre d\'état propose « Réessayer » en cas d\'échec', (tester) async {
    final launcher = _launcher(MockClient((_) async => http.Response('erreur', 500)));
    await tester.runAsync(launcher.start);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BackendStatusBar(launcher: launcher))));
    expect(find.text('Réessayer'), findsOneWidget);
  });
}
