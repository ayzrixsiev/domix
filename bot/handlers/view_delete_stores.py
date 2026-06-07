from aiogram import Router, types, F
from aiogram.fsm.context import FSMContext
from aiogram.utils.keyboard import InlineKeyboardBuilder

from statesFSM.delete_store import DeleteStoreState
from database.requests import get_user_stores, delete_store
from bot.handlers.common import show_main_profile

mgmt_router = Router()


# View stores
@mgmt_router.message(F.text.in_(["🏢 Мои магазины", "🏢 Mening do'konlarim"]))
async def process_view_stores(message: types.Message, state: FSMContext):
    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    stores = await get_user_stores(message.from_user.id)

    if not stores:
        text = (
            "У вас пока нет добавленных магазинов."
            if lang == "ru"
            else "Sizda hali qo'shilgan do'konlar mavjud emas."
        )
        await message.answer(text)
        await show_main_profile(message, state)
        return

    # Loop through and build a clean structural list of all owned stores
    response_lines = []
    if lang == "ru":
        response_lines.append("<b>🏢 Список ваших магазинов:</b>\n")
        for idx, store in enumerate(stores, start=1):
            response_lines.append(
                f"{idx}. <b>{store.name}</b>\n"
                f"📍 Адрес: {store.address}\n"
                f"🗺 Координаты: {store.lat}, {store.lon}\n"
            )
    else:
        response_lines.append("<b>🏢 Do'konlaringiz ro'yxati:</b>\n")
        for idx, store in enumerate(stores, start=1):
            response_lines.append(
                f"{idx}. <b>{store.name}</b>\n"
                f"📍 Manzil: {store.address}\n"
                f"🗺 Koordinatalar: {store.lat}, {store.lon}\n"
            )

    full_text = "\n".join(response_lines)
    await message.answer(full_text)

    # Return user directly back to the navigation dashboard options
    await show_main_profile(message, state)


# Delete store
@mgmt_router.message(F.text.in_(["🗑 Удалить", "🗑 O'chirish"]))
async def start_delete_store(message: types.Message, state: FSMContext):
    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    stores = await get_user_stores(message.from_user.id)

    if not stores:
        text = (
            "У вас пока нет магазинов для удаления."
            if lang == "ru"
            else "Sizda o'chirish uchun do'konlar mavjud emas."
        )
        await message.answer(text)
        await show_main_profile(message, state)
        return

    # Build dynamic inline layout tracking store database keys
    builder = InlineKeyboardBuilder()
    for store in stores:
        builder.button(text=store.name, callback_data=f"del_sid_{store.id}")
    builder.adjust(1)

    prompt = (
        "Выберите магазин, который вы хотите полностью удалить:"
        if lang == "ru"
        else "Butunlay o'chirish uchun do'konni tanlang:"
    )

    await message.answer(prompt, reply_markup=builder.as_markup())
    await state.set_state(DeleteStoreState.selecting_store)


@mgmt_router.callback_query(
    DeleteStoreState.selecting_store, F.data.startswith("del_sid_")
)
async def process_delete_store(callback: types.CallbackQuery, state: FSMContext):
    store_id = int(callback.data.split("_")[2])

    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    # Execute transaction to database
    await delete_store(store_id)

    # Clean the inline panel completely to prevent double clicks
    await callback.message.delete()

    success = (
        "Магазин был успешно удален!"
        if lang == "ru"
        else "Do'kon muvaffaqiyatli o'chirildi!"
    )
    await callback.message.answer(success)

    # Draw profile options back up and reset operational states
    await show_main_profile(callback.message, state)
    await state.set_state(None)
