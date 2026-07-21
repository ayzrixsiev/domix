import 'package:flutter/material.dart';
import 'app_localizations.dart';

class LanguageProvider extends ChangeNotifier {
  LanguageProvider({AppLanguage initialLanguage = AppLanguage.ru})
      : _language = initialLanguage;

  AppLanguage _language;

  AppLanguage get language => _language;
  Locale get locale => Locale(_language.code);
  AppLocalizations get strings => AppLocalizations(_language);

  void updateLanguage(AppLanguage newLanguage) {
    if (newLanguage == _language) return;
    _language = newLanguage;
    notifyListeners();
  }
}
