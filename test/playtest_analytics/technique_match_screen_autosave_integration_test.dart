import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_night_match/src/playtest_analytics/playtest_match_repository.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_deck.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_models.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_storage.dart';
import 'package:one_night_match/src/technique_deck/technique_match_screen.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart' show MoveAttribute;

/// 【Playtest Analytics Phase A 実プレイ確認】
///
/// 「実際にTechnique Matchを1試合プレイした場合、Playtest Analyticsへ
/// 自動保存・自動解析される状態であることを確認してください」への回答として
/// 追加した統合テスト。JSONダウンロードボタンなど手動操作を一切使わず、
/// `test/technique_match_screen_test.dart`の「回避せず諦めると勝敗が決まり、
/// 勝利バナーが表示される」と同じ操作（技を選ぶ→使用する→技を受ける→
/// 諦める）でTechniqueMatchScreenを実際のウィジェットツリー・実際の
/// TechniqueMatchEngine/TechniqueMatchCpu経由でフォール勝利まで進め、
/// その後[PlaytestMatchRepository]に試合が自動保存され、
/// [TechniqueMatchAnalyzer]による解析結果が付与されていることを確認する。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  TechniqueDeckCardCatalog fallCatalog() => const TechniqueDeckCardCatalog(
    techniques: [
      TechniqueDeckTechniqueCard(
        id: 'fall_move',
        name: 'フォール技',
        category: TechniqueCardCategory.normal,
        attribute: MoveAttribute.strike,
        attackEnergyCost: {MoveAttribute.strike: 1},
        reversalEnergyCost: {MoveAttribute.counter: 1},
        power: 10,
        hasPinEffect: true,
        kickOutThreshold: 20,
        kickOutHpRate: 0.5,
      ),
    ],
    energies: [
      TechniqueEnergyCard(
        id: 'energy_strike',
        attribute: MoveAttribute.strike,
        name: '打エネルギー',
      ),
    ],
  );

  testWidgets('試合終了時にPlaytest Analyticsへ自動保存・自動解析される', (tester) async {
    final repo = LocalTechniqueDeckRepository();
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: TechniqueMatchScreen(catalog: fallCatalog(), deckRepository: repo),
      ),
    );
    await tester.pumpAndSettle();

    final dynamic screenState = tester.state(find.byType(TechniqueMatchScreen));
    // ignore: avoid_dynamic_calls
    final wrestlerAId = (screenState as dynamic).wrestlerA.id as String;
    await repo.save(
      TechniqueDeckSaveRecord(
        deckId: 'fall_deck',
        name: 'フォールテスト用デッキ',
        wrestlerId: wrestlerAId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        entries: const [
          TechniqueDeckEntry(instanceId: 'e1', cardId: 'fall_move', cardType: TechniqueDeckCardType.technique),
          TechniqueDeckEntry(instanceId: 'e2', cardId: 'energy_strike', cardType: TechniqueDeckCardType.energy),
        ],
      ),
    );

    // 保存前は当然0件（このテストが唯一の保存経路であることの前提確認）。
    expect(await PlaytestMatchRepository().loadAll(), isEmpty);

    await tester.tap(find.text('試合開始'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('打エネルギー').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('セットする'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('フォール技').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用する'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('技を受ける'));
    await tester.pumpAndSettle();

    expect(find.text('諦める（敗北を認める）'), findsOneWidget);
    await tester.tap(find.text('諦める（敗北を認める）'));
    await tester.pumpAndSettle();

    // 試合終了（勝利バナー）を確認 — ここまでは既存テストと同じ操作。
    expect(find.textContaining('の勝利！'), findsOneWidget);
    expect(find.textContaining('フォール勝利'), findsWidgets);

    // 【本題】JSONダウンロードボタンを一切押していないのに、
    // Playtest Analyticsのローカル保存へ自動的に記録されていることを確認。
    final saved = await PlaytestMatchRepository().loadAll();
    expect(saved, hasLength(1));
    final record = saved.single;
    expect(record.finishReason, 'フォール勝利');
    expect(record.turns, greaterThan(0));
    // 自動診断（TechniqueMatchAnalyzer）が実行され、結果が保存されている
    // こと（正常な試合なのでCRITICALは0件のはず）。
    expect(record.summary.criticalCount, 0);
  });
}
