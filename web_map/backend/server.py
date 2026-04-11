"""
server.py — FastAPI сервер для Domix Map Mini App
"""

import os
import logging
from fastapi import FastAPI, Query
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
import uvicorn

try:
    from .geocoding import search_places
except ImportError:
    from geocoding import search_places

logging.basicConfig(level=logging.INFO)
LOGGER = logging.getLogger(__name__)

app = FastAPI(title="Domix Map API")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
FRONTEND_DIR = os.path.join(BASE_DIR, "..", "frontend")
if not os.path.isdir(FRONTEND_DIR):
    FRONTEND_DIR = BASE_DIR  # fallback: map.html лежит рядом с server.py


@app.get("/map")
async def get_map():
    """Отдаёт HTML страницу с картой."""
    html_path = os.path.join(FRONTEND_DIR, "map.html")
    if not os.path.exists(html_path):
        return JSONResponse({"error": "map.html not found"}, status_code=404)
    return FileResponse(
        html_path,
        media_type="text/html",
        headers={
            "Cache-Control": "no-cache, no-store, must-revalidate",
            "Pragma": "no-cache",
            "Expires": "0",
        },
    )


@app.get("/health")
async def health_check():
    return {"status": "ok"}


@app.get("/api/geocode/search")
async def geocode_search(
    q: str = Query(default="", min_length=2, description="Поисковый запрос"),
    lang: str = Query(default="ru,uz", description="Языки ответа"),
):
    LOGGER.info("Search request: q=%r lang=%r", q, lang)
    items = await search_places(q, lang)
    LOGGER.info("Search results: %d items for q=%r", len(items), q)
    return {"items": items}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000, reload=True)
