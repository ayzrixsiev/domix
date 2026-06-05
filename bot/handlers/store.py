from aiogram import Router, types, F
from aiogram.fsm.context import FSMContext
from statesFSM.store import AddStoreState

store_router = Router()


@store_router.message(F.text.in_(["➕ Добавить магазин", "➕ Do'kon qo'shish"]))
async def start_add_store(message: types.Message, state: FSMContext):
    # 1. Fetch the user's data from the FSM scratchpad
    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")  # Fallback to 'ru' if not found

    # 2. Put the user into the waiting state for location
    await state.set_state(AddStoreState.waiting_for_location)

    # 3. Deliver localized map instructions
    if lang == "ru":
        text = (
            "📍 **Шаг 1: Укажите расположение магазина**\n\n"
            "Чтобы добавить магазин на карту Domix, выполните действия:\n"
            "1. Нажмите на иконку **Скрепки (📎)** рядом с полем ввода.\n"
            "2. Выберите пункт **'Локация' (Location)**.\n"
            "3. Перетащите маркер на карте прямо на ваш магазин.\n"
            "4. Нажмите кнопку **'Отправить выбранную локацию'**."
        )
    else:
        text = (
            "📍 **1-qadam: Do'kon joylashuvini ko'rsating**\n\n"
            "Do'konni Domix xaritasiga qo'shish uchun quyidagilarni bajaring:\n"
            "1. Kiritish maydoni yonidagi **Qog'oz qisgich (📎)** belgisini bosing.\n"
            "2. **'Joylashuv' (Location)** bo'limini tanlang.\n"
            "3. Xaritadagi belgini to'g'ri do'koningiz ustiga suring.\n"
            "4. **'Tanlangan joylashuvni yuborish'** tugmasini bosing."
        )

    await message.answer(text, parse_mode="Markdown")


@store_router.message(AddStoreState.waiting_for_location, F.location)
async def process_native_location(message: types.Message, state: FSMContext):
    lat = message.location.latitude
    lon = message.location.longitude

    # Save coordinates to our temporary FSM scratchpad
    await state.update_data(lat=lat, lon=lon)

    # Fetch language again to reply correctly
    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    if lang == "ru":
        reply_text = (
            f"✅ **Координаты получены!** (`{lat}`, `{lon}`)\n\n"
            "Теперь отправьте текстовое название вашего магазина:"
        )
    else:
        reply_text = (
            f"✅ **Koordinatalar qabul qilindi!** (`{lat}`, `{lon}`)\n\n"
            "Endi do'koningizning matnli nomini yuboring:"
        )

    await message.answer(reply_text, parse_mode="Markdown")

    # Move the user to the next logical step
    await state.set_state(AddStoreState.waiting_for_name)
