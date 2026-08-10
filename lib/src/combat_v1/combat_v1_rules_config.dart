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
    this.totalPinCards = 4,
    this.pinCountOneKocCost = 3,
    this.pinCountTwoKocCost = 2,
    this.pinCountTwoPointNineKocCost = 1,
    this.submissionHpThreshold = 50,
    this.submissionEscapeKocCost = 1,
    this.restHpRecovery = 10,
    this.roughRestrictedTechniqueLimit = 1,
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

  /// PINカードの共有総数（docs/combat_rules_v1.md 8.1章）。
  /// `playerA.pinCardsHeld + playerB.pinCardsHeld`は常にこの値と等しい
  /// （Phase 5、match-level invariant）。
  final int totalPinCards;

  /// 1カウントでPINが終了した際に防御側が支払うKOC（docs/combat_rules_v1.md
  /// 8.2章）。
  final int pinCountOneKocCost;

  /// 2カウントでPINが終了した際に防御側が支払うKOC（docs/combat_rules_v1.md
  /// 8.2章）。
  final int pinCountTwoKocCost;

  /// 2.9カウントでPINが終了した際に防御側が支払うKOC
  /// （docs/combat_rules_v1.md 8.2章）。
  final int pinCountTwoPointNineKocCost;

  /// 通常SUBMISSIONへ移行できる相手HPの上限（docs/combat_rules_v1.md
  /// 10.1章「相手HP50以下で宣言可能」、Phase 6）。submissionHold=trueの
  /// TECHNIQUEがCOUNTERされず成立し、解決後の相手HPがこの値以下になった
  /// 場合にのみSUBMISSIONへ自動移行する。
  final int submissionHpThreshold;

  /// ESCAPEに必要なKOC（docs/combat_rules_v1.md 10.1章「ESCAPE: KOC1を
  /// 消費」、Phase 6）。防御側がこのKOCを支払えなければGIVE UPとなる。
  final int submissionEscapeKocCost;

  /// RESTによるHP回復量（docs/combat_rules_v1.md 11章「REST: HP+10回復
  /// （最大150を超えない）」、Phase 7）。`maxHp`を超えない範囲で回復する。
  final int restHpRecovery;

  /// ROUGH技によって次ターン制限を受けたプレイヤーが、そのターンに宣言
  /// できるTECHNIQUEの上限枚数（docs/combat_rules_v1.md 15章「相手は次の
  /// 自ターンにTECHNIQUEを最大1枚しか使用できない」、Phase 8）。
  /// COUNTER・REST・起き上がりはこの上限に含めない（宣言＝
  /// `techniquesUsedThisTurn`と同じ「使用」基準でカウントする、Phase
  /// 8セッションでユーザーが確定した方針）。
  final int roughRestrictedTechniqueLimit;

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
