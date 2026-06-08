from aiogram import Router, types, F
from aiogram.fsm.context import FSMContext
from aiogram.utils.keyboard import InlineKeyboardBuilder

from bot.statesFSM.delete_store import DeleteStoreState
from database.requests import get_user_stores, delete_store
from bot.handlers.register import show_main_profile

mgmt_router = Router()


# View stores
@mgmt_router.callback_query(F.data == "menu_view_stores")
async def process_view_stores(callback: types.CallbackQuery, state: FSMContext):
    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    stores = await get_user_stores(callback.from_user.id)
    builder = InlineKeyboardBuilder()
    builder.button(
        text="↩️ Назад" if lang == "ru" else "↩️ Orqaga",
        callback_data="go_to_main_menu",
    )

    if not stores:
        text = (
            "У вас пока нет добавленных магазинов."
            if lang == "ru"
            else "Sizda hali qo'shilgan do'konlar mavjud emas."
        )
        await callback.message.edit_text(text, reply_markup=builder.as_markup())
        await callback.answer()
        return

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

    # Edit message to show the list alongside the back button
    await callback.message.edit_text(full_text, reply_markup=builder.as_markup())
    await callback.answer()


# Delete store
@mgmt_router.callback_query(F.data == "menu_delete_store")
async def start_delete_store(callback: types.CallbackQuery, state: FSMContext):
    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    stores = await get_user_stores(callback.from_user.id)
    builder = InlineKeyboardBuilder()

    if not stores:
        text = (
            "У вас пока нет магазинов для удаления."
            if lang == "ru"
            else "Sizda o'chirish uchun do'konlar mavjud emas."
        )
        builder.button(
            text="↩️ Назад" if lang == "ru" else "↩️ Orqaga",
            callback_data="go_to_main_menu",
        )
        await callback.message.edit_text(text, reply_markup=builder.as_markup())
        await callback.answer()
        return

    # Build dynamic list of targets
    for store in stores:
        builder.button(text=store.name, callback_data=f"del_sid_{store.id}")

    builder.button(
        text="❌ Отмена" if lang == "ru" else "❌ Bekor qilish",
        callback_data="go_to_main_menu",
    )
    builder.adjust(1)

    prompt = (
        "Выберите магазин, который вы хотите полностью удалить:"
        if lang == "ru"
        else "Butunlay o'chirish uchun do'konni tanlang:"
    )

    await callback.message.edit_text(prompt, reply_markup=builder.as_markup())
    await state.set_state(DeleteStoreState.selecting_store)
    await callback.answer()


# Processing store deletion via callback execution
@mgmt_router.callback_query(
    DeleteStoreState.selecting_store, F.data.startswith("del_sid_")
)
async def process_delete_store(callback: types.CallbackQuery, state: FSMContext):
    store_id = int(callback.data.split("_")[2])

    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    await delete_store(store_id)

    success = (
        "Магазин успешно удален!"
        if lang == "ru"
        else "Do'kon muvaffaqiyatli o'chirildi!"
    )

    # Send a quick native notification popup at the top of their screen
    await callback.answer(text=success, show_alert=True)

    # Immediately transform the current window back to the clean main menu hub
    await show_main_profile(callback, state)
