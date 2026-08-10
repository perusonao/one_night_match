// Combat Ver.1 Phase 4: COUNTER ENERGYのライフタイム検証
// （docs/combat_rules_v1.md 7.1章「COUNTER後のENERGY」、15章
// 「COUNTERはtechniquesUsedThisTurnに含めない」、テスト項目31-G）。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';

import 'combat_v1_test_fixtures.dart';

void main() {
  const attack = CombatV1DeckEntry(
    instanceId: 'atk1',
    cardId: 'fx_normal_strike', // 打1コスト、family=elbow
    category: CombatV1CardCategory.normal,
  );
  const counter = CombatV1DeckEntry(
    instanceId: 'ctr1',
    cardId: 'fx_counter_a', // attribute=strike, groups=[strike]
    category: CombatV1CardCategory.counter,
  );

  group('defenderのCOUNTER ENERGY', () {
    test('COUNTER成功後、defenderのspentEnergyは即座には回復しない', () {
      final state = buildMatchState(handA: const [attack], handB: const [counter]);
      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
      final afterCounter = CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(1),
      );

      expect(afterCounter.playerB.spentEnergy[CombatV1EnergyAttribute.strike], 1);
      // まだplayerBの自ターンが開始していないため回復しない。
      expect(afterCounter.playerB.availableEnergyFor(CombatV1EnergyAttribute.strike), 1);
    });

    test('defenderの次の自ターン開始時に全回復する', () {
      final state = buildMatchState(handA: const [attack], handB: const [counter]);
      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
      var after = CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(after.playerB.spentEnergy[CombatV1EnergyAttribute.strike], 1);

      // playCounter後はphase==actionへ戻っている（discardは1ターンにつき
      // 1回、ターン開始時のみ）。playerA（active）のターンをそのまま
      // 終了し、playerBの自ターンを開始させる。
      expect(after.phase, CombatV1MatchPhase.action);
      after = CombatV1Engine.endTurn(after, random: Random(2)); // → playerB discard

      expect(after.activePlayerIndex, 1);
      expect(after.playerB.spentEnergy[CombatV1EnergyAttribute.strike] ?? 0, 0);
      expect(after.playerB.availableEnergyFor(CombatV1EnergyAttribute.strike), 2);
    });

    test('COUNTER直後に自動回復しない（endTurnを挟むまでは残ったまま）', () {
      final state = buildMatchState(handA: const [attack], handB: const [counter]);
      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
      final after = CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(1),
      );
      // COUNTER後もphaseはactionへ戻るだけで、ターン境界を跨いでいない。
      expect(after.phase, CombatV1MatchPhase.action);
      expect(after.playerB.spentEnergy[CombatV1EnergyAttribute.strike], 1);
    });
  });

  group('COUNTERはtechniquesUsedThisTurnに含めない（23）', () {
    test('COUNTER成立してもdefenderのtechniquesUsedThisTurnは変化しない', () {
      final state = buildMatchState(handA: const [attack], handB: const [counter]);
      final techniquesUsedBBefore = state.playerB.techniquesUsedThisTurn;
      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
      final after = CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(after.playerB.techniquesUsedThisTurn, techniquesUsedBBefore);
    });

    test('攻撃側のtechniquesUsedThisTurnはTECHNIQUE宣言時点で+1されており、'
        'COUNTER成立/decline問わず変化しない', () {
      final state = buildMatchState(handA: const [attack], handB: const [counter]);
      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
      expect(pending.playerA.techniquesUsedThisTurn, 1);

      final afterCounter = CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(afterCounter.playerA.techniquesUsedThisTurn, 1);
    });
  });

  group('攻撃側のTECHNIQUE ENERGYはCOUNTER後も消費されたまま', () {
    test('COUNTER成立で攻撃が無効化されても、攻撃側が宣言時に支払ったENERGYは戻らない', () {
      final state = buildMatchState(handA: const [attack], handB: const [counter]);
      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
      expect(pending.playerA.spentEnergy[CombatV1EnergyAttribute.strike], 1);

      final after = CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(1),
      );
      // 攻撃が無効化されてもENERGYの返還は無い。
      expect(after.playerA.spentEnergy[CombatV1EnergyAttribute.strike], 1);
    });
  });
}
