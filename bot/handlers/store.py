from aiogram import Router, types, F
from aiogram.fsm.context import FSMContext
from statesFSM.store import AddStoreState

store_router = Router()


# Button which opens up a map
@store_router.message(F.text.in_(["➕ Добавить магазин", "➕ Do'kon qo'shish"]))
async def start_add_store(message: types.Message, state: FSMContext):
    await state.set_state(AddStoreState.waiting_for_location)

    await message.answer(
        "Нажмите на кнопку ниже, чтобы выбрать местоположение магазина на карте:",
        reply_markup=types.ReplyKeyboardMarkup(
            keyboard=[
                [
                    types.KeyboardButton(
                        text="📍 Открыть карту",
                        web_app=types.WebAppInfo(
                            url="https://jeep-prepay-penholder.ngrok-free.dev/map"  # Сервер вызывает API эндпоинты
                        ),
                    )
                ]
            ],
            resize_keyboard=True,
        ),
    )
