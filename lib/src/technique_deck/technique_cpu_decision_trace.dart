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
  };

  @override
  String toString() =>
      'CPU[Turn$turnNumber P$playerIndex $decisionType] → ${chosen.action}'
      '${chosen.cardName != null ? "(${chosen.cardName})" : ""}: ${chosen.reason}';
}
