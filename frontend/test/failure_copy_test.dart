import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/network/api_client.dart';

// **"Проверьте подключение" is only true when no answer came back.** under a 500 or a 429 it sends
// somebody off to fix a phone that works, and the sentences live far from the screens that pick them.
void main() {
  const connection = ['подключ', 'ulanish'];

  for (final language in AppLanguage.values) {
    test(
      'a server that answered is never blamed on the connection (${language.name})',
      () {
        final strings = AppLocalizations(language);
        final answered = [
          for (final failure in [LoadFailure.busy, LoadFailure.server]) ...[
            strings.loadErrorHintFor(failure),
            strings.mapLoadErrorFor(failure),
            strings.storeCreationFailedFor(failure),
          ],
          strings.waybillSendError('rate_limited'),
          strings.waybillSendError('server_error'),
        ];

        for (final sentence in answered) {
          for (final word in connection) {
            expect(
              sentence.toLowerCase(),
              isNot(contains(word)),
              reason: sentence,
            );
          }
        }
      },
    );

    test('no answer at all does say so (${language.name})', () {
      final strings = AppLocalizations(language);
      for (final sentence in [
        strings.loadErrorHintFor(LoadFailure.network),
        strings.mapLoadErrorFor(LoadFailure.network),
        strings.storeCreationFailedFor(LoadFailure.network),
        strings.waybillSendError('network'),
      ]) {
        expect(
          connection.any(sentence.toLowerCase().contains),
          isTrue,
          reason: sentence,
        );
      }
    });
  }
}
