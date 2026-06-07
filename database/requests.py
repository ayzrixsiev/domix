import pandas as pd
from database.engine import session_factory
from database.models import User, Store, Product
from sqlalchemy import select, update, delete


# Add user
async def set_user(tg_id: int, username: str, full_name: str, language: str):
    """
    Saves a user to the database if they don't exist,
    or updates their fields if they already exist.
    """
    async with session_factory() as session:
        query = select(User).where(User.tg_id == tg_id)
        result = await session.execute(query)
        user = result.scalar_one_or_none()

        if not user:
            new_user = User(
                tg_id=tg_id, username=username, full_name=full_name, language=language
            )
            session.add(new_user)
            await session.commit()
            return new_user
        else:
            user.username = username
            user.full_name = full_name
            user.language = language
            await session.commit()
            return user


# Add store
async def add_store(tg_id: int, name: str, address: str, lat: float, lon: float):
    """
    Fetches the internal database ID of the user using their tg_id,
    then saves the complete store profile.
    """
    async with session_factory() as session:
        # Find the internal user.id using the external tg_id
        user_query = select(User.id).where(User.tg_id == tg_id)
        user_result = await session.execute(user_query)
        internal_owner_id = user_result.scalar()

        if not internal_owner_id:
            raise ValueError("User not found in database.")

        # Create the complete store with all required fields
        new_store = Store(
            name=name, address=address, lat=lat, lon=lon, owner_id=internal_owner_id
        )
        session.add(new_store)
        await session.commit()


# Edit store
async def get_user_stores(tg_id: int):
    """
    Fetches all stores owned by a specific Telegram user ID.
    """
    async with session_factory() as session:
        # We find the user first, then load their related stores via relationship
        query = select(User).where(User.tg_id == tg_id)
        result = await session.execute(query)
        user = result.scalar_one_or_none()

        if user:
            # Accessing the relationship shortcut we established earlier
            return user.stores
        return []


async def update_store(store_id: int, **kwargs):
    """
    Dynamically updates specified fields of a store by its internal ID.
    Usage: await update_store(store_id, name="New Name")
    """
    async with session_factory() as session:
        query = update(Store).where(Store.id == store_id).values(**kwargs)
        await session.execute(query)
        await session.commit()


# Delete store
async def delete_store(store_id: int):
    """
    Permanently deletes a store from PostgreSQL by its internal ID.
    """
    async with session_factory() as session:
        query = delete(Store).where(Store.id == store_id)
        await session.execute(query)
        await session.commit()


# Add products to the store
async def add_products_from_dataframe(store_id: int, df: pd.DataFrame):
    async with session_factory() as session:
        # Fill empty cells with safe default values to prevent database constraint errors
        df = df.fillna(
            {
                "Артикул": "",
                "Категория": "Без категории",
                "Наименование товара": "Без названия",
                "Цена (сум)": 0.0,
                "Единица измерения": "шт",
                "Наличие": "Есть",
            }
        )

        products = []
        for _, row in df.iterrows():
            products.append(
                Product(
                    store_id=store_id,
                    article=str(row["Артикул"]),
                    category=str(row["Категория"]),
                    name=str(row["Наименование товара"]),
                    price=float(row["Цена (сум)"]),
                    unit=str(row["Единица измерения"]),
                    availability=str(row["Наличие"]),
                )
            )

        session.add_all(products)
        await session.commit()
