import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/widgets/app_page_header.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/core/widgets/primary_action_button.dart';
import 'package:frontend/features/favorites/presentation/controllers/favorites_controller.dart';
import 'package:frontend/features/favorites/presentation/favorite_action.dart';
import 'package:frontend/features/products/presentation/widgets/product_grid.dart';
import 'package:frontend/features/products/presentation/widgets/product_tile.dart';
import 'package:frontend/features/stores/presentation/screens/shop_card_screen.dart';

/// The saved products, opened from Профиль.
///
/// Unlike the category pages this reads the controller rather than loading a list of its own: the
/// hearts on those pages write to the same controller, so a product unsaved anywhere has to leave
/// this grid without a second request.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const FavoritesScreen()));

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  void initState() {
    super.initState();
    // the controller may already hold a list from sign-in; opening the screen is still the moment to
    // find out whether a shop has withdrawn something since
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<FavoritesController>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final favorites = context.watch<FavoritesController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          AppPageHeader(title: strings.favorites),
          Expanded(child: _body(favorites, strings)),
        ],
      ),
    );
  }

  Widget _body(FavoritesController favorites, AppLocalizations strings) {
    if (favorites.isLoading && favorites.items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryOrange),
      );
    }

    if (favorites.failure case final failure? when favorites.items.isEmpty) {
      return EmptyStateView(
        icon: failure == LoadFailure.network
            ? CupertinoIcons.wifi_exclamationmark
            : CupertinoIcons.exclamationmark_circle,
        iconColor: AppColors.danger,
        iconBackground: AppColors.dangerSoft,
        title: strings.favoritesLoadError,
        subtitle: strings.loadErrorHintFor(failure),
        action: PrimaryActionButton(
          label: strings.retryButtonShort,
          onTap: () => context.read<FavoritesController>().load(),
        ),
      );
    }

    if (favorites.items.isEmpty) {
      return EmptyStateView(
        icon: CupertinoIcons.heart,
        title: strings.favoritesEmptyTitle,
        subtitle: strings.favoritesEmptyBody,
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryOrange,
      onRefresh: () => context.read<FavoritesController>().load(),
      child: ProductGrid(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        tiles: [
          for (final entry in favorites.items)
            ProductTile(
              product: entry.product,
              strings: strings,
              subtitle: entry.shopName,
              showBuyerActions: true,
              // always true here by definition, and tapping it is how a product leaves this grid
              isFavorite: true,
              onFavoriteToggle: () => toggleFavorite(context, entry),
              onTap: () => openShopById(context, entry.product.shopId),
            ),
        ],
      ),
    );
  }
}
