import io
import pandas as pd
from aiogram import Router, types, F
from aiogram.fsm.context import FSMContext
from aiogram.utils.keyboard import InlineKeyboardBuilder

from statesFSM.add_products import AddProductsState
from database.requests import get_user_stores, add_products_from_dataframe
from bot.handlers.common import show_main_profile

products_router = Router()


@products_router.message(F.text.in_(["📦 Добавить товары", "📦 Mahsulot qo'shish"]))
async def start_add_products(message: types.Message, state: FSMContext):
    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    stores = await get_user_stores(message.from_user.id)

    if not stores:
        text = (
            "Сначала добавьте магазин, чтобы загрузить товары."
            if lang == "ru"
            else "Mahsulot yuklash uchun avval do'kon qo'shing."
        )
        await message.answer(text)
        await show_main_profile(message, state)
        return

    builder = InlineKeyboardBuilder()
    for store in stores:
        builder.button(text=store.name, callback_data=f"prod_sid_{store.id}")
    builder.adjust(1)

    prompt = (
        "Выберите магазин для загрузки прайс-листа (Excel):"
        if lang == "ru"
        else "Numnoma (Excel) yuklash uchun do'konni tanlang:"
    )

    await message.answer(prompt, reply_markup=builder.as_markup())
    await state.set_state(AddProductsState.selecting_store)


@products_router.callback_query(
    AddProductsState.selecting_store, F.data.startswith("prod_sid_")
)
async def process_store_selection(callback: types.CallbackQuery, state: FSMContext):
    store_id = int(callback.data.split("_")[2])
    await state.update_data(target_store_id=store_id)

    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    await callback.message.delete()

    prompt = (
        "Отправьте файл Excel (.xlsx) с заполненными товарами.\n\n"
        "Убедитесь, что колонки называются так:\n"
        "Артикул | Категория | Наименование товара | Цена (сум) | Единица измерения | Наличие"
        if lang == "ru"
        else "To'ldirilgan Excel (.xlsx) faylini yuboring.\n\n"
        "Ustunlar quyidagicha nomlanganiga ishonch hosil qiling:\n"
        "Артикул | Категория | Наименование товара | Цена (сум) | Единица измерения | Наличие"
    )

    await callback.message.answer(prompt)
    await state.set_state(AddProductsState.waiting_for_file)


async def handle_upload_failure(message: types.Message, lang: str, current_err: str):
    """
    Helper function to send the error message and display inline choices
    instead of trapping the user or automatically kicking them out.
    """
    builder = InlineKeyboardBuilder()
    if lang == "ru":
        builder.button(text="🔄 Попробовать снова", callback_data="excel_retry")
        builder.button(text="🏠 Главное меню", callback_data="excel_cancel")
    else:
        builder.button(text="🔄 Yana urinib ko'rish", callback_data="excel_retry")
        builder.button(text="🏠 Asosiy menyu", callback_data="excel_cancel")
    builder.adjust(1)

    await message.answer(current_err, reply_markup=builder.as_markup())


@products_router.message(AddProductsState.waiting_for_file, F.document)
async def process_excel_file(message: types.Message, state: FSMContext):
    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")
    store_id = user_data.get("target_store_id")

    # 1. Validate file extension
    if not message.document.file_name.endswith((".xlsx", ".xls")):
        err = (
            "Неверный формат файла. Требуется Excel (.xlsx)."
            if lang == "ru"
            else "Fayl formati noto'g'ri. Excel (.xlsx) talab qilinadi."
        )
        await handle_upload_failure(message, lang, err)
        return

    wait_msg = await message.answer(
        "Обработка файла..." if lang == "ru" else "Fayl qayta ishlanmoqda..."
    )

    try:
        # Download file securely into memory
        file_stream = io.BytesIO()
        await message.bot.download(message.document, destination=file_stream)
        file_stream.seek(0)

        # Parse with Pandas
        df = pd.read_excel(file_stream)

        # Verify critical columns exist
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
            await wait_msg.delete()
            err = (
                f"В файле отсутствуют обязательные колонки: {missing_str}"
                if lang == "ru"
                else f"Faylda majburiy ustunlar yo'q: {missing_str}"
            )
            await handle_upload_failure(message, lang, err)
            return

        # Execute database insertion if checks pass
        await add_products_from_dataframe(store_id, df)

        success = (
            f"Успешно загружено {len(df)} товаров!"
            if lang == "ru"
            else f"{len(df)} ta mahsulot muvaffaqiyatli yuklandi!"
        )
        await wait_msg.edit_text(success)

        # Clear state and return to main layout on success
        await state.set_state(None)
        await show_main_profile(message, state)

    except Exception as e:
        await wait_msg.delete()
        err = (
            f"Произошла ошибка при чтении файла: {str(e)}"
            if lang == "ru"
            else f"Faylni o'qishda xatolik yuz berdi: {str(e)}"
        )
        await handle_upload_failure(message, lang, err)


# Make user pick whether he want to try again after fail upload of the file, or keep trying
@products_router.callback_query(
    AddProductsState.waiting_for_file, F.data == "excel_cancel"
)
async def cancel_excel_upload(callback: types.CallbackQuery, state: FSMContext):
    """
    Triggers if the user wants to abort and return to the main menu.
    """
    await callback.message.delete()
    await state.set_state(None)
    await show_main_profile(callback.message, state)


@products_router.callback_query(
    AddProductsState.waiting_for_file, F.data == "excel_retry"
)
async def retry_excel_upload(callback: types.CallbackQuery, state: FSMContext):
    """
    Triggers if the user wants to attempt the upload again.
    Keeps the FSM state active.
    """
    user_data = await state.get_data()
    lang = user_data.get("chosen_lang", "ru")

    await callback.message.delete()

    prompt = (
        "Отправьте файл Excel (.xlsx) с заполненными товарами:"
        if lang == "ru"
        else "To'ldirilgan Excel (.xlsx) faylini yuboring:"
    )
    await callback.message.answer(prompt)
