import 'package:aniplay/controllers/skip_controller.dart';
import 'package:aniplay/models/skip_segment.dart';
import 'package:flutter_test/flutter_test.dart';

Duration s(int sec) => Duration(seconds: sec);

const op = SkipSegment(type: SegmentType.opening, start: Duration(seconds: 90), end: Duration(seconds: 180));

void main() {
  late List<Duration> seeks;
  late SkipController c;

  setUp(() {
    seeks = [];
    c = SkipController(onSeek: (d) async => seeks.add(d))..setSegments([op]);
  });

  test('le bouton apparaît uniquement dans le segment', () {
    c.updatePosition(s(80));
    expect(c.isVisible, isFalse);
    c.updatePosition(s(95));
    expect(c.isVisible, isTrue);
    expect(c.progress.value, closeTo(5 / 90, 1e-6));
    c.updatePosition(s(179) + const Duration(milliseconds: 500)); // dernière seconde
    expect(c.isVisible, isFalse);
  });

  test('skip() saute à la fin du segment', () async {
    c.updatePosition(s(100));
    await c.skip();
    expect(seeks, [s(180)]);
    expect(c.isVisible, isFalse);
  });

  test('dismiss masque jusqu\'à la sortie du segment', () {
    c.updatePosition(s(100));
    c.dismiss();
    c.updatePosition(s(110));
    expect(c.isVisible, isFalse);
    c.updatePosition(s(300)); // sortie
    c.updatePosition(s(100)); // retour en arrière
    expect(c.isVisible, isTrue);
  });

  test('auto-skip ne se déclenche qu\'une fois par segment', () async {
    c.autoSkip = true;
    c.updatePosition(s(91));
    await Future<void>.delayed(Duration.zero);
    c.updatePosition(s(92)); // l'utilisateur revient revoir l'opening
    await Future<void>.delayed(Duration.zero);
    expect(seeks, [s(180)]);
    expect(c.isVisible, isTrue); // le bouton manuel reste disponible
  });

  test('les détections IA peu fiables sont ignorées', () {
    c.setSegments([
      const SkipSegment(
        type: SegmentType.ending,
        start: Duration(seconds: 10),
        end: Duration(seconds: 100),
        source: SegmentSource.localAudio,
        confidence: 0.3,
      ),
    ]);
    c.updatePosition(s(50));
    expect(c.isVisible, isFalse);
  });

  test('parsing JSON robuste', () {
    final ok = SkipSegment.tryParse({'type': 'op', 'start': 81.5, 'end': 171.5, 'source': 'local-visual'});
    expect(ok?.start, const Duration(milliseconds: 81500));
    expect(ok?.source.isAi, isTrue);
    expect(SkipSegment.tryParse({'type': 'op', 'start': 50, 'end': 10}), isNull);
    expect(SkipSegment.tryParse({'type': 'intro', 'start': 0, 'end': 10}), isNull);
  });
}
