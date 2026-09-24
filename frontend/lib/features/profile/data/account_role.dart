import 'package:flutter/widgets.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:frontend/core/localization/app_localizations.dart';

/// Which side of the market this account stands on - picked at registration.
///
/// **It mirrors `users.role` exactly**, which is why nothing is stored on the phone: the server is
/// the only place a role lives, and `/api/me` is what answers on the next foreground. A third role
/// for workers comes back with the job marketplace, and with a server role of its own.
enum AccountRole {
  client('customer'),
  shopOwner('shop_owner');

  const AccountRole(this.code);

  /// a string rather than the enum index, so reordering cannot silently change what an account is
  final String code;

  static AccountRole of({required bool isVendor}) => isVendor ? shopOwner : client;

  /// **A role goes one way only.** A customer may become a shop owner; going back would strip them
  /// of the authorization to edit shops they still own - see PATCH /api/me, which refuses it on the
  /// server too, because a rule enforced only by a hidden button is not enforced.
  bool get canStillChange => this == client;

  /// The pill in the profile header. The short form for a shop owner - «Продавец» rather than
  /// «Владелец магазина», which is a sentence rather than a badge.
  String badgeLabel(AppLocalizations strings) => switch (this) {
        AccountRole.client => strings.roleCustomer,
        AccountRole.shopOwner => strings.vendorBadge,
      };

  // exhaustive switches rather than fields on the constructor: the analyzer fails the build on a
  // missing case, so a third role is a compile error instead of an untranslated label
  String label(AppLocalizations strings) => switch (this) {
        AccountRole.client => strings.roleCustomer,
        AccountRole.shopOwner => strings.roleVendor,
      };

  String subtitle(AppLocalizations strings) => switch (this) {
        AccountRole.client => strings.roleCustomerSub,
        AccountRole.shopOwner => strings.roleVendorSub,
      };

  IconData get icon => switch (this) {
        AccountRole.client => LucideIcons.house,
        AccountRole.shopOwner => LucideIcons.store,
      };
}
