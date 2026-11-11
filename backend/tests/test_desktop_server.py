"""Point d'entrée bureau (aniplay_server.py) utilisé par l'application Windows."""
import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import aniplay_server

KEYS = ("ANIPLAY_LOCAL_MODE", "ANIPLAY_MEDIA_ROOT", "ANIPLAY_SUBTITLES_DIR", "HF_HOME",
        "ANIPLAY_WHISPER_MODEL", "PATH")


@pytest.fixture
def clean_env():
    """configure_environment écrit dans os.environ : on restaure tout après chaque test."""
    saved = dict(os.environ)
    for key in KEYS:
        if key != "PATH":
            os.environ.pop(key, None)
    yield
    os.environ.clear()
    os.environ.update(saved)


def test_configure_environment_uses_data_dir(tmp_path, clean_env):
    aniplay_server.configure_environment(tmp_path)
    assert os.environ["ANIPLAY_LOCAL_MODE"] == "true"
    assert Path(os.environ["ANIPLAY_SUBTITLES_DIR"]) == tmp_path / "subtitles"
    assert Path(os.environ["HF_HOME"]) == tmp_path / "models"
    assert (tmp_path / "media").is_dir()


def test_backend_env_file_overrides_defaults(tmp_path, clean_env):
    (tmp_path / "backend.env").write_text(
        "# réglages perso\nANIPLAY_WHISPER_MODEL=small  # plus précis\nANIPLAY_LOCAL_MODE=false\n",
        encoding="utf-8",
    )
    aniplay_server.configure_environment(tmp_path)
    assert os.environ["ANIPLAY_WHISPER_MODEL"] == "small"
    assert os.environ["ANIPLAY_LOCAL_MODE"] == "false"


def test_process_alive():
    assert aniplay_server._process_alive(os.getpid())
    assert not aniplay_server._process_alive(2**22 + 12345)


def test_parse_args_defaults():
    args = aniplay_server.parse_args([])
    assert args.host == "127.0.0.1" and args.port == 8765 and args.parent_pid is None
