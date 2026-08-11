// Combat Ver.1 Phase 12B-1: CombatV1BatchSimulationConfig
// （lib/src/combat_v1/simulation/batch/combat_v1_batch_simulation_config.dart）
// のtest。
//
// docs/design/combat_v1_phase12b1_batch_core_aggregation.md 8・9章、および
// 36章「TESTS — CONFIG」を検証する。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_matchup.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_simulation_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_policy.dart';

void main() {
  group('CombatV1BatchSimulationConfig', () {
    test('default wrestlerIdsはmisaki/jack/akari/reina', () {
      final config = CombatV1BatchSimulationConfig(
        matchesPerMatchup: 1,
        masterSeed: 1,
      );
      expect(config.wrestlerIds, ['misaki', 'jack', 'akari', 'reina']);
    });

    test('default pairingはrandomLegal/randomLegal', () {
      final config = CombatV1BatchSimulationConfig(
        matchesPerMatchup: 1,
        masterSeed: 1,
      );
      expect(config.playerAPolicy, CombatV1SimulationPolicyKind.randomLegal);
      expect(config.playerBPolicy, CombatV1SimulationPolicyKind.randomLegal);
      expect(config.pairing, CombatV1PolicyPairing.randomVsRandom);
    });

    test('default maxActionsは500', () {
      final config = CombatV1BatchSimulationConfig(
        matchesPerMatchup: 1,
        masterSeed: 1,
      );
      expect(config.maxActions, 500);
    });

    test('wrestlerIdsはunmodifiable', () {
      final config = CombatV1BatchSimulationConfig(
        matchesPerMatchup: 1,
        masterSeed: 1,
      );
      expect(() => config.wrestlerIds.add('x'), throwsUnsupportedError);
    });

    test('wrestlerIdsのdefensive copy: 呼び出し側のリスト変更が反映されない', () {
      final source = ['misaki', 'jack'];
      final config = CombatV1BatchSimulationConfig(
        wrestlerIds: source,
        matchesPerMatchup: 1,
        masterSeed: 1,
      );
      source.add('akari');
      expect(config.wrestlerIds, ['misaki', 'jack']);
    });

    test('明示的なpairing/maxActions/rulesが反映される', () {
      const pairing = CombatV1PolicyPairing(
        playerAPolicy: CombatV1SimulationPolicyKind.firstLegal,
        playerBPolicy: CombatV1SimulationPolicyKind.randomLegal,
      );
      final config = CombatV1BatchSimulationConfig(
        wrestlerIds: const ['misaki', 'jack'],
        matchesPerMatchup: 5,
        masterSeed: 42,
        pairing: pairing,
        maxActions: 200,
      );
      expect(config.matchesPerMatchup, 5);
      expect(config.masterSeed, 42);
      expect(config.pairing, pairing);
      expect(config.maxActions, 200);
    });

    test('wrestlerIdsが空なら拒否', () {
      expect(
        () => CombatV1BatchSimulationConfig(
          wrestlerIds: const [],
          matchesPerMatchup: 1,
          masterSeed: 1,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('wrestlerIdsに重複があれば拒否', () {
      expect(
        () => CombatV1BatchSimulationConfig(
          wrestlerIds: const ['misaki', 'jack', 'misaki'],
          matchesPerMatchup: 1,
          masterSeed: 1,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('未知のwrestlerIdは拒否', () {
      expect(
        () => CombatV1BatchSimulationConfig(
          wrestlerIds: const ['misaki', 'unknown-wrestler'],
          matchesPerMatchup: 1,
          masterSeed: 1,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('空白のみのwrestlerIdは拒否', () {
      expect(
        () => CombatV1BatchSimulationConfig(
          wrestlerIds: const ['misaki', '   '],
          matchesPerMatchup: 1,
          masterSeed: 1,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('空文字列のwrestlerIdは拒否', () {
      expect(
        () => CombatV1BatchSimulationConfig(
          wrestlerIds: const ['misaki', ''],
          matchesPerMatchup: 1,
          masterSeed: 1,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('matchesPerMatchup <= 0は拒否', () {
      expect(
        () =>
            CombatV1BatchSimulationConfig(matchesPerMatchup: 0, masterSeed: 1),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(
        () =>
            CombatV1BatchSimulationConfig(matchesPerMatchup: -1, masterSeed: 1),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('maxActions <= 0は拒否', () {
      expect(
        () => CombatV1BatchSimulationConfig(
          matchesPerMatchup: 1,
          masterSeed: 1,
          maxActions: 0,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });
}
