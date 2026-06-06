import re
from aiogram import Router, types, F
from aiogram.filters import Command
from aiogram.fsm.context import FSMContext
from aiogram.utils.keyboard import ReplyKeyboardBuilder

from statesFSM.register import RegisterState
from database.requests import set_user

common_router = Router()  # Common router, combines all the routers into one place


# Initial detector, event listener
@common_router.message(Command("start"))
async def cmd_start(message: types.Message, state: FSMContext):

    # As soon as user presses start, we clean up his previous history (FSM)
    await state.clear()

    # Button for picking a language
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

    # Change the state in FSM
    await state.set_state(RegisterState.waiting_for_language)


# Language pick
@common_router.message(
    RegisterState.waiting_for_language, F.text.in_(["Русский 🇷🇺", "O'zbekcha 🇺🇿"])
)
async def language_selected(message: types.Message, state: FSMContext):
    # Temporarily saving the language to communicate with the user with convinient language
    lang = "ru" if "Русский" in message.text else "uz"
    # Update FSM data for this particular user
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

    user_data = (
        await state.get_data()
    )  # All data about user is stored into the user_data
    lang = user_data.get(
        "chosen_lang"
    )  # And our of this user data we are extracting chosen language

    # Check how we got the phone number, via button or text
    if message.contact:
        phone_number = message.contact.phone_number
    else:
        phone_number = message.text

    phone_number = "".join(filter(str.isdigit, phone_number))

    # Add + if it's missing
    if not phone_number.startswith("+"):
        # If user entered 998..., cast into +998...
        if phone_number.startswith("998"):
            phone_number = f"+{phone_number}"
        else:
            # If number is without country number 901234567
            phone_number = f"+{phone_number}"

    # Validate using Regex (Uzbekistan format: +998 XX XXX XX XX)
    # \+998 — starts with +998
    # \d{9} — exactly 9 numbers after country code
    uz_phone_regex = r"^\+998\d{9}$"

    if re.match(uz_phone_regex, phone_number):
        # If number is correct save it (info about user)
        await state.update_data(phone=phone_number)

        # Write the data directly down to PostgreSQL using your manually gathered FSM name
        await set_user(
            tg_id=message.from_user.id,
            username=message.from_user.username,
            full_name=user_data.get("full_name"),
            language=lang,
        )

        success_text = (
            f"Отлично! Номер {phone_number} подтвержден.\nПереходим в ваш профиль..."
            if lang == "ru"
            else f"Ajoyib! {phone_number} raqami tasdiqlandi.\nProfilingizga o'tilmoqda..."
        )
        await message.answer(
            success_text, reply_markup=types.ReplyKeyboardRemove()
        )  # Print the text and clear the buttons

        # In the future we will be checking whether the user is in db
        await show_main_profile(message, state)

    else:
        # If number did not pass validation
        fail_text = (
            "Неверный формат номера. Пожалуйста, отправьте номер кнопкой или введите вручную: +998XXXXXXXXX."
            if lang == "ru"
            else "Raqam formati noto'g'ri. Iltimos, raqamni tugma orqali yuboring yoki qo'lda kiriting: +998XXXXXXXXX"
        )
        await message.answer(fail_text)


async def show_main_profile(message: types.Message, state: FSMContext):
    data = await state.get_data()
    lang = data.get("chosen_lang")

    builder = ReplyKeyboardBuilder()
    if lang == "ru":
        builder.row(types.KeyboardButton(text="➕ Добавить магазин"))
        builder.row(
            types.KeyboardButton(text="📝 Редактировать"),
            types.KeyboardButton(text="🗑 Удалить"),
        )
        builder.row(types.KeyboardButton(text="📦 Добавить товары"))
        builder.row(types.KeyboardButton(text="🏢 Мои магазины"))
        msg = "<b>Ваш профиль</b>\nМагазинов добавлено: 0\n\nЧто хотите сделать?"
    else:
        builder.row(types.KeyboardButton(text="➕ Do'kon qo'shish"))
        builder.row(
            types.KeyboardButton(text="📝 Tahrirlash"),
            types.KeyboardButton(text="🗑 O'chirish"),
        )
        builder.row(types.KeyboardButton(text="📦 Mahsulot qo'shish"))
        builder.row(types.KeyboardButton(text="🏢 Mening do'konlarim"))
        msg = (
            "<b>Sizning profilingiz</b>\nQo'shilgan do'konlar: 0\n\nNima qilmoqchisiz?"
        )

    await message.answer(msg, reply_markup=builder.as_markup(resize_keyboard=True))

    # Clearing registration state, since it is finished
    await state.set_state(None)
