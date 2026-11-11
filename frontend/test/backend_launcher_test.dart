import 'dart:convert';

import 'package:aniplay/screens/home_screen.dart';
import 'package:aniplay/services/backend_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

BackendLauncher _launcher(MockClient client) => BackendLauncher(
      client: client,
      // Chemin inexistant : pas d'exécutable embarqué → recherche d'un backend de dev
      executableOverride: '/nexiste/pas/aniplay-backend',
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
    expect(launcher.message, contains('lecture possible'));
    expect(await launcher.waitUntilReady(), isFalse);
  });

  testWidgets('la barre d\'état propose « Réessayer » en cas d\'échec', (tester) async {
    final launcher = _launcher(MockClient((_) async => http.Response('erreur', 500)));
    await tester.runAsync(launcher.start);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BackendStatusBar(launcher: launcher))));
    expect(find.text('Réessayer'), findsOneWidget);
  });
}
