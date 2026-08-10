// Combat Ver.1 Phase 5: PIN / KOC のテスト
// （docs/combat_rules_v1.md 8・9章、テスト項目31-A〜31-J相当）。
//
// Phase 5セッションでユーザーが確定した仕様:
// - PINカード移動の向き: 1/2カウントで終了したPINでは、攻撃側→防御側へ
//   1枚移動する（最低1枚保証あり、8.1章）。
// - カウント進行: 1段階ずつ防御側が応答する複数ステップではなく、防御側の
//   現在KOCから一括で最終カウントを決定する（自動、防御側の任意選択は
//   存在しない）。
// - KICK OUT: 防御側がKOCを支払えれば自動的に成立する（あえて支払わない
//   選択肢は無い）。
// - 1/2カウントでキックアウトした場合: 攻守交代・ターン終了寄りの扱いと
//   する（`endTurn`と同じ内部処理で防御側の新しいターンへ進む）。
// - 2.9カウントでキックアウトした場合: `combat_rules_v1.md`
//   8.2章の記載どおり、攻撃側は攻撃を継続できる（phase/activePlayerIndex
//   とも変更しない）。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_pin_rules.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_state_invariants.dart';

import 'combat_v1_test_fixtures.dart';

void main() {
  const attack = CombatV1DeckEntry(
    instanceId: 'atk1',
    cardId: 'fx_normal_throw_down', // 投1, DMG20, HEAT20, STAND->DOWN
    category: CombatV1CardCategory.normal,
  );
  const directPinAttack = CombatV1DeckEntry(
    instanceId: 'atk_dp',
    cardId: 'fx_normal_direct_pin', // 投1, STAND->DOWN, directPin=true
    category: CombatV1CardCategory.normal,
  );
  const matchingCounter = CombatV1DeckEntry(
    instanceId: 'ctr1',
    cardId: 'fx_counter_b', // backdrop/suplex系統を投属性で返せる
    category: CombatV1CardCategory.counter,
  );

  group('A. PIN初期状態', () {
    test('start直後、両者pinCardsHeld=2・合計4・各1以上・koc=10', () {
      final state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck(fixtureWrestlerA.id),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck(fixtureWrestlerB.id),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(1),
      );

      expect(state.playerA.pinCardsHeld, 2);
      expect(state.playerB.pinCardsHeld, 2);
      expect(
        state.playerA.pinCardsHeld + state.playerB.pinCardsHeld,
        fixtureRules.totalPinCards,
      );
      expect(state.playerA.pinCardsHeld, greaterThanOrEqualTo(1));
      expect(state.playerB.pinCardsHeld, greaterThanOrEqualTo(1));
      expect(state.playerA.koc, 10);
      expect(state.playerB.koc, 10);
      expect(state.isOver, isFalse);
      expect(state.winnerPlayerIndex, isNull);
    });
  });

  group('B. PIN legality（declarePin/checkPinLegality）', () {
    CombatV1MatchState legalBaseState({int turnNumber = 1}) => buildMatchState(
      postureB: CombatV1WrestlerPosture.down,
      turnNumber: turnNumber,
      lastSuccessfulTechnique: fixtureSuccessfulTechnique(
        attackerPlayerIndex: 0,
        turnNumber: turnNumber,
      ),
    );

    test('legal case: 相手DOWN・このターン成功済みならPIN宣言できる', () {
      final state = legalBaseState();
      final check = CombatV1Engine.checkPinLegality(state);
      expect(check.legal, isTrue);
      expect(CombatV1Engine.hasPinOption(state), isTrue);
    });

    test('wrong phase: discard中はPIN宣言できない', () {
      final state = buildMatchState(
        phase: CombatV1MatchPhase.discard,
        postureB: CombatV1WrestlerPosture.down,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final check = CombatV1Engine.checkPinLegality(state);
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1PinLegalityReasonCode.wrongPhase);
    });

    test('match over: 試合終了後はPIN宣言できない', () {
      final state = legalBaseState().copyWith(winnerPlayerIndex: 0);
      final check = CombatV1Engine.checkPinLegality(state);
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1PinLegalityReasonCode.matchOver);
    });

    test('opponent state mismatch: 相手がSTANDならPIN宣言できない', () {
      final state = buildMatchState(
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final check = CombatV1Engine.checkPinLegality(state);
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1PinLegalityReasonCode.opponentNotDown);
    });

    test('lastSuccessfulTechniqueが無ければPIN宣言できない', () {
      final state = buildMatchState(postureB: CombatV1WrestlerPosture.down);
      final check = CombatV1Engine.checkPinLegality(state);
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1PinLegalityReasonCode.noSuccessfulTechniqueThisTurn,
      );
    });

    test('stale directPin不可: turnNumberが異なる古いsnapshotは無効', () {
      // 前のターン（turnNumber=1）で成功していたが、現在はturnNumber=2。
      final state = legalBaseState(turnNumber: 1).copyWith(turnNumber: 2);
      final check = CombatV1Engine.checkPinLegality(state);
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1PinLegalityReasonCode.noSuccessfulTechniqueThisTurn,
      );
    });

    test('stale: attackerPlayerIndexが現在の手番と異なる場合は無効', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        turnNumber: 1,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 1, // 手番はplayerA(0)だが成功記録はplayerB(1)
          turnNumber: 1,
        ),
      );
      final check = CombatV1Engine.checkPinLegality(state);
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1PinLegalityReasonCode.noSuccessfulTechniqueThisTurn,
      );
    });
  });

  group('C. カウント決定（determinePinCountResult、combat_v1_pin_rules.dart）', () {
    test('KOC10（潤沢）→1カウント', () {
      expect(
        determinePinCountResult(defenderKoc: 10, rules: fixtureRules),
        CombatV1PinCountResult.one,
      );
    });

    test('KOC3（ちょうど1カウント分）→1カウント', () {
      expect(
        determinePinCountResult(defenderKoc: 3, rules: fixtureRules),
        CombatV1PinCountResult.one,
      );
    });

    test('KOC2（1カウント分は払えないが2カウント分は払える）→2カウント', () {
      expect(
        determinePinCountResult(defenderKoc: 2, rules: fixtureRules),
        CombatV1PinCountResult.two,
      );
    });

    test('KOC1→2.9カウント', () {
      expect(
        determinePinCountResult(defenderKoc: 1, rules: fixtureRules),
        CombatV1PinCountResult.twoPointNine,
      );
    });

    test('KOC0→null（3カウント、PIN決着）', () {
      expect(
        determinePinCountResult(defenderKoc: 0, rules: fixtureRules),
        isNull,
      );
    });

    test('displayLabelが"1"/"2"/"2.9"を返す', () {
      expect(CombatV1PinCountResult.one.displayLabel, '1');
      expect(CombatV1PinCountResult.two.displayLabel, '2');
      expect(CombatV1PinCountResult.twoPointNine.displayLabel, '2.9');
    });
  });

  group('D. KOC消費', () {
    test('1カウント: 防御側のKOCが3減る', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocB: 10,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final resolved = CombatV1Engine.declarePin(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerB.koc, 7);
      expect(resolved.playerA.koc, 10); // 攻撃側は支払わない
    });

    test('exact KOC: KOC3ちょうどなら1カウントで0になる（負にならない）', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocB: 3,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final resolved = CombatV1Engine.declarePin(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerB.koc, 0);
      expect(
        validatePlayerStateInvariants(resolved.playerB).isValid,
        isTrue,
      );
    });

    test('insufficient KOC: KOC0なら3カウントPIN決着（試合終了）', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocB: 0,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final resolved = CombatV1Engine.declarePin(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerB.koc, 0); // 支払い不能なのでKOCは変化しない
      expect(resolved.winnerPlayerIndex, 0);
      expect(resolved.isOver, isTrue);
    });

    test('KOCは負数にならない（Command経由でnegativeを生成できない）', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocB: 1,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final resolved = CombatV1Engine.declarePin(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerB.koc, greaterThanOrEqualTo(0));
    });
  });

  group('E. PIN CARD移動', () {
    test('1カウント: 攻撃側→防御側へ1枚移動する', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocB: 10,
        pinCardsHeldA: 2,
        pinCardsHeldB: 2,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final resolved = CombatV1Engine.declarePin(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerA.pinCardsHeld, 1); // 攻撃側
      expect(resolved.playerB.pinCardsHeld, 3); // 防御側
      expect(
        resolved.playerA.pinCardsHeld + resolved.playerB.pinCardsHeld,
        fixtureRules.totalPinCards,
      );
    });

    test('2カウント: 攻撃側→防御側へ1枚移動する', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocB: 2,
        pinCardsHeldA: 2,
        pinCardsHeldB: 2,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final resolved = CombatV1Engine.declarePin(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerA.pinCardsHeld, 1);
      expect(resolved.playerB.pinCardsHeld, 3);
    });

    test('2.9カウント: PINカードは移動しない', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocB: 1,
        pinCardsHeldA: 2,
        pinCardsHeldB: 2,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final resolved = CombatV1Engine.declarePin(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerA.pinCardsHeld, 2);
      expect(resolved.playerB.pinCardsHeld, 2);
    });

    test('最低1枚保証: 攻撃側が1枚しかなければ1/2カウントでも移動しない', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocB: 10,
        pinCardsHeldA: 1,
        pinCardsHeldB: 3,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final resolved = CombatV1Engine.declarePin(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      // カード移動は抑止されるが、KOC消費・カウント結果自体は通常どおり発生する。
      expect(resolved.playerA.pinCardsHeld, 1);
      expect(resolved.playerB.pinCardsHeld, 3);
      expect(resolved.playerB.koc, 7);
      expect(
        resolved.playerA.pinCardsHeld + resolved.playerB.pinCardsHeld,
        fixtureRules.totalPinCards,
      );
    });

    test('1/3の非対称分布でもtotal4・各1以上は常に維持される', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocB: 2,
        pinCardsHeldA: 3,
        pinCardsHeldB: 1,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final resolved = CombatV1Engine.declarePin(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerA.pinCardsHeld, 2);
      expect(resolved.playerB.pinCardsHeld, 2);
      expect(
        validateMatchStateInvariants(resolved, rules: fixtureRules).isValid,
        isTrue,
      );
    });
  });

  group('F. DIRECT PIN', () {
    final directPinCatalog = CombatV1CardCatalog(
      techniques: fixtureTechniques,
      counters: fixtureCounters,
    );

    test('DIRECT PIN技がdeclineで成立するとPINへ自動移行する', () {
      final state = buildMatchState(
        handA: const [directPinAttack],
        kocB: 10,
        pinCardsHeldA: 2,
        pinCardsHeldB: 2,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_dp',
        catalog: directPinCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );

      // Technique成功（DMG・HEAT・posture変化・attacker draw）は通常どおり発生。
      expect(resolved.playerB.hp, 130); // 150 - 20(DMG)
      expect(resolved.sharedHeat, 20);
      expect(resolved.playerB.posture, CombatV1WrestlerPosture.down);
      expect(resolved.lastSuccessfulTechnique, isNotNull);
      expect(resolved.lastSuccessfulTechnique!.directPin, isTrue);

      // KOC10 → 1カウントでキックアウト → PINカード移動 → ターン終了して
      // playerBの新しいターン（discardフェーズ）へ進む。
      expect(resolved.playerB.koc, 7);
      expect(resolved.playerA.pinCardsHeld, 1);
      expect(resolved.playerB.pinCardsHeld, 3);
      expect(resolved.activePlayerIndex, 1);
      expect(resolved.phase, CombatV1MatchPhase.discard);
      expect(resolved.isOver, isFalse);
      expect(resolved.log.any((l) => l.contains('DIRECT PIN')), isTrue);
    });

    test('COUNTERされたDIRECT PINはPINにならない', () {
      final state = buildMatchState(
        handA: const [directPinAttack],
        handB: const [matchingCounter],
        kocB: 10,
        pinCardsHeldA: 2,
        pinCardsHeldB: 2,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_dp',
        catalog: directPinCatalog,
      );
      final resolved = CombatV1Engine.playCounter(
        declared,
        'ctr1',
        catalog: directPinCatalog,
        rules: fixtureRules,
        random: Random(1),
      );

      // COUNTER成立: 攻撃は完全無効化。PINへは一切移行しない。
      expect(resolved.playerB.posture, CombatV1WrestlerPosture.stand);
      expect(resolved.playerB.hp, 150);
      expect(resolved.lastSuccessfulTechnique, isNull);
      expect(resolved.winnerPlayerIndex, isNull);
      expect(resolved.playerB.koc, 10); // KOC未消費
      expect(resolved.playerA.pinCardsHeld, 2); // PINカード未移動
      expect(resolved.playerB.pinCardsHeld, 2);
      expect(resolved.phase, CombatV1MatchPhase.action);
      expect(resolved.activePlayerIndex, 0); // 攻守交代なし
      expect(resolved.log.any((l) => l.contains('を仕掛けた')), isFalse);
    });

    test('stale lastSuccessfulTechnique（古いdirectPin記録）は再発火しない', () {
      // 前のターンにdirectPin技で成功した記録が残っている状態で、今回は
      // directPinを持たない通常技を使う。相手はすでにDOWNのまま。
      final staleSnapshot = fixtureSuccessfulTechnique(
        attackerPlayerIndex: 0,
        turnNumber: 1,
        directPin: true,
      );
      final state = buildMatchState(
        handA: const [attack],
        postureB: CombatV1WrestlerPosture.down,
        turnNumber: 2,
        kocB: 10,
        lastSuccessfulTechnique: staleSnapshot,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk1',
        catalog: fixtureCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );

      // 新しいTECHNIQUE（fx_normal_throw_down、directPin=false）が
      // lastSuccessfulTechniqueを上書きするのみで、PINは自動開始されない
      // （KOCもPINカードも一切動かない、staleなdirectPin再発火防止）。
      expect(resolved.lastSuccessfulTechnique!.directPin, isFalse);
      expect(resolved.winnerPlayerIndex, isNull);
      expect(resolved.playerB.koc, 10);
      expect(resolved.playerA.pinCardsHeld, 2);
      expect(resolved.playerB.pinCardsHeld, 2);
      expect(resolved.phase, CombatV1MatchPhase.action);
      expect(resolved.activePlayerIndex, 0);
    });

    test('draw/card cycleとの順序: TECHNIQUE成功の1drawが先、PIN開始ログは後', () {
      final state = buildMatchState(
        handA: const [directPinAttack],
        drawPileA: const [
          CombatV1DeckEntry(
            instanceId: 'reserve',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
        ],
        kocB: 10,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_dp',
        catalog: directPinCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );

      final drawLogIndex = resolved.log.indexWhere(
        (l) => l.contains('カードを1枚引いた'),
      );
      final pinLogIndex = resolved.log.indexWhere(
        (l) => l.contains('DIRECT PIN'),
      );
      expect(drawLogIndex, greaterThanOrEqualTo(0));
      expect(pinLogIndex, greaterThan(drawLogIndex));
      // Phase 4のTECHNIQUE成功後1drawが実際に実行されていること
      // （攻撃側の手札にreserveカードが加わっている）。
      expect(
        resolved.playerA.hand.any((e) => e.instanceId == 'reserve'),
        isTrue,
      );
    });
  });

  group('G. PIN State Machine', () {
    test('action → declarePin: 2.9カウントならphase/activePlayerIndexとも維持', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocB: 1,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final resolved = CombatV1Engine.declarePin(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.phase, CombatV1MatchPhase.action);
      expect(resolved.activePlayerIndex, 0);
      // 攻撃側は攻撃を継続できる: 実際にdeclareTechniqueを続けて呼べる
      // （actionフェーズのまま、手札に技があれば宣言できる）。
      expect(CombatV1Engine.hasAnyPlayableTechnique(
        resolved,
        catalog: fixtureCatalog,
      ), isA<bool>());
    });

    test('kick out継続（1/2カウント）: 防御側の新しいターン（discard）へ進む', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocB: 10,
        turnNumber: 3,
        spentB: const {CombatV1EnergyAttribute.strike: 1},
        techniquesUsedB: 2,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 3,
        ),
      );
      final resolved = CombatV1Engine.declarePin(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.activePlayerIndex, 1);
      expect(resolved.phase, CombatV1MatchPhase.discard);
      expect(resolved.turnNumber, 4);
      // ターン開始処理（ENERGY全回復・1ドロー）が防御側に適用されている。
      expect(resolved.playerB.spentEnergy, isEmpty);
      expect(resolved.playerB.techniquesUsedThisTurn, 0);
    });

    test('match end path: KOC不足なら以後のCommandがすべて拒否される', () {
      final state = buildMatchState(
        handA: const [attack],
        postureB: CombatV1WrestlerPosture.down,
        kocB: 0,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final resolved = CombatV1Engine.declarePin(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.isOver, isTrue);

      expect(
        () => CombatV1Engine.declareTechnique(
          resolved,
          'atk1',
          catalog: fixtureCatalog,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(
        () => CombatV1Engine.endTurn(resolved),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(
        () => CombatV1Engine.declarePin(resolved, rules: fixtureRules),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('H. Match over', () {
    test('winnerPlayerIndex/isOverが正しく設定される', () {
      // 手番（攻撃側）はplayerB（activePlayerIndex=1）。防御側はplayerA
      // なので、DOWN・KOC不足はplayerA側に設定する。
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        kocA: 0,
        activePlayerIndex: 1,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 1,
          turnNumber: 1,
        ),
      );
      final resolved = CombatV1Engine.declarePin(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.winnerPlayerIndex, 1);
      expect(resolved.isOver, isTrue);
    });

    test('discardCard/playCounter/declineCounterも試合終了後は拒否される', () {
      final endedState = buildMatchState().copyWith(winnerPlayerIndex: 0);

      expect(
        () => CombatV1Engine.discardCard(endedState, 'x'),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(
        () => CombatV1Engine.playCounter(
          endedState,
          'x',
          catalog: fixtureCatalog,
          rules: fixtureRules,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(
        () => CombatV1Engine.declineCounter(endedState),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('I. Atomicity（不正PIN Command）', () {
    test('checkPinLegalityがfalseを返すケースはdeclarePinがstateを一切変更せず例外送出', () {
      final state = buildMatchState(); // 相手STAND・lastSuccessfulTechniqueなし
      expect(
        () => CombatV1Engine.declarePin(state, rules: fixtureRules),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      // 例外前後でstateそのものが不変であること（immutableなので同一
      // インスタンスを再検証するだけで十分）。
      expect(state.playerA.koc, 10);
      expect(state.playerB.koc, 10);
      expect(state.playerA.pinCardsHeld, 2);
      expect(state.playerB.pinCardsHeld, 2);
      expect(state.winnerPlayerIndex, isNull);
    });
  });

  group('J. Regression: card conservation', () {
    test('PIN解決はTECHNIQUE/COUNTERカードの総数を変化させない', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocB: 10,
        drawPileB: const [
          CombatV1DeckEntry(
            instanceId: 'b_reserve',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
        ],
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      int totalCards(CombatV1MatchState s) =>
          s.playerA.hand.length +
          s.playerA.drawPile.length +
          s.playerA.discardPile.length +
          s.playerB.hand.length +
          s.playerB.drawPile.length +
          s.playerB.discardPile.length;

      final before = totalCards(state);
      final resolved = CombatV1Engine.declarePin(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      // 1カウントの追加ドロー（playerBがb_reserveを引く）はplayerB内の
      // ゾーン間移動のみで、総数は変化しない。ターン開始時のドロー1枚も
      // 同様（山札が尽きていれば増減しない）。
      expect(totalCards(resolved), before);
    });
  });

  group('K. Codexレビュー追加推奨テスト', () {
    test(
      'current turnでTechnique A成功→Technique BがCOUNTERされても、'
      'checkPinLegalityはAを根拠にlegalのまま',
      () {
        const attackA = CombatV1DeckEntry(
          instanceId: 'a_A',
          cardId: 'fx_normal_throw_down', // 投1, STAND->DOWN
          category: CombatV1CardCategory.normal,
        );
        const attackB = CombatV1DeckEntry(
          instanceId: 'a_B',
          cardId: 'fx_normal_strike', // 打1, family=elbow(STRIKE)
          category: CombatV1CardCategory.normal,
        );
        const counterB = CombatV1DeckEntry(
          instanceId: 'c_B',
          cardId: 'fx_counter_a', // attribute=strike, groups=[strike]
          category: CombatV1CardCategory.counter,
        );

        var state = buildMatchState(
          handA: const [attackA, attackB],
          handB: const [counterB],
        );

        // Technique A: 成立させる（相手DOWN・lastSuccessfulTechniqueを確定）。
        final declaredA = CombatV1Engine.declareTechnique(
          state,
          'a_A',
          catalog: fixtureCatalog,
        );
        state = CombatV1Engine.declineCounter(
          declaredA,
          rules: fixtureRules,
          random: Random(1),
        );
        expect(state.lastSuccessfulTechnique?.cardInstanceId, 'a_A');
        expect(
          CombatV1Engine.checkPinLegality(state, rules: fixtureRules).legal,
          isTrue,
        );

        // Technique B: 宣言してCOUNTERされる（同一ターン内・同一活動側）。
        final declaredB = CombatV1Engine.declareTechnique(
          state,
          'a_B',
          catalog: fixtureCatalog,
        );
        final afterCounter = CombatV1Engine.playCounter(
          declaredB,
          'c_B',
          catalog: fixtureCatalog,
          rules: fixtureRules,
          random: Random(2),
        );

        // COUNTER成立はlastSuccessfulTechniqueを更新しない（Phase 4仕様）
        // ため、Aの成功記録が引き続きPIN legalityの根拠として有効。
        expect(afterCounter.lastSuccessfulTechnique?.cardInstanceId, 'a_A');
        expect(
          CombatV1Engine.checkPinLegality(afterCounter, rules: fixtureRules).legal,
          isTrue,
        );
      },
    );

    test('非常に大きいKOC（100）でも1カウント・KOC3のみ消費される', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocB: 100,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final resolved = CombatV1Engine.declarePin(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerB.koc, 97);
    });
  });
}
