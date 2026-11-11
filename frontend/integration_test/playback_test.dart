// Test sur appareil réel / émulateur : vérifie que libmpv (media_kit) lit vraiment une vidéo.
//
//   flutter test integration_test/playback_test.dart \
//     --dart-define=TEST_VIDEO_URL=http://10.0.2.2:8088/test.mp4
import 'dart:async';
import 'dart:io';

import 'package:aniplay/main.dart';
import 'package:aniplay/screens/player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

const _videoUrl = String.fromEnvironment('TEST_VIDEO_URL');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets("l'accueil s'affiche", (tester) async {
    await tester.pumpWidget(const AniPlayApp());
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('AniPlay AI'), findsWidgets);
    expect(find.text('Lire'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('libmpv lit une vidéo (la position avance)', (tester) async {
    expect(_videoUrl, isNotEmpty, reason: 'passer --dart-define=TEST_VIDEO_URL=…');

    // 1. Réseau : on télécharge la vidéo dans le dossier temporaire de l'app
    final file = File('${Directory.systemTemp.path}/aniplay-test.mp4');
    await tester.runAsync(() async {
      final client = HttpClient();
      final res = await (await client.getUrl(Uri.parse(_videoUrl))).close();
      await res.pipe(file.openWrite());
      client.close();
    });
    debugPrint('[test] vidéo téléchargée : ${file.lengthSync()} octets');
    expect(file.lengthSync(), greaterThan(10000));

    // 2. Lecture du fichier local avec libmpv
    final player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn));
    final logs = <String>[];
    final subs = [
      player.stream.log.listen((l) => logs.add('[${l.prefix}] ${l.text}')),
      player.stream.error.listen((e) => logs.add('[erreur] $e')),
    ];
    // L'émulateur de CI n'a pas de sortie audio : sans cela mpv peut rester bloqué
    final platform = player.platform;
    if (platform is NativePlayer) await platform.setProperty('ao', 'null');
    final advanced = Completer<Duration>();
    subs.add(player.stream.position.listen((p) {
      if (p > const Duration(seconds: 2) && !advanced.isCompleted) advanced.complete(p);
    }));
    try {
      await player.open(Media(file.path));
      final reached = await tester.runAsync(
        () => advanced.future.timeout(const Duration(seconds: 40), onTimeout: () => Duration.zero),
      );
      final st = player.state;
      debugPrint('[test] position=${st.position} durée=${st.duration} lecture=${st.playing} '
          'buffering=${st.buffering}\n${logs.take(40).join('\n')}');
      expect(reached, greaterThan(const Duration(seconds: 2)), reason: logs.join('\n'));
      expect(st.duration, greaterThan(const Duration(seconds: 5)));
    } finally {
      for (final s in subs) {
        await s.cancel();
      }
      await tester.runAsync(() => player.dispose().timeout(const Duration(seconds: 5), onTimeout: () {}));
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets("l'écran de lecture s'ouvre sans erreur", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PlayerScreen(
          request: PlaybackRequest(source: _videoUrl, title: 'test', malId: 21, episode: 1),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 6)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('test'), findsOneWidget);
    // Démonte l'écran (libère le lecteur) avant la fin du test
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
