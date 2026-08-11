// Balance Dashboard 1A test fixtures — synthetic CombatV1BatchSimulationResult
// builder（engineを一切起動しない）。
//
// combat_v1_balance_dashboard_view_model_test.dart /
// combat_v1_balance_dashboard_screen_test.dart 双方から使う共通helper。

import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_aggregate.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_length_statistics.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_matchup.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_simulation_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_simulation_result.dart';

const combatV1DashboardTestWrestlerIds = combatV1DefaultBatchWrestlerIds; // [misaki, jack, akari, reina]

int combatV1DashboardTestIndex(String id) =>
    combatV1DashboardTestWrestlerIds.indexOf(id);

/// (a, b)から決定論的だが非対称なplayerAWins値を作るformula（A vs B ≠
/// B vs Aをテストするため、row/columnどちらにも依存させる）。
int combatV1DashboardTestPlayerAWinsFor(String a, String b) =>
    (combatV1DashboardTestIndex(a) * 2 + combatV1DashboardTestIndex(b)) % 9;

CombatV1TerminationDistribution combatV1DashboardTestTermination({
  int total = 10,
  int completed = 8,
  int safetyLimit = 0,
  int invariantViolation = 0,
}) => CombatV1TerminationDistribution(
  totalMatches: total,
  completedMatches: completed,
  safetyLimitMatches: safetyLimit,
  invariantViolationMatches: invariantViolation,
);

const combatV1DashboardTestCauses = CombatV1TerminalCauseCounts(
  normalPin: 8,
  directPin: 0,
  submission: 0,
  submissionFinisher: 0,
  other: 0,
);

List<CombatV1MatchupAggregate> combatV1DashboardTestMatchups({
  List<String>? wrestlerIds,
}) {
  final ids = wrestlerIds ?? combatV1DashboardTestWrestlerIds;
  return [
    for (final a in ids)
      for (final b in ids)
        CombatV1MatchupAggregate(
          matchup: CombatV1Matchup(wrestlerAId: a, wrestlerBId: b),
          termination: combatV1DashboardTestTermination(
            safetyLimit: a == 'akari' && b == 'akari' ? 1 : 0,
            invariantViolation: a == 'akari' && b == 'akari' ? 1 : 0,
          ),
          playerAWins: combatV1DashboardTestPlayerAWinsFor(a, b),
          playerBWins: 8 - combatV1DashboardTestPlayerAWinsFor(a, b),
          terminalCauseCounts: combatV1DashboardTestCauses,
        ),
  ];
}

List<CombatV1MatchupDescriptiveStatistics> combatV1DashboardTestMatchupStatistics({
  List<String>? wrestlerIds,
}) {
  final ids = wrestlerIds ?? combatV1DashboardTestWrestlerIds;
  return [
    for (final a in ids)
      for (final b in ids)
        CombatV1MatchupDescriptiveStatistics(
          matchup: CombatV1Matchup(wrestlerAId: a, wrestlerBId: b),
          length: CombatV1MatchLengthStatistics(
            actionCount: CombatV1NumericDistributionSummary(
              sampleCount: 8,
              mean:
                  (20 +
                          combatV1DashboardTestIndex(a) +
                          combatV1DashboardTestIndex(b))
                      .toDouble(),
              median: 19,
              p90: 30,
              p95: 32,
              min: 5,
              max: 40,
            ),
            finalTurnNumber: CombatV1NumericDistributionSummary(
              sampleCount: 8,
              mean:
                  (10 +
                          combatV1DashboardTestIndex(a) +
                          combatV1DashboardTestIndex(b))
                      .toDouble(),
              median: 9,
              p90: 15,
              p95: 16,
              min: 2,
              max: 20,
            ),
          ),
        ),
  ];
}

/// misaki/jack/akariは通常のcompletedデータを持ち、reinaは意図的に
/// completedAppearances == 0（null win rate、formatting testの
/// fixtureとして使う）。
List<CombatV1WrestlerAggregate> combatV1DashboardTestWrestlers() => const [
  CombatV1WrestlerAggregate(
    wrestlerId: 'misaki',
    playerAAppearances: 8,
    playerACompletedAppearances: 8,
    playerAWins: 5,
    playerBAppearances: 8,
    playerBCompletedAppearances: 8,
    playerBWins: 3,
  ),
  CombatV1WrestlerAggregate(
    wrestlerId: 'jack',
    playerAAppearances: 8,
    playerACompletedAppearances: 8,
    playerAWins: 3,
    playerBAppearances: 8,
    playerBCompletedAppearances: 8,
    playerBWins: 2,
  ),
  CombatV1WrestlerAggregate(
    wrestlerId: 'akari',
    playerAAppearances: 8,
    playerACompletedAppearances: 6,
    playerAWins: 4,
    playerBAppearances: 8,
    playerBCompletedAppearances: 8,
    playerBWins: 4,
  ),
  CombatV1WrestlerAggregate(
    wrestlerId: 'reina',
    playerAAppearances: 8,
    playerACompletedAppearances: 0,
    playerAWins: 0,
    playerBAppearances: 8,
    playerBCompletedAppearances: 0,
    playerBWins: 0,
  ),
];

/// synthetic [CombatV1BatchSimulationResult]を組み立てるtest helper
/// （engineを一切起動しない、Phase 12B-1/12B-2A pure value typeの
/// constructorのみを使う）。
CombatV1BatchSimulationResult combatV1DashboardTestResult({
  List<String>? wrestlerIds,
  List<CombatV1MatchupAggregate>? matchups,
  List<CombatV1MatchupDescriptiveStatistics>? matchupStatistics,
  List<CombatV1WrestlerAggregate>? wrestlers,
  int globalSafetyLimit = 3,
  int globalInvariantViolation = 2,
}) {
  final ids = wrestlerIds ?? combatV1DashboardTestWrestlerIds;
  final config = CombatV1BatchSimulationConfig(
    wrestlerIds: ids,
    matchesPerMatchup: 10,
    masterSeed: 12345,
    pairing: CombatV1PolicyPairing.randomVsRandom,
    maxActions: 500,
  );
  return CombatV1BatchSimulationResult(
    config: config,
    requestedMatchCount: ids.length * ids.length * 10,
    executedMatchCount: ids.length * ids.length * 10,
    global: CombatV1GlobalAggregate(
      termination: combatV1DashboardTestTermination(
        total: ids.length * ids.length * 10,
        completed: ids.length * ids.length * 8,
        safetyLimit: globalSafetyLimit,
        invariantViolation: globalInvariantViolation,
      ),
      playerAWins: 60,
      playerBWins: 68,
      terminalCauseCounts: const CombatV1TerminalCauseCounts(
        normalPin: 100,
        directPin: 10,
        submission: 10,
        submissionFinisher: 5,
        other: 3,
      ),
    ),
    matchups: matchups ?? combatV1DashboardTestMatchups(wrestlerIds: ids),
    wrestlers: wrestlers ?? combatV1DashboardTestWrestlers(),
    seat: const CombatV1SeatAggregate(
      playerACompletedMatches: 128,
      playerBCompletedMatches: 128,
      playerAWins: 60,
      playerBWins: 68,
    ),
    mirror: const CombatV1MirrorAggregate(
      termination: CombatV1TerminationDistribution(
        totalMatches: 40,
        completedMatches: 32,
        safetyLimitMatches: 1,
        invariantViolationMatches: 1,
      ),
      playerAWins: 15,
      playerBWins: 17,
    ),
    statistics: CombatV1BatchDescriptiveStatistics(
      global: const CombatV1GlobalDescriptiveStatistics(
        length: CombatV1MatchLengthStatistics(
          actionCount: CombatV1NumericDistributionSummary(
            sampleCount: 128,
            mean: 42.0,
            median: 40.0,
            p90: 60.0,
            p95: 65.0,
            min: 10,
            max: 90,
          ),
          finalTurnNumber: CombatV1NumericDistributionSummary(
            sampleCount: 128,
            mean: 21.0,
            median: 20.0,
            p90: 30.0,
            p95: 32.0,
            min: 5,
            max: 45,
          ),
        ),
      ),
      matchups: matchupStatistics ?? combatV1DashboardTestMatchupStatistics(wrestlerIds: ids),
    ),
  );
}
