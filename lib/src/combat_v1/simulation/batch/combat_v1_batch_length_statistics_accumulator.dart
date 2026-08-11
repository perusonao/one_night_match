/// Combat Ver.1 Phase 12B-2A — Match Length Statistics Accumulator
/// （docs/design/combat_v1_phase12b2a_match_length_statistics.md 13〜21章）。
///
/// [CombatV1MatchSimulationResult]をstreamingで受け取り、completed match
/// （`termination == matchOver`）の`actionCount`/`finalTurnNumber`について
/// exact bounded histogram（sparse `Map<int, int>`）を積み上げるmutable
/// accumulator。Raw valueのListは一切保持しない（21章「Histogram
/// Strategy」）——memory complexityはobserved distinct valueの数に比例し、
/// `O(totalMatches)`にはならない（19章「Streaming Memory」）。
///
/// Phase 12B-1の[CombatV1BatchAggregationAccumulator]
/// （`combat_v1_batch_aggregator.dart`）とは完全に独立したaccumulatorであり
/// ——このfileは`combat_v1_batch_aggregator.dart`/`combat_v1_batch_aggregate.dart`
/// を一切importしない。Batch Runnerが両accumulatorへ同じ
/// `CombatV1MatchSimulationResult`を渡すのみで接続する（20章「Batch Runner
/// Integration」）。
library;

import '../../combat_v1_cpu_match_runner.dart';
import '../combat_v1_match_simulation_result.dart';
import 'combat_v1_batch_length_statistics.dart';
import 'combat_v1_batch_matchup.dart';

/// `ceil(a / b)`を整数演算のみで計算する（`a`, `b`は正の整数）。
///
/// p90/p95のrank計算（11章「P90 / P95 Algorithm」）で、浮動小数点乗算
/// （`0.90 * sampleCount`）を経由しないために使う——VM/Web間の浮動小数点
/// 誤差を構造的に排除する。
int _ceilDiv(int a, int b) => (a + b - 1) ~/ b;

/// 1つの整数distribution（`actionCount`または`finalTurnNumber`）用の
/// exact bounded histogram accumulator（internal、13章「Histogram
/// Strategy」）。
///
/// 固定`List<int>`ではなく、sparse `Map<int, int>`（value → 出現回数）を
/// 採用する——memoryが`config.maxActions`の値ではなく、実際に観測した
/// distinct valueの数にのみ比例するようにするため（design doc 13章参照）。
class _CombatV1HistogramAccumulator {
  int _sampleCount = 0;
  int _sum = 0;
  final Map<int, int> _counts = {};

  /// [value]を1件追加する。
  void add(int value) {
    _sampleCount += 1;
    _sum += value;
    _counts.update(value, (count) => count + 1, ifAbsent: () => 1);
  }

  int get sampleCount => _sampleCount;

  /// 現時点までの[add]内容から[CombatV1NumericDistributionSummary]を構築
  /// する。呼び出し後もこのaccumulator自身は引き続きmutableなまま
  /// （build結果はimmutable snapshotであり、その後の[add]で変化しない、
  /// 「Immutability」章参照）。
  CombatV1NumericDistributionSummary build() {
    if (_sampleCount == 0) {
      return CombatV1NumericDistributionSummary.empty;
    }

    // sorted distinct values——sortの対象はobserved distinct value数のみ
    // （sampleCountそのものではない）。Map iteration順（insertion/hash順）
    // に一切依存しない、determinismの根拠（23章「Snapshot Determinism」）。
    final sortedValues = _counts.keys.toList()..sort();

    // 1-based rankに対応するsource valueを、累積countがrank以上になる
    // 最初のvalueとして返す（15・16章）。
    int valueAtRank(int rank) {
      var cumulative = 0;
      for (final value in sortedValues) {
        cumulative += _counts[value]!;
        if (cumulative >= rank) return value;
      }
      // sortedValuesの累積countの合計は常にsampleCountと一致するため
      // （internal invariant）、rank <= sampleCountである限り到達しない。
      throw StateError(
        'unreachable: rank($rank)がsampleCount($_sampleCount)を超えました',
      );
    }

    final double median;
    if (_sampleCount.isOdd) {
      median = valueAtRank((_sampleCount + 1) ~/ 2).toDouble();
    } else {
      final lower = valueAtRank(_sampleCount ~/ 2);
      final upper = valueAtRank(_sampleCount ~/ 2 + 1);
      median = (lower + upper) / 2;
    }

    // p90 = ceil(9n/10), p95 = ceil(19n/20)（0.90 = 9/10, 0.95 = 19/20の
    // 既約分数を使い、浮動小数点乗算を経由しない）。
    final p90 = valueAtRank(_ceilDiv(9 * _sampleCount, 10)).toDouble();
    final p95 = valueAtRank(_ceilDiv(19 * _sampleCount, 20)).toDouble();

    return CombatV1NumericDistributionSummary(
      sampleCount: _sampleCount,
      mean: _sum / _sampleCount,
      median: median,
      p90: p90,
      p95: p95,
      min: sortedValues.first,
      max: sortedValues.last,
    );
  }
}

/// completed matchについて`actionCount`/`finalTurnNumber`を積み上げる
/// internal accumulator（27章「Length Accumulator」）。Global用に1つ、
/// matchup別bucketとして各1つ生成される。
class _CombatV1MatchLengthStatisticsAccumulator {
  final _CombatV1HistogramAccumulator actionCount =
      _CombatV1HistogramAccumulator();
  final _CombatV1HistogramAccumulator finalTurnNumber =
      _CombatV1HistogramAccumulator();

  void add({required int actionCount, required int finalTurnNumber}) {
    this.actionCount.add(actionCount);
    this.finalTurnNumber.add(finalTurnNumber);
  }

  CombatV1MatchLengthStatistics build() => CombatV1MatchLengthStatistics(
    actionCount: actionCount.build(),
    finalTurnNumber: finalTurnNumber.build(),
  );
}

/// [CombatV1MatchSimulationResult]をstreamingで受け取り、Global /
/// Ordered Matchup単位のmatch length descriptive statisticsを積み上げる
/// public mutable accumulator（Phase 12B-2A）。
///
/// Batch Runnerは、1試合実行するたびに[add]を呼び、`result`への参照は
/// そのループiteration内でしか保持しない——Phase 12B-1
/// [CombatV1BatchAggregationAccumulator]と同じstreaming契約。[build]は
/// 最終的な[CombatV1BatchDescriptiveStatistics]を構築する。
class CombatV1BatchDescriptiveStatisticsAccumulator {
  final _CombatV1MatchLengthStatisticsAccumulator _global =
      _CombatV1MatchLengthStatisticsAccumulator();

  final Map<CombatV1Matchup, _CombatV1MatchLengthStatisticsAccumulator>
  _matchupAccumulators = {};
  final List<CombatV1Matchup> _matchupOrder = [];

  /// [result]を1件aggregateする。
  ///
  /// matchup bucketは、`termination`に関わらず初出時に必ず作成する——
  /// Phase 12B-1 `CombatV1BatchAggregationAccumulator.add`が`total++`を
  /// terminationの種類を問わず行うのと同じタイミングでbucketを生成する
  /// ことで、両accumulatorの`matchupOrder`が同じ`CombatV1MatchSimulationResult`
  /// streamから独立に同じcanonical orderになることを保証する（20章
  /// 「Matchup Statistics Order」）。
  ///
  /// `actionCount`/`finalTurnNumber`への実際の値追加は、`termination ==
  /// matchOver`（completed match）の場合のみ行う（6章「Completed-Only
  /// Denominator」）。
  void add(CombatV1MatchSimulationResult result) {
    final matchup = CombatV1Matchup(
      wrestlerAId: result.wrestlerAId,
      wrestlerBId: result.wrestlerBId,
    );
    final bucket = _matchupAccumulators.putIfAbsent(matchup, () {
      _matchupOrder.add(matchup);
      return _CombatV1MatchLengthStatisticsAccumulator();
    });

    if (result.termination != CombatV1CpuMatchTermination.matchOver) {
      return;
    }

    _global.add(
      actionCount: result.actionCount,
      finalTurnNumber: result.finalTurnNumber,
    );
    bucket.add(
      actionCount: result.actionCount,
      finalTurnNumber: result.finalTurnNumber,
    );
  }

  /// これまで[add]した全結果から[CombatV1BatchDescriptiveStatistics]を
  /// 構築する。
  CombatV1BatchDescriptiveStatistics build() {
    final matchups = <CombatV1MatchupDescriptiveStatistics>[
      for (final matchup in _matchupOrder)
        CombatV1MatchupDescriptiveStatistics(
          matchup: matchup,
          length: _matchupAccumulators[matchup]!.build(),
        ),
    ];

    return CombatV1BatchDescriptiveStatistics(
      global: CombatV1GlobalDescriptiveStatistics(length: _global.build()),
      matchups: matchups,
    );
  }
}

/// [results]から[CombatV1BatchDescriptiveStatistics]を構築するpure facade
/// （Phase 12B-1の`combatV1AggregateBatchResults`と同型）。
/// [CombatV1BatchDescriptiveStatisticsAccumulator]を内部で使い、`add`を
/// ループするのみ——engineを一切実行していないsynthetic
/// `CombatV1MatchSimulationResult`の`Iterable`を渡すだけで結果を得られる
/// （unit testable pure boundary）。
CombatV1BatchDescriptiveStatistics combatV1AggregateBatchLengthStatistics(
  Iterable<CombatV1MatchSimulationResult> results,
) {
  final accumulator = CombatV1BatchDescriptiveStatisticsAccumulator();
  for (final result in results) {
    accumulator.add(result);
  }
  return accumulator.build();
}
