import 'package:aniplay/controllers/skip_controller.dart';
import 'package:aniplay/models/skip_segment.dart';
import 'package:aniplay/widgets/skip_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('le bouton apparaît, passe, puis disparaît', (tester) async {
    final seeks = <Duration>[];
    final c = SkipController(onSeek: (d) async => seeks.add(d))
      ..setSegments(const [
        SkipSegment(type: SegmentType.opening, start: Duration(seconds: 90), end: Duration(seconds: 180)),
      ]);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SkipButton(controller: c)))));
    expect(find.text("Passer l'opening"), findsNothing);

    c.updatePosition(const Duration(seconds: 100));
    await tester.pumpAndSettle();
    expect(find.text("Passer l'opening"), findsOneWidget);
    expect(find.text('IA'), findsNothing); // source AniSkip

    await tester.tap(find.text("Passer l'opening"));
    await tester.pumpAndSettle();
    expect(seeks, [const Duration(seconds: 180)]);
    expect(find.text("Passer l'opening"), findsNothing);

    c.dispose();
  });
}
