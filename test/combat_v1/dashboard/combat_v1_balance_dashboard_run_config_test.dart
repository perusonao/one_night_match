// Balance Dashboard 1B: CombatV1BalanceDashboardRunConfig test
// （lib/src/combat_v1/dashboard/combat_v1_balance_dashboard_run_config.dart）。
//
// docs/design/combat_v1_balance_dashboard_1b.md「Test — Config」（59章）を
// 検証する。pure Dart classのみ・Flutter widgetへの依存なし。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/dashboard/combat_v1_balance_dashboard_run_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_policy.dart';

void main() {
  group('default config（54章「Default Draft」）', () {
    test('1Aのfixed defaultと同一値', () {
      final draft = CombatV1BalanceDashboardRunConfig.initial();
      expect(draft.matchesPreset, CombatV1BalanceDashboardMatchesPreset.quick);
      expect(draft.matchesPerMatchup, 100);
      expect(draft.masterSeed, 12345);
      expect(draft.playerAPolicy, CombatV1SimulationPolicyKind.randomLegal);
      expect(draft.playerBPolicy, CombatV1SimulationPolicyKind.randomLegal);
      expect(draft.maxActions, 500);
      expect(draft.isValid, isTrue);
      expect(draft.totalMatches, 16 * 100);
    });

    test('toBatchConfigはcanonical wrestlerId・固定rulesを持つ', () {
      final draft = CombatV1BalanceDashboardRunConfig.initial();
      final config = draft.toBatchConfig();
      expect(config.wrestlerIds, ['misaki', 'jack', 'akari', 'reina']);
      expect(config.matchesPerMatchup, 100);
      expect(config.masterSeed, 12345);
      expect(config.maxActions, 500);
      expect(config.rules, const CombatV1RulesConfig());
    });
  });

  group('preset（8章「Matches Per Matchup」）', () {
    test('Smoke preset = 20', () {
      final draft = CombatV1BalanceDashboardRunConfig.initial().copyWith(
        matchesPreset: CombatV1BalanceDashboardMatchesPreset.smoke,
      );
      expect(draft.matchesPerMatchup, 20);
      expect(draft.totalMatches, 16 * 20);
      expect(draft.isValid, isTrue);
      expect(draft.showsPerformanceWarning, isFalse);
      expect(draft.requiresRunConfirmation, isFalse);
    });

    test('Quick preset = 100', () {
      final draft = CombatV1BalanceDashboardRunConfig.initial().copyWith(
        matchesPreset: CombatV1BalanceDashboardMatchesPreset.quick,
      );
      expect(draft.matchesPerMatchup, 100);
      expect(draft.totalMatches, 16 * 100);
      expect(draft.isValid, isTrue);
      // >100ではなく==100なので performance warningの対象外。
      expect(draft.showsPerformanceWarning, isFalse);
      expect(draft.requiresRunConfirmation, isFalse);
    });

    test('Analysis preset = 1000、performance warning・confirmation両方対象', () {
      final draft = CombatV1BalanceDashboardRunConfig.initial().copyWith(
        matchesPreset: CombatV1BalanceDashboardMatchesPreset.analysis,
      );
      expect(draft.matchesPerMatchup, 1000);
      expect(draft.totalMatches, 16000);
      expect(draft.isValid, isTrue);
      expect(draft.showsPerformanceWarning, isTrue);
      expect(draft.requiresRunConfirmation, isTrue);
    });
  });

  group('custom range（10章「Hard Max」）', () {
    test('custom valid（例: 250）', () {
      final draft = CombatV1BalanceDashboardRunConfig.initial().copyWith(
        matchesPreset: CombatV1BalanceDashboardMatchesPreset.custom,
        customMatchesPerMatchupText: '250',
      );
      expect(draft.matchesPerMatchup, 250);
      expect(draft.matchesPerMatchupError, isNull);
      expect(draft.isValid, isTrue);
      expect(draft.showsPerformanceWarning, isTrue);
      expect(draft.requiresRunConfirmation, isFalse);
    });

    test('custom invalid: 0は1未満でinvalid', () {
      final draft = CombatV1BalanceDashboardRunConfig.initial().copyWith(
        matchesPreset: CombatV1BalanceDashboardMatchesPreset.custom,
        customMatchesPerMatchupText: '0',
      );
      expect(draft.matchesPerMatchupError, isNotNull);
      expect(draft.isValid, isFalse);
    });

    test('custom invalid: 1001はhard max超過でinvalid', () {
      final draft = CombatV1BalanceDashboardRunConfig.initial().copyWith(
        matchesPreset: CombatV1BalanceDashboardMatchesPreset.custom,
        customMatchesPerMatchupText: '1001',
      );
      expect(draft.matchesPerMatchupError, isNotNull);
      expect(draft.isValid, isFalse);
    });

    test('custom: 1000ちょうどはvalidかつconfirmation対象', () {
      final draft = CombatV1BalanceDashboardRunConfig.initial().copyWith(
        matchesPreset: CombatV1BalanceDashboardMatchesPreset.custom,
        customMatchesPerMatchupText: '1000',
      );
      expect(draft.matchesPerMatchupError, isNull);
      expect(draft.isValid, isTrue);
      expect(draft.requiresRunConfirmation, isTrue);
    });

    test('custom invalid: 空欄', () {
      final draft = CombatV1BalanceDashboardRunConfig.initial().copyWith(
        matchesPreset: CombatV1BalanceDashboardMatchesPreset.custom,
        customMatchesPerMatchupText: '',
      );
      expect(draft.matchesPerMatchupError, isNotNull);
      expect(draft.isValid, isFalse);
    });

    test('custom invalid: 数字でない文字列', () {
      final draft = CombatV1BalanceDashboardRunConfig.initial().copyWith(
        matchesPreset: CombatV1BalanceDashboardMatchesPreset.custom,
        customMatchesPerMatchupText: 'abc',
      );
      expect(draft.matchesPerMatchupError, isNotNull);
      expect(draft.isValid, isFalse);
    });
  });

  group('master seed（11章）', () {
    test('invalid: 空欄はblank不可', () {
      final draft = CombatV1BalanceDashboardRunConfig.initial().copyWith(
        masterSeedText: '',
      );
      expect(draft.masterSeedError, isNotNull);
      expect(draft.isValid, isFalse);
    });

    test('invalid: 整数でない文字列', () {
      final draft = CombatV1BalanceDashboardRunConfig.initial().copyWith(
        masterSeedText: 'not-a-number',
      );
      expect(draft.masterSeedError, isNotNull);
      expect(draft.isValid, isFalse);
    });

    test('valid: 負の整数も許容する（seedは符号を問わない）', () {
      final draft = CombatV1BalanceDashboardRunConfig.initial().copyWith(
        masterSeedText: '-42',
      );
      expect(draft.masterSeedError, isNull);
      expect(draft.masterSeed, -42);
      expect(draft.isValid, isTrue);
    });
  });

  group('max actions（13章）', () {
    test('invalid: 0は1未満', () {
      final draft = CombatV1BalanceDashboardRunConfig.initial().copyWith(
        maxActionsText: '0',
      );
      expect(draft.maxActionsError, isNotNull);
      expect(draft.isValid, isFalse);
    });

    test('invalid: 空欄', () {
      final draft = CombatV1BalanceDashboardRunConfig.initial().copyWith(
        maxActionsText: '',
      );
      expect(draft.maxActionsError, isNotNull);
      expect(draft.isValid, isFalse);
    });

    test('valid: 1は最小値として許容', () {
      final draft = CombatV1BalanceDashboardRunConfig.initial().copyWith(
        maxActionsText: '1',
      );
      expect(draft.maxActionsError, isNull);
      expect(draft.maxActions, 1);
      expect(draft.isValid, isTrue);
    });
  });

  group('policy A/B mapping（12章）', () {
    test('Player A/BへそれぞれFirst Legal/Random Legalを独立に設定できる', () {
      final draft = CombatV1BalanceDashboardRunConfig.initial().copyWith(
        playerAPolicy: CombatV1SimulationPolicyKind.firstLegal,
        playerBPolicy: CombatV1SimulationPolicyKind.randomLegal,
      );
      final config = draft.toBatchConfig();
      expect(config.playerAPolicy, CombatV1SimulationPolicyKind.firstLegal);
      expect(config.playerBPolicy, CombatV1SimulationPolicyKind.randomLegal);
    });

    test('4通りの組み合わせすべてtoBatchConfigへ正しく伝わる', () {
      for (final a in CombatV1SimulationPolicyKind.values) {
        for (final b in CombatV1SimulationPolicyKind.values) {
          final draft = CombatV1BalanceDashboardRunConfig.initial().copyWith(
            playerAPolicy: a,
            playerBPolicy: b,
          );
          final config = draft.toBatchConfig();
          expect(config.playerAPolicy, a);
          expect(config.playerBPolicy, b);
        }
      }
    });
  });
}
