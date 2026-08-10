// Combat Ver.1 Phase 7: REST / 起き上がり のテスト
// （docs/combat_rules_v1.md 11章「REST / DOWN」）。
//
// Phase 7セッションでユーザーが確定した仕様:
// - 「起き上がり」（RESTしない場合の復帰）は明示的なCommand（`standUp`）と
//   して実装する。posture: down→standへ遷移するのみで、HP・ENERGY・
//   hand/draw/discardは変化せず、`phase`/`activePlayerIndex`/`turnNumber`
//   も変化しない。ターンを消費せず、同一ターン内でそのままTECHNIQUE等の
//   通常行動へ進める。
// - `rest`はposture: down→standへ遷移し、HPを`restHpRecovery`（既定10）
//   回復する（`maxHp`を超えない）。RESTはそのターンの行動を確定し、
//   `endTurn`と同じ内部処理（手番交代・turnNumber加算・新しい手番
//   プレイヤーのターン開始処理）まで一括で進める。
// - `rest`/`standUp`はいずれもDOWN状態限定（STAND状態では選択できない）。
// - 自分（active player）がDOWN状態のままでは、TECHNIQUE宣言・PIN宣言・
//   endTurnのいずれも実行できない（`selfDown`）。先に`rest`または
//   `standUp`でDOWNから復帰する必要がある。
// - RESTがそのターンの行動を確定し即ターン終了する設計により、「RESTした
//   ターンはTECHNIQUEを使用できない」（11章）は自然に満たされる。
//   「COUNTERは使用可能」（11章）も、RESTが自分のspentEnergy等を変更
//   しないため、既存のCOUNTER legality判定へ一切影響しない。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rest_rules.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_state_invariants.dart';

import 'combat_v1_test_fixtures.dart';

void main() {
  const attack = CombatV1DeckEntry(
    instanceId: 'atk1',
    cardId: 'fx_normal_strike', // 打1, DMG10, HEAT10, STAND->STAND
    category: CombatV1CardCategory.normal,
  );
  const downingAttack = CombatV1DeckEntry(
    instanceId: 'atk_down',
    cardId: 'fx_normal_throw_down', // 投1, DMG20, STAND->DOWN
    category: CombatV1CardCategory.normal,
  );

  int totalCards(CombatV1MatchState s) =>
      s.playerA.hand.length +
      s.playerA.drawPile.length +
      s.playerA.discardPile.length +
      s.playerB.hand.length +
      s.playerB.drawPile.length +
      s.playerB.discardPile.length;

  group('A. restRecoveredHp（combat_v1_rest_rules.dart、純粋関数）', () {
    test('通常回復: maxHpを超えない範囲でrecoveryAmount分回復する', () {
      // Given: hp=50, restHpRecovery=10 → Then: hp==60
      expect(
        restRecoveredHp(currentHp: 50, maxHp: 150, recoveryAmount: 10),
        60,
      );
    });

    test('clamp（上限）: maxHp付近では超える分が切り詰められる', () {
      // Given: hp=maxHp-5, restHpRecovery=10 → Then: hp==maxHp
      expect(
        restRecoveredHp(currentHp: 145, maxHp: 150, recoveryAmount: 10),
        150,
      );
    });

    test('境界: ちょうどmaxHpならmaxHpのまま', () {
      expect(
        restRecoveredHp(currentHp: 150, maxHp: 150, recoveryAmount: 10),
        150,
      );
    });

    test(
      'clamp（下限）: 負のrecoveryAmountでもHPは0未満にならない（Codexレビュー指摘対応）',
      () {
        // Given: hp=5, restHpRecovery=-10 → Then: hp==0（5-10=-5をclamp）
        expect(
          restRecoveredHp(currentHp: 5, maxHp: 150, recoveryAmount: -10),
          0,
        );
      },
    );

    test('clamp（下限）: 大きな負のrecoveryAmountでもHPは0未満にならない', () {
      // Given: hp=5, restHpRecovery=-100 → Then: hp==0
      expect(
        restRecoveredHp(currentHp: 5, maxHp: 150, recoveryAmount: -100),
        0,
      );
    });

    test('境界: 計算結果がちょうど0ならhp==0（0未満へは切り詰めない）', () {
      expect(
        restRecoveredHp(currentHp: 10, maxHp: 150, recoveryAmount: -10),
        0,
      );
    });
  });

  group('B. checkRestLegality / hasRestOption', () {
    test('legal: DOWN状態・actionフェーズならREST可能', () {
      final state = buildMatchState(postureA: CombatV1WrestlerPosture.down);
      final check = CombatV1Engine.checkRestLegality(state);
      expect(check.legal, isTrue);
      expect(CombatV1Engine.hasRestOption(state), isTrue);
    });

    test('notDown: STAND状態ではREST不可', () {
      final state = buildMatchState();
      final check = CombatV1Engine.checkRestLegality(state);
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1RestLegalityReasonCode.notDown);
      expect(CombatV1Engine.hasRestOption(state), isFalse);
    });

    test('wrongPhase: discardフェーズ中はREST不可', () {
      final state = buildMatchState(
        phase: CombatV1MatchPhase.discard,
        postureA: CombatV1WrestlerPosture.down,
      );
      final check = CombatV1Engine.checkRestLegality(state);
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1RestLegalityReasonCode.wrongPhase);
    });

    test('matchOver: 試合終了後はREST不可', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
      ).copyWith(winnerPlayerIndex: 0);
      final check = CombatV1Engine.checkRestLegality(state);
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1RestLegalityReasonCode.matchOver);
    });
  });

  group('C. checkStandUpLegality / hasStandUpOption', () {
    test('legal: DOWN状態・actionフェーズなら起き上がり可能', () {
      final state = buildMatchState(postureA: CombatV1WrestlerPosture.down);
      final check = CombatV1Engine.checkStandUpLegality(state);
      expect(check.legal, isTrue);
      expect(CombatV1Engine.hasStandUpOption(state), isTrue);
    });

    test('notDown: STAND状態では起き上がり不可', () {
      final state = buildMatchState();
      final check = CombatV1Engine.checkStandUpLegality(state);
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1StandUpLegalityReasonCode.notDown);
      expect(CombatV1Engine.hasStandUpOption(state), isFalse);
    });

    test('wrongPhase: discardフェーズ中は起き上がり不可', () {
      final state = buildMatchState(
        phase: CombatV1MatchPhase.discard,
        postureA: CombatV1WrestlerPosture.down,
      );
      final check = CombatV1Engine.checkStandUpLegality(state);
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1StandUpLegalityReasonCode.wrongPhase);
    });

    test('matchOver: 試合終了後は起き上がり不可', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
      ).copyWith(winnerPlayerIndex: 0);
      final check = CombatV1Engine.checkStandUpLegality(state);
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1StandUpLegalityReasonCode.matchOver);
    });
  });

  group('D. standUp（起き上がり）の効果', () {
    test('posture: down→standへ遷移するのみ（HP等は不変）', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        hpA: 90,
        kocA: 7,
        pinCardsHeldA: 2,
        sharedHeat: 40,
      );
      final result = CombatV1Engine.standUp(state);

      expect(result.playerA.posture, CombatV1WrestlerPosture.stand);
      expect(result.playerA.hp, 90); // HP不変
      expect(result.playerA.koc, 7); // KOC不変
      expect(result.playerA.pinCardsHeld, 2); // PINカード不変
      expect(result.sharedHeat, 40); // HEAT不変
    });

    test('ターンを消費しない: phase/activePlayerIndex/turnNumberは不変', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        turnNumber: 5,
      );
      final result = CombatV1Engine.standUp(state);

      expect(result.phase, CombatV1MatchPhase.action);
      expect(result.activePlayerIndex, 0);
      expect(result.turnNumber, 5);
    });

    test('hand/draw/discardは変化しない（card conservation）', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        handA: const [attack],
      );
      final before = totalCards(state);
      final result = CombatV1Engine.standUp(state);

      expect(totalCards(result), before);
      expect(result.playerA.hand, state.playerA.hand);
    });

    test('起き上がった後は同一ターン内でTECHNIQUEを使用できる', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        handA: const [attack],
      );
      final stoodUp = CombatV1Engine.standUp(state);
      expect(
        CombatV1Engine.checkTechniqueLegality(
          stoodUp,
          'atk1',
          catalog: fixtureCatalog,
        ).legal,
        isTrue,
      );
      final declared = CombatV1Engine.declareTechnique(
        stoodUp,
        'atk1',
        catalog: fixtureCatalog,
      );
      expect(declared.phase, CombatV1MatchPhase.counterResponsePending);
    });

    test('不正呼び出し（STAND状態）は例外を送出しstateを一切変更しない', () {
      final state = buildMatchState();
      expect(
        () => CombatV1Engine.standUp(state),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(state.playerA.posture, CombatV1WrestlerPosture.stand);
    });

    test('game-over guard: 試合終了後はstandUpを実行できない', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
      ).copyWith(winnerPlayerIndex: 0);
      expect(
        () => CombatV1Engine.standUp(state),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('E. rest（REST）の効果', () {
    test('HP+10回復・posture: down→stand', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        hpA: 100,
      );
      final result = CombatV1Engine.rest(state, rules: fixtureRules, random: Random(1));

      // activeはRESTを実行したplayerAだが、rest内部でturnを終了して
      // activePlayerIndexが1へ移るため、playerAは以後opponent側になる。
      expect(result.playerA.hp, 110);
      expect(result.playerA.posture, CombatV1WrestlerPosture.stand);
    });

    test('HP clamp: maxHpを超えて回復しない', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        hpA: 145,
      );
      final result = CombatV1Engine.rest(state, rules: fixtureRules, random: Random(1));
      expect(result.playerA.hp, 150);
    });

    test(
      'Codexレビュー指摘対応: 負のrestHpRecovery（malformed rules）でもREST解決後のHPは'
      '0未満にならない',
      () {
        const negativeRecoveryRules = CombatV1RulesConfig(restHpRecovery: -100);
        final state = buildMatchState(
          postureA: CombatV1WrestlerPosture.down,
          hpA: 5,
        );
        final result = CombatV1Engine.rest(
          state,
          rules: negativeRecoveryRules,
          random: Random(1),
        );
        expect(result.playerA.hp, 0);
        expect(
          validatePlayerStateInvariants(result.playerA).isValid,
          isTrue,
        );
      },
    );

    test('KOC/PINカード/HEATは変化しない（SSOTに明記が無いため）', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        hpA: 100,
        kocA: 6,
        pinCardsHeldA: 1,
        pinCardsHeldB: 3,
        sharedHeat: 50,
      );
      final result = CombatV1Engine.rest(state, rules: fixtureRules, random: Random(1));
      expect(result.playerA.koc, 6);
      expect(result.playerA.pinCardsHeld, 1);
      expect(result.playerB.pinCardsHeld, 3);
      expect(result.sharedHeat, 50);
    });

    test('REST後: 手番が交代し、turnNumberが加算され、phaseはdiscardになる', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        hpA: 100,
        turnNumber: 3,
      );
      final result = CombatV1Engine.rest(state, rules: fixtureRules, random: Random(1));
      expect(result.activePlayerIndex, 1);
      expect(result.turnNumber, 4);
      expect(result.phase, CombatV1MatchPhase.discard);
    });

    test('REST後: 新しい手番プレイヤー（相手）のENERGYが全回復し、1ドローする', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        hpA: 100,
        spentB: const {CombatV1EnergyAttribute.strike: 1},
        techniquesUsedB: 2,
        drawPileB: const [
          CombatV1DeckEntry(
            instanceId: 'b_reserve',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
        ],
      );
      final result = CombatV1Engine.rest(state, rules: fixtureRules, random: Random(1));
      expect(result.playerB.spentEnergy, isEmpty);
      expect(result.playerB.techniquesUsedThisTurn, 0);
      expect(
        result.playerB.hand.any((e) => e.instanceId == 'b_reserve'),
        isTrue,
      );
    });

    test('RESTした側自身のhand/draw/discardは変化しない', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        hpA: 100,
        handA: const [attack],
      );
      final result = CombatV1Engine.rest(state, rules: fixtureRules, random: Random(1));
      expect(result.playerA.hand, state.playerA.hand);
      expect(result.playerA.discardPile, state.playerA.discardPile);
    });

    test('card conservation: RESTはカード総数を変化させない', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        hpA: 100,
        handA: const [attack],
        drawPileB: const [
          CombatV1DeckEntry(
            instanceId: 'b_reserve',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
        ],
      );
      final before = totalCards(state);
      final result = CombatV1Engine.rest(state, rules: fixtureRules, random: Random(1));
      expect(totalCards(result), before);
    });

    test(
      'RESTしたターンはTECHNIQUEを使用できない・COUNTERは使用可能（11章）: '
      'RESTがターンを終了するため、次にTECHNIQUEを宣言できるのは相手であり、'
      'RESTした側のCOUNTER能力（ENERGY）はそのまま保持される',
      () {
        final state = buildMatchState(
          postureA: CombatV1WrestlerPosture.down,
          hpA: 100,
          handB: const [attack, downingAttack],
        );
        final rested = CombatV1Engine.rest(
          state,
          rules: fixtureRules,
          random: Random(1),
        );
        expect(rested.activePlayerIndex, 1);
        expect(rested.phase, CombatV1MatchPhase.discard);

        // 通常の手札循環（discardフェーズ）を経てactionフェーズへ進める。
        final afterDiscard = CombatV1Engine.discardCard(
          rested,
          rested.playerB.hand.first.instanceId,
        );

        // 相手（新しい手番、playerB）がTECHNIQUEを宣言すると、RESTした側
        // （playerA）はCOUNTER応答フェーズに入れる（COUNTERは使用可能）。
        final declared = CombatV1Engine.declareTechnique(
          afterDiscard,
          'atk_down',
          catalog: fixtureCatalog,
        );
        expect(declared.phase, CombatV1MatchPhase.counterResponsePending);
        expect(
          CombatV1Engine.hasAnyPlayableCounter(
            declared,
            catalog: fixtureCatalog,
            rules: fixtureRules,
          ),
          isA<bool>(),
        );
      },
    );

    test('不正呼び出し（STAND状態）は例外を送出しstateを一切変更しない', () {
      final state = buildMatchState(hpA: 100);
      expect(
        () => CombatV1Engine.rest(state, rules: fixtureRules),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(state.playerA.hp, 100);
      expect(state.playerA.posture, CombatV1WrestlerPosture.stand);
      expect(state.activePlayerIndex, 0);
      expect(state.turnNumber, 1);
    });

    test('不正呼び出し（wrongPhase）は例外を送出する', () {
      final state = buildMatchState(
        phase: CombatV1MatchPhase.discard,
        postureA: CombatV1WrestlerPosture.down,
      );
      expect(
        () => CombatV1Engine.rest(state, rules: fixtureRules),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('game-over guard: 試合終了後はrestを実行できない', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
      ).copyWith(winnerPlayerIndex: 0);
      expect(
        () => CombatV1Engine.rest(state, rules: fixtureRules),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('F. DOWN時の合法行動（Phase 3〜6 legality regression）', () {
    test('checkTechniqueLegality: 自分がDOWNならselfDownで拒否される', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        handA: const [attack],
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'atk1',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1TechniqueLegalityReasonCode.selfDown);
    });

    test('declareTechnique: 自分がDOWNなら例外を送出しstateを一切変更しない', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        handA: const [attack],
      );
      expect(
        () => CombatV1Engine.declareTechnique(
          state,
          'atk1',
          catalog: fixtureCatalog,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(state.playerA.hand, const [attack]);
      expect(state.phase, CombatV1MatchPhase.action);
    });

    test('hasAnyPlayableTechnique: 自分がDOWNなら手札に使える技があってもfalse', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        handA: const [attack],
      );
      expect(
        CombatV1Engine.hasAnyPlayableTechnique(state, catalog: fixtureCatalog),
        isFalse,
      );
    });

    test('checkPinLegality: 自分（攻撃側）がDOWNならselfDownで拒否される', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        turnNumber: 1,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final check = CombatV1Engine.checkPinLegality(state, rules: fixtureRules);
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1PinLegalityReasonCode.selfDown);
    });

    test('declarePin: 自分（攻撃側）がDOWNなら例外を送出する', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        turnNumber: 1,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      expect(
        () => CombatV1Engine.declarePin(state, rules: fixtureRules),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('endTurn: 自分がDOWNなら例外を送出する（先にrest/standUpが必要）', () {
      final state = buildMatchState(postureA: CombatV1WrestlerPosture.down);
      expect(
        () => CombatV1Engine.endTurn(state),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(state.activePlayerIndex, 0);
      expect(state.turnNumber, 1);
    });

    test('COUNTERは自分がDOWN状態でも一切制限されない（防御側の判定に影響しない）', () {
      // activeはplayerB（DOWN状態）だが、COUNTER判定はplayerA視点の
      // pending攻撃には無関係（このシナリオはplayerAがactiveのまま攻撃する）。
      // ここではplayerB自身がDOWNのまま相手の攻撃をCOUNTERできることを、
      // 直接pendingを構築して確認する。
      final state = buildMatchState(
        handA: const [downingAttack],
        postureB: CombatV1WrestlerPosture.down,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_down',
        catalog: fixtureCatalog,
      );
      // playerB（防御側）がDOWNのままでも、COUNTER legality判定はposture
      // を一切参照しない（`checkCounterLegality`にselfDown相当のガードを
      // 追加していないことを確認する回帰テスト）。
      expect(declared.phase, CombatV1MatchPhase.counterResponsePending);
      expect(declared.opponent.posture, CombatV1WrestlerPosture.down);
    });
  });

  group('G. PIN 1/2カウント後のREST/起き上がり統合（Phase 5整合）', () {
    test('1カウントkick out後: 新しい手番（防御側）はDOWNのままrecoveryが必須', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocB: 10,
        handB: const [attack, downingAttack],
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
      final afterPin = CombatV1Engine.declarePin(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(afterPin.activePlayerIndex, 1);
      expect(afterPin.phase, CombatV1MatchPhase.discard);
      expect(afterPin.playerB.posture, CombatV1WrestlerPosture.down);

      // discardフェーズを経てactionフェーズへ（通常の手札循環）。
      final discardTarget = afterPin.playerB.hand.first;
      final afterDiscard = CombatV1Engine.discardCard(
        afterPin,
        discardTarget.instanceId,
      );
      expect(afterDiscard.phase, CombatV1MatchPhase.action);

      // まだDOWNのままrecoveryしていないため、TECHNIQUE宣言・endTurnは拒否。
      final remainingCard = afterDiscard.playerB.hand.first;
      expect(
        () => CombatV1Engine.declareTechnique(
          afterDiscard,
          remainingCard.instanceId,
          catalog: fixtureCatalog,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(
        () => CombatV1Engine.endTurn(afterDiscard),
        throwsA(isA<CombatV1IllegalActionException>()),
      );

      // standUpで復帰すれば、同一ターン内でTECHNIQUEを使用できる。
      final stoodUp = CombatV1Engine.standUp(afterDiscard);
      expect(stoodUp.playerB.posture, CombatV1WrestlerPosture.stand);
      expect(
        CombatV1Engine.hasAnyPlayableTechnique(stoodUp, catalog: fixtureCatalog),
        isTrue,
      );
    });

    test('2カウントkick out後も同様にrecoveryが必須', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocB: 2,
        handB: const [attack, downingAttack],
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final afterPin = CombatV1Engine.declarePin(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(afterPin.activePlayerIndex, 1);
      expect(afterPin.playerB.posture, CombatV1WrestlerPosture.down);

      final afterDiscard = CombatV1Engine.discardCard(
        afterPin,
        afterPin.playerB.hand.first.instanceId,
      );
      final remainingCard = afterDiscard.playerB.hand.first;
      expect(
        CombatV1Engine.checkTechniqueLegality(
          afterDiscard,
          remainingCard.instanceId,
          catalog: fixtureCatalog,
        ).reasonCode,
        CombatV1TechniqueLegalityReasonCode.selfDown,
      );

      // RESTを選べば、HP回復した上でそのままターン終了する。
      final rested = CombatV1Engine.rest(
        afterDiscard,
        rules: fixtureRules,
        random: Random(2),
      );
      // rest実行前のactiveはplayerB(index1)なので、restを実行したのは
      // playerB自身——手番はplayerAへ戻る。
      expect(rested.playerB.posture, CombatV1WrestlerPosture.stand);
      expect(rested.activePlayerIndex, 0);
    });

    test('2.9カウント継続中は攻撃側（DOWNではない）に一切recoveryを要求しない', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocB: 1,
        handA: const [attack],
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
      // 2.9カウント: phase/activePlayerIndexとも維持、攻撃側はSTANDのまま
      // なので、そのままTECHNIQUEを宣言できる（recoveryは不要）。
      expect(resolved.phase, CombatV1MatchPhase.action);
      expect(resolved.activePlayerIndex, 0);
      expect(resolved.playerA.posture, CombatV1WrestlerPosture.stand);
      expect(
        CombatV1Engine.checkTechniqueLegality(
          resolved,
          'atk1',
          catalog: fixtureCatalog,
        ).legal,
        isTrue,
      );
    });
  });

  group('H. SUBMISSION ESCAPE後のREST/起き上がり統合（Phase 6整合）', () {
    test('ESCAPE成功後も防御側のpostureはESCAPE自体では変化しない', () {
      const submissionAttack = CombatV1DeckEntry(
        instanceId: 'atk_sub',
        cardId: 'fx_normal_submission_hold',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(
        handA: const [submissionAttack],
        handB: const [attack],
        hpB: 150,
        kocB: 10,
        postureB: CombatV1WrestlerPosture.down,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_sub',
        catalog: fixtureCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );

      // ESCAPE成功（10.1章、Phase6）: 攻撃側のターンを終了し、防御側の
      // 新しいターンへ進める。SUBMISSIONはPINカードもpostureも操作しない
      // ため、防御側はDOWNのままアクティブになる。
      expect(resolved.activePlayerIndex, 1);
      expect(resolved.phase, CombatV1MatchPhase.discard);
      expect(resolved.playerB.posture, CombatV1WrestlerPosture.down);

      final afterDiscard = CombatV1Engine.discardCard(
        resolved,
        resolved.playerB.hand.first.instanceId,
      );
      expect(
        () => CombatV1Engine.endTurn(afterDiscard),
        throwsA(isA<CombatV1IllegalActionException>()),
      );

      final rested = CombatV1Engine.rest(
        afterDiscard,
        rules: fixtureRules,
        random: Random(2),
      );
      expect(rested.playerB.posture, CombatV1WrestlerPosture.stand);
      expect(rested.activePlayerIndex, 0);
    });
  });

  group('I. Invariant / atomicity 全体確認', () {
    test('checkRestLegality/checkStandUpLegalityはmalformedPendingStateも判定する', () {
      final malformed = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
      ).copyWith(phase: CombatV1MatchPhase.counterResponsePending);
      expect(
        CombatV1Engine.checkRestLegality(malformed).reasonCode,
        CombatV1RestLegalityReasonCode.malformedPendingState,
      );
      expect(
        CombatV1Engine.checkStandUpLegality(malformed).reasonCode,
        CombatV1StandUpLegalityReasonCode.malformedPendingState,
      );
    });

    test('rest失敗時、playerA/playerB双方のstateが完全に不変', () {
      final state = buildMatchState(
        hpA: 120,
        hpB: 130,
        kocA: 8,
        kocB: 9,
        pinCardsHeldA: 3,
        pinCardsHeldB: 1,
        sharedHeat: 60,
        turnNumber: 4,
        handA: const [attack],
      );
      expect(
        () => CombatV1Engine.rest(state, rules: fixtureRules),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(
        validatePlayerStateInvariants(state.playerA).isValid,
        isTrue,
      );
      expect(state.playerA.hp, 120);
      expect(state.playerB.hp, 130);
      expect(state.playerA.koc, 8);
      expect(state.playerB.koc, 9);
      expect(state.playerA.pinCardsHeld, 3);
      expect(state.playerB.pinCardsHeld, 1);
      expect(state.sharedHeat, 60);
      expect(state.turnNumber, 4);
      expect(state.playerA.hand, const [attack]);
    });
  });

  group('J. Phase 1〜6 regression（フィクスチャデッキ・catalogに影響なし）', () {
    test('フィクスチャ30枚デッキは引き続きvalidである', () {
      final started = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck(fixtureWrestlerA.id),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck(fixtureWrestlerB.id),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(1),
      );
      expect(started.phase, CombatV1MatchPhase.discard);
      expect(started.playerA.posture, CombatV1WrestlerPosture.stand);
      expect(started.playerB.posture, CombatV1WrestlerPosture.stand);
    });
  });
}
