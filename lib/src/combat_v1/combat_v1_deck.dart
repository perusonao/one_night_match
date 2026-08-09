/// デッキ関連モデル（docs/combat_rules_v1.md 3章）。
library;

import 'combat_v1_enums.dart';

/// デッキ内の物理カード1枚。
class CombatV1DeckEntry {
  const CombatV1DeckEntry({
    required this.instanceId,
    required this.cardId,
    required this.category,
  });

  /// このデッキ内で一意な物理カードID（同名カードを複数枚区別するため）。
  final String instanceId;

  /// カード定義ID（`CombatV1Technique.id` または `CombatV1Counter.id`）。
  final String cardId;

  final CombatV1CardCategory category;
}

/// 1人ぶんの30枚デッキ定義。
class CombatV1DeckDefinition {
  const CombatV1DeckDefinition({
    required this.wrestlerId,
    required this.entries,
  });

  final String wrestlerId;
  final List<CombatV1DeckEntry> entries;

  int get size => entries.length;

  int countOf(CombatV1CardCategory category) =>
      entries.where((entry) => entry.category == category).length;
}

/// デッキのカテゴリ別枚数設定（docs/combat_rules_v1.md 3章）。
///
/// NORMAL18／SIGNATURE4／FINISHER2／COUNTER6＝合計30が既定値。数値は
/// 調整可能にするため`CombatV1RulesConfig`から差し替えられる構造にする
/// （docs/combat_rules_v1.md 26章「ルール定数とレスラー/技データを分離する」）。
class CombatV1DeckComposition {
  const CombatV1DeckComposition({
    this.normalCount = 18,
    this.signatureCount = 4,
    this.finisherCount = 2,
    this.counterCount = 6,
  });

  final int normalCount;
  final int signatureCount;
  final int finisherCount;
  final int counterCount;

  int get total => normalCount + signatureCount + finisherCount + counterCount;

  /// [definition] がこの構成と一致するか（枚数のみ検証、カード内容は問わない）。
  bool matches(CombatV1DeckDefinition definition) =>
      definition.size == total &&
      definition.countOf(CombatV1CardCategory.normal) == normalCount &&
      definition.countOf(CombatV1CardCategory.signature) == signatureCount &&
      definition.countOf(CombatV1CardCategory.finisher) == finisherCount &&
      definition.countOf(CombatV1CardCategory.counter) == counterCount;
}
