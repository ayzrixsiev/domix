import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/app_form.dart';
import 'package:frontend/core/widgets/app_page_header.dart';
import 'package:frontend/core/widgets/circle_icon_button.dart';
import 'package:frontend/core/widgets/destructive_confirm_dialog.dart';
import 'package:frontend/core/widgets/pressable_scale.dart';
import 'package:frontend/core/widgets/role_option_tile.dart';
import 'package:frontend/core/widgets/segmented_tabs.dart';
import 'package:frontend/features/map/presentation/widgets/shop_marker.dart';
import 'package:frontend/features/onboarding/presentation/screens/onboarding_flow.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/waybills/data/waybill.dart';
import 'package:frontend/features/waybills/data/waybills_repository.dart';
import 'package:frontend/features/waybills/presentation/controllers/waybills_controller.dart';
import 'package:frontend/features/waybills/presentation/widgets/waybill_sheet.dart';

enum _Step { category, list, sent }

enum _Mode { form, photo }

/// What the keyboard and the server both hold a list to.
const int _maxRows = 100;
const int _maxNameLength = 150;
const int _maxQuantityLength = 30;

/// A new list: the market, then rows or a photo, then the number it was given.
///
/// A flow of its own over the shell, like onboarding: the X abandons it from any step, «Назад» walks one.
/// **A guest fills it in like anybody else** and signs in at «Отправить», with every row still there.
class NewWaybillFlow extends StatefulWidget {
  const NewWaybillFlow({super.key, this.restoredPhoto});

  /// A photo Android handed back after killing the app while the camera was open - see
  /// [WaybillsScreen]. The customer has lost everything else, so it is what they start from.
  final File? restoredPhoto;

  static Future<void> open(BuildContext context, {File? restoredPhoto}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NewWaybillFlow(restoredPhoto: restoredPhoto),
          fullscreenDialog: true,
        ),
      );

  @override
  State<NewWaybillFlow> createState() => _NewWaybillFlowState();
}

class _NewWaybillFlowState extends State<NewWaybillFlow> {
  _Step _step = _Step.category;
  late _Mode _mode = widget.restoredPhoto == null ? _Mode.form : _Mode.photo;
  ShopCategory? _category;

  final List<_RowDraft> _rows = [];
  int _nextRowId = 0;
  late File? _photo = widget.restoredPhoto;

  /// The rows the last refused «Отправить» complained about, painted until they are fixed.
  bool _showRowErrors = false;

  /// Already localized, because what produced it knew the reason and this does not.
  String? _error;
  bool _busy = false;
  Waybill? _sent;

  /// **The same id for every retry of the same list, a new one once anything changes.** A retried id
  /// answers with the list already stored, so keeping it across an edit would silently drop the edit.
  String? _requestId;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // **one line, because every row on the sheet has to be filled before it sends.** a sheet that
    // opened with three would refuse the customer who wants one thing until they deleted two.
    _rows.add(_newRow());
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  _RowDraft _newRow() => _RowDraft(_nextRowId++);

  // from onChanged rather than a controller listener, which also fires when a field merely takes focus:
  // that is what a refusal does to the field it names, and it would wipe the refusal off the screen
  void _edited() {
    _requestId = null;
    if (_error != null) setState(() => _error = null);
  }

  bool get _hasWork => _photo != null || _rows.any((row) => !row.isBlank);

  // ------------------------------------------------------------------------------------------
  // moving through the flow
  // ------------------------------------------------------------------------------------------

  Future<void> _close() async {
    if (_step != _Step.sent && _hasWork) {
      final strings = context.read<LanguageProvider>().strings;
      final confirmed = await DestructiveConfirmDialog.show(
        context,
        title: strings.waybillAbandonTitle,
        body: strings.waybillAbandonBody,
        confirmLabel: strings.closeButton,
        cancelLabel: strings.waybillAbandonKeep,
        icon: LucideIcons.x,
      );
      if (!confirmed) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _pickCategory(ShopCategory category) {
    _requestId = null;
    setState(() {
      _category = category;
      _step = _Step.list;
      _error = null;
    });
  }

  void _backToCategory() {
    setState(() {
      _step = _Step.category;
      _error = null;
    });
  }

  void _setMode(int index) {
    FocusScope.of(context).unfocus();
    _requestId = null;
    setState(() {
      _mode = _Mode.values[index];
      _error = null;
    });
  }

  // ------------------------------------------------------------------------------------------
  // the rows
  // ------------------------------------------------------------------------------------------

  // a sheet that gained or lost a row is not the sheet the last «Отправить» complained about, so the
  // refusal goes with it - which is also what makes deleting the row it named the way to clear it
  void _rowsChanged() {
    _requestId = null;
    _error = null;
    _showRowErrors = false;
  }

  void _addRow({bool focus = false}) {
    if (_rows.length >= _maxRows) return;
    final row = _newRow();
    setState(() {
      _rowsChanged();
      _rows.add(row);
    });
    if (focus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) row.nameFocus.requestFocus();
      });
    }
  }

  /// Takes a row off the sheet. **The last one stays**, filled or not: a sheet with no rows has no
  /// way back to one, and the cross is not offered on it - see [_sheet].
  void _removeRow(_RowDraft row) {
    setState(() {
      _rowsChanged();
      _rows.remove(row);
    });
    // after the frame, while the fields are still attached to the tree they are leaving
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  // the keyboard's «далее» from a quantity walks onto the next row, making one at the end of the sheet
  void _nextFrom(_RowDraft row) {
    final index = _rows.indexOf(row);
    if (index < 0) return;
    if (index + 1 < _rows.length) {
      _rows[index + 1].nameFocus.requestFocus();
    } else if (_rows.length < _maxRows) {
      _addRow(focus: true);
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  // ------------------------------------------------------------------------------------------
  // the photo
  // ------------------------------------------------------------------------------------------

  Future<void> _pickPhoto(ImageSource source) async {
    FocusScope.of(context).unfocus();

    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        // **large on purpose, unlike a product photo**: somebody has to read handwriting off this. the
        // limits are also what make the plugin re-encode, which turns a HEIC into a jpeg the server takes.
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
      );
    } on PlatformException catch (error) {
      debugPrint('new waybill: the picker refused: $error');
      if (mounted) {
        setState(
          () => _error = context
              .read<LanguageProvider>()
              .strings
              .waybillSendError('picker_failed'),
        );
      }
      return;
    }
    if (picked == null || !mounted) return;

    _requestId = null;
    final file = File(picked.path);
    setState(() {
      _photo = file;
      _error = null;
    });
  }

  void _removePhoto() {
    _requestId = null;
    setState(() => _photo = null);
  }

  // ------------------------------------------------------------------------------------------
  // sending
  // ------------------------------------------------------------------------------------------

  /// Null when the current mode holds something sendable, with the sentence and the focus handled.
  String? _validate(AppLocalizations strings) {
    if (_mode == _Mode.photo) {
      return _photo == null ? strings.waybillPhotoMissing : null;
    }

    if (_rows.every((row) => row.isBlank)) return strings.waybillEmptyError;

    // **every row goes, so every row has to be filled.** nothing is dropped on the way out: staff
    // price what is on the sheet, and a line the customer typed half of is a line they meant.
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      if (row.isComplete) continue;
      (row.name.isEmpty ? row.nameFocus : row.quantityFocus).requestFocus();
      return strings.waybillRowIncomplete(i + 1);
    }
    return null;
  }

  Future<void> _send() async {
    final strings = context.read<LanguageProvider>().strings;
    final category = _category!;

    final refusal = _validate(strings);
    if (refusal != null) {
      setState(() {
        _error = refusal;
        _showRowErrors = true;
      });
      return;
    }

    final auth = context.read<AuthController>();
    final waybills = context.read<WaybillsController>();

    if (auth.profileState.isGuest) {
      final signedIn = await OnboardingFlow.open(context);
      if (!mounted || !signedIn) return;
    }

    // signing in can land on an owner's account, and the tab that would have said so has just gone
    if (!auth.profileState.seesCart) {
      setState(() => _error = strings.waybillSendError('customers_only'));
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    final requestId = _requestId ??= _newRequestId();
    setState(() {
      _busy = true;
      _error = null;
      _showRowErrors = false;
    });

    try {
      final Waybill waybill;
      if (_mode == _Mode.photo) {
        waybill = await waybills.repository.sendPhoto(
          requestId: requestId,
          category: category,
          filePath: _photo!.path,
        );
      } else {
        waybill = await waybills.repository.sendList(
          requestId: requestId,
          category: category,
          items: [
            for (final row in _rows)
              WaybillItem(name: row.name, quantity: row.quantity),
          ],
        );
      }
      if (!mounted) return;

      waybills.add(waybill);
      setState(() {
        _busy = false;
        _sent = waybill;
        _step = _Step.sent;
      });
    } catch (error) {
      debugPrint('new waybill: send failed ($error)');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = strings.waybillSendError(
          error is WaybillSendException ? error.code : 'network',
        );
      });
    }
  }

  static String _newRequestId() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }

  // ------------------------------------------------------------------------------------------
  // drawing
  // ------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LanguageProvider>().strings;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _busy) return;
        if (_step == _Step.list) {
          _backToCategory();
        } else {
          _close();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPageHeader(
              title: strings.cartNewButton,
              // «Назад» in the footer is the step back; this abandons the whole flow
              showBack: false,
              action: CircleIconButton(
                icon: LucideIcons.x,
                tooltip: strings.closeButton,
                onTap: _busy ? () {} : _close,
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: AppMotion.base,
                switchInCurve: AppMotion.easing,
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: switch (_step) {
                    _Step.category => _categoryStep(strings),
                    _Step.list => _listStep(strings),
                    _Step.sent => _sentStep(strings),
                  },
                ),
              ),
            ),
            if (_step == _Step.list) _footer(strings),
          ],
        ),
      ),
    );
  }

  Widget _categoryStep(AppLocalizations strings) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          strings.waybillCategoryTitle,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 22,
            height: 1.2,
            letterSpacing: -0.4,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          strings.waybillCategoryHint,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        for (final category in ShopCategory.values) ...[
          RoleOptionTile.artwork(
            // the pin this market is plotted as on the map: the customer picks here the same drawing
            // they will go looking for there
            artwork: ShopPinIcon(category: category, height: 42),
            title: category.label(strings),
            subtitle: category.description(strings),
            isSelected: null,
            onTap: () => _pickCategory(category),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _listStep(AppLocalizations strings) {
    return ListView(
      // the fields sit in a list, so a dragged list puts the keyboard away instead of fighting it
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        SegmentedTabs(
          labels: [strings.waybillModeForm, strings.waybillModePhoto],
          selected: _mode.index,
          onSelected: _setMode,
        ),
        const SizedBox(height: 14),
        if (_mode == _Mode.form)
          _sheet(strings)
        else
          _PhotoPane(
            strings: strings,
            photo: _photo,
            busy: _busy,
            onPick: _pickPhoto,
            onRemove: _removePhoto,
          ),
      ],
    );
  }

  Widget _sheet(AppLocalizations strings) {
    return WaybillSheet(
      strings: strings,
      editable: true,
      trailingHeading: strings.waybillNumberPending,
      shopsLine: strings.waybillShopsLine(_category!.label(strings)),
      rows: [
        for (var i = 0; i < _rows.length; i++)
          _EditableRow(
            key: ValueKey(_rows[i].id),
            row: _rows[i],
            number: i + 1,
            strings: strings,
            showError: _showRowErrors,
            onEdited: _edited,
            onNext: () => _nextFrom(_rows[i]),
            onRemove: _rows.length > 1 ? () => _removeRow(_rows[i]) : null,
          ),
      ],
      footer: _rows.length >= _maxRows
          ? Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                strings.waybillRowLimit,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textGrey, fontSize: 13),
              ),
            )
          : DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.hairline)),
              ),
              child: PressableScale(
                onTap: () => _addRow(focus: true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        LucideIcons.plus,
                        size: 17,
                        color: AppColors.primaryOrange,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        strings.waybillAddRow,
                        style: const TextStyle(
                          color: AppColors.primaryOrange,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _footer(AppLocalizations strings) {
    // viewPadding rather than padding, which collapses while the keyboard is open. the keyboard itself
    // is what pushes this up: Scaffold resizes the body to clear it.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final systemInset = keyboardOpen
        ? 0.0
        : MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, systemInset + 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error case final message?) ...[
            AppErrorLine(message),
            const SizedBox(height: 10),
          ],
          AppWideButton(
            label: strings.waybillSend,
            busy: _busy,
            onTap: _busy ? null : _send,
          ),
          // the sheet stays in reach while typing: a second footer line would eat what the keyboard left
          if (!keyboardOpen)
            SizedBox(
              height: 40,
              child: TextButton(
                onPressed: _busy ? null : _backToCategory,
                child: Text(
                  strings.stepBackButton,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sentStep(AppLocalizations strings) {
    final waybill = _sent!;
    final phone = context.read<AuthController>().profileState.phoneNumber;
    final systemInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, systemInset + 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                color: AppColors.successSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.check,
                color: AppColors.success,
                size: 34,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            strings.waybillNumber(waybill.id),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 24,
              height: 1.2,
              letterSpacing: -0.4,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            strings.waybillSentBody(formatUzPhone(phone)),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 14.5,
              height: 1.45,
            ),
          ),
          const Spacer(),
          AppWideButton(
            label: strings.waybillSentDone,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// The two fields of one row and everything that has to be released with them.
class _RowDraft {
  _RowDraft(this.id);

  final int id;
  final nameController = TextEditingController();
  final quantityController = TextEditingController();
  final nameFocus = FocusNode();
  final quantityFocus = FocusNode();

  String get name => nameController.text.trim();
  String get quantity => quantityController.text.trim();

  bool get isBlank => name.isEmpty && quantity.isEmpty;
  bool get isComplete => name.isNotEmpty && quantity.isNotEmpty;

  void dispose() {
    nameController.dispose();
    quantityController.dispose();
    nameFocus.dispose();
    quantityFocus.dispose();
  }
}

class _EditableRow extends StatelessWidget {
  const _EditableRow({
    super.key,
    required this.row,
    required this.number,
    required this.strings,
    required this.showError,
    required this.onEdited,
    required this.onNext,
    required this.onRemove,
  });

  final _RowDraft row;
  final int number;
  final AppLocalizations strings;
  final bool showError;
  final VoidCallback onEdited;
  final VoidCallback onNext;

  /// Null on the last row left, which has no cross: the sheet always keeps one.
  final VoidCallback? onRemove;

  static const _fieldStyle = TextStyle(
    color: AppColors.textDark,
    fontSize: 14.5,
    height: 1.3,
  );

  InputDecoration _decoration(String hint, bool refused) => InputDecoration(
    isCollapsed: true,
    border: InputBorder.none,
    contentPadding: const EdgeInsets.symmetric(vertical: 13),
    hintText: hint,
    hintStyle: TextStyle(
      color: refused ? AppColors.danger : AppColors.textFaint,
      fontSize: 14.5,
      fontWeight: FontWeight.w400,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        row.nameController,
        row.quantityController,
      ]),
      builder: (context, _) {
        final broken = showError && !row.isComplete;
        final nameRefused = broken && row.name.isEmpty;
        final quantityRefused = broken && row.quantity.isEmpty;

        return WaybillRowFrame(
          quantityTint: quantityRefused ? AppColors.dangerSoft : null,
          number: Text(
            '$number',
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          name: TextField(
            controller: row.nameController,
            focusNode: row.nameFocus,
            style: _fieldStyle,
            cursorColor: AppColors.primaryOrange,
            // long names wrap and the row grows, because the whole name goes on the form
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            inputFormatters: [LengthLimitingTextInputFormatter(_maxNameLength)],
            onChanged: (_) => onEdited(),
            onSubmitted: (_) => row.quantityFocus.requestFocus(),
            decoration: _decoration(strings.waybillNameHint, nameRefused),
          ),
          quantity: TextField(
            controller: row.quantityController,
            focusNode: row.quantityFocus,
            style: _fieldStyle,
            cursorColor: AppColors.primaryOrange,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_maxQuantityLength),
            ],
            onChanged: (_) => onEdited(),
            onSubmitted: (_) => onNext(),
            decoration: _decoration(
              strings.waybillQuantityHint,
              quantityRefused,
            ),
          ),
          // **the empty slot, not no slot**: the column has to run the height of the sheet, or the
          // rule beside the last row steps in by 30px
          trailing: switch (onRemove) {
            final VoidCallback remove => Tooltip(
              message: strings.waybillRemoveRow,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: remove,
                child: const Center(
                  child: Icon(
                    LucideIcons.x,
                    size: 15,
                    color: AppColors.textFaint,
                  ),
                ),
              ),
            ),
            _ => const SizedBox.shrink(),
          },
        );
      },
    );
  }
}

class _PhotoPane extends StatelessWidget {
  const _PhotoPane({
    required this.strings,
    required this.photo,
    required this.busy,
    required this.onPick,
    required this.onRemove,
  });

  final AppLocalizations strings;
  final File? photo;
  final bool busy;
  final ValueChanged<ImageSource> onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final picked = photo;
    if (picked == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _SourceTile(
                  icon: LucideIcons.camera,
                  label: strings.waybillTakePhoto,
                  onTap: () => onPick(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SourceTile(
                  icon: LucideIcons.images,
                  label: strings.waybillFromGallery,
                  onTap: () => onPick(ImageSource.gallery),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              strings.waybillPhotoPrompt,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 340,
          decoration: BoxDecoration(
            color: AppColors.surfaceWhite,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: AppShadows.card,
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.file(picked, fit: BoxFit.contain, cacheWidth: 900),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: busy ? null : () => onPick(ImageSource.camera),
                icon: const Icon(
                  LucideIcons.camera,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                label: Text(
                  strings.waybillRetakePhoto,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: busy ? null : onRemove,
                icon: const Icon(
                  LucideIcons.trash_2,
                  size: 16,
                  color: AppColors.danger,
                ),
                label: Text(
                  strings.removePhotoAction,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 26),
        decoration: BoxDecoration(
          color: AppColors.surfaceWhite,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primaryOrange, size: 23),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 14,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
