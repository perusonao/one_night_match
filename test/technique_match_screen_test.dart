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

  // UI Ver.2改修により、手札カードは「タップ→選択→確認ボタン」の2段階
  // 操作に戻った（誤操作防止のため、Ver.1のタップ即実行から巻き戻した）。
  // カードをタップすると選択され、下に現れる確認バーのボタン（従来と同じ
  // 「セットする」「使用する」「宣言する」）で実行する。長押しは常に詳細
  // ダイアログを開く。また進行ログ・プレイヤーカードの詳細情報は折りたたみ
  // 式のため、それらの内容を検証するテストでは事前に展開操作を行う。

  Future<void> expandLog(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('logToggle')));
    await tester.pumpAndSettle();
  }

  Future<void> expandPlayerDetail(WidgetTester tester, int playerIndex) async {
    await tester.tap(find.byKey(ValueKey('playerDetailToggle$playerIndex')));
    await tester.pumpAndSettle();
  }

  /// 手札カードを選択→確認バーのボタンをタップして実行する（Ver.2の
  /// 標準操作）。
  Future<void> selectAndConfirm(
    WidgetTester tester,
    String cardName,
    String confirmLabel,
  ) async {
    await tester.tap(find.text(cardName).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(confirmLabel));
    await tester.pumpAndSettle();
  }

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
      await expandPlayerDetail(tester, 0);
      expect(find.textContaining('仮デッキを自動生成'), findsWidgets);
    });
  });

  group('TechniqueMatchScreen: 試合進行', () {
    testWidgets('休息するとダウン状態を経てHPが回復しターンが終了する', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('試合開始'));
      await tester.pumpAndSettle();

      // 「ダウンする」ボタンは廃止済み。スタンド中に「休息」を押すと
      // ダウン→HP回復→ターン終了が連続で発生する。
      await tester.tap(find.text('休息'));
      await tester.pumpAndSettle();

      // 休息した側（元のアクティブプレイヤー）はダウン状態のまま残るため、
      // ダウンバッジが引き続き表示される。
      expect(find.text('ダウン'), findsWidgets);

      await expandLog(tester);
      expect(find.textContaining('休息してHPを'), findsOneWidget);
      expect(find.textContaining('の手番'), findsWidgets);
    });

    testWidgets('ターン終了を押すと手番が入れ替わる', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('試合開始'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ターン終了'));
      await tester.pumpAndSettle();

      await expandLog(tester);
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

      await expandPlayerDetail(tester, 0);
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
      await expandLog(tester);

      // カードをタップ→選択→確認バーの「セットする」で実行する。
      await selectAndConfirm(tester, '打エネルギー', 'セットする');
      expect(find.textContaining('エネルギーとしてセットした'), findsOneWidget);

      // 技カードも同様にタップ→選択→「使用する」で宣言する。
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

    testWidgets('エネルギー不足の技を選択すると使用不可の理由が確認バーに表示され、使用するボタンが無効になる', (
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

      // このカードは個別に使用不可（エネルギー不足）。選択すると確認バーに
      // 理由が表示され、実行ボタンは無効になる。
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
      await expandLog(tester);

      await selectAndConfirm(tester, '打エネルギー', 'セットする');

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

  group('TechniqueMatchScreen: Phase 6 フォール・ギブアップ回避', () {
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
      defenseCards: [
        TechniqueDefenseCard(
          id: 'kickout_normal',
          name: '通常キックアウト',
          type: TechniqueDeckCardType.kickOut,
          kickOutCategory: KickOutCardCategory.normal,
        ),
      ],
    );

    Future<void> pumpFallScreen(
      WidgetTester tester, {
      required TechniqueDeckRepository deckRepository,
    }) async {
      await tester.binding.setSurfaceSize(const Size(800, 3000));
      await tester.pumpWidget(
        MaterialApp(
          home: TechniqueMatchScreen(
            catalog: fallCatalog(),
            deckRepository: deckRepository,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('フォール技が成立すると回避判定ダイアログが開き、キックアウトカードで回避できる', (
      tester,
    ) async {
      final repo = LocalTechniqueDeckRepository();
      await pumpFallScreen(tester, deckRepository: repo);
      final state = tester.state(find.byType(TechniqueMatchScreen));
      // ignore: avoid_dynamic_calls
      final wrestlerAId = (state as dynamic).wrestlerA.id as String;

      await repo.save(
        TechniqueDeckSaveRecord(
          deckId: 'fall_deck',
          name: 'フォールテスト用デッキ',
          wrestlerId: wrestlerAId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          entries: const [
            TechniqueDeckEntry(
              instanceId: 'e1',
              cardId: 'fall_move',
              cardType: TechniqueDeckCardType.technique,
            ),
            TechniqueDeckEntry(
              instanceId: 'e2',
              cardId: 'energy_strike',
              cardType: TechniqueDeckCardType.energy,
            ),
          ],
        ),
      );
      await tester.tap(find.text('試合開始'));
      await tester.pumpAndSettle();
      await expandLog(tester);

      await selectAndConfirm(tester, '打エネルギー', 'セットする');

      // Bの手札をキックアウトカード1枚だけに差し替える（実プレイではBの
      // デッキに含まれる。ここではUIの配線確認が目的のため直接注入する。
      // Bの自動生成デッキが偶然同名カードを引いている場合との重複を避ける
      // ため、追記ではなく丸ごと置き換える）。
      final dynamic screenState = tester.state(find.byType(TechniqueMatchScreen));
      final TechniqueMatchState beforeDeclare = screenState.matchState;
      screenState.matchState = beforeDeclare.copyWith(
        playerB: beforeDeclare.playerB.copyWith(
          hand: const [
            TechniqueDeckEntry(
              instanceId: 'k1',
              cardId: 'kickout_normal',
              cardType: TechniqueDeckCardType.kickOut,
            ),
          ],
        ),
      );

      await tester.tap(find.text('フォール技').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用する'));
      await tester.pumpAndSettle();

      // 返技せず成立させる。
      await tester.tap(find.text('返技しない'));
      await tester.pumpAndSettle();

      expect(find.textContaining('フォールの危機'), findsWidgets);
      final kickOutButton = find.widgetWithText(OutlinedButton, '通常キックアウト');
      expect(kickOutButton, findsOneWidget);

      await tester.tap(kickOutButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('を回避した'), findsOneWidget);
      expect(find.text('ターン終了'), findsOneWidget); // 通常の行動選択に戻る
    });

    testWidgets('回避せず諦めると勝敗が決まり、勝利バナーが表示される', (tester) async {
      final repo = LocalTechniqueDeckRepository();
      await pumpFallScreen(tester, deckRepository: repo);
      final state = tester.state(find.byType(TechniqueMatchScreen));
      // ignore: avoid_dynamic_calls
      final wrestlerAId = (state as dynamic).wrestlerA.id as String;

      await repo.save(
        TechniqueDeckSaveRecord(
          deckId: 'fall_deck',
          name: 'フォールテスト用デッキ',
          wrestlerId: wrestlerAId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          entries: const [
            TechniqueDeckEntry(
              instanceId: 'e1',
              cardId: 'fall_move',
              cardType: TechniqueDeckCardType.technique,
            ),
            TechniqueDeckEntry(
              instanceId: 'e2',
              cardId: 'energy_strike',
              cardType: TechniqueDeckCardType.energy,
            ),
          ],
        ),
      );
      await tester.tap(find.text('試合開始'));
      await tester.pumpAndSettle();

      await selectAndConfirm(tester, '打エネルギー', 'セットする');

      await tester.tap(find.text('フォール技').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用する'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('返技しない'));
      await tester.pumpAndSettle();

      expect(find.text('諦める（敗北を認める）'), findsOneWidget);
      await tester.tap(find.text('諦める（敗北を認める）'));
      await tester.pumpAndSettle();

      expect(find.textContaining('の勝利！'), findsOneWidget);
      expect(find.textContaining('フォール勝利'), findsWidgets);
      // 試合終了後は通常の行動ボタンが表示されない。
      expect(find.text('ターン終了'), findsNothing);
    });
  });

  group('TechniqueMatchScreen: Phase 7 フィニッシャー', () {
    // LocalWrestlerRepository（未上書き時）のデフォルト先頭レスラーは常に
    // 'wrestler_akari'（lib/src/wrestler_editor/defaults.dart）。これを
    // allowedWrestlerIdsに直接指定することで、試合開始後の非同期ロードを
    // 待たずにフィニッシャーの使用可否を確定させる。
    TechniqueDeckCardCatalog finisherCatalog() => const TechniqueDeckCardCatalog(
      techniques: [
        TechniqueDeckTechniqueCard(
          id: 'finisher_move',
          name: 'テストフィニッシャー',
          category: TechniqueCardCategory.finisher,
          attribute: MoveAttribute.strike,
          allowedWrestlerIds: ['wrestler_akari'],
          minimumLevel: 1,
          attackEnergyCost: {MoveAttribute.strike: 2},
          power: 30,
          heatDelta: 10,
          hasFinisherEffect: true,
        ),
      ],
      energies: [
        TechniqueEnergyCard(
          id: 'energy_strike',
          attribute: MoveAttribute.strike,
          name: '打エネルギー',
        ),
      ],
      defenseCards: [
        TechniqueDefenseCard(
          id: 'escape_card',
          name: 'エスケープ',
          type: TechniqueDeckCardType.escape,
        ),
        TechniqueDefenseCard(
          id: 'special_kickout_card',
          name: '特殊キックアウト',
          type: TechniqueDeckCardType.kickOut,
          kickOutCategory: KickOutCardCategory.finisherEscape,
        ),
      ],
    );

    Future<void> pumpFinisherScreen(
      WidgetTester tester, {
      required TechniqueDeckRepository deckRepository,
    }) async {
      await tester.binding.setSurfaceSize(const Size(800, 3000));
      await tester.pumpWidget(
        MaterialApp(
          home: TechniqueMatchScreen(
            catalog: finisherCatalog(),
            deckRepository: deckRepository,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('フィニッシャーが成立し脱出できないと勝利バナーが表示される', (tester) async {
      final repo = LocalTechniqueDeckRepository();
      await pumpFinisherScreen(tester, deckRepository: repo);
      final state = tester.state(find.byType(TechniqueMatchScreen));
      // ignore: avoid_dynamic_calls
      final wrestlerAId = (state as dynamic).wrestlerA.id as String;

      await repo.save(
        TechniqueDeckSaveRecord(
          deckId: 'fin_deck',
          name: 'フィニッシャーテスト用デッキ',
          wrestlerId: wrestlerAId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          entries: const [
            TechniqueDeckEntry(
              instanceId: 'e1',
              cardId: 'finisher_move',
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
          ],
        ),
      );
      await tester.tap(find.text('試合開始'));
      await tester.pumpAndSettle();

      await selectAndConfirm(tester, '打エネルギー', 'セットする');
      await selectAndConfirm(tester, '打エネルギー', 'セットする');

      // フィニッシャーもタップ→選択→「宣言する」で宣言する。
      await tester.tap(find.text('テストフィニッシャー').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('宣言する'));
      await tester.pumpAndSettle();

      expect(find.textContaining('発動キャンセル判定'), findsOneWidget);
      expect(find.text('キャンセルしない'), findsOneWidget);
      await tester.tap(find.text('キャンセルしない'));
      await tester.pumpAndSettle();

      expect(find.textContaining('成立した'), findsWidgets);
      expect(find.text('諦める（敗北を認める）'), findsOneWidget);
      await tester.tap(find.text('諦める（敗北を認める）'));
      await tester.pumpAndSettle();

      expect(find.textContaining('の勝利！'), findsOneWidget);
      expect(find.textContaining('フィニッシャー勝利'), findsWidgets);
      expect(find.text('ターン終了'), findsNothing);
    });

    testWidgets('エスケープカードで発動をキャンセルできる（ダメージなし）', (tester) async {
      final repo = LocalTechniqueDeckRepository();
      await pumpFinisherScreen(tester, deckRepository: repo);
      final state = tester.state(find.byType(TechniqueMatchScreen));
      // ignore: avoid_dynamic_calls
      final wrestlerAId = (state as dynamic).wrestlerA.id as String;

      await repo.save(
        TechniqueDeckSaveRecord(
          deckId: 'fin_deck2',
          name: 'フィニッシャーテスト用デッキ2',
          wrestlerId: wrestlerAId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          entries: const [
            TechniqueDeckEntry(
              instanceId: 'e1',
              cardId: 'finisher_move',
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
          ],
        ),
      );
      await tester.tap(find.text('試合開始'));
      await tester.pumpAndSettle();

      // Bにエスケープカードを直接注入する（実プレイではBのデッキに含まれる。
      // ここではUIの配線確認が目的のため直接注入する）。
      final dynamic screenState = tester.state(find.byType(TechniqueMatchScreen));
      final TechniqueMatchState before = screenState.matchState;
      screenState.matchState = before.copyWith(
        playerB: before.playerB.copyWith(
          hand: const [
            TechniqueDeckEntry(
              instanceId: 'esc1',
              cardId: 'escape_card',
              cardType: TechniqueDeckCardType.escape,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await selectAndConfirm(tester, '打エネルギー', 'セットする');
      await selectAndConfirm(tester, '打エネルギー', 'セットする');

      await tester.tap(find.text('テストフィニッシャー').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('宣言する'));
      await tester.pumpAndSettle();

      final escapeButton = find.widgetWithText(OutlinedButton, 'エスケープ');
      expect(escapeButton, findsOneWidget);
      await tester.tap(escapeButton);
      await tester.pumpAndSettle();

      await expandLog(tester);
      expect(find.textContaining('キャンセルした'), findsOneWidget);
      // ダメージが発生していないこと（勝敗もついていない）。
      expect(find.text('ターン終了'), findsOneWidget);
    });
  });
}
