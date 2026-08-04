import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_deck.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_models.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_storage.dart';
import 'package:one_night_match/src/technique_deck/technique_match_screen.dart';
import 'package:one_night_match/src/technique_deck/technique_match_state.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart' show MoveAttribute;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  TechniqueDeckCardCatalog testCatalog() => const TechniqueDeckCardCatalog(
    techniques: [
      TechniqueDeckTechniqueCard(
        id: 'normal_1',
        name: '通常技A',
        category: TechniqueCardCategory.normal,
        attribute: MoveAttribute.strike,
        attackEnergyCost: {MoveAttribute.strike: 1},
        reversalEnergyCost: {MoveAttribute.counter: 1},
        power: 10,
      ),
    ],
    energies: [
      TechniqueEnergyCard(
        id: 'energy_strike',
        attribute: MoveAttribute.strike,
        name: '打エネルギー',
      ),
      TechniqueEnergyCard(
        id: 'energy_counter',
        attribute: MoveAttribute.counter,
        name: '返エネルギー',
      ),
    ],
    defenseCards: [],
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    TechniqueDeckRepository? deckRepository,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    await tester.pumpWidget(
      MaterialApp(
        home: TechniqueMatchScreen(
          catalog: testCatalog(),
          deckRepository: deckRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<String> startWithFixedDeck(
    WidgetTester tester,
    LocalTechniqueDeckRepository repo,
    List<TechniqueDeckEntry> entries,
  ) async {
    await pumpScreen(tester, deckRepository: repo);
    final state = tester.state(find.byType(TechniqueMatchScreen));
    // ignore: avoid_dynamic_calls
    final wrestlerAId = (state as dynamic).wrestlerA.id as String;
    await repo.save(
      TechniqueDeckSaveRecord(
        deckId: 'combat_deck',
        name: '戦闘テスト用デッキ',
        wrestlerId: wrestlerAId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        entries: entries,
      ),
    );
    await tester.tap(find.text('試合開始'));
    await tester.pumpAndSettle();
    return wrestlerAId;
  }

  group('TechniqueMatchScreen: セットアップ', () {
    testWidgets('レスラーAとBの初期選択が表示される', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Player A'), findsOneWidget);
      expect(find.text('Player B'), findsOneWidget);
      expect(find.text('試合開始'), findsOneWidget);
    });

    testWidgets('試合開始すると、保存済みデッキが無ければ自動生成した仮デッキで開始する', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('試合開始'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ターン1'), findsWidgets);
      expect(find.textContaining('仮デッキを自動生成'), findsWidgets);
    });
  });

  group('TechniqueMatchScreen: 試合進行', () {
    testWidgets('ダウンする→休息でHPが回復しターンが終了する', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('試合開始'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ダウンする'));
      await tester.pumpAndSettle();
      expect(find.text('ダウン'), findsWidgets);

      await tester.tap(find.text('休息'));
      await tester.pumpAndSettle();

      // 休息はターン終了を伴うため、手番はBに移りログにも記録される。
      expect(find.textContaining('休息してHPを'), findsOneWidget);
      expect(find.textContaining('の手番'), findsWidgets);
    });

    testWidgets('ターン終了を押すと手番が入れ替わる', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('試合開始'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ターン終了'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ターンを終了した'), findsOneWidget);
    });

    testWidgets('新しい試合ボタンでセットアップ画面へ戻る', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('試合開始'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      expect(find.text('試合開始'), findsOneWidget);
    });
  });

  group('TechniqueMatchScreen: 保存済みデッキの利用', () {
    testWidgets('保存済みデッキがあればそれを使用する', (tester) async {
      final repo = LocalTechniqueDeckRepository();
      await pumpScreen(tester, deckRepository: repo);

      // wrestlers読み込み完了後、初期選択されるレスラーIDに合わせて保存する
      // 必要があるため、いったんセットアップ画面が出てから該当IDで保存する。
      final state = tester.state(find.byType(TechniqueMatchScreen));
      // ignore: avoid_dynamic_calls
      final wrestlerAId = (state as dynamic).wrestlerA.id as String;

      await repo.save(
        TechniqueDeckSaveRecord(
          deckId: 'saved_deck',
          name: '保存デッキ',
          wrestlerId: wrestlerAId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          entries: const [
            TechniqueDeckEntry(
              instanceId: 'e1',
              cardId: 'normal_1',
              cardType: TechniqueDeckCardType.technique,
            ),
          ],
        ),
      );

      await tester.tap(find.text('試合開始'));
      await tester.pumpAndSettle();

      expect(find.textContaining('保存済みデッキ「保存デッキ」を使用'), findsOneWidget);
    });
  });

  group('TechniqueMatchScreen: 技の宣言・成立', () {
    testWidgets('エネルギーをセットしてから技を使用すると相手にダメージが入る', (tester) async {
      final repo = LocalTechniqueDeckRepository();
      await startWithFixedDeck(tester, repo, const [
        TechniqueDeckEntry(
          instanceId: 'e1',
          cardId: 'normal_1',
          cardType: TechniqueDeckCardType.technique,
        ),
        TechniqueDeckEntry(
          instanceId: 'e2',
          cardId: 'energy_strike',
          cardType: TechniqueDeckCardType.energy,
        ),
        TechniqueDeckEntry(
          instanceId: 'e3',
          cardId: 'energy_strike',
          cardType: TechniqueDeckCardType.energy,
        ),
        TechniqueDeckEntry(
          instanceId: 'e4',
          cardId: 'energy_strike',
          cardType: TechniqueDeckCardType.energy,
        ),
        TechniqueDeckEntry(
          instanceId: 'e5',
          cardId: 'energy_strike',
          cardType: TechniqueDeckCardType.energy,
        ),
      ]);

      await tester.tap(find.text('打エネルギー').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('セットする'));
      await tester.pumpAndSettle();
      expect(find.textContaining('エネルギーとしてセットした'), findsOneWidget);

      await tester.tap(find.text('通常技A').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用する'));
      await tester.pumpAndSettle();

      // 技を宣言すると防御側の返技判定ダイアログが自動で開く。
      expect(find.textContaining('宣言した'), findsOneWidget);
      expect(find.text('返技しない'), findsOneWidget);

      await tester.tap(find.text('返技しない'));
      await tester.pumpAndSettle();

      expect(find.textContaining('が成立した'), findsOneWidget);
      expect(find.textContaining('ダメージ'), findsOneWidget);
    });

    testWidgets('エネルギー不足の技は使用不可の理由が表示され、使用するボタンが無効になる', (
      tester,
    ) async {
      final repo = LocalTechniqueDeckRepository();
      await startWithFixedDeck(tester, repo, const [
        TechniqueDeckEntry(
          instanceId: 'e1',
          cardId: 'normal_1',
          cardType: TechniqueDeckCardType.technique,
        ),
      ]);

      await tester.tap(find.text('通常技A').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('エネルギーが不足しています'), findsOneWidget);
      final useButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '使用する'),
      );
      expect(useButton.onPressed, isNull);
    });
  });

  group('TechniqueMatchScreen: Phase 5 ラリー', () {
    testWidgets('攻撃を宣言すると返技判定ダイアログが開き、返技すると攻守交代してChainが表示される', (
      tester,
    ) async {
      final repo = LocalTechniqueDeckRepository();
      await startWithFixedDeck(tester, repo, const [
        TechniqueDeckEntry(
          instanceId: 'e1',
          cardId: 'normal_1',
          cardType: TechniqueDeckCardType.technique,
        ),
        TechniqueDeckEntry(
          instanceId: 'e2',
          cardId: 'energy_strike',
          cardType: TechniqueDeckCardType.energy,
        ),
      ]);

      await tester.tap(find.text('打エネルギー').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('セットする'));
      await tester.pumpAndSettle();

      // Bに返技エネルギーを直接注入する（実プレイではBの手番に自分で
      // セットする。ここではUIの配線確認が目的のため直接注入する）。
      final dynamic screenState = tester.state(find.byType(TechniqueMatchScreen));
      final TechniqueMatchState current = screenState.matchState;
      screenState.matchState = current.copyWith(
        playerB: current.playerB.copyWith(
          energyPool: const {MoveAttribute.counter: 1},
        ),
      );

      await tester.tap(find.text('通常技A').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用する'));
      await tester.pumpAndSettle();

      expect(find.textContaining('[Chain 1]'), findsWidgets);
      expect(find.text('返技する'), findsOneWidget);

      await tester.tap(find.text('返技する'));
      await tester.pumpAndSettle();

      expect(find.textContaining('攻守交代'), findsOneWidget);
      expect(find.textContaining('Chain 1'), findsWidgets);
      expect(find.textContaining('攻撃側'), findsWidgets);
      expect(find.text('ラリーを終了する'), findsOneWidget);

      // 攻守交代後、追撃せずラリーを終了できる。
      await tester.tap(find.text('ラリーを終了する'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ラリーを終了した'), findsOneWidget);
      expect(find.text('ターン終了'), findsOneWidget); // 通常の行動選択に戻る
    });
  });
}
