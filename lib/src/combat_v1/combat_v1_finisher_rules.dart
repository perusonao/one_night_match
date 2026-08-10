/// FINISHER（docs/combat_rules_v1.md 13章）の解禁判定・SUBMISSION
/// FINISHER専用のESCAPE/GIVE UP判定を決定する純粋関数群（Phase 9）。
///
/// `CombatV1Engine`から呼び出される計算ロジックをここへ切り出し、Engine本体
/// （state遷移の配線）とルール計算（解禁しているか・ESCAPEできるか）の責務を
/// 分離する（`combat_v1_pin_rules.dart`・`combat_v1_submission_rules.dart`と
/// 同じ方針）。
library;

import 'combat_v1_enums.dart';
import 'combat_v1_rules_config.dart';
import 'combat_v1_submission_rules.dart';

/// 共有[sharedHeat]がFINISHER解禁閾値
/// （[CombatV1RulesConfig.finisherHeatThreshold]、既定200）に達しているか
/// （docs/combat_rules_v1.md 12章「200以上でFINISHER解禁」・13章）。
///
/// HEATは消費リソースではないため（12章）、この関数はHEATを変更しない
/// 純粋な読み取り専用判定であり、一度trueになった状態がfalseへ戻ることは
/// ゲーム進行上ない。
bool finisherUnlocked({
  required int sharedHeat,
  required CombatV1RulesConfig rules,
}) => sharedHeat >= rules.finisherHeatThreshold;

/// SUBMISSION FINISHER（docs/combat_rules_v1.md 10.2章）の自動解決結果を
/// 決定する。
///
/// 通常SUBMISSION（[determineSubmissionOutcome]、
/// `combat_v1_submission_rules.dart`）との唯一の相違点:
/// 解決後の相手[opponentHp]が0の場合、[defenderKoc]の保有量に関わらず
/// 即GIVE UPとなる（10.2章「HP0: 即GIVE UP」——HP0による特殊決着の
/// 唯一の例外パターン、14章「HP0の扱い」）。相手HPが1以上（かつ突入条件
/// である[CombatV1RulesConfig.submissionHpThreshold]以下）の場合は、
/// 通常SUBMISSIONと全く同じKOCベースのESCAPE/GIVE UP判定（10.2章
/// 「HP1〜50: KOC1でESCAPE可能」）を適用するため、[determineSubmissionOutcome]
/// をそのまま再利用する（判定ロジックの重複を避ける）。
///
/// KOCを実際に消費するかどうかはこの関数の責務ではない（読み取り専用の
/// 判定のみ）。突入条件（相手HPが[CombatV1RulesConfig.submissionHpThreshold]
/// 以下か）の判定はこの関数の責務ではなく、通常SUBMISSIONと同じ
/// `submissionEligible`（`combat_v1_submission_rules.dart`）を呼び出し側が
/// 別途使用する。
CombatV1SubmissionOutcome determineFinisherSubmissionOutcome({
  required int opponentHp,
  required int defenderKoc,
  required CombatV1RulesConfig rules,
}) {
  if (opponentHp <= 0) {
    return CombatV1SubmissionOutcome.giveUp;
  }
  return determineSubmissionOutcome(defenderKoc: defenderKoc, rules: rules);
}
