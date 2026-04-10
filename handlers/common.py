import re
from aiogram import Router, types, F
from aiogram.filters import Command
from aiogram.fsm.context import FSMContext
from aiogram.utils.keyboard import ReplyKeyboardBuilder

from states.register import RegisterState

common_router = Router()  # Роутер собирает хендлеры в одну кучу


@common_router.message(Command("start"))
async def cmd_start(message: types.Message, state: FSMContext):

    # Как только юзер жмет старт мы чистим всю его прошлую историю
    await state.clear()

    # Создаем кнопку выбора языка
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

    # Меняем state в FSM
    await state.set_state(RegisterState.waiting_for_language)


@router.message(
    RegisterState.waiting_for_language, F.text.in_(["Русский 🇷🇺", "O'zbekcha 🇺🇿"])
)
async def language_selected(message: types.Message, state: FSMContext):
    # Временно сохраняем какой язык выбрали чтобы после проверить и выдать текст
    lang = "ru" if "Русский" in message.text else "uz"
    # Обновляем FSM данные этого конкретного юзера, это его личный блокнот
    await state.update_data(chosen_lang=lang)

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


@router.message(RegisterState.waiting_for_phone)
async def process_contact(message: types.Message, state: FSMContext):

    user_data = (
        await state.get_data()
    )  # Весь наш блокнот о юзере мы сохраняем в user_data
    lang = user_data.get(
        "chosen_lang"
    )  # Вытаскиваем из блокнота строку о выбранном юзером языке

    # Проверяем как пришел номер телефона, с помощью кнопки или вручную текстом
    if message.contact:
        phone_number = message.contact.phone_number
    else:
        phone_number = message.text

    phone_number = "".join(filter(str.isdigit, phone_number))

    # Добавляем плюс, если его нет
    if not phone_number.startswith("+"):
        # Если юзер ввел 998..., превращаем в +998...
        if phone_number.startswith("998"):
            phone_number = f"+{phone_number}"
        else:
            # Если ввел без кода страны, например 901234567
            phone_number = f"+998{phone_number}"

    # Валидация через Regex (формат Узбекистана: +998 XX XXX XX XX)
    # \+998 — начало с +998
    # \d{9} — ровно 9 цифр после кода страны
    uz_phone_regex = r"^\+998\d{9}$"

    if re.match(uz_phone_regex, phone_number):
        # Если номер верный, сохраняем его в FSM
        await state.update_data(phone=phone_number)

        success_text = (
            f"Отлично! Номер {phone_number} подтвержден.\nПереходим в ваш профиль..."
            if lang == "ru"
            else f"Ajoyib! {phone_number} raqami tasdiqlandi.\nProfilingizga o'tilmoqda..."
        )
        await message.answer(
            success_text, reply_markup=types.ReplyKeyboardRemove()
        )  # Выводим текст и убираем кнопки

        # В БУДУЩЕМ: Здесь будет проверка в БД (найден/не найден)
        await show_main_profile(message, state)

    else:
        # Если номер не прошел проверку
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

    # Очищаем состояние регистрации, так как она завершена
    await state.set_state(None)
