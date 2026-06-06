from aiogram.fsm.state import StatesGroup, State


# Class that group all the FSM states for registration
class RegisterState(StatesGroup):

    waiting_for_language = State()
    waiting_for_full_name = State()
    waiting_for_phone = State()
