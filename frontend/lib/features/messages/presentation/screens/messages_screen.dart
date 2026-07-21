import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/language_provider.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key, this.showScaffold = true, this.bottomPadding = 36});

  final bool showScaffold;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    final body = SafeArea(
      bottom: false,
      child: Container(
        color: AppColors.background,
        padding: EdgeInsets.fromLTRB(16, 24, 16, bottomPadding),
        child: Center(
          child: Text(
            strings.messagesComingSoon,
            style: const TextStyle(fontSize: 16, color: AppColors.textGrey),
          ),
        ),
      ),
    );

    if (!showScaffold) {
      return body;
    }

    return Scaffold(backgroundColor: AppColors.background, body: body);
  }
}
