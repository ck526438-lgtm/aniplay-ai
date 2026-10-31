import 'package:aniplay/controllers/subtitle_generation_controller.dart';
import 'package:aniplay/models/subtitle_job.dart';
import 'package:aniplay/services/subtitle_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Faux backend : le job passe par transcription puis traduction avant d'être prêt.
class FakeSubtitleApi extends SubtitleApiService {
  FakeSubtitleApi() : super(baseUrl: 'http://test');

  final steps = ['transcribing', 'translating', 'done'];
  String? lastTarget;
  int? lastTrack;

  SubtitleJob _job(String status, double p) => SubtitleJob.fromJson({
        'id': 'job1',
        'status': status,
        'progress': p,
        'target_lang': lastTarget,
        'detected_language': 'ja',
        if (status == 'done') 'download_url': 'http://test/api/v1/subtitles/jobs/job1/file',
      });

  @override
  Future<SubtitleJob> create({
    required String source,
    String targetLang = 'fr',
    String? sourceLang,
    int? audioTrack,
  }) async {
    lastTarget = targetLang;
    lastTrack = audioTrack;
    return _job('queued', 0);
  }

  @override
  Future<SubtitleJob> status(String jobId) async {
    final s = steps.removeAt(0);
    return _job(s, s == 'done' ? 1 : 0.5);
  }
}

void main() {
  test('suit le job jusqu\'au bout puis charge la piste VF', () async {
    final api = FakeSubtitleApi();
    final loaded = <String>[];
    final c = SubtitleGenerationController(
      api: api,
      pollInterval: const Duration(milliseconds: 5),
      onReady: (url, lang, title) async => loaded.add('$lang|$title|$url'),
    );

    await c.start(source: 'ep1.mkv', targetLang: 'fr', languageName: 'Français', audioTrack: 0);
    expect(c.isRunning, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(c.isRunning, isFalse);
    expect(c.job?.status, SubtitleJobStatus.done);
    expect(api.lastTrack, 0);
    expect(loaded, ['fr|Français (IA)|http://test/api/v1/subtitles/jobs/job1/file']);
    expect(c.generated.keys, ['fr']);
    c.dispose();
  });
}
