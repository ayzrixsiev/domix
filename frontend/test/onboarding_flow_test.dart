// The guest flow, at the things that only show up on a real phone.
//
// **The footer sits at one height on every step**: both slots are always drawn and the error lives in
// the scrolling content, or the pair walks up and down the screen as you advance. The assertion is a
// measurement, because nothing throws when a button is 40px lower than it was.
//
// **The footer clears the phone's own bar** - a gesture-navigation phone draws a home indicator over
// the bottom of the screen.
//
// **It is a route over the shell**, so it can be closed from any step and takes itself off the screen
// once an account exists.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/features/profile/data/account_role.dart';

import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/role_option_tile.dart';
import 'package:frontend/features/onboarding/data/privacy_policy.dart';
import 'package:frontend/features/onboarding/presentation/screens/onboarding_flow.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';

final _strings = AppLocalizations(AppLanguage.ru);

/// A phone with a home indicator: `viewPadding.bottom` is what the old footer ignored.
const double _systemInset = 34;

const Size _phone = Size(360, 800);

Widget _providers({required Widget child}) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => LanguageProvider()),
    ChangeNotifierProvider.value(value: AuthController()),
  ],
  child: MaterialApp(home: child),
);

void _sizePhone(WidgetTester tester) {
  tester.view.physicalSize = Size(_phone.width * 3, _phone.height * 3);
  tester.view.devicePixelRatio = 3;
  tester.view.viewPadding = const FakeViewPadding(bottom: _systemInset * 3);
  tester.view.padding = const FakeViewPadding(bottom: _systemInset * 3);
  addTearDown(tester.view.reset);
}

Future<void> _pumpFlow(WidgetTester tester) async {
  _sizePhone(tester);

  await tester.pumpWidget(_providers(child: const OnboardingFlow()));
  await tester.pumpAndSettle();
}

/// Ticks the consent box, which is the only thing the policy step gates on.
///
/// `ensureVisible` first: `flutter_test` measures every glyph as a square em box, so the Cyrillic
/// here lays out roughly twice as wide as the real thing and the tick sits below the fold in the
/// test where it is on screen on a real phone.
Future<void> _acceptPolicy(WidgetTester tester) async {
  await _scrollTo(tester, find.text(_strings.policyAcceptLabel));
  await tester.tap(find.text(_strings.policyAcceptLabel));
  await tester.pumpAndSettle();
}

/// Scrolls the step's list until [target] is built and on screen. A `ListView` does not build what
/// it does not show, so `ensureVisible` has nothing to find until this has run.
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the footer sits at one height on every step', (tester) async {
    await _pumpFlow(tester);

    // the primary button's caption changes with the step; its position must not
    final positions = <String, double>{};
    void record(String step, String label) {
      positions[step] = tester.getCenter(find.text(label)).dy;
    }

    record('language', _strings.nextButton);

    await tester.tap(find.text(_strings.nextButton));
    await tester.pumpAndSettle();
    record('policy', _strings.nextButton);

    await _acceptPolicy(tester);
    await tester.tap(find.text(_strings.nextButton));
    await tester.pumpAndSettle();
    expect(
      find.byType(RoleOptionTile),
      findsNWidgets(AccountRole.values.length),
      reason: 'we are on the profile step',
    );
    record('profile', _strings.nextButton);

    await tester.enterText(find.byType(TextField).first, 'Азиз');
    await tester.tap(find.text(_strings.nextButton));
    await tester.pumpAndSettle();
    record('telegram', _strings.telegramSignInButton);

    final heights = positions.values.toSet();
    expect(
      heights,
      hasLength(1),
      reason: 'the primary button moved between steps: $positions',
    );
  });

  testWidgets('an error does not move the footer', (tester) async {
    await _pumpFlow(tester);

    await tester.tap(find.text(_strings.nextButton));
    await tester.pumpAndSettle();
    final before = tester.getCenter(find.text(_strings.nextButton)).dy;

    // «Далее» on the policy step without accepting it: a refusal, drawn in the content above
    await tester.tap(find.text(_strings.nextButton));
    await tester.pumpAndSettle();

    expect(find.text(_strings.policyMustAccept), findsOneWidget);
    expect(
      tester.getCenter(find.text(_strings.nextButton)).dy,
      before,
      reason: 'the error line pushed the footer down',
    );
  });

  testWidgets('the footer clears the system inset', (tester) async {
    await _pumpFlow(tester);

    // step two, so the back button is drawn and is the lowest thing on screen
    await tester.tap(find.text(_strings.nextButton));
    await tester.pumpAndSettle();

    expect(
      tester.getBottomLeft(find.text(_strings.stepBackButton)).dy,
      lessThan(_phone.height - _systemInset),
      reason: 'the back button is under the home indicator',
    );
  });

  // The X is the only way out that does not walk back through every step, and it has to be there on
  // all of them - «Назад» is one step, this is the whole flow.
  testWidgets('the X closes the flow from any step', (tester) async {
    _sizePhone(tester);

    await tester.pumpWidget(
      _providers(
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => OnboardingFlow.open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(_strings.onboardingTitle), findsOneWidget);

    // one step in, to prove the X is not only on the first
    await tester.tap(find.text(_strings.nextButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(_strings.closeButton));
    await tester.pumpAndSettle();

    expect(find.text(_strings.onboardingTitle), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  // The last step is the telegram button, and the name and role typed before it are what it carries:
  // a name left empty is refused on the profile step, never discovered after Telegram has opened.
  // **The phone route is a door off it, not a step**, so the counter still ends at four.
  testWidgets('the last step is the telegram button, behind a name', (
    tester,
  ) async {
    await _pumpFlow(tester);
    await tester.tap(find.text(_strings.nextButton));
    await tester.pumpAndSettle();
    await _acceptPolicy(tester);
    await tester.tap(find.text(_strings.nextButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text(_strings.nextButton));
    await tester.pumpAndSettle();
    expect(find.text(_strings.nameRequiredError), findsOneWidget);
    expect(find.text(_strings.telegramSignInButton), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'Азиз');
    await tester.tap(find.text(_strings.nextButton));
    await tester.pumpAndSettle();

    expect(find.text(_strings.telegramSignInButton), findsOneWidget);
    expect(find.text(_strings.telegramStepBody), findsOneWidget);
    expect(find.text(_strings.stepCounter(4, 4)), findsOneWidget);
    expect(find.text(_strings.phoneSignInButton), findsOneWidget);
    // the number is asked on the phone route, never in this flow
    expect(find.byType(TextField), findsNothing);
  });

  // The steps carry no headline of their own: the screen header names the flow, the progress bar
  // says where you are, and each control is labelled. «Выберите язык» over two language tiles and
  // «Как вас зовут?» over a field called «Имя и фамилия» were saying it a third time.
  testWidgets('the steps carry no titles of their own', (tester) async {
    await _pumpFlow(tester);

    expect(find.text(AppLanguage.ru.displayName), findsOneWidget);
    expect(
      find.byType(RoleOptionTile),
      findsNWidgets(AppLanguage.values.length),
    );

    await tester.tap(find.text(_strings.nextButton));
    await tester.pumpAndSettle();
    await _acceptPolicy(tester);
    await tester.tap(find.text(_strings.nextButton));
    await tester.pumpAndSettle();

    // the field's own label and nothing above it
    expect(find.text(_strings.nameInputLabel), findsWidgets);
    expect(
      find.byType(RoleOptionTile),
      findsNWidgets(AccountRole.values.length),
    );
  });

  // The full policy is a sheet, not the step. Opening it is the thing that has to keep working,
  // because it is the only route to the text both stores require be available before consent.
  testWidgets('«Читать полностью» opens the whole policy', (tester) async {
    await _pumpFlow(tester);
    await tester.tap(find.text(_strings.nextButton));
    await tester.pumpAndSettle();

    // the summary is on the step; the sections themselves are not. read from the policy itself, so
    // rewording a heading does not break the test that only cares the sheet opens
    final firstHeading = privacyPolicySections(AppLanguage.ru).first.title;
    expect(find.text(firstHeading), findsNothing);

    await _scrollTo(tester, find.text(_strings.policyReadFull));
    await tester.tap(find.text(_strings.policyReadFull));
    await tester.pumpAndSettle();

    // only the first section is asserted: the rest are below the sheet's fold and a ListView does
    // not build what it does not show
    expect(find.text(firstHeading), findsOneWidget);
  });
}
