// Combat Ver.1 Phase 12A: Simulation seed derivation
// （lib/src/combat_v1/simulation/combat_v1_simulation_seed.dart）のtest。
//
// deterministic・versioned・pure functionであること、masterSeed/matchIndex/
// wrestler/policyの各要素がmatchSeedへ正しく反映されること、
// engine/A/B policy seedが分離していることを検証する。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_seed.dart';

CombatV1SimulationSeedSet _seeds({
  int masterSeed = 12345,
  int matchIndex = 0,
  String wrestlerAId = 'misaki',
  String wrestlerBId = 'jack',
  String playerAPolicyId = 'firstLegal',
  String playerBPolicyId = 'randomLegal',
}) => deriveV1SimulationSeeds(
  masterSeed: masterSeed,
  matchIndex: matchIndex,
  wrestlerAId: wrestlerAId,
  wrestlerBId: wrestlerBId,
  playerAPolicyId: playerAPolicyId,
  playerBPolicyId: playerBPolicyId,
);

void main() {
  group('A. 同じ入力→同じseed（pure function）', () {
    test('同じ引数を複数回呼んでも全fieldが一致する', () {
      final a = _seeds();
      final b = _seeds();

      expect(a.matchSeed, b.matchSeed);
      expect(a.engineSeed, b.engineSeed);
      expect(a.playerAPolicySeed, b.playerAPolicySeed);
      expect(a.playerBPolicySeed, b.playerBPolicySeed);
      expect(a.derivationVersion, b.derivationVersion);
    });
  });

  group('B. matchIndex違い→matchSeed違い', () {
    test('matchIndexだけを変えるとmatchSeedが変わる', () {
      final a = _seeds(matchIndex: 0);
      final b = _seeds(matchIndex: 1);

      expect(a.matchSeed, isNot(b.matchSeed));
    });

    test('matchIndexが安定していれば同じmatchSeedへ戻る', () {
      final a = _seeds(matchIndex: 5);
      final b = _seeds(matchIndex: 5);

      expect(a.matchSeed, b.matchSeed);
    });
  });

  group('C. engine/A/B seedが分離', () {
    test('同一matchSeedから導出される3本のseedは互いに異なる', () {
      final seeds = _seeds();

      expect(seeds.engineSeed, isNot(seeds.playerAPolicySeed));
      expect(seeds.engineSeed, isNot(seeds.playerBPolicySeed));
      expect(seeds.playerAPolicySeed, isNot(seeds.playerBPolicySeed));
    });
  });

  group('D. wrestler違い→matchSeed違い', () {
    test('wrestlerAIdが違えばmatchSeedが変わる', () {
      final a = _seeds(wrestlerAId: 'misaki');
      final b = _seeds(wrestlerAId: 'akari');

      expect(a.matchSeed, isNot(b.matchSeed));
    });

    test('wrestlerBIdが違えばmatchSeedが変わる', () {
      final a = _seeds(wrestlerBId: 'jack');
      final b = _seeds(wrestlerBId: 'reina');

      expect(a.matchSeed, isNot(b.matchSeed));
    });
  });

  group('E. policy違い→matchSeed違い', () {
    test('playerAPolicyIdが違えばmatchSeedが変わる', () {
      final a = _seeds(playerAPolicyId: 'firstLegal');
      final b = _seeds(playerAPolicyId: 'randomLegal');

      expect(a.matchSeed, isNot(b.matchSeed));
    });

    test('playerBPolicyIdが違えばmatchSeedが変わる', () {
      final a = _seeds(playerBPolicyId: 'firstLegal');
      final b = _seeds(playerBPolicyId: 'randomLegal');

      expect(a.matchSeed, isNot(b.matchSeed));
    });
  });

  group('F. masterSeed違い→matchSeed違い', () {
    test('masterSeedが違えばmatchSeedが変わる', () {
      final a = _seeds(masterSeed: 1);
      final b = _seeds(masterSeed: 2);

      expect(a.matchSeed, isNot(b.matchSeed));
    });
  });

  group('G. derivation versionが固定', () {
    test('derivationVersionは公開定数combatV1SeedDerivationVersionと一致する', () {
      final seeds = _seeds();
      expect(seeds.derivationVersion, combatV1SeedDerivationVersion);
      expect(combatV1SeedDerivationVersion, isPositive);
    });
  });

  group('H. matchIndex/masterSeedがresultへ複製される', () {
    test('引数と同じ値がそのままCombatV1SimulationSeedSetへ入る', () {
      final seeds = _seeds(masterSeed: 999, matchIndex: 7);
      expect(seeds.masterSeed, 999);
      expect(seeds.matchIndex, 7);
    });
  });
}
