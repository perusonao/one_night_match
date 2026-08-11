// Combat Ver.1 Phase 12B-2A: CombatV1BatchDescriptiveStatisticsAccumulator
// （lib/src/combat_v1/simulation/batch/
// combat_v1_batch_length_statistics_accumulator.dart）のtest。
//
// docs/design/combat_v1_phase12b2a_match_length_statistics.md 6・17・18・
// 19章（Completed-Only Denominator / Internal Invariants / Matchup
// Statistics Order / Streaming Memory）を検証する。synthetic
// CombatV1MatchSimulationResultのみを使い、engineを一切実行しない。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_cpu_match_runner.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_length_statistics.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_length_statistics_accumulator.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_matchup.dart';

import 'combat_v1_batch_length_statistics_test_helper.dart';

void main() {
  group('Completed-only', () {
    test('matchOverの結果はsampleへ入る', () {
      final statistics = combatV1AggregateBatchLengthStatistics([
        statsTestResult(id: 'a', actionCount: 12, finalTurnNumber: 4),
      ]);
      expect(statistics.global.length.actionCount.sampleCount, 1);
      expect(statistics.global.length.actionCount.min, 12);
      expect(statistics.global.length.finalTurnNumber.min, 4);
    });

    test('safetyLimitの結果はsampleへ入らない（matchup bucket自体は作られる）', () {
      final statistics = combatV1AggregateBatchLengthStatistics([
        statsTestResult(
          id: 'a',
          termination: CombatV1CpuMatchTermination.safetyLimit,
          actionCount: 500,
          finalTurnNumber: 80,
        ),
      ]);
      expect(statistics.global.length.actionCount.sampleCount, 0);
      expect(statistics.matchups, hasLength(1));
      expect(statistics.matchups.single.length.actionCount.sampleCount, 0);
    });

    test('invariantViolation Shape A（winner両方null）の結果はsampleへ入らない', () {
      final statistics = combatV1AggregateBatchLengthStatistics([
        statsTestRawResult(
          termination: CombatV1CpuMatchTermination.invariantViolation,
          invariantViolationMessage: 'shape A: no winner',
          actionCount: 33,
          finalTurnNumber: 9,
        ),
      ]);
      expect(statistics.global.length.actionCount.sampleCount, 0);
      expect(statistics.global.length.finalTurnNumber.sampleCount, 0);
    });

    test(
      'invariantViolation Shape B（winner preserved from final state）の'
      '結果もwinner metadataの有無に関わらずsampleへ入らない'
      '（terminationのみで判定する）',
      () {
        final statistics = combatV1AggregateBatchLengthStatistics([
          statsTestRawResult(
            termination: CombatV1CpuMatchTermination.invariantViolation,
            invariantViolationMessage: 'shape B: winner preserved',
            winnerPlayerIndex: 0,
            winnerWrestlerId: 'misaki',
            actionCount: 77,
            finalTurnNumber: 11,
          ),
        ]);
        expect(statistics.global.length.actionCount.sampleCount, 0);
        expect(statistics.global.length.finalTurnNumber.sampleCount, 0);
      },
    );
  });

  group('Global / Matchup correspondence', () {
    test('global sampleCount == 全completed matchの件数', () {
      final results = [
        statsTestResult(id: 'a', actionCount: 10),
        statsTestResult(
          id: 'b',
          termination: CombatV1CpuMatchTermination.safetyLimit,
          actionCount: 500,
        ),
        statsTestResult(id: 'c', actionCount: 20),
        statsTestRawResult(
          termination: CombatV1CpuMatchTermination.invariantViolation,
          invariantViolationMessage: 'x',
          actionCount: 5,
        ),
      ];
      final statistics = combatV1AggregateBatchLengthStatistics(results);
      expect(statistics.global.length.actionCount.sampleCount, 2);
    });

    test('各matchupのsampleCount == そのmatchupのcompleted件数、'
        '全matchup合計 == global sampleCount', () {
      final results = [
        statsTestResult(
          id: 'a1',
          wrestlerAId: 'misaki',
          wrestlerBId: 'jack',
          actionCount: 10,
        ),
        statsTestResult(
          id: 'a2',
          wrestlerAId: 'misaki',
          wrestlerBId: 'jack',
          actionCount: 12,
        ),
        statsTestResult(
          id: 'b1',
          wrestlerAId: 'jack',
          wrestlerBId: 'misaki',
          actionCount: 30,
        ),
        statsTestResult(
          id: 'c1',
          wrestlerAId: 'misaki',
          wrestlerBId: 'jack',
          termination: CombatV1CpuMatchTermination.safetyLimit,
          actionCount: 500,
        ),
      ];
      final statistics = combatV1AggregateBatchLengthStatistics(results);

      final misakiVsJack = statistics.matchups.singleWhere(
        (m) =>
            m.matchup.wrestlerAId == 'misaki' &&
            m.matchup.wrestlerBId == 'jack',
      );
      final jackVsMisaki = statistics.matchups.singleWhere(
        (m) =>
            m.matchup.wrestlerAId == 'jack' &&
            m.matchup.wrestlerBId == 'misaki',
      );

      expect(misakiVsJack.length.actionCount.sampleCount, 2);
      expect(jackVsMisaki.length.actionCount.sampleCount, 1);

      final matchupSampleSum = statistics.matchups.fold<int>(
        0,
        (sum, m) => sum + m.length.actionCount.sampleCount,
      );
      expect(matchupSampleSum, statistics.global.length.actionCount.sampleCount);
    });
  });

  group('Matchup independence', () {
    test(
      'A vs B（短い試合）とB vs A（長い試合）のlength分布が混ざらない',
      () {
        final results = [
          for (var i = 0; i < 5; i++)
            statsTestResult(
              id: 'short-$i',
              wrestlerAId: 'misaki',
              wrestlerBId: 'jack',
              actionCount: 10,
              finalTurnNumber: 3,
            ),
          for (var i = 0; i < 5; i++)
            statsTestResult(
              id: 'long-$i',
              wrestlerAId: 'jack',
              wrestlerBId: 'misaki',
              actionCount: 400,
              finalTurnNumber: 90,
            ),
        ];
        final statistics = combatV1AggregateBatchLengthStatistics(results);

        final short = statistics.matchups.singleWhere(
          (m) =>
              m.matchup.wrestlerAId == 'misaki' &&
              m.matchup.wrestlerBId == 'jack',
        );
        final long = statistics.matchups.singleWhere(
          (m) =>
              m.matchup.wrestlerAId == 'jack' &&
              m.matchup.wrestlerBId == 'misaki',
        );

        expect(short.length.actionCount.mean, 10.0);
        expect(short.length.actionCount.max, 10);
        expect(long.length.actionCount.mean, 400.0);
        expect(long.length.actionCount.min, 400);

        // globalは両方混ざる。
        expect(statistics.global.length.actionCount.min, 10);
        expect(statistics.global.length.actionCount.max, 400);
      },
    );
  });

  group('Determinism', () {
    test('同じresult setを順不同でaddしても同一のsummaryになる', () {
      final results = [
        statsTestResult(id: 'a', actionCount: 12, finalTurnNumber: 3),
        statsTestResult(id: 'b', actionCount: 40, finalTurnNumber: 9),
        statsTestResult(id: 'c', actionCount: 12, finalTurnNumber: 3),
        statsTestResult(id: 'd', actionCount: 7, finalTurnNumber: 2),
      ];

      final forward = combatV1AggregateBatchLengthStatistics(results);
      final reversed = combatV1AggregateBatchLengthStatistics(
        results.reversed,
      );

      CombatV1NumericDistributionSummary actionCountOf(
        CombatV1BatchDescriptiveStatistics s,
      ) => s.global.length.actionCount;

      final a = actionCountOf(forward);
      final b = actionCountOf(reversed);
      expect(a.sampleCount, b.sampleCount);
      expect(a.mean, b.mean);
      expect(a.median, b.median);
      expect(a.p90, b.p90);
      expect(a.p95, b.p95);
      expect(a.min, b.min);
      expect(a.max, b.max);
    });
  });

  group('Immutability', () {
    test('buildしたsnapshotは、その後のaddで変化しない', () {
      final accumulator = CombatV1BatchDescriptiveStatisticsAccumulator();
      accumulator.add(statsTestResult(id: 'a', actionCount: 10));
      final snapshotA = accumulator.build();

      accumulator.add(statsTestResult(id: 'b', actionCount: 90));
      final snapshotB = accumulator.build();

      // Aは1件のまま。
      expect(snapshotA.global.length.actionCount.sampleCount, 1);
      expect(snapshotA.global.length.actionCount.mean, 10.0);

      // Bは2件に更新されている。
      expect(snapshotB.global.length.actionCount.sampleCount, 2);
      expect(snapshotB.global.length.actionCount.mean, 50.0);
    });

    test('matchups listはunmodifiable', () {
      final statistics = combatV1AggregateBatchLengthStatistics([
        statsTestResult(id: 'a'),
      ]);
      expect(
        () => statistics.matchups.add(
          const CombatV1MatchupDescriptiveStatistics(
            matchup: CombatV1Matchup(wrestlerAId: 'x', wrestlerBId: 'y'),
            length: CombatV1MatchLengthStatistics.empty,
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
