import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/features/favorites/presentation/controllers/favorites_controller.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/onboarding/presentation/screens/onboarding_flow.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';

/// What the heart on a product tile does, in the one place both grids call.
///
/// **A guest has nowhere to save to**, so the tap opens the sign-in flow rather than failing quietly -
/// and if they come back with an account the product they were reaching for is saved, which is what
/// the tap meant.
Future<void> toggleFavorite(BuildContext context, CategoryProduct item) async {
  if (context.read<AuthController>().profileState.isGuest) {
    final signedIn = await OnboardingFlow.open(context);
    if (!signedIn || !context.mounted) return;
    await context.read<FavoritesController>().load();
    if (!context.mounted) return;
  }
  await context.read<FavoritesController>().toggle(item);
}
