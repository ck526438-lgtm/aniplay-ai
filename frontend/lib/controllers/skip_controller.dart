import 'package:flutter/foundation.dart';

import '../models/skip_segment.dart';

/// Signature de la fonction qui déplace la lecture (fournie par le lecteur).
typedef SeekCallback = Future<void> Function(Duration position);

/// Cerveau du bouton « Passer l'opening ».
///
/// Volontairement INDÉPENDANT de media_kit : il reçoit des positions et
/// appelle un callback de seek. On peut donc le tester sans lecteur réel et
/// le brancher sur n'importe quel moteur vidéo.
///
/// Deux notifications distinctes pour limiter les reconstructions :
///  * `this` (ChangeNotifier) → change quand le segment actif change ;
///  * [progress] → avancement dans le segment (barre de remplissage du bouton).
class SkipController extends ChangeNotifier {
  SkipController({
    required SeekCallback onSeek,
    bool autoSkip = false,
    this.hideBeforeEnd = const Duration(seconds: 1),
    this.minConfidence = 0.5,
  })  : _onSeek = onSeek,
        _autoSkip = autoSkip;

  final SeekCallback _onSeek;

  /// On masque le bouton dans la dernière seconde : passer ne servirait à rien.
  final Duration hideBeforeEnd;

  /// Les détections IA sous ce seuil de confiance sont ignorées.
  final double minConfidence;

  List<SkipSegment> _segments = const [];
  SkipSegment? _active;
  bool _autoSkip;
  bool _seeking = false;

  /// Segments que l'utilisateur a fermés (✕) — réaffichés s'il revient dedans plus tard.
  final Set<String> _dismissed = {};

  /// Segments déjà passés automatiquement : on ne ré-auto-skip pas si
  /// l'utilisateur revient volontairement en arrière pour revoir l'opening.
  final Set<String> _autoSkipped = {};

  final ValueNotifier<double> progress = ValueNotifier(0);

  List<SkipSegment> get segments => _segments;
  SkipSegment? get activeSegment => _active;
  bool get isVisible => _active != null;
  bool get autoSkip => _autoSkip;

  set autoSkip(bool value) {
    if (_autoSkip == value) return;
    _autoSkip = value;
    notifyListeners();
  }

  void setSegments(List<SkipSegment> segments) {
    _segments = segments
        .where((s) => s.confidence >= minConfidence)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    _dismissed.clear();
    _autoSkipped.clear();
    _setActive(null);
  }

  /// À appeler à chaque tick de position du lecteur.
  void updatePosition(Duration position) {
    if (_seeking) return;

    SkipSegment? found;
    for (final s in _segments) {
      if (position >= s.start && position < s.end - hideBeforeEnd) {
        found = s;
        break;
      }
    }

    // Sortir d'un segment « ré-arme » le bouton pour une prochaine fois.
    if (found == null || found.key != _active?.key) {
      _dismissed.removeWhere((k) => k != found?.key);
    }

    final visible = found != null && !_dismissed.contains(found.key) ? found : null;
    _setActive(visible);

    if (visible != null) {
      final total = visible.duration.inMilliseconds;
      final done = (position - visible.start).inMilliseconds;
      progress.value = total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);

      if (_autoSkip && !_autoSkipped.contains(visible.key)) {
        _autoSkipped.add(visible.key);
        skip();
      }
    }
  }

  /// Saute à la fin du segment actif.
  Future<void> skip() async {
    final target = _active;
    if (target == null || _seeking) return;
    _seeking = true;
    _setActive(null);
    try {
      await _onSeek(target.end);
    } finally {
      _seeking = false;
    }
  }

  /// L'utilisateur ferme le bouton sans passer (il veut regarder l'opening).
  void dismiss() {
    final current = _active;
    if (current == null) return;
    _dismissed.add(current.key);
    _setActive(null);
  }

  void _setActive(SkipSegment? segment) {
    if (segment?.key == _active?.key) return;
    _active = segment;
    if (segment == null) progress.value = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    progress.dispose();
    super.dispose();
  }
}
