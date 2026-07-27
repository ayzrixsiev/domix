import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/map/presentation/screens/location_picker_screen.dart';
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

  String? _nameError;
  String? _phoneError;
  String? _locationError;

  AppLocalizations get _strings => Provider.of<LanguageProvider>(context).strings;

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

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    setState(() {
      _nameError = name.isEmpty ? _strings.shopNameRequiredError : null;
      _phoneError = phone.isEmpty ? _strings.contactPhoneRequiredError : null;
      _locationError = _pickedLocation == null ? _strings.locationRequiredError : null;
    });

    if (name.isEmpty || phone.isEmpty || _pickedLocation == null) return;

    final controller = Provider.of<StoresController>(context, listen: false);
    final location = _pickedLocation!;
    final success = await controller.createShop(
      name: name,
      contactPhone: phone,
      address: location.address,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        iconTheme: const IconThemeData(color: AppColors.textDark),
        title: Text(
          _strings.addStoreScreenTitle,
          style: const TextStyle(color: AppColors.textDark, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _FormLabel(_strings.shopNameLabel),
            const SizedBox(height: 8),
            _FormTextField(
              controller: _nameController,
              hint: _strings.shopNameLabel,
              errorText: _nameError,
              icon: CupertinoIcons.building_2_fill,
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: 18),
            _FormLabel(_strings.contactPhoneLabel),
            const SizedBox(height: 8),
            _FormTextField(
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
            _FormLabel(_strings.locationLabel),
            const SizedBox(height: 8),
            _LocationPickerTile(
              pickedAddress: _pickedLocation?.address,
              errorText: _locationError,
              strings: _strings,
              onTap: _pickLocation,
            ),
            if (controller.saveError != null) ...[
              const SizedBox(height: 18),
              _InlineErrorCard(message: _strings.storeCreationFailed),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryOrange,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: controller.isSaving ? null : _submit,
                child: controller.isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : Text(
                        _strings.createStoreButton,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: AppColors.textDark, fontSize: 13.5, fontWeight: FontWeight.w700),
    );
  }
}

class _FormTextField extends StatelessWidget {
  const _FormTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.errorText,
    this.keyboardType,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final String? errorText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: const TextStyle(color: AppColors.textDark, fontSize: 15.5, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        errorText: errorText,
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        prefixIcon: Icon(icon, color: AppColors.textGrey, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primaryOrange, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
      ),
    );
  }
}

class _LocationPickerTile extends StatelessWidget {
  const _LocationPickerTile({
    required this.pickedAddress,
    required this.errorText,
    required this.strings,
    required this.onTap,
  });

  final String? pickedAddress;
  final String? errorText;
  final AppLocalizations strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasLocation = pickedAddress != null;
    final borderColor = errorText != null
        ? AppColors.danger
        : (hasLocation ? AppColors.primaryOrange : const Color(0xFFE2E8F0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: hasLocation || errorText != null ? 1.5 : 1),
            ),
            child: Row(
              children: [
                Icon(
                  hasLocation ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.map_pin_ellipse,
                  color: hasLocation ? AppColors.primaryOrange : AppColors.textGrey,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pickedAddress ?? strings.pickLocationPrompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasLocation ? AppColors.textDark : AppColors.textGrey,
                      fontSize: 13.5,
                      fontWeight: hasLocation ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (hasLocation)
                  Text(
                    strings.changeLocationButton,
                    style: const TextStyle(color: AppColors.primaryOrange, fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              errorText!,
              style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ],
    );
  }
}

class _InlineErrorCard extends StatelessWidget {
  const _InlineErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: AppColors.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
