/// COUNTERカード定義モデル（docs/combat_rules_v1.md 7章）。
///
/// Phase 1〜3ではCOUNTER判定そのものを実装しなかった（Phase 4で正式化）。
/// COUNTERカード自身は固定ENERGY COSTを持たない（返される攻撃TECHNIQUEの
/// ENERGY COST総量が必要支払い量になる、docs/combat_rules_v1.md「7.
/// COUNTER ENERGY」、判定・支払いロジックは
/// `combat_v1_counter_rules.dart`/`combat_v1_engine.dart`参照）。
library;

import 'combat_v1_enums.dart';

/// COUNTERカード1枚の静的定義。
///
/// [counterableFamilies]/[counterableGroups]はどちらか一方でも空でない
/// ことをCatalog validation（`combat_v1_catalog_validation.dart`）が要求する。
/// 意図的に重複・冗長な指定を含むテスト用データも構築できるよう、`List`
/// のまま保持し、値の一意性・冗長性はCatalog validationが検出する
/// （immutableなSetへ変換すると重複自体が構造的に不可能になり、Catalog
/// validationの対応するエラー種別が到達不能になってしまうため、あえて
/// `List`のままにしている）。
class CombatV1Counter {
  const CombatV1Counter({
    required this.id,
    required this.name,
    required this.attribute,
    this.counterableFamilies = const [],
    this.counterableGroups = const [],
  });

  final String id;
  final String name;

  /// このCOUNTERを使用するために支払うENERGYの属性。返される攻撃
  /// TECHNIQUEのENERGY属性構成をコピーするのではなく、単一属性で必要量
  /// （攻撃Costのtotal）を支払う（docs/combat_rules_v1.md「7. COUNTER
  /// ENERGY」）。wildはCatalog validationで拒否する（Counter.attribute
  /// != wild）。
  final CombatV1EnergyAttribute attribute;

  /// このCOUNTERが返せる技系統（具体分類）一覧
  /// （docs/combat_rules_v1.md「23.3章 Technique Family」）。
  final List<CombatV1TechniqueFamily> counterableFamilies;

  /// このCOUNTERが返せる技系統グループ（上位分類）一覧
  /// （docs/combat_rules_v1.md「23.2章 Family Group」）。
  final List<CombatV1TechniqueFamilyGroup> counterableGroups;
}
