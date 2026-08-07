/// Playtest Analytics Phase A: 自動診断1件分の結果モデル。
///
/// [TechniqueMatchAnalyzer]の出力型。UI・Firestore・ローカル保存のいずれにも
/// 依存しない、純粋なデータクラス。
library;

/// 診断の重大度。[index]の昇順が重大度の昇順（info < warning < error <
/// critical）になるよう並べている。
enum TechniqueMatchAnalysisSeverity {
  info,
  warning,
  error,
  critical;

  static TechniqueMatchAnalysisSeverity fromName(String name) =>
      TechniqueMatchAnalysisSeverity.values.firstWhere(
        (v) => v.name == name,
        orElse: () => TechniqueMatchAnalysisSeverity.info,
      );
}

/// [TechniqueMatchAnalyzer]が検出した1件の診断結果。
class TechniqueMatchAnalysisResult {
  const TechniqueMatchAnalysisResult({
    required this.severity,
    required this.diagnosticCode,
    required this.title,
    required this.description,
    this.turnNumber,
    this.playerId,
    this.relatedCardId,
    this.actualValue,
    this.threshold,
    this.metadata = const {},
  });

  /// INFO / WARNING / ERROR / CRITICAL。
  final TechniqueMatchAnalysisSeverity severity;

  /// 例: `CRITICAL_LEGAL_MOVE_PASS`、`WARNING_DRAW`。診断ルールの機械可読な
  /// 識別子（Analytics画面でのフィルタ・集計にも使う）。
  final String diagnosticCode;

  /// 一覧表示用の短い日本語タイトル。
  final String title;

  /// 詳細画面用の説明文（何が・なぜ異常と判定されたか）。
  final String description;

  /// 診断が特定のターンに紐づく場合のターン番号（試合全体に関する診断は
  /// null）。
  final int? turnNumber;

  /// 診断が特定プレイヤーに紐づく場合の`playerId`（'A'/'B'）。
  final String? playerId;

  /// 診断に関連するカードID（例: CPUが選ぶべきだった最良合法技）。
  final String? relatedCardId;

  /// 実際に観測された値（例: legalMoveCount、countersUsed）。
  final num? actualValue;

  /// 判定に用いた閾値（該当しない診断ではnull）。
  final num? threshold;

  /// 診断ごとの追加情報（例: noLegalMoveReasonCode、candidatesEligible）。
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
    'severity': severity.name,
    'diagnosticCode': diagnosticCode,
    'title': title,
    'description': description,
    if (turnNumber != null) 'turnNumber': turnNumber,
    if (playerId != null) 'playerId': playerId,
    if (relatedCardId != null) 'relatedCardId': relatedCardId,
    if (actualValue != null) 'actualValue': actualValue,
    if (threshold != null) 'threshold': threshold,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  factory TechniqueMatchAnalysisResult.fromJson(Map<String, dynamic> json) =>
      TechniqueMatchAnalysisResult(
        severity: TechniqueMatchAnalysisSeverity.fromName(
          json['severity'] as String? ?? 'info',
        ),
        diagnosticCode: json['diagnosticCode'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        turnNumber: json['turnNumber'] as int?,
        playerId: json['playerId'] as String?,
        relatedCardId: json['relatedCardId'] as String?,
        actualValue: json['actualValue'] as num?,
        threshold: json['threshold'] as num?,
        metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  @override
  String toString() => '[${severity.name.toUpperCase()}] $diagnosticCode: $title';
}

/// 診断結果一覧から導出する集計値（Analytics一覧・保存レコードで使う）。
class TechniqueMatchAnalysisSummary {
  const TechniqueMatchAnalysisSummary({
    required this.overallSeverity,
    required this.criticalCount,
    required this.warningCount,
    required this.errorCount,
    required this.infoCount,
  });

  factory TechniqueMatchAnalysisSummary.fromResults(
    List<TechniqueMatchAnalysisResult> results,
  ) {
    final critical = results
        .where((r) => r.severity == TechniqueMatchAnalysisSeverity.critical)
        .length;
    final error = results
        .where((r) => r.severity == TechniqueMatchAnalysisSeverity.error)
        .length;
    final warning = results
        .where((r) => r.severity == TechniqueMatchAnalysisSeverity.warning)
        .length;
    final info = results
        .where((r) => r.severity == TechniqueMatchAnalysisSeverity.info)
        .length;
    final overall = critical > 0
        ? TechniqueMatchAnalysisSeverity.critical
        : error > 0
        ? TechniqueMatchAnalysisSeverity.error
        : warning > 0
        ? TechniqueMatchAnalysisSeverity.warning
        : TechniqueMatchAnalysisSeverity.info;
    return TechniqueMatchAnalysisSummary(
      overallSeverity: overall,
      criticalCount: critical,
      warningCount: warning,
      errorCount: error,
      infoCount: info,
    );
  }

  final TechniqueMatchAnalysisSeverity overallSeverity;
  final int criticalCount;
  final int warningCount;
  final int errorCount;
  final int infoCount;
}
