from aiogram import Router, types, F
from aiogram.fsm.context import FSMContext
from states.store import AddStoreState

store_router = Router()


# Кнопка которая откроает карту чтобы выбрать магазин из нее
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
                        web_app=types.WebAppInfo(url="ТВОЙ_URL_ЗДЕСЬ"),
                    )
                ]
            ],
            resize_keyboard=True,
        ),
    )
