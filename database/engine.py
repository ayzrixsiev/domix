import os
from dotenv import load_dotenv
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from .models import Base

load_dotenv()

DB_URL = os.getenv("DB_URL")

# Создаем движок
engine = create_async_engine(DB_URL, echo=True)

# Создаем фабрику сессий (каждый запрос к базе — это сессия)
session_factory = async_sessionmaker(
    bind=engine, class_=AsyncSession, expire_on_commit=False
)


# Функция-помощник для получения сессии
async def get_session():
    async with session_factory() as session:
        yield session
