// Combat Ver.1 Phase 1: Core Skeletonの最小戦闘ループを検証する
// （docs/combat_rules_v1.md、docs/design/combat_v1_phase1_design.md）。
//
// 方針:
// - Match初期化／ターン進行の骨格（discard→action→turnEnd相当の内部遷移）
//   は CombatV1Engine.start / discardCard / endTurn を実際に呼び出して検証
//   する（discardCard/endTurnはどの具体的なカードが手札にあるかに依存しない
//   ため、フィクスチャデッキの実際のシャッフル結果に依存せず決定的に書ける）。
// - TECHNIQUEのCOST支払い・DMG・HEAT・状態遷移など「特定の技を使う」検証は、
//   `buildActionState`で手札の中身を直接指定した状態を組み立ててから
//   `playTechnique`を呼ぶ（シャッフル結果に依存しない決定的なテストにする
//   ため）。CombatV1PlayerState/CombatV1MatchStateはイミュータブルな値
//   オブジェクトであり、この直接構築は正当な使い方である。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';

import 'combat_v1_test_fixtures.dart';

/// `phase == action`・playerAが手番、というテスト用の最小状態を直接組み立てる。
/// 山札・捨て札の中身には依存しない検証をしたいテストで使う。
CombatV1MatchState buildActionState({
  List<CombatV1DeckEntry> handA = const [],
  List<CombatV1DeckEntry> drawPileA = const [],
  List<CombatV1DeckEntry> handB = const [],
  int hpA = 150,
  int hpB = 150,
  Map<CombatV1EnergyAttribute, int> spentA = const {},
  CombatV1WrestlerPosture postureB = CombatV1WrestlerPosture.stand,
  int sharedHeat = 0,
}) {
  final playerA = CombatV1PlayerState(
    wrestlerId: fixtureWrestlerA.id,
    wrestlerName: fixtureWrestlerA.name,
    maxHp: 150,
    hp: hpA,
    koc: 10,
    pinCardsHeld: 2,
    energyPool: fixtureWrestlerA.energyPool,
    spentEnergy: spentA,
    hand: handA,
    drawPile: drawPileA,
  );
  final playerB = CombatV1PlayerState(
    wrestlerId: fixtureWrestlerB.id,
    wrestlerName: fixtureWrestlerB.name,
    maxHp: 150,
    hp: hpB,
    koc: 10,
    pinCardsHeld: 2,
    posture: postureB,
    energyPool: fixtureWrestlerB.energyPool,
    hand: handB,
  );
  return CombatV1MatchState(
    matchId: 'test-match',
    playerA: playerA,
    playerB: playerB,
    activePlayerIndex: 0,
    sharedHeat: sharedHeat,
    turnNumber: 1,
    phase: CombatV1MatchPhase.action,
  );
}

void main() {
  group('CombatV1Engine.start — Match初期化', () {
    late CombatV1MatchState state;

    setUp(() {
      state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck('fx_wrestler_a'),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck('fx_wrestler_b'),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(1),
      );
    });

    test('先攻(playerA)のターン開始処理まで完了し、discardフェーズになる', () {
      expect(state.phase, CombatV1MatchPhase.discard);
      expect(state.activePlayerIndex, 0);
      expect(state.turnNumber, 1);
    });

    test('HPは全レスラー共通で150に初期化される', () {
      expect(state.playerA.hp, 150);
      expect(state.playerA.maxHp, 150);
      expect(state.playerB.hp, 150);
      expect(state.playerB.maxHp, 150);
    });

    test('KOCは10に初期化される', () {
      expect(state.playerA.koc, 10);
      expect(state.playerB.koc, 10);
    });

    test('PIN CARDは両者2枚ずつに初期化される', () {
      expect(state.playerA.pinCardsHeld, 2);
      expect(state.playerB.pinCardsHeld, 2);
    });

    test('共有HEATは0で初期化される', () {
      expect(state.sharedHeat, 0);
    });

    test('ENERGYはレスラー固有のプール通りに初期化される', () {
      for (final attribute in CombatV1EnergyAttribute.values) {
        expect(
          state.playerA.availableEnergyFor(attribute),
          fixtureWrestlerA.energyPool.amountFor(attribute),
        );
        expect(
          state.playerB.availableEnergyFor(attribute),
          fixtureWrestlerB.energyPool.amountFor(attribute),
        );
      }
    });

    test('初期手札は5枚配られる', () {
      // playerBはまだ自分の手番のターン開始処理（1ドロー）を経ていないため、
      // 配られた初期手札5枚がそのまま観測できる。
      expect(state.playerB.hand.length, 5);
      // playerA（先攻）はstart()の中で最初のターン開始処理（1ドロー）まで
      // 完了しているため、初期手札5枚+ターン開始ドロー1枚=6枚になる
      // （docs/combat_rules_v1.md 4章のターン進行に「初期手札5枚」の直後に
      // 「ターン開始→…→1枚ドロー」と続くため、先攻1ターン目も例外なく
      // この手順を踏む）。
      expect(state.playerA.hand.length, 6);
    });

    test('デッキ構成に一致しないデッキではstartがCombatV1IllegalActionExceptionを投げる', () {
      final brokenDeck = CombatV1DeckDefinition(
        wrestlerId: 'broken',
        entries: fixtureDeck('broken').entries.take(29).toList(),
      );
      expect(
        () => CombatV1Engine.start(
          wrestlerA: fixtureWrestlerA,
          deckA: brokenDeck,
          wrestlerB: fixtureWrestlerB,
          deckB: fixtureDeck('fx_wrestler_b'),
          rules: fixtureRules,
          catalog: fixtureCatalog,
          random: Random(1),
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('ターン進行（discard→action→turnEnd相当の内部遷移）', () {
    test('discardCardは手札を1枚減らし、捨て札へ送り、phaseをactionへ進める', () {
      var state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck('fx_wrestler_a'),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck('fx_wrestler_b'),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(1),
      );
      final handSizeBefore = state.playerA.hand.length;
      final discardSizeBefore = state.playerA.discardPile.length;
      final instanceId = state.playerA.hand.first.instanceId;

      state = CombatV1Engine.discardCard(state, instanceId);

      expect(state.phase, CombatV1MatchPhase.action);
      expect(state.playerA.hand.length, handSizeBefore - 1);
      expect(state.playerA.discardPile.length, discardSizeBefore + 1);
      expect(
        state.playerA.discardPile.any((e) => e.instanceId == instanceId),
        isTrue,
      );
    });

    test('endTurnで手番が交代し、新しい手番プレイヤーはENERGY全回復・1ドローを行う', () {
      var state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck('fx_wrestler_a'),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck('fx_wrestler_b'),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(1),
      );

      // playerAが一部ENERGYを消費済みという状況を直接組み立てる
      // （手札の中身に依存しないテストにするため）。
      state = state.withActive(
        state.playerA.copyWith(
          spentEnergy: const {CombatV1EnergyAttribute.strike: 2},
        ),
      );
      expect(state.playerA.availableEnergyFor(CombatV1EnergyAttribute.strike), 1);

      final playerBHandBefore = state.playerB.hand.length;

      state = CombatV1Engine.discardCard(state, state.active.hand.first.instanceId);
      state = CombatV1Engine.endTurn(state, random: Random(2));

      expect(state.activePlayerIndex, 1);
      expect(state.turnNumber, 2);
      expect(state.phase, CombatV1MatchPhase.discard);
      expect(state.playerB.hand.length, playerBHandBefore + 1); // ターン開始1ドロー

      state = CombatV1Engine.discardCard(state, state.active.hand.first.instanceId);
      state = CombatV1Engine.endTurn(state, random: Random(3));

      expect(state.activePlayerIndex, 0);
      expect(state.turnNumber, 3);
      // ENERGY全回復（使用済みが0へ戻る）。
      expect(state.playerA.spentEnergy[CombatV1EnergyAttribute.strike] ?? 0, 0);
      expect(state.playerA.availableEnergyFor(CombatV1EnergyAttribute.strike), 3);
    });

    test('discardフェーズ以外でdiscardCardを呼ぶとCombatV1IllegalActionExceptionを投げる', () {
      final state = buildActionState(); // phase == action
      expect(
        () => CombatV1Engine.discardCard(state, 'dummy'),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('actionフェーズ以外でplayTechnique/endTurnを呼ぶとCombatV1IllegalActionExceptionを投げる', () {
      final state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck('fx_wrestler_a'),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck('fx_wrestler_b'),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(1),
      ); // phase == discard

      expect(
        () => CombatV1Engine.playTechnique(
          state,
          'dummy',
          techniques: fixtureTechniques,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(
        () => CombatV1Engine.endTurn(state),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('playTechnique — TECHNIQUE使用', () {
    test('ENERGY COSTを支払い、支払い済みENERGYへ反映する', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildActionState(handA: [entry]);

      final next = CombatV1Engine.playTechnique(
        state,
        'a1',
        techniques: fixtureTechniques,
      );

      expect(next.playerA.spentEnergy[CombatV1EnergyAttribute.strike], 1);
    });

    test('DMGが相手HPへ即時反映され、共有HEATが加算される', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike', // damage 10, heatGain 10
        category: CombatV1CardCategory.normal,
      );
      final state = buildActionState(handA: [entry], hpB: 150, sharedHeat: 0);

      final next = CombatV1Engine.playTechnique(
        state,
        'a1',
        techniques: fixtureTechniques,
      );

      expect(next.playerB.hp, 140);
      expect(next.sharedHeat, 10);
    });

    test('使用したカードは手札から除かれ捨て札へ送られ、使用後に1枚ドローする', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final drawCard = const CombatV1DeckEntry(
        instanceId: 'a2',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildActionState(handA: [entry], drawPileA: [drawCard]);

      final next = CombatV1Engine.playTechnique(
        state,
        'a1',
        techniques: fixtureTechniques,
        random: Random(1),
      );

      expect(next.playerA.hand.any((e) => e.instanceId == 'a1'), isFalse);
      expect(
        next.playerA.discardPile.any((e) => e.instanceId == 'a1'),
        isTrue,
      );
      // 使用直後の1ドローにより、drawPileにあったカードが手札へ移る。
      expect(next.playerA.hand.any((e) => e.instanceId == 'a2'), isTrue);
      expect(next.playerA.drawPile, isEmpty);
    });

    test('HPは0未満にならず（クランプ）、HP0でも試合は継続する', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_throw_down', // damage 20
        category: CombatV1CardCategory.normal,
      );
      final state = buildActionState(handA: [entry], hpB: 15);

      final next = CombatV1Engine.playTechnique(
        state,
        'a1',
        techniques: fixtureTechniques,
      );

      expect(next.playerB.hp, 0); // 15 - 20 は -5 だが 0 でクランプされる

      // HP0でも「勝敗」を表すフィールド自体がCombatV1MatchStateに存在せず
      // （docs/design/combat_v1_phase1_design.md 2.6章）、試合はそのまま
      // 継続できることを、実際にターンを進められることで示す。
      final afterEndTurn = CombatV1Engine.endTurn(next);
      expect(afterEndTurn.activePlayerIndex, 1);
      expect(afterEndTurn.turnNumber, 2);
    });

    test('同一ターン内でENERGYが残っていれば複数回TECHNIQUEを使用できる', () {
      final first = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike', // 打1消費, damage10, heat10
        category: CombatV1CardCategory.normal,
      );
      final second = const CombatV1DeckEntry(
        instanceId: 'a2',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      // fixtureWrestlerAの打ENERGYは3なので、打1コストの技を複数回使える。
      final state = buildActionState(handA: [first, second]);

      var next = CombatV1Engine.playTechnique(
        state,
        'a1',
        techniques: fixtureTechniques,
      );
      expect(next.phase, CombatV1MatchPhase.action); // ターンは終了しない
      expect(next.playerB.hp, 140);

      next = CombatV1Engine.playTechnique(
        next,
        'a2',
        techniques: fixtureTechniques,
      );
      expect(next.phase, CombatV1MatchPhase.action);
      expect(next.playerB.hp, 130); // ダメージが累積する
      expect(next.sharedHeat, 20); // HEATも累積する
      expect(next.playerA.spentEnergy[CombatV1EnergyAttribute.strike], 2);
    });

    test('単一属性の不足分をワイルド(＊)で補って使用できる', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_combo_cost', // 打2 + 投1
        category: CombatV1CardCategory.normal,
      );
      // fixtureWrestlerAの打は3。すでに2消費済みで残り1、＊は2残っている
      // 想定を作り、打の不足分1を＊で補う。
      final state = buildActionState(
        handA: [entry],
        spentA: const {CombatV1EnergyAttribute.strike: 2},
      );

      final next = CombatV1Engine.playTechnique(
        state,
        'a1',
        techniques: fixtureTechniques,
      );

      expect(next.playerA.spentEnergy[CombatV1EnergyAttribute.strike], 3); // 3使用済み(残り0)
      expect(next.playerA.spentEnergy[CombatV1EnergyAttribute.throwing], 1);
      expect(next.playerA.spentEnergy[CombatV1EnergyAttribute.wild], 1); // 打の不足1を＊で補完
    });

    test('複数属性の不足分を合算してワイルド(＊)で補って使用できる', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_combo_cost', // 打2 + 投1
        category: CombatV1CardCategory.normal,
      );
      // 打・投とも既にほぼ使い切っており、合計2の不足を＊2で補う。
      final state = buildActionState(
        handA: [entry],
        spentA: const {
          CombatV1EnergyAttribute.strike: 2, // 残り1（コスト2に対して1不足）
          CombatV1EnergyAttribute.throwing: 2, // 残り0（コスト1に対して1不足）
        },
      );

      final next = CombatV1Engine.playTechnique(
        state,
        'a1',
        techniques: fixtureTechniques,
      );

      expect(next.playerA.spentEnergy[CombatV1EnergyAttribute.wild], 2);
    });

    test('ENERGYが不足していれば使用できない（checkTechniqueLegalityとplayTechnique両方）', () {
      final expensive = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_overpriced',
        category: CombatV1CardCategory.normal,
      );
      final techniques = {
        ...fixtureTechniques,
        'fx_overpriced': const CombatV1Technique(
          id: 'fx_overpriced',
          name: 'テスト超高コスト技',
          category: CombatV1CardCategory.normal,
          attribute: CombatV1EnergyAttribute.strike,
          energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 99}),
          damage: 10,
          heatGain: 10,
        ),
      };
      final state = buildActionState(handA: [expensive]);

      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'a1',
        techniques: techniques,
      );
      expect(check.legal, isFalse);

      expect(
        () => CombatV1Engine.playTechnique(state, 'a1', techniques: techniques),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('手札に存在しないカードを指定するとCombatV1IllegalActionExceptionを投げる', () {
      final state = buildActionState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
        ],
      );

      expect(
        () => CombatV1Engine.playTechnique(
          state,
          'not_in_hand',
          techniques: fixtureTechniques,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('相手の状態条件を満たさない技は使用できない', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_ground', // requiredOpponentState == down
        category: CombatV1CardCategory.normal,
      );
      final state = buildActionState(
        handA: [entry],
        postureB: CombatV1WrestlerPosture.stand, // downではない
      );

      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'a1',
        techniques: fixtureTechniques,
      );
      expect(check.legal, isFalse);

      expect(
        () => CombatV1Engine.playTechnique(
          state,
          'a1',
          techniques: fixtureTechniques,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );

      // 相手がdown状態なら使用できる。
      final downState = buildActionState(
        handA: [entry],
        postureB: CombatV1WrestlerPosture.down,
      );
      expect(
        CombatV1Engine.checkTechniqueLegality(
          downState,
          'a1',
          techniques: fixtureTechniques,
        ).legal,
        isTrue,
      );
    });

    test('COUNTERカードはTECHNIQUEとして使用できない', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_counter_a',
        category: CombatV1CardCategory.counter,
      );
      final state = buildActionState(handA: [entry]);

      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'a1',
        techniques: fixtureTechniques,
      );
      expect(check.legal, isFalse);
    });
  });

  group('山札再構築・FATIGUE無し', () {
    test('山札が空になると捨て札をシャッフルして再構築し、HP/HEATは変化しない（FATIGUEなし）', () {
      const smallComposition = CombatV1DeckComposition(
        normalCount: 5,
        signatureCount: 0,
        finisherCount: 0,
        counterCount: 0,
      );
      const smallRules = CombatV1RulesConfig(
        startingHandSize: 2,
        deckComposition: smallComposition,
        // このテストは同名カード1種のみで山札を構成する
        // （山札再構築の検証に本質的でない同名上限の影響を避けるため、
        // Phase 2で追加されたNORMAL同名上限（既定3枚）を超えて許容する）。
        normalSameNameLimit: 5,
      );

      CombatV1DeckDefinition smallDeck(String wrestlerId) => CombatV1DeckDefinition(
        wrestlerId: wrestlerId,
        entries: [
          for (var i = 0; i < 5; i++)
            CombatV1DeckEntry(
              instanceId: '${wrestlerId}_card_$i',
              cardId: 'fx_normal_strike',
              category: CombatV1CardCategory.normal,
            ),
        ],
      );

      var state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: smallDeck('small_a'),
        wrestlerB: fixtureWrestlerB,
        deckB: smallDeck('small_b'),
        rules: smallRules,
        catalog: fixtureCatalog,
        random: Random(7),
      );

      final initialHpA = state.playerA.hp;
      final initialHpB = state.playerB.hp;
      final initialHeat = state.sharedHeat;

      int totalCardsFor(CombatV1PlayerState player) =>
          player.drawPile.length + player.hand.length + player.discardPile.length;

      expect(totalCardsFor(state.playerA), 5);
      expect(totalCardsFor(state.playerB), 5);

      // TECHNIQUEは一切使わず、discardCard→endTurnのみで手札循環を繰り返し、
      // playerAの山札を再構築させる。
      for (var i = 0; i < 12; i++) {
        state = CombatV1Engine.discardCard(state, state.active.hand.first.instanceId);
        state = CombatV1Engine.endTurn(state, random: Random(100 + i));
      }

      expect(state.playerA.reshuffleCount, greaterThan(0));
      // 捨て札・除外の仕組みが無いため、総カード枚数は常に保存される。
      expect(totalCardsFor(state.playerA), 5);
      expect(totalCardsFor(state.playerB), 5);
      // FATIGUEペナルティ（HP減少・HEAT増加）が発生していないことを確認。
      expect(state.playerA.hp, initialHpA);
      expect(state.playerB.hp, initialHpB);
      expect(state.sharedHeat, initialHeat);
    });
  });
}
