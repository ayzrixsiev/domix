import pandas as pd
from database.engine import session_factory
from database.models import User, Store, Product
from sqlalchemy import select, update, delete


# Add user
async def set_user(
    tg_id: int, phone_number: str, username: str, full_name: str, language: str
):

    async with session_factory() as session:
        # Look if user with this tg id already exists
        query = select(User).where(User.tg_id == tg_id)
        result = await session.execute(query)
        user = result.scalar_one_or_none()

        if not user:  # Add enw user if does not exists
            new_user = User(
                tg_id=tg_id,
                phone_number=phone_number,
                username=username,
                full_name=full_name,
                language=language,
            )
            session.add(new_user)
            await session.commit()
            return new_user
        else:  # In case there are any changes, update them
            user.username = username
            user.phone_number = phone_number
            user.full_name = full_name
            user.language = language
            await session.commit()
            return user


# Add store
async def add_store(tg_id: int, name: str, address: str, lat: float, lon: float):

    async with session_factory() as session:
        # Fetch the user id to set up owner_id column in store and make it a child to the user
        query = select(User.id).where(User.tg_id == tg_id)
        result = await session.execute(query)
        owner_id = result.scalar()

        if not owner_id:
            raise ("User not found in database")

        new_store = Store(
            name=name, address=address, lat=lat, lon=lon, owner_id=owner_id
        )
        session.add(new_store)
        await session.commit()


# View user stores
async def get_user_stores(tg_id: int):
    async with (
        session_factory() as session
    ):  # Fixed: changed async_session to session_factory
        # Query stores directly by looking up the owner's auto-incrementing ID
        stmt = select(Store).where(
            Store.owner_id
            == select(User.id).where(User.tg_id == tg_id).scalar_subquery()
        )
        result = await session.execute(stmt)
        return result.scalars().all()


# Edit store
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
