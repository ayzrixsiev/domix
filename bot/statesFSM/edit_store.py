from aiogram.fsm.state import StatesGroup, State


class EditStoreState(StatesGroup):
    selecting_store = State()  # Waiting for user to choose which store to edit
    choosing_field = (
        State()
    )  # Waiting for user to select what to edit (Name, Address, Location)
    waiting_for_new_value = State()  # Waiting for the actual text/location update
