from aiogram import Router, types, F
from aiogram.fsm.context import FSMContext
from aiogram.utils.keyboard import InlineKeyboardBuilder, ReplyKeyboardBuilder

from bot.statesFSM.edit_store import EditStoreState
from database.requests import get_user_stores, update_store
from bot.handlers.register import show_main_profile

edit_router = Router()


# Pick a store
@edit_router.callback_query(F.data == "menu_edit_store")
async def start_edit_store(callback: types.CallbackQuery, state: FSMContext):
    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    stores = await get_user_stores(callback.from_user.id)
    builder = InlineKeyboardBuilder()

    if not stores:
        text = (
            "У вас пока нет добавленных магазинов."
            if lang == "ru"
            else "Sizda hali qo'shilgan do'konlar mavjud emas."
        )
        builder.button(
            text="↩️ Назад" if lang == "ru" else "↩️ Orqaga",
            callback_data="go_to_main_menu",
        )
        await callback.message.edit_text(text, reply_markup=builder.as_markup())
        await callback.answer()
        return

    # Build dynamic inline buttons for each store
    for store in stores:
        builder.button(text=store.name, callback_data=f"edit_sid_{store.id}")

    # Navigation fallback back to menu hub
    builder.button(
        text="↩️ Назад" if lang == "ru" else "↩️ Orqaga",
        callback_data="go_to_main_menu",
    )
    builder.adjust(1)

    prompt = (
        "Выберите магазин для редактирования:"
        if lang == "ru"
        else "Tahrirlash uchun do'konni tanlang:"
    )

    await callback.message.edit_text(prompt, reply_markup=builder.as_markup())
    await state.set_state(EditStoreState.selecting_store)
    await callback.answer()


# Pick what to edit in store
@edit_router.callback_query(
    EditStoreState.selecting_store, F.data.startswith("edit_sid_")
)
async def store_selected(callback: types.CallbackQuery, state: FSMContext):
    # Fixed index calculation bug here from [3] to [2]
    store_id = int(callback.data.split("_")[2])
    await state.update_data(editing_store_id=store_id)

    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    builder = InlineKeyboardBuilder()
    if lang == "ru":
        builder.button(text="📝 Название", callback_data="field_name")
        builder.button(text="📍 Адрес (текст)", callback_data="field_address")
        builder.button(text="🗺 Координаты", callback_data="field_location")
        builder.button(text="↩️ Назад", callback_data="menu_edit_store")
        text = "Что именно вы хотите изменить?"
    else:
        builder.button(text="📝 Nomini", callback_data="field_name")
        builder.button(text="📍 Manzilni (matn)", callback_data="field_address")
        builder.button(text="🗺 Koordinatalarni", callback_data="field_location")
        builder.button(text="↩️ Orqaga", callback_data="menu_edit_store")
        text = "Aynan nimani o'zgartirmoqchisiz?"

    builder.adjust(1)
    await callback.message.edit_text(text, reply_markup=builder.as_markup())
    await state.set_state(EditStoreState.choosing_field)
    await callback.answer()


# Processing target field selection
@edit_router.callback_query(EditStoreState.choosing_field, F.data.startswith("field_"))
async def field_selected(callback: types.CallbackQuery, state: FSMContext):
    field = callback.data.split("_")[1]
    await state.update_data(editing_field=field)

    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    # Inline cancel button to let them back out before sending messages
    cancel_builder = InlineKeyboardBuilder()
    cancel_builder.button(
        text="❌ Отмена" if lang == "ru" else "❌ Bekor qilish",
        callback_data="go_to_main_menu",
    )

    if field == "name":
        prompt = (
            "Отправьте новое название магазина:"
            if lang == "ru"
            else "Do'konning yangi nomini yuboring:"
        )
        await callback.message.edit_text(
            prompt, reply_markup=cancel_builder.as_markup()
        )

    elif field == "address":
        prompt = (
            "Отправьте новый текстовый адрес:"
            if lang == "ru"
            else "Yangi matnli manzilni yuboring:"
        )
        await callback.message.edit_text(
            prompt, reply_markup=cancel_builder.as_markup()
        )

    elif field == "location":
        # Native location requests require a physical Reply Keyboard panel popup
        await callback.message.delete()  # Clear inline trace out of screen cleanly

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
    await callback.answer()


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
    await message.answer(success)
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

    await update_store(store_id, lat=lat, lon=lon)

    success = (
        "Координаты успешно обновлены!"
        if lang == "ru"
        else "Koordinatalar muvaffaqiyatli yangilandi!"
    )
    # Drops the temporary native location reply layout back down
    await message.answer(success, reply_markup=types.ReplyKeyboardRemove())
    await show_main_profile(message, state)
    await state.set_state(None)
