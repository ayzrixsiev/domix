// The support chat, at the two places it can go wrong on its own.
//
// The controller, because everything the screen shows is a state it decides: whether a failure is
// the load's or the send's, whether the composer keeps its text, and - the one that is a privacy
// bug rather than a stale-data bug - whether a conversation survives a logout into the next
// person's session on the same phone.
//
// The bubble, because *side* is what says who wrote a message. It is the one piece of this feature
// that could invert without an error anywhere: the thread would still render, still scroll, still
// be the right words, and every answer would look like it came from the user.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/widgets/circle_back_button.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/screen_header.dart';
import 'package:frontend/features/messages/data/support_message.dart';
import 'package:frontend/features/messages/data/support_repository.dart';
import 'package:frontend/features/messages/presentation/controllers/support_controller.dart';
import 'package:frontend/features/messages/presentation/screens/chats_screen.dart';
import 'package:frontend/features/messages/presentation/screens/messages_screen.dart';
import 'package:frontend/features/messages/presentation/widgets/message_bubble.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';

/// Stands in for the network. `implements` rather than a subclass, so the fake cannot accidentally
/// inherit a real http call the day one is added to the repository.
class _FakeSupportRepository implements SupportRepository {
  _FakeSupportRepository({this.thread = const [], this.loadError, this.sendError});

  List<SupportMessage> thread;
  Object? loadError;
  Object? sendError;

  int loads = 0;
  final List<String> sent = [];

  /// The read watermark, in memory instead of the keystore - there is no secure storage in a widget
  /// test, and what these check is what the controller *does* with the number.
  int watermark = 0;

  @override
  Future<int> readWatermark() async => watermark;

  @override
  Future<void> writeWatermark(int messageId) async => watermark = messageId;

  @override
  Future<void> clearWatermark() async => watermark = 0;

  @override
  Future<List<SupportMessage>> fetchMessages() async {
    loads++;
    if (loadError != null) throw loadError!;
    return thread;
  }

  @override
  Future<SupportMessage> sendMessage(String body) async {
    if (sendError != null) throw sendError!;
    sent.add(body);
    final message = _message(id: 100 + sent.length, fromSupport: false, body: body);
    thread = [...thread, message];
    return message;
  }
}

SupportMessage _message({
  required int id,
  required bool fromSupport,
  String body = 'текст',
  DateTime? at,
}) {
  return SupportMessage(
    id: id,
    fromSupport: fromSupport,
    body: body,
    sentAt: at ?? DateTime(2026, 8, 19, 14, 20),
  );
}

/// Hydrates the real [AuthController] out of a faked secure storage, which is the only public
/// way into a signed-in state - the profile state has no setter on purpose.
Future<void> signIn({required bool signedIn}) async {
  // a token whose `exp` is in the future. AuthController reads that claim itself, offline, so a
  // hand-built one is exactly as good as a real one for this.
  String jwt() {
    String chunk(Map<String, dynamic> m) =>
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    final exp = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
    return '${chunk({'alg': 'HS256'})}.${chunk({'exp': exp})}.signature';
  }

  final store = signedIn
      ? {
          'domix_jwt_token': jwt(),
          'domix_user_role': 'shop_owner',
          'domix_user_name': 'Азиз',
          'domix_user_phone': '+998900000000',
        }
      : <String, String>{};

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      switch (call.method) {
        case 'read':
          return store[(call.arguments as Map)['key']];
        case 'readAll':
          return store;
        default:
          return null;
      }
    },
  );

  // AuthController is a process-wide singleton, so a signed-in state set by one test would
  // otherwise leak into the next and make these pass or fail on declaration order
  await AuthController().logout();
  await AuthController().checkExistingLogin();
}

void main() {
  group('SupportController', () {
    test('loads the thread once and leaves a fresh one alone', () async {
      final repo = _FakeSupportRepository(thread: [_message(id: 1, fromSupport: false)]);
      final controller = SupportController(repository: repo);

      await controller.load();
      expect(controller.messages, hasLength(1));
      expect(controller.hasLoaded, isTrue);

      // a second visit to the tab inside the freshness window must not cost a request
      await controller.refreshIfStale();
      expect(repo.loads, 1);

      // ...but an explicit refresh always does
      await controller.load(force: true);
      expect(repo.loads, 2);
    });

    test('a failed load is retried the next time the tab is opened', () async {
      final repo = _FakeSupportRepository(
        loadError: const SupportException(code: 'server_error', message: 'boom'),
      );
      final controller = SupportController(repository: repo);

      await controller.load();
      expect(controller.loadErrorCode, 'server_error');
      expect(controller.hasLoaded, isFalse);

      // the map screen's bug, avoided here: an error left in place with nothing to clear it means a
      // dead screen that even restarting the app cannot fix
      repo.loadError = null;
      repo.thread = [_message(id: 1, fromSupport: true)];
      await controller.refreshIfStale();

      expect(repo.loads, 2);
      expect(controller.loadErrorCode, isNull);
      expect(controller.messages, hasLength(1));
    });

    test('a sent message is appended as the server returned it', () async {
      final repo = _FakeSupportRepository();
      final controller = SupportController(repository: repo);
      await controller.load();

      expect(await controller.send('  как добавить магазин?  '), isTrue);

      // trimmed before it is sent - a message of three spaces is not a message
      expect(repo.sent.single, 'как добавить магазин?');
      expect(controller.messages.single.body, 'как добавить магазин?');
      expect(controller.messages.single.fromSupport, isFalse);
      expect(controller.sendErrorCode, isNull);
    });

    test('a failed send reports its code and adds nothing to the thread', () async {
      final repo = _FakeSupportRepository(
        sendError: const SupportException(code: 'too_many_messages', message: 'slow down'),
      );
      final controller = SupportController(repository: repo);
      await controller.load();

      expect(await controller.send('ещё одно'), isFalse);
      expect(controller.sendErrorCode, 'too_many_messages');
      // nothing optimistic: a bubble that appears and then is not there is worse than waiting
      expect(controller.messages, isEmpty);

      controller.clearSendError();
      expect(controller.sendErrorCode, isNull);
    });

    test('an empty composer sends nothing at all', () async {
      final repo = _FakeSupportRepository();
      final controller = SupportController(repository: repo);

      expect(await controller.send('   \n  '), isFalse);
      expect(repo.sent, isEmpty);
    });

    // **the privacy one.** a support thread is where somebody typed their phone number and their
    // problem; left in memory after a logout it is the next person to sign in on this phone who
    // reads it.
    test('the conversation is dropped when the session ends', () async {
      final repo = _FakeSupportRepository(
        thread: [_message(id: 1, fromSupport: false, body: 'мой номер +998 90 123 45 67')],
      );
      final controller = SupportController(repository: repo);
      await controller.load();
      expect(controller.messages, isNotEmpty);

      controller.handleSessionEnded();

      expect(controller.messages, isEmpty);
      expect(controller.hasLoaded, isFalse);
      expect(controller.loadErrorCode, isNull);

      // and the next account starts from the network, not from what is left in memory
      repo.thread = const [];
      await controller.refreshIfStale();
      expect(repo.loads, 2);
      expect(controller.messages, isEmpty);
    });
  });

  // ── the live thread ──
  //
  // **The bug these exist for: a reply was invisible until the app was restarted.** The tab only
  // re-fetched when it became visible again, so sitting on the conversation meant nothing ever asked
  // the server. What replaced that is an adaptive poll, and the two things that make it acceptable on
  // one small server are that it runs *only* while somebody is watching, and that it backs off when
  // nothing is happening. Both are properties nobody would notice breaking - the app would still
  // work, it would just quietly ask a hundred times an hour - so both are pinned here.
  //
  // `testWidgets` rather than `test` for the whole group: it runs inside a fake clock, so
  // `tester.pump(duration)` fires the timers without anything actually waiting.
  group('SupportController live poll', () {
    testWidgets('only runs while somebody is watching', (tester) async {
      final repo = _FakeSupportRepository(thread: [_message(id: 1, fromSupport: false)]);
      final controller = SupportController(repository: repo);

      // nobody watching yet: no amount of time costs a request
      await tester.pump(const Duration(minutes: 5));
      expect(repo.loads, 0);

      controller.setWatching(true);

      // the first poll is one interval away rather than immediate - the screen has just fetched
      // through refreshIfStale, and polling straight away would double every arrival
      await tester.pump(const Duration(seconds: 9));
      expect(repo.loads, 0);

      await tester.pump(const Duration(seconds: 2));
      expect(repo.loads, 1);

      // and it stops dead. this is the case that costs nothing while the app sits on another tab or
      // in a pocket, which is where it spends almost all of its life.
      controller.setWatching(false);
      await tester.pump(const Duration(minutes: 10));
      expect(repo.loads, 1, reason: 'a poll survived the screen it belongs to');
    });

    testWidgets('a reply appears without anything being reopened', (tester) async {
      final repo = _FakeSupportRepository(thread: [_message(id: 1, fromSupport: false)]);
      final controller = SupportController(repository: repo);
      await controller.load();

      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setWatching(true);

      // nothing new: the thread is left alone, and the screen is not told to rebuild for a list it
      // already has
      await tester.pump(const Duration(seconds: 11));
      expect(controller.messages, hasLength(1));
      expect(notifications, 0, reason: 'a poll that found nothing still rebuilt the conversation');

      // support answers
      repo.thread = [...repo.thread, _message(id: 2, fromSupport: true, body: 'уже смотрим')];
      await tester.pump(const Duration(seconds: 21)); // past the backed-off interval

      expect(controller.messages, hasLength(2));
      expect(controller.messages.last.body, 'уже смотрим');
      expect(notifications, 1);

      controller.setWatching(false);
    });

    testWidgets('backs off while nothing is happening, and speeds up again when it does', (
      tester,
    ) async {
      final repo = _FakeSupportRepository(thread: [_message(id: 1, fromSupport: false)]);
      final controller = SupportController(repository: repo);
      await controller.load();
      controller.setWatching(true);

      // every poll that finds nothing doubles the wait, so the polls land at 10s, 30s, 70s, 130s -
      // the last gap being 60 rather than 80, because the back-off is capped.
      //
      // written as "just before, then just after" pairs: asserting only the moment a poll lands
      // would pass just as happily against a poll that had run five times too often.
      var elapsed = Duration.zero;
      Future<void> pumpTo(int seconds) async {
        final target = Duration(seconds: seconds);
        await tester.pump(target - elapsed);
        elapsed = target;
      }

      await pumpTo(9);
      expect(repo.loads, 1);
      await pumpTo(11);
      expect(repo.loads, 2);

      await pumpTo(29);
      expect(repo.loads, 2, reason: 'the interval did not grow after an empty poll');
      await pumpTo(31);
      expect(repo.loads, 3);

      await pumpTo(69);
      expect(repo.loads, 3);
      await pumpTo(71);
      expect(repo.loads, 4);

      // the cap: 40 doubles to 80, which is held at 60 - so the next one lands at 130 and not 150
      await pumpTo(129);
      expect(repo.loads, 4);
      await pumpTo(131);
      expect(repo.loads, 5, reason: 'the back-off climbed past its ceiling');

      // something happening puts it back to attentive: a conversation is most likely to get an
      // answer right after a question
      await controller.send('ещё вопрос');
      final before = repo.loads;
      await tester.pump(const Duration(seconds: 11));
      expect(repo.loads, before + 1, reason: 'sending did not reset the back-off');

      controller.setWatching(false);
    });

    testWidgets('a failed poll leaves the conversation on screen alone', (tester) async {
      final repo = _FakeSupportRepository(
        thread: [_message(id: 1, fromSupport: true, body: 'ответ')],
      );
      final controller = SupportController(repository: repo);
      await controller.load();
      controller.setWatching(true);

      repo.loadError = const SupportException(code: 'server_error', message: 'boom');
      await tester.pump(const Duration(seconds: 11));

      // the thread the user can see is still the last known good one. turning a blip of no signal
      // into an error state would replace a readable conversation with a retry button.
      expect(controller.messages, hasLength(1));
      expect(controller.loadErrorCode, isNull);

      controller.setWatching(false);
    });

    testWidgets('the poll stops when the session ends', (tester) async {
      // it fetches *the caller's* thread, so one still armed after a logout would be a request for
      // whoever signs in on this phone next
      final repo = _FakeSupportRepository();
      final controller = SupportController(repository: repo);
      controller.setWatching(true);

      controller.handleSessionEnded();
      await tester.pump(const Duration(minutes: 5));

      expect(repo.loads, 0);
    });
  });

  group('MessageBubble', () {
    Future<Alignment> alignmentOf(WidgetTester tester, SupportMessage message) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(message: message, senderLabel: 'Поддержка Domix'),
          ),
        ),
      );
      final row = tester.widget<Row>(find.byType(Row).first);
      return row.mainAxisAlignment == MainAxisAlignment.end
          ? Alignment.centerRight
          : Alignment.centerLeft;
    }

    testWidgets('the user writes on the right, support on the left', (tester) async {
      expect(
        await alignmentOf(tester, _message(id: 1, fromSupport: false)),
        Alignment.centerRight,
        reason: 'the reader wrote this one, so it belongs on their side',
      );
      expect(await alignmentOf(tester, _message(id: 2, fromSupport: true)), Alignment.centerLeft);
    });

  });

  group('localization', () {
    // the codes the backend actually answers with. a code with no case of its own falls through to
    // the generic sentence, which is correct; what would not be is a case that forgot one of the
    // two languages and answers both from the same branch.
    //
    // uzbek is written in latin script here, so "does it contain english letters" cannot be the
    // check. what can be checked is that russian is cyrillic and that the two differ.
    test('every support failure the server can send is written in both languages', () {
      const codes = [
        'empty_message',
        'message_too_long',
        'too_many_messages',
        'timeout',
        'unauthorized',
        'server_error',
      ];

      final ru = AppLocalizations(AppLanguage.ru);
      final uz = AppLocalizations(AppLanguage.uz);

      for (final code in codes) {
        final russian = ru.supportSendErrorMessage(code);
        final uzbek = uz.supportSendErrorMessage(code);

        expect(russian, isNotEmpty, reason: '$code has no russian message');
        expect(
          RegExp(r'[А-Яа-яЁё]').hasMatch(russian),
          isTrue,
          reason: '$code has a russian message with no cyrillic in it',
        );
        expect(uzbek, isNotEmpty, reason: '$code has no uzbek message');
        expect(uzbek, isNot(russian), reason: '$code is the same string in both languages');
      }
    });
  });

  // ── the whole screen ──
  //
  // what these catch is a layout that cannot build at all: the composer is a TextField inside a Row
  // inside a Column inside an Expanded's sibling, and every one of those is a place an unbounded
  // constraint throws rather than looking wrong. that is not visible in a controller test and not
  // visible on a desktop run either, because the failure is in a state the desktop happens not to be
  // in.
  group('MessagesScreen', () {
    Future<void> pumpScreen(WidgetTester tester, SupportController controller) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
            ChangeNotifierProvider<AuthController>.value(value: AuthController()),
            ChangeNotifierProvider<SupportController>.value(value: controller),
          ],
          child: const MaterialApp(home: MessagesScreen()),
        ),
      );
      // the first load is kicked off from a post-frame callback, so one pump builds and the next
      // settles whatever it started
      await tester.pumpAndSettle();
    }

    testWidgets('a guest is told why they cannot write, and gets no composer', (tester) async {
      await signIn(signedIn: false);
      final repo = _FakeSupportRepository();

      await pumpScreen(tester, SupportController(repository: repo));

      final strings = AppLocalizations(AppLanguage.ru);
      expect(find.text(strings.supportGuestTitle), findsOneWidget);
      // a text field a guest can type into leads to a message with nowhere to send an answer
      expect(find.byType(TextField), findsNothing);
      // and nothing is fetched for somebody with no account
      expect(repo.loads, 0);
    });

    testWidgets('a signed-in user gets the thread and a working composer', (tester) async {
      await signIn(signedIn: true);
      final repo = _FakeSupportRepository(
        thread: [
          _message(id: 1, fromSupport: false, body: 'как поднять магазин в VIP?'),
          _message(id: 2, fromSupport: true, body: 'напишите, на какой срок'),
        ],
      );
      final controller = SupportController(repository: repo);

      await pumpScreen(tester, controller);

      expect(repo.loads, 1);
      expect(find.text('как поднять магазин в VIP?'), findsOneWidget);
      expect(find.text('напишите, на какой срок'), findsOneWidget);
      // both messages fell on the same day, so there is exactly one separator and not one per bubble
      expect(find.byType(MessageDaySeparator), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'на месяц');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(InkWell).last);
      await tester.pumpAndSettle();

      expect(repo.sent.single, 'на месяц');
      expect(find.text('на месяц'), findsOneWidget);
      // cleared on success, so the next message starts from an empty box
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });

    testWidgets('a failed send keeps the text and says what went wrong', (tester) async {
      await signIn(signedIn: true);
      final repo = _FakeSupportRepository(
        sendError: const SupportException(code: 'too_many_messages', message: 'slow down'),
      );
      final controller = SupportController(repository: repo);

      await pumpScreen(tester, controller);

      await tester.enterText(find.byType(TextField), 'ещё вопрос');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(InkWell).last);
      await tester.pumpAndSettle();

      final strings = AppLocalizations(AppLanguage.ru);
      expect(find.text(strings.supportSendErrorMessage('too_many_messages')), findsOneWidget);
      // nothing retyped: the words stay in the box
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'ещё вопрос');
    });

    // ── getting the keyboard back off the screen ──
    //
    // **There was no way to do it at all.** The conversation ignored taps, the list did not dismiss
    // on drag, and back went to a Navigator with nothing to pop, so the only escape from a focused
    // composer was force-closing the app. Three gestures are wired now; each is one line and each is
    // invisible when it breaks, which is exactly why they are tested rather than tried once by hand.

    /// The composer's focus node, read off the live widget rather than held by the test - what is
    /// being checked is the field a person is typing into.
    FocusNode composerFocus(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).focusNode!;

    Future<FocusNode> focusedComposer(WidgetTester tester) async {
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      final node = composerFocus(tester);
      expect(node.hasFocus, isTrue, reason: 'the composer never took focus, so nothing is proved');
      return node;
    }

    testWidgets('tapping the conversation puts the keyboard away', (tester) async {
      await signIn(signedIn: true);
      await pumpScreen(
        tester,
        SupportController(
          repository: _FakeSupportRepository(
            thread: [_message(id: 1, fromSupport: true, body: 'здравствуйте')],
          ),
        ),
      );

      final node = await focusedComposer(tester);

      await tester.tap(find.text('здравствуйте'));
      await tester.pumpAndSettle();

      expect(node.hasFocus, isFalse);
    });

    testWidgets('dragging the conversation puts the keyboard away', (tester) async {
      await signIn(signedIn: true);
      await pumpScreen(
        tester,
        SupportController(
          repository: _FakeSupportRepository(
            thread: [for (var i = 1; i <= 12; i++) _message(id: i, fromSupport: i.isEven)],
          ),
        ),
      );

      await focusedComposer(tester);

      // the drag half has to live on the scrollable itself - a ListView claims a vertical drag
      // before any ancestor gesture detector is offered it, so no wrapper could implement this
      expect(
        tester.widget<ListView>(find.byType(ListView)).keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );
    });

    testWidgets('the back gesture closes the keyboard instead of doing nothing', (tester) async {
      await signIn(signedIn: true);
      await pumpScreen(tester, SupportController(repository: _FakeSupportRepository()));

      final node = await focusedComposer(tester);

      // what Android sends when the back button is pressed. inside the shell this screen sits on the
      // *root* route, so there is nothing to pop - which is why the press used to do nothing at all
      // and why PopScope has to intercept it explicitly.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(node.hasFocus, isFalse);
    });

    testWidgets('leaving the tab takes the keyboard with it', (tester) async {
      await signIn(signedIn: true);
      final controller = SupportController(repository: _FakeSupportRepository());

      Future<void> pumpWithActive(bool isActive) => tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
            ChangeNotifierProvider<AuthController>.value(value: AuthController()),
            ChangeNotifierProvider<SupportController>.value(value: controller),
          ],
          child: MaterialApp(home: MessagesScreen(isActive: isActive)),
        ),
      );

      await pumpWithActive(true);
      await tester.pumpAndSettle();

      final node = await focusedComposer(tester);

      // the shell's IndexedStack keeps this State and its focus alive across a tab switch, so a
      // composer left focused kept the keyboard up over the map and the home feed - most of what
      // "the keyboard cannot be dismissed" actually was
      await pumpWithActive(false);
      await tester.pumpAndSettle();

      expect(node.hasFocus, isFalse);
    });

    testWidgets('an empty thread invites the first message instead of showing nothing', (
      tester,
    ) async {
      await signIn(signedIn: true);
      final controller = SupportController(repository: _FakeSupportRepository());

      await pumpScreen(tester, controller);

      final strings = AppLocalizations(AppLanguage.ru);
      expect(find.text(strings.supportEmptyTitle), findsOneWidget);
      // the composer is still there - an empty conversation is the one most in need of it
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  // The Сообщения tab is a *list* of conversations now, and today the list has one row. What can
  // break silently here is the row's own arithmetic - a preview that shows your own question back
  // to you, or a badge that never clears - and the hand-off to the chat, since the list and the
  // chat both drive the same poll and the pop is what used to leave the list frozen.
  group('ChatsScreen', () {
    Future<void> pumpList(WidgetTester tester, SupportController controller) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
            ChangeNotifierProvider<AuthController>.value(value: AuthController()),
            ChangeNotifierProvider<SupportController>.value(value: controller),
          ],
          child: const MaterialApp(home: ChatsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    // **The header is the only thing separating this tab from an empty white page.** It used to be
    // a bare heading over an `AppColors.hairline` rule - three units away from the page colour,
    // which is to say invisible - and now sits on the white surface with a trackGrey edge. The
    // guest state is the emptier of the two and is exactly where a missing header reads as an
    // unfinished screen, so that is the one pinned here; the signed-in case is asserted in the
    // list test below, which already owns the poll timer's teardown.
    testWidgets('a guest still gets the tab header', (tester) async {
      await signIn(signedIn: false);
      await pumpList(tester, SupportController(repository: _FakeSupportRepository()));

      final strings = AppLocalizations(AppLanguage.ru);
      expect(find.byType(ScreenHeader), findsOneWidget);
      expect(find.text(strings.chatsScreenTitle), findsOneWidget);
      expect(find.text(strings.chatsScreenSubtitle), findsOneWidget);
    });

    testWidgets('the tab is a list, and its row opens the conversation', (tester) async {
      await signIn(signedIn: true);
      final controller = SupportController(
        repository: _FakeSupportRepository(
          thread: [_message(id: 1, fromSupport: true, body: 'Здравствуйте!')],
        ),
      );

      await pumpList(tester, controller);

      final strings = AppLocalizations(AppLanguage.ru);
      // the header, signed in - the guest half of this is its own test above
      expect(find.byType(ScreenHeader), findsOneWidget);
      expect(find.text(strings.chatsScreenTitle), findsOneWidget);
      // the list, not the chat: a row previewing the thread and no composer anywhere
      expect(find.byType(ChatListRow), findsOneWidget);
      expect(find.text(strings.supportSenderLabel), findsOneWidget);
      expect(find.text('Здравствуйте!'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.byType(ChatListRow));
      await tester.pumpAndSettle();

      expect(find.byType(MessagesScreen), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a reply nobody has opened is counted, and opening it clears the count',
        (tester) async {
      await signIn(signedIn: true);
      final repo = _FakeSupportRepository(thread: [
        _message(id: 7, fromSupport: false, body: 'Когда ответите?'),
        _message(id: 8, fromSupport: true, body: 'Уже смотрим'),
      ]);
      final controller = SupportController(repository: repo);

      await pumpList(tester, controller);

      // nothing has ever been read on this install, so the watermark is 0 and the reply is new
      expect(controller.unreadCount, 1);
      expect(find.text('1'), findsOneWidget);

      await tester.tap(find.byType(ChatListRow));
      await tester.pumpAndSettle();
      // and back out of the chat, which is where the second markThreadRead lands. tapping the
      // button rather than pageBack() also pins that a pushed conversation has a visible way back
      // at all - inside the shell it had none, and did not need one.
      await tester.tap(find.byType(CircleBackButton));
      await tester.pumpAndSettle();

      expect(controller.unreadCount, 0);
      // the watermark is the newest id, not a flag - a message arriving next is unread by
      // arithmetic rather than because something remembered to set a bit
      expect(repo.watermark, 8);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('the preview says who wrote the last line', (tester) async {
      await signIn(signedIn: true);
      final controller = SupportController(
        repository: _FakeSupportRepository(
          thread: [_message(id: 3, fromSupport: false, body: 'Мой вопрос')],
        ),
      );

      await pumpList(tester, controller);

      final strings = AppLocalizations(AppLanguage.ru);
      // without the prefix a row shows your own question back to you as though it had been answered
      expect(find.text('${strings.chatPreviewYou}Мой вопрос'), findsOneWidget);
      // and the reader's own message is not news to them, so no badge
      expect(controller.unreadCount, 0);
    });
  });
}
