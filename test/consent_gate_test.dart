import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_companion_app/controllers/consent_controller.dart';
import 'package:pet_companion_app/screens/consent_screen.dart';
import 'package:pet_companion_app/screens/legal_document_screen.dart';
import 'package:pet_companion_app/services/auth/consent_api_service.dart';
import 'package:pet_companion_app/services/consent_service.dart';

/// 不打網路的同意補送 stub：讓本檔聚焦在「同意 gate / 持久化」行為，
/// 後端補送另有專屬測試（consent_backend_sync_test.dart）。
class _OfflineConsentApi extends ConsentApiService {
  @override
  Future<bool> submitConsent({
    required String consentType,
    required String consentVersion,
    String action = 'granted',
    String? source,
    String? firebaseUid,
    String? idToken,
    String? userId,
    String? elderId,
    String? appVersion,
    String? platform,
    String? agreedAt,
  }) async =>
      false;
}

ConsentService _offlineConsentService() =>
    ConsentService(consentApi: _OfflineConsentApi());

/// 依 [ConsentController.status] 分流的精簡 gate（鏡像 app.dart 的 ConsentGate，
/// 但不拉進整個 AuthGate / MultiProvider 依賴）。
class _TestConsentGate extends StatelessWidget {
  const _TestConsentGate();

  @override
  Widget build(BuildContext context) {
    final consent = context.watch<ConsentController>();
    switch (consent.status) {
      case ConsentStatus.loading:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case ConsentStatus.needsConsent:
        return ConsentScreen(
          onAgreed: () => context.read<ConsentController>().grantConsent(),
        );
      case ConsentStatus.granted:
        return const Scaffold(body: Center(child: Text('已進入主流程')));
    }
  }
}

Future<void> _pumpGate(
  WidgetTester tester,
  ConsentController controller,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<ConsentController>.value(
      value: controller,
      child: const MaterialApp(home: _TestConsentGate()),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void useTallView(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
  }

  testWidgets('未同意時 Gate 擋住，顯示知情同意流程', (tester) async {
    useTallView(tester);
    SharedPreferences.setMockInitialValues({});
    final controller =
        ConsentController(consentService: _offlineConsentService());
    await controller.load();
    await _pumpGate(tester, controller);
    await tester.pump();

    expect(find.byType(ConsentScreen), findsOneWidget);
    expect(find.text('歡迎來到你的陪伴空間'), findsOneWidget);
    expect(find.text('已進入主流程'), findsNothing);
    // 沒有工程字樣 / 英文錯誤。
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('error'), findsNothing);
  });

  testWidgets('同意按鈕預設不可按，勾選後才可按；按下後進入主流程', (tester) async {
    useTallView(tester);
    SharedPreferences.setMockInitialValues({});
    final controller =
        ConsentController(consentService: _offlineConsentService());
    await controller.load();
    await _pumpGate(tester, controller);
    await tester.pump();

    final agreeButton = find.widgetWithText(FilledButton, '我同意，開始陪伴');
    expect(agreeButton, findsOneWidget);
    // 未勾選前不可按。
    expect(tester.widget<FilledButton>(agreeButton).onPressed, isNull);

    // 主動勾選。
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(tester.widget<FilledButton>(agreeButton).onPressed, isNotNull);

    // 按下同意。
    await tester.tap(agreeButton);
    await tester.pumpAndSettle();

    expect(find.text('已進入主流程'), findsOneWidget);
    expect(find.byType(ConsentScreen), findsNothing);
  });

  testWidgets('同意狀態持久化：重啟（新 controller 載入）後不再要求同意', (tester) async {
    useTallView(tester);
    SharedPreferences.setMockInitialValues({});

    // 第一次：同意。
    final first = ConsentController(consentService: _offlineConsentService());
    await first.load();
    await first.grantConsent();
    expect(first.status, ConsentStatus.granted);

    // 模擬重啟：用新的 controller + service，從同一個本機儲存載入。
    final second = ConsentController(consentService: _offlineConsentService());
    await second.load();
    expect(second.status, ConsentStatus.granted);

    await _pumpGate(tester, second);
    await tester.pump();
    expect(find.text('已進入主流程'), findsOneWidget);
    expect(find.byType(ConsentScreen), findsNothing);
  });

  testWidgets('條款版本更新後，舊版本同意者需重新同意', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = _offlineConsentService();
    // 已同意舊版本。
    await service.recordConsent('old.version');

    final controller = ConsentController(
      consentService: service,
      requiredVersion: 'new.version',
    );
    await controller.load();
    expect(controller.status, ConsentStatus.needsConsent);
  });

  testWidgets('同意畫面可開啟隱私權政策與服務條款（App 內可捲動閱讀）', (tester) async {
    useTallView(tester);
    SharedPreferences.setMockInitialValues({});
    final controller =
        ConsentController(consentService: _offlineConsentService());
    await controller.load();
    await _pumpGate(tester, controller);
    await tester.pump();

    await tester.tap(find.text('閱讀隱私權政策'));
    await tester.pumpAndSettle();
    expect(find.byType(LegalDocumentScreen), findsOneWidget);
    expect(find.text('隱私權政策'), findsWidgets);
    // 返回。
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('閱讀服務條款'));
    await tester.pumpAndSettle();
    expect(find.byType(LegalDocumentScreen), findsOneWidget);
  });

  testWidgets('隱私權政策 / 服務條款畫面可在 App 內捲動閱讀（設定頁與同意畫面共用入口）',
      (tester) async {
    useTallView(tester);

    await tester.pumpWidget(
      MaterialApp(home: LegalDocumentScreen.privacyPolicy()),
    );
    await tester.pump();
    expect(find.text('隱私權政策'), findsWidgets);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('我們會收集哪些資料'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(home: LegalDocumentScreen.termsOfService()),
    );
    await tester.pump();
    expect(find.text('服務條款'), findsWidgets);
    expect(find.text('陪伴提醒不是醫療診斷'), findsOneWidget);
  });

  test('resetConsent 後回到 needsConsent（設定頁重新檢視同意用）', () async {
    SharedPreferences.setMockInitialValues({});
    final controller =
        ConsentController(consentService: _offlineConsentService());
    await controller.load();
    await controller.grantConsent();
    expect(controller.status, ConsentStatus.granted);

    await controller.resetConsent();
    expect(controller.status, ConsentStatus.needsConsent);

    // 持久化也清掉了：新 controller 載入仍為 needsConsent。
    final reloaded = ConsentController(consentService: _offlineConsentService());
    await reloaded.load();
    expect(reloaded.status, ConsentStatus.needsConsent);
  });
}
