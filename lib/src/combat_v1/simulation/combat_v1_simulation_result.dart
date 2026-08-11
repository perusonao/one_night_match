/// Combat Ver.1 Phase 12A — Simulation Result
/// （docs/design/combat_v1_phase12a_simulation_core.md）。
///
/// [CombatV1SimulationRunner]が複数試合実行した結果全体。4×4 matchup
/// matrix・wrestler別勝率・balance statistics・warning判定・CSV・dashboard
/// はPhase 12B以降のスコープであり、ここでは含めない（20章）。整合確認用の
/// 最小限のderived getterのみを提供する。
library;

import '../combat_v1_cpu_match_runner.dart';
import 'combat_v1_match_simulation_result.dart';
import 'combat_v1_simulation_config.dart';

/// [CombatV1SimulationRunner.run]の結果（Phase 12A）。
class CombatV1SimulationResult {
  CombatV1SimulationResult({
    required this.config,
    required List<CombatV1MatchSimulationResult> matches,
    required this.requestedMatchCount,
    required this.executedMatchCount,
  }) : matches = List.unmodifiable(matches);

  /// このSimulationを実行した[CombatV1SimulationConfig]のsnapshot（Replay
  /// metadataの一部。12章）。
  final CombatV1SimulationConfig config;

  /// 実行された各試合の[CombatV1MatchSimulationResult]（unmodifiable、
  /// `matchIndex`昇順）。
  final List<CombatV1MatchSimulationResult> matches;

  /// [CombatV1SimulationConfig.matchCount]と同じ値（要求された試合数）。
  final int requestedMatchCount;

  /// 実際に実行された試合数（[matches.length]と同じ値）。
  final int executedMatchCount;

  /// `termination == matchOver`で終了した試合数。
  int get completedCount => matches
      .where((m) => m.termination == CombatV1CpuMatchTermination.matchOver)
      .length;

  /// `termination == safetyLimit`で終了した試合数。
  int get safetyLimitCount => matches
      .where((m) => m.termination == CombatV1CpuMatchTermination.safetyLimit)
      .length;

  /// `termination == invariantViolation`で終了した試合数。Phase 12Aの
  /// 通常運用では0であることが期待される（14章「Invariant Validation」）。
  int get invariantViolationCount => matches
      .where(
        (m) => m.termination == CombatV1CpuMatchTermination.invariantViolation,
      )
      .length;
}
