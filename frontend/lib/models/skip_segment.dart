/// Miroir Dart du modèle `SkipSegment` exposé par le backend.
enum SegmentType {
  opening('op'),
  ending('ed'),
  mixedOpening('mixed-op'),
  mixedEnding('mixed-ed'),
  recap('recap');

  const SegmentType(this.wire);
  final String wire;

  static SegmentType? fromWire(String value) {
    for (final t in values) {
      if (t.wire == value) return t;
    }
    return null;
  }

  /// Libellé affiché sur le bouton.
  String get skipLabel => switch (this) {
        SegmentType.opening || SegmentType.mixedOpening => "Passer l'opening",
        SegmentType.ending || SegmentType.mixedEnding => "Passer l'ending",
        SegmentType.recap => 'Passer le récap',
      };
}

enum SegmentSource {
  aniskip('aniskip'),
  localAudio('local-audio'),
  localVisual('local-visual');

  const SegmentSource(this.wire);
  final String wire;

  bool get isAi => this != SegmentSource.aniskip;

  static SegmentSource fromWire(String value) =>
      values.firstWhere((s) => s.wire == value, orElse: () => SegmentSource.aniskip);
}

class SkipSegment {
  const SkipSegment({
    required this.type,
    required this.start,
    required this.end,
    this.source = SegmentSource.aniskip,
    this.confidence = 1.0,
    this.skipId,
  }); // validation start < end faite dans tryParse (un assert sur Duration n'est pas const)

  final SegmentType type;
  final Duration start;
  final Duration end;
  final SegmentSource source;
  final double confidence;
  final String? skipId;

  Duration get duration => end - start;

  /// Identifiant stable, utilisé pour mémoriser « déjà passé » / « ignoré ».
  String get key => skipId ?? '${type.wire}@${start.inMilliseconds}';

  bool contains(Duration position) => position >= start && position < end;

  /// Retourne null si l'entrée est invalide (on ne plante jamais sur une donnée réseau).
  static SkipSegment? tryParse(Map<String, dynamic> json) {
    final type = SegmentType.fromWire('${json['type']}');
    final start = (json['start'] as num?)?.toDouble();
    final end = (json['end'] as num?)?.toDouble();
    if (type == null || start == null || end == null || end <= start || start < 0) {
      return null;
    }
    return SkipSegment(
      type: type,
      start: Duration(milliseconds: (start * 1000).round()),
      end: Duration(milliseconds: (end * 1000).round()),
      source: SegmentSource.fromWire('${json['source']}'),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      skipId: json['skip_id'] as String?,
    );
  }

  @override
  String toString() => 'SkipSegment(${type.wire} $start→$end, ${source.wire})';
}
