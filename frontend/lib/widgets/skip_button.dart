import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/skip_controller.dart';
import '../models/skip_segment.dart';

/// Bouton « Passer l'opening » qui apparaît / disparaît selon la position de lecture.
///
/// * Entrée animée (glissement + fondu) quand un segment devient actif.
/// * Remplissage progressif = avancement dans l'opening.
/// * Badge « IA » quand le segment vient de la détection locale.
/// * Clavier / télécommande : focus automatique, Entrée/Espace pour passer, Échap pour ignorer.
class SkipButton extends StatelessWidget {
  const SkipButton({super.key, required this.controller});

  final SkipController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final segment = controller.activeSegment;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: const Offset(0.25, 0), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          child: segment == null
              ? const SizedBox.shrink(key: ValueKey('skip-hidden'))
              : _SkipChip(
                  key: ValueKey(segment.key),
                  segment: segment,
                  progress: controller.progress,
                  onSkip: controller.skip,
                  onDismiss: controller.dismiss,
                ),
        );
      },
    );
  }
}

class _SkipChip extends StatefulWidget {
  const _SkipChip({
    super.key,
    required this.segment,
    required this.progress,
    required this.onSkip,
    required this.onDismiss,
  });

  final SkipSegment segment;
  final ValueListenable<double> progress;
  final VoidCallback onSkip;
  final VoidCallback onDismiss;

  @override
  State<_SkipChip> createState() => _SkipChipState();
}

class _SkipChipState extends State<_SkipChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final seg = widget.segment;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: '${seg.type.skipLabel}, jusqu\'à ${_fmt(seg.end)}',
            child: FocusableActionDetector(
              autofocus: true, // télécommande Android TV / clavier
              onShowHoverHighlight: (v) => setState(() => _hover = v),
              actions: {
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    widget.onSkip();
                    return null;
                  },
                ),
              },
              child: GestureDetector(
                onTap: widget.onSkip,
                child: AnimatedScale(
                  scale: _hover ? 1.04 : 1,
                  duration: const Duration(milliseconds: 120),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      children: [
                        // Fond + remplissage progressif
                        Positioned.fill(
                          child: ColoredBox(color: Colors.black.withValues(alpha: 0.72)),
                        ),
                        Positioned.fill(
                          child: ValueListenableBuilder<double>(
                            valueListenable: widget.progress,
                            builder: (_, p, __) => FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: p,
                              child: ColoredBox(color: scheme.primary.withValues(alpha: 0.35)),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                seg.type.skipLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.skip_next_rounded, color: Colors.white, size: 22),
                              if (seg.source.isAi) ...[
                                const SizedBox(width: 8),
                                _AiBadge(confidence: seg.confidence),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Fermer sans passer
          IconButton.filledTonal(
            tooltip: 'Regarder quand même',
            onPressed: widget.onDismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.55),
              foregroundColor: Colors.white70,
              minimumSize: const Size(36, 36),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _AiBadge extends StatelessWidget {
  const _AiBadge({required this.confidence});

  final double confidence;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Détecté par l\'IA locale — confiance ${(confidence * 100).round()} %',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.tertiary,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'IA',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.black),
        ),
      ),
    );
  }
}
