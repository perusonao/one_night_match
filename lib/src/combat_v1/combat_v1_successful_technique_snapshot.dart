/// 直近で成立した（COUNTERされずにdeclineで解決した）TECHNIQUE1件の
/// immutable snapshot（Phase 4、Codexレビュー指摘H2/H3対応）。
///
/// Phase 5（PIN）・Phase 6（SUBMISSION）・Phase 8（ROUGH次ターン制限）・
/// Phase 9（FINISHER）が「直近で成立したTECHNIQUEはどれか」を参照するため
/// のDomain境界。Phase 4ではこのsnapshotを`CombatV1MatchState`へ保持する
/// だけで、[directPin]/[submissionHold]/[finisherType]の値による分岐処理
/// （PIN移行・SUBMISSION判定・FINISHER解禁等）は一切行わない。
library;

import 'combat_v1_enums.dart';

/// 成立したTECHNIQUE1件のスナップショット。
///
/// 「使用した（`techniquesUsedThisTurn`）」と「成立した
/// （`lastSuccessfulTechnique`）」は別概念（docs/combat_rules_v1.md
/// 「15. Technique宣言」「23. COUNTERはtechniquesUsedThisTurnに含めない」）:
/// - TECHNIQUE宣言はCOUNTERされてもされなくても`techniquesUsedThisTurn`を
///   +1する。
/// - `lastSuccessfulTechnique`は、宣言された攻撃がCOUNTERされず
///   （declineで）成立した場合にのみ更新する。COUNTER成立時は更新しない
///   （既存の値も上書きしない）。
class CombatV1SuccessfulTechniqueSnapshot {
  const CombatV1SuccessfulTechniqueSnapshot({
    required this.attackerPlayerIndex,
    required this.cardInstanceId,
    required this.cardId,
    required this.category,
    required this.attribute,
    required this.family,
    required this.directPin,
    required this.submissionHold,
    required this.finisherType,
    required this.resultOpponentState,
  });

  /// 成立させた攻撃側のplayerIndex。
  final int attackerPlayerIndex;

  final String cardInstanceId;
  final String cardId;
  final CombatV1CardCategory category;
  final CombatV1EnergyAttribute attribute;
  final CombatV1TechniqueFamily family;
  final bool directPin;
  final bool submissionHold;
  final CombatV1FinisherType? finisherType;
  final CombatV1WrestlerPosture? resultOpponentState;
}
