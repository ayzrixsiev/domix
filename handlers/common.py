from aiogram import Router, types
from aiogram.filters import Command
from aiogram.utils.keyboard import ReplyKeyboardBuilder

router = (
    Router()
)  # Роутер — это как разветвитель, который собирает хендлеры в одну кучу


@router.message(Command("start"))
async def cmd_start(message: type.Message):
    builder = ReplyKeyboardBuilder()
    builder.row(
        type.KeyboardButton(
            text="📱 Отправить номер телефона",
            request_contact=True,  # ТГ сам предложит отправить номер телефона, pre build функция
        )
    )

    await message.answer(
        f"<b>Добро пожаловать в Domix Bot!</b>\n\n"
        f"Здесь владельцы магазинов могут добавлять свои магазины и товары на карту.\n"
        f"Для продолжения, пожалуйста, поделитесь номером телефона.",
        reply_markup=builder.as_markup(resize_keyboard=True),
    )
