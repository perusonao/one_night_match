/// 調整可能なルール定数の一元管理（docs/combat_rules_v1.md 26章の方針:
/// 「ルール定数とレスラー/技データを分離する」）。
library;

import 'combat_v1_deck.dart';
import 'combat_v1_enums.dart';

/// Combat Ver.1のルール定数。
///
/// Phase 1〜2で実際に使用する定数のみを持つ。KOC消費量・PINカード総数(4枚)・
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
    this.signatureSameNameLimit = 2,
    this.finisherSameNameLimit = 1,
    this.counterSameNameLimit = 2,
    this.counterAllowsWildSubstitution = false,
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

  /// NORMALの同名カード上限（docs/combat_rules_v1.md 3章）。
  final int normalSameNameLimit;

  /// SIGNATUREの同名カード上限（docs/combat_rules_v1.md 3章）。
  final int signatureSameNameLimit;

  /// FINISHERの同名カード上限（docs/combat_rules_v1.md 3章）。
  final int finisherSameNameLimit;

  /// COUNTERの同名カード上限（docs/combat_rules_v1.md 3章）。
  final int counterSameNameLimit;

  /// COUNTER支払い（synthetic cost）で＊(wild)ENERGYによる補完を許可するか
  /// （docs/combat_rules_v1.md 5.2章「COUNTERでの＊(ワイルド)ENERGYの
  /// 扱い」、Phase
  /// 4で確定）。既定値`false`——通常TECHNIQUE支払いとは異なるポリシーで
  /// あることが今回のPhase 4の確定事項（既定でCOUNTER側はwild補完不可）。
  /// `resolveEnergyPayment`の`allowWildSubstitution`引数へそのまま渡す
  /// （`combat_v1_energy.dart`）。
  final bool counterAllowsWildSubstitution;

  /// [category]の同名カード上限（docs/combat_rules_v1.md 3章）。
  /// Deck validation（[../combat_v1_deck_validation.dart]）が参照する
  /// ルール値の一元管理先（Engine内へのマジックナンバー直書きを避けるため）。
  int sameNameLimitFor(CombatV1CardCategory category) => switch (category) {
    CombatV1CardCategory.normal => normalSameNameLimit,
    CombatV1CardCategory.signature => signatureSameNameLimit,
    CombatV1CardCategory.finisher => finisherSameNameLimit,
    CombatV1CardCategory.counter => counterSameNameLimit,
  };
}
