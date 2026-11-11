import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../controllers/skip_controller.dart';
import '../controllers/subtitle_generation_controller.dart';
import '../models/subtitle_job.dart';
import '../services/backend_launcher.dart';
import '../services/skip_api_service.dart';
import '../services/subtitle_api_service.dart';
import '../widgets/skip_button.dart';
import '../widgets/subtitle_generator_panel.dart';

/// Ce que l'écran d'accueil transmet au lecteur.
class PlaybackRequest {
  const PlaybackRequest({
    required this.source,
    this.title,
    this.malId,
    this.episode,
    this.autoSkip = false,
    this.externalSubtitle,
  });

  /// Chemin local, URL http(s), HLS (.m3u8)…
  final String source;
  final String? title;
  final int? malId;
  final double? episode;
  final bool autoSkip;

  /// Fichier .srt/.ass externe (optionnel).
  final String? externalSubtitle;
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.request, this.api});

  final PlaybackRequest request;
  final SkipApiService? api;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player(
    configuration: const PlayerConfiguration(title: 'AniPlay AI', bufferSize: 64 * 1024 * 1024),
  );
  late final VideoController _video = VideoController(_player);
  late final SkipApiService _api = widget.api ?? SkipApiService();
  late final SkipController _skip = SkipController(
    onSeek: _player.seek,
    autoSkip: widget.request.autoSkip,
  );

  final SubtitleApiService _subtitleApi = SubtitleApiService();
  late final Future<List<SubtitleLanguage>> _languages = _subtitleApi.languages();
  late final SubtitleGenerationController _subGen = SubtitleGenerationController(
    api: _subtitleApi,
    onReady: _loadGeneratedSubtitle,
  );

  final List<StreamSubscription<dynamic>> _subs = [];
  bool _segmentsRequested = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _subs
      ..add(_player.stream.position.listen(_skip.updatePosition))
      // On attend la durée réelle pour que le backend recale les timestamps.
      ..add(_player.stream.duration.listen(_onDuration))
      ..add(_player.stream.error.listen((e) => _toast('Erreur lecteur : $e')));
    _open();
  }

  Future<void> _open() async {
    final req = widget.request;
    await _player.open(Media(req.source));
    if (req.externalSubtitle != null) {
      await _player.setSubtitleTrack(SubtitleTrack.uri(req.externalSubtitle!, title: 'Externe'));
    }
  }

  Future<void> _onDuration(Duration duration) async {
    final req = widget.request;
    if (_segmentsRequested || duration <= Duration.zero) return;
    if (req.malId == null || req.episode == null) return; // pas d'identifiant : pas de skip
    _segmentsRequested = true;

    // Au tout premier lancement, le moteur IA peut encore être en train de démarrer.
    if (widget.api == null) await BackendLauncher.instance.waitUntilReady();
    if (!mounted) return;
    final lookup = await _api.fetchSkipTimes(
      malId: req.malId!,
      episode: req.episode!,
      episodeLength: duration,
    );
    if (!mounted) return;
    _skip.setSegments(lookup.segments);
    setState(() {
      _status = lookup.found
          ? '${lookup.segments.length} segment(s) à passer'
          : (lookup.message ?? 'Aucun segment trouvé');
    });
  }

  /// Piste audio actuellement écoutée → index pour ffmpeg (VO/VF dans un même mkv).
  /// mpv numérote les pistes audio à partir de 1 ; ffmpeg à partir de 0.
  int? get _currentAudioIndex {
    final id = int.tryParse(_player.state.track.audio.id);
    return id == null ? null : id - 1;
  }

  void _generateSubtitles(SubtitleLanguage lang) {
    _subGen.start(
      source: widget.request.source,
      targetLang: lang.code,
      languageName: lang.name,
      audioTrack: _currentAudioIndex,
    );
  }

  Future<void> _loadGeneratedSubtitle(String url, String lang, String title) async {
    await _player.setSubtitleTrack(SubtitleTrack.uri(url, title: title, language: lang));
    _toast('Sous-titres « $title » activés');
  }

  void _openSubtitleGenerator() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SubtitleGeneratorPanel(
        controller: _subGen,
        languages: _languages,
        onGenerate: _generateSubtitles,
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _skip.dispose();
    _subGen.dispose();
    _subtitleApi.dispose();
    _player.dispose();
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ UI
  /// On injecte le bouton DANS les contrôles de media_kit : il reste ainsi
  /// visible aussi en plein écran (media_kit pousse une nouvelle route).
  Widget _controls(VideoState state) {
    return Stack(
      children: [
        AdaptiveVideoControls(state),
        Positioned(
          right: 24,
          bottom: 96, // au-dessus de la barre de progression
          child: SkipButton(controller: _skip),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS): _skip.skip,
        const SingleActivator(LogicalKeyboardKey.space): _player.playOrPause,
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _player.seek(_player.state.position + const Duration(seconds: 10)),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _player.seek(_player.state.position - const Duration(seconds: 10)),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: Text(req.title ?? 'Lecture', overflow: TextOverflow.ellipsis),
            actions: [
              ListenableBuilder(
                listenable: _skip,
                builder: (_, __) => Tooltip(
                  message: 'Passer automatiquement les génériques',
                  child: Row(
                    children: [
                      const Text('Auto-skip', style: TextStyle(fontSize: 13)),
                      Switch(
                        value: _skip.autoSkip,
                        onChanged: (v) => _skip.autoSkip = v,
                      ),
                    ],
                  ),
                ),
              ),
              // Indicateur de progression discret pendant la génération.
              // Masqué si le moteur IA ne contient pas les sous-titres (édition standard).
              if (BackendLauncher.instance.subtitlesAvailable)
              ListenableBuilder(
                listenable: _subGen,
                builder: (_, __) => IconButton(
                  tooltip: 'Générer des sous-titres (IA)',
                  onPressed: _openSubtitleGenerator,
                  icon: _subGen.isRunning
                      ? SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            value: _subGen.job?.progress,
                          ),
                        )
                      : const Icon(Icons.auto_awesome),
                ),
              ),
              IconButton(
                tooltip: 'Pistes audio et sous-titres',
                icon: const Icon(Icons.subtitles_outlined),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (_) => _TracksSheet(player: _player),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: Video(controller: _video, controls: _controls),
              ),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_status!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sélection des pistes audio (VO/VF…) et sous-titres embarqués.
class _TracksSheet extends StatelessWidget {
  const _TracksSheet({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Track>(
      stream: player.stream.track,
      initialData: player.state.track,
      builder: (context, snap) {
        final current = snap.data ?? player.state.track;
        final tracks = player.state.tracks;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const ListTile(title: Text('Audio', style: TextStyle(fontWeight: FontWeight.bold))),
            for (final a in tracks.audio)
              RadioListTile<String>(
                value: a.id,
                groupValue: current.audio.id,
                title: Text(_label(a.id, a.title, a.language)),
                onChanged: (_) => player.setAudioTrack(a),
              ),
            const Divider(),
            const ListTile(title: Text('Sous-titres', style: TextStyle(fontWeight: FontWeight.bold))),
            for (final s in tracks.subtitle)
              RadioListTile<String>(
                value: s.id,
                groupValue: current.subtitle.id,
                title: Text(_label(s.id, s.title, s.language)),
                onChanged: (_) => player.setSubtitleTrack(s),
              ),
          ],
        );
      },
    );
  }

  static String _label(String id, String? title, String? lang) {
    if (id == 'auto') return 'Automatique';
    if (id == 'no') return 'Désactivé';
    return [title, lang].whereType<String>().where((s) => s.isNotEmpty).join(' · ').ifEmpty('Piste $id');
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
