/// SUBMISSION（docs/combat_rules_v1.md 10.1章「通常SUBMISSION」）の突入条件・
/// ESCAPE/GIVE UP判定を決定する純粋関数群（Phase 6）。
///
/// `CombatV1Engine`から呼び出される計算ロジックをここへ切り出し、Engine本体
/// （state遷移の配線）とルール計算（SUBMISSIONへ移行するか・ESCAPEできるか）
/// の責務を分離する（`combat_v1_pin_rules.dart`と同じ方針）。
library;

import 'combat_v1_enums.dart';
import 'combat_v1_rules_config.dart';

/// [opponentHp]（SUBMISSIONホールド技の解決後の相手HP）が、通常SUBMISSIONへ
/// 自動移行できる条件（docs/combat_rules_v1.md 10.1章「相手HP50以下で
/// 宣言可能」）を満たすか。
///
/// HP0でも条件を満たす（14章「HP0でも試合は継続する」・10.1章「HP0でも
/// KOCがあればESCAPE可能」——SUBMISSION自体の突入をHP0で特別扱いしない）。
bool submissionEligible({
  required int opponentHp,
  required CombatV1RulesConfig rules,
}) => opponentHp <= rules.submissionHpThreshold;

/// 防御側の[defenderKoc]から、SUBMISSIONの自動解決結果を決定する
/// （docs/combat_rules_v1.md 10.1章「ESCAPE: KOC1を消費。KOCを支払えなければ
/// GIVE UP」）。
///
/// PINのKICK OUTと同じく、防御側が必要なKOCを保有していれば必ずESCAPEする
/// （あえて支払わずGIVE UPを選ぶ、という選択肢は存在しない）。KOCを実際に
/// 消費するかどうかはこの関数の責務ではない（読み取り専用の判定のみ）。
CombatV1SubmissionOutcome determineSubmissionOutcome({
  required int defenderKoc,
  required CombatV1RulesConfig rules,
}) => defenderKoc >= rules.submissionEscapeKocCost
    ? CombatV1SubmissionOutcome.escape
    : CombatV1SubmissionOutcome.giveUp;
