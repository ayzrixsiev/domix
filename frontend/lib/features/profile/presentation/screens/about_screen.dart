import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:frontend/core/constants/api_config.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/app_page_header.dart';

/// «О приложении». **It exists for two licences, not for decoration**: Yandex's free MapKit terms
/// ask for a link to them in an app's «About» section, and the address search is OpenStreetMap data,
/// whose licence asks for the credit. A rejected MapKit licence switches the map off for everybody.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  // the address Yandex's free-use terms name for this link
  static final Uri yandexMapsTerms = Uri.parse(
    'https://yandex.ru/legal/maps_api/',
  );
  static final Uri openStreetMapCopyright = Uri.parse(
    'https://www.openstreetmap.org/copyright',
  );

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppPageHeader(title: strings.aboutApp),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: AppShadows.card,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _LinkRow(
                    icon: LucideIcons.map,
                    title: strings.yandexMapsTerms,
                    uri: yandexMapsTerms,
                  ),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.hairline,
                  ),
                  _LinkRow(
                    icon: LucideIcons.map_pin,
                    title: strings.openStreetMapCredit,
                    uri: openStreetMapCopyright,
                  ),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.hairline,
                  ),
                  // the site's home page, not one document: it links the terms and the policy
                  _LinkRow(
                    icon: LucideIcons.file_text,
                    title: strings.termsAndPrivacy,
                    uri: Uri.parse('${ApiConfig.serverRoot}/'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.title, required this.uri});

  final IconData icon;
  final String title;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        // the browser, not an in-app view: both pages are legal text the reader may want to keep open
        onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
        // one fixed minimum so the rows match whether the title takes one line or two
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: AppColors.textMuted, size: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 14.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(
                  CupertinoIcons.arrow_up_right,
                  color: AppColors.textFaint,
                  size: 15,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
