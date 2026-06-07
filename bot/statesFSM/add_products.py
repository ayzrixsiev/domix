from aiogram.fsm.state import StatesGroup, State


class AddProductsState(StatesGroup):
    selecting_store = State()  # Waiting for user to pick a store from inline buttons
    waiting_for_file = State()  # Waiting for the .xlsx document upload
