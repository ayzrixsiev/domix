import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
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
            _SubmitButton(
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

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textDark,
        fontSize: 13,
        letterSpacing: 0.1,
        fontWeight: FontWeight.w600,
      ),
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
      style: const TextStyle(color: AppColors.textDark, fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 15, fontWeight: FontWeight.w400),
        errorText: errorText,
        errorStyle: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w500),
        filled: true,
        fillColor: AppColors.surfaceMuted,
        prefixIcon: Icon(icon, color: AppColors.textFaint, size: 18),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        // an unfocused field is a plain hairline, not a heavy outline - the border only gains
        // weight and colour once the field is actually the one being edited
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.primaryOrange, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
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
        : (hasLocation ? AppColors.primaryOrange : AppColors.hairline);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Ink(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: borderColor,
                  width: hasLocation || errorText != null ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    hasLocation ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.map_pin_ellipse,
                    color: hasLocation ? AppColors.primaryOrange : AppColors.textFaint,
                    size: 18,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      pickedAddress ?? strings.pickLocationPrompt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasLocation ? AppColors.textDark : AppColors.textFaint,
                        fontSize: 13.5,
                        height: 1.35,
                        fontWeight: hasLocation ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (hasLocation) ...[
                    const SizedBox(width: 10),
                    Text(
                      strings.changeLocationButton,
                      style: const TextStyle(
                        color: AppColors.primaryOrange,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              errorText!,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
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
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: AppColors.danger, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// matches the call cta in the shop details sheet: fixed comfortable height, radius from the scale,
// and a soft brand-coloured glow instead of material's default grey elevation.
class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.label, required this.isBusy, required this.onTap});

  final String label;
  final bool isBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        // the glow is dropped while saving so the disabled state reads as genuinely inert
        boxShadow: isBusy ? const [] : AppShadows.accent(AppColors.primaryOrange),
      ),
      child: Material(
        color: isBusy ? AppColors.primaryOrange.withValues(alpha: 0.55) : AppColors.primaryOrange,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: isBusy ? null : onTap,
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: Center(
              child: isBusy
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        letterSpacing: 0.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
