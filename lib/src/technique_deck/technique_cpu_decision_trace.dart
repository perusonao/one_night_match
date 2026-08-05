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

/// 最終的に選ばれた行動。
class TechniqueCpuChosenAction {
  const TechniqueCpuChosenAction({
    required this.action,
    this.cardId,
    this.cardName,
    required this.reason,
  });

  /// 'setEnergy' | 'declareAttack' | 'declareFinisher' | 'rest' | 'endTurn' |
  /// 'endRally' | 'counterAttack' | 'acceptHit' | 'escapeWithCard' |
  /// 'escapeWithHp' | 'concede' | 'cancelFinisher' | 'acceptFinisher' |
  /// 'escapeFinisherWithCard' | 'concedeFinisher'
  final String action;
  final String? cardId;
  final String? cardName;
  final String reason;

  Map<String, dynamic> toJson() => {
    'action': action,
    if (cardId != null) 'cardId': cardId,
    if (cardName != null) 'cardName': cardName,
    'reason': reason,
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
class TechniqueCpuDecisionTrace {
  const TechniqueCpuDecisionTrace({
    required this.turnNumber,
    required this.playerIndex,
    required this.cpuLevel,
    required this.decisionType,
    this.candidates = const [],
    required this.chosen,
    this.rejected = const [],
  });

  final int turnNumber;

  /// 0=A, 1=B。この意思決定を行ったプレイヤー。
  final int playerIndex;

  /// 'normal'（本ラウンドで実装するCPUレベル。将来level1/2/3等が増える
  /// 場合はここに追加する）。
  final String cpuLevel;

  /// 'setEnergy' | 'declareAttack' | 'restOrEndTurn' | 'endRally' |
  /// 'counterAttack' | 'escapeChoice' | 'cancelFinisher' |
  /// 'finisherEscapeChoice'
  final String decisionType;

  final List<TechniqueCpuCandidate> candidates;
  final TechniqueCpuChosenAction chosen;
  final List<TechniqueCpuRejectedCandidate> rejected;

  Map<String, dynamic> toJson() => {
    'turnNumber': turnNumber,
    'playerIndex': playerIndex,
    'cpuLevel': cpuLevel,
    'decisionType': decisionType,
    'candidates': candidates.map((c) => c.toJson()).toList(),
    'chosen': chosen.toJson(),
    'rejected': rejected.map((r) => r.toJson()).toList(),
  };

  @override
  String toString() =>
      'CPU[Turn$turnNumber P$playerIndex $decisionType] → ${chosen.action}'
      '${chosen.cardName != null ? "(${chosen.cardName})" : ""}: ${chosen.reason}';
}
