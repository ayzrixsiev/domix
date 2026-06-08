import io
import pandas as pd
from aiogram import Router, types, F
from aiogram.fsm.context import FSMContext
from aiogram.utils.keyboard import InlineKeyboardBuilder

from bot.statesFSM.add_products import AddProductsState
from database.requests import get_user_stores, add_products_from_dataframe
from bot.handlers.register import show_main_profile

products_router = Router()


# Pick a store to add products
@products_router.callback_query(F.data == "menu_add_products")
async def start_add_products(callback: types.CallbackQuery, state: FSMContext):
    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    stores = await get_user_stores(callback.from_user.id)
    builder = InlineKeyboardBuilder()

    if not stores:
        text = (
            "Сначала добавьте магазин, чтобы загрузить товары."
            if lang == "ru"
            else "Mahsulot yuklash uchun avval do'kon qo'shing."
        )
        builder.button(
            text="↩️ Назад" if lang == "ru" else "↩️ Orqaga",
            callback_data="go_to_main_menu",
        )
        await callback.message.edit_text(text, reply_markup=builder.as_markup())
        await callback.answer()
        return

    for store in stores:
        builder.button(text=store.name, callback_data=f"prod_sid_{store.id}")

    builder.button(
        text="↩️ Назад" if lang == "ru" else "↩️ Orqaga",
        callback_data="go_to_main_menu",
    )
    builder.adjust(1)

    prompt = (
        "Выберите магазин для загрузки прайс-листа (Excel):"
        if lang == "ru"
        else "Numnoma (Excel) yuklash uchun do'konni tanlang:"
    )

    await callback.message.edit_text(prompt, reply_markup=builder.as_markup())
    await state.set_state(AddProductsState.selecting_store)
    await callback.answer()


# Process products file
@products_router.callback_query(
    AddProductsState.selecting_store, F.data.startswith("prod_sid_")
)
async def process_store_selection(callback: types.CallbackQuery, state: FSMContext):
    store_id = int(callback.data.split("_")[2])
    await state.update_data(target_store_id=store_id)

    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    builder = InlineKeyboardBuilder()
    builder.button(
        text="❌ Отмена" if lang == "ru" else "❌ Bekor qilish",
        callback_data="go_to_main_menu",
    )

    prompt = (
        "Отправьте файл Excel (.xlsx) с заполненными товарами.\n\n"
        "Убедитесь, что колонки называются так:\n"
        "<b>Артикул | Категория | Наименование товара | Цена (сум) | Единица измерения | Наличие</b>"
        if lang == "ru"
        else "To'ldirilgan Excel (.xlsx) faylini yuboring.\n\n"
        "Ustunlar quyidagicha nomlanganiga ishonch hosil qiling:\n"
        "<b>Артикул | Категория | Наименование товара | Цена (сум) | Единица измерения | Наличие</b>"
    )

    await callback.message.edit_text(prompt, reply_markup=builder.as_markup())
    await state.set_state(AddProductsState.waiting_for_file)
    await callback.answer()


async def handle_upload_failure(
    msg_to_edit: types.Message, lang: str, current_err: str
):
    """
    Helper function rewritten to morph the processing status message in place
    instead of dropping disconnected error text boxes down the chat line.
    """
    builder = InlineKeyboardBuilder()
    if lang == "ru":
        builder.button(text="🔄 Попробовать снова", callback_data="excel_retry")
        builder.button(text="🏠 Главное меню", callback_data="excel_cancel")
    else:
        builder.button(text="🔄 Yana urinib ko'rish", callback_data="excel_retry")
        builder.button(text="🏠 Asosiy menyu", callback_data="excel_cancel")
    builder.adjust(1)

    await msg_to_edit.edit_text(current_err, reply_markup=builder.as_markup())


# File ingestion report
@products_router.message(AddProductsState.waiting_for_file, F.document)
async def process_excel_file(message: types.Message, state: FSMContext):
    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")
    store_id = user_data.get("target_store_id")

    # Capture initial reference token to mutate state dynamically later
    wait_msg = await message.answer(
        "Обработка файла..." if lang == "ru" else "Fayl qayta ishlanmoqda..."
    )

    if not message.document.file_name.endswith((".xlsx", ".xls")):
        err = (
            "⚠️ Неверный формат файла. Требуется Excel (.xlsx)."
            if lang == "ru"
            else "⚠️ Fayl formati noto'g'ri. Excel (.xlsx) talab qilinadi."
        )
        await handle_upload_failure(wait_msg, lang, err)
        return

    try:
        file_stream = io.BytesIO()
        await message.bot.download(message.document, destination=file_stream)
        file_stream.seek(0)

        df = pd.read_excel(file_stream)

        required_columns = [
            "Категория",
            "Наименование товара",
            "Цена (сум)",
            "Единица измерения",
            "Наличие",
        ]
        missing_columns = [col for col in required_columns if col not in df.columns]

        if missing_columns:
            missing_str = ", ".join(missing_columns)
            err = (
                f"⚠️ В файле отсутствуют обязательные колонки: {missing_str}"
                if lang == "ru"
                else f"⚠️ Faylda majburiy ustunlar yo'q: {missing_str}"
            )
            await handle_upload_failure(wait_msg, lang, err)
            return

        await add_products_from_dataframe(store_id, df)

        success = (
            f"🎉 Успешно загружено {len(df)} товаров!"
            if lang == "ru"
            else f"🎉 {len(df)} ta mahsulot muvaffaqiyatli yuklandi!"
        )
        await wait_msg.edit_text(success)

        # Draw a fresh interactive dashboard right beneath the upload transaction history
        await show_main_profile(message, state)

    except Exception as e:
        err = (
            f"❌ Произошла ошибка при чтении файла: {str(e)}"
            if lang == "ru"
            else f"❌ Faylni o'qishda xatolik yuz berdi: {str(e)}"
        )
        await handle_upload_failure(wait_msg, lang, err)


# Cancel products upload
@products_router.callback_query(
    AddProductsState.waiting_for_file, F.data == "excel_cancel"
)
async def cancel_excel_upload(callback: types.CallbackQuery, state: FSMContext):
    await state.clear()
    await show_main_profile(callback, state)


# Retry callback shifts window parameters back to active listening state
@products_router.callback_query(
    AddProductsState.waiting_for_file, F.data == "excel_retry"
)
async def retry_excel_upload(callback: types.CallbackQuery, state: FSMContext):
    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    builder = InlineKeyboardBuilder()
    builder.button(
        text="❌ Отмена" if lang == "ru" else "❌ Bekor qilish",
        callback_data="go_to_main_menu",
    )

    prompt = (
        "Отправьте файл Excel (.xlsx) с заполненными товарами:"
        if lang == "ru"
        else "To'ldirilgan Excel (.xlsx) faylini yuboring:"
    )
    await callback.message.edit_text(prompt, reply_markup=builder.as_markup())
    await callback.answer()
