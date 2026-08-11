/// Combat Ver.1 Phase 12B-2A — Match Length Descriptive Statistics value
/// types（docs/design/combat_v1_phase12b2a_match_length_statistics.md
/// 7・8・16章）。
///
/// [CombatV1BatchDescriptiveStatisticsAccumulator]
/// （`combat_v1_batch_length_statistics_accumulator.dart`）が構築する、
/// immutableな結果の型群。Phase 12B-1既存のaggregate schema
/// （`combat_v1_batch_aggregate.dart`）とは独立したtreeとして追加する
/// ——`CombatV1GlobalAggregate`/`CombatV1MatchupAggregate`自体は変更しない
/// （19章「Statistics Tree」）。
library;

import 'combat_v1_batch_matchup.dart';

/// 1つの整数distribution（`actionCount`または`finalTurnNumber`）の
/// descriptive statistics（18章「Proposed Public Types」）。immutable。
///
/// `sampleCount == 0`の場合、[mean]/[median]/[p90]/[p95]/[min]/[max]は
/// すべて`null`——`0`や`0.0`をfabricateしない（13章「Empty Sample
/// Semantics」）。
class CombatV1NumericDistributionSummary {
  const CombatV1NumericDistributionSummary({
    required this.sampleCount,
    required this.mean,
    required this.median,
    required this.p90,
    required this.p95,
    required this.min,
    required this.max,
  });

  /// `sampleCount == 0`のcanonical empty value（13章）。
  static const CombatV1NumericDistributionSummary empty =
      CombatV1NumericDistributionSummary(
        sampleCount: 0,
        mean: null,
        median: null,
        p90: null,
        p95: null,
        min: null,
        max: null,
      );

  final int sampleCount;

  /// 整数`sum`/`sampleCount`から計算した算術平均（14章「Mean」）。
  /// incremental floating meanは使わない。
  final double? mean;

  /// odd sampleは中央1値、even sampleは中央2値の算術平均（15章
  /// 「Median」）。
  final double? median;

  /// nearest-rank方式（`rank = ceil(0.90 * sampleCount)`、16章「P90 / P95」）。
  final double? p90;

  /// nearest-rank方式（`rank = ceil(0.95 * sampleCount)`、16章「P90 / P95」）。
  final double? p95;

  final int? min;
  final int? max;
}

/// completed matchの`actionCount`/`finalTurnNumber`の分布（Phase 12B-2A
/// 「Required Metrics」12章）。immutable。
class CombatV1MatchLengthStatistics {
  const CombatV1MatchLengthStatistics({
    required this.actionCount,
    required this.finalTurnNumber,
  });

  /// [sampleCount]が両方0のcanonical empty value。
  static const CombatV1MatchLengthStatistics empty = CombatV1MatchLengthStatistics(
    actionCount: CombatV1NumericDistributionSummary.empty,
    finalTurnNumber: CombatV1NumericDistributionSummary.empty,
  );

  final CombatV1NumericDistributionSummary actionCount;
  final CombatV1NumericDistributionSummary finalTurnNumber;
}

/// batch全体のGlobal descriptive statistics（19章「Statistics Tree」）。
///
/// [length]のみを持つ中間wrapperとして設計する——Phase 12B-2B（final state
/// statistics）が将来、この同じwrapperへ`finalState`のような兄弟fieldを
/// additiveに追加できる余地を残すため（Phase 12B-2A自身はこの余地を使わ
/// ない）。
class CombatV1GlobalDescriptiveStatistics {
  const CombatV1GlobalDescriptiveStatistics({required this.length});

  final CombatV1MatchLengthStatistics length;
}

/// 1 matchup（`CombatV1Matchup`）単位のdescriptive statistics（19章）。
class CombatV1MatchupDescriptiveStatistics {
  const CombatV1MatchupDescriptiveStatistics({
    required this.matchup,
    required this.length,
  });

  final CombatV1Matchup matchup;
  final CombatV1MatchLengthStatistics length;
}

/// [CombatV1BatchDescriptiveStatisticsAccumulator.build]の戻り値（19章）。
/// `CombatV1BatchSimulationResult.statistics`としてPhase 12B-1既存treeの
/// 外側へ追加する。
class CombatV1BatchDescriptiveStatistics {
  CombatV1BatchDescriptiveStatistics({
    required this.global,
    required List<CombatV1MatchupDescriptiveStatistics> matchups,
  }) : matchups = List.unmodifiable(matchups);

  final CombatV1GlobalDescriptiveStatistics global;

  /// canonical matchup順（Phase 12B-1 `result.matchups`と同じ初出順、
  /// 20章「Matchup Statistics Order」）、unmodifiable。
  final List<CombatV1MatchupDescriptiveStatistics> matchups;
}
