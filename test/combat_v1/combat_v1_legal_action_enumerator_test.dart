// Combat Ver.1 Phase 11B: CombatV1LegalActionEnumeratorのテスト。
//
// 「CPUが合法性を判断する」のではなく、既存Engine legality
// API（checkTechniqueLegality等）へ委譲していることを、代表的な
// phase/state別に検証する。completeness/soundness（列挙した全Actionが
// 同じstateでExecutorへ渡した際に例外を出さないこと）も確認する。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_action_executor.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action_enumerator.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';

import 'combat_v1_test_fixtures.dart';

const CombatV1RulesConfig rules = fixtureRules;

List<CombatV1LegalAction> _enumerate(CombatV1MatchState state) =>
    CombatV1LegalActionEnumerator.enumerate(
      state,
      catalog: fixtureCatalog,
      rules: rules,
    );

/// 列挙された全Actionを同じ[state]でExecutorへ渡し、
/// [CombatV1IllegalActionException]が出ないことを検証する（completeness/
/// soundness、Phase 11B項目36）。
void _expectAllExecutable(CombatV1MatchState state, List<CombatV1LegalAction> actions) {
  for (final action in actions) {
    expect(
      () => CombatV1ActionExecutor.execute(
        state,
        action,
        catalog: fixtureCatalog,
        rules: rules,
      ),
      returnsNormally,
      reason: '列挙されたAction $action が同じstateで実行できません',
    );
  }
}

void main() {
  group('1. match over → empty', () {
    test('winnerPlayerIndexが設定されているstateは空Listを返す', () {
      final state = buildMatchState(winnerPlayerIndex: 0);
      expect(_enumerate(state), isEmpty);
    });
  });

  group('2. discard: active hand全physical instance', () {
    test('handAの全カードがDiscardActionとして列挙される', () {
      const c1 = CombatV1DeckEntry(
        instanceId: 'h1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      const c2 = CombatV1DeckEntry(
        instanceId: 'h2',
        cardId: 'fx_normal_strike_alt',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(
        phase: CombatV1MatchPhase.discard,
        handA: [c1, c2],
      );
      final actions = _enumerate(state);

      expect(actions.length, 2);
      expect(actions.every((a) => a is CombatV1DiscardAction), isTrue);
      expect(actions.every((a) => a.actorPlayerIndex == 0), isTrue);
      expect(
        actions.map((a) => (a as CombatV1DiscardAction).cardInstanceId).toSet(),
        {'h1', 'h2'},
      );
      _expectAllExecutable(state, actions);
    });
  });

  group('3. action/STAND: legal Technique + PIN + endTurn', () {
    test('合法なTechnique・PIN・endTurnのみ列挙される（不合法な技は除外）', () {
      const legalStrike = CombatV1DeckEntry(
        instanceId: 'legal-strike',
        cardId: 'fx_normal_strike', // cost strike1, 常に使用可能
        category: CombatV1CardCategory.normal,
      );
      const legalGround = CombatV1DeckEntry(
        instanceId: 'legal-ground',
        cardId: 'fx_normal_ground', // requiredOpponentState=down（相手DOWNで合法）
        category: CombatV1CardCategory.normal,
      );
      const heatLockedFinisher = CombatV1DeckEntry(
        instanceId: 'heat-locked-finisher',
        cardId: 'fx_finisher_a', // sharedHeat<200のため不合法
        category: CombatV1CardCategory.finisher,
      );

      final state = buildMatchState(
        handA: [legalStrike, legalGround, heatLockedFinisher],
        postureB: CombatV1WrestlerPosture.down,
        sharedHeat: 0,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final actions = _enumerate(state);

      final techniqueIds = actions
          .whereType<CombatV1TechniqueAction>()
          .map((a) => a.cardInstanceId)
          .toSet();
      expect(techniqueIds, {'legal-strike', 'legal-ground'});
      expect(actions.whereType<CombatV1PinAction>().length, 1);
      expect(actions.whereType<CombatV1EndTurnAction>().length, 1);
      expect(actions.whereType<CombatV1RestAction>(), isEmpty);
      expect(actions.whereType<CombatV1StandUpAction>(), isEmpty);
      expect(actions.every((a) => a.actorPlayerIndex == 0), isTrue);

      _expectAllExecutable(state, actions);
    });
  });

  group('4. action/DOWN: standUp + REST', () {
    test('両方legalなstandUp/RESTのみ列挙され、Technique/PIN/endTurnは列挙されない', () {
      const anyCard = CombatV1DeckEntry(
        instanceId: 'irrelevant',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(
        handA: [anyCard],
        postureA: CombatV1WrestlerPosture.down,
      );
      final actions = _enumerate(state);

      expect(actions.length, 2);
      expect(actions.whereType<CombatV1StandUpAction>().length, 1);
      expect(actions.whereType<CombatV1RestAction>().length, 1);
      expect(actions.whereType<CombatV1TechniqueAction>(), isEmpty);
      expect(actions.whereType<CombatV1PinAction>(), isEmpty);
      expect(actions.whereType<CombatV1EndTurnAction>(), isEmpty);
      expect(actions.every((a) => a.actorPlayerIndex == 0), isTrue);

      _expectAllExecutable(state, actions);
    });
  });

  group('5. counter pending: 全legal Counter + decline', () {
    const attack = CombatV1DeckEntry(
      instanceId: 'atk1',
      cardId: 'fx_normal_strike', // family=elbow（STRIKE group）
      category: CombatV1CardCategory.normal,
    );
    const matchingCounter = CombatV1DeckEntry(
      instanceId: 'ctr-strike',
      cardId: 'fx_counter_a', // groups=[strike] → elbow(STRIKE)にmatch
      category: CombatV1CardCategory.counter,
    );
    const nonMatchingCounter = CombatV1DeckEntry(
      instanceId: 'ctr-throw',
      cardId: 'fx_counter_b', // backdrop/suplexのみ → elbowにmatchしない
      category: CombatV1CardCategory.counter,
    );

    test('familyがmatchするCounterのみ + declineが常に列挙される', () {
      final state = buildMatchState(
        handA: const [attack],
        handB: const [matchingCounter, nonMatchingCounter],
      );
      final pending = CombatV1Engine.declareTechnique(
        state,
        'atk1',
        catalog: fixtureCatalog,
      );
      final actions = _enumerate(pending);

      final counterIds = actions
          .whereType<CombatV1CounterAction>()
          .map((a) => a.cardInstanceId)
          .toSet();
      expect(counterIds, {'ctr-strike'});
      expect(actions.whereType<CombatV1DeclineCounterAction>().length, 1);
      // activePlayerIndexは攻撃側(0)のまま変わらないが、actorは防御側(1)。
      expect(pending.activePlayerIndex, 0);
      expect(actions.every((a) => a.actorPlayerIndex == 1), isTrue);

      _expectAllExecutable(pending, actions);
    });
  });

  group('6. Counter 0件: declineのみ', () {
    test('legal Counterが1枚も無くてもdeclineは列挙される', () {
      const attack = CombatV1DeckEntry(
        instanceId: 'atk1',
        cardId: 'fx_normal_strike', // family=elbow
        category: CombatV1CardCategory.normal,
      );
      const nonMatchingCounter = CombatV1DeckEntry(
        instanceId: 'ctr-throw',
        cardId: 'fx_counter_b', // backdrop/suplexのみ → elbowと不一致
        category: CombatV1CardCategory.counter,
      );
      final state = buildMatchState(
        handA: const [attack],
        handB: const [nonMatchingCounter],
      );
      final pending = CombatV1Engine.declareTechnique(
        state,
        'atk1',
        catalog: fixtureCatalog,
      );
      final actions = _enumerate(pending);

      expect(actions.length, 1);
      expect(actions.single, isA<CombatV1DeclineCounterAction>());
      expect(actions.single.actorPlayerIndex, 1);

      _expectAllExecutable(pending, actions);
    });
  });

  group('7. FINISHER HEAT未達: Technique actionなし', () {
    test('sharedHeatが閾値未満ならFINISHERは列挙されない', () {
      const finisher = CombatV1DeckEntry(
        instanceId: 'fin1',
        cardId: 'fx_finisher_a',
        category: CombatV1CardCategory.finisher,
      );
      final state = buildMatchState(handA: const [finisher], sharedHeat: 0);
      final actions = _enumerate(state);

      expect(actions.whereType<CombatV1TechniqueAction>(), isEmpty);
      expect(actions.whereType<CombatV1EndTurnAction>().length, 1);
    });
  });

  group('8. FINISHER HEAT到達: legalなら列挙される', () {
    test('sharedHeatが閾値以上ならFINISHERが列挙される', () {
      const finisher = CombatV1DeckEntry(
        instanceId: 'fin1',
        cardId: 'fx_finisher_a', // cost strike2、wrestlerA pool strike3で足りる
        category: CombatV1CardCategory.finisher,
      );
      final state = buildMatchState(
        handA: const [finisher],
        sharedHeat: rules.finisherHeatThreshold,
      );
      final actions = _enumerate(state);

      final techniqueIds = actions
          .whereType<CombatV1TechniqueAction>()
          .map((a) => a.cardInstanceId)
          .toSet();
      expect(techniqueIds, {'fin1'});

      _expectAllExecutable(state, actions);
    });
  });

  group('9. ROUGH constraint: 上限到達で列挙されない', () {
    test('roughTechniqueLimitActive中に上限枚数使用済みならTechniqueは列挙されない', () {
      const strike = CombatV1DeckEntry(
        instanceId: 'strike1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(
        handA: const [strike],
        roughLimitActiveA: true,
        techniquesUsedA: rules.roughRestrictedTechniqueLimit,
      );
      final actions = _enumerate(state);

      expect(actions.whereType<CombatV1TechniqueAction>(), isEmpty);
      expect(actions.whereType<CombatV1EndTurnAction>().length, 1);
    });
  });

  group('10. illegal posture Technique: 列挙されない', () {
    test('相手の状態条件を満たさない技は列挙されない', () {
      const ground = CombatV1DeckEntry(
        instanceId: 'ground1',
        cardId: 'fx_normal_ground', // requiredOpponentState=down
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(
        handA: const [ground],
        postureB: CombatV1WrestlerPosture.stand,
      );
      final actions = _enumerate(state);

      expect(actions.whereType<CombatV1TechniqueAction>(), isEmpty);
    });
  });

  group('11. Energy不足: 列挙されない', () {
    test('ENERGY(wild含め)が不足する技は列挙されない', () {
      const signatureA = CombatV1DeckEntry(
        instanceId: 'sig-a',
        cardId: 'fx_signature_a', // cost joint1
        category: CombatV1CardCategory.signature,
      );
      final state = buildMatchState(
        handA: const [signatureA],
        // wrestlerA pool: joint1, wild2 → 両方使い切る。
        spentA: const {
          CombatV1EnergyAttribute.joint: 1,
          CombatV1EnergyAttribute.wild: 2,
        },
      );
      final actions = _enumerate(state);

      expect(actions.whereType<CombatV1TechniqueAction>(), isEmpty);
    });
  });

  group('12. normal PIN legality: legal/illegal境界', () {
    test('相手がDOWNでなければPINは列挙されない', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.stand,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      expect(_enumerate(state).whereType<CombatV1PinAction>(), isEmpty);
    });

    test('相手がDOWNかつ今ターンTECHNIQUEを成功させていればPINが列挙される', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      expect(_enumerate(state).whereType<CombatV1PinAction>().length, 1);
    });
  });

  group('13. nonterminal正常stateは最低1action', () {
    test('discard/action-stand/action-down/counter-pendingのいずれも空でない', () {
      final discardState = buildMatchState(
        phase: CombatV1MatchPhase.discard,
        handA: const [
          CombatV1DeckEntry(
            instanceId: 'x',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
        ],
      );
      final actionStandState = buildMatchState();
      final actionDownState = buildMatchState(postureA: CombatV1WrestlerPosture.down);

      expect(_enumerate(discardState), isNotEmpty);
      expect(_enumerate(actionStandState), isNotEmpty); // 最低限endTurnが残る
      expect(_enumerate(actionDownState), isNotEmpty); // 最低限standUpが残る
    });
  });

  group('setup/turnEndフェーズはprogramming errorとして拒否する', () {
    test('setupフェーズはCombatV1IllegalActionExceptionを送出する', () {
      final state = buildMatchState(phase: CombatV1MatchPhase.setup);
      expect(
        () => _enumerate(state),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('turnEndフェーズはCombatV1IllegalActionExceptionを送出する', () {
      final state = buildMatchState(phase: CombatV1MatchPhase.turnEnd);
      expect(
        () => _enumerate(state),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });
}
