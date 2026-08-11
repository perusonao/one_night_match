// Balance Dashboard 1A: small-scale real integration test
// （docs/design/combat_v1_balance_dashboard_1a.md 16章「Integration
// test」）。
//
// 実`CombatV1BatchSimulationRunner`（Phase 12B-1、engineを実際に起動する）を
// canonical 4 wrestler・1 match/matchup（16 matches）で実行し、
// `CombatV1BalanceDashboardViewModel.fromResult`（pure mapper）まで正しく
// 結線されることを確認する。Dashboard 1Aの正式fixed default
// （100 matches/matchup、1,600 total）そのものの大量再実行はここでは行わない
// ——正式default値の検証は
// [combatV1BalanceDashboardDefaultConfig]の値そのものを確認する軽量testで
// 行う。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/dashboard/combat_v1_balance_dashboard_view_model.dart';
import 'package:one_night_match/src/combat_v1/dashboard/combat_v1_balance_simulation_service.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_matchup.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_simulation_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_simulation_runner.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_policy.dart';

void main() {
  test('combatV1BalanceDashboardDefaultConfigはDashboard 1Aの正式fixed default'
      'と一致する（5章）', () {
    final config = combatV1BalanceDashboardDefaultConfig();
    expect(config.wrestlerIds, ['misaki', 'jack', 'akari', 'reina']);
    expect(config.matchesPerMatchup, 100);
    expect(config.masterSeed, 12345);
    expect(config.playerAPolicy, CombatV1SimulationPolicyKind.randomLegal);
    expect(config.playerBPolicy, CombatV1SimulationPolicyKind.randomLegal);
    expect(config.maxActions, 500);
  });

  test(
    'runner→mapperの実結線: canonical 4 wrestler・1 match/matchup（16 matches）',
    () {
      // Dashboard 1Aのfixed configと同じwrestler/seed/policy/maxActionsを
      // 使い、matchesPerMatchupのみ小さくした構成で、実engineを起動する
      // runner→pure ViewModel mapperの結線を確認する（53章）。
      final config = CombatV1BatchSimulationConfig(
        wrestlerIds: combatV1DefaultBatchWrestlerIds,
        matchesPerMatchup: 1,
        masterSeed: 12345,
        pairing: CombatV1PolicyPairing.randomVsRandom,
        maxActions: 500,
      );
      const runner = CombatV1BatchSimulationRunner();
      final result = runner.run(config);

      expect(result.requestedMatchCount, 16);
      expect(result.executedMatchCount, 16);

      final viewModel = CombatV1BalanceDashboardViewModel.fromResult(result);

      expect(viewModel.runSummary.masterSeed, 12345);
      expect(viewModel.runSummary.executedMatchCount, 16);
      expect(viewModel.runSummary.wrestlerIds, [
        'misaki',
        'jack',
        'akari',
        'reina',
      ]);

      expect(viewModel.wrestlerRows, hasLength(4));
      expect(
        viewModel.wrestlerRows.map((r) => r.wrestlerId),
        ['misaki', 'jack', 'akari', 'reina'],
      );

      expect(viewModel.matchupMatrix.wrestlerIds, [
        'misaki',
        'jack',
        'akari',
        'reina',
      ]);
      expect(viewModel.matchupMatrix.rows, hasLength(4));
      for (final row in viewModel.matchupMatrix.rows) {
        expect(row, hasLength(4));
      }
      // diagonal（mirror）が正しく検出されている。
      for (var i = 0; i < 4; i++) {
        expect(viewModel.matchupMatrix.rows[i][i].isMirror, isTrue);
      }

      expect(viewModel.globalSummary.totalMatches, 16);
      // completedMatches <= totalMatches（safety/invariantを含んでもよい）。
      expect(
        viewModel.globalSummary.completedMatches,
        lessThanOrEqualTo(16),
      );

      // Player A/B panelの分母は常にglobal completedMatchesと一致する
      // （Phase 12B-1 23章の契約、ViewModelはそのままpass-throughする）。
      expect(
        viewModel.seatSummary.playerACompletedMatches,
        viewModel.globalSummary.completedMatches,
      );
      expect(
        viewModel.seatSummary.playerBCompletedMatches,
        viewModel.globalSummary.completedMatches,
      );
    },
  );
}
