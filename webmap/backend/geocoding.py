import asyncio
import json
import logging
import re
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
    "o'zbekiston",
    "узбекистан",
)

# Кириллица → Латиница (узбекский алфавит + русские буквы)
_CYR_TO_LAT_MULTI: list[tuple[str, str]] = [
    ("ё", "yo"),
    ("ю", "yu"),
    ("я", "ya"),
    ("ж", "j"),
    ("ц", "ts"),
    ("ч", "ch"),
    ("ш", "sh"),
    ("щ", "sh"),
    ("ъ", ""),
    ("ь", ""),
    ("ый", "iy"),
    # Узбекские специфичные
    ("ў", "o'"),
    ("қ", "q"),
    ("ғ", "g'"),
    ("ҳ", "h"),
    ("ъ", "'"),
]

_CYR_TO_LAT_SINGLE: list[tuple[str, str]] = [
    ("а", "a"),
    ("б", "b"),
    ("в", "v"),
    ("г", "g"),
    ("д", "d"),
    ("е", "e"),
    ("з", "z"),
    ("и", "i"),
    ("й", "y"),
    ("к", "k"),
    ("л", "l"),
    ("м", "m"),
    ("н", "n"),
    ("о", "o"),
    ("п", "p"),
    ("р", "r"),
    ("с", "s"),
    ("т", "t"),
    ("у", "u"),
    ("ф", "f"),
    ("х", "x"),
    ("ы", "i"),
    ("э", "e"),
]

# Латиница → Кириллица (обратная транслитерация)
_LAT_TO_CYR_MULTI: list[tuple[str, str]] = [
    ("yo", "ё"),
    ("yu", "ю"),
    ("ya", "я"),
    ("ts", "ц"),
    ("ch", "ч"),
    ("sh", "ш"),
    ("g'", "ғ"),
    ("o'", "ў"),
    ("gh", "ғ"),
    ("kh", "х"),
]

_LAT_TO_CYR_SINGLE: list[tuple[str, str]] = [
    ("a", "а"),
    ("b", "б"),
    ("v", "в"),
    ("g", "г"),
    ("d", "д"),
    ("e", "е"),
    ("j", "ж"),
    ("z", "з"),
    ("i", "и"),
    ("y", "й"),
    ("k", "к"),
    ("l", "л"),
    ("m", "м"),
    ("n", "н"),
    ("o", "о"),
    ("p", "п"),
    ("q", "к"),
    ("r", "р"),
    ("s", "с"),
    ("t", "т"),
    ("u", "у"),
    ("f", "ф"),
    ("x", "х"),
    ("h", "х"),
]


def _has_cyrillic(text: str) -> bool:
    """Проверяем есть ли в строке кириллические символы."""
    return bool(re.search(r"[а-яёА-ЯЁа-яёҲҳҚқҒғЎў]", text))


def _has_latin(text: str) -> bool:
    """Проверяем есть ли в строке латинские символы."""
    return bool(re.search(r"[a-zA-Z]", text))


def _cyr_to_lat(text: str) -> str:
    """Переводит кириллицу в латиницу. ТТЗ → TTZ, Ташкент → Tashkent."""
    result = text.lower()
    for cyr, lat in _CYR_TO_LAT_MULTI:
        result = result.replace(cyr, lat)
    for cyr, lat in _CYR_TO_LAT_SINGLE:
        result = result.replace(cyr, lat)
    return result


def _lat_to_cyr(text: str) -> str:
    """Переводит латиницу в кириллицу. TTZ → ТТЗ, Tashkent → Ташкент."""
    result = text.lower()
    for lat, cyr in _LAT_TO_CYR_MULTI:
        result = result.replace(lat, cyr)
    for lat, cyr in _LAT_TO_CYR_SINGLE:
        result = result.replace(lat, cyr)
    return result


def _build_query_variants(query: str) -> list[str]:
    """
    Строим список вариантов для поиска.
    Пример: "ТТЗ" → ["ТТЗ", "TTZ", "ТТЗ, Uzbekistan", "TTZ, Uzbekistan"]
    Это гарантирует что поиск работает на любом языке.
    """
    base = query.strip()
    variants: list[str] = [base]

    # Добавляем транслитерированный вариант
    if _has_cyrillic(base):
        lat_variant = _cyr_to_lat(base)
        if lat_variant and lat_variant.strip() != base.lower():
            variants.append(lat_variant)
    elif _has_latin(base):
        cyr_variant = _lat_to_cyr(base)
        if cyr_variant and cyr_variant.strip() != base.lower():
            variants.append(cyr_variant)

    # Для каждого варианта добавляем версию с ", Uzbekistan"
    # чтобы Nominatim точнее находил местные объекты
    has_country = _contains_country_hint(base)
    if not has_country:
        with_country = [f"{v}, Uzbekistan" for v in variants]
        variants.extend(with_country)

    # Убираем дубликаты, сохраняем порядок
    seen: set[str] = set()
    result: list[str] = []
    for v in variants:
        key = v.lower().strip()
        if key not in seen:
            seen.add(key)
            result.append(v)

    return result


# ---------------------------------------------------------------------------
# HTTP запросы
# ---------------------------------------------------------------------------


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


# ---------------------------------------------------------------------------
# Форматирование результатов
# ---------------------------------------------------------------------------


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


def _normalize_reverse_item(item: dict[str, Any]) -> dict[str, Any] | None:
    display_name = str(item.get("display_name", "")).strip()
    if not display_name:
        return None

    try:
        lat = float(item["lat"])
        lon = float(item["lon"])
    except (KeyError, TypeError, ValueError):
        return None

    return {
        "lat": lat,
        "lon": lon,
        "display_name": display_name,
        "title": _build_title(item),
        "subtitle": _build_subtitle(item),
    }


# ---------------------------------------------------------------------------
# ГЛАВНАЯ ФУНКЦИЯ
# ---------------------------------------------------------------------------


async def search_places(query: str, accept_language: str) -> list[dict[str, Any]]:
    """
    Ищет места по запросу. Автоматически пробует все варианты:
    оригинал, транслитерацию и версии с "Uzbekistan".

    Возвращает первый непустой результат из вариантов.
    """
    cleaned = query.strip()
    if len(cleaned) < 2:
        return []

    # Генерируем все варианты запроса (с транслитерацией)
    candidates = _build_query_variants(cleaned)
    LOGGER.debug("Query variants for %r: %s", cleaned, candidates)

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
            LOGGER.warning("Geocoding failed for %r: %s", candidate, error)
            continue

        for item in payload:
            normalized = _normalize_search_item(item)
            if not normalized:
                continue

            key = (normalized["lat"], normalized["lon"], normalized["display_name"])
            if key in seen_keys:
                continue

            seen_keys.add(key)
            normalized_results.append(normalized)

        # Нашли результаты — не ищем дальше
        if normalized_results:
            break

    return normalized_results[:8]


async def reverse_place(lat: float, lon: float, accept_language: str) -> dict[str, Any] | None:
    """Возвращает строку адреса по координатам через Nominatim reverse."""
    try:
        payload = await asyncio.to_thread(
            _fetch_json,
            "/reverse",
            {
                "format": "jsonv2",
                "addressdetails": 1,
                "lat": lat,
                "lon": lon,
                "accept-language": accept_language or "ru,uz",
            },
        )
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as error:
        LOGGER.warning("Reverse geocoding failed for %r,%r: %s", lat, lon, error)
        return None

    return _normalize_reverse_item(payload)
