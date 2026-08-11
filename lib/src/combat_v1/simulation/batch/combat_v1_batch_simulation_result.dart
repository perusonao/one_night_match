/// Combat Ver.1 Phase 12B-1 — Batch Simulation Result
/// （docs/design/combat_v1_phase12b1_batch_core_aggregation.md 19章）。
///
/// [CombatV1BatchSimulationRunner]（`combat_v1_batch_simulation_runner.dart`）
/// がbatch実行を完了した結果全体。個別match resultは一切保持しない
/// （aggregate-only、17章）。
///
/// [statistics]（Phase 12B-2A、
/// docs/design/combat_v1_phase12b2a_match_length_statistics.md 7章）は、
/// 既存field群への後方互換なadditive extension——既存fieldのrename・
/// semantic変更は一切行わない。
library;

import 'combat_v1_batch_aggregate.dart';
import 'combat_v1_batch_length_statistics.dart';
import 'combat_v1_batch_simulation_config.dart';

/// [CombatV1BatchSimulationRunner.run]の結果（Phase 12B-1）。immutable。
class CombatV1BatchSimulationResult {
  CombatV1BatchSimulationResult({
    required this.config,
    required this.requestedMatchCount,
    required this.executedMatchCount,
    required this.global,
    required List<CombatV1MatchupAggregate> matchups,
    required List<CombatV1WrestlerAggregate> wrestlers,
    required this.seat,
    required this.mirror,
    required this.statistics,
  }) : matchups = List.unmodifiable(matchups),
       wrestlers = List.unmodifiable(wrestlers);

  /// このbatchを実行した[CombatV1BatchSimulationConfig]のsnapshot（replay
  /// metadataの一部）。
  final CombatV1BatchSimulationConfig config;

  /// `matrix.length * config.matchesPerMatchup`と同じ値（要求された試合数）。
  final int requestedMatchCount;

  /// 実際に実行された試合数（正常時は[requestedMatchCount]と一致）。
  final int executedMatchCount;

  final CombatV1GlobalAggregate global;

  /// canonical matrix順（初出順）、unmodifiable。
  final List<CombatV1MatchupAggregate> matchups;

  /// wrestlerId初出順、unmodifiable。
  final List<CombatV1WrestlerAggregate> wrestlers;

  final CombatV1SeatAggregate seat;
  final CombatV1MirrorAggregate mirror;

  /// Phase 12B-2A — completed-only match length descriptive statistics
  /// （Global / Ordered Matchup単位）。
  final CombatV1BatchDescriptiveStatistics statistics;

  /// [global.termination]と同一instance（19章「Result Hierarchy」——別途
  /// 再計算しない利便性field）。
  CombatV1TerminationDistribution get termination => global.termination;
}
