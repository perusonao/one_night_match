/// CombatV1ActionObserver（Phase 11B addendum「Structured Action
/// Observation」、docs/design/combat_v1_phase11b_cpu.md）。
///
/// [CombatV1CpuMatchRunner]が各Action実行の前後を通知するための最小限の
/// optional extension point。Phase 11B自身はobservationを一切蓄積・分析
/// しない——Phase 12（Simulator）がcollectorを差し込むための構造だけを
/// 用意する。
library;

import 'combat_v1_legal_action.dart';
import 'combat_v1_match_state.dart';

/// [CombatV1CpuMatchRunner]が[CombatV1ActionExecutor.execute]成功のたびに
/// 通知する1件の観測（Phase 11B addendum）。
///
/// Engine内部で自動的に行われる処理（direct PIN resolution・submission
/// resolution・draw・shuffle・posture update・turn transition等）は個別の
/// observationを持たない——それらは[stateAfter]の一部として、対応する
/// public Action（例: [CombatV1DeclineCounterAction]）1件の観測に含まれる。
class CombatV1ActionObservation {
  const CombatV1ActionObservation({
    required this.actionIndex,
    required this.turnNumber,
    required this.actorPlayerIndex,
    required this.action,
    required this.stateBefore,
    required this.stateAfter,
  });

  /// この試合内で0始まりの、成功したpublic CPU actionの通し番号
  /// （[CombatV1CpuMatchResult.actionCount]と同じ数え方）。
  final int actionIndex;

  /// [action]実行時点（[stateBefore]）の`turnNumber`。
  final int turnNumber;

  /// [action.actorPlayerIndex]と同じ値（呼び出し側の利便性のため複製）。
  final int actorPlayerIndex;

  /// 実行された[CombatV1LegalAction]。
  final CombatV1LegalAction action;

  /// [action]実行前の[CombatV1MatchState]。
  final CombatV1MatchState stateBefore;

  /// [action]実行後の[CombatV1MatchState]。
  final CombatV1MatchState stateAfter;
}

/// [CombatV1CpuMatchRunner.run]が各Action実行後に通知するinterface
/// （Phase 11B addendum）。
///
/// optional——observerを渡さなくても[CombatV1CpuMatchRunner]は正常動作する。
/// 実装は読み取り専用の観測に徹し、[CombatV1MatchState]や試合進行へ
/// 副作用を与えないこと。
abstract interface class CombatV1ActionObserver {
  void onActionResolved(CombatV1ActionObservation observation);
}
