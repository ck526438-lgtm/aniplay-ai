"""Pipeline de sous-titres IA, testé avec des moteurs simulés (pas de modèle à télécharger)."""
import shutil
import time

import numpy as np
import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.services.subtitles import formats, languages
from app.services.subtitles.engines import EngineUnavailable
from app.services.subtitles.formats import Cue
from app.services.subtitles.jobs import SubtitleJobManager

sf = pytest.importorskip("soundfile")
needs_ffmpeg = pytest.mark.skipif(not shutil.which("ffmpeg"), reason="ffmpeg requis")


# ------------------------------------------------------------------ formats
def test_srt_timestamps_and_numbering():
    srt = formats.render([Cue(1.5, 3.25, "Bonjour"), Cue(3661.0, 3663.0, "Salut")], "srt")
    assert srt.startswith("1\n00:00:01,500 --> 00:00:03,250\nBonjour\n\n2\n01:01:01,000")


def test_long_text_is_wrapped_and_split():
    text = "Ceci est une très longue réplique " * 6
    cues = formats.normalize_timing(formats.split_long_cues([Cue(0, 12, text)]))
    assert len(cues) > 1
    for c in cues:
        lines = c.text.split("\n")
        assert len(lines) <= 2 and all(len(line) <= 42 for line in lines)
    assert cues[0].start == 0 and cues[-1].end == pytest.approx(12, abs=0.05)


def test_vtt_and_overlap_fix():
    vtt = formats.render([Cue(0, 5, "A"), Cue(2, 4, "B")], "vtt")
    assert vtt.startswith("WEBVTT\n\n00:00:00.000 --> 00:00:01.960\nA")


# ------------------------------------------------------------------ langues
def test_opus_model_name_for_pair():
    assert languages.opus_model("ja", "fr") == "Helsinki-NLP/opus-mt-ja-fr"


def test_opus_model_rejects_unknown_language():
    with pytest.raises(ValueError, match="non prise en charge"):
        languages.opus_model("fr", "xx")


# ------------------------------------------------------------------ jobs
class FakeWhisper:
    def __init__(self, lang="ja"):
        self.lang, self.calls = lang, 0

    def transcribe(self, audio, language, on_progress):
        self.calls += 1
        assert audio.dtype == np.float32 and audio.size > 16000
        on_progress(0.5)
        on_progress(1.0)
        return [Cue(1.0, 2.5, "こんにちは"), Cue(3.0, 4.0, "ありがとう")], language or self.lang


class FakeNllb:
    def __init__(self):
        self.calls = []

    def translate(self, texts, source, target, on_progress):
        self.calls.append((source, target))
        on_progress(1.0)
        return [f"[{target}] {t}" for t in texts]


class BrokenWhisper:
    def transcribe(self, *a):
        raise EngineUnavailable("faster-whisper n'est pas installé")


@pytest.fixture
def media_dir(tmp_path):
    root = tmp_path / "media"
    root.mkdir()
    sr = 16000
    t = np.arange(sr * 5) / sr
    sf.write(root / "ep1.wav", (0.3 * np.sin(2 * np.pi * 440 * t)).astype(np.float32), sr)
    return root


def make_client(tmp_path, media_dir, whisper=None, nllb=None):
    settings = Settings(media_root=media_dir, subtitles_dir=tmp_path / "subs")
    app = create_app()
    app.state.subtitle_jobs = SubtitleJobManager(settings, whisper or FakeWhisper(), nllb or FakeNllb())
    return TestClient(app)


def wait_done(client, job_id, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        body = client.get(f"/api/v1/subtitles/jobs/{job_id}").json()
        if body["status"] in ("done", "error"):
            return body
        time.sleep(0.05)
    raise AssertionError("job non terminé")


@needs_ffmpeg
def test_full_flow_japanese_to_french(tmp_path, media_dir):
    nllb = FakeNllb()
    with make_client(tmp_path, media_dir, nllb=nllb) as client:
        r = client.post("/api/v1/subtitles", json={"source": "ep1.wav"})
        assert r.status_code == 202
        body = wait_done(client, r.json()["id"])

        assert body["status"] == "done", body["error"]
        assert body["detected_language"] == "ja" and body["progress"] == 1.0
        assert nllb.calls == [("ja", "fr")]

        fr = client.get(body["download_url"])
        assert fr.status_code == 200
        assert "00:00:01,000 --> 00:00:02,500\n[fr] こんにちは" in fr.text

        orig = client.get(body["original_url"])
        assert "[fr]" not in orig.text and "ありがとう" in orig.text


@needs_ffmpeg
def test_other_target_language_and_cache(tmp_path, media_dir):
    whisper = FakeWhisper()
    with make_client(tmp_path, media_dir, whisper=whisper) as client:
        payload = {"source": "ep1.wav", "target_lang": "en", "format": "vtt"}
        first = wait_done(client, client.post("/api/v1/subtitles", json=payload).json()["id"])
        again = client.post("/api/v1/subtitles", json=payload).json()
        assert again["id"] == first["id"] and whisper.calls == 1
        assert client.get(first["download_url"]).text.startswith("WEBVTT")


@needs_ffmpeg
def test_no_translation_when_already_target_language(tmp_path, media_dir):
    nllb = FakeNllb()
    with make_client(tmp_path, media_dir, whisper=FakeWhisper(lang="fr"), nllb=nllb) as client:
        body = wait_done(client, client.post("/api/v1/subtitles", json={"source": "ep1.wav"}).json()["id"])
        assert body["status"] == "done" and nllb.calls == []


@needs_ffmpeg
def test_missing_engine_reports_clear_error(tmp_path, media_dir):
    with make_client(tmp_path, media_dir, whisper=BrokenWhisper()) as client:
        body = wait_done(client, client.post("/api/v1/subtitles", json={"source": "ep1.wav"}).json()["id"])
        assert body["status"] == "error" and "faster-whisper" in body["error"]


def test_validation_errors(tmp_path, media_dir):
    with make_client(tmp_path, media_dir) as client:
        post = lambda **kw: client.post("/api/v1/subtitles", json={"source": "ep1.wav", **kw})
        assert post(target_lang="xx").status_code == 422
        assert client.post("/api/v1/subtitles", json={"source": "../secret.mkv"}).status_code == 422
        assert client.post("/api/v1/subtitles", json={"source": "/etc/passwd"}).status_code == 422
        assert client.post("/api/v1/subtitles", json={"source": "file:///etc/passwd"}).status_code == 422
        langs = {lang["code"] for lang in client.get("/api/v1/subtitles/languages").json()}
        assert {"fr", "ja", "dyu"} <= langs
