from datetime import datetime
from typing import List
from sqlalchemy import BigInteger, String, Float, Text, DateTime, ForeignKey, Index
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
from sqlalchemy.sql import func


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(
        primary_key=True
    )  # Для всей внутренней логики и связей между таблицами.
    # Индекс на tg_id критически важен для скорости
    tg_id: Mapped[int] = mapped_column(
        BigInteger, unique=True, index=True
    )  # ТГ айди, важен для скорости, чтобы найти юзера, когда он пишет боту
    username: Mapped[str | None] = mapped_column(
        String(32)
    )  # ТГ юзер, для менеджеров и поддержки
    full_name: Mapped[str | None] = mapped_column(String(128))  # Полное имя
    language: Mapped[str] = mapped_column(
        String(2), server_default="ru"
    )  # Язык выбранный юзером
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now()
    )  # Время когда регался

    # Связь: Один пользователь может иметь много магазинов
    stores: Mapped[List["Store"]] = relationship(
        back_populates="owner", cascade="all, delete-orphan"
    )


class Store(Base):
    __tablename__ = "stores"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(
        String(100), index=True
    )  # Индекс для поиска по названию
    address: Mapped[str] = mapped_column(Text)

    # Координаты для карты
    lat: Mapped[float] = mapped_column(Float)
    lon: Mapped[float] = mapped_column(Float)

    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    owner: Mapped["User"] = relationship(back_populates="stores")

    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    # Составной индекс для быстрого поиска по координатам (Гео-флоат)
    __table_args__ = (Index("ix_store_location", "lat", "lon"),)
    # Postgres создает «сортированную карту» координат. Он мгновенно отсекает 99% магазинов, которые не попадают в диапазон, и выдает результат за миллисекунды.
