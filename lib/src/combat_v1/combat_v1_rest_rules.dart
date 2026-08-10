/// REST（docs/combat_rules_v1.md 11章「REST / DOWN」）のHP回復量を決定する
/// 純粋関数群（Phase 7）。
///
/// `CombatV1Engine`から呼び出される計算ロジックをここへ切り出し、Engine本体
/// （state遷移の配線）とルール計算（回復量）の責務を分離する
/// （`combat_v1_pin_rules.dart`・`combat_v1_submission_rules.dart`と同じ方針）。
library;

/// RESTによる回復後のHP（docs/combat_rules_v1.md 11章「REST: HP+10回復
/// （最大150を超えない）」）。[maxHp]を超えない。
int restRecoveredHp({
  required int currentHp,
  required int maxHp,
  required int recoveryAmount,
}) {
  final healed = currentHp + recoveryAmount;
  return healed > maxHp ? maxHp : healed;
}
