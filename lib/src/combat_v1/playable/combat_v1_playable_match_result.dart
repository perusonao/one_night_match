/// Combat Ver.1 Playable 1A — Match Result
/// （docs/design/combat_v1_playable_match_ui.md 18章）。
///
/// `CombatV1PlayableMatchController.status`が`matchOver`/`safetyLimit`/
/// `invariantViolation`のいずれかになった時点で1度だけ構築される、
/// structured terminal result。既存`CombatV1MatchSimulationResult`
/// （Simulation層）はそのまま再利用しない——`simulationMatchId`・owner
/// audit・batch identityはPlayableに不要であり、Simulation packageへの
/// 依存方向を持ち込まないため。
library;

import '../combat_v1_enums.dart';
import '../combat_v1_match_lifecycle.dart';
import '../combat_v1_rules_config.dart';
import 'combat_v1_playable_match_snapshot.dart';

/// [CombatV1PlayableMatchController]の試合終了後結果
/// （docs/design/combat_v1_playable_match_ui.md 18章）。
class CombatV1PlayableMatchResult {
  const CombatV1PlayableMatchResult({
    required this.status,
    required this.actionCount,
    required this.finalTurnNumber,
    required this.safetyLimitReached,
    required this.finalHumanStatus,
    required this.finalCpuStatus,
    required this.finalSharedHeat,
    required this.finalPhase,
    required this.finalActivePlayerIndex,
    required this.humanWrestlerId,
    required this.cpuWrestlerId,
    required this.engineSeed,
    required this.cpuPolicySeed,
    required this.maxActions,
    required this.rules,
    this.terminalCause,
    this.winnerPlayerIndex,
    this.winnerWrestlerId,
    this.invariantViolationMessage,
  });

  /// `matchOver`/`safetyLimit`/`invariantViolation`のいずれか
  /// （`active`/`error`でこのresultが構築されることはない）。
  final CombatV1PlayableControllerStatus status;

  /// `status == matchOver`の場合のみ非null。
  final CombatV1MatchTerminalCause? terminalCause;

  /// `0`=Human、`1`=CPU。未決着（safetyLimit/invariantViolation）では
  /// 勝敗をfabricateしないため常に`null`。
  final int? winnerPlayerIndex;

  /// [winnerPlayerIndex]を[humanWrestlerId]/[cpuWrestlerId]へ変換した値。
  final String? winnerWrestlerId;

  final int actionCount;
  final int finalTurnNumber;

  /// `status == safetyLimit`かどうかの利便性フラグ。
  final bool safetyLimitReached;

  /// `status == invariantViolation`の場合のみ非null。
  final String? invariantViolationMessage;

  /// 試合終了直後のHuman/CPU status（`CombatV1PlayableMatchSnapshot`と
  /// 同じhidden-safe projection型を再利用する——3つ目のsummary型を
  /// 新規追加しない）。
  final CombatV1PlayableHumanStatus finalHumanStatus;
  final CombatV1PlayableOpponentStatus finalCpuStatus;

  final int finalSharedHeat;
  final CombatV1MatchPhase finalPhase;
  final int finalActivePlayerIndex;

  final String humanWrestlerId;
  final String cpuWrestlerId;
  final int engineSeed;
  final int cpuPolicySeed;
  final int maxActions;
  final CombatV1RulesConfig rules;

  bool get hasWinner => winnerPlayerIndex != null;
}
