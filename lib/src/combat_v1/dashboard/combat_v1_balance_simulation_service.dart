/// Balance Dashboard 1A — Simulation Service
/// （docs/design/combat_v1_balance_dashboard_1a.md 5・11・24章）。
///
/// [combatV1BalanceDashboardDefaultConfig]がDashboard 1Aの正式fixed
/// default config（5章）を組み立て、[CombatV1BalanceSimulationService]が
/// Stopwatch計測 → `CombatV1BatchSimulationRunner.run`呼び出し → pure
/// ViewModel mapping → [CombatV1BalanceRunOutput]構築、を行う薄い
/// service層。
///
/// Batch Runner本体（`CombatV1BatchSimulationRunner`）へprogress
/// callback・cancellation・chunkingを追加しない（Core変更禁止、57章）。
/// Development Snapshot writer（`dart:io`依存）はimportしない（7章）。
library;

import '../simulation/batch/combat_v1_batch_matchup.dart';
import '../simulation/batch/combat_v1_batch_simulation_config.dart';
import '../simulation/batch/combat_v1_batch_simulation_runner.dart';
import 'combat_v1_balance_dashboard_view_model.dart';

/// Dashboard 1Aの正式fixed default config（5章「Fixed Default Config」）。
///
/// `CombatV1BatchSimulationConfig`自体のdefault値とは独立に、このfileが
/// Dashboard 1Aの「正式default」を明示的に定義する唯一の場所とする。
CombatV1BatchSimulationConfig combatV1BalanceDashboardDefaultConfig() =>
    CombatV1BatchSimulationConfig(
      wrestlerIds: combatV1DefaultBatchWrestlerIds,
      matchesPerMatchup: 100,
      masterSeed: 12345,
      pairing: CombatV1PolicyPairing.randomVsRandom,
      maxActions: 500,
    );

/// 1回のDashboard runの結果（26章「Run Output」）。
///
/// domain result（`CombatV1BatchSimulationResult`）自体は保持しない——
/// Dashboard 1AのUIはViewModelのみで完結するため、軽量な構造とする
/// （10章「State Model」）。
class CombatV1BalanceRunOutput {
  const CombatV1BalanceRunOutput({
    required this.viewModel,
    required this.runtime,
    required this.ranAt,
  });

  final CombatV1BalanceDashboardViewModel viewModel;

  /// UI/service側`Stopwatch`計測値。domain resultへは持たせない（27章
  /// 「Run Metadata」、50章「Generated At」——determinismへ影響させない）。
  final Duration runtime;

  /// `DateTime.now()`で記録するUI/service metadata。domain/statisticsへは
  /// 一切渡さない。
  final DateTime ranAt;
}

/// production/testで差し替え可能なrun function（25章「Test Injection」）。
///
/// Widget testでは1,600 simulationを実行させず、この型のfakeを注入する。
typedef CombatV1BalanceRunFunction = Future<CombatV1BalanceRunOutput> Function();

/// Dashboard 1A用の薄いsimulation service（24章「Service / Runner
/// Wrapper」）。repository/interface hierarchyは持たない。
class CombatV1BalanceSimulationService {
  const CombatV1BalanceSimulationService();

  /// fixed default configで1回batch simulationを実行し、[CombatV1BalanceRunOutput]
  /// を返す（19章「Run Default Simulation」5〜10のステップ）。
  ///
  /// 例外（`CombatV1IllegalActionException`等）はcatchせずそのまま
  /// 呼び出し元（UI側）へ伝播する——呼び出し元がerror stateへ遷移させる
  /// 責務を持つ（19章11、46章「Error Handling」）。
  Future<CombatV1BalanceRunOutput> run() async {
    final config = combatV1BalanceDashboardDefaultConfig();
    final stopwatch = Stopwatch()..start();
    const runner = CombatV1BatchSimulationRunner();
    final result = runner.run(config);
    final viewModel = CombatV1BalanceDashboardViewModel.fromResult(result);
    stopwatch.stop();
    return CombatV1BalanceRunOutput(
      viewModel: viewModel,
      runtime: stopwatch.elapsed,
      ranAt: DateTime.now(),
    );
  }
}
