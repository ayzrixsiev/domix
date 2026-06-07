from aiogram.fsm.state import StatesGroup, State


class DeleteStoreState(StatesGroup):
    selecting_store = State()
