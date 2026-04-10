import asyncio
import json
import logging
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

LOGGER = logging.getLogger(__name__)

NOMINATIM_BASE_URL = "https://nominatim.openstreetmap.org"
REQUEST_TIMEOUT_SECONDS = 8
USER_AGENT = "DomixBotMap/1.0 (Telegram Mini App)"
UZBEKISTAN_VIEWBOX = "55.9966,45.5901,73.2317,37.1722"
UZBEKISTAN_LAT_RANGE = (37.1722, 45.5901)
UZBEKISTAN_LON_RANGE = (55.9966, 73.2317)
COUNTRY_KEYWORDS = (
    "uzbekistan",
    "uzbekiston",
    "o'zbekiston",
    "o‘zbekiston",
    "узбекистан",
)


def _is_inside_uzbekistan(lat: float, lon: float) -> bool:
    return (
        UZBEKISTAN_LAT_RANGE[0] <= lat <= UZBEKISTAN_LAT_RANGE[1]
        and UZBEKISTAN_LON_RANGE[0] <= lon <= UZBEKISTAN_LON_RANGE[1]
    )


def _fetch_json(path: str, params: dict[str, Any]) -> Any:
    url = f"{NOMINATIM_BASE_URL}{path}?{urlencode(params)}"
    request = Request(
        url,
        headers={
            "Accept": "application/json",
            "Accept-Language": params.get("accept-language", "ru,uz"),
            "User-Agent": USER_AGENT,
        },
    )

    with urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
        return json.loads(response.read().decode("utf-8"))


def _contains_country_hint(query: str) -> bool:
    normalized = query.lower()
    return any(keyword in normalized for keyword in COUNTRY_KEYWORDS)


def _build_title(item: dict[str, Any]) -> str:
    address = item.get("address") or {}
    display_name = item.get("display_name", "")

    return (
        item.get("name")
        or address.get("amenity")
        or address.get("building")
        or address.get("road")
        or display_name.split(",")[0].strip()
        or display_name
    )


def _build_subtitle(item: dict[str, Any]) -> str:
    address = item.get("address") or {}
    road = address.get("road")
    house_number = address.get("house_number")

    if road and house_number:
        road = f"{road}, {house_number}"

    parts = [
        road,
        address.get("suburb") or address.get("neighbourhood"),
        address.get("city")
        or address.get("town")
        or address.get("village")
        or address.get("county")
        or address.get("state"),
    ]

    subtitle = " • ".join(part for part in parts if part)
    return subtitle or item.get("display_name", "")


def _normalize_search_item(item: dict[str, Any]) -> dict[str, Any] | None:
    try:
        lat = float(item["lat"])
        lon = float(item["lon"])
    except (KeyError, TypeError, ValueError):
        return None

    if not _is_inside_uzbekistan(lat, lon):
        return None

    address = item.get("address") or {}
    country_code = str(address.get("country_code", "")).lower()

    if country_code and country_code != "uz":
        return None

    display_name = str(item.get("display_name", "")).strip()
    if not display_name:
        return None

    return {
        "lat": lat,
        "lon": lon,
        "display_name": display_name,
        "title": _build_title(item),
        "subtitle": _build_subtitle(item),
    }


async def search_places(query: str, accept_language: str) -> list[dict[str, Any]]:
    cleaned_query = query.strip()
    if len(cleaned_query) < 2:
        return []

    candidates = [cleaned_query]
    if not _contains_country_hint(cleaned_query):
        candidates.append(f"{cleaned_query}, Uzbekistan")

    params = {
        "format": "jsonv2",
        "addressdetails": 1,
        "bounded": 1,
        "countrycodes": "uz",
        "dedupe": 1,
        "limit": 8,
        "viewbox": UZBEKISTAN_VIEWBOX,
        "accept-language": accept_language or "ru,uz",
    }

    seen_keys: set[tuple[float, float, str]] = set()
    normalized_results: list[dict[str, Any]] = []

    for candidate in candidates:
        try:
            payload = await asyncio.to_thread(
                _fetch_json,
                "/search",
                {**params, "q": candidate},
            )
        except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as error:
            LOGGER.warning("Geocoding search failed for query %r: %s", candidate, error)
            continue

        for item in payload:
            normalized = _normalize_search_item(item)
            if not normalized:
                continue

            result_key = (
                normalized["lat"],
                normalized["lon"],
                normalized["display_name"],
            )
            if result_key in seen_keys:
                continue

            seen_keys.add(result_key)
            normalized_results.append(normalized)

        if normalized_results:
            break

    return normalized_results[:8]
