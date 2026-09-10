import 'package:flutter/widgets.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:frontend/core/localization/app_localizations.dart';

/// Which side of the job market this account stands on - picked at registration, and the only thing
/// that decides what the Заявки tab draws.
///
/// **This is not the account's server role**: `users.role` governs *permissions*, this governs a
/// *view*. [worker] has no server counterpart yet - `/api/auth/init` normalises everything that is
/// not `shop_owner` down to `customer` - so a worker is stored as a customer and this enum, held on
/// the phone by [TicketsController], is what remembers the difference.
enum JobRole {
  client('customer'),
  worker('worker'),
  shopOwner('shop_owner');

  const JobRole(this.code);

  /// a string rather than the enum index, so reordering the enum cannot silently turn every stored
  /// worker into a client
  final String code;

  /// an unrecognised value is null rather than a guess: the caller shows the role chooser, where
  /// defaulting would put somebody in the wrong half of the marketplace without ever asking
  static JobRole? tryFromCode(String? code) {
    for (final role in values) {
      if (role.code == code) return role;
    }
    return null;
  }

  // exhaustive switches rather than fields on the constructor: the analyzer fails the build on a
  // missing case, so a fourth role is a compile error instead of an untranslated label
  String label(AppLocalizations strings) => switch (this) {
        JobRole.client => strings.roleCustomer,
        JobRole.worker => strings.roleWorker,
        JobRole.shopOwner => strings.roleVendor,
      };

  String subtitle(AppLocalizations strings) => switch (this) {
        JobRole.client => strings.roleCustomerSub,
        JobRole.worker => strings.roleWorkerSub,
        JobRole.shopOwner => strings.roleVendorSub,
      };

  IconData get icon => switch (this) {
        JobRole.client => LucideIcons.house,
        JobRole.worker => LucideIcons.hard_hat,
        JobRole.shopOwner => LucideIcons.store,
      };
}
