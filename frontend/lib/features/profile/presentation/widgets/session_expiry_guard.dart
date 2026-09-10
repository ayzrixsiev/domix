import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';

// tells the user why they were signed out, then takes them off whatever a session had opened.
// it wraps the shell rather than living on a screen because a 401 can land while the user is deep in
// a pushed route, and only a widget on the first route can pop back to something a guest may see.
class SessionExpiryGuard extends StatefulWidget {
  const SessionExpiryGuard({super.key, required this.child});

  final Widget child;

  @override
  State<SessionExpiryGuard> createState() => _SessionExpiryGuardState();
}

class _SessionExpiryGuardState extends State<SessionExpiryGuard> {
  late final AuthController _auth;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthController>()..addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!_auth.sessionExpiredUnseen || _showing) return;
    _showing = true;
    // the notification can arrive mid-build, and a route cannot be pushed during one
    WidgetsBinding.instance.addPostFrameCallback((_) => _announce());
  }

  Future<void> _announce() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SessionExpiredDialog(
        strings: context.read<LanguageProvider>().strings,
      ),
    );
    if (!mounted) return;

    _showing = false;
    _auth.acknowledgeSessionExpiry();
    // everything stacked above the shell was opened by a session that no longer exists
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SessionExpiredDialog extends StatelessWidget {
  const _SessionExpiredDialog({required this.strings});

  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.warningSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.lock_shield,
                color: AppColors.warning,
                size: 22,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              strings.sessionExpiredTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 17,
                height: 1.3,
                letterSpacing: -0.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              strings.sessionExpiredBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: Material(
                color: AppColors.primaryOrange,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: () => Navigator.of(context).pop(),
                  child: SizedBox(
                    height: 48,
                    child: Center(
                      child: Text(
                        strings.okButton,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
