/// PIN（docs/combat_rules_v1.md 8章）のカウント・KOC・PINカード移動を
/// 決定する純粋関数群（Phase 5）。
///
/// `CombatV1Engine`から呼び出される計算ロジックをここへ切り出し、Engine本体
/// （state遷移の配線）とルール計算（何カウントになるか・何が動くか）の
/// 責務を分離する（`combat_v1_counter_rules.dart`と同じ方針）。
library;

import 'combat_v1_enums.dart';
import 'combat_v1_rules_config.dart';

/// PINの最終カウント結果を判定する（docs/combat_rules_v1.md 8.2章
/// 「カウント」）。
///
/// 防御側の[defenderKoc]で支払える最も有利な（防御側にとって結果の良い）
/// カウントを1つ返す。カウントは「1（KOC3、返した側が1枚追加ドロー）」
/// 「2（KOC2）」「2.9（KOC1、攻撃側は攻撃を継続できる）」の順に有利
/// （8.2章のカウント表の並び順）なので、最も有利な段階から順に
/// 支払い可能かを確認する。いずれのKOCコストも支払えない場合は`null`
/// を返す——「必要なKOCを支払えなければ3カウントとなり、PIN決着」
/// （8.2章）に対応する、PIN決着（match over）を意味する。
///
/// KOCを実際に消費するかどうかはこの関数の責務ではない（読み取り専用の
/// 判定のみ）。呼び出し側（`CombatV1Engine`）が、返された結果に応じて
/// 実際にKOCを差し引く。
CombatV1PinCountResult? determinePinCountResult({
  required int defenderKoc,
  required CombatV1RulesConfig rules,
}) {
  if (defenderKoc >= rules.pinCountOneKocCost) {
    return CombatV1PinCountResult.one;
  }
  if (defenderKoc >= rules.pinCountTwoKocCost) {
    return CombatV1PinCountResult.two;
  }
  if (defenderKoc >= rules.pinCountTwoPointNineKocCost) {
    return CombatV1PinCountResult.twoPointNine;
  }
  return null;
}

/// [count]でPINを終了する際に防御側が支払うKOC（docs/combat_rules_v1.md
/// 8.2章）。
int pinKocCostFor(CombatV1PinCountResult count, CombatV1RulesConfig rules) =>
    switch (count) {
      CombatV1PinCountResult.one => rules.pinCountOneKocCost,
      CombatV1PinCountResult.two => rules.pinCountTwoKocCost,
      CombatV1PinCountResult.twoPointNine =>
        rules.pinCountTwoPointNineKocCost,
    };

/// [count]でPINが終了した場合にPINカードが移動するか（docs/combat_rules_v1.md
/// 8.1章「1カウント／2カウントで終了したPINでは、使用したPINカードを
/// 原則として相手側へ移動する。2.9カウントでは移動しない」）。
///
/// 移動の向きは攻撃側→防御側で確定している（Phase 5セッションでユーザーが
/// 確定）。最低1枚保証（8.1章）による移動抑止は、この関数の呼び出し側
/// （`pinCardTransferAmount`）が[attackerPinCardsHeld]を見て判定する。
bool pinCardMovesFor(CombatV1PinCountResult count) => switch (count) {
  CombatV1PinCountResult.one => true,
  CombatV1PinCountResult.two => true,
  CombatV1PinCountResult.twoPointNine => false,
};

/// [count]でPINが終了した際に、攻撃側から防御側へ実際に移動するPINカード
/// 枚数（0または1）を返す。
///
/// 最低1枚保証（docs/combat_rules_v1.md 8.1章「現在PINカードが1枚しか
/// ないプレイヤーは、そのカードを相手へ移動しない」）により、
/// [attackerPinCardsHeld]が1以下の場合は移動しない（0を返す）。
int pinCardTransferAmount({
  required CombatV1PinCountResult count,
  required int attackerPinCardsHeld,
}) {
  if (!pinCardMovesFor(count)) return 0;
  if (attackerPinCardsHeld <= 1) return 0;
  return 1;
}

/// [count]で1カウント特有のボーナス（返した側＝防御側が山札から追加で
/// 1枚引く、docs/combat_rules_v1.md 8.2章）が発生するか。
///
/// カード移動が最低1枚保証で抑止された場合でも、この効果自体は
/// カウント結果に紐づく別効果として発生する（8.1章のカード移動ルールと
/// 8.2章のカウント表は独立した効果として記載されているため）。
bool pinCountGrantsBonusDraw(CombatV1PinCountResult count) =>
    count == CombatV1PinCountResult.one;

/// [count]で2.9カウント特有の「攻撃側は攻撃を継続できる」
/// （docs/combat_rules_v1.md 8.2章）が適用されるか。
///
/// 1／2カウントでは、Phase 5セッションでユーザーが確定した方針により
/// 攻守交代・ターン終了寄りの扱いとなる（`CombatV1Engine._resolvePin`
/// 参照）。
bool pinCountAllowsAttackerToContinue(CombatV1PinCountResult count) =>
    count == CombatV1PinCountResult.twoPointNine;
