import os
from dotenv import load_dotenv
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from .models import Base

load_dotenv()

DB_URL = os.getenv("DB_URL")

# Creating an engine (that connects with the db)
engine = create_async_engine(DB_URL, echo=True)

# We are creating a factory of sessions (each call for the db - session)
session_factory = async_sessionmaker(
    bind=engine, class_=AsyncSession, expire_on_commit=False
)


# Function helper which gives us sessions
async def get_session():
    async with session_factory() as session:
        yield session
