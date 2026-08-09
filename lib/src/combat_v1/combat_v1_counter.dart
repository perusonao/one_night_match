/// COUNTERカード定義モデル（docs/combat_rules_v1.md 7章）。
///
/// Phase 1ではCOUNTER判定そのものを実装しない（Phase 4予定）。デッキ内に
/// COUNTERカードのカテゴリを保持できる最小限のモデルのみ用意する。
library;

import 'combat_v1_enums.dart';

/// COUNTERカード1枚の静的定義（Phase 1は最小形）。
class CombatV1Counter {
  const CombatV1Counter({
    required this.id,
    required this.name,
    required this.attribute,
    this.counterableFamilyIds = const [],
  });

  final String id;
  final String name;
  final CombatV1EnergyAttribute attribute;

  /// このCOUNTERが返せる技系統のID一覧（Phase 4の技系統マッチング用の
  /// 予約フィールド。正式taxonomy未確定のため空リストが既定値、
  /// docs/design/combat_v1_open_questions.md 4番）。
  final List<String> counterableFamilyIds;
}
