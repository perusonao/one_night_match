/// Technique Match CPU（優先度6）の意思決定ログ（Decision Trace）。
///
/// docs/design/technique_deck_cpu_design.md 3章で定義した構造をそのまま
/// 実装したもの。デバッグ・バランス調整専用の機能であり、試合の勝敗判定
/// には一切関与しない（`TechniqueMatchState`本体にも持たせない）。
/// デバッグON時のみUI等で表示する想定（優先度7）。
library;

/// 1候補技の評価内訳（1項目分）。
class TechniqueCpuScoreFactor {
  const TechniqueCpuScoreFactor({required this.label, required this.delta});

  final String label;
  final int delta;

  Map<String, dynamic> toJson() => {'label': label, 'delta': delta};

  @override
  String toString() => '$label(${delta >= 0 ? "+" : ""}$delta)';
}

/// 候補となったカード1枚分の評価。
class TechniqueCpuCandidate {
  const TechniqueCpuCandidate({
    required this.cardId,
    required this.cardName,
    required this.eligible,
    required this.score,
    this.factors = const [],
    this.ineligibleReason,
  });

  final String cardId;
  final String cardName;
  final bool eligible;
  final int score;
  final List<TechniqueCpuScoreFactor> factors;

  /// [eligible] がfalseの場合の理由（`canDeclareAttack`等の`reason`）。
  final String? ineligibleReason;

  Map<String, dynamic> toJson() => {
    'cardId': cardId,
    'cardName': cardName,
    'eligible': eligible,
    'score': score,
    'factors': factors.map((f) => f.toJson()).toList(),
    if (ineligibleReason != null) 'ineligibleReason': ineligibleReason,
  };
}

/// 【次フェーズ Stage7】CPUの意思決定理由を機械可読な形で分類する
/// （既存の自由文`TechniqueCpuChosenAction.reason`は人間が読む説明として
/// そのまま残し、こちらは将来の集計・分析用の追加情報として併記する）。
enum TechniqueCpuDecisionReason {
  /// 使用可能な攻撃技が手札に無い。
  noPlayableAttack,

  /// 返技用エネルギーを温存するため、あえてこの技を選ばなかった／使わない。
  saveEnergy,

  /// 返技可能な候補があり、返技を選んだ。
  counterAvailable,

  /// 複数の返技候補の中から、最も評価の高いものを選んだ。
  counterPreferred,

  /// 返技可能だったが、脅威スコアが閾値未満のため受けを選んだ。
  counterDeclined,

  /// フィニッシャーの発動条件を満たしていない。
  finisherNotReady,

  /// エネルギーをセットした。
  energySet,

  /// 追撃せず攻防（ラリー）を終えた。
  rallyEnded,

  /// 使用可能な技が無いため無言でターンを自動終了した。
  autoPassTurn,

  /// 上記のいずれにも当てはまらない。
  other,
}

/// 【Rule Cleanup STEP7: CPU Action Selection Fix】`_decideRallyAction`が
/// passTurn／endRallyを選んだ際、なぜ合法な技が1つも無かったかを機械可読に
/// 分類する診断情報。**新しい戦略的判断（撤退・温存等）を追加するものでは
/// なく**、`_checkEligibility`が既に返している`ineligibleReason`（自由文）を
/// 事後的に分類するだけの、既存の意思決定ロジックには一切影響しない
/// 付加情報。
enum TechniqueCpuNoLegalMoveReason {
  /// 手札に技カード（フィニッシャー含む）自体が無い。
  noLegalMove,

  /// 候補はあるが、いずれもCombo Speed不足で使用できない。
  insufficientSpeed,

  /// 候補はあるが、いずれも技エネルギー不足で使用できない。
  insufficientEnergy,

  /// 候補はあるが、いずれも相手の`targetState`条件（スタンド／ダウン限定）
  /// を満たさない。
  targetStateMismatch,

  /// 上記のいずれにも当てはまらない（複合的な理由、レベル不足、使用可能
  /// レスラー制限、フィニッシャー発動条件未達等）。
  other,
}

/// 最終的に選ばれた行動。
class TechniqueCpuChosenAction {
  const TechniqueCpuChosenAction({
    required this.action,
    this.cardId,
    this.cardName,
    required this.reason,
    this.reasonCode,
  });

  /// 'setEnergy' | 'declareAttack' | 'declareFinisher' | 'passTurn' |
  /// 'endRally' | 'counterAttack' | 'acceptHit' | 'escapeWithCard' |
  /// 'escapeWithHp' | 'concede' | 'cancelFinisher' | 'acceptFinisher' |
  /// 'escapeFinisherWithCard' | 'concedeFinisher'
  final String action;
  final String? cardId;
  final String? cardName;
  final String reason;

  /// 【次フェーズ Stage7】[reason]（自由文）を機械可読に分類したもの。
  /// 追加のみのnullableフィールドのため、未設定の既存呼び出し箇所には
  /// 一切影響しない。
  final TechniqueCpuDecisionReason? reasonCode;

  Map<String, dynamic> toJson() => {
    'action': action,
    if (cardId != null) 'cardId': cardId,
    if (cardName != null) 'cardName': cardName,
    'reason': reason,
    if (reasonCode != null) 'reasonCode': reasonCode!.name,
  };
}

/// 採用されなかった候補とその理由。
class TechniqueCpuRejectedCandidate {
  const TechniqueCpuRejectedCandidate({required this.cardId, required this.reason});

  final String cardId;
  final String reason;

  Map<String, dynamic> toJson() => {'cardId': cardId, 'reason': reason};
}

/// CPUの1意思決定ポイント分の思考ログ。
///
/// 【Phase 8.5A-2】CPU攻撃停止バグ（合法技があるのにpassTurnし続ける）の
/// 調査で、既存の`candidates`/`chosen`だけでは「その時点でラリー・
/// ComboSpeed・手札・エネルギーがどんな状態だったか」を後から追えず
/// 原因特定に手間取ったため、`_decideRallyAction`（技を使う／ラリーを
/// 終える／ターンを自動終了する、の意思決定点）に限定して診断用の
/// スナップショットフィールドを追加した（最低限の項目のみ。既存フィールド
/// と重複するturn/playerIndex/decisionType/chosenは流用する）。
class TechniqueCpuDecisionTrace {
  const TechniqueCpuDecisionTrace({
    required this.turnNumber,
    required this.playerIndex,
    required this.cpuLevel,
    required this.decisionType,
    this.candidates = const [],
    required this.chosen,
    this.rejected = const [],
    this.rallyAttackerIndex,
    this.remainingSpeed,
    this.comboSpeed,
    this.handCardIds,
    this.energyPool,
    this.legalMoveCount,
    this.bestEligibleCardId,
    this.bestEligibleCardName,
    this.bestEligibleScore,
    this.noLegalMoveReasonCode,
  });

  final int turnNumber;

  /// 0=A, 1=B。この意思決定を行ったプレイヤー。
  final int playerIndex;

  /// 'normal'（本ラウンドで実装するCPUレベル。将来level1/2/3等が増える
  /// 場合はここに追加する）。
  final String cpuLevel;

  /// 'setEnergy' | 'declareAttack' | 'declareFinisher' | 'passTurn' |
  /// 'endRally' | 'counterAttack' | 'escapeChoice' | 'cancelFinisher' |
  /// 'finisherEscapeChoice'
  final String decisionType;

  final List<TechniqueCpuCandidate> candidates;
  final TechniqueCpuChosenAction chosen;
  final List<TechniqueCpuRejectedCandidate> rejected;

  /// `_decideRallyAction`診断用スナップショット（Phase 8.5A-2）。
  /// この意思決定点以外（setEnergy・counterAttack等）ではnullのまま。
  final int? rallyAttackerIndex;
  final int? remainingSpeed;
  final int? comboSpeed;
  final List<String>? handCardIds;
  final Map<String, int>? energyPool;

  /// 【Rule Cleanup STEP7】`candidates`のうち`eligible == true`だった件数
  /// （`_decideRallyAction`のみ設定。他の意思決定点ではnull）。
  /// `passTurn`／`endRally`の場合はこれが`0`であることが不変条件
  /// （`legalMoveCount > 0`のままpassTurn／endRallyを選ぶのは異常）。
  final int? legalMoveCount;

  /// 候補の中で最もスコアが高かった合法技（`eligible == true`）のID／名前／
  /// スコア。合法技が無ければ全てnull。`declareAttack`／`declareFinisher`
  /// の場合は`chosen`と同じ値になる（冗長だが解析の一貫性のため）。
  final String? bestEligibleCardId;
  final String? bestEligibleCardName;
  final int? bestEligibleScore;

  /// `legalMoveCount == 0`だった場合の理由分類
  /// （[TechniqueCpuNoLegalMoveReason].name）。合法技が1つでもあればnull。
  final String? noLegalMoveReasonCode;

  Map<String, dynamic> toJson() => {
    'turnNumber': turnNumber,
    'playerIndex': playerIndex,
    'cpuLevel': cpuLevel,
    'decisionType': decisionType,
    'candidates': candidates.map((c) => c.toJson()).toList(),
    'chosen': chosen.toJson(),
    'rejected': rejected.map((r) => r.toJson()).toList(),
    if (rallyAttackerIndex != null) 'rallyAttackerIndex': rallyAttackerIndex,
    if (remainingSpeed != null) 'remainingSpeed': remainingSpeed,
    if (comboSpeed != null) 'comboSpeed': comboSpeed,
    if (handCardIds != null) 'handCardIds': handCardIds,
    if (energyPool != null) 'energyPool': energyPool,
    if (legalMoveCount != null) 'legalMoveCount': legalMoveCount,
    if (bestEligibleCardId != null) 'bestEligibleCardId': bestEligibleCardId,
    if (bestEligibleCardName != null) 'bestEligibleCardName': bestEligibleCardName,
    if (bestEligibleScore != null) 'bestEligibleScore': bestEligibleScore,
    if (noLegalMoveReasonCode != null) 'noLegalMoveReasonCode': noLegalMoveReasonCode,
  };

  @override
  String toString() =>
      'CPU[Turn$turnNumber P$playerIndex $decisionType] → ${chosen.action}'
      '${chosen.cardName != null ? "(${chosen.cardName})" : ""}: ${chosen.reason}';
}
