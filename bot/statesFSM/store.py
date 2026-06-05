from aiogram.fsm.state import StatesGroup, State


# Class for grouping all FSM states for adding store
class AddStoreState(StatesGroup):
    waiting_for_location = State()  # Wait for store coordinates
    waiting_for_name = State()  # Wait for store name
    waiting_for_phone = State()  # Wait for store contact number
    waiting_for_photo = State()  # Wait for photos 1-3
    confirm_store = State()  # Wait for final confirmation
