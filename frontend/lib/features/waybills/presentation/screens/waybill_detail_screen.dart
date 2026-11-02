import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/widgets/app_page_header.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/core/widgets/primary_action_button.dart';
import 'package:frontend/features/waybills/data/waybill.dart';
import 'package:frontend/features/waybills/presentation/controllers/waybills_controller.dart';
import 'package:frontend/features/waybills/presentation/widgets/waybill_sheet.dart';

/// One sent list, read back. Nothing here edits it: it has a number and staff may already be working
/// from it.
class WaybillDetailScreen extends StatefulWidget {
  const WaybillDetailScreen({super.key, required this.waybill});

  final Waybill waybill;

  static Future<void> open(BuildContext context, Waybill waybill) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WaybillDetailScreen(waybill: waybill),
        ),
      );

  @override
  State<WaybillDetailScreen> createState() => _WaybillDetailScreenState();
}

class _WaybillDetailScreenState extends State<WaybillDetailScreen> {
  Future<Uint8List>? _photo;

  @override
  void initState() {
    super.initState();
    if (widget.waybill.hasPhoto) _loadPhoto();
  }

  // through the repository and not Image.network: the photo is private, and the bearer token and the
  // 401 handling are all there
  void _loadPhoto() {
    final repository = context.read<WaybillsController>().repository;
    setState(() => _photo = repository.fetchPhoto(widget.waybill.id));
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final waybill = widget.waybill;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          AppPageHeader(
            title: strings.waybillNumber(waybill.id),
            subtitle:
                '${waybill.category.label(strings)} · ${waybill.dateLabel}',
          ),
          Expanded(
            child: waybill.hasPhoto ? _photoView(strings) : _rowsView(strings),
          ),
        ],
      ),
    );
  }

  Widget _rowsView(AppLocalizations strings) {
    final waybill = widget.waybill;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        WaybillSheet(
          strings: strings,
          trailingHeading: '№ ${waybill.id}',
          shopsLine: strings.waybillShopsLine(waybill.category.label(strings)),
          rows: [
            for (var i = 0; i < waybill.items.length; i++)
              WaybillRowFrame(
                number: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                name: _cell(waybill.items[i].name),
                quantity: _cell(waybill.items[i].quantity),
              ),
          ],
        ),
      ],
    );
  }

  Widget _cell(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.textDark,
        fontSize: 14.5,
        height: 1.3,
      ),
    ),
  );

  Widget _photoView(AppLocalizations strings) {
    return FutureBuilder<Uint8List>(
      future: _photo,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final failure = LoadFailure.of(snapshot.error!);
          return EmptyStateView(
            icon: CupertinoIcons.exclamationmark_circle,
            iconColor: AppColors.danger,
            iconBackground: AppColors.dangerSoft,
            title: strings.waybillPhotoError,
            subtitle: strings.loadErrorHintFor(failure),
            action: PrimaryActionButton(
              label: strings.retryButtonShort,
              onTap: _loadPhoto,
            ),
          );
        }

        final bytes = snapshot.data;
        if (bytes == null) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primaryOrange),
          );
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            MediaQuery.viewPaddingOf(context).bottom + 16,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: ColoredBox(
              color: AppColors.surfaceWhite,
              // handwriting is read with two fingers
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
              ),
            ),
          ),
        );
      },
    );
  }
}
