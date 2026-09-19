// The Заявки tab, at the two things that are actually load-bearing about it.
//
// **The role routing**, because one nav item hides three screens: a role that resolves to the wrong
// one is not an error anywhere, it is a worker looking at a client's empty list and concluding the
// marketplace is dead.
//
// **The round trip between two roles**, because that is the whole claim the feature makes. A ticket
// posted on the client's screen has to arrive on the worker's, and an offer made on the worker's has
// to raise the count the client reads. Those two lists are separate objects in the controller, so
// they can drift apart silently - and a demo where the job you just posted is nowhere to be found is
// worse than no demo.
//
// The third case is the privacy one the support thread already has a test for: what a session leaves
// behind on a shared phone. A ticket carries its writer's district and their budget.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/role_option_tile.dart';
import 'package:frontend/core/widgets/segmented_tabs.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';
import 'package:frontend/features/tickets/data/demo_job_market.dart';
import 'package:frontend/features/tickets/data/job_category.dart';
import 'package:frontend/features/tickets/data/job_role.dart';
import 'package:frontend/features/tickets/presentation/controllers/tickets_controller.dart';
import 'package:frontend/features/tickets/presentation/screens/tickets_screen.dart';
import 'package:frontend/features/tickets/presentation/widgets/ticket_card.dart';
import 'package:frontend/features/tickets/presentation/widgets/worker_card.dart';
import 'package:frontend/features/profile/presentation/screens/profile_screen.dart';

final _strings = AppLocalizations(AppLanguage.ru);

/// Rendered at a real phone's width, not the 800px test default.
///
/// Every card in this feature is a row of chips, a price and a button competing for the same line,
/// and 800px hides exactly the overflow that a 360px phone would show. `flutter_test` turns a
/// RenderFlex overflow into a failure, so pinning the width here is what makes these tests a layout
/// guard as well as a routing one.
///
/// It is a *conservative* guard: `flutter_test` measures every glyph as a square em box, so text
/// here is roughly twice as wide as the real Cyrillic it stands for. A layout that survives this
/// survives a real phone with room to spare - which is the right way round, but it means a failure
/// is a reason to make the row flexible rather than proof that a user would have seen the stripes.
Future<TicketsController> _pump(WidgetTester tester, {JobRole? role}) async {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final tickets = TicketsController();
  if (role != null) tickets.setRole(role);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        // the screen watches it for the name that goes on the анкета; the guest state is enough
        ChangeNotifierProvider.value(value: AuthController()),
        ChangeNotifierProvider.value(value: tickets),
      ],
      child: const MaterialApp(home: TicketsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return tickets;
}

void main() {
  testWidgets('with no role chosen the tab asks rather than guessing', (tester) async {
    await _pump(tester);

    // the header asks it - the chooser itself is three tiles and nothing else
    expect(find.text(_strings.ticketsTab), findsOneWidget);
    expect(find.text(_strings.rolePromptSubtitle), findsOneWidget);
    // all three sides on offer - a two-sided market that only offers one side of itself is the bug
    expect(find.byType(RoleOptionTile), findsNWidgets(3));
    expect(find.text(_strings.roleWorker), findsOneWidget);
  });

  testWidgets('picking a role from the chooser opens that role\'s screen', (tester) async {
    final tickets = await _pump(tester);

    await tester.tap(find.text(_strings.roleWorker));
    await tester.pumpAndSettle();

    expect(tickets.role, JobRole.worker);
    expect(find.text(_strings.tabJobFeed), findsOneWidget);
    expect(find.text(_strings.tabMyProfile), findsOneWidget);
    // a worker's feed is other people's jobs, and it is not empty on a fresh install
    expect(find.byType(TicketCard), findsWidgets);
  });

  testWidgets('a client gets their own list and the workers, not the job feed', (tester) async {
    await _pump(tester, role: JobRole.client);

    expect(find.text(_strings.createTicketAction), findsOneWidget);
    expect(find.text(_strings.tabJobFeed), findsNothing);

    await tester.tap(find.text(_strings.tabWorkers));
    await tester.pumpAndSettle();

    expect(find.byType(WorkerCard), findsWidgets);
  });

  testWidgets('a shop owner sees only the jobs that still need materials', (tester) async {
    final tickets = await _pump(tester, role: JobRole.shopOwner);

    // the filter is the whole reason this role has a screen of its own
    expect(tickets.materialTickets.length, lessThan(tickets.openTickets.length));
    expect(
      tickets.materialTickets.every((ticket) => ticket.needsMaterials),
      isTrue,
    );
    expect(find.text(_strings.offerMaterialsAction), findsWidgets);
  });


  // Every tab of every role, rendered at phone width. Nothing is asserted beyond "it drew" - the
  // assertion is `flutter_test` itself, which fails the test on a RenderFlex overflow, and a card
  // that overflows is the one defect a screenshot demo cannot survive.
  testWidgets('every role\'s two tabs render at phone width', (tester) async {
    for (final role in JobRole.values) {
      final tickets = await _pump(tester, role: role);
      expect(tickets.role, role);

      expect(find.byType(SegmentedTabs), findsOneWidget);

      // the second segment, whatever it is called for this role
      final second = switch (role) {
        JobRole.client => _strings.tabWorkers,
        JobRole.worker => _strings.tabMyProfile,
        JobRole.shopOwner => _strings.tabMyOffers,
      };
      await tester.tap(find.text(second));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  // ─────────────────────────── where the role is actually chosen ───────────────────────────
  //
  // Registration is the other end of the same decision, and it is the one that grew: two role
  // squares became three stacked rows. It used to be a bottom sheet - a min-height Column that does
  // not scroll unless told to - and the failure mode was a striped overflow bar under the name field
  // on any ordinary phone with the keyboard up. It is now step three of OnboardingFlow, on a
  // ListView, and this test is what keeps it scrollable.
  testWidgets('onboarding offers all three roles with the keyboard up', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ChangeNotifierProvider.value(value: AuthController()),
          ChangeNotifierProvider.value(value: TicketsController()),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // step 1, language - two options, and «Далее» moves on
    expect(find.text(AppLanguage.ru.displayName), findsOneWidget);
    await tester.tap(find.text(_strings.nextButton));
    await tester.pumpAndSettle();

    // step 2, the policy: a summary, a way in to the full text, and the tick
    expect(find.text(_strings.onboardingPolicyTitle), findsOneWidget);
    expect(find.text(_strings.policyReadFull), findsOneWidget);
    await tester.tap(find.text(_strings.policyAcceptLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_strings.nextButton));
    await tester.pumpAndSettle();

    // step 3, the roles themselves
    expect(find.byType(RoleOptionTile), findsNWidgets(3));
    expect(find.text(_strings.roleWorker), findsOneWidget);
    expect(find.text(_strings.roleVendor), findsOneWidget);

    // the keyboard the name field brings up, which is what used to turn this into an overflow
    tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('a posted ticket reaches the worker feed as well as the client\'s own list', () {
    final tickets = TicketsController();
    final feedBefore = tickets.openTickets.length;
    final mineBefore = tickets.myTickets.length;

    tickets.addTicket(
      title: 'Покрасить потолок',
      description: 'Комната 18 м²',
      category: JobCategory.finishing,
      budgetFrom: 1500000,
      district: 'Чиланзар',
    );

    expect(tickets.myTickets.length, mineBefore + 1);
    expect(tickets.openTickets.length, feedBefore + 1);
    // newest first in both, so it is the row a demo lands on rather than one to scroll for
    expect(tickets.myTickets.first.title.ru, 'Покрасить потолок');
    expect(tickets.openTickets.first.title.ru, 'Покрасить потолок');
    // it needs materials, which is what also puts it in front of the shop owner
    expect(tickets.materialTickets.first.title.ru, 'Покрасить потолок');
  });

  test('an offer raises the count the client reads, and only once', () {
    final tickets = TicketsController();
    final id = tickets.myTickets.first.id;
    final before = tickets.myTickets.first.responses;

    tickets.respondTo(id);
    expect(tickets.hasResponded(id), isTrue);
    expect(tickets.myTickets.first.responses, before + 1);

    // pressing an already-answered card must not stack offers
    tickets.respondTo(id);
    expect(tickets.myTickets.first.responses, before + 1);
  });

  test('the end of a session takes the role and anything written during it', () {
    final tickets = TicketsController();
    tickets.setRole(JobRole.worker);
    tickets.addTicket(
      title: 'Заявка ушедшего пользователя',
      description: 'С адресом и бюджетом',
      category: JobCategory.plumbing,
      budgetFrom: 900000,
      district: 'Мирабад',
    );
    tickets.respondTo(tickets.openTickets.first.id);
    tickets.saveProfile(
      skills: const [JobCategory.electric],
      experienceYears: 20,
      priceFrom: 999000,
      about: 'Личный текст',
      availableNow: false,
    );

    tickets.handleSessionEnded();

    expect(tickets.role, isNull);
    expect(tickets.myTickets.length, DemoJobMarket.myTickets.length);
    expect(
      tickets.openTickets.any((t) => t.title.ru == 'Заявка ушедшего пользователя'),
      isFalse,
    );
    expect(tickets.hasResponded(DemoJobMarket.openTickets.first.id), isFalse);
    expect(tickets.myProfile.about.ru, DemoJobMarket.draftProfile.about.ru);
  });
}
