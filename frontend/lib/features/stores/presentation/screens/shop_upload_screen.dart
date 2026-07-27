import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/stores/data/product_upload_result.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import '../controllers/stores_controller.dart';

// per-shop screen opened from MyShopsScreen. for now this only supports bulk-uploading a products
// .xlsx file (see backend/internal/endpoints/products.go) - editing/adding a single product by hand
// is a later feature, not built yet.
class ShopUploadScreen extends StatefulWidget {
  const ShopUploadScreen({super.key, required this.shop});

  final Shop shop;

  @override
  State<ShopUploadScreen> createState() => _ShopUploadScreenState();
}

class _ShopUploadScreenState extends State<ShopUploadScreen> {
  // set when the file picker itself fails (an unreadable pick), as opposed to the backend rejecting
  // an upload - that one lives on the controller as a ProductUploadException
  String? _pickError;

  @override
  void initState() {
    super.initState();
    // clear on the way in, not on the way out: resetting in dispose() meant looking up a provider
    // off a context that is already being torn down, and notifying listeners mid-teardown. doing it
    // here is equivalent for the user (one shop's result never shows under another's name) and
    // safe, because nothing has rendered this state yet when initState runs.
    context.read<StoresController>().resetUploadState();
  }

  Future<void> _pickAndUpload() async {
    final controller = context.read<StoresController>();

    FilePickerResult? picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
    } on PlatformException catch (e) {
      debugPrint('File picker failed: $e');
      if (mounted) setState(() => _pickError = 'picker_failed');
      return;
    }

    if (picked == null || !mounted) return; // user dismissed the picker

    final path = picked.files.single.path;
    if (path == null) {
      // no readable path (a cloud/virtual file on some platforms) - say so rather than appearing
      // to do nothing at all when the button is tapped
      setState(() => _pickError = 'no_path');
      return;
    }

    setState(() => _pickError = null);
    await controller.uploadProductsFile(shopId: widget.shop.id, filePath: path);
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
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
          strings.uploadScreenTitle,
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
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            _ShopHeaderCard(shop: widget.shop, strings: strings),
            const SizedBox(height: 18),
            _FormatGuideCard(strings: strings),
            const SizedBox(height: 18),
            _UploadDropzone(
              strings: strings,
              isUploading: controller.isUploading,
              onTap: controller.isUploading ? null : _pickAndUpload,
            ),
            const SizedBox(height: 12),
            Text(
              strings.skippedRowsHint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textFaint,
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
            if (controller.uploadResult != null) ...[
              const SizedBox(height: 20),
              _UploadResultCard(result: controller.uploadResult!, strings: strings),
            ],
            if (controller.uploadError != null) ...[
              const SizedBox(height: 20),
              _MessageCard(
                icon: CupertinoIcons.exclamationmark_triangle_fill,
                color: AppColors.danger,
                background: AppColors.dangerSoft,
                message: strings.uploadErrorMessage(
                  controller.uploadError!.code,
                  limit: controller.uploadError!.limit,
                ),
              ),
            ],
            if (_pickError != null) ...[
              const SizedBox(height: 20),
              _MessageCard(
                icon: CupertinoIcons.exclamationmark_triangle_fill,
                color: AppColors.danger,
                background: AppColors.dangerSoft,
                message: strings.fileNotReadable,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// reminds the owner which shop they're uploading into - this screen is reachable from a list where
// every row looks alike, and uploading 50 products into the wrong shop is annoying to undo
class _ShopHeaderCard extends StatelessWidget {
  const _ShopHeaderCard({required this.shop, required this.strings});

  final Shop shop;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(CupertinoIcons.building_2_fill, color: AppColors.primaryOrange, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shop.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 16,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  shop.productCount > 0
                      ? strings.productsCountLabel(shop.productCount)
                      : strings.noProductsYet,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// the owner has no other way to discover the expected layout: the backend silently skips rows it
// can't read, so a mismatched column order would look like "the upload just doesn't work"
class _FormatGuideCard extends StatelessWidget {
  const _FormatGuideCard({required this.strings});

  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final columns = strings.productColumnSpec;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.table, color: AppColors.textFaint, size: 15),
              const SizedBox(width: 8),
              Text(
                strings.fileFormatTitle,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 15,
                  letterSpacing: -0.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            strings.fileFormatHint,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < columns.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // the column's position is the part that actually matters to the parser
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          columns[i].header,
                          style: const TextStyle(
                            color: AppColors.textDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          columns[i].example,
                          style: const TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// a dashed "drop target" rather than a plain button: it reads as a file slot, and it's a big tap
// area on the one action this whole screen exists for
class _UploadDropzone extends StatelessWidget {
  const _UploadDropzone({
    required this.strings,
    required this.isUploading,
    required this.onTap,
  });

  final AppLocalizations strings;
  final bool isUploading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: isUploading ? AppColors.hairline : AppColors.primaryOrange.withValues(alpha: 0.4),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
          decoration: BoxDecoration(
            color: isUploading ? AppColors.surfaceMuted : AppColors.primarySoft.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            children: [
              if (isUploading)
                const SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.primaryOrange),
                )
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: AppShadows.accent(AppColors.primaryOrange),
                  ),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryOrange,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(CupertinoIcons.arrow_up_doc_fill, color: Colors.white, size: 20),
                  ),
                ),
              const SizedBox(height: 13),
              Text(
                isUploading ? strings.uploadingLabel : strings.pickFileButton,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 15,
                  letterSpacing: -0.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!isUploading) ...[
                const SizedBox(height: 4),
                Text(
                  strings.pickFileHint,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// flutter has no dashed-border decoration built in, so the outline is drawn by hand: walk the
// rounded rect's path and paint alternating on/off segments of it
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(AppRadius.md)),
      );

    const dashLength = 6.0;
    const gapLength = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => oldDelegate.color != color;
}

class _UploadResultCard extends StatelessWidget {
  const _UploadResultCard({required this.result, required this.strings});

  final ProductUploadResult result;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    // a file that parsed cleanly but produced nothing is technically a 200, yet it's a failure from
    // the owner's point of view - it gets the warning treatment, not a green checkmark
    final isEmpty = result.isEmptyResult;
    final accent = isEmpty ? AppColors.starYellow : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isEmpty
                    ? CupertinoIcons.exclamationmark_circle_fill
                    : CupertinoIcons.checkmark_circle_fill,
                color: accent,
                size: 18,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  isEmpty ? strings.uploadNothingTitle : strings.uploadDoneTitle,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 15,
                    letterSpacing: -0.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatTile(
                value: result.rowsInFile,
                label: strings.uploadStatRows,
                color: AppColors.textDark,
              ),
              const SizedBox(width: 10),
              _StatTile(
                value: result.processed,
                label: strings.uploadStatProcessed,
                color: AppColors.success,
              ),
              const SizedBox(width: 10),
              _StatTile(
                value: result.skipped,
                label: strings.uploadStatSkipped,
                // zero skipped rows is the good outcome, so it shouldn't shout in warning colours
                color: result.skipped > 0 ? AppColors.starYellow : AppColors.textGrey,
              ),
            ],
          ),
          if (isEmpty) ...[
            const SizedBox(height: 12),
            Text(
              strings.uploadNothingHint,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 12.5,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label, required this.color});

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: 20,
                letterSpacing: -0.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textFaint,
                fontSize: 10.5,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.color,
    required this.background,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13, height: 1.35, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
