from datetime import datetime
from typing import List
from sqlalchemy import (
    Integer,
    BigInteger,
    String,
    Float,
    Text,
    DateTime,
    ForeignKey,
    Index,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
from sqlalchemy.sql import func


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(
        primary_key=True
    )  # All data entities will be referinng to this column using this id
    phone_number: Mapped[str] = mapped_column(String(20), unique=True)
    tg_id: Mapped[int] = mapped_column(
        BigInteger, unique=True, index=True
    )  # Save a tg id of users for faster verification
    username: Mapped[str | None] = mapped_column(
        String(32)
    )  # Additional info about user (@username)
    full_name: Mapped[str | None] = mapped_column(String(128))
    language: Mapped[str] = mapped_column(
        String(2), server_default="ru"
    )  # Language chosen by the user to interact with the bot
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now()
    )  # Time when user registered

    # One-to-many relationship, one user can have many stores. We use this relationship to be able to target certain store and delete it,
    # without any need to remove a whole user. It also helps us go through Stores using user table, like: stores.owner.full_name
    stores: Mapped[List["Store"]] = relationship(
        back_populates="owner", cascade="all, delete-orphan"
    )


class Store(Base):
    __tablename__ = "stores"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(
        String(100), index=True
    )  # Index to search a shop by it's name
    address: Mapped[str] = mapped_column(Text)

    # Coordinates for the map
    lat: Mapped[float] = mapped_column(Float)
    lon: Mapped[float] = mapped_column(Float)

    # Hold a value of id column from User table, when a user is deleted, all stores holding this value will be removed as well
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    # This is a navigation shortcut. We can access all the attributes of the user through the store and vice versa
    owner: Mapped["User"] = relationship(back_populates="stores")

    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    products: Mapped[List["Product"]] = relationship(
        back_populates="store", cascade="all, delete-orphan"
    )

    # Composite index for high performance stores look up in a certain territory
    # It creates a B-Tree which helps us ignore unecessary stores and do not waste time traversing through the whole table, which gives us answer in millis
    __table_args__ = (Index("ix_store_location", "lat", "lon"),)


class Product(Base):
    __tablename__ = "products"

    # Excel file structure
    id: Mapped[int] = mapped_column(primary_key=True)
    article: Mapped[str | None] = mapped_column(String(50))  # Артикул
    category: Mapped[str] = mapped_column(String(100), index=True)  # Категория
    name: Mapped[str] = mapped_column(String(255), index=True)  # Наименование товара
    price: Mapped[float] = mapped_column(Float)  # Цена (сум)
    unit: Mapped[str] = mapped_column(
        String(20), default="шт"
    )  # Единица измерения (шт/кг/м²)
    availability: Mapped[str] = mapped_column(
        String(50), default="Есть"
    )  # Наличие (Есть/Под заказ/Нет)

    # Connection to the one unique store
    store_id: Mapped[int] = mapped_column(ForeignKey("stores.id", ondelete="CASCADE"))
    store: Mapped["Store"] = relationship(back_populates="products")
