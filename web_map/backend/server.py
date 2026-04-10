from fastapi import FastAPI, Query
from fastapi.responses import FileResponse
import uvicorn
import os

try:
    from .geocoding import search_places
except ImportError:
    from geocoding import search_places

app = FastAPI()

frontend_path = os.path.join(os.path.dirname(__file__), "..", "frontend")


@app.get("/map")
async def get_map():
    # Отдаем файл map.html по адресу
    return FileResponse(os.path.join(frontend_path, "map.html"))


# Тестовый эндпоинт, чтобы проверить работает ли сервер
@app.get("/health")
async def health_check():
    return {"status": "ok", "message": "Server is running"}


@app.get("/api/geocode/search")
async def geocode_search(
    q: str = Query(default="", min_length=2),
    lang: str = Query(default="ru,uz"),
):
    return {"items": await search_places(q, lang)}


if __name__ == "__main__":
    # Запускаем на 0.0.0.0, чтобы сервер был доступен извне (через ngrok)
    uvicorn.run(app, host="0.0.0.0", port=8000)
