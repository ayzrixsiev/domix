import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/map/presentation/screens/location_picker_screen.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/stores/presentation/widgets/store_form_fields.dart';
import '../controllers/stores_controller.dart';

// the "add store" page: shop name, contact number, and a location picked on the map.
// no photo yet - shops get a default banner (see ShopBanner in map_screen.dart) until photo
// upload comes back as a later feature. on success the new shop is added to StoresController's
// list, so it shows up on the map immediately, and this screen closes back to wherever it opened from.
class AddStoreScreen extends StatefulWidget {
  const AddStoreScreen({super.key});

  @override
  State<AddStoreScreen> createState() => _AddStoreScreenState();
}

class _AddStoreScreenState extends State<AddStoreScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  LocationPickResult? _pickedLocation;

  // no default: the category decides which product catalogue the new shop is seeded with and can't
  // be changed afterwards, so pre-selecting one would let an owner tap straight past the single
  // choice on this form with lasting consequences
  ShopCategory? _pickedCategory;

  String? _nameError;
  String? _phoneError;
  String? _categoryError;
  String? _locationError;

  // listen: false, and that is not a micro-optimisation - it is what makes this getter callable at
  // all. Provider.of with listen:true asserts unless it is read during a build, so every read from a
  // tap handler threw and the handler died before it did anything. that is exactly why the category
  // tile "did nothing" when pressed while the location tile worked: _pickLocation never touches
  // _strings, _pickCategory reads it on its first line.
  AppLocalizations get _strings => Provider.of<LanguageProvider>(context, listen: false).strings;

  @override
  void initState() {
    super.initState();
    // a failure from a previous visit would otherwise still be on the controller and paint an error
    // card over a form the user hasn't even submitted yet. safe to do synchronously here: nothing
    // has rendered this state yet, so no listener needs notifying.
    context.read<StoresController>().resetSaveState();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.of(context).push<LocationPickResult>(
      MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
    );
    if (result == null || !mounted) return;
    setState(() {
      _pickedLocation = result;
      _locationError = null;
    });
  }

  Future<void> _pickCategory() async {
    final result = await ShopCategorySheet.show(
      context,
      selected: _pickedCategory,
      strings: _strings,
    );
    if (result == null || !mounted) return; // dismissed without choosing
    setState(() {
      _pickedCategory = result;
      _categoryError = null;
    });
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    setState(() {
      _nameError = name.isEmpty ? _strings.shopNameRequiredError : null;
      _phoneError = phone.isEmpty ? _strings.contactPhoneRequiredError : null;
      _categoryError = _pickedCategory == null ? _strings.categoryRequiredError : null;
      _locationError = _pickedLocation == null ? _strings.locationRequiredError : null;
    });

    if (name.isEmpty || phone.isEmpty || _pickedCategory == null || _pickedLocation == null) {
      return;
    }

    final controller = Provider.of<StoresController>(context, listen: false);
    final location = _pickedLocation!;
    final success = await controller.createShop(
      name: name,
      contactPhone: phone,
      address: location.address,
      category: _pickedCategory!,
      latitude: location.latitude,
      longitude: location.longitude,
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_strings.storeCreatedMessage),
          backgroundColor: AppColors.textDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
      );
    }
    // on failure controller.saveError is now set, and build() below shows the inline error card
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<StoresController>(context);

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
          _strings.addStoreScreenTitle,
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
          padding: const EdgeInsets.all(20),
          children: [
            StoreFormLabel(_strings.shopNameLabel),
            const SizedBox(height: 8),
            StoreFormTextField(
              controller: _nameController,
              hint: _strings.shopNameLabel,
              errorText: _nameError,
              icon: CupertinoIcons.building_2_fill,
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: 18),
            StoreFormLabel(_strings.contactPhoneLabel),
            const SizedBox(height: 8),
            StoreFormTextField(
              controller: _phoneController,
              hint: _strings.contactPhoneLabel,
              errorText: _phoneError,
              icon: CupertinoIcons.phone_fill,
              keyboardType: TextInputType.phone,
              onChanged: (_) {
                if (_phoneError != null) setState(() => _phoneError = null);
              },
            ),
            const SizedBox(height: 18),
            StoreFormLabel(_strings.shopCategoryLabel),
            const SizedBox(height: 8),
            StoreCategoryTile(
              selected: _pickedCategory,
              errorText: _categoryError,
              strings: _strings,
              onTap: _pickCategory,
            ),
            const SizedBox(height: 18),
            StoreFormLabel(_strings.locationLabel),
            const SizedBox(height: 8),
            StoreLocationTile(
              pickedAddress: _pickedLocation?.address,
              errorText: _locationError,
              strings: _strings,
              onTap: _pickLocation,
            ),
            if (controller.saveError != null) ...[
              const SizedBox(height: 18),
              StoreInlineErrorCard(message: _strings.storeCreationFailed),
            ],
            const SizedBox(height: 28),
            StoreSubmitButton(
              label: _strings.createStoreButton,
              isBusy: controller.isSaving,
              onTap: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
