from aiogram import Router, types, F
from aiogram.fsm.context import FSMContext
from aiogram.types import ReplyKeyboardRemove
from bot.statesFSM.store import AddStoreState
from database.requests import add_store
from bot.handlers.register import show_main_profile

store_router = Router()


# Store address from map
@store_router.callback_query(F.data == "menu_add_store")
async def start_add_store(callback: types.CallbackQuery, state: FSMContext):
    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    await state.set_state(AddStoreState.waiting_for_location)

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

    # Edit the main menu message in place
    await callback.message.edit_text(text, parse_mode="Markdown")
    await callback.answer()


# Store address in the form of text
@store_router.message(AddStoreState.waiting_for_location, F.location)
async def process_native_location(message: types.Message, state: FSMContext):
    lat = message.location.latitude
    lon = message.location.longitude

    await state.update_data(lat=lat, lon=lon)

    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    if lang == "ru":
        reply_text = (
            "✅ **Координаты получены!**\n\n"
            "Теперь отправьте текстовый адрес вашего магазина (например: *Ташкент, Чиланзар-2, ул. Гагарина, 14*):"
        )
    else:
        reply_text = (
            "✅ **Koordinatalar qabul qilindi!**\n\n"
            "Endi do'koningizning matnli manzilini yuboring (masalan: *Toshkent, Chilonzor-2, Gagarin ko'chasi, 14-uy*):"
        )

    await message.answer(reply_text, parse_mode="Markdown")
    await state.set_state(AddStoreState.waiting_for_address)


# Store name
@store_router.message(AddStoreState.waiting_for_address)
async def process_store_address(message: types.Message, state: FSMContext):
    await state.update_data(address=message.text)

    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    if lang == "ru":
        reply_text = "Теперь отправьте текстовое название вашего магазина:"
    else:
        reply_text = "Endi do'koningizning nomini yuboring:"

    await message.answer(reply_text, parse_mode="Markdown")
    await state.set_state(AddStoreState.waiting_for_name)


@store_router.message(AddStoreState.waiting_for_name)
async def process_store_name(message: types.Message, state: FSMContext):
    await state.update_data(name=message.text)

    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

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

    # This will send a clean new inline menu right underneath the success text
    await show_main_profile(message, state)
    await state.set_state(None)
