from aiogram.fsm.state import StatesGroup, State


class AddStoreState(StatesGroup):
    waiting_for_location = State()  # Ждем координаты из Web App
    waiting_for_name = State()  # Ждем название
    waiting_for_phone = State()  # Ждем номер телефона магазина
    waiting_for_photo = State()  # Ждем фото (1-3 шт)
    confirm_store = State()  # Финальное подтверждение
