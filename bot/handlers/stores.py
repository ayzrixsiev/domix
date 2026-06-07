from aiogram import Router, types, F
from aiogram.fsm.context import FSMContext
from statesFSM.store import AddStoreState
from database.requests import add_store
from bot.handlers.common import show_main_profile

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
            "✅ **Координаты получены!\n\n"
            "Теперь отправьте текстовый адрес вашего магазина (например: *Ташкент, Чиланзар-2, ул. Гагарина, 14*):"
        )
    else:
        reply_text = (
            "✅ **Koordinatalar qabul qilindi!\n\n"
            "Endi do'koningizning matnli manzilini yuboring (masalan: *Toshkent, Chilonzor-2, Gagarin ko'chasi, 14-uy*):"
        )

    await message.answer(reply_text, parse_mode="Markdown")

    # Move the user to the next logical step
    await state.set_state(AddStoreState.waiting_for_address)


@store_router.message(AddStoreState.waiting_for_address)
async def process_store_address(message: types.Message, state: FSMContext):
    # Save address to our temporary FSM scratchpad
    await state.update_data(address=message.text)

    # Fetch language again to reply correctly
    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    if lang == "ru":
        reply_text = "Теперь отправьте текстовое название вашего магазина:"
    else:
        reply_text = "Endi do'koningizning nomini yuboring:"

    await message.answer(reply_text, parse_mode="Markdown")

    # Move the user to the next step to gather the mandatory database address field
    await state.set_state(AddStoreState.waiting_for_name)


# Store name processing
@store_router.message(AddStoreState.waiting_for_name)
async def process_store_name(message: types.Message, state: FSMContext):
    # Save name to our temporary FSM scratchpad
    await state.update_data(name=message.text)

    # Fetch all gathered puzzle pieces from our FSM scratchpad
    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    # Execute the database write operation now that all NOT NULL constraints are satisfied
    await add_store(
        tg_id=message.from_user.id,
        name=user_data.get("name"),
        address=user_data.get("address"),
        lat=user_data.get("lat"),
        lon=user_data.get("lon"),
    )

    if lang == "ru":
        success_text = (
            "🎉 **Поздравляем! Ваш магазин успешно добавлен в Domix!**\n\n"
            "Вы можете продолжить настройку профиля или добавить товары."
        )
    else:
        success_text = (
            "🎉 **Tabriklaymiz! Do'koningiz Domix ilovasiga muvaffaqiyatli qo'shildi!**\n\n"
            "Profilingizni sozlashda davom etishingiz yoki mahsulotlar qo'shishingiz mumkin."
        )

    await message.answer(success_text, parse_mode="Markdown")
    await show_main_profile(message, state)

    # Clear only the store creation FSM state since the workflow is fully completed
    # This leaves 'chosen_lang' intact inside the FSM data dictionary for future use
    await state.set_state(None)
