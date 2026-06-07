import os
import asyncio
import logging

from dotenv import load_dotenv
from aiogram import Bot, Dispatcher
from aiogram.client.default import DefaultBotProperties
from aiogram.enums import ParseMode
from bot.handlers.common import common_router
from bot.handlers.stores import store_router

# Loading hidden data from .env
load_dotenv()

# Logging to see errors in the terminal
logging.basicConfig(level=logging.INFO)

# Bot initialization
bot = Bot(
    token=os.getenv("BOT_TOKEN"),
    default=DefaultBotProperties(
        parse_mode=ParseMode.HTML
    ),  # So that buttons support html
)

"""Dispatcher - brain, which processes incoming events. In other words incoming commands, like start and helps FSM"""
dp = Dispatcher()


async def main():
    # Turn on all the routers
    dp.include_router(common_router)
    dp.include_router(store_router)

    # Turn on "listening for commands" process for telegram
    print("Bot started...")
    await dp.start_polling(bot)


# Start the main function
if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("Бот выключен")
