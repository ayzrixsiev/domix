import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key, this.showScaffold = true, this.bottomPadding = 36});

  final bool showScaffold;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      bottom: false,
      child: Container(
        color: AppColors.background,
        padding: EdgeInsets.fromLTRB(16, 24, 16, bottomPadding),
        child: const Center(
          child: Text(
            'Map screen coming soon',
            style: TextStyle(fontSize: 16, color: AppColors.textGrey),
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
