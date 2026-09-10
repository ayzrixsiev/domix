import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/widgets/pressable_scale.dart';

/// The photo control on [ProductEditScreen]. **It draws two sources of truth as one thing**: a
/// product being edited has its photo as a url, while one being *created* has no id to attach a file
/// to, so its photo is a file in the app's cache. [localFile] wins over [imageUrl] when both are set.
class ProductPhotoField extends StatelessWidget {
  const ProductPhotoField({
    super.key,
    required this.strings,
    required this.imageUrl,
    required this.localFile,
    required this.isBusy,
    required this.isPendingUpload,
    required this.isLocked,
    required this.onPick,
    required this.onRemove,
  });

  final AppLocalizations strings;

  /// What the server currently has, already absolute - see `Product.imageUrl`.
  final String? imageUrl;

  /// What the owner picked a moment ago and the server has not been told about yet.
  final File? localFile;

  /// An upload or a removal is in flight. The controls go inert and a scrim covers the picture rather
  /// than the picture disappearing - a photo that vanishes while it is being *saved* reads as deleted.
  final bool isBusy;

  /// True while a picked file waits for a product that does not exist yet. Draws the caption that
  /// stops the wait reading as a failed upload.
  final bool isPendingUpload;

  /// This row's photograph is the catalogue's and not the owner's to change - see
  /// `Product.photoEditable`. **The picture still shows, with a lock chip on it**: the owner is
  /// entitled to see what a customer sees on their own tile; what they are not offered is a control.
  final bool isLocked;

  final VoidCallback onPick;

  /// null when there is nothing to remove, which is what hides the button rather than disabling it.
  final VoidCallback? onRemove;

  /// Tall enough that a product is recognisable, short enough that the fields under it stay on screen
  /// with the keyboard up. `contain` inside it: filling a band crops the head off a hammer.
  static const double _height = 190;

  bool get _hasPhoto => localFile != null || (imageUrl != null && imageUrl!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PressableScale(
          // a tap anywhere on the frame opens the picker, and it is disabled outright while a request is in
          // flight so a second pick cannot race the first upload. null on a locked row leaves the frame inert
          // *and* unanimated, which stops it reading as a control that swallowed the tap.
          onTap: isBusy || isLocked ? null : onPick,
          child: Container(
            height: _height,
            width: double.infinity,
            decoration: BoxDecoration(
              color: _hasPhoto ? AppColors.surfaceWhite : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: _hasPhoto || isLocked ? AppColors.hairline : AppColors.primaryTint,
                // the empty state is an invitation, so its edge is heavier - the same weight the add-product tile
                // uses. a locked row is not an invitation, so it keeps the plain hairline even when empty.
                width: _hasPhoto || isLocked ? 1 : 1.4,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_hasPhoto)
                  _Photo(localFile: localFile, imageUrl: imageUrl)
                else if (isLocked)
                  const _PhotoUnavailable()
                else
                  _EmptyPrompt(strings: strings),
                if (isBusy) const _BusyScrim(),
                if (isLocked)
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: _Caption(
                      label: strings.templateFieldLocked,
                      icon: CupertinoIcons.lock_fill,
                    ),
                  ),
                if (isPendingUpload && !isBusy)
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: _Caption(label: strings.photoPendingSaveLabel),
                  ),
              ],
            ),
          ),
        ),
        if (_hasPhoto && !isLocked) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              _PhotoAction(
                label: strings.changePhotoAction,
                icon: CupertinoIcons.arrow_2_circlepath,
                onTap: isBusy ? null : onPick,
              ),
              const SizedBox(width: 10),
              if (onRemove != null)
                _PhotoAction(
                  label: strings.removePhotoAction,
                  icon: CupertinoIcons.trash,
                  isDestructive: true,
                  onTap: isBusy ? null : onRemove,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// a local file takes precedence: it is what the owner just chose, and the url beside it is still
// the previous photo until the upload finishes
class _Photo extends StatelessWidget {
  const _Photo({required this.localFile, required this.imageUrl});

  final File? localFile;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    if (localFile case final file?) {
      return Image.file(file, fit: BoxFit.contain);
    }
    return Image.network(
      imageUrl!,
      fit: BoxFit.contain,
      // decoded at roughly the width it is painted rather than at full size - a 1000px jpeg held as a raw
      // bitmap is 4 MB whatever it is drawn at
      cacheWidth: 900,
      errorBuilder: (_, _, _) => const _PhotoUnavailable(),
    );
  }
}

class _PhotoUnavailable extends StatelessWidget {
  const _PhotoUnavailable();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceMuted,
      child: Center(
        child: Icon(CupertinoIcons.photo, color: AppColors.textFaint, size: 30),
      ),
    );
  }
}

// the empty state: a glyph, a verb and the reason. an icon alone would be a grey box nobody presses.
class _EmptyPrompt extends StatelessWidget {
  const _EmptyPrompt({required this.strings});

  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
          child: const Icon(CupertinoIcons.camera, color: AppColors.primaryOrange, size: 21),
        ),
        const SizedBox(height: 12),
        Text(
          strings.addPhotoAction,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 14,
            letterSpacing: -0.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            strings.productPhotoHint,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

// covers the photo while a request is in flight instead of replacing it - see [ProductPhotoField.isBusy]
class _BusyScrim extends StatelessWidget {
  const _BusyScrim();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.72),
      child: const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primaryOrange),
        ),
      ),
    );
  }
}

// a solid white pill: a translucent one that reads correctly over a pale photo disappears over a
// dark one
class _Caption extends StatelessWidget {
  const _Caption({required this.label, this.icon = CupertinoIcons.clock});

  final String label;

  /// A clock while a pick waits for a product that does not exist yet, a padlock on a row whose photo
  /// is the catalogue's. Same pill, and the glyph is what says which of the two it is.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textGrey, size: 11),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// flat, bordered and equal in weight - neither is the primary action on this screen, which is the
// save button at the bottom
class _PhotoAction extends StatelessWidget {
  const _PhotoAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final colour = isDestructive ? AppColors.danger : AppColors.textDark;

    return Expanded(
      child: PressableScale(
        onTap: onTap,
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: enabled ? AppColors.surfaceWhite : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: enabled ? colour : AppColors.textFaint),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? colour : AppColors.textFaint,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "camera or gallery" sheet - a question with two answers asked only at the moment of tapping,
/// so both do not sit on the form permanently. Returns the picked source, or null if dismissed.
class PhotoSourceSheet extends StatelessWidget {
  const PhotoSourceSheet({super.key, required this.strings});

  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.trackGrey,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                strings.photoSourceTitle,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 16,
                  letterSpacing: -0.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _SourceRow(
              label: strings.photoFromCamera,
              icon: CupertinoIcons.camera_fill,
              onTap: () => Navigator.of(context).pop(PhotoSource.camera),
            ),
            const SizedBox(height: 10),
            _SourceRow(
              label: strings.photoFromGallery,
              icon: CupertinoIcons.photo_fill_on_rectangle_fill,
              onTap: () => Navigator.of(context).pop(PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's own enum rather than image_picker's `ImageSource`, so nothing outside the one method
/// that calls the plugin imports it.
enum PhotoSource { camera, gallery }

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primaryOrange, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(CupertinoIcons.chevron_right, color: AppColors.textFaint, size: 15),
          ],
        ),
      ),
    );
  }
}
