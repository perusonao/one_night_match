/// 調整可能なルール定数の一元管理（docs/combat_rules_v1.md 26章の方針:
/// 「ルール定数とレスラー/技データを分離する」）。
library;

import 'combat_v1_deck.dart';

/// Combat Ver.1のルール定数。
///
/// Phase 1で実際に使用する定数のみを持つ。KOC消費量・PINカード総数(4枚)・
/// REST回復量・FINISHER解禁HEAT(200)等は、該当ロジックを実装するPhaseで
/// 追加する（Phase 1では未使用の定数を先行して持たない、
/// docs/design/combat_v1_phase1_design.md 9章）。
class CombatV1RulesConfig {
  const CombatV1RulesConfig({
    this.startingHp = 150,
    this.startingKoc = 10,
    this.startingPinCards = 2,
    this.startingHandSize = 5,
    this.deckComposition = const CombatV1DeckComposition(),
    this.normalSameNameLimit = 3,
  });

  /// 全レスラー共通の初期HP（docs/combat_rules_v1.md 2・14章）。
  final int startingHp;

  /// 初期KOC（docs/combat_rules_v1.md 9章）。Phase 1では初期化のみ対象。
  final int startingKoc;

  /// 試合開始時の保有PINカード枚数（docs/combat_rules_v1.md 8.1章）。
  /// Phase 1では初期化のみ対象。
  final int startingPinCards;

  final int startingHandSize;

  /// デッキのカテゴリ別枚数（docs/combat_rules_v1.md 3章）。
  final CombatV1DeckComposition deckComposition;

  /// NORMALの同名カード上限（docs/combat_rules_v1.md 3章）。Phase 1では
  /// デッキ検証ロジックに未接続（値のみ保持）。
  final int normalSameNameLimit;
}
