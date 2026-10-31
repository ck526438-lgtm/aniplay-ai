import 'package:flutter/material.dart';

import '../controllers/subtitle_generation_controller.dart';
import '../models/subtitle_job.dart';

/// Panneau « Générer des sous-titres IA » : choix de la langue + progression.
class SubtitleGeneratorPanel extends StatefulWidget {
  const SubtitleGeneratorPanel({
    super.key,
    required this.controller,
    required this.languages,
    required this.onGenerate,
  });

  final SubtitleGenerationController controller;
  final Future<List<SubtitleLanguage>> languages;
  final void Function(SubtitleLanguage language) onGenerate;

  @override
  State<SubtitleGeneratorPanel> createState() => _SubtitleGeneratorPanelState();
}

class _SubtitleGeneratorPanelState extends State<SubtitleGeneratorPanel> {
  String _target = 'fr'; // VF par défaut

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<SubtitleLanguage>>(
      future: widget.languages,
      builder: (context, snap) {
        final langs = snap.data ?? SubtitleLanguage.fallback;
        if (!langs.any((l) => l.code == _target)) _target = langs.first.code;

        return ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final c = widget.controller;
            final job = c.job;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: theme.colorScheme.tertiary),
                      const SizedBox(width: 10),
                      Text('Sous-titres IA', style: theme.textTheme.titleLarge),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "L'IA écoute l'épisode, détecte la langue parlée et traduit les dialogues.",
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    value: _target,
                    decoration: const InputDecoration(
                      labelText: 'Langue des sous-titres',
                      prefixIcon: Icon(Icons.translate),
                    ),
                    items: [
                      for (final l in langs)
                        DropdownMenuItem(
                          value: l.code,
                          child: Text(
                            c.generated.containsKey(l.code) ? '${l.name}  ✓' : l.name,
                          ),
                        ),
                    ],
                    onChanged: c.isRunning ? null : (v) => setState(() => _target = v ?? _target),
                  ),
                  const SizedBox(height: 16),
                  if (c.isRunning) ...[
                    LinearProgressIndicator(value: job == null ? null : job.progress),
                    const SizedBox(height: 8),
                    Text(
                      [
                        job?.status.label ?? 'Démarrage…',
                        if (job?.detectedLanguage != null) 'langue détectée : ${job!.detectedLanguage}',
                        if (job != null) '${(job.progress * 100).round()} %',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Vous pouvez continuer à regarder pendant la génération.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                    ),
                  ] else
                    FilledButton.icon(
                      onPressed: () => widget.onGenerate(langs.firstWhere((l) => l.code == _target)),
                      icon: const Icon(Icons.subtitles),
                      label: const Text('Générer'),
                    ),
                  if (c.error != null) ...[
                    const SizedBox(height: 12),
                    Text(c.error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  if (!c.isRunning && job?.status == SubtitleJobStatus.done) ...[
                    const SizedBox(height: 12),
                    Text(
                      '✓ Piste chargée dans le lecteur',
                      style: TextStyle(color: theme.colorScheme.tertiary),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
