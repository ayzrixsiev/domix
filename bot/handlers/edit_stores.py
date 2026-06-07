from aiogram import Router, types, F
from aiogram.fsm.context import FSMContext
from aiogram.utils.keyboard import InlineKeyboardBuilder, ReplyKeyboardBuilder

from statesFSM.edit_store import EditStoreState
from database.requests import get_user_stores, update_store
from bot.handlers.common import show_main_profile

edit_router = Router()


# Entry point triggered from the main profile menu
@edit_router.message(F.text.in_(["📝 Редактировать", "📝 Tahrirlash"]))
async def start_edit_store(message: types.Message, state: FSMContext):
    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    # Fetch stores from database
    stores = await get_user_stores(message.from_user.id)

    if not stores:
        text = (
            "У вас пока нет добавленных магазинов."
            if lang == "ru"
            else "Sizda hali qo'shilgan do'konlar mavjud emas."
        )
        await message.answer(text)
        return

    # Build dynamic inline buttons for each store
    builder = InlineKeyboardBuilder()
    for store in stores:
        builder.button(text=store.name, callback_data=f"edit_sid_{store.id}")
    builder.adjust(1)  # Stack buttons vertically

    prompt = (
        "Выберите магазин для редактирования:"
        if lang == "ru"
        else "Tahrirlash uchun do'konni tanlang:"
    )

    await message.answer(prompt, reply_markup=builder.as_markup())
    await state.set_state(EditStoreState.selecting_store)


# Processing store selection via inline callback data
@edit_router.callback_query(
    EditStoreState.selecting_store, F.data.startswith("edit_sid_")
)
async def store_selected(callback: types.CallbackQuery, state: FSMContext):
    store_id = int(callback.data.split("_")[3])
    await state.update_data(editing_store_id=store_id)

    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    # Offer fields to edit
    builder = InlineKeyboardBuilder()
    if lang == "ru":
        builder.button(text="📝 Название", callback_data="field_name")
        builder.button(text="📍 Адрес (текст)", callback_data="field_address")
        builder.button(text="🗺 Координаты", callback_data="field_location")
        text = "Что именно вы хотите изменить?"
    else:
        builder.button(text="📝 Nomini", callback_data="field_name")
        builder.button(text="📍 Manzilni (matn)", callback_data="field_address")
        builder.button(text="🗺 Koordinatalarni", callback_data="field_location")
        text = "Aynan nimani o'zgartirmoqchisiz?"

    builder.adjust(1)
    await callback.message.edit_text(text, reply_markup=builder.as_markup())
    await state.set_state(EditStoreState.choosing_field)


# Processing target field selection
@edit_router.callback_query(EditStoreState.choosing_field, F.data.startswith("field_"))
async def field_selected(callback: types.CallbackQuery, state: FSMContext):
    field = callback.data.split("_")[1]
    await state.update_data(editing_field=field)

    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    # Remove inline layout and prompt for input
    await callback.message.delete()

    if field == "name":
        prompt = (
            "Отправьте новое название магазина:"
            if lang == "ru"
            else "Do'konning yangi nomini yuboring:"
        )
        await callback.message.answer(prompt)
    elif field == "address":
        prompt = (
            "Отправьте новый текстовый адрес:"
            if lang == "ru"
            else "Yangi matnli manzilni yuboring:"
        )
        await callback.message.answer(prompt)
    elif field == "location":
        # Request location object via native button interface
        builder = ReplyKeyboardBuilder()
        builder.row(
            types.KeyboardButton(
                text=(
                    "📍 Отправить локацию"
                    if lang == "ru"
                    else "📍 Lokatsiyani yuborish"
                ),
                request_location=True,
            )
        )
        prompt = (
            "Отправьте новые координаты через кнопку:"
            if lang == "ru"
            else "Yangi koordinatalarni tugma orqali yuboring:"
        )
        await callback.message.answer(
            prompt, reply_markup=builder.as_markup(resize_keyboard=True)
        )

    await state.set_state(EditStoreState.waiting_for_new_value)


# Applying the text changes (Name or Address)
@edit_router.message(EditStoreState.waiting_for_new_value, F.text)
async def process_text_update(message: types.Message, state: FSMContext):
    user_data = await state.get_data()
    store_id = user_data.get("editing_store_id")
    field = user_data.get("editing_field")
    lang = user_data.get("chosen_lang", "ru")

    if field == "name":
        await update_store(store_id, name=message.text)
    elif field == "address":
        await update_store(store_id, address=message.text)

    success = (
        "Данные успешно обновлены!"
        if lang == "ru"
        else "Ma'lumotlar muvaffaqiyatli yangilandi!"
    )
    await message.answer(success, reply_markup=types.ReplyKeyboardRemove())
    await show_main_profile(message, state)
    await state.set_state(None)


# Applying coordinate changes
@edit_router.message(EditStoreState.waiting_for_new_value, F.location)
async def process_location_update(message: types.Message, state: FSMContext):
    user_data = await state.get_data()
    store_id = user_data.get("editing_store_id")
    lang = user_data.get("chosen_lang", "ru")

    lat = message.location.latitude
    lon = message.location.longitude

    # Update both layout metrics simultaneously in the kwargs parameters
    await update_store(store_id, lat=lat, lon=lon)

    success = (
        "Координаты успешно обновлены!"
        if lang == "ru"
        else "Koordinatalar muvaffaqiyatli yangilandi!"
    )
    await message.answer(success, reply_markup=types.ReplyKeyboardRemove())
    await show_main_profile(message, state)
    await state.set_state(None)
