import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import 'player_screen.dart';

/// Écran d'accueil minimal : choisir une source + identifier l'épisode pour AniSkip.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _form = GlobalKey<FormState>();
  final _source = TextEditingController();
  final _malId = TextEditingController();
  final _episode = TextEditingController(text: '1');
  final _subtitle = TextEditingController();
  bool _autoSkip = false;

  @override
  void dispose() {
    for (final c in [_source, _malId, _episode, _subtitle]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(TextEditingController target, {List<String>? ext}) async {
    final res = await FilePicker.platform.pickFiles(
      type: ext == null ? FileType.video : FileType.custom,
      allowedExtensions: ext,
    );
    final path = res?.files.single.path;
    if (path != null) setState(() => target.text = path);
  }

  void _play() {
    if (!_form.currentState!.validate()) return;
    final source = _source.text.trim();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          request: PlaybackRequest(
            source: source,
            title: _titleFrom(source),
            malId: int.tryParse(_malId.text.trim()),
            episode: double.tryParse(_episode.text.trim().replaceAll(',', '.')),
            autoSkip: _autoSkip,
            externalSubtitle: _subtitle.text.trim().isEmpty ? null : _subtitle.text.trim(),
          ),
        ),
      ),
    );
  }

  /// Nom de fichier lisible pour chemins Windows, Unix ou URL.
  static String _titleFrom(String source) {
    var clean = source.split('?').first;
    try {
      clean = Uri.decodeFull(clean);
    } on ArgumentError {
      // '%' isolé dans un nom de fichier : on garde la chaîne brute
    }
    final parts = clean.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty);
    return parts.isEmpty ? source : parts.last;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Text('AniPlay AI', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  'Lecteur d\'anime avec skip intelligent des génériques',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _source,
                  decoration: InputDecoration(
                    labelText: 'Fichier local ou URL (mp4, mkv, m3u8…)',
                    prefixIcon: const Icon(Icons.movie_outlined),
                    suffixIcon: IconButton(
                      tooltip: 'Parcourir',
                      icon: const Icon(Icons.folder_open),
                      onPressed: () => _pick(_source),
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Source requise' : null,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _malId,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'ID MyAnimeList',
                          helperText: 'myanimelist.net/anime/<ID>',
                          prefixIcon: Icon(Icons.tag),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null; // optionnel
                          return (int.tryParse(v.trim()) ?? 0) > 0 ? null : 'ID invalide';
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _episode,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Épisode'),
                        validator: (v) =>
                            (double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0) > 0 ? null : 'Invalide',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _subtitle,
                  decoration: InputDecoration(
                    labelText: 'Sous-titres externes (optionnel)',
                    prefixIcon: const Icon(Icons.closed_caption_outlined),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.folder_open),
                      onPressed: () => _pick(_subtitle, ext: ['srt', 'ass', 'ssa', 'vtt']),
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _autoSkip,
                  onChanged: (v) => setState(() => _autoSkip = v),
                  title: const Text('Passer automatiquement openings et endings'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _play,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('Lire'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Backend : ${AppConfig.apiBaseUrl}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
