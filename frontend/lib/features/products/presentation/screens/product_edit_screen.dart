import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/stores/presentation/controllers/stores_controller.dart';
import 'package:frontend/features/stores/presentation/widgets/store_form_fields.dart';
import '../../data/product_category.dart';
import '../../data/product_model.dart';
import '../controllers/products_controller.dart';
import '../widgets/product_category_field.dart';

// add or edit one product. one screen for both, because the fields are the same either way - the
// differences are the title, which endpoint is called, and whether there is anything to delete.
//
// [product] null means "new product". a new one is always the owner's own and fully editable. an
// existing one may be from the category template, and then only its price and availability are
// editable: the template is the shared basket every shop of that category is compared on, and it
// stops being shared the moment one owner can rename an item or move it to another category. the
// backend enforces that (UpdateProductPricing has no column for the rest); this screen simply
// doesn't offer the controls.
class ProductEditScreen extends StatefulWidget {
  const ProductEditScreen({
    super.key,
    required this.shopId,
    this.product,
    this.suggestedCategory,
  });

  final int shopId;
  final Product? product;

  /// preselected in the category dropdown of a *new* product - the category of the last product in
  /// this shop, which for a seeded shop is a real one from its own template. saves a tap far more
  /// often than it costs one.
  final ProductCategory? suggestedCategory;

  bool get isNew => product == null;

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _unitController;

  late ProductAvailability _availability;

  /// null until picked. no default: a category chosen for the owner is a category they never look
  /// at, and a wrong one is worse than an empty one now that the value actually groups products.
  ProductCategory? _pickedCategory;

  String? _nameError;
  String? _categoryError;
  String? _unitError;
  String? _priceError;

  // the units the category templates actually use, offered as one-tap shortcuts above the field.
  // the field itself stays free text: these are the russian abbreviations, and an uzbek-speaking
  // owner typing "dona" must not be blocked by a fixed list.
  static const _unitSuggestions = [
    'шт', 'м', 'м²', 'м³', 'кг', 'л',
    'мешок', 'рулон', 'лист', 'упак', 'компл',
  ];

  @override
  void initState() {
    super.initState();
    final product = widget.product;

    // prefilled on an edit, not blank: a template product arrives with its name, category and unit
    // already right, and the owner is usually here only to type a price
    _nameController = TextEditingController(text: product?.name ?? '');
    // an unpriced product shows an empty field rather than "0" - the field being empty is what
    // "no price yet" looks like, and it is also how the owner clears one back to unpriced
    _priceController = TextEditingController(text: product?.price?.toString() ?? '');
    _unitController = TextEditingController(text: product?.unit ?? '');
    _availability = product?.availability ?? ProductAvailability.inStock;

    // tryFromCode returns null for a category this app has no code for, which happens exactly once:
    // a product created before the shared vocabulary existed, whose category is free text. the
    // dropdown then opens empty and the owner has to pick, which is the intended one-time fixup -
    // guessing on their behalf would file the product somewhere nobody chose.
    _pickedCategory = product == null
        ? widget.suggestedCategory
        : ProductCategory.tryFromCode(product.category);

    // a failure from a previous visit would otherwise still be on the controller and paint an error
    // card over a form nothing has been submitted from yet. safe synchronously: nothing has
    // rendered this state, so no listener needs notifying.
    context.read<ProductsController>().resetSaveState();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  AppLocalizations get _strings => Provider.of<LanguageProvider>(context, listen: false).strings;

  Future<void> _save() async {
    final existing = widget.product;
    final isTemplate = existing?.isTemplate ?? false;

    // a template row's name, category and unit are read straight off the product rather than out of
    // form controls, because on that path there are no form controls - they are rendered as locked
    // text. the backend ignores whatever arrives in those three fields for a template row anyway,
    // so this is about sending something truthful, not about being trusted.
    final name = isTemplate ? existing!.name : _nameController.text.trim();
    final categoryCode = isTemplate ? existing!.category : (_pickedCategory?.code ?? '');
    final unit = isTemplate ? existing!.unit : _unitController.text.trim();

    final priceText = _priceController.text.trim();
    // an empty price field is legal and means "not priced yet". only a field with something
    // unparseable in it is an error - the input formatter keeps it to digits, so this only fires
    // on a number too large for an int.
    final price = priceText.isEmpty ? null : int.tryParse(priceText);
    final priceIsInvalid = priceText.isNotEmpty && price == null;

    setState(() {
      _nameError = name.isEmpty ? _strings.productNameRequiredError : null;
      _categoryError = categoryCode.isEmpty ? _strings.productCategoryRequiredError : null;
      _unitError = unit.isEmpty ? _strings.productUnitRequiredError : null;
      _priceError = priceIsInvalid ? _strings.productPriceInvalidError : null;
    });

    if (name.isEmpty || categoryCode.isEmpty || unit.isEmpty || priceIsInvalid) return;

    final controller = context.read<ProductsController>();

    final Product? saved;
    if (existing == null) {
      saved = await controller.addProduct(
        shopId: widget.shopId,
        // id 0 is a placeholder the backend ignores and replaces - a create request carries no id,
        // and inventing a second "draft product" type for one nullable field is not worth it
        draft: Product(
          id: 0,
          shopId: widget.shopId,
          name: name,
          category: categoryCode,
          unit: unit,
          price: price,
          availability: _availability,
          isTemplate: false,
        ),
      );
    } else {
      saved = await controller.updateProduct(
        existing.copyWith(
          name: name,
          category: categoryCode,
          unit: unit,
          price: price,
          clearPrice: price == null,
          availability: _availability,
        ),
      );
    }

    if (!mounted) return;
    if (saved != null) {
      // a new product changes the shop's catalogue size, which is a number StoresController holds
      // and only /api/shops/mine recomputes - so tell it rather than leaving a stale badge behind
      if (existing == null) {
        context.read<StoresController>().adjustProductCount(widget.shopId, 1);
      }
      Navigator.of(context).pop();
      _showSnack(_strings.productSavedMessage);
    }
    // on failure controller.saveError is now set, and build() shows the inline error card
  }

  Future<void> _confirmDelete() async {
    final product = widget.product;
    if (product == null) return;

    final strings = _strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteProductDialog(product: product, strings: strings),
    );
    if (confirmed != true || !mounted) return;

    final controller = context.read<ProductsController>();
    final deleted = await controller.deleteProduct(product);

    if (!mounted) return;
    if (deleted) {
      context.read<StoresController>().adjustProductCount(widget.shopId, -1);
      Navigator.of(context).pop();
      _showSnack(strings.productDeletedMessage);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.textDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final controller = Provider.of<ProductsController>(context);
    final isBusy = controller.isSaving;
    final product = widget.product;
    final isTemplate = product?.isTemplate ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        iconTheme: const IconThemeData(color: AppColors.textDark, size: 22),
        title: Text(
          widget.isNew ? strings.addProductTitle : strings.editProductTitle,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 18,
            letterSpacing: -0.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            // the rule goes above the fields it explains, not below them: read first, it says why
            // three of the inputs on this screen are text; read last, it explains a layout the
            // owner has already decided is broken
            if (isTemplate) ...[
              _HintCard(message: strings.templateProductHint),
              const SizedBox(height: 20),
            ],

            StoreFormLabel(strings.productNameLabel),
            const SizedBox(height: 8),
            if (isTemplate)
              ProductLockedField(
                value: product!.name,
                icon: CupertinoIcons.cube_box,
                strings: strings,
              )
            else
              StoreFormTextField(
                controller: _nameController,
                hint: strings.productNameLabel,
                errorText: _nameError,
                icon: CupertinoIcons.cube_box,
                // guarded: without the check this would rebuild the whole screen on every keystroke
                onChanged: (_) {
                  if (_nameError != null) setState(() => _nameError = null);
                },
              ),
            const SizedBox(height: 18),

            StoreFormLabel(strings.productCategoryLabel),
            const SizedBox(height: 8),
            if (isTemplate)
              ProductLockedField(
                // labelForCode, not _pickedCategory: a template row's category is always a known
                // code, but going through the same fallback the rest of the app uses keeps one
                // answer to "how is a stored category displayed"
                value: ProductCategory.labelForCode(product!.category, strings),
                icon: _pickedCategory?.icon ?? CupertinoIcons.square_grid_2x2,
                strings: strings,
              )
            else
              ProductCategoryPicker(
                value: _pickedCategory,
                strings: strings,
                errorText: _categoryError,
                onChanged: (picked) => setState(() {
                  _pickedCategory = picked;
                  _categoryError = null;
                }),
              ),
            const SizedBox(height: 18),

            // price and availability are the two fields every product has, template or not - they
            // are exactly the facts that differ between two shops stocking the same item
            StoreFormLabel(strings.productPriceLabel),
            const SizedBox(height: 8),
            StoreFormTextField(
              controller: _priceController,
              hint: strings.productPriceHint,
              errorText: _priceError,
              icon: CupertinoIcons.tag,
              // the currency named inside the field, in the app's language. it used to be a dollar
              // glyph in the prefix, which is the wrong currency for every shop this app has.
              suffixText: strings.currencySom,
              keyboardType: TextInputType.number,
              // the field only ever holds a whole number of so'm. filtering at the keyboard is
              // kinder than validating afterwards: a character that can't be typed can't be wrong.
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) {
                if (_priceError != null) setState(() => _priceError = null);
              },
            ),
            const SizedBox(height: 18),

            StoreFormLabel(strings.productUnitLabel),
            const SizedBox(height: 8),
            if (isTemplate)
              ProductLockedField(
                value: product!.unit,
                icon: CupertinoIcons.scope,
                strings: strings,
              )
            else ...[
              StoreFormTextField(
                controller: _unitController,
                hint: strings.productUnitLabel,
                errorText: _unitError,
                icon: CupertinoIcons.scope,
                onChanged: (_) {
                  if (_unitError != null) setState(() => _unitError = null);
                },
              ),
              const SizedBox(height: 10),
              // listens to the field itself rather than being handed a value from build(). typing
              // has to move the highlight, and the alternative - setState on every keystroke - would
              // rebuild this whole form to repaint eleven chips. same reason the home search bar's
              // clear button uses a ValueListenableBuilder.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _unitController,
                builder: (context, value, _) => _UnitSuggestions(
                  units: _unitSuggestions,
                  selected: value.text.trim(),
                  onSelected: (unit) {
                    _unitController.text = unit;
                    if (_unitError != null) setState(() => _unitError = null);
                  },
                ),
              ),
            ],
            const SizedBox(height: 18),

            StoreFormLabel(strings.productAvailabilityLabel),
            const SizedBox(height: 8),
            _AvailabilityPicker(
              value: _availability,
              strings: strings,
              onChanged: (value) => setState(() => _availability = value),
            ),

            if (controller.saveError != null) ...[
              const SizedBox(height: 18),
              StoreInlineErrorCard(
                message: strings.productErrorMessage(
                  controller.saveError!.code,
                  limit: controller.saveError!.limit,
                ),
              ),
            ],

            const SizedBox(height: 28),
            StoreSubmitButton(
              label: strings.saveProductButton,
              isBusy: isBusy,
              onTap: _save,
            ),

            // only the owner's own products can be removed. a template row has no delete button at
            // all rather than a disabled one - the hint card above already says why, and a control
            // that is present but never works is worse than one that isn't there.
            if (product != null && !product.isTemplate) ...[
              const SizedBox(height: 32),
              const SizedBox(height: 1, child: ColoredBox(color: AppColors.hairline)),
              const SizedBox(height: 20),
              StoreDangerButton(
                label: strings.deleteProductButton,
                isBusy: isBusy,
                onTap: _confirmDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// one-tap shortcuts that fill the unit field. a horizontal Wrap rather than a scrolling row, so
// every option is visible at once - there are only eleven, and a hidden shortcut is not a shortcut.
class _UnitSuggestions extends StatelessWidget {
  const _UnitSuggestions({
    required this.units,
    required this.selected,
    required this.onSelected,
  });

  final List<String> units;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final unit in units)
          _ChoiceChip(
            label: unit,
            isSelected: unit == selected,
            onTap: () => onSelected(unit),
          ),
      ],
    );
  }
}

class _AvailabilityPicker extends StatelessWidget {
  const _AvailabilityPicker({
    required this.value,
    required this.strings,
    required this.onChanged,
  });

  final ProductAvailability value;
  final AppLocalizations strings;
  final ValueChanged<ProductAvailability> onChanged;

  String _label(ProductAvailability availability) => switch (availability) {
        ProductAvailability.inStock => strings.availabilityInStock,
        ProductAvailability.onOrder => strings.availabilityOnOrder,
        ProductAvailability.unavailable => strings.availabilityUnavailable,
      };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final availability in ProductAvailability.values) ...[
          if (availability != ProductAvailability.values.first) const SizedBox(width: 8),
          Expanded(
            child: _ChoiceChip(
              label: _label(availability),
              isSelected: availability == value,
              // a full-height segment rather than a pill, so the three options read as one control
              // with three states instead of three separate buttons
              height: 46,
              onTap: () => onChanged(availability),
            ),
          ),
        ],
      ],
    );
  }
}

// the selected state is a soft orange fill with an orange border, not a saturated block: brand
// colour marks the active choice without turning a form field into the loudest thing on the page.
class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.height,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final background = isSelected ? AppColors.primarySoft : AppColors.surfaceMuted;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.xs),
            border: Border.all(
              color: isSelected ? AppColors.primaryOrange : AppColors.hairline,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: height == null ? 9 : 0),
            child: Center(
              widthFactor: height == null ? 1 : null,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? AppColors.primaryOrange : AppColors.textGrey,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// neutral, not red: this explains a rule, it does not report a problem
class _HintCard extends StatelessWidget {
  const _HintCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(CupertinoIcons.info_circle_fill, color: AppColors.textFaint, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// names the product being removed, the same reason the delete-shop dialog names the shop: a bare
// "are you sure?" gives nothing to check an intent against, which is exactly when people confirm
// the wrong thing.
class _DeleteProductDialog extends StatelessWidget {
  const _DeleteProductDialog({required this.product, required this.strings});

  final Product product;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.dangerSoft, shape: BoxShape.circle),
              child: const Icon(CupertinoIcons.trash_fill, color: AppColors.danger, size: 22),
            ),
            const SizedBox(height: 16),
            Text(
              strings.deleteProductConfirmTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 17,
                height: 1.3,
                letterSpacing: -0.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              strings.deleteProductConfirmBody(product.name),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 22),
            // cancel first and visually heavier than confirm: the safe choice should be the one the
            // thumb lands on and the one the eye reads as the default
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: strings.cancelButton,
                    background: AppColors.surfaceMuted,
                    foreground: AppColors.textDark,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DialogButton(
                    label: strings.deleteStoreConfirmAction,
                    background: AppColors.danger,
                    foreground: Colors.white,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: foreground, fontSize: 14.5, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}
