// Combat Ver.1 Phase 12A: CombatV1SimulationConfig
// （lib/src/combat_v1/simulation/combat_v1_simulation_config.dart）のtest。
//
// fail-fast validation（matchCount/maxActions<=0・unknown wrestler・空
// policy id）と、validな入力が正しく保持されることを検証する。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_config.dart';

CombatV1SimulationConfig _validConfig({
  int matchCount = 1,
  int maxActions = 500,
  String wrestlerAId = 'misaki',
  String wrestlerBId = 'jack',
}) => CombatV1SimulationConfig(
  wrestlerAId: wrestlerAId,
  wrestlerBId: wrestlerBId,
  playerAPolicy: CombatV1SimulationPolicySpec.firstLegal,
  playerBPolicy: CombatV1SimulationPolicySpec.randomLegal,
  matchCount: matchCount,
  masterSeed: 42,
  maxActions: maxActions,
);

void main() {
  group('A. valid config', () {
    test('必須値がそのまま保持される', () {
      final config = _validConfig();

      expect(config.wrestlerAId, 'misaki');
      expect(config.wrestlerBId, 'jack');
      expect(config.playerAPolicy.id, 'firstLegal');
      expect(config.playerBPolicy.id, 'randomLegal');
      expect(config.matchCount, 1);
      expect(config.masterSeed, 42);
      expect(config.maxActions, 500);
      expect(config.rules, const CombatV1RulesConfig());
    });

    test('mirror match（同一wrestler同士）も許容する', () {
      expect(
        () => _validConfig(wrestlerAId: 'misaki', wrestlerBId: 'misaki'),
        returnsNormally,
      );
    });

    test('rulesを明示的に上書きできる', () {
      const customRules = CombatV1RulesConfig(startingHp: 200);
      final config = CombatV1SimulationConfig(
        wrestlerAId: 'akari',
        wrestlerBId: 'reina',
        playerAPolicy: CombatV1SimulationPolicySpec.firstLegal,
        playerBPolicy: CombatV1SimulationPolicySpec.firstLegal,
        matchCount: 1,
        masterSeed: 1,
        rules: customRules,
      );
      expect(config.rules.startingHp, 200);
    });
  });

  group('B. matchCount拒否', () {
    test('matchCount == 0は拒否', () {
      expect(
        () => _validConfig(matchCount: 0),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('matchCount < 0は拒否', () {
      expect(
        () => _validConfig(matchCount: -1),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('C. maxActions拒否', () {
    test('maxActions == 0は拒否', () {
      expect(
        () => _validConfig(maxActions: 0),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('maxActions < 0は拒否', () {
      expect(
        () => _validConfig(maxActions: -1),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('D. unknown wrestler拒否', () {
    test('未知のwrestlerAIdは拒否', () {
      expect(
        () => _validConfig(wrestlerAId: 'not-a-wrestler'),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('未知のwrestlerBIdは拒否', () {
      expect(
        () => _validConfig(wrestlerBId: 'not-a-wrestler'),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('E. invalid policy拒否', () {
    test('playerAPolicy.idが空白のみなら拒否', () {
      expect(
        () => CombatV1SimulationConfig(
          wrestlerAId: 'misaki',
          wrestlerBId: 'jack',
          playerAPolicy: CombatV1SimulationPolicySpec(
            id: '   ',
            create: CombatV1SimulationPolicySpec.randomLegal.create,
          ),
          playerBPolicy: CombatV1SimulationPolicySpec.firstLegal,
          matchCount: 1,
          masterSeed: 1,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });
}
