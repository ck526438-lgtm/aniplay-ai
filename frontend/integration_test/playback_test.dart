// Test sur appareil réel / émulateur : vérifie que libmpv (media_kit) lit vraiment une vidéo.
//
//   flutter test integration_test/playback_test.dart \
//     --dart-define=TEST_VIDEO_URL=http://10.0.2.2:8088/test.mp4
import 'dart:async';

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
  });

  testWidgets('libmpv lit une vidéo (la position avance)', (tester) async {
    expect(_videoUrl, isNotEmpty, reason: 'passer --dart-define=TEST_VIDEO_URL=…');
    final player = Player();
    addTearDown(player.dispose);
    final advanced = Completer<Duration>();
    final sub = player.stream.position.listen((p) {
      if (p > const Duration(seconds: 2) && !advanced.isCompleted) advanced.complete(p);
    });
    addTearDown(sub.cancel);
    await player.open(Media(_videoUrl));
    final reached = await tester.runAsync(() => advanced.future.timeout(const Duration(seconds: 40)));
    expect(reached, isNotNull);
    expect(player.state.duration, greaterThan(const Duration(seconds: 5)));
  });

  testWidgets("l'écran de lecture s'ouvre sans erreur", (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PlayerScreen(
        request: PlaybackRequest(source: _videoUrl, title: 'test', malId: 21, episode: 1),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 6)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('test'), findsOneWidget);
  });
}
