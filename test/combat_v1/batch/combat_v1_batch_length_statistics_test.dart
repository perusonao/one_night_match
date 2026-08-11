// Combat Ver.1 Phase 12B-2A: Match Length Statistics — pure numeric/
// histogram logic test。
//
// docs/design/combat_v1_phase12b2a_match_length_statistics.md 9〜18章
// （Mean/Median/P90/P95/Min-Max/Empty Sample/Histogram Strategy）を検証
// する。engineを一切起動せず、`combatV1AggregateBatchLengthStatistics`
// （internal histogram accumulatorを内部で使うpure facade）へsynthetic
// `CombatV1MatchSimulationResult`を渡すのみ——これがhistogram/distribution
// logicを直接exerciseする経路になっている。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_length_statistics.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_length_statistics_accumulator.dart';

import 'combat_v1_batch_length_statistics_test_helper.dart';

/// [actionCounts]をそれぞれ持つcompleted matchのlistから、globalの
/// `actionCount` distribution summaryを返す（`finalTurnNumber`は無関係な
/// 固定値を混ぜて、両metricが独立にhistogram化されることも併せて検証
/// する）。
CombatV1NumericDistributionSummary _actionCountSummary(
  List<int> actionCounts, {
  int finalTurnNumberOffset = 1000,
}) {
  final results = [
    for (var i = 0; i < actionCounts.length; i++)
      statsTestResult(
        id: 'm$i',
        actionCount: actionCounts[i],
        finalTurnNumber: finalTurnNumberOffset + i,
      ),
  ];
  return combatV1AggregateBatchLengthStatistics(
    results,
  ).global.length.actionCount;
}

void main() {
  group('Empty sample', () {
    test('sampleCount 0・全summary null', () {
      final summary = _actionCountSummary(const []);
      expect(summary.sampleCount, 0);
      expect(summary.mean, isNull);
      expect(summary.median, isNull);
      expect(summary.p90, isNull);
      expect(summary.p95, isNull);
      expect(summary.min, isNull);
      expect(summary.max, isNull);
    });

    test('CombatV1NumericDistributionSummary.empty / '
        'CombatV1MatchLengthStatistics.emptyと一致する', () {
      final statistics = combatV1AggregateBatchLengthStatistics(const []);
      expect(
        statistics.global.length.actionCount.sampleCount,
        CombatV1NumericDistributionSummary.empty.sampleCount,
      );
      expect(
        statistics.global.length.finalTurnNumber.sampleCount,
        CombatV1MatchLengthStatistics.empty.finalTurnNumber.sampleCount,
      );
      expect(statistics.matchups, isEmpty);
    });
  });

  group('Single sample', () {
    test('[5]: mean/median/p90/p95/min/max全て5', () {
      final summary = _actionCountSummary(const [5]);
      expect(summary.sampleCount, 1);
      expect(summary.mean, 5.0);
      expect(summary.median, 5.0);
      expect(summary.p90, 5.0);
      expect(summary.p95, 5.0);
      expect(summary.min, 5);
      expect(summary.max, 5);
    });
  });

  group('Median', () {
    test('odd sample [1,2,3]: median=2（中央1値）', () {
      final summary = _actionCountSummary(const [1, 2, 3]);
      expect(summary.median, 2.0);
    });

    test('even sample [1,2,3,4]: median=2.5（中央2値の算術平均）', () {
      final summary = _actionCountSummary(const [1, 2, 3, 4]);
      expect(summary.median, 2.5);
    });

    test('even sample、値が重複していても中央2値平均が正しい [1,1,2,2]', () {
      final summary = _actionCountSummary(const [1, 1, 2, 2]);
      // sorted order statistics: [1,1,2,2] → rank2=1, rank3=2 → (1+2)/2=1.5
      expect(summary.median, 1.5);
    });
  });

  group('P90 / P95 — nearest-rank固定', () {
    test('1..10（n=10）: p90=ceil(9)=9番目の値=9, p95=ceil(9.5)=10番目の値=10', () {
      final summary = _actionCountSummary([for (var i = 1; i <= 10; i++) i]);
      expect(summary.p90, 9.0);
      expect(summary.p95, 10.0);
    });

    test('1..20（n=20）: p90=ceil(18)=18番目=18, p95=ceil(19)=19番目=19', () {
      final summary = _actionCountSummary([for (var i = 1; i <= 20; i++) i]);
      expect(summary.p90, 18.0);
      expect(summary.p95, 19.0);
    });

    test('sampleCount=1でもp90/p95は最初のrank(=1)を指す（0にならない）', () {
      final summary = _actionCountSummary(const [42]);
      expect(summary.p90, 42.0);
      expect(summary.p95, 42.0);
    });
  });

  group('Repeated values', () {
    test('[5,5,5,5,5]: 全summaryが5に一致', () {
      final summary = _actionCountSummary(const [5, 5, 5, 5, 5]);
      expect(summary.sampleCount, 5);
      expect(summary.mean, 5.0);
      expect(summary.median, 5.0);
      expect(summary.p90, 5.0);
      expect(summary.p95, 5.0);
      expect(summary.min, 5);
      expect(summary.max, 5);
    });
  });

  group('Min / Max', () {
    test('[3,1,4,1,5,9,2,6]: min=1, max=9', () {
      final summary = _actionCountSummary(const [3, 1, 4, 1, 5, 9, 2, 6]);
      expect(summary.min, 1);
      expect(summary.max, 9);
    });

    test('boundary: actionCount=0を含む分布も安全に扱える', () {
      final summary = _actionCountSummary(const [0, 0, 3]);
      expect(summary.min, 0);
      expect(summary.max, 3);
      expect(summary.sampleCount, 3);
    });
  });

  group('Histogram — bucket counts / sum / traversal order independence', () {
    test('sum・sampleCountがadd順に関わらず一致する', () {
      const values = [7, 3, 9, 3, 1, 7, 7, 2];
      final forward = _actionCountSummary(values);
      final reversed = _actionCountSummary(values.reversed.toList());
      final shuffled = _actionCountSummary([2, 7, 1, 3, 9, 7, 3, 7]);

      for (final summary in [forward, reversed, shuffled]) {
        expect(summary.sampleCount, forward.sampleCount);
        expect(summary.mean, forward.mean);
        expect(summary.median, forward.median);
        expect(summary.p90, forward.p90);
        expect(summary.p95, forward.p95);
        expect(summary.min, forward.min);
        expect(summary.max, forward.max);
      }
    });

    test('大量のduplicate valueでもO(distinct value数)で正しく集約できる'
        '（sparse histogramのsmoke test）', () {
      // distinct valueは0..99の100種のみ——observed distinct value数に
      // 比例するsparse Mapであれば、10,000件addしてもhistogramのkey数は
      // 高々100に収まる。
      final values = [for (var i = 0; i < 10000; i++) i % 100];
      final summary = _actionCountSummary(values);
      expect(summary.sampleCount, 10000);
      expect(summary.min, 0);
      expect(summary.max, 99);
      // mean of 0..99 repeated uniformly == 49.5
      expect(summary.mean, 49.5);
    });

    test('actionCountとfinalTurnNumberは独立したhistogramを持つ'
        '（互いのvalueが混入しない）', () {
      final results = [
        statsTestResult(id: 'a', actionCount: 10, finalTurnNumber: 1),
        statsTestResult(id: 'b', actionCount: 20, finalTurnNumber: 2),
        statsTestResult(id: 'c', actionCount: 30, finalTurnNumber: 3),
      ];
      final length = combatV1AggregateBatchLengthStatistics(
        results,
      ).global.length;

      expect(length.actionCount.min, 10);
      expect(length.actionCount.max, 30);
      expect(length.actionCount.mean, 20.0);

      expect(length.finalTurnNumber.min, 1);
      expect(length.finalTurnNumber.max, 3);
      expect(length.finalTurnNumber.mean, 2.0);
    });
  });
}
