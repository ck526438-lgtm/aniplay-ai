import numpy as np

from app.services.matching import find_common_segment, normalize


def test_finds_shared_block_at_different_offsets():
    rng = np.random.default_rng(0)
    common = rng.normal(size=(90, 24))
    a = np.vstack([rng.normal(size=(40, 24)), common, rng.normal(size=(70, 24))])
    b = np.vstack([rng.normal(size=(15, 24)), common, rng.normal(size=(95, 24))])
    # bruit léger sur la copie B
    b[15:105] += rng.normal(scale=0.2, size=(90, 24))

    m = find_common_segment(normalize(a), normalize(b), threshold=0.6, min_length=30)
    assert m is not None
    assert abs(m.start_a - 40) <= 1 and abs(m.start_b - 15) <= 1
    assert 88 <= m.length <= 91


def test_no_match_on_unrelated_content():
    rng = np.random.default_rng(1)
    a, b = rng.normal(size=(200, 24)), rng.normal(size=(200, 24))
    assert find_common_segment(normalize(a), normalize(b), min_length=30) is None
