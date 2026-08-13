/// Combat Ver.1 Playable 2A-4 — Counter Prevention Projection
/// （Review Findings Fix、Major）。
///
/// `CombatV1PlayableMatchController`がCounter feedback
/// （`CombatV1PlayableActionFeedback.preventedDirectPin`/
/// `preventedSubmissionHold`）を構築する際に使う、pure derivation関数群。
///
/// Core `combat_v1_engine.dart` `_resolvePendingAttack`が、宣言済み
/// TECHNIQUEをCounterしなかった場合に実際にDIRECT PIN/SUBMISSION自動
/// 移行へ進む条件（DIRECT PIN: 解決後の防御側postureがDOWN／SUBMISSION:
/// damage適用後の防御側HPが閾値以下）を、controller層専用に安全に
/// projectionするだけの純粋関数——Coreの条件式と1:1で一致させ、新しい
/// Combat rule判定は一切追加しない（`submissionEligible`はCore自身が
/// 使う関数をそのまま呼び出し、閾値比較を再実装しない）。
///
/// 「DIRECT PIN/SUBMISSION traitを持っていた」ことと「Counterしなければ
/// 実際にその自動移行へ進んでいた」ことは別概念——この2関数は後者だけを
/// 判定する（前者はTechnique/PendingAttackの`directPin`/`submissionHold`/
/// `finisherType`フィールドをそのまま参照すればよく、この専用関数は
/// 不要）。
library;

import '../combat_v1_enums.dart';
import '../combat_v1_rules_config.dart';
import '../combat_v1_submission_rules.dart';

/// DIRECT PIN traitを持つ攻撃（[effectiveDirectPin]、FINISHER優先順位
/// 適用済みの値を呼び出し側から渡す）が、Counterされず成立した場合に、
/// Core `_resolvePendingAttack`の
/// `effectiveDirectPin && next.opponent.posture == down`と同じ条件で
/// 実際にDIRECT PIN自動移行へ進むか。
///
/// [resultOpponentState]は宣言済みTECHNIQUEの静的metadata
/// （`CombatV1PendingAttack.resultOpponentState`、非nullならTechnique
/// 解決後の防御側postureを直接指定する）。`null`の場合、Coreは防御側の
/// 現在postureをそのまま維持する（`pending.resultOpponentState ??
/// state.opponent.posture`）ため、[defenderPostureBeforeResolution]
/// （宣言からCounter応答までの間変化しない、防御側の現在posture）を
/// そのまま使う。
bool combatV1PlayableWouldTransitionToDirectPin({
  required bool effectiveDirectPin,
  required CombatV1WrestlerPosture? resultOpponentState,
  required CombatV1WrestlerPosture defenderPostureBeforeResolution,
}) {
  if (!effectiveDirectPin) return false;
  final resolvedPosture =
      resultOpponentState ?? defenderPostureBeforeResolution;
  return resolvedPosture == CombatV1WrestlerPosture.down;
}

/// SUBMISSION traitを持つ攻撃（[effectiveSubmissionHold]、FINISHER優先
/// 順位適用済みの値を呼び出し側から渡す）が、Counterされず成立した
/// 場合に、Core `_resolvePendingAttack`の
/// `effectiveSubmissionHold && submissionEligible(damage適用後HP)`と
/// 同じ条件で実際にSUBMISSION resolutionへ進むか。
///
/// [defenderHpBeforeResolution]/[defenderMaxHp]/[damage]から、Coreと
/// 同じ`max(0, min(hp - damage, maxHp))`でdamage適用後HPを算出し、
/// Core自身が使う[submissionEligible]（`combat_v1_submission_rules.dart`）
/// をそのまま呼び出す——閾値比較をここで再実装しない。
///
/// NORMAL Submission TechniqueとSUBMISSION FINISHERで、この突入条件
/// 自体は同一——差があるのは突入後のESCAPE/GIVE UP判定
/// （`combat_v1_finisher_rules.dart`
/// `determineFinisherSubmissionOutcome`のHP0特殊処理、GIVE UP即決着）
/// であり、「SUBMISSION resolutionへ移行するか」を意味するこの関数の
/// 戻り値には影響しない——「SUBMISSION trait」「SUBMISSION
/// transition」「GIVE UP」を混同しないこと。
bool combatV1PlayableWouldTransitionToSubmission({
  required bool effectiveSubmissionHold,
  required int defenderHpBeforeResolution,
  required int defenderMaxHp,
  required int damage,
  required CombatV1RulesConfig rules,
}) {
  if (!effectiveSubmissionHold) return false;
  final wouldBeOpponentHp = (defenderHpBeforeResolution - damage).clamp(
    0,
    defenderMaxHp,
  );
  return submissionEligible(opponentHp: wouldBeOpponentHp, rules: rules);
}
