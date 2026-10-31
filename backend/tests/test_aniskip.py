import httpx
import pytest
import respx

from app.schemas import SegmentType
from app.services.aniskip import AniSkipClient, AniSkipError

BASE = "https://api.aniskip.com/v2"

FOUND = {
    "found": True,
    "results": [
        {"interval": {"startTime": 1300.5, "endTime": 1390.5}, "skipType": "ed",
         "skipId": "b", "episodeLength": 1420.0},
        {"interval": {"startTime": 81.0, "endTime": 171.0}, "skipType": "op",
         "skipId": "a", "episodeLength": 1420.0},
        {"interval": {"startTime": 5, "endTime": 2}, "skipType": "op"},  # invalide
        {"interval": {"startTime": 5, "endTime": 9}, "skipType": "unknown"},  # type inconnu
    ],
    "message": "Successfully found skip times",
    "statusCode": 200,
}


@pytest.fixture
async def client():
    c = AniSkipClient(base_url=BASE, retries=1, cache_ttl=60)
    yield c
    await c.aclose()


@respx.mock
async def test_parse_and_sort(client):
    route = respx.get(f"{BASE}/skip-times/21/1").mock(return_value=httpx.Response(200, json=FOUND))
    res = await client.get_skip_times(21, 1, types=[SegmentType.opening, SegmentType.ending])

    assert res.found
    assert [s.type for s in res.segments] == [SegmentType.opening, SegmentType.ending]
    assert res.segments[0].start == 81.0 and res.segments[0].end == 171.0
    params = route.calls[0].request.url.params
    assert params.get_list("types[]") == ["op", "ed"]


@respx.mock
async def test_404_means_not_found(client):
    respx.get(f"{BASE}/skip-times/99999/3").mock(
        return_value=httpx.Response(404, json={"found": False, "results": [], "statusCode": 404})
    )
    res = await client.get_skip_times(99999, 3)
    assert res.found is False and res.segments == []


@respx.mock
async def test_cache_avoids_second_call(client):
    route = respx.get(f"{BASE}/skip-times/21/2").mock(return_value=httpx.Response(200, json=FOUND))
    await client.get_skip_times(21, 2)
    await client.get_skip_times(21, 2)
    assert route.call_count == 1


@respx.mock
async def test_retry_then_error(client):
    route = respx.get(f"{BASE}/skip-times/21/4").mock(return_value=httpx.Response(503))
    with pytest.raises(AniSkipError):
        await client.get_skip_times(21, 4)
    assert route.call_count == 2  # 1 essai + 1 retry


@respx.mock
async def test_rescale_when_episode_length_differs(client):
    respx.get(f"{BASE}/skip-times/21/5").mock(return_value=httpx.Response(200, json=FOUND))
    res = await client.get_skip_times(21, 5, episode_length=1420.0 * 1.04)  # version 4 % plus longue
    op = res.segments[0]
    assert op.start == pytest.approx(81.0 * 1.04, rel=1e-3)


async def test_invalid_args(client):
    with pytest.raises(ValueError):
        await client.get_skip_times(0, 1)
