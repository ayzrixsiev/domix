import re
from aiogram import Router, types, F
from aiogram.filters import Command
from aiogram.fsm.context import FSMContext
from aiogram.utils.keyboard import ReplyKeyboardBuilder, InlineKeyboardBuilder

from bot.statesFSM.register import RegisterState
from database.requests import set_user

common_router = Router()


# Initial detector, event listener
@common_router.message(Command("start"))
async def cmd_start(message: types.Message, state: FSMContext):
    await state.clear()

    builder = ReplyKeyboardBuilder()
    builder.row(
        types.KeyboardButton(text="Русский 🇷🇺"),
        types.KeyboardButton(text="O'zbekcha 🇺🇿"),
    )

    await message.answer(
        f"<b>Добро пожаловать в Domix Bot!</b>\n"
        f"Здесь владельцы магазинов могут добавлять свои магазины и товары на карту.\n"
        f"Для продолжения, пожалуйста, выберите язык.\n\n"
        f"<b>Domix Bot-ga xush kelibsiz!</b>\n"
        f"Bu yerda do'kon egalari o'z do'konlari va mahsulotlarini xaritaga qo'shishlari mumkin.\n"
        f"Davom etish uchun iltimos, tilni tanlang.",
        reply_markup=builder.as_markup(resize_keyboard=True),
    )
    await state.set_state(RegisterState.waiting_for_language)


# Language pick
@common_router.message(
    RegisterState.waiting_for_language, F.text.in_(["Русский 🇷🇺", "O'zbekcha 🇺🇿"])
)
async def language_selected(message: types.Message, state: FSMContext):
    lang = "ru" if "Русский" in message.text else "uz"
    await state.update_data(chosen_lang=lang)

    name_prompt = (
        "Пожалуйста, введите ваше имя и фамилию:"
        if lang == "ru"
        else "Iltimos, ism va familiyangizni kiriting:"
    )
    await message.answer(name_prompt, reply_markup=types.ReplyKeyboardRemove())
    await state.set_state(RegisterState.waiting_for_full_name)


# Full name processing
@common_router.message(RegisterState.waiting_for_full_name)
async def process_full_name(message: types.Message, state: FSMContext):
    await state.update_data(full_name=message.text)

    user_data = await state.get_data()
    lang = user_data.get("chosen_lang")

    builder = ReplyKeyboardBuilder()
    builder.row(
        types.KeyboardButton(
            text=(
                "📱 Отправить номер телефона"
                if lang == "ru"
                else "📱 Telefon raqamni yuborish"
            ),
            request_contact=True,
        )
    )
    text = (
        "Пожалуйста, поделитесь вашим номером телефона для регистрации в формате +99899123456."
        if lang == "ru"
        else "Ro'yxatdan o'tish uchun telefon raqamingizni yuboring, ushbu formatda +99899123456."
    )
    await message.answer(text, reply_markup=builder.as_markup(resize_keyboard=True))
    await state.set_state(RegisterState.waiting_for_phone)


@common_router.message(RegisterState.waiting_for_phone)
async def process_contact(message: types.Message, state: FSMContext):
    user_data = await state.get_data()
    lang = user_data.get("chosen_lang")

    if message.contact:
        phone_number = message.contact.phone_number
    else:
        phone_number = message.text

    phone_number = "".join(filter(str.isdigit, phone_number))

    if not phone_number.startswith("+"):
        phone_number = (
            f"+{phone_number}" if phone_number.startswith("998") else f"+{phone_number}"
        )

    uz_phone_regex = r"^\+998\d{9}$"

    if re.match(uz_phone_regex, phone_number):
        await state.update_data(phone=phone_number)

        await set_user(
            tg_id=message.from_user.id,
            phone_number=phone_number,
            username=message.from_user.username,
            full_name=user_data.get("full_name"),
            language=lang,
        )

        success_text = (
            f"Отлично! Номер {phone_number} подтвержден.\nПереходим в ваш профиль..."
            if lang == "ru"
            else f"Ajoyib! {phone_number} raqami tasdiqlandi.\nProfilingizga o'tilmoqda..."
        )

        # Drops the reply buttons panel down completely
        await message.answer(success_text, reply_markup=types.ReplyKeyboardRemove())

        # Launch inline layout profile choice
        await show_main_profile(message, state)
    else:
        fail_text = (
            "Неверный формат номера. Пожалуйста, отправьте номер кнопкой или введите вручную: +998XXXXXXXXX."
            if lang == "ru"
            else "Raqam formati noto'g'ri. Iltimos, raqamni tugma orqali yuboring yoki qo'lda kiriting: +998XXXXXXXXX"
        )
        await message.answer(fail_text)


# Main menu
async def show_main_profile(
    event: types.Message | types.CallbackQuery, state: FSMContext
):
    data = await state.get_data()
    lang = data.get("chosen_lang", "uz")

    builder = InlineKeyboardBuilder()
    if lang == "ru":
        builder.row(
            types.InlineKeyboardButton(
                text="➕ Добавить магазин", callback_data="menu_add_store"
            )
        )
        builder.row(
            types.InlineKeyboardButton(
                text="📝 Редактировать", callback_data="menu_edit_store"
            ),
            types.InlineKeyboardButton(
                text="🗑 Удалить", callback_data="menu_delete_store"
            ),
        )
        builder.row(
            types.InlineKeyboardButton(
                text="📦 Добавить товары", callback_data="menu_add_products"
            )
        )
        builder.row(
            types.InlineKeyboardButton(
                text="🏢 Мои магазины", callback_data="menu_view_stores"
            )
        )
        msg = "<b>Ваш профиль</b>\n\nЧто хотите сделать?"
    else:
        builder.row(
            types.InlineKeyboardButton(
                text="➕ Do'kon qo'shish", callback_data="menu_add_store"
            )
        )
        builder.row(
            types.InlineKeyboardButton(
                text="📝 Tahrirlash", callback_data="menu_edit_store"
            ),
            types.InlineKeyboardButton(
                text="🗑 O'chirish", callback_data="menu_delete_store"
            ),
        )
        builder.row(
            types.InlineKeyboardButton(
                text="📦 Mahsulot qo'shish", callback_data="menu_add_products"
            )
        )
        builder.row(
            types.InlineKeyboardButton(
                text="🏢 Mening do'konlarim", callback_data="menu_view_stores"
            )
        )
        msg = "<b>Sizning profilingiz</b>\n\nNima qilmoqchisiz?"

    # Switch display pattern based on structural event type
    if isinstance(event, types.CallbackQuery):
        await event.message.edit_text(msg, reply_markup=builder.as_markup())
        await event.answer()
    else:
        await event.answer(msg, reply_markup=builder.as_markup())

    await state.set_state(None)


@common_router.callback_query(F.data == "go_to_main_menu")
async def handle_back_to_menu(callback: types.CallbackQuery, state: FSMContext):
    """Catch-all for 'Back' actions across your entire application."""
    await state.clear()
    await show_main_profile(callback, state)
