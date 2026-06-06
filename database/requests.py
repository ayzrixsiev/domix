from database.engine import session_factory
from database.models import User, Store
from sqlalchemy import select


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
