import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/widgets/app_form.dart';
import 'package:frontend/core/widgets/app_page_header.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/core/widgets/plain_page.dart';
import 'package:frontend/core/widgets/primary_action_button.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';
import 'package:frontend/features/waybills/data/waybill.dart';
import 'package:frontend/features/waybills/presentation/controllers/waybills_controller.dart';
import 'package:frontend/features/waybills/presentation/screens/new_waybill_flow.dart';
import 'package:frontend/features/waybills/presentation/screens/waybill_detail_screen.dart';

/// The Корзина tab: what this customer has sent, and the way to send another. The shell keeps it off an
/// owner's bar, and the server refuses an owner whatever the bar shows.
///
/// **It runs edge to edge like the map**, with no nav bar: the list ends in a pinned «Новая накладная»,
/// and a floating bar over it was a second button's worth of chrome on top of the one that matters.
class WaybillsScreen extends StatefulWidget {
  const WaybillsScreen({
    super.key,
    required this.isActive,
    required this.onExit,
  });

  /// The shell's IndexedStack builds every page at launch, so this is how the tab learns it is in view.
  final bool isActive;

  /// The way back to the rest of the app, drawn as the header's back disc. **Required**: with the nav
  /// bar gone this is the button, and a tab with no way out is the trap the shell's map test guards.
  final VoidCallback onExit;

  @override
  State<WaybillsScreen> createState() => _WaybillsScreenState();
}

class _WaybillsScreenState extends State<WaybillsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_recoverLostPhoto());
  }

  @override
  void didUpdateWidget(WaybillsScreen old) {
    super.didUpdateWidget(old);
    // opening the tab is the moment to look, on any phone this account has sent from. after the frame,
    // because the shell is mid-build here and a load notifies its listeners straight away
    if (widget.isActive && !old.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
  }

  void _reload() {
    final profile = context.read<AuthController>().profileState;
    if (profile.isGuest || !profile.seesCart) return;
    unawaited(context.read<WaybillsController>().load());
  }

  /// **On a phone short of memory Android kills this app while the camera is open**, and the photo comes
  /// back on the next launch through this call or not at all. Answering it is the difference between a
  /// customer's picture of their list and the app silently restarting on the home screen.
  ///
  /// An owner's lost product photo must not open a customer's flow, which is why the role is read first.
  Future<void> _recoverLostPhoto() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (!context.read<AuthController>().profileState.seesCart) return;

    final LostDataResponse lost;
    try {
      lost = await ImagePicker().retrieveLostData();
    } catch (error) {
      debugPrint('waybills: no lost photo to recover ($error)');
      return;
    }
    final file = lost.file;
    if (file == null || !mounted) return;
    await NewWaybillFlow.open(context, restoredPhoto: File(file.path));
  }

  Future<void> _newWaybill() async {
    await NewWaybillFlow.open(context);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final waybills = context.watch<WaybillsController>();

    final body = Column(
      children: [
        AppPageHeader(title: strings.cartTab, onBack: widget.onExit),
        Expanded(child: _content(waybills, strings)),
      ],
    );

    return ColoredBox(color: AppColors.background, child: body);
  }

  /// What the pinned button and the empty states keep clear at the foot: the system inset alone, since
  /// this tab has no nav bar over it.
  double get _bottomInset => MediaQuery.viewPaddingOf(context).bottom;

  Widget _content(WaybillsController waybills, AppLocalizations strings) {
    if (waybills.isLoading && waybills.items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryOrange),
      );
    }

    if (waybills.failure case final failure? when waybills.items.isEmpty) {
      return EmptyStateView(
        icon: failure == LoadFailure.network
            ? CupertinoIcons.wifi_exclamationmark
            : CupertinoIcons.exclamationmark_circle,
        iconColor: AppColors.danger,
        iconBackground: AppColors.dangerSoft,
        title: strings.cartLoadError,
        subtitle: strings.loadErrorHintFor(failure),
        action: PrimaryActionButton(
          label: strings.retryButtonShort,
          onTap: _reload,
        ),
        bottomInset: _bottomInset,
      );
    }

    if (waybills.items.isEmpty) {
      return EmptyStateView(
        icon: LucideIcons.shopping_cart,
        title: strings.cartEmptyTitle,
        subtitle: strings.cartEmptyBody,
        action: PrimaryActionButton(
          label: strings.cartNewButton,
          onTap: _newWaybill,
        ),
        bottomInset: _bottomInset,
      );
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primaryOrange,
            onRefresh: waybills.load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                PlainPageTitle.gutter,
                0,
                PlainPageTitle.gutter,
                12,
              ),
              children: [
                PageBand(
                  children: [
                    for (final waybill in waybills.items)
                      BandRow(
                        icon: waybill.category.icon,
                        title: strings.waybillNumber(waybill.id),
                        subtitle: _summary(waybill, strings),
                        // its own slot, because at the end of the subtitle the date is what gets cut off
                        trailing: Text(
                          waybill.dateLabel,
                          style: const TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () => WaybillDetailScreen.open(context, waybill),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // pinned rather than at the end of the list: the one thing this tab is for must not scroll away
        Padding(
          padding: EdgeInsets.fromLTRB(
            PlainPageTitle.gutter,
            4,
            PlainPageTitle.gutter,
            _bottomInset + 4,
          ),
          child: AppWideButton(
            label: strings.cartNewButton,
            onTap: _newWaybill,
          ),
        ),
      ],
    );
  }

  String _summary(Waybill waybill, AppLocalizations strings) {
    final content = waybill.hasPhoto
        ? strings.waybillPhotoLabel
        : strings.waybillRowCount(waybill.items.length);
    return '${waybill.category.label(strings)} · $content';
  }
}
