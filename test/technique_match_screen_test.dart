import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_deck.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_defaults.dart'
    show buildProvisionalTechniqueDeckCatalog;
import 'package:one_night_match/src/technique_deck/technique_deck_models.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_storage.dart';
import 'package:one_night_match/src/technique_deck/technique_cpu_presentation_timing.dart';
import 'package:one_night_match/src/technique_deck/technique_match_screen.dart';
import 'package:one_night_match/src/technique_deck/technique_match_state.dart';
import 'package:one_night_match/src/wrestler_editor/defaults.dart'
    show defaultEditorWrestlers;
import 'package:one_night_match/src/wrestler_editor/models.dart' show MoveAttribute;
import 'package:one_night_match/src/wrestler_editor/repository.dart'
    show LocalWrestlerRepository;

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
    LocalWrestlerRepository? wrestlerRepository,
    TechniqueDeckCardCatalog? catalog,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    await tester.pumpWidget(
      MaterialApp(
        home: TechniqueMatchScreen(
          catalog: catalog ?? testCatalog(),
          deckRepository: deckRepository,
          wrestlerRepository: wrestlerRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<String> startWithFixedDeck(
    WidgetTester tester,
    LocalTechniqueDeckRepository repo,
    List<TechniqueDeckEntry> entries, {
    TechniqueDeckCardCatalog? catalog,
  }) async {
    await pumpScreen(tester, deckRepository: repo, catalog: catalog);
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

    testWidgets('試合開始すると、保存済みデッキが無ければPhase 7Aモデルデッキで開始する', (tester) async {
      // Technique Deck Rules Phase 7A（仕様書「⑥Technique Match」）で
      // デッキ解決優先度が「保存済みデッキ→モデルデッキ→AutoGenerator」に
      // 変更された。既定のレスラー（wrestler_akari等）は全員Phase 7A
      // モデルデッキを持つため、保存済みデッキが無い場合はモデルデッキが
      // 使われることを検証する。
      // Phase 8.5A: 休息廃止により、使用可能な技も手札のエネルギーカードも
      // 無いフレッシュターンは無言でターンを自動終了するようになった。この
      // テストは「試合開始直後」の状態を検証したいため、gameplay用の
      // testCatalog()（1技のみの縮小版）ではなく、実際のデッキと一致する
      // 本物のカタログを使い、Aの手札のエネルギーカードが正しく認識されて
      // 自動終了しない状態にする。
      await pumpScreen(tester, catalog: buildProvisionalTechniqueDeckCatalog());
      await tester.tap(find.text('試合開始'));
      await tester.pumpAndSettle();

      // 優先度1（縦1画面化）でターン数バッジは常時表示から外れ、ログ展開時
      // のみ見えるようになった。
      await expandLog(tester);
      expect(find.textContaining('ターン1'), findsWidgets);
      await expandPlayerDetail(tester, 0);
      expect(find.textContaining('モデルデッキ'), findsWidgets);
    });

    testWidgets(
      '試合開始すると、保存済みデッキもモデルデッキも無ければ自動生成した仮デッキで開始する',
      (tester) async {
        // Phase 7Aモデルデッキを持たないレスラー（新規登録直後の想定）
        // では、従来通りAutoGeneratorへフォールバックすることを検証する。
        final base = defaultEditorWrestlers.first;
        final customWrestlers = [
          base.copyWith(id: 'wrestler_test_no_model_a', name: 'Test No-Model A'),
          base.copyWith(id: 'wrestler_test_no_model_b', name: 'Test No-Model B'),
        ];
        SharedPreferences.setMockInitialValues({
          LocalWrestlerRepository.storageKey: jsonEncode(
            customWrestlers.map((w) => w.toJson()).toList(),
          ),
        });
        // Phase 8.5A: 上のテストと同じ理由で本物のカタログを使う。
        await pumpScreen(
          tester,
          wrestlerRepository: LocalWrestlerRepository(),
          catalog: buildProvisionalTechniqueDeckCatalog(),
        );
        await tester.tap(find.text('試合開始'));
        await tester.pumpAndSettle();

        await expandLog(tester);
        expect(find.textContaining('ターン1'), findsWidgets);
        await expandPlayerDetail(tester, 0);
        expect(find.textContaining('仮デッキを自動生成'), findsWidgets);
      },
    );
  });

  group('TechniqueMatchScreen: 試合進行', () {
    testWidgets(
      '使用可能な技もエネルギーカードも無いフレッシュターンは無言でターンが自動終了する（Phase 8.5A: 休息廃止）',
      (tester) async {
        // 休息・独立した「ターン終了」ボタンはPhase 8.5Aで廃止された。
        // Aの手札を技カード1枚のみ（エネルギーカードは無し）にすることで、
        // このターンにAが取れる行動が無い状況を作る。Bは本物のカタログで
        // 通常どおり解決させ、Aの手番だけが無言で自動終了することを確認する。
        final repo = LocalTechniqueDeckRepository();
        await startWithFixedDeck(
          tester,
          repo,
          const [
            TechniqueDeckEntry(
              instanceId: 'e1',
              cardId: 'normal_1',
              cardType: TechniqueDeckCardType.technique,
            ),
          ],
          catalog: buildProvisionalTechniqueDeckCatalog(),
        );

        // 「ターン終了」「休息」いずれのボタンも存在しない。
        expect(find.text('ターン終了'), findsNothing);
        expect(find.text('休息'), findsNothing);

        final dynamic screenState = tester.state(find.byType(TechniqueMatchScreen));
        final TechniqueMatchState state = screenState.matchState;
        expect(state.activePlayerIndex, 1); // Aの手番が無言でBへ移った

        await expandLog(tester);
        expect(find.textContaining('のターンを終了した'), findsWidgets);
      },
    );

    testWidgets('新しい試合ボタンは確認ダイアログを経てセットアップ画面へ戻る', (tester) async {
      // Ver.3⑧: デッキリセット相当の取り消せない操作のため確認ダイアログを
      // 追加した。
      await pumpScreen(tester);
      await tester.tap(find.text('試合開始'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      expect(find.text('新しい試合を始めますか？'), findsOneWidget);
      await tester.tap(find.text('新しい試合を始める'));
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

      // 【次フェーズ Stage4】手札の技カードにSPEEDが表示され、speed未指定
      // カード（testCatalog()のnormal_1、既定値1）でも例外にならないこと
      // を確認する。
      expect(find.textContaining('SPD1'), findsWidgets);

      // 技カードも同様にタップ→選択→「使用する」で宣言する。
      await tester.tap(find.text('通常技A').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用する'));
      await tester.pumpAndSettle();

      // 技を宣言すると防御側の返技判定ダイアログが自動で開く。
      expect(find.textContaining('宣言した'), findsOneWidget);
      expect(find.text('技を受ける'), findsOneWidget);

      await tester.tap(find.text('技を受ける'));
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

      // 【ゲームサイクル整理ラウンド 優先度2】返技には手札の返技候補カードが
      // 必要になった。Bに返技エネルギーと返技候補カード（通常技A自身。
      // reversalEnergyCost: counter1）を直接注入する（実プレイではBの手番に
      // 自分でセットする。ここではUIの配線確認が目的のため直接注入する）。
      final dynamic screenState = tester.state(find.byType(TechniqueMatchScreen));
      final TechniqueMatchState current = screenState.matchState;
      screenState.matchState = current.copyWith(
        playerB: current.playerB.copyWith(
          energyPool: const {MoveAttribute.counter: 1},
          hand: const [
            TechniqueDeckEntry(
              instanceId: 'b_counter_1',
              cardId: 'normal_1',
              cardType: TechniqueDeckCardType.technique,
            ),
          ],
        ),
      );

      await tester.tap(find.text('通常技A').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用する'));
      await tester.pumpAndSettle();

      expect(find.textContaining('[COMBO ×1]'), findsWidgets);
      expect(find.text('使用できる返技'), findsOneWidget);

      // 【次フェーズ Stage3】判定待ち中は中央RINGにATTACK/DEFENSEラベルと
      // 使用技の威力・SPEEDチップが表示される。
      expect(find.text('ATTACK'), findsOneWidget);
      expect(find.text('DEFENSE'), findsOneWidget);
      expect(find.textContaining('「通常技A」 POW10 SPD1'), findsOneWidget);

      final counterButton = find.widgetWithText(OutlinedButton, '通常技A　返×1');
      expect(counterButton, findsOneWidget);

      await tester.tap(counterButton);
      await tester.pumpAndSettle();

      // 【次フェーズ Stage3】返技成立時はCOUNTER！が中央RINGに表示される
      // （旧正規表現の不一致バグを修正）。
      expect(find.textContaining('COUNTER'), findsWidgets);
      expect(find.textContaining('攻守交代'), findsOneWidget);
      expect(find.textContaining('COMBO ×1'), findsWidgets);
      expect(find.textContaining('攻撃側'), findsWidgets);
      expect(find.text('攻防を終了する'), findsOneWidget);

      // 攻守交代後、追撃せず攻防を終了できる。優先度1により、追撃せず
      // 攻防を終了した時点で自動的にターンも終了する。
      await tester.tap(find.text('攻防を終了する'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ラリーを終了した'), findsOneWidget);
      // 次の手番へ正常に進み、ラリー・判定待ちが残っていないことを確認する
      // （Phase 8.5A: 休息ボタンは廃止済みのため状態レベルで確認する。
      // このテストのB側は本物のカードIDを認識できないtestCatalog()を使う
      // ため、Bの手番も直ちに無言で自動終了しAに戻りうる。誰の手番かでは
      // なく、決着待ちの状態が残っていないことを確認する）。
      final TechniqueMatchState afterState = screenState.matchState;
      expect(afterState.isRallyActive, isFalse);
      expect(afterState.pendingAttack, isNull);
      expect(afterState.pendingEscape, isNull);
      expect(afterState.pendingFinisher, isNull);
    });
  });

  group('TechniqueMatchScreen: 試合時間表示（Phase 8.5A-2 ⑫）', () {
    testWidgets('試合開始直後は「試合時間 0:30」がTURN表示より優先して常時表示される', (tester) async {
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

      // 1ターン目 = 30秒換算。実時間タイマー（旧30秒ターンタイマー）の
      // 復活ではなく、あくまでターン数からの換算表示であることを確認する。
      expect(find.textContaining('試合時間 0:30'), findsOneWidget);
      expect(find.textContaining('TURN 1'), findsOneWidget);

      final dynamic screenState = tester.state(find.byType(TechniqueMatchScreen));
      final TechniqueMatchState current = screenState.matchState;
      expect(current.turnNumber, 1);
    });

    testWidgets('ターン数が進むと試合時間表示もturnNumber*30秒で更新される', (tester) async {
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
      final dynamic screenState = tester.state(find.byType(TechniqueMatchScreen));
      final TechniqueMatchState current = screenState.matchState as TechniqueMatchState;
      // turnNumberを直接21へ書き換え、画面表示がformatMatchTime(21)="10:30"
      // と一致することだけを確認する（エンジンのターン進行ロジック自体は
      // 対象外。表示側の換算式のみを検証する）。setState経由で反映させる。
      screenState.setState(() {
        screenState.matchState = current.copyWith(turnNumber: 21);
      });
      await tester.pump();
      expect(find.textContaining('試合時間 10:30'), findsOneWidget);
      expect(find.textContaining('TURN 21'), findsOneWidget);
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
      await tester.tap(find.text('技を受ける'));
      await tester.pumpAndSettle();

      expect(find.textContaining('フォールの危機'), findsWidgets);
      final kickOutButton = find.widgetWithText(OutlinedButton, '通常キックアウト');
      expect(kickOutButton, findsOneWidget);

      await tester.tap(kickOutButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('を回避した'), findsOneWidget);
      // 回避が成立した時点で自動的にターンが終了し、決着待ちの状態が
      // 残っていないことを確認する（Phase 8.5A: 休息ボタンは廃止済みの
      // ため状態レベルで確認する。Bのカタログ非認識による無言自動終了の
      // 連鎖で誰の手番になるかはこのテストでは断定しない）。
      final dynamic screenStateAfter = tester.state(find.byType(TechniqueMatchScreen));
      final TechniqueMatchState stateAfter = screenStateAfter.matchState;
      expect(stateAfter.pendingEscape, isNull);
      expect(stateAfter.isRallyActive, isFalse);
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

      await tester.tap(find.text('技を受ける'));
      await tester.pumpAndSettle();

      expect(find.text('諦める（敗北を認める）'), findsOneWidget);
      await tester.tap(find.text('諦める（敗北を認める）'));
      await tester.pumpAndSettle();

      expect(find.textContaining('の勝利！'), findsOneWidget);
      expect(find.textContaining('フォール勝利'), findsWidgets);
      // 試合終了後は通常の行動ボタンが表示されない。
      expect(find.text('休息'), findsNothing);
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
          // 技エネルギーは1ターンに1枚のみセット可能（エンジンの制約）なため、
          // このテストフィクスチャは1で十分な必要量にしてある。
          attackEnergyCost: {MoveAttribute.strike: 1},
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
      expect(find.text('休息'), findsNothing);
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
      // ダメージが発生していないこと（勝敗もついていない）。キャンセル成立
      // （エスケープ）でそのターンも自動終了し、判定待ちが残っていない
      // ことを確認する（Phase 8.5A: 休息ボタンは廃止済みのため状態レベルで
      // 確認する。Bのカタログ非認識による無言自動終了の連鎖で誰の手番に
      // なるかはこのテストでは断定しない）。
      final dynamic screenStateAfter = tester.state(find.byType(TechniqueMatchScreen));
      final TechniqueMatchState stateAfter = screenStateAfter.matchState;
      expect(stateAfter.winnerIndex, isNull);
      expect(stateAfter.pendingFinisher, isNull);
      expect(stateAfter.isRallyActive, isFalse);
    });
  });

  group('TechniqueMatchScreen: CPU対戦統合（優先度7）', () {
    // 【Phase 8.5A】testCatalog()（1技のみの縮小版）だとAの実デッキ
    // （本物のカードID）を一切認識できず、有効な技もエネルギーカードも
    // 無いと判定されてAの初手から無言で自動終了してしまう。このグループは
    // 「Aの手番は人間として操作できる」ことの検証が目的のため、本物の
    // カタログを使う。
    Future<void> pumpCpuScreen(
      WidgetTester tester, {
      TechniqueDeckRepository? deckRepository,
      TechniqueDeckCardCatalog? catalog,
      TechniqueCpuPresentationSpeed cpuPresentationSpeed = TechniqueCpuPresentationSpeed.normal,
    }) async {
      await tester.binding.setSurfaceSize(const Size(800, 3000));
      await tester.pumpWidget(
        MaterialApp(
          home: TechniqueMatchScreen(
            catalog: catalog ?? buildProvisionalTechniqueDeckCatalog(),
            vsCpu: true,
            deckRepository: deckRepository,
            cpuPresentationSpeed: cpuPresentationSpeed,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('vsCpu:trueで試合を開始できる（Aの手番はいつも通り操作できる）', (tester) async {
      await pumpCpuScreen(tester);
      await tester.tap(find.text('試合開始'));
      await tester.pumpAndSettle();

      // 最初はAの手番（人間）。CPU思考中／行動状況インジケーターは出ない。
      expect(find.byKey(const Key('techniqueCpuStatusIndicator')), findsNothing);
      final dynamic screenState = tester.state(find.byType(TechniqueMatchScreen));
      final TechniqueMatchState state = screenState.matchState;
      expect(state.activePlayerIndex, 0);
    });

    // 【次フェーズ Stage2: 対面レイアウト】vsCpu時は相手（CPU、常にB）が
    // 画面上部、自分（人間、常にA）が下部に来ることを、両者の名前
    // テキストの画面上の垂直位置（dy）で確認する。
    testWidgets('vsCpu時はCPU（相手）が画面上部、人間（自分）が下部に表示される', (tester) async {
      await pumpCpuScreen(tester);
      await tester.tap(find.text('試合開始'));
      await tester.pumpAndSettle();

      final dynamic screenState = tester.state(find.byType(TechniqueMatchScreen));
      final String wrestlerAName = screenState.wrestlerA.name as String;
      final String wrestlerBName = screenState.wrestlerB.name as String;

      final aTop = tester.getTopLeft(find.text(wrestlerAName).first).dy;
      final bTop = tester.getTopLeft(find.text(wrestlerBName).first).dy;
      expect(bTop, lessThan(aTop));
    });

    testWidgets('Aがラリーを終えてBの手番になると、CPUが手札を公開せず自動的に思考・行動する', (tester) async {
      final repo = LocalTechniqueDeckRepository();
      // このテストではB（CPU）が実際に技を選べるかどうかは検証対象では
      // なく、CPUの手番へ制御が渡った際にUIが正しく振る舞う（手札を公開
      // しない・スピナー表示・行動後にログが伸びる）ことだけを見たいため、
      // 挙動を決定的にできるtestCatalog()を使う（Bの実デッキのカードIDは
      // このカタログでは認識されず、CPUは常に「有効な技が無い」と判定
      // される＝有効な技が無い場合の無言自動終了で必ずBのターンが終わる）。
      await pumpCpuScreen(tester, deckRepository: repo, catalog: testCatalog());
      final state = tester.state(find.byType(TechniqueMatchScreen));
      // ignore: avoid_dynamic_calls
      final wrestlerAId = (state as dynamic).wrestlerA.id as String;
      await repo.save(
        TechniqueDeckSaveRecord(
          deckId: 'cpu_test_deck',
          name: 'CPU対戦テスト用デッキ',
          wrestlerId: wrestlerAId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          entries: const [
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
          ],
        ),
      );
      await tester.tap(find.text('試合開始'));
      await tester.pumpAndSettle();

      await selectAndConfirm(tester, '打エネルギー', 'セットする');
      await tester.tap(find.text('通常技A').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用する'));
      await tester.pumpAndSettle();

      // Phase 8.5A: 単発ヒットだけではラリーが終わらないため、明示的に
      // 終了してBの手番へ渡す。
      await tester.tap(find.text('攻防を終了する'));
      await tester.pump();

      // Bの手番になった直後は思考中インジケーター表示のみで、手札は表示
      // されない（CPUの手札は人間に見せない）。
      expect(find.byKey(const Key('techniqueCpuStatusIndicator')), findsOneWidget);

      // 【Phase 8.5A-2 ⑪】CPUの思考ディレイ（標準速度で600ms）＋行動後の
      // 静止時間（passTurnで500ms）が経過すると、CPUが自動的に行動する
      // （有効な技が無いため無言でターンを終了し、Aの手番に戻る）。
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      await expandLog(tester);
      expect(find.textContaining('の手番'), findsWidgets);
    });

    // 【Phase 8.5A-2 ⑪】CPU演出速度は「見せ方」だけを変える設定であり、
    // CPUの意思決定・強さには影響しない。ここでは同じ局面（有効な技が無く
    // passTurnになるケース）を使い、高速(fast)なら標準(normal)より短い
    // 経過時間で手番が完了することだけを確認する。
    Future<void> reachCpuTurn(WidgetTester tester, {required TechniqueCpuPresentationSpeed speed}) async {
      final repo = LocalTechniqueDeckRepository();
      await pumpCpuScreen(
        tester,
        deckRepository: repo,
        catalog: testCatalog(),
        cpuPresentationSpeed: speed,
      );
      final state = tester.state(find.byType(TechniqueMatchScreen));
      // ignore: avoid_dynamic_calls
      final wrestlerAId = (state as dynamic).wrestlerA.id as String;
      await repo.save(
        TechniqueDeckSaveRecord(
          deckId: 'cpu_speed_test_deck',
          name: 'CPU演出速度テスト用デッキ',
          wrestlerId: wrestlerAId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          entries: const [
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
          ],
        ),
      );
      await tester.tap(find.text('試合開始'));
      await tester.pumpAndSettle();
      await selectAndConfirm(tester, '打エネルギー', 'セットする');
      await tester.tap(find.text('通常技A').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用する'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('攻防を終了する'));
      await tester.pump();
    }

    testWidgets('CPU演出速度「高速」は「標準」より短い経過時間でCPUの手番が完了する', (tester) async {
      // 高速(0.5倍): think 600ms*0.5=300ms + passTurnの静止 500ms*0.5=250ms
      // = 合計550ms。600ms待てば完了しているはず。
      await reachCpuTurn(tester, speed: TechniqueCpuPresentationSpeed.fast);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('techniqueCpuStatusIndicator')), findsNothing);
    });

    testWidgets('CPU演出速度「標準」は同じ600msではまだCPUの手番の途中', (tester) async {
      // 標準(1.0倍): think 600ms + passTurnの静止 500ms = 合計1100ms。
      // 600ms時点ではまだ静止（結果表示）待ちの途中のはず。
      await reachCpuTurn(tester, speed: TechniqueCpuPresentationSpeed.normal);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('techniqueCpuStatusIndicator')), findsOneWidget);
      // 残りの静止時間も進めれば完了する（後始末としてpumpAndSettleする）。
      await tester.pumpAndSettle();
    });

    testWidgets('CPUの遅延コールバック待機中にウィジェットが破棄されても例外にならない', (tester) async {
      await reachCpuTurn(tester, speed: TechniqueCpuPresentationSpeed.normal);
      // CPUの思考中インジケーターが出ている（=まだ_cpuTimer/_cpuHoldTimerが
      // 保留中の）状態で、ウィジェットツリーを丸ごと差し替える（Navigator.pop
      // 相当のdisposeを模擬）。
      expect(find.byKey(const Key('techniqueCpuStatusIndicator')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
      // dispose済みでも保留中のタイマーが発火しうる時間まで進めるが、
      // mountedチェックにより例外や不正なsetStateは起きないはず。
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });
  });
}
