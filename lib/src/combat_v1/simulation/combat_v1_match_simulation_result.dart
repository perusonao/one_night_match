/// Combat Ver.1 Phase 12A — Match Simulation Result
/// （docs/design/combat_v1_phase12a_simulation_core.md）。
///
/// [CombatV1SimulationRunner]が1試合実行するごとに構築する、Phase 12Aの
/// 最小限のstructured result。Phase 11Bの`CombatV1CpuMatchResult`（structured
/// termination・terminal cause・actionCount等）をそのまま利用し、Simulator
/// 独自のPIN/SUBMISSION判定やsafetyLimit/invariantViolationの再解釈は行わない
/// （13章「Structured terminal result」）。
///
/// full action traceは保存しない——`finalState`そのもの（hand/drawPile/
/// discardPile・logを含む）ではなく、平坦化した[CombatV1MatchFinalStateSummary]
/// のみを保持することで、複数試合分のResultが肥大化しないようにする。
library;

import '../combat_v1_cpu_match_runner.dart';
import '../combat_v1_enums.dart';
import '../combat_v1_legal_action.dart';
import '../combat_v1_match_state.dart';
import '../combat_v1_rules_config.dart';
import 'combat_v1_simulation_seed.dart';

/// 1試合の決着後stateから抽出した、最小限の平坦化summary（Phase 12A
/// 「Match Simulation Result」9章）。
///
/// `CombatV1MatchState`自体（hand/drawPile/discardPileの中身・human可読log
/// 等）は保持しない。value equality（`==`/`hashCode`）を持つため、
/// determinism test・replay testで`expect(a, b)`による直接比較ができる。
class CombatV1MatchFinalStateSummary {
  const CombatV1MatchFinalStateSummary({
    required this.playerAHp,
    required this.playerBHp,
    required this.playerAKoc,
    required this.playerBKoc,
    required this.playerAPosture,
    required this.playerBPosture,
    required this.playerAPinCardsHeld,
    required this.playerBPinCardsHeld,
    required this.playerAHandSize,
    required this.playerADrawPileSize,
    required this.playerADiscardPileSize,
    required this.playerBHandSize,
    required this.playerBDrawPileSize,
    required this.playerBDiscardPileSize,
    required this.playerAReshuffleCount,
    required this.playerBReshuffleCount,
    required this.sharedHeat,
    required this.finalPhase,
    required this.activePlayerIndex,
    required this.hasPendingAttack,
  });

  /// [state]から[CombatV1MatchFinalStateSummary]を抽出する。
  factory CombatV1MatchFinalStateSummary.fromState(CombatV1MatchState state) =>
      CombatV1MatchFinalStateSummary(
        playerAHp: state.playerA.hp,
        playerBHp: state.playerB.hp,
        playerAKoc: state.playerA.koc,
        playerBKoc: state.playerB.koc,
        playerAPosture: state.playerA.posture,
        playerBPosture: state.playerB.posture,
        playerAPinCardsHeld: state.playerA.pinCardsHeld,
        playerBPinCardsHeld: state.playerB.pinCardsHeld,
        playerAHandSize: state.playerA.hand.length,
        playerADrawPileSize: state.playerA.drawPile.length,
        playerADiscardPileSize: state.playerA.discardPile.length,
        playerBHandSize: state.playerB.hand.length,
        playerBDrawPileSize: state.playerB.drawPile.length,
        playerBDiscardPileSize: state.playerB.discardPile.length,
        playerAReshuffleCount: state.playerA.reshuffleCount,
        playerBReshuffleCount: state.playerB.reshuffleCount,
        sharedHeat: state.sharedHeat,
        finalPhase: state.phase,
        activePlayerIndex: state.activePlayerIndex,
        hasPendingAttack: state.pendingAttack != null,
      );

  final int playerAHp;
  final int playerBHp;
  final int playerAKoc;
  final int playerBKoc;
  final CombatV1WrestlerPosture playerAPosture;
  final CombatV1WrestlerPosture playerBPosture;
  final int playerAPinCardsHeld;
  final int playerBPinCardsHeld;
  final int playerAHandSize;
  final int playerADrawPileSize;
  final int playerADiscardPileSize;
  final int playerBHandSize;
  final int playerBDrawPileSize;
  final int playerBDiscardPileSize;
  final int playerAReshuffleCount;
  final int playerBReshuffleCount;
  final int sharedHeat;
  final CombatV1MatchPhase finalPhase;
  final int activePlayerIndex;
  final bool hasPendingAttack;

  @override
  bool operator ==(Object other) =>
      other is CombatV1MatchFinalStateSummary &&
      other.playerAHp == playerAHp &&
      other.playerBHp == playerBHp &&
      other.playerAKoc == playerAKoc &&
      other.playerBKoc == playerBKoc &&
      other.playerAPosture == playerAPosture &&
      other.playerBPosture == playerBPosture &&
      other.playerAPinCardsHeld == playerAPinCardsHeld &&
      other.playerBPinCardsHeld == playerBPinCardsHeld &&
      other.playerAHandSize == playerAHandSize &&
      other.playerADrawPileSize == playerADrawPileSize &&
      other.playerADiscardPileSize == playerADiscardPileSize &&
      other.playerBHandSize == playerBHandSize &&
      other.playerBDrawPileSize == playerBDrawPileSize &&
      other.playerBDiscardPileSize == playerBDiscardPileSize &&
      other.playerAReshuffleCount == playerAReshuffleCount &&
      other.playerBReshuffleCount == playerBReshuffleCount &&
      other.sharedHeat == sharedHeat &&
      other.finalPhase == finalPhase &&
      other.activePlayerIndex == activePlayerIndex &&
      other.hasPendingAttack == hasPendingAttack;

  @override
  int get hashCode => Object.hashAll([
    playerAHp,
    playerBHp,
    playerAKoc,
    playerBKoc,
    playerAPosture,
    playerBPosture,
    playerAPinCardsHeld,
    playerBPinCardsHeld,
    playerAHandSize,
    playerADrawPileSize,
    playerADiscardPileSize,
    playerBHandSize,
    playerBDrawPileSize,
    playerBDiscardPileSize,
    playerAReshuffleCount,
    playerBReshuffleCount,
    sharedHeat,
    finalPhase,
    activePlayerIndex,
    hasPendingAttack,
  ]);
}

/// [CombatV1SimulationRunner]が1試合実行するごとに構築するresult（Phase
/// 12A）。
///
/// Replay metadata（12章）として、この1試合を同一条件で再実行するために
/// 必要な値（wrestler/policy/seed/rules/maxActions/matchIndex）をすべて
/// 保持する。ただし実際の再実行には、`CombatV1SimulationPolicyKind`
/// （`combat_v1_simulation_policy.dart`）から[CombatV1DecisionPolicy]を
/// 生成し直す必要がある——Phase 12Aではresult全体のserializationは行わない
/// ため、replayは同一の`CombatV1SimulationConfig`
/// （`CombatV1SimulationResult.config`）と[matchIndex]を組み合わせて
/// `CombatV1SimulationRunner.runSingleMatch`を呼び直す形で行う。
class CombatV1MatchSimulationResult {
  const CombatV1MatchSimulationResult({
    required this.matchIndex,
    required this.simulationMatchId,
    required this.wrestlerAId,
    required this.wrestlerBId,
    required this.playerAOwnerId,
    required this.playerBOwnerId,
    required this.playerAPolicyId,
    required this.playerBPolicyId,
    required this.masterSeed,
    required this.matchSeed,
    required this.engineSeed,
    required this.playerAPolicySeed,
    required this.playerBPolicySeed,
    required this.seedDerivationVersion,
    required this.maxActions,
    required this.rules,
    required this.termination,
    required this.actionCount,
    required this.finalTurnNumber,
    required this.safetyLimitReached,
    required this.finalStateSummary,
    this.terminalCause,
    this.winnerPlayerIndex,
    this.winnerWrestlerId,
    this.lastAction,
    this.invariantViolationMessage,
  });

  /// このSimulation内で0始まりの試合番号（`deriveV1SimulationSeeds`の
  /// `matchIndex`と同じ値）。
  final int matchIndex;

  /// Simulator独自のdeterministic match identity（Codex review M2対応）。
  /// `CombatV1SimulationSeedSet.simulationMatchId`をそのまま転記する
  /// ——`CombatV1Engine.start`が生成する時刻依存の`matchId`
  /// （`finalState.matchId`）とは独立した、canonicalなidentityであり、
  /// Phase 12Bの集計・監査・replay boundaryとして利用できる。同一の
  /// `CombatV1SimulationConfig` + `matchIndex`からは常に同じ値になる。
  final String simulationMatchId;

  final String wrestlerAId;
  final String wrestlerBId;

  /// `CombatV1ProductionMatchConfig.playerAOwnerId`/`playerBOwnerId`へ
  /// 実際に渡した値をそのまま転記する（Codex review M2対応）——Result用に
  /// 別途再計算した値ではない。これにより「Resultに記録されたowner
  /// namespace」と「実際にphysical card instance生成へ使用されたowner
  /// namespace」の一致を構造的に保証する（`CombatV1SimulationRunner`
  /// 参照）。
  final String playerAOwnerId;
  final String playerBOwnerId;

  /// [CombatV1CpuMatchResult.policyAId]/[CombatV1CpuMatchResult.policyBId]
  /// と同じ値（実際に実行されたPolicyの`id`）。
  final String playerAPolicyId;
  final String playerBPolicyId;

  final int masterSeed;
  final int matchSeed;
  final int engineSeed;
  final int playerAPolicySeed;
  final int playerBPolicySeed;
  final int seedDerivationVersion;

  final int maxActions;
  final CombatV1RulesConfig rules;

  final CombatV1CpuMatchTermination termination;

  /// `termination == matchOver`の場合のみ非null
  /// （[CombatV1CpuMatchResult.terminalCause]をそのまま転記）。
  final CombatV1CpuMatchTerminalCause? terminalCause;

  /// `finalState.winnerPlayerIndex`（0=playerA、1=playerB）。未決着なら
  /// `null`。
  final int? winnerPlayerIndex;

  /// [winnerPlayerIndex]を[wrestlerAId]/[wrestlerBId]へ変換した値。未決着
  /// なら`null`。
  final String? winnerWrestlerId;

  final int actionCount;
  final int finalTurnNumber;

  /// `termination == safetyLimit`かどうかの利便性フラグ
  /// （`termination`本体が正なので冗長だが、集計時の判定を簡潔にする）。
  final bool safetyLimitReached;

  /// [CombatV1CpuMatchResult.lastAction]をそのまま転記
  /// （1件もactionが成功しなかった場合は`null`）。
  final CombatV1LegalAction? lastAction;

  /// `termination == invariantViolation`の場合のみ非null。
  final String? invariantViolationMessage;

  final CombatV1MatchFinalStateSummary finalStateSummary;

  /// [CombatV1CpuMatchRunner]の結果から[CombatV1MatchSimulationResult]を
  /// 構築する。Simulator側でPIN/SUBMISSION種別やsafetyLimit/
  /// invariantViolationの意味を再解釈することはない——`cpuResult`が持つ
  /// structured terminationをそのまま転記するのみ。
  factory CombatV1MatchSimulationResult.fromCpuResult({
    required int matchIndex,
    required String wrestlerAId,
    required String wrestlerBId,
    required String playerAOwnerId,
    required String playerBOwnerId,
    required CombatV1RulesConfig rules,
    required CombatV1SimulationSeedSet seeds,
    required CombatV1CpuMatchResult cpuResult,
  }) {
    final winnerPlayerIndex = cpuResult.finalState.winnerPlayerIndex;
    final winnerWrestlerId = switch (winnerPlayerIndex) {
      0 => wrestlerAId,
      1 => wrestlerBId,
      _ => null,
    };

    return CombatV1MatchSimulationResult(
      matchIndex: matchIndex,
      simulationMatchId: seeds.simulationMatchId,
      wrestlerAId: wrestlerAId,
      wrestlerBId: wrestlerBId,
      playerAOwnerId: playerAOwnerId,
      playerBOwnerId: playerBOwnerId,
      playerAPolicyId: cpuResult.policyAId,
      playerBPolicyId: cpuResult.policyBId,
      masterSeed: seeds.masterSeed,
      matchSeed: seeds.matchSeed,
      engineSeed: seeds.engineSeed,
      playerAPolicySeed: seeds.playerAPolicySeed,
      playerBPolicySeed: seeds.playerBPolicySeed,
      seedDerivationVersion: seeds.derivationVersion,
      maxActions: cpuResult.maxActions,
      rules: rules,
      termination: cpuResult.termination,
      terminalCause: cpuResult.terminalCause,
      winnerPlayerIndex: winnerPlayerIndex,
      winnerWrestlerId: winnerWrestlerId,
      actionCount: cpuResult.actionCount,
      finalTurnNumber: cpuResult.finalTurnNumber,
      safetyLimitReached:
          cpuResult.termination == CombatV1CpuMatchTermination.safetyLimit,
      lastAction: cpuResult.lastAction,
      invariantViolationMessage: cpuResult.invariantViolationMessage,
      finalStateSummary:
          CombatV1MatchFinalStateSummary.fromState(cpuResult.finalState),
    );
  }
}
