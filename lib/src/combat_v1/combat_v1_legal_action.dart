/// CPU / Legal Action基盤の最小データモデル（Phase 11B、
/// docs/design/combat_v1_phase11b_cpu.md）。
///
/// [CombatV1MatchState]から「今この瞬間に合法な1手」を表現するための、
/// Engine非依存のimmutable value object群。[CombatV1LegalActionEnumerator]が
/// 生成し、[CombatV1DecisionPolicy]が選択し、[CombatV1ActionExecutor]が
/// `CombatV1Engine`のCommandへ変換する（責務はこのファイルへ混ぜない——
/// このファイル自身はlegality判定もEngine呼び出しも一切行わない）。
///
/// [CombatV1MatchState]/Catalog/Rules/Randomはいずれも保持しない。Actionは
/// 「宣言時点の意図」のみを表す軽量な値であり、古いstateから生成した
/// Actionを新しいstateへ適用した場合の扱いは[CombatV1ActionExecutor]の責務
/// （stale action検出）とする。
library;

/// [CombatV1LegalAction]の8 variantを表す安定したkind（Phase 11B
/// addendum「Action Identity」）。
///
/// Phase 12・[CombatV1ActionObserver]等が`is`/`switch`によるsealed
/// pattern matchingへ依存せず、構造的にAction種別を識別できるようにする
/// ための公開identity。値そのものに意味的な優先順位はない
/// （優先順位は[CombatV1FirstLegalPolicy]側で別途定義する）。
enum CombatV1LegalActionKind {
  discard,
  technique,
  counter,
  declineCounter,
  pin,
  rest,
  standUp,
  endTurn,
}

/// 1件の合法手（Phase 11B）。sealedにより、[CombatV1ActionExecutor]の
/// dispatchが8 variant全てを網羅していることをコンパイル時に強制する。
///
/// directPin/submit/giveUp/escape/finisher resolutionはvariantとして
/// 追加しない——これらはEngine内部で自動的に解決される（`declineCounter`の
/// 内部処理、docs/combat_rules_v1.md 8・10・13章）ため、外部から選択可能な
/// 「手」として存在しない。
sealed class CombatV1LegalAction {
  const CombatV1LegalAction({required this.actorPlayerIndex});

  /// このActionを実行する主体のplayerIndex（0=playerA、1=playerB）。
  ///
  /// `state.activePlayerIndex`をそのまま使い回さないこと——
  /// `counterResponsePending`中は`activePlayerIndex`が攻撃側のまま変化
  /// しないため、COUNTER/declineCounterのactorPlayerIndexは防御側
  /// （`1 - activePlayerIndex`）になる（[CombatV1LegalActionEnumerator]
  /// 参照）。
  final int actorPlayerIndex;

  /// このActionの[CombatV1LegalActionKind]（Phase 11B addendum「Action
  /// Identity」）。
  CombatV1LegalActionKind get kind;

  /// カードを使うAction（discard/technique/counter）のみ物理instanceId
  /// （`CombatV1DeckEntry.instanceId`）を返す。それ以外は`null`。
  /// TechniqueやCounterのcardId（カード定義identity）はここでは保持しない
  /// ——Catalogから`cardInstanceId`経由で導出可能なため重複保持しない。
  String? get cardInstanceId => null;
}

/// 手札から指定の物理カードを1枚捨てる（`phase == discard`専用）。
final class CombatV1DiscardAction extends CombatV1LegalAction {
  const CombatV1DiscardAction({
    required super.actorPlayerIndex,
    required this.cardInstanceId,
  });

  /// 捨てる物理カードのinstanceId（`CombatV1DeckEntry.instanceId`）。
  /// cardId（カード定義identity）ではなく、同名カードを区別できる物理
  /// instanceを常に指定する。
  @override
  final String cardInstanceId;

  @override
  CombatV1LegalActionKind get kind => CombatV1LegalActionKind.discard;

  @override
  bool operator ==(Object other) =>
      other is CombatV1DiscardAction &&
      other.actorPlayerIndex == actorPlayerIndex &&
      other.cardInstanceId == cardInstanceId;

  @override
  int get hashCode => Object.hash(
    CombatV1DiscardAction,
    actorPlayerIndex,
    cardInstanceId,
  );

  @override
  String toString() =>
      'CombatV1DiscardAction(actor:$actorPlayerIndex, card:$cardInstanceId)';
}

/// TECHNIQUEを宣言する（`phase == action`、STAND状態専用）。
final class CombatV1TechniqueAction extends CombatV1LegalAction {
  const CombatV1TechniqueAction({
    required super.actorPlayerIndex,
    required this.cardInstanceId,
  });

  @override
  final String cardInstanceId;

  @override
  CombatV1LegalActionKind get kind => CombatV1LegalActionKind.technique;

  @override
  bool operator ==(Object other) =>
      other is CombatV1TechniqueAction &&
      other.actorPlayerIndex == actorPlayerIndex &&
      other.cardInstanceId == cardInstanceId;

  @override
  int get hashCode => Object.hash(
    CombatV1TechniqueAction,
    actorPlayerIndex,
    cardInstanceId,
  );

  @override
  String toString() =>
      'CombatV1TechniqueAction(actor:$actorPlayerIndex, card:$cardInstanceId)';
}

/// COUNTERで応答する（`phase == counterResponsePending`専用）。actorは常に
/// 防御側。
final class CombatV1CounterAction extends CombatV1LegalAction {
  const CombatV1CounterAction({
    required super.actorPlayerIndex,
    required this.cardInstanceId,
  });

  @override
  final String cardInstanceId;

  @override
  CombatV1LegalActionKind get kind => CombatV1LegalActionKind.counter;

  @override
  bool operator ==(Object other) =>
      other is CombatV1CounterAction &&
      other.actorPlayerIndex == actorPlayerIndex &&
      other.cardInstanceId == cardInstanceId;

  @override
  int get hashCode => Object.hash(
    CombatV1CounterAction,
    actorPlayerIndex,
    cardInstanceId,
  );

  @override
  String toString() =>
      'CombatV1CounterAction(actor:$actorPlayerIndex, card:$cardInstanceId)';
}

/// COUNTERせず攻撃を成立させる（`phase == counterResponsePending`専用）。
/// actorは常に防御側。カードを使わないためcardInstanceIdを持たない。
final class CombatV1DeclineCounterAction extends CombatV1LegalAction {
  const CombatV1DeclineCounterAction({required super.actorPlayerIndex});

  @override
  CombatV1LegalActionKind get kind => CombatV1LegalActionKind.declineCounter;

  @override
  bool operator ==(Object other) =>
      other is CombatV1DeclineCounterAction &&
      other.actorPlayerIndex == actorPlayerIndex;

  @override
  int get hashCode => Object.hash(CombatV1DeclineCounterAction, actorPlayerIndex);

  @override
  String toString() => 'CombatV1DeclineCounterAction(actor:$actorPlayerIndex)';
}

/// 通常PINを宣言する（`phase == action`専用）。DIRECT PINはEngine内部の
/// 自動処理のため、このvariantでは表現しない。
final class CombatV1PinAction extends CombatV1LegalAction {
  const CombatV1PinAction({required super.actorPlayerIndex});

  @override
  CombatV1LegalActionKind get kind => CombatV1LegalActionKind.pin;

  @override
  bool operator ==(Object other) =>
      other is CombatV1PinAction && other.actorPlayerIndex == actorPlayerIndex;

  @override
  int get hashCode => Object.hash(CombatV1PinAction, actorPlayerIndex);

  @override
  String toString() => 'CombatV1PinAction(actor:$actorPlayerIndex)';
}

/// RESTする（`phase == action`、DOWN状態専用）。
final class CombatV1RestAction extends CombatV1LegalAction {
  const CombatV1RestAction({required super.actorPlayerIndex});

  @override
  CombatV1LegalActionKind get kind => CombatV1LegalActionKind.rest;

  @override
  bool operator ==(Object other) =>
      other is CombatV1RestAction && other.actorPlayerIndex == actorPlayerIndex;

  @override
  int get hashCode => Object.hash(CombatV1RestAction, actorPlayerIndex);

  @override
  String toString() => 'CombatV1RestAction(actor:$actorPlayerIndex)';
}

/// DOWN状態から起き上がる（`phase == action`、DOWN状態専用）。
final class CombatV1StandUpAction extends CombatV1LegalAction {
  const CombatV1StandUpAction({required super.actorPlayerIndex});

  @override
  CombatV1LegalActionKind get kind => CombatV1LegalActionKind.standUp;

  @override
  bool operator ==(Object other) =>
      other is CombatV1StandUpAction && other.actorPlayerIndex == actorPlayerIndex;

  @override
  int get hashCode => Object.hash(CombatV1StandUpAction, actorPlayerIndex);

  @override
  String toString() => 'CombatV1StandUpAction(actor:$actorPlayerIndex)';
}

/// ターンを終了する（`phase == action`、STAND状態専用）。
final class CombatV1EndTurnAction extends CombatV1LegalAction {
  const CombatV1EndTurnAction({required super.actorPlayerIndex});

  @override
  CombatV1LegalActionKind get kind => CombatV1LegalActionKind.endTurn;

  @override
  bool operator ==(Object other) =>
      other is CombatV1EndTurnAction && other.actorPlayerIndex == actorPlayerIndex;

  @override
  int get hashCode => Object.hash(CombatV1EndTurnAction, actorPlayerIndex);

  @override
  String toString() => 'CombatV1EndTurnAction(actor:$actorPlayerIndex)';
}
