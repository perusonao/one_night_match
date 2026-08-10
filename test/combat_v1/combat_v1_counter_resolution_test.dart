// Combat Ver.1 Phase 4: playCounter（COUNTER成立）の検証
// （docs/combat_rules_v1.md 7章「COUNTER」7.1章
// 「PendingAttack・counterResponsePending」、テスト項目31-E・32）。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';

import 'combat_v1_test_fixtures.dart';

void main() {
  // fx_normal_strike: attribute=strike, family=elbow(STRIKE), cost 打1
  // fx_counter_a: attribute=strike, counterableGroups=[strike] → group match
  const attack = CombatV1DeckEntry(
    instanceId: 'atk1',
    cardId: 'fx_normal_strike',
    category: CombatV1CardCategory.normal,
  );
  const matchingCounter = CombatV1DeckEntry(
    instanceId: 'ctr1',
    cardId: 'fx_counter_a',
    category: CombatV1CardCategory.counter,
  );

  CombatV1MatchState declareState({
    List<CombatV1DeckEntry> handA = const [attack],
    List<CombatV1DeckEntry> handB = const [matchingCounter],
    List<CombatV1DeckEntry> drawPileA = const [],
    List<CombatV1DeckEntry> drawPileB = const [],
    int hpB = 150,
    int sharedHeat = 0,
    CombatV1WrestlerPosture postureB = CombatV1WrestlerPosture.stand,
  }) {
    final state = buildMatchState(
      handA: handA,
      handB: handB,
      drawPileA: drawPileA,
      drawPileB: drawPileB,
      hpB: hpB,
      sharedHeat: sharedHeat,
      postureB: postureB,
    );
    return CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
  }

  group('checkCounterLegality/playCounter — matching success', () {
    test('family/groupが一致するCOUNTERは成立する', () {
      final pending = declareState();
      final check = CombatV1Engine.checkCounterLegality(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      );
      expect(check.legal, isTrue);
    });

    test('COUNTER成立後、attack DMG/HEAT/posture変更は完全に無効化される', () {
      final pending = declareState(hpB: 150, sharedHeat: 0);
      final after = CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(after.playerB.hp, 150); // DMG無効
      expect(after.sharedHeat, 0); // HEAT無効
      expect(after.playerB.posture, CombatV1WrestlerPosture.stand); // posture無効
    });

    test('攻撃カードは攻撃側のdiscardへ、COUNTERカードは防御側のdiscardへ移動する', () {
      // 双方のdrawPileへfillerを1枚用意しておく。drawPileが空のまま
      // 「discard直後に1 draw」が起きると、直前に捨てたばかりのカードが
      // 空のdrawPileに対する再構築（捨て札シャッフル）で即座に引き戻されて
      // しまい、このテストの本来の関心事（discardへ実際に移動したか）と
      // 無関係な結果になるため（Phase 3のtest 44と同じ理由、
      // combat_v1_technique_legality_test.dartのコメント参照）。
      final fillerA = const CombatV1DeckEntry(
        instanceId: 'fillerA',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final fillerB = const CombatV1DeckEntry(
        instanceId: 'fillerB',
        cardId: 'fx_counter_a',
        category: CombatV1CardCategory.counter,
      );
      final pending = declareState(drawPileA: [fillerA], drawPileB: [fillerB]);
      final after = CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(after.playerA.discardPile.any((e) => e.instanceId == 'atk1'), isTrue);
      expect(after.playerB.discardPile.any((e) => e.instanceId == 'ctr1'), isTrue);
      expect(after.playerB.hand.any((e) => e.instanceId == 'ctr1'), isFalse);
    });

    test('攻撃側・防御側の双方が1枚ずつdrawする', () {
      final drawA = const CombatV1DeckEntry(
        instanceId: 'reserveA',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final drawB = const CombatV1DeckEntry(
        instanceId: 'reserveB',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(
        handA: [attack],
        handB: [matchingCounter],
        drawPileA: [drawA],
        drawPileB: [drawB],
      );
      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);

      final after = CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(1),
      );

      expect(after.playerA.hand.any((e) => e.instanceId == 'reserveA'), isTrue);
      expect(after.playerB.hand.any((e) => e.instanceId == 'reserveB'), isTrue);
    });

    test('activePlayerIndexは宣言した攻撃側のまま、phaseはactionへ戻る', () {
      final pending = declareState();
      final after = CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(after.activePlayerIndex, 0);
      expect(after.phase, CombatV1MatchPhase.action);
      expect(after.pendingAttack, isNull);
    });

    test('defender COUNTER ENERGY支払いはspentEnergyへ反映される', () {
      final pending = declareState();
      final after = CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(1),
      );
      // fx_counter_a.attribute=strike、攻撃Cost totalは1（fx_normal_strike：打1）。
      expect(after.playerB.spentEnergy[CombatV1EnergyAttribute.strike], 1);
    });
  });

  group('checkCounterLegality — 拒否ケース', () {
    test('family不一致は拒否される（familyGroupMismatch）', () {
      final state = buildMatchState(
        handA: [attack],
        handB: const [
          CombatV1DeckEntry(
            instanceId: 'ctr_narrow',
            cardId: 'fx_counter_c', // families=[dropKick]のみ、strike/elbow非対応
            category: CombatV1CardCategory.counter,
          ),
        ],
      );
      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);

      final check = CombatV1Engine.checkCounterLegality(
        pending,
        'ctr_narrow',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      );
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1CounterLegalityReasonCode.familyGroupMismatch);
    });

    test('group不一致（groupsに一致無し・familiesにも一致無し）は拒否される', () {
      final state = buildMatchState(
        handA: const [
          CombatV1DeckEntry(
            instanceId: 'atk_throw',
            cardId: 'fx_normal_throw_down', // family=slam (THROW)
            category: CombatV1CardCategory.normal,
          ),
        ],
        handB: const [
          CombatV1DeckEntry(
            instanceId: 'ctr_strike_group',
            cardId: 'fx_counter_a', // groups=[strike]のみ
            category: CombatV1CardCategory.counter,
          ),
        ],
      );
      final pending = CombatV1Engine.declareTechnique(state, 'atk_throw', catalog: fixtureCatalog);

      final check = CombatV1Engine.checkCounterLegality(
        pending,
        'ctr_strike_group',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      );
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1CounterLegalityReasonCode.familyGroupMismatch);
    });

    test('ENERGY不足は拒否される（insufficientEnergy）', () {
      final state = buildMatchState(
        handA: [attack],
        handB: [matchingCounter],
        spentB: const {CombatV1EnergyAttribute.strike: 2}, // fixtureWrestlerBの打は2、残り0
      );
      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);

      final check = CombatV1Engine.checkCounterLegality(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      );
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1CounterLegalityReasonCode.insufficientEnergy);
    });

    test('攻撃側は自分の攻撃をCOUNTERできない（攻撃側手札のCOUNTERカードは'
        '防御側handから見つからずcardNotInHandになる＝「wrong responder」の拒否）', () {
      final state = buildMatchState(
        handA: [attack, matchingCounter], // 攻撃側も同じCOUNTERカードを持つ
        handB: const [],
      );
      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);

      final check = CombatV1Engine.checkCounterLegality(
        pending,
        'ctr1', // 攻撃側(playerA)の手札にあるinstanceId
        catalog: fixtureCatalog,
        rules: fixtureRules,
      );
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1CounterLegalityReasonCode.cardNotInHand);
    });

    test('pendingが無い（phase==action）状態ではwrongPhaseで拒否される', () {
      final state = buildMatchState(handA: [attack], handB: [matchingCounter]);
      final check = CombatV1Engine.checkCounterLegality(
        state,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      );
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1CounterLegalityReasonCode.wrongPhase);
    });

    test('COUNTER成立後の二重応答は拒否される（pending既にクリア済み）', () {
      final pending = declareState();
      final resolved = CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(1),
      );

      expect(
        () => CombatV1Engine.playCounter(
          resolved,
          'ctr1',
          catalog: fixtureCatalog,
          rules: fixtureRules,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(
        () => CombatV1Engine.declineCounter(resolved),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('hasAnyPlayableCounter（32）', () {
    test('matching Counterがあればtrue', () {
      final pending = declareState();
      expect(
        CombatV1Engine.hasAnyPlayableCounter(
          pending,
          catalog: fixtureCatalog,
          rules: fixtureRules,
        ),
        isTrue,
      );
    });

    test('family mismatchのみならfalse', () {
      final state = buildMatchState(
        handA: [attack],
        handB: const [
          CombatV1DeckEntry(
            instanceId: 'ctr_narrow',
            cardId: 'fx_counter_c',
            category: CombatV1CardCategory.counter,
          ),
        ],
      );
      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
      expect(
        CombatV1Engine.hasAnyPlayableCounter(
          pending,
          catalog: fixtureCatalog,
          rules: fixtureRules,
        ),
        isFalse,
      );
    });

    test('group matchがあればtrue', () {
      final pending = declareState(); // fx_counter_a groups=[strike]
      expect(
        CombatV1Engine.hasAnyPlayableCounter(
          pending,
          catalog: fixtureCatalog,
          rules: fixtureRules,
        ),
        isTrue,
      );
    });

    test('Energy不足のみならfalse', () {
      final state = buildMatchState(
        handA: [attack],
        handB: [matchingCounter],
        spentB: const {CombatV1EnergyAttribute.strike: 2},
      );
      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
      expect(
        CombatV1Engine.hasAnyPlayableCounter(
          pending,
          catalog: fixtureCatalog,
          rules: fixtureRules,
        ),
        isFalse,
      );
    });

    test('wild=falseでは不足のままfalse', () {
      final state = buildMatchState(
        handA: [attack],
        handB: [matchingCounter],
        spentB: const {
          CombatV1EnergyAttribute.strike: 2, // 残り0
          CombatV1EnergyAttribute.wild: 0, // 残り2（wildはあるが使えない）
        },
      );
      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
      expect(
        CombatV1Engine.hasAnyPlayableCounter(
          pending,
          catalog: fixtureCatalog,
          rules: const CombatV1RulesConfig(counterAllowsWildSubstitution: false),
        ),
        isFalse,
      );
    });

    test('wild=trueで補完可能ならtrue', () {
      final state = buildMatchState(
        handA: [attack],
        handB: [matchingCounter],
        spentB: const {
          CombatV1EnergyAttribute.strike: 2, // 残り0
        },
      );
      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
      expect(
        CombatV1Engine.hasAnyPlayableCounter(
          pending,
          catalog: fixtureCatalog,
          rules: const CombatV1RulesConfig(counterAllowsWildSubstitution: true),
        ),
        isTrue,
      );
    });

    test('pendingが無ければfalse', () {
      final state = buildMatchState(handA: [attack], handB: [matchingCounter]);
      expect(
        CombatV1Engine.hasAnyPlayableCounter(
          state,
          catalog: fixtureCatalog,
          rules: fixtureRules,
        ),
        isFalse,
      );
    });

    test('wrong phase（action）ならfalse', () {
      final state = buildMatchState(handA: [attack], handB: [matchingCounter]);
      expect(state.phase, CombatV1MatchPhase.action);
      expect(
        CombatV1Engine.hasAnyPlayableCounter(
          state,
          catalog: fixtureCatalog,
          rules: fixtureRules,
        ),
        isFalse,
      );
    });
  });
}
