import os
import asyncio
import logging

from dotenv import load_dotenv
from aiogram import Bot, Dispatcher
from aiogram.client.default import DefaultBotProperties
from aiogram.enums import ParseMode
from handlers.common import router

# Загружаем скрытые настройки из .evn
load_dotenv()

# Включаем логгирование для просмотров ошибок в консоли
logging.basicConfig(level=logging.INFO)

# Инициализируем бота
bot = Bot(
    token=os.getenv("BOT_TOKEN"),
    default=DefaultBotProperties(
        parse_mode=ParseMode.HTML
    ),  # Чтобы кнопки и текст поддерживали HTML
)

# Диспетчер — это "мозг", который обрабатывает входящие события. То есть проверяет
# входящие команды по типу /start, и помогает с FSM. Так же мы создали блокнот который хранит данные на моем компе, позже сделаю Redis
dp = Dispatcher()


async def main():
    # Запускаем все роутеры
    dp.include_router(router)
    # Запускаем "прослушку" обновлений от Telegram
    print("Bot started...")
    await dp.start_polling(bot)


# Запускаем функцию main только в случае если данный файл был запущен. import тоже не сработает
if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("Бот выключен")
