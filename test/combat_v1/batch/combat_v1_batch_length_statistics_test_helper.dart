// Combat Ver.1 Phase 12B-2A: match length statistics testで共通に使う
// synthetic CombatV1MatchSimulationResult builder。
//
// combat_v1_batch_aggregator_test.dartの`_result`/`_summary`と同じ
// pattern——engineを一切実行しない。actionCount/finalTurnNumberを直接
// 指定できるようにしている点のみ異なる。

import 'package:one_night_match/src/combat_v1/combat_v1_cpu_match_runner.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_match_simulation_result.dart';

const CombatV1RulesConfig statsTestRules = CombatV1RulesConfig();

CombatV1MatchFinalStateSummary statsTestFinalStateSummary() =>
    const CombatV1MatchFinalStateSummary(
      playerAHp: 100,
      playerBHp: 50,
      playerAKoc: 5,
      playerBKoc: 5,
      playerAPosture: CombatV1WrestlerPosture.stand,
      playerBPosture: CombatV1WrestlerPosture.down,
      playerAPinCardsHeld: 2,
      playerBPinCardsHeld: 2,
      playerAHandSize: 5,
      playerADrawPileSize: 10,
      playerADiscardPileSize: 3,
      playerBHandSize: 5,
      playerBDrawPileSize: 10,
      playerBDiscardPileSize: 3,
      playerAReshuffleCount: 0,
      playerBReshuffleCount: 0,
      sharedHeat: 100,
      finalPhase: CombatV1MatchPhase.action,
      activePlayerIndex: 0,
      hasPendingAttack: false,
    );

/// synthetic [CombatV1MatchSimulationResult]を組み立てるtest helper。
/// [actionCount]/[finalTurnNumber]を直接指定できる——length statistics
/// testが分布の中身をコントロールするために使う。
CombatV1MatchSimulationResult statsTestResult({
  required String id,
  String wrestlerAId = 'misaki',
  String wrestlerBId = 'jack',
  int matchIndex = 0,
  int actionCount = 10,
  int finalTurnNumber = 5,
  CombatV1CpuMatchTermination termination =
      CombatV1CpuMatchTermination.matchOver,
  CombatV1CpuMatchTerminalCause? terminalCause =
      CombatV1CpuMatchTerminalCause.normalPin,
  int? winnerPlayerIndex = 0,
  String? invariantViolationMessage,
}) {
  final winnerWrestlerId = switch (winnerPlayerIndex) {
    0 => wrestlerAId,
    1 => wrestlerBId,
    _ => null,
  };
  return CombatV1MatchSimulationResult(
    matchIndex: matchIndex,
    simulationMatchId: id,
    wrestlerAId: wrestlerAId,
    wrestlerBId: wrestlerBId,
    playerAOwnerId: 'sim-1-$matchIndex-a',
    playerBOwnerId: 'sim-1-$matchIndex-b',
    playerAPolicyId: 'randomLegal',
    playerBPolicyId: 'randomLegal',
    masterSeed: 1,
    matchSeed: 2,
    engineSeed: 3,
    playerAPolicySeed: 4,
    playerBPolicySeed: 5,
    seedDerivationVersion: 1,
    maxActions: 500,
    rules: statsTestRules,
    termination: termination,
    actionCount: actionCount,
    finalTurnNumber: finalTurnNumber,
    safetyLimitReached: termination == CombatV1CpuMatchTermination.safetyLimit,
    finalStateSummary: statsTestFinalStateSummary(),
    terminalCause: termination == CombatV1CpuMatchTermination.matchOver
        ? terminalCause
        : null,
    winnerPlayerIndex: termination == CombatV1CpuMatchTermination.matchOver
        ? winnerPlayerIndex
        : null,
    winnerWrestlerId: termination == CombatV1CpuMatchTermination.matchOver
        ? winnerWrestlerId
        : null,
    invariantViolationMessage: invariantViolationMessage,
  );
}

/// [statsTestResult]と異なり、`termination`と各fieldの整合性を一切自動
/// 調整しない低レベルtest helper——`invariantViolation`のwinner-preserved
/// Shape B（Phase 12B-1 contract、`combat_v1_batch_aggregator.dart`参照）
/// を意図的に組み立てるためのもの。
CombatV1MatchSimulationResult statsTestRawResult({
  String id = 'raw',
  String wrestlerAId = 'misaki',
  String wrestlerBId = 'jack',
  int matchIndex = 0,
  int actionCount = 10,
  int finalTurnNumber = 5,
  required CombatV1CpuMatchTermination termination,
  CombatV1CpuMatchTerminalCause? terminalCause,
  int? winnerPlayerIndex,
  String? winnerWrestlerId,
  bool safetyLimitReached = false,
  String? invariantViolationMessage,
}) => CombatV1MatchSimulationResult(
  matchIndex: matchIndex,
  simulationMatchId: id,
  wrestlerAId: wrestlerAId,
  wrestlerBId: wrestlerBId,
  playerAOwnerId: 'sim-1-$matchIndex-a',
  playerBOwnerId: 'sim-1-$matchIndex-b',
  playerAPolicyId: 'randomLegal',
  playerBPolicyId: 'randomLegal',
  masterSeed: 1,
  matchSeed: 2,
  engineSeed: 3,
  playerAPolicySeed: 4,
  playerBPolicySeed: 5,
  seedDerivationVersion: 1,
  maxActions: 500,
  rules: statsTestRules,
  termination: termination,
  actionCount: actionCount,
  finalTurnNumber: finalTurnNumber,
  safetyLimitReached: safetyLimitReached,
  finalStateSummary: statsTestFinalStateSummary(),
  terminalCause: terminalCause,
  winnerPlayerIndex: winnerPlayerIndex,
  winnerWrestlerId: winnerWrestlerId,
  invariantViolationMessage: invariantViolationMessage,
);
