import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/destructive_confirm_dialog.dart';
import 'package:frontend/features/map/presentation/screens/location_picker_screen.dart';
import 'package:frontend/features/products/presentation/controllers/products_controller.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/stores/presentation/widgets/store_form_fields.dart';
import '../controllers/stores_controller.dart';
import 'package:frontend/core/widgets/app_page_header.dart';

// the "Данные магазина" section of ShopSettingsScreen: name, phone and location, and - in its own
// block below a full-width rule - delete. pops `true` when the shop was deleted and `null` on a
// plain back, so the settings screen knows whether the shop it describes still exists.
class EditStoreScreen extends StatefulWidget {
  const EditStoreScreen({super.key, required this.shop});

  final Shop shop;

  @override
  State<EditStoreScreen> createState() => _EditStoreScreenState();
}

class _EditStoreScreenState extends State<EditStoreScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;

  // the shop's saved location until the owner opens the picker. never null here, unlike on the add
  // form - an existing shop always has coordinates.
  late double _latitude;
  late double _longitude;
  late String _address;

  String? _nameError;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    // prefilled, not blank: making someone retype a phone number they only wanted to keep is how a
    // "fix the address" trip turns into a data-loss trip
    _nameController = TextEditingController(text: widget.shop.name);
    _phoneController = TextEditingController(text: widget.shop.contactPhone);
    _latitude = widget.shop.latitude;
    _longitude = widget.shop.longitude;
    _address = widget.shop.address;

    // a failure from a previous visit would otherwise paint an error card over a form nothing has been
    // submitted from. safe synchronously: nothing has rendered this state yet.
    context.read<StoresController>().resetShopMutationState();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  AppLocalizations get _strings => Provider.of<LanguageProvider>(context, listen: false).strings;

  bool get _hasChanges =>
      _nameController.text.trim() != widget.shop.name ||
      _phoneController.text.trim() != widget.shop.contactPhone ||
      _address != widget.shop.address ||
      _latitude != widget.shop.latitude ||
      _longitude != widget.shop.longitude;

  Future<void> _pickLocation() async {
    final result = await Navigator.of(context).push<LocationPickResult>(
      MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
    );
    if (result == null || !mounted) return;
    setState(() {
      _latitude = result.latitude;
      _longitude = result.longitude;
      _address = result.address;
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    setState(() {
      _nameError = name.isEmpty ? _strings.shopNameRequiredError : null;
      _phoneError = phone.isEmpty ? _strings.contactPhoneRequiredError : null;
    });
    if (name.isEmpty || phone.isEmpty) return;

    // a no-op PUT would still bump updated_at server-side and cost a round trip, and the "saved!"
    // toast would be a lie about work that did not happen
    if (!_hasChanges) {
      _showSnack(_strings.noChangesToSave);
      return;
    }

    final controller = context.read<StoresController>();
    final saved = await controller.updateShop(
      shopId: widget.shop.id,
      name: name,
      contactPhone: phone,
      address: _address,
      latitude: _latitude,
      longitude: _longitude,
    );

    if (!mounted) return;
    if (saved != null) {
      Navigator.of(context).pop();
      _showSnack(_strings.storeUpdatedMessage);
    }
    // on failure controller.shopMutationError is now set, and build() shows the inline error card
  }

  Future<void> _confirmDelete() async {
    final strings = _strings;
    // names the shop and counts what disappears with it: a bare "are you sure?" gives the owner nothing
    // to check their intent against
    final confirmed = await DestructiveConfirmDialog.show(
      context,
      title: strings.deleteStoreConfirmTitle,
      body: strings.deleteStoreConfirmBody(widget.shop.name, widget.shop.productCount),
      confirmLabel: strings.deleteStoreConfirmAction,
      cancelLabel: strings.cancelButton,
    );
    if (!confirmed || !mounted) return;

    final controller = context.read<StoresController>();
    final productsController = context.read<ProductsController>();
    final deleted = await controller.deleteShop(widget.shop.id);

    if (!mounted) return;
    if (deleted) {
      // the shop's products went with it (products.shop_id cascades), and postgres reuses ids - so a
      // cached catalogue left behind would eventually be served under another shop's name
      productsController.forgetShop(widget.shop.id);
      // `true` tells ShopSettingsScreen the shop it describes is gone, so it pops itself too and the
      // owner lands back on the shops list rather than on a page about nothing
      Navigator.of(context).pop(true);
      _showSnack(strings.storeDeletedMessage);
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
    final controller = Provider.of<StoresController>(context);
    final isBusy = controller.isMutatingShop;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppPageHeader(title: strings.editStoreScreenTitle),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            StoreFormLabel(strings.shopNameLabel),
            const SizedBox(height: 8),
            StoreFormTextField(
              controller: _nameController,
              hint: strings.shopNameLabel,
              errorText: _nameError,
              icon: CupertinoIcons.building_2_fill,
              // guarded: without the check this would rebuild the whole screen on every keystroke
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: 18),
            StoreFormLabel(strings.contactPhoneLabel),
            const SizedBox(height: 8),
            StoreFormTextField(
              controller: _phoneController,
              hint: strings.contactPhoneLabel,
              errorText: _phoneError,
              icon: CupertinoIcons.phone_fill,
              keyboardType: TextInputType.phone,
              onChanged: (_) {
                if (_phoneError != null) setState(() => _phoneError = null);
              },
            ),
            const SizedBox(height: 18),
            StoreFormLabel(strings.locationLabel),
            const SizedBox(height: 8),
            StoreLocationTile(
              pickedAddress: _address,
              errorText: null, // never empty on an existing shop, so it can't fail validation
              strings: strings,
              onTap: _pickLocation,
            ),
            if (controller.shopMutationError != null) ...[
              const SizedBox(height: 18),
              StoreInlineErrorCard(
                message: strings.shopMutationErrorMessage(controller.shopMutationError!.code),
              ),
            ],
            const SizedBox(height: 28),
            StoreSubmitButton(
              label: strings.saveChangesButton,
              isBusy: isBusy,
              onTap: _save,
            ),

            // everything below this rule is destructive. the gap and the divider put enough distance between
            // "save" and "delete" that a mis-tap cannot reach the wrong one, without hiding delete.
            const SizedBox(height: 38),
            const SizedBox(height: 1, child: ColoredBox(color: AppColors.hairline)),
            const SizedBox(height: 22),
            _DangerZone(
              strings: strings,
              isBusy: isBusy,
              onDelete: _confirmDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _DangerZone extends StatelessWidget {
  const _DangerZone({required this.strings, required this.isBusy, required this.onDelete});

  final AppLocalizations strings;
  final bool isBusy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: AppColors.danger, size: 15),
            const SizedBox(width: 8),
            Text(
              strings.dangerZoneTitle,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 13,
                letterSpacing: 0.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          strings.deleteStoreHint,
          style: const TextStyle(
            color: AppColors.textGrey,
            fontSize: 12.5,
            height: 1.45,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 16),
        // shared with the edit-product form (StoreDangerButton) - it was private here until a second
        // destructive form needed the identical control
        StoreDangerButton(
          label: strings.deleteStoreButton,
          isBusy: isBusy,
          onTap: onDelete,
        ),
      ],
    );
  }
}
