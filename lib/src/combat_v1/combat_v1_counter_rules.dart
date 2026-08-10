/// COUNTER成立判定・動的ENERGY COST算出（docs/combat_rules_v1.md 7章、
/// Phase 4）。
///
/// `CombatV1Engine`（`combat_v1_engine.dart`）から呼ばれる純粋関数群。
/// MatchState/PlayerStateは一切変更しない読み取り専用ロジックのみを持つ
/// （docs/design/combat_v1_phase1_design.md 1章「拡張ポイント」で想定
/// されていた`combat_v1_counter_rules.dart`）。
library;

import 'combat_v1_counter.dart';
import 'combat_v1_energy.dart';
import 'combat_v1_enums.dart';

/// [counter]が攻撃[attackFamily]を返せるか（docs/combat_rules_v1.md
/// 「23.5章 COUNTER matching」）。
///
/// 成立条件: `familyMatch || groupMatch`。
/// - familyMatch: `counter.counterableFamilies`が`attackFamily`を含む。
/// - groupMatch: `counter.counterableGroups`が`attackFamily.group`を含む。
///
/// attribute（ENERGY属性）の一致だけではCOUNTER成立にしない
/// （呼び出し側が別途[CombatV1Counter.attribute]とENERGY支払いを検証する）。
bool techniqueFamilyMatchesCounter(
  CombatV1Counter counter,
  CombatV1TechniqueFamily attackFamily,
) {
  final familyMatch = counter.counterableFamilies.contains(attackFamily);
  final groupMatch = counter.counterableGroups.contains(attackFamily.group);
  return familyMatch || groupMatch;
}

/// COUNTER成立に必要な合成ENERGY COST（docs/combat_rules_v1.md「7. COUNTER
/// ENERGY」）。
///
/// 返される攻撃TECHNIQUEのENERGY COST「総量」（[attackEnergyCost.total]）を、
/// [counter.attribute]単一属性で要求する合成Costを組み立てる。攻撃Costの
/// 属性構成（例: 投2+打1）をCOUNTER側へコピーすることはしない。
CombatV1EnergyCost counterSyntheticCost(
  CombatV1Counter counter,
  CombatV1EnergyCost attackEnergyCost,
) => CombatV1EnergyCost({counter.attribute: attackEnergyCost.total});
