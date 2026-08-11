// Combat Ver.1 Phase 12A: CombatV1SimulationConfig
// （lib/src/combat_v1/simulation/combat_v1_simulation_config.dart）のtest。
//
// fail-fast validation（matchCount/maxActions<=0・unknown wrestler）と、
// validな入力が正しく保持されることを検証する。
//
// 旧「E. invalid policy拒否」（playerAPolicy.idが空白のみのcustom
// CombatV1SimulationPolicySpecを拒否する）は、Codex review Major Finding
// M1対応でCombatV1SimulationPolicySpec（任意のfactory closureを注入できる
// public API）自体を廃止したため、テスト対象のAPI面がもう存在しない。
// 置き換えとして「E. policy APIが構造的に2種類へ閉じている」を追加し、
// 同じ懸念（任意のpolicyを注入できてしまう）を新しいAPI形状で確認する。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_policy.dart';

CombatV1SimulationConfig _validConfig({
  int matchCount = 1,
  int maxActions = 500,
  String wrestlerAId = 'misaki',
  String wrestlerBId = 'jack',
}) => CombatV1SimulationConfig(
  wrestlerAId: wrestlerAId,
  wrestlerBId: wrestlerBId,
  playerAPolicy: CombatV1SimulationPolicyKind.firstLegal,
  playerBPolicy: CombatV1SimulationPolicyKind.randomLegal,
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
      expect(config.playerAPolicy, CombatV1SimulationPolicyKind.firstLegal);
      expect(config.playerBPolicy, CombatV1SimulationPolicyKind.randomLegal);
      expect(config.playerAPolicy.policyId, 'firstLegal');
      expect(config.playerBPolicy.policyId, 'randomLegal');
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
        playerAPolicy: CombatV1SimulationPolicyKind.firstLegal,
        playerBPolicy: CombatV1SimulationPolicyKind.firstLegal,
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

  group('E. policy APIが構造的に2種類へ閉じている（Codex review M1対応）', () {
    test('CombatV1SimulationPolicyKindはfirstLegal/randomLegalの2種類のみ', () {
      expect(CombatV1SimulationPolicyKind.values, hasLength(2));
      expect(
        CombatV1SimulationPolicyKind.values,
        containsAll(<CombatV1SimulationPolicyKind>[
          CombatV1SimulationPolicyKind.firstLegal,
          CombatV1SimulationPolicyKind.randomLegal,
        ]),
      );
    });

    test('playerAPolicy/playerBPolicyはCombatV1SimulationPolicyKind型のみを'
        '受け付ける（任意のfactory closureをpublic APIへ注入する経路が'
        '存在しない）', () {
      // CombatV1SimulationConfigのplayerAPolicy/playerBPolicyフィールドは
      // enum型で宣言されているため、CombatV1SimulationPolicyKind.values
      // 以外の値は型システム上そもそも渡せない
      // （コンパイルエラーになる。実行時validationではなく型による保証）。
      final config = _validConfig();
      expect(config.playerAPolicy, isA<CombatV1SimulationPolicyKind>());
      expect(config.playerBPolicy, isA<CombatV1SimulationPolicyKind>());
    });
  });
}
