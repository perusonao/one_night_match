/// REST（docs/combat_rules_v1.md 11章「REST / DOWN」）のHP回復量を決定する
/// 純粋関数群（Phase 7）。
///
/// `CombatV1Engine`から呼び出される計算ロジックをここへ切り出し、Engine本体
/// （state遷移の配線）とルール計算（回復量）の責務を分離する
/// （`combat_v1_pin_rules.dart`・`combat_v1_submission_rules.dart`と同じ方針）。
library;

import 'dart:math';

/// RESTによる回復後のHP（docs/combat_rules_v1.md 11章「REST: HP+10回復
/// （最大150を超えない）」）。[maxHp]を超えず、0未満にもならない
/// （`_resolvePendingAttack`のHP 0 clampと同じ`max(0, min(..., maxHp))`
/// パターン、`combat_v1_engine.dart`参照）。[recoveryAmount]が負数
/// （malformed `CombatV1RulesConfig.restHpRecovery`）であっても、HPが
/// 負数になることはない（Phase 7 Codexレビュー指摘対応）。
int restRecoveredHp({
  required int currentHp,
  required int maxHp,
  required int recoveryAmount,
}) {
  final healed = currentHp + recoveryAmount;
  return max(0, min(healed, maxHp));
}
