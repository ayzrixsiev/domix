import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/circle_back_button.dart';
import 'package:frontend/features/stores/presentation/widgets/store_form_fields.dart';
import 'package:frontend/features/tickets/data/job_category.dart';
import 'package:frontend/features/tickets/presentation/controllers/tickets_controller.dart';

/// «Оставить заявку» - the client's half of the marketplace, as a form. It reuses the shop form's
/// inputs rather than styling its own, and contributes the one control those forms lack: the trade
/// picker.
///
/// Nothing is sent anywhere. [TicketsController.addTicket] puts the ticket into the client's list
/// *and* the open feed, so switching roles afterwards shows it arriving on a worker's screen.
class CreateTicketScreen extends StatefulWidget {
  const CreateTicketScreen({super.key});

  @override
  State<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends State<CreateTicketScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _budgetController = TextEditingController();
  final _districtController = TextEditingController();

  JobCategory _category = JobCategory.finishing;

  /// Set only once the user has pressed the button - a form that turns red while it is still being
  /// filled in is telling somebody off for not having finished yet.
  bool _submitted = false;

  AppLocalizations get _strings => Provider.of<LanguageProvider>(context).strings;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _budgetController.dispose();
    _districtController.dispose();
    super.dispose();
  }

  String? _errorFor(TextEditingController controller) {
    if (!_submitted || controller.text.trim().isNotEmpty) return null;
    return _strings.fieldRequiredError;
  }

  void _submit() {
    setState(() => _submitted = true);

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final district = _districtController.text.trim();
    final budget = int.tryParse(_budgetController.text.trim()) ?? 0;

    if (title.isEmpty || description.isEmpty || district.isEmpty || budget <= 0) return;

    Provider.of<TicketsController>(context, listen: false).addTicket(
      title: title,
      description: description,
      category: _category,
      budgetFrom: budget,
      district: district,
    );

    // read before the pop: after it this element is deactivated and the lookup asserts
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(_strings.ticketPostedMessage),
        backgroundColor: AppColors.textDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = _strings;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        iconTheme: const IconThemeData(color: AppColors.textDark, size: 22),
        leading: const CircleBackButton(),
        leadingWidth: CircleBackButton.leadingWidth,
        title: Text(
          strings.createTicketTitle,
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
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            StoreFormLabel(strings.ticketTitleLabel),
            const SizedBox(height: 8),
            StoreFormTextField(
              controller: _titleController,
              hint: strings.ticketTitleHint,
              icon: LucideIcons.clipboard_list,
              errorText: _errorFor(_titleController),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 18),
            StoreFormLabel(strings.ticketCategoryLabel),
            const SizedBox(height: 8),
            JobCategoryPicker(
              selected: {_category},
              strings: strings,
              onToggle: (category) => setState(() => _category = category),
            ),
            const SizedBox(height: 18),
            StoreFormLabel(strings.ticketDescriptionLabel),
            const SizedBox(height: 8),
            // the one field that is not a StoreFormTextField: a job is described in sentences, and a
            // single-line input for three of them is why people write «ремонт» and press send
            _DescriptionField(
              controller: _descriptionController,
              hint: strings.ticketDescriptionHint,
              errorText: _errorFor(_descriptionController),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 18),
            StoreFormLabel(strings.ticketBudgetLabel),
            const SizedBox(height: 8),
            StoreFormTextField(
              controller: _budgetController,
              hint: strings.ticketBudgetHint,
              icon: LucideIcons.wallet,
              keyboardType: TextInputType.number,
              // digits only, filtered at the keyboard: what cannot be typed cannot be wrong
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              suffixText: strings.currencySom,
              errorText: _submitted && (int.tryParse(_budgetController.text.trim()) ?? 0) <= 0
                  ? strings.fieldRequiredError
                  : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 18),
            StoreFormLabel(strings.ticketDistrictLabel),
            const SizedBox(height: 8),
            StoreFormTextField(
              controller: _districtController,
              hint: strings.ticketDistrictHint,
              icon: LucideIcons.map_pin,
              errorText: _errorFor(_districtController),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 26),
            StoreSubmitButton(
              label: strings.publishTicket,
              isBusy: false,
              icon: LucideIcons.send_horizontal,
              onTap: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// The trades, as a wrap of toggles. **One widget for two jobs**: the client's form picks exactly
/// one, the worker's анкета several - the difference is which set the caller hands back from
/// [onToggle], so the control never has to know how many are allowed.
class JobCategoryPicker extends StatelessWidget {
  const JobCategoryPicker({
    super.key,
    required this.selected,
    required this.strings,
    required this.onToggle,
  });

  final Set<JobCategory> selected;
  final AppLocalizations strings;
  final ValueChanged<JobCategory> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final category in JobCategory.values)
          _CategoryToggle(
            category: category,
            label: category.label(strings),
            isSelected: selected.contains(category),
            onTap: () => onToggle(category),
          ),
      ],
    );
  }
}

class _CategoryToggle extends StatelessWidget {
  const _CategoryToggle({
    required this.category,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final JobCategory category;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easing,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primarySoft : AppColors.surfaceWhite,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: isSelected ? AppColors.primaryOrange : AppColors.hairline,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                category.icon,
                size: 15,
                color: isSelected ? AppColors.primaryOrange : AppColors.textMuted,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppColors.primaryOrange : AppColors.textDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A multi-line variant of [StoreFormTextField] - four lines tall and no prefix icon, since a glyph
/// pinned to the top-left of a paragraph box reads as a bullet.
class _DescriptionField extends StatelessWidget {
  const _DescriptionField({
    required this.controller,
    required this.hint,
    required this.errorText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final String? errorText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      minLines: 4,
      maxLines: 6,
      textCapitalization: TextCapitalization.sentences,
      cursorColor: AppColors.primaryOrange,
      style: const TextStyle(color: AppColors.textDark, fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: AppColors.textFaint,
          fontSize: 15,
          height: 1.4,
          fontWeight: FontWeight.w400,
        ),
        errorText: errorText,
        errorStyle: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w500),
        filled: true,
        fillColor: AppColors.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
