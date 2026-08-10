// Combat Ver.1 Phase 4: COUNTER動的ENERGY COST・wild policyの検証
// （docs/combat_rules_v1.md 7章「COUNTER」・7.2章「CombatV1EnergyCost.total」・
// 5.2章「COUNTERでの＊(ワイルド)ENERGYの扱い」、テスト項目31-C）。
//
// 攻撃Cost: throwing2 + strike1（total3）、Counter.attribute=throwing
// という共通シナリオで、counterAllowsWildSubstitution=false/trueそれぞれの
// 挙動を検証する。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_counter.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_counter_rules.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';

import 'combat_v1_test_fixtures.dart';

// throwing2 + strike1（total 3）、family=backdrop
// （fixtureCounters['fx_counter_b']がbackdrop/suplexを返せる）。
const _mixedCostAttack = CombatV1Technique(
  id: 'ce_mixed_cost_attack',
  name: 'テスト複合コスト攻撃',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.throwing,
  energyCost: CombatV1EnergyCost({
    CombatV1EnergyAttribute.throwing: 2,
    CombatV1EnergyAttribute.strike: 1,
  }),
  damage: 20,
  heatGain: 20,
  family: CombatV1TechniqueFamily.backdrop,
);

void main() {
  group('CombatV1EnergyCost.total', () {
    test('total3 = throwing2 + strike1', () {
      expect(_mixedCostAttack.energyCost.total, 3);
    });
  });

  group('counterSyntheticCost — 動的ENERGY COST（docs/combat_rules_v1.md「7章」）', () {
    test('COUNTER必要量は攻撃Cost属性構成をコピーせず、単一属性totalになる', () {
      final counter = CombatV1Counter(
        id: 'synthetic_test_counter',
        name: 'テスト合成コストカウンター',
        attribute: CombatV1EnergyAttribute.throwing,
        counterableFamilies: [CombatV1TechniqueFamily.backdrop],
      );
      final synthetic = counterSyntheticCost(counter, _mixedCostAttack.energyCost);

      expect(synthetic.amountFor(CombatV1EnergyAttribute.throwing), 3);
      expect(synthetic.amountFor(CombatV1EnergyAttribute.strike), 0); // コピーされない
    });
  });

  group('resolveEnergyPayment — wild policy（Config=false、docs/combat_rules_v1.md「5.2章」）', () {
    const pool = CombatV1EnergyPool({
      CombatV1EnergyAttribute.throwing: 3,
      CombatV1EnergyAttribute.wild: 3,
    });
    final syntheticCost = CombatV1EnergyCost({
      CombatV1EnergyAttribute.throwing: _mixedCostAttack.energyCost.total,
    });

    test('投3 → success', () {
      final result = resolveEnergyPayment(
        pool: pool,
        spent: const {},
        cost: syntheticCost,
        allowWildSubstitution: false,
      );
      expect(result.isSuccess, isTrue);
    });

    test('投2 + wild1 → fail（wild補完不可）', () {
      final result = resolveEnergyPayment(
        pool: pool,
        spent: const {
          CombatV1EnergyAttribute.throwing: 1, // 残り2
          CombatV1EnergyAttribute.wild: 2, // 残り1
        },
        cost: syntheticCost,
        allowWildSubstitution: false,
      );
      expect(result.isSuccess, isFalse);
    });

    test('投1 + wild2 → fail', () {
      final result = resolveEnergyPayment(
        pool: pool,
        spent: const {
          CombatV1EnergyAttribute.throwing: 2, // 残り1
          CombatV1EnergyAttribute.wild: 1, // 残り2
        },
        cost: syntheticCost,
        allowWildSubstitution: false,
      );
      expect(result.isSuccess, isFalse);
    });

    test('投0 + wild3 → fail', () {
      final result = resolveEnergyPayment(
        pool: pool,
        spent: const {
          CombatV1EnergyAttribute.throwing: 3, // 残り0
        },
        cost: syntheticCost,
        allowWildSubstitution: false,
      );
      expect(result.isSuccess, isFalse);
    });
  });

  group('resolveEnergyPayment — wild policy（Config=true、docs/combat_rules_v1.md「5.2章」）', () {
    const pool = CombatV1EnergyPool({
      CombatV1EnergyAttribute.throwing: 3,
      CombatV1EnergyAttribute.wild: 3,
    });
    final syntheticCost = CombatV1EnergyCost({
      CombatV1EnergyAttribute.throwing: _mixedCostAttack.energyCost.total,
    });

    test('投3 → success', () {
      final result = resolveEnergyPayment(
        pool: pool,
        spent: const {},
        cost: syntheticCost,
        allowWildSubstitution: true,
      );
      expect(result.isSuccess, isTrue);
    });

    test('投2 + wild1 → success', () {
      final result = resolveEnergyPayment(
        pool: pool,
        spent: const {
          CombatV1EnergyAttribute.throwing: 1,
          CombatV1EnergyAttribute.wild: 2,
        },
        cost: syntheticCost,
        allowWildSubstitution: true,
      );
      expect(result.isSuccess, isTrue);
    });

    test('投1 + wild2 → success', () {
      final result = resolveEnergyPayment(
        pool: pool,
        spent: const {
          CombatV1EnergyAttribute.throwing: 2,
          CombatV1EnergyAttribute.wild: 1,
        },
        cost: syntheticCost,
        allowWildSubstitution: true,
      );
      expect(result.isSuccess, isTrue);
    });

    test('投0 + wild3 → success', () {
      final result = resolveEnergyPayment(
        pool: pool,
        spent: const {
          CombatV1EnergyAttribute.throwing: 3,
        },
        cost: syntheticCost,
        allowWildSubstitution: true,
      );
      expect(result.isSuccess, isTrue);
    });

    test('投2 + wild0 → fail（wild残量が無いため補完不可）', () {
      final result = resolveEnergyPayment(
        pool: pool,
        spent: const {
          CombatV1EnergyAttribute.throwing: 1, // 残り2
          CombatV1EnergyAttribute.wild: 3, // 残り0
        },
        cost: syntheticCost,
        allowWildSubstitution: true,
      );
      expect(result.isSuccess, isFalse);
    });
  });

  group('CombatV1RulesConfig.counterAllowsWildSubstitution — 既定値', () {
    test('既定値はfalse', () {
      expect(const CombatV1RulesConfig().counterAllowsWildSubstitution, isFalse);
    });
  });

  group('Engine統合 — checkCounterLegality/playCounterがrules.counterAllowsWildSubstitutionに従う', () {
    CombatV1MatchState declaredState({required CombatV1EnergyPool defenderPool}) {
      final catalog = CombatV1CardCatalog(
        techniques: {...fixtureTechniques, _mixedCostAttack.id: _mixedCostAttack},
        counters: fixtureCounters,
      );
      final attackEntry = const CombatV1DeckEntry(
        instanceId: 'atk1',
        cardId: 'ce_mixed_cost_attack',
        category: CombatV1CardCategory.normal,
      );
      final counterEntry = const CombatV1DeckEntry(
        instanceId: 'ctr1',
        cardId: 'fx_counter_b', // attribute=throwing, families=[backdrop, suplex]
        category: CombatV1CardCategory.counter,
      );
      final attackerPool = const CombatV1EnergyPool({
        CombatV1EnergyAttribute.throwing: 2,
        CombatV1EnergyAttribute.strike: 1,
      });
      final playerA = CombatV1PlayerState(
        wrestlerId: 'ce_a',
        wrestlerName: 'CE攻撃側',
        maxHp: 150,
        hp: 150,
        koc: 10,
        pinCardsHeld: 2,
        energyPool: attackerPool,
        hand: [attackEntry],
      );
      final playerB = CombatV1PlayerState(
        wrestlerId: 'ce_b',
        wrestlerName: 'CE防御側',
        maxHp: 150,
        hp: 150,
        koc: 10,
        pinCardsHeld: 2,
        energyPool: defenderPool,
        hand: [counterEntry],
      );
      final state = CombatV1MatchState(
        matchId: 'ce-test',
        playerA: playerA,
        playerB: playerB,
        activePlayerIndex: 0,
        turnNumber: 1,
        phase: CombatV1MatchPhase.action,
      );
      return CombatV1Engine.declareTechnique(state, 'atk1', catalog: catalog);
    }

    final catalog = CombatV1CardCatalog(
      techniques: {...fixtureTechniques, _mixedCostAttack.id: _mixedCostAttack},
      counters: fixtureCounters,
    );

    test('Config=false・投3ちょうど保有 → playCounterが成功する', () {
      final pending = declaredState(
        defenderPool: const CombatV1EnergyPool({CombatV1EnergyAttribute.throwing: 3}),
      );
      const rules = CombatV1RulesConfig(); // counterAllowsWildSubstitution: false

      final check = CombatV1Engine.checkCounterLegality(
        pending,
        'ctr1',
        catalog: catalog,
        rules: rules,
      );
      expect(check.legal, isTrue);

      final after = CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: catalog,
        rules: rules,
      );
      expect(after.phase, CombatV1MatchPhase.action);
    });

    test('Config=false・投2+wild1しか無い → playCounterはinsufficientEnergyで拒否', () {
      final pending = declaredState(
        defenderPool: const CombatV1EnergyPool({
          CombatV1EnergyAttribute.throwing: 2,
          CombatV1EnergyAttribute.wild: 1,
        }),
      );
      const rules = CombatV1RulesConfig();

      final check = CombatV1Engine.checkCounterLegality(
        pending,
        'ctr1',
        catalog: catalog,
        rules: rules,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1CounterLegalityReasonCode.insufficientEnergy,
      );
      expect(
        () => CombatV1Engine.playCounter(pending, 'ctr1', catalog: catalog, rules: rules),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('Config=true・投2+wild1 → playCounterが成功する', () {
      final pending = declaredState(
        defenderPool: const CombatV1EnergyPool({
          CombatV1EnergyAttribute.throwing: 2,
          CombatV1EnergyAttribute.wild: 1,
        }),
      );
      const rules = CombatV1RulesConfig(counterAllowsWildSubstitution: true);

      final check = CombatV1Engine.checkCounterLegality(
        pending,
        'ctr1',
        catalog: catalog,
        rules: rules,
      );
      expect(check.legal, isTrue);

      final after = CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: catalog,
        rules: rules,
      );
      expect(after.phase, CombatV1MatchPhase.action);
      expect(
        after.playerB.spentEnergy[CombatV1EnergyAttribute.wild],
        1,
      );
    });
  });
}
