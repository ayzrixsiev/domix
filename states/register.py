from aiogram.fsm.state import StatesGroup, State


# Класс который группирует все FSM states в регистрации
class RegisterState(StatesGroup):

    waiting_for_language = State()
    waiting_for_phone = State()
