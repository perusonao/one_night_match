// Combat Ver.1 Playable 1A — CombatV1PlayableMatchConfig。
//
// fail-fast validation（未知wrestlerId・maxActions<=0）・mirror match許可・
// owner ID helperの決定論性/A-B分離を検証する。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_config.dart';

void main() {
  group('CombatV1PlayableMatchConfig validation', () {
    test('未知のhumanWrestlerIdはfail-fastで拒否される', () {
      expect(
        () => CombatV1PlayableMatchConfig(
          humanWrestlerId: 'unknown_wrestler',
          cpuWrestlerId: 'misaki',
          engineSeed: 1,
          cpuPolicySeed: 2,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('未知のcpuWrestlerIdはfail-fastで拒否される', () {
      expect(
        () => CombatV1PlayableMatchConfig(
          humanWrestlerId: 'misaki',
          cpuWrestlerId: 'unknown_wrestler',
          engineSeed: 1,
          cpuPolicySeed: 2,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('maxActions<=0はfail-fastで拒否される', () {
      expect(
        () => CombatV1PlayableMatchConfig(
          humanWrestlerId: 'misaki',
          cpuWrestlerId: 'jack',
          engineSeed: 1,
          cpuPolicySeed: 2,
          maxActions: 0,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('mirror match（同一wrestlerId同士）は許可される', () {
      expect(
        () => CombatV1PlayableMatchConfig(
          humanWrestlerId: 'misaki',
          cpuWrestlerId: 'misaki',
          engineSeed: 1,
          cpuPolicySeed: 2,
        ),
        returnsNormally,
      );
    });

    test('既定値: maxActions==500, cpuPolicyKind==randomLegal', () {
      final config = CombatV1PlayableMatchConfig(
        humanWrestlerId: 'misaki',
        cpuWrestlerId: 'jack',
        engineSeed: 1,
        cpuPolicySeed: 2,
      );
      expect(config.maxActions, 500);
      expect(config.cpuPolicyKind, CombatV1PlayableCpuPolicyKind.randomLegal);
    });
  });

  group('combatV1PlayableOwnerId', () {
    test('同じengineSeedでも、playerSuffixが異なればowner IDは異なる', () {
      final humanOwnerId = combatV1PlayableOwnerId(
        engineSeed: 42,
        playerSuffix: 'human',
      );
      final cpuOwnerId = combatV1PlayableOwnerId(
        engineSeed: 42,
        playerSuffix: 'cpu',
      );
      expect(humanOwnerId, isNot(cpuOwnerId));
    });

    test('決定論的: 同じ引数なら常に同じ値を返す', () {
      final a = combatV1PlayableOwnerId(engineSeed: 7, playerSuffix: 'human');
      final b = combatV1PlayableOwnerId(engineSeed: 7, playerSuffix: 'human');
      expect(a, b);
    });
  });
}
