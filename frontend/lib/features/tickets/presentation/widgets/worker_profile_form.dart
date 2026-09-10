import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/features/stores/presentation/widgets/store_form_fields.dart';
import 'package:frontend/features/tickets/data/job_category.dart';
import 'package:frontend/features/tickets/data/job_ticket.dart';
import 'package:frontend/features/tickets/presentation/controllers/tickets_controller.dart';
import 'package:frontend/features/tickets/presentation/screens/create_ticket_screen.dart';
import 'package:frontend/features/tickets/presentation/widgets/worker_card.dart';

/// «Моя анкета» - the worker's own listing, with the card a client will read sitting **above** the
/// fields that produce it. The preview updates on every keystroke: a form whose result is only
/// visible after saving asks the writer to imagine the reader.
class WorkerProfileForm extends StatefulWidget {
  const WorkerProfileForm({super.key, required this.strings, required this.bottomPadding});

  final AppLocalizations strings;
  final double bottomPadding;

  @override
  State<WorkerProfileForm> createState() => _WorkerProfileFormState();
}

class _WorkerProfileFormState extends State<WorkerProfileForm> {
  late final TextEditingController _experienceController;
  late final TextEditingController _priceController;
  late final TextEditingController _aboutController;

  late Set<JobCategory> _skills;
  late bool _availableNow;

  @override
  void initState() {
    super.initState();
    // seeded from whatever the controller already holds, so leaving the tab and coming back does not
    // throw away half-finished edits
    final profile = context.read<TicketsController>().myProfile;
    _experienceController = TextEditingController(text: profile.experienceYears.toString());
    _priceController = TextEditingController(text: profile.priceFrom.toString());
    _aboutController = TextEditingController(text: profile.about.of(widget.strings));
    _skills = {...profile.skills};
    _availableNow = profile.availableNow;
  }

  @override
  void dispose() {
    _experienceController.dispose();
    _priceController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  /// What the preview draws: the stored profile with everything currently on screen laid over it.
  WorkerProfile _draftOf(WorkerProfile stored) {
    final about = _aboutController.text.trim();
    return stored.copyWith(
      skills: _skills.toList(),
      experienceYears: int.tryParse(_experienceController.text.trim()) ?? stored.experienceYears,
      priceFrom: int.tryParse(_priceController.text.trim()) ?? stored.priceFrom,
      about: about.isEmpty ? stored.about : DemoText(about, about),
      availableNow: _availableNow,
    );
  }

  /// A worker with no trade selected cannot be matched to anything, so that is the one field the form
  /// refuses to save empty.
  void _save() {
    if (_skills.isEmpty) {
      _toast(widget.strings.skillsRequiredError);
      return;
    }

    Provider.of<TicketsController>(context, listen: false).saveProfile(
      skills: _skills.toList(),
      experienceYears: int.tryParse(_experienceController.text.trim()) ?? 0,
      priceFrom: int.tryParse(_priceController.text.trim()) ?? 0,
      about: _aboutController.text.trim(),
      availableNow: _availableNow,
    );

    FocusScope.of(context).unfocus();
    _toast(widget.strings.profileSavedMessage);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.textDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final stored = context.watch<TicketsController>().myProfile;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, widget.bottomPadding + 24),
      children: [
        Text(
          strings.profilePreviewLabel,
          style: const TextStyle(
            color: AppColors.textFaint,
            fontSize: 11.5,
            letterSpacing: 0.3,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        WorkerCard(worker: _draftOf(stored), strings: strings, isPreview: true),
        const SizedBox(height: 24),
        StoreFormLabel(strings.profileSkillsLabel),
        const SizedBox(height: 8),
        JobCategoryPicker(
          selected: _skills,
          strings: strings,
          // a set, not a single value: this is the picker's multi-select half, and the toggle is what makes
          // it so - the client's form hands back a one-element set instead
          onToggle: (category) => setState(() {
            _skills.contains(category) ? _skills.remove(category) : _skills.add(category);
          }),
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StoreFormLabel(strings.profileExperienceLabel),
                  const SizedBox(height: 8),
                  StoreFormTextField(
                    controller: _experienceController,
                    hint: '5',
                    icon: LucideIcons.briefcase,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StoreFormLabel(strings.profilePriceLabel),
                  const SizedBox(height: 8),
                  StoreFormTextField(
                    controller: _priceController,
                    hint: '400000',
                    icon: LucideIcons.wallet,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        StoreFormLabel(strings.profileAboutLabel),
        const SizedBox(height: 8),
        _AboutField(
          controller: _aboutController,
          hint: strings.profileAboutHint,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        _AvailabilitySwitch(
          value: _availableNow,
          strings: strings,
          onChanged: (value) => setState(() => _availableNow = value),
        ),
        const SizedBox(height: 24),
        StoreSubmitButton(
          label: strings.saveProfile,
          isBusy: false,
          icon: LucideIcons.badge_check,
          onTap: _save,
        ),
      ],
    );
  }
}

/// The «Готов взять заказ» toggle, as a card rather than a bare switch in a row: it is the field
/// with the largest consequence here - it decides whether the card shows a green dot, the first
/// thing a client filters on - so it is not left to be scrolled past in the run of text inputs.
class _AvailabilitySwitch extends StatelessWidget {
  const _AvailabilitySwitch({
    required this.value,
    required this.strings,
    required this.onChanged,
  });

  final bool value;
  final AppLocalizations strings;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.profileAvailableLabel,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  strings.profileAvailableHint,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.primaryOrange,
          ),
        ],
      ),
    );
  }
}

/// Same shape as the ticket form's description box. Written out rather than shared because the two
/// differ in every value that matters - height, hint, capitalisation - and a widget parameterised
/// down to nothing shared is a worse copy than two honest ones.
class _AboutField extends StatelessWidget {
  const _AboutField({required this.controller, required this.hint, required this.onChanged});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      minLines: 3,
      maxLines: 5,
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
      ),
    );
  }
}
