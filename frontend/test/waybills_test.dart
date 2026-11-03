import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/waybills/data/waybill.dart';
import 'package:frontend/features/waybills/data/waybills_repository.dart';
import 'package:frontend/features/waybills/presentation/controllers/waybills_controller.dart';
import 'package:frontend/features/waybills/presentation/screens/new_waybill_flow.dart';

/// Records what the flow sent, and refuses for as long as [refusal] is set.
class _RecordingRepository extends WaybillsRepository {
  final List<String> requestIds = [];
  List<WaybillItem> lastItems = const [];
  String? refusal = 'network';

  @override
  Future<Waybill> sendList({
    required String requestId,
    required ShopCategory category,
    required List<WaybillItem> items,
  }) async {
    requestIds.add(requestId);
    lastItems = items;
    if (refusal case final code?) throw WaybillSendException(code);
    return Waybill(
      id: 1042,
      category: category,
      items: items,
      hasPhoto: false,
      createdAt: DateTime(2026, 11, 2),
    );
  }
}

// the real controller hydrated out of a faked secure store: the profile state has no setter
Future<void> _signInAs(String role) async {
  String chunk(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp =
      DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/
      1000;
  final store = {
    'domix_jwt_token':
        '${chunk({'alg': 'HS256'})}.${chunk({'exp': exp})}.signature',
    'domix_user_role': role,
    'domix_user_name': 'Азиз Рихсиев',
    'domix_user_phone': '998901234567',
  };

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => switch (call.method) {
          'read' => store[(call.arguments as Map)['key']],
          'readAll' => store,
          _ => null,
        },
      );

  await AuthController().logout();
  await AuthController().checkExistingLogin();
}

Future<void> _pumpFlow(
  WidgetTester tester, {
  WaybillsRepository? repository,
  double width = 360,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 780));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider.value(value: AuthController()),
        ChangeNotifierProvider(
          create: (_) => WaybillsController(repository: repository),
        ),
      ],
      child: const MaterialApp(home: NewWaybillFlow()),
    ),
  );
  await tester.pump();
}

Future<void> _chooseFirstCategory(
  WidgetTester tester,
  AppLocalizations strings,
) async {
  await tester.tap(find.text(ShopCategory.plumbing.label(strings)));
  await tester.pumpAndSettle();
}

void main() {
  final strings = AppLocalizations(AppLanguage.ru);

  test('a list comes back from the server rows and all', () {
    final waybill = Waybill.fromJson({
      'id': 1042,
      'shop_category': 'plumbing',
      'items': [
        {'name': 'Цемент', 'quantity': '10 мешков'},
      ],
      'has_photo': false,
      'created_at': '2026-11-02T09:30:00Z',
    });

    expect(waybill.id, 1042);
    expect(waybill.category, ShopCategory.plumbing);
    expect(waybill.items.single.quantity, '10 мешков');
    expect(waybill.hasPhoto, isFalse);
  });

  test('a photo list decodes with no rows', () {
    final waybill = Waybill.fromJson({
      'id': 7,
      'shop_category': 'wood',
      'items': const [],
      'has_photo': true,
      'created_at': '2026-11-02T09:30:00Z',
    });
    expect(waybill.items, isEmpty);
    expect(waybill.hasPhoto, isTrue);
  });

  test('russian row counts agree with their number', () {
    expect(strings.waybillRowCount(1), '1 строка');
    expect(strings.waybillRowCount(3), '3 строки');
    expect(strings.waybillRowCount(5), '5 строк');
    expect(strings.waybillRowCount(11), '11 строк');
    expect(strings.waybillRowCount(21), '21 строка');
  });

  test('a retried send replaces its row instead of listing it twice', () {
    final controller = WaybillsController();
    final waybill = Waybill(
      id: 1,
      category: ShopCategory.wood,
      items: const [],
      hasPhoto: true,
      createdAt: DateTime(2026),
    );
    controller.add(waybill);
    controller.add(waybill);
    expect(controller.items, hasLength(1));

    controller.handleSessionEnded();
    expect(
      controller.items,
      isEmpty,
      reason: 'the next person on this phone must not see these',
    );
  });

  testWidgets('every market is offered, then the sheet opens on it', (
    tester,
  ) async {
    await _pumpFlow(tester);

    for (final category in ShopCategory.values) {
      expect(find.text(category.label(strings)), findsOneWidget);
    }

    await _chooseFirstCategory(tester, strings);
    expect(
      find.text(strings.waybillShopsLine(ShopCategory.plumbing.label(strings))),
      findsOneWidget,
    );
    expect(find.text(strings.waybillColumnName), findsOneWidget);
    expect(find.text(strings.waybillColumnQuantity), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing sends while the sheet is empty', (tester) async {
    await _pumpFlow(tester);
    await _chooseFirstCategory(tester, strings);

    await tester.tap(find.text(strings.waybillSend));
    await tester.pump();

    expect(find.text(strings.waybillEmptyError), findsOneWidget);
  });

  testWidgets('a name with no amount is refused and names its row', (
    tester,
  ) async {
    await _pumpFlow(tester);
    await _chooseFirstCategory(tester, strings);

    await tester.tap(find.text(strings.waybillAddRow));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'Цемент М400');
    await tester.enterText(find.byType(TextField).at(1), '10 мешков');
    await tester.enterText(find.byType(TextField).at(2), 'Песок');
    await tester.pump();
    await tester.tap(find.text(strings.waybillSend));
    await tester.pump();

    expect(find.text(strings.waybillRowIncomplete(2)), findsOneWidget);
  });

  // **the rule the whole sheet rests on**: every row the customer can see is a row staff will price,
  // so none of them may go out half-written and none is quietly dropped on the way.
  testWidgets('a row left blank holds the whole sheet back', (tester) async {
    await _pumpFlow(tester);
    await _chooseFirstCategory(tester, strings);

    await tester.enterText(find.byType(TextField).at(0), 'Цемент М400');
    await tester.enterText(find.byType(TextField).at(1), '10 мешков');
    await tester.tap(find.text(strings.waybillAddRow));
    await tester.pump();

    await tester.tap(find.text(strings.waybillSend));
    await tester.pump();
    expect(find.text(strings.waybillRowIncomplete(2)), findsOneWidget);

    // taking the empty row off is the other way to answer, and it clears the refusal with it
    await tester.tap(find.byTooltip(strings.waybillRemoveRow).last);
    await tester.pumpAndSettle();
    expect(find.text(strings.waybillRowIncomplete(2)), findsNothing);
  });

  testWidgets('a blank row is removable, and the last row is not', (
    tester,
  ) async {
    await _pumpFlow(tester);
    await _chooseFirstCategory(tester, strings);

    // one row and no cross: a sheet with nothing on it has no way back to a row
    expect(find.byTooltip(strings.waybillRemoveRow), findsNothing);

    await tester.tap(find.text(strings.waybillAddRow));
    await tester.pump();
    expect(
      find.byTooltip(strings.waybillRemoveRow),
      findsNWidgets(2),
      reason: 'a row nobody has typed into is the one most worth taking off',
    );

    await tester.tap(find.byTooltip(strings.waybillRemoveRow).first);
    await tester.pumpAndSettle();
    expect(find.byTooltip(strings.waybillRemoveRow), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets(
    'adding a row keeps what the others hold, and taking one off closes the numbers up',
    (tester) async {
      await _pumpFlow(tester);
      await _chooseFirstCategory(tester, strings);

      await tester.tap(find.text(strings.waybillAddRow));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'Первая');
      await tester.enterText(find.byType(TextField).at(2), 'Вторая');
      await tester.pump();

      await tester.tap(find.text(strings.waybillAddRow));
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Первая'), findsOneWidget);

      await tester.tap(find.byTooltip(strings.waybillRemoveRow).first);
      await tester.pumpAndSettle();
      expect(find.text('Первая'), findsNothing);
      expect(find.text('Вторая'), findsOneWidget);
      expect(find.text('3'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the photo tab offers the camera and the gallery', (
    tester,
  ) async {
    await _pumpFlow(tester);
    await _chooseFirstCategory(tester, strings);

    await tester.tap(find.text(strings.waybillModePhoto));
    await tester.pumpAndSettle();

    expect(find.text(strings.waybillTakePhoto), findsOneWidget);
    expect(find.text(strings.waybillFromGallery), findsOneWidget);

    await tester.tap(find.text(strings.waybillSend));
    await tester.pump();
    expect(find.text(strings.waybillPhotoMissing), findsOneWidget);
  });

  testWidgets('«Назад» walks one step and the rows survive it', (tester) async {
    await _pumpFlow(tester);
    await _chooseFirstCategory(tester, strings);

    await tester.enterText(find.byType(TextField).first, 'Цемент');
    await tester.pump();
    await tester.tap(find.text(strings.stepBackButton));
    await tester.pumpAndSettle();
    expect(find.text(strings.waybillCategoryTitle), findsOneWidget);

    await _chooseFirstCategory(tester, strings);
    expect(find.text('Цемент'), findsOneWidget);
  });

  testWidgets('the X over a filled sheet asks first', (tester) async {
    await _pumpFlow(tester);
    await _chooseFirstCategory(tester, strings);

    await tester.enterText(find.byType(TextField).first, 'Цемент');
    await tester.pump();
    await tester.tap(find.byTooltip(strings.closeButton));
    await tester.pumpAndSettle();

    expect(find.text(strings.waybillAbandonTitle), findsOneWidget);
  });

  testWidgets('a retry keeps its id and an edit draws a new one', (
    tester,
  ) async {
    await _signInAs('customer');
    final repository = _RecordingRepository();
    await _pumpFlow(tester, repository: repository);
    await _chooseFirstCategory(tester, strings);

    await tester.enterText(find.byType(TextField).at(0), 'Цемент');
    await tester.enterText(find.byType(TextField).at(1), '10 мешков');
    await tester.pump();

    // the connection fails twice, and pressing again must not become a second list on the server
    await tester.tap(find.text(strings.waybillSend));
    await tester.pumpAndSettle();
    expect(find.text(strings.waybillSendError('network')), findsOneWidget);
    await tester.tap(find.text(strings.waybillSend));
    await tester.pumpAndSettle();
    expect(repository.requestIds, hasLength(2));
    expect(repository.requestIds[1], repository.requestIds[0]);
    expect(
      repository.requestIds[0],
      matches(RegExp(r'^[0-9a-f]{32}$')),
      reason: 'the shape the server accepts',
    );

    // **the old id would answer with the list as it was before this edit**
    await tester.enterText(find.byType(TextField).at(1), '12 мешков');
    await tester.pump();
    repository.refusal = null;
    await tester.tap(find.text(strings.waybillSend));
    await tester.pumpAndSettle();

    expect(repository.requestIds.last, isNot(repository.requestIds.first));
    expect(repository.lastItems.single.quantity, '12 мешков');

    expect(find.text(strings.waybillNumber(1042)), findsOneWidget);
    expect(
      find.text(strings.waybillSentBody('+998 90 123 45 67')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an owner is told, and nothing is sent', (tester) async {
    await _signInAs('shop_owner');
    final repository = _RecordingRepository();
    await _pumpFlow(tester, repository: repository);
    await _chooseFirstCategory(tester, strings);

    await tester.enterText(find.byType(TextField).at(0), 'Цемент');
    await tester.enterText(find.byType(TextField).at(1), '1');
    await tester.pump();
    await tester.tap(find.text(strings.waybillSend));
    await tester.pumpAndSettle();

    expect(
      find.text(strings.waybillSendError('customers_only')),
      findsOneWidget,
    );
    expect(repository.requestIds, isEmpty);
  });

  testWidgets('an admin sends like a customer', (tester) async {
    await _signInAs('admin');
    final repository = _RecordingRepository();
    await _pumpFlow(tester, repository: repository);
    await _chooseFirstCategory(tester, strings);

    await tester.enterText(find.byType(TextField).at(0), 'Цемент');
    await tester.enterText(find.byType(TextField).at(1), '1');
    await tester.pump();
    await tester.tap(find.text(strings.waybillSend));
    await tester.pumpAndSettle();

    expect(find.text(strings.waybillSendError('customers_only')), findsNothing);
    expect(repository.requestIds, hasLength(1));
  });

  testWidgets(
    'the sheet holds the longest row on the narrowest phone, in both languages',
    (tester) async {
      await _pumpFlow(tester, width: 320);
      await _chooseFirstCategory(tester, strings);

      await tester.enterText(
        find.byType(TextField).at(0),
        'Цементно-песчаная смесь ' * 6,
      );
      await tester.enterText(find.byType(TextField).at(1), '9' * 30);
      await tester.pump();
      await tester.tap(find.text(strings.waybillSend));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text(strings.waybillModePhoto));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
