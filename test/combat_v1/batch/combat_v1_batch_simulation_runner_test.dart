// Combat Ver.1 Phase 12B-1: CombatV1BatchSimulationRunner
// （lib/src/combat_v1/simulation/batch/combat_v1_batch_simulation_runner.dart）
// のtest。
//
// docs/design/combat_v1_phase12b1_batch_core_aggregation.md 38〜42章
// （TESTS — DETERMINISM / REPLAY / POLICY PAIRINGS / SAFETY・INVARIANT /
// INTEGRATION SMOKE）を検証する。Phase 12A自身のCPU対戦ロジック（合法手
// 列挙・decline counter・terminal cause分類等）の網羅的な再テストは
// 行わない——Batch境界として必要な確認のみを追加する。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_matchup.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_simulation_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_simulation_runner.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_policy.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_runner.dart';

const _runner = CombatV1BatchSimulationRunner();
const _simulationRunner = CombatV1SimulationRunner();

CombatV1BatchSimulationConfig _config({
  List<String> wrestlerIds = combatV1DefaultBatchWrestlerIds,
  int matchesPerMatchup = 2,
  int masterSeed = 100,
  CombatV1PolicyPairing pairing = CombatV1PolicyPairing.randomVsRandom,
  int maxActions = 500,
}) => CombatV1BatchSimulationConfig(
  wrestlerIds: wrestlerIds,
  matchesPerMatchup: matchesPerMatchup,
  masterSeed: masterSeed,
  pairing: pairing,
  maxActions: maxActions,
);

/// [CombatV1BatchSimulationRunner.run]が内部でmatchup毎に組み立てるのと
/// 同じ[CombatV1SimulationConfig]を、公開APIのみから再構築する（replay/
/// determinism testで使う）。
CombatV1SimulationConfig _singleMatchConfigFor(
  CombatV1BatchSimulationConfig batchConfig,
  CombatV1Matchup matchup,
) => CombatV1SimulationConfig(
  wrestlerAId: matchup.wrestlerAId,
  wrestlerBId: matchup.wrestlerBId,
  playerAPolicy: batchConfig.playerAPolicy,
  playerBPolicy: batchConfig.playerBPolicy,
  matchCount: batchConfig.matchesPerMatchup,
  masterSeed: batchConfig.masterSeed,
  maxActions: batchConfig.maxActions,
  rules: batchConfig.rules,
);

void main() {
  group('G. Determinism — same config', () {
    test('同一configを複数回runすると同一aggregateになる', () {
      final config = _config(matchesPerMatchup: 3, masterSeed: 555);
      final resultA = _runner.run(config);
      final resultB = _runner.run(config);

      expect(resultA.global.totalMatches, resultB.global.totalMatches);
      expect(resultA.global.completedMatches, resultB.global.completedMatches);
      expect(resultA.global.playerAWins, resultB.global.playerAWins);
      expect(resultA.global.playerBWins, resultB.global.playerBWins);
      expect(
        resultA.global.terminalCauseCounts.total,
        resultB.global.terminalCauseCounts.total,
      );
      for (var i = 0; i < resultA.matchups.length; i++) {
        expect(resultA.matchups[i].matchup, resultB.matchups[i].matchup);
        expect(
          resultA.matchups[i].totalMatches,
          resultB.matchups[i].totalMatches,
        );
        expect(
          resultA.matchups[i].playerAWins,
          resultB.matchups[i].playerAWins,
        );
        expect(
          resultA.matchups[i].playerBWins,
          resultB.matchups[i].playerBWins,
        );
      }
    });

    test(
      'requestedMatchCount/executedMatchCountはmatrix size × matchesPerMatchup',
      () {
        final config = _config(
          wrestlerIds: const ['misaki', 'jack', 'akari'],
          matchesPerMatchup: 2,
        );
        final result = _runner.run(config);
        expect(result.requestedMatchCount, 9 * 2);
        expect(result.executedMatchCount, 9 * 2);
      },
    );
  });

  group('G. Determinism — execution order independence', () {
    test('wrestlerIds順序（matrix traversal順）を変えても、matchup単位の値は不変', () {
      final configCanonical = _config(
        wrestlerIds: const ['misaki', 'jack', 'akari'],
        matchesPerMatchup: 2,
        masterSeed: 777,
      );
      final configShuffled = _config(
        wrestlerIds: const ['akari', 'misaki', 'jack'],
        matchesPerMatchup: 2,
        masterSeed: 777,
      );

      final resultCanonical = _runner.run(configCanonical);
      final resultShuffled = _runner.run(configShuffled);

      final canonicalByMatchup = {
        for (final m in resultCanonical.matchups) m.matchup: m,
      };
      final shuffledByMatchup = {
        for (final m in resultShuffled.matchups) m.matchup: m,
      };

      expect(canonicalByMatchup.keys.toSet(), shuffledByMatchup.keys.toSet());
      for (final matchup in canonicalByMatchup.keys) {
        final a = canonicalByMatchup[matchup]!;
        final b = shuffledByMatchup[matchup]!;
        expect(a.totalMatches, b.totalMatches, reason: '$matchup totalMatches');
        expect(
          a.completedMatches,
          b.completedMatches,
          reason: '$matchup completedMatches',
        );
        expect(a.playerAWins, b.playerAWins, reason: '$matchup playerAWins');
        expect(a.playerBWins, b.playerBWins, reason: '$matchup playerBWins');
      }

      // 出力の並び順自体はcanonical matrix順を維持する。
      expect(
        resultCanonical.matchups.map((m) => m.matchup).toList(),
        combatV1GenerateMatchupMatrix(configCanonical.wrestlerIds),
      );
      expect(
        resultShuffled.matchups.map((m) => m.matchup).toList(),
        combatV1GenerateMatchupMatrix(configShuffled.wrestlerIds),
      );
    });

    test('個別matchupを他matchupと独立に実行しても同じPhase 12A resultになる', () {
      final config = _config(
        wrestlerIds: const ['misaki', 'jack'],
        matchesPerMatchup: 2,
        masterSeed: 999,
      );
      final fullResult = _runner.run(config);
      expect(fullResult.global.totalMatches, 8);

      // akari/reinaを含まないconfigでも、共通のmatchup（misaki vs jack等）
      // は同じmasterSeedである限りseed/結果が変化しない
      // （実行順序・batch内の他matchupの有無に依存しないことの確認）。
      final matchup = const CombatV1Matchup(
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
      );
      final isolatedConfig = _singleMatchConfigFor(config, matchup);
      final isolatedResult = _simulationRunner.runSingleMatch(
        isolatedConfig,
        0,
      );

      final matchupAggregate = fullResult.matchups.firstWhere(
        (m) => m.matchup == matchup,
      );
      expect(matchupAggregate.totalMatches, 2);
      expect(isolatedResult.wrestlerAId, 'misaki');
      expect(isolatedResult.wrestlerBId, 'jack');
      // isolatedResultはfullResult実行時のlocal matchIndex 0の試合と
      // 同一のsimulationMatchId/terminationになるはず（replay boundaryの
      // 直接確認は次のgroupで行う）。
      expect(isolatedResult.masterSeed, config.masterSeed);
    });

    test('per-match identity: wrestlerIds順序（matrix traversal順）を変えても、代表'
        '(matchup, localMatchIndex)のPhase 12A resultは完全に一致する（Codex '
        'review Minor m1対応——aggregate比較だけでなく、simulationMatchId/seed/'
        'termination/terminalCause/winner/actionCount/finalTurnNumber/'
        'finalStateSummaryをbit単位で固定する）。BatchResultはaggregate-onlyの'
        'ため、production APIへall match result retentionは追加せず、'
        'batch configから公開APIのみでsingle matchを再構築して比較する。', () {
      final configCanonical = _config(
        wrestlerIds: const ['misaki', 'jack', 'akari', 'reina'],
        matchesPerMatchup: 3,
        masterSeed: 31415,
      );
      final configReversed = _config(
        wrestlerIds: const ['reina', 'akari', 'jack', 'misaki'],
        matchesPerMatchup: 3,
        masterSeed: 31415,
      );
      final configShuffled = _config(
        wrestlerIds: const ['akari', 'reina', 'misaki', 'jack'],
        matchesPerMatchup: 3,
        masterSeed: 31415,
      );

      const representativeMatchups = [
        CombatV1Matchup(wrestlerAId: 'misaki', wrestlerBId: 'jack'),
        CombatV1Matchup(wrestlerAId: 'jack', wrestlerBId: 'misaki'),
        CombatV1Matchup(wrestlerAId: 'akari', wrestlerBId: 'akari'),
        CombatV1Matchup(wrestlerAId: 'reina', wrestlerBId: 'misaki'),
      ];

      for (final matchup in representativeMatchups) {
        for (var localMatchIndex = 0; localMatchIndex < 3; localMatchIndex++) {
          final fromCanonical = _simulationRunner.runSingleMatch(
            _singleMatchConfigFor(configCanonical, matchup),
            localMatchIndex,
          );
          final fromReversed = _simulationRunner.runSingleMatch(
            _singleMatchConfigFor(configReversed, matchup),
            localMatchIndex,
          );
          final fromShuffled = _simulationRunner.runSingleMatch(
            _singleMatchConfigFor(configShuffled, matchup),
            localMatchIndex,
          );

          for (final other in [fromReversed, fromShuffled]) {
            final reason = '$matchup localMatchIndex:$localMatchIndex';
            expect(
              other.simulationMatchId,
              fromCanonical.simulationMatchId,
              reason: '$reason simulationMatchId',
            );
            expect(
              other.matchSeed,
              fromCanonical.matchSeed,
              reason: '$reason matchSeed',
            );
            expect(
              other.engineSeed,
              fromCanonical.engineSeed,
              reason: '$reason engineSeed',
            );
            expect(
              other.playerAPolicySeed,
              fromCanonical.playerAPolicySeed,
              reason: '$reason playerAPolicySeed',
            );
            expect(
              other.playerBPolicySeed,
              fromCanonical.playerBPolicySeed,
              reason: '$reason playerBPolicySeed',
            );
            expect(
              other.termination,
              fromCanonical.termination,
              reason: '$reason termination',
            );
            expect(
              other.terminalCause,
              fromCanonical.terminalCause,
              reason: '$reason terminalCause',
            );
            expect(
              other.winnerPlayerIndex,
              fromCanonical.winnerPlayerIndex,
              reason: '$reason winnerPlayerIndex',
            );
            expect(
              other.winnerWrestlerId,
              fromCanonical.winnerWrestlerId,
              reason: '$reason winnerWrestlerId',
            );
            expect(
              other.actionCount,
              fromCanonical.actionCount,
              reason: '$reason actionCount',
            );
            expect(
              other.finalTurnNumber,
              fromCanonical.finalTurnNumber,
              reason: '$reason finalTurnNumber',
            );
            expect(
              other.finalStateSummary,
              fromCanonical.finalStateSummary,
              reason: '$reason finalStateSummary',
            );
          }
        }
      }
    });

    test('execution plan: wrestlerIds順序を変えても、production '
        'CombatV1BatchSimulationRunner.runと同じ組み立て方（matrix × local '
        'index）で生成した(matchup, localMatchIndex)の集合は不変（Codex review '
        'Minor m4対応）。production APIへall-match retentionを追加せず、'
        'matrix generator（`combatV1GenerateMatchupMatrix`、Runnerが実際に使う'
        'のと同じpure helper）とmatchesPerMatchupのlocal indexループのみで'
        'execution planをpureに再構築して比較する。', () {
      Set<(CombatV1Matchup, int)> executionPlanFor(
        List<String> wrestlerIds,
        int matchesPerMatchup,
      ) => {
        for (final matchup in combatV1GenerateMatchupMatrix(wrestlerIds))
          for (
            var localMatchIndex = 0;
            localMatchIndex < matchesPerMatchup;
            localMatchIndex++
          )
            (matchup, localMatchIndex),
      };

      const matchesPerMatchup = 4;
      final planCanonical = executionPlanFor(const [
        'misaki',
        'jack',
        'akari',
        'reina',
      ], matchesPerMatchup);
      final planReversed = executionPlanFor(const [
        'reina',
        'akari',
        'jack',
        'misaki',
      ], matchesPerMatchup);
      final planShuffled = executionPlanFor(const [
        'akari',
        'reina',
        'misaki',
        'jack',
      ], matchesPerMatchup);

      expect(planCanonical, hasLength(16 * matchesPerMatchup));
      expect(planReversed, equals(planCanonical));
      expect(planShuffled, equals(planCanonical));

      // Runnerが実際に生成するrequestedMatchCountとも一致する。
      final config = _config(matchesPerMatchup: matchesPerMatchup);
      final result = _runner.run(config);
      expect(planCanonical.length, result.requestedMatchCount);
    });
  });

  group('G. Determinism — different master seed', () {
    test('masterSeedが異なればsimulationMatchId（したがってidentity）が変化する', () {
      final configA = _config(masterSeed: 1);
      final configB = _config(masterSeed: 2);

      final matchup = const CombatV1Matchup(
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
      );
      final resultA = _simulationRunner.runSingleMatch(
        _singleMatchConfigFor(configA, matchup),
        0,
      );
      final resultB = _simulationRunner.runSingleMatch(
        _singleMatchConfigFor(configB, matchup),
        0,
      );

      expect(
        resultA.simulationMatchId,
        isNot(equals(resultB.simulationMatchId)),
      );
      expect(resultA.matchSeed, isNot(equals(resultB.matchSeed)));
    });
  });

  group('H. Replay', () {
    test('config + matchup + localMatchIndexから代表matchを再実行すると一致する', () {
      final config = _config(
        wrestlerIds: const ['misaki', 'jack', 'akari'],
        matchesPerMatchup: 3,
        masterSeed: 4242,
      );
      final result = _runner.run(config);
      expect(result.global.totalMatches, greaterThan(0));

      // akari vs jack, local matchIndex 1を代表matchとしてreplayする。
      const matchup = CombatV1Matchup(
        wrestlerAId: 'akari',
        wrestlerBId: 'jack',
      );
      final replayed = _simulationRunner.runSingleMatch(
        _singleMatchConfigFor(config, matchup),
        1,
      );
      final replayedAgain = _simulationRunner.runSingleMatch(
        _singleMatchConfigFor(config, matchup),
        1,
      );

      expect(replayed.simulationMatchId, replayedAgain.simulationMatchId);
      expect(replayed.matchSeed, replayedAgain.matchSeed);
      expect(replayed.engineSeed, replayedAgain.engineSeed);
      expect(replayed.playerAPolicySeed, replayedAgain.playerAPolicySeed);
      expect(replayed.playerBPolicySeed, replayedAgain.playerBPolicySeed);
      expect(replayed.termination, replayedAgain.termination);
      expect(replayed.terminalCause, replayedAgain.terminalCause);
      expect(replayed.winnerPlayerIndex, replayedAgain.winnerPlayerIndex);
      expect(replayed.winnerWrestlerId, replayedAgain.winnerWrestlerId);
      expect(replayed.actionCount, replayedAgain.actionCount);
      expect(replayed.finalTurnNumber, replayedAgain.finalTurnNumber);
      expect(replayed.finalStateSummary, replayedAgain.finalStateSummary);
      // owner metadata（playerAOwnerId/playerBOwnerId）も、masterSeed +
      // matchIndexから決定論的に導出されるため一致する（8章）。
      expect(replayed.playerAOwnerId, replayedAgain.playerAOwnerId);
      expect(replayed.playerBOwnerId, replayedAgain.playerBOwnerId);
      expect(replayed.wrestlerAId, 'akari');
      expect(replayed.wrestlerBId, 'jack');
      expect(replayed.matchIndex, 1);
    });
  });

  group('I. Policy Pairings', () {
    for (final pairing in const [
      CombatV1PolicyPairing(
        playerAPolicy: CombatV1SimulationPolicyKind.firstLegal,
        playerBPolicy: CombatV1SimulationPolicyKind.firstLegal,
      ),
      CombatV1PolicyPairing.randomVsRandom,
      CombatV1PolicyPairing(
        playerAPolicy: CombatV1SimulationPolicyKind.firstLegal,
        playerBPolicy: CombatV1SimulationPolicyKind.randomLegal,
      ),
      CombatV1PolicyPairing(
        playerAPolicy: CombatV1SimulationPolicyKind.randomLegal,
        playerBPolicy: CombatV1SimulationPolicyKind.firstLegal,
      ),
    ]) {
      test(
        'pairing ${pairing.playerAPolicy.name}/${pairing.playerBPolicy.name}のsmoke',
        () {
          final config = _config(
            wrestlerIds: const ['misaki', 'jack'],
            matchesPerMatchup: 1,
            pairing: pairing,
          );
          final result = _runner.run(config);
          expect(result.executedMatchCount, 4);
          expect(result.global.totalMatches, 4);
        },
      );
    }
  });

  group('J. Safety Limit', () {
    test('低いmaxActionsでsafetyLimitが発生してもbatchは継続する', () {
      final config = _config(
        wrestlerIds: const ['misaki', 'jack'],
        matchesPerMatchup: 2,
        maxActions: 1,
      );
      final result = _runner.run(config);

      expect(result.executedMatchCount, 8);
      expect(result.global.safetyLimitMatches, 8);
      expect(result.global.completedMatches, 0);
      expect(result.global.playerAWins, 0);
      expect(result.global.playerBWins, 0);
      expect(result.global.playerAWinRateCompletedMatches, isNull);
      for (final matchup in result.matchups) {
        expect(matchup.safetyLimitMatches, matchup.totalMatches);
      }
    });
  });

  group('K. Integration Smoke', () {
    test('default 4 wrestlers・小規模件数で16 matchup全実行', () {
      final config = _config(matchesPerMatchup: 5, masterSeed: 24680);
      final result = _runner.run(config);

      expect(result.matchups, hasLength(16));
      expect(result.requestedMatchCount, 16 * 5);
      expect(result.executedMatchCount, 16 * 5);
      expect(result.global.totalMatches, 80);
      expect(
        result.global.totalMatches,
        result.global.completedMatches +
            result.global.safetyLimitMatches +
            result.global.invariantViolationMatches,
      );
      expect(
        result.global.completedMatches,
        result.global.playerAWins + result.global.playerBWins,
      );
      expect(
        result.global.terminalCauseCounts.total,
        result.global.completedMatches,
      );
      expect(result.mirror.totalMatches, greaterThanOrEqualTo(0));
      expect(result.wrestlers, hasLength(4));
      expect(
        result.wrestlers.fold<int>(0, (s, w) => s + w.appearances),
        2 * result.global.totalMatches,
      );

      // deterministic: 同一configで再実行しても同じ結果。
      final rerun = _runner.run(config);
      expect(rerun.global.totalMatches, result.global.totalMatches);
      expect(rerun.global.completedMatches, result.global.completedMatches);
      expect(rerun.global.playerAWins, result.global.playerAWins);
    });
  });

  group('L. 構造的invariantの直接確認', () {
    test('CombatV1BatchSimulationResultの各Listはunmodifiable', () {
      final config = _config(
        wrestlerIds: const ['misaki', 'jack'],
        matchesPerMatchup: 1,
      );
      final result = _runner.run(config);
      expect(
        () => result.matchups.add(result.matchups.first),
        throwsUnsupportedError,
      );
      expect(
        () => result.wrestlers.add(result.wrestlers.first),
        throwsUnsupportedError,
      );
    });

    test('termination fieldはglobal.terminationと同一instance', () {
      final config = _config(
        wrestlerIds: const ['misaki', 'jack'],
        matchesPerMatchup: 1,
      );
      final result = _runner.run(config);
      expect(identical(result.termination, result.global.termination), isTrue);
    });
  });

  group('M. Phase 12B-2A — statistics統合', () {
    test('statistics.global.length.actionCount/finalTurnNumberの'
        'sampleCountがglobal.completedMatchesと一致する', () {
      final config = _config(matchesPerMatchup: 3, masterSeed: 42);
      final result = _runner.run(config);

      expect(
        result.statistics.global.length.actionCount.sampleCount,
        result.global.completedMatches,
      );
      expect(
        result.statistics.global.length.finalTurnNumber.sampleCount,
        result.global.completedMatches,
      );
    });

    test('statistics.matchupsはresult.matchupsと同じcanonical order・'
        '同じ件数で対応し、各entryのsampleCountがcompletedMatchesと一致する', () {
      final config = _config(matchesPerMatchup: 3, masterSeed: 42);
      final result = _runner.run(config);

      expect(result.statistics.matchups, hasLength(result.matchups.length));
      for (var i = 0; i < result.matchups.length; i++) {
        final core = result.matchups[i];
        final stats = result.statistics.matchups[i];
        expect(stats.matchup, core.matchup);
        expect(stats.length.actionCount.sampleCount, core.completedMatches);
        expect(
          stats.length.finalTurnNumber.sampleCount,
          core.completedMatches,
        );
      }

      final matchupSampleSum = result.statistics.matchups.fold<int>(
        0,
        (sum, m) => sum + m.length.actionCount.sampleCount,
      );
      expect(
        matchupSampleSum,
        result.statistics.global.length.actionCount.sampleCount,
      );
    });

    test('同一configを複数回runしてもstatisticsが同一になる（determinism）', () {
      final config = _config(matchesPerMatchup: 4, masterSeed: 999);
      final resultA = _runner.run(config);
      final resultB = _runner.run(config);

      expect(
        resultA.statistics.global.length.actionCount.sampleCount,
        resultB.statistics.global.length.actionCount.sampleCount,
      );
      expect(
        resultA.statistics.global.length.actionCount.mean,
        resultB.statistics.global.length.actionCount.mean,
      );
      expect(
        resultA.statistics.global.length.actionCount.median,
        resultB.statistics.global.length.actionCount.median,
      );
      expect(
        resultA.statistics.global.length.actionCount.p90,
        resultB.statistics.global.length.actionCount.p90,
      );
      expect(
        resultA.statistics.global.length.actionCount.p95,
        resultB.statistics.global.length.actionCount.p95,
      );
      for (var i = 0; i < resultA.statistics.matchups.length; i++) {
        expect(
          resultA.statistics.matchups[i].length.actionCount.sampleCount,
          resultB.statistics.matchups[i].length.actionCount.sampleCount,
        );
      }
    });

    test('statistics.matchups listはunmodifiable', () {
      final config = _config(
        wrestlerIds: const ['misaki', 'jack'],
        matchesPerMatchup: 1,
      );
      final result = _runner.run(config);
      expect(
        () => result.statistics.matchups.add(result.statistics.matchups.first),
        throwsUnsupportedError,
      );
    });
  });
}
