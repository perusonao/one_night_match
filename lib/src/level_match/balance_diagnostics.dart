import '../wrestler_editor/models.dart';
import 'deck_balance_models.dart';
import 'deck_balance_report.dart';

/// Ver.1.1: バランス調整フェーズの目標値。既定値は運営が指定した
/// 目標レンジ（勝率45〜55%、主力技40〜70%、切り札10〜30%、未使用率90%
/// 以上は要改善、観戦評価70点以上）に対応する。
class BalanceThresholds {
  const BalanceThresholds({
    this.winRateLow = 0.45,
    this.winRateHigh = 0.55,
    this.basicUsageLow = 0.40,
    this.basicUsageHigh = 0.70,
    this.signatureUsageLow = 0.10,
    this.signatureUsageHigh = 0.30,
    this.unusedRateCritical = 0.90,
    this.entertainmentTarget = 70,
  });

  final double winRateLow;
  final double winRateHigh;
  final double basicUsageLow;
  final double basicUsageHigh;
  final double signatureUsageLow;
  final double signatureUsageHigh;
  final double unusedRateCritical;
  final double entertainmentTarget;
}

class WrestlerDiagnosis {
  const WrestlerDiagnosis({
    required this.wrestlerId,
    required this.name,
    required this.winRate,
    required this.avgEntertainmentScore,
    required this.status,
    required this.findings,
  });
  final String wrestlerId;
  final String name;
  final double winRate;
  final double avgEntertainmentScore;
  final String status; // strong / weak / ok
  final List<AiFinding> findings;
}

class MoveDiagnosis {
  const MoveDiagnosis({
    required this.moveId,
    required this.name,
    required this.usageRate,
    required this.role,
    required this.status,
  });
  final String moveId;
  final String name;
  final double usageRate;
  final String role; // 主力技 / 切り札
  final String status; // overused / underused / ok
}

class BalanceDiagnosis {
  const BalanceDiagnosis({
    required this.wrestlers,
    required this.moves,
    required this.overallFindings,
  });
  final List<WrestlerDiagnosis> wrestlers;
  final List<MoveDiagnosis> moves;
  final List<AiFinding> overallFindings;

  List<WrestlerDiagnosis> get strongWrestlers =>
      wrestlers.where((w) => w.status == 'strong').toList();
  List<WrestlerDiagnosis> get weakWrestlers =>
      wrestlers.where((w) => w.status == 'weak').toList();
  List<MoveDiagnosis> get overusedMoves =>
      moves.where((m) => m.status == 'overused').toList();
  List<MoveDiagnosis> get underusedMoves =>
      moves.where((m) => m.status == 'underused').toList();

  Map<String, dynamic> toJson() => {
    'wrestlers': [
      for (final w in wrestlers)
        {
          'wrestlerId': w.wrestlerId,
          'name': w.name,
          'winRate': w.winRate,
          'avgEntertainmentScore': w.avgEntertainmentScore,
          'status': w.status,
          'findings': w.findings.map((f) => f.toJson()).toList(),
        },
    ],
    'moves': [
      for (final m in moves)
        {
          'moveId': m.moveId,
          'name': m.name,
          'usageRate': m.usageRate,
          'role': m.role,
          'status': m.status,
        },
    ],
    'overallFindings': overallFindings.map((f) => f.toJson()).toList(),
  };
}

/// 実装1・2（バランス診断＋原因分析）。マージ済みDeckBalanceReportと
/// 静的なレスラー/技定義を突き合わせ、目標レンジ超過のレスラー・技を検出し、
/// それぞれについて「なぜそうなっているか」の原因分析を添える。
BalanceDiagnosis diagnoseBalance({
  required DeckBalanceReport report,
  required Map<String, WrestlerDefinition> wrestlersById,
  required Map<String, MoveDefinition> moves,
  BalanceThresholds thresholds = const BalanceThresholds(),
}) {
  // ロースター平均（外れ値判定の基準として使う）。
  final cannotCounterCounts = <String, int>{};
  for (final entry in wrestlersById.entries) {
    var count = 0;
    for (final lv in entry.value.levels) {
      for (final id in [...lv.moveIds, if (lv.finisherId != null) lv.finisherId!]) {
        final m = moves[id];
        if (m != null && m.specialAbilities.contains('cannotCounter')) count++;
      }
    }
    cannotCounterCounts[entry.key] = count;
  }
  final avgCannotCounter = cannotCounterCounts.isEmpty
      ? 0
      : cannotCounterCounts.values.reduce((a, b) => a + b) /
          cannotCounterCounts.length;

  final avgCounteredAgainst = report.wrestlerStats.values.isEmpty
      ? 0.0
      : report.wrestlerStats.values
              .map((w) => w.counteredAgainstPerGame)
              .reduce((a, b) => a + b) /
          report.wrestlerStats.length;

  final wrestlerDiagnoses = <WrestlerDiagnosis>[];
  for (final entry in report.wrestlerStats.entries) {
    final w = entry.value;
    if (w.games == 0) continue;
    final findings = <AiFinding>[];
    final String status;
    if (w.winRate >= thresholds.winRateHigh) {
      status = 'strong';
    } else if (w.winRate < thresholds.winRateLow) {
      status = 'weak';
    } else {
      status = 'ok';
    }

    final cannotCounter = cannotCounterCounts[entry.key] ?? 0;
    if (status == 'strong' && cannotCounter > avgCannotCounter) {
      findings.add(AiFinding(
        subject: w.name,
        observation:
            'cannotCounter技を$cannotCounter個保有（ロースター平均${avgCannotCounter.toStringAsFixed(1)}個）し、'
            '相手からの被カウンター回数は1試合あたり${w.counteredAgainstPerGame.toStringAsFixed(2)}回'
            '（平均${avgCounteredAgainst.toStringAsFixed(2)}回）。',
        suggestion: 'cannotCounterを保有技の一部から外し、相手が返し技で対抗できる技を残すことを検討してください。',
        severity: 'critical',
      ));
    }
    if (w.counterSuccessRate > 0 && w.counteredAgainstPerGame < avgCounteredAgainst * 0.5) {
      findings.add(AiFinding(
        subject: w.name,
        observation:
            '自分の返し技成功率${(w.counterSuccessRate * 100).toStringAsFixed(0)}%に対し、'
            '相手に返される回数はロースター平均の半分以下。',
        suggestion: '「返せるが返されない」非対称性が勝率に寄与している可能性があります。',
        severity: 'warn',
      ));
    }
    if (status == 'weak' && w.finisherLands > 0 && w.finisherSuccessRate < 0.15) {
      findings.add(AiFinding(
        subject: w.name,
        observation: 'フィニッシャー成功率${(w.finisherSuccessRate * 100).toStringAsFixed(0)}%と低く、'
            '決定機を活かせていません。',
        suggestion: 'フィニッシャーのpinPower/submissionPowerを+5〜+10、またはキックアウトコストを重くしてください。',
        severity: 'warn',
      ));
    }
    if (status == 'weak' && w.basicDependencyRate >= 0.6) {
      findings.add(AiFinding(
        subject: w.name,
        observation: '通常技依存率${(w.basicDependencyRate * 100).toStringAsFixed(0)}%と高く、'
            '固有技を活かせないまま試合が進んでいます。',
        suggestion: '固有技のダメージ以外の価値（HEAT増加量、次ターン有利、追加効果）を高めることを検討してください。',
        severity: 'warn',
      ));
    }
    findings.add(AiFinding(
      subject: w.name,
      observation:
          '平均レベル到達${w.avgLevel.toStringAsFixed(2)} / エネルギー余剰率'
          '${(_wrestlerEnergySurplusRate(w) * 100).toStringAsFixed(0)}%。',
      suggestion: w.avgLevel < 2.5 ? 'レベル到達条件が厳しすぎないか確認してください。' : '',
      severity: 'info',
    ));

    wrestlerDiagnoses.add(WrestlerDiagnosis(
      wrestlerId: entry.key,
      name: w.name,
      winRate: w.winRate,
      avgEntertainmentScore: w.avgEntertainmentScore,
      status: status,
      findings: findings,
    ));
  }

  final moveDiagnoses = <MoveDiagnosis>[];
  for (final entry in report.moveStats.entries) {
    final m = entry.value;
    if (m.eligibleMatches == 0) continue;
    final role = m.category == MoveCategory.basic ? '主力技' : '切り札';
    final String status;
    if (m.unusedRate >= thresholds.unusedRateCritical) {
      status = 'underused';
    } else if (role == '主力技') {
      status = m.usageRate > thresholds.basicUsageHigh
          ? 'overused'
          : (m.usageRate < thresholds.basicUsageLow ? 'underused' : 'ok');
    } else {
      status = m.usageRate > thresholds.signatureUsageHigh
          ? 'overused'
          : (m.usageRate < thresholds.signatureUsageLow ? 'underused' : 'ok');
    }
    moveDiagnoses.add(MoveDiagnosis(
      moveId: entry.key,
      name: m.name,
      usageRate: m.usageRate,
      role: role,
      status: status,
    ));
  }

  final overall = <AiFinding>[];
  if (report.counterSuccessRate >= 0.95) {
    overall.add(AiFinding(
      subject: '全体ルール',
      observation:
          'カウンター成功率が${(report.counterSuccessRate * 100).toStringAsFixed(0)}%。'
          '対応フェーズでは攻撃側の技属性が事前に見えるため、返し技を選んだ時点でほぼ確実に成立する。',
      suggestion: '返し技に成功率（例: 70〜90%）を導入する、または属性を伏せた状態で選択させるなど、'
          '「読み合い」の要素を加えることを検討してください。',
      severity: 'warn',
    ));
  }
  return BalanceDiagnosis(
    wrestlers: wrestlerDiagnoses,
    moves: moveDiagnoses,
    overallFindings: overall,
  );
}

double _wrestlerEnergySurplusRate(WrestlerAccumulator w) {
  final invested = w.attributeEnergyInvested.values.fold<int>(0, (a, b) => a + b);
  final ready = w.attributeEnergyReadyAtEnd.values.fold<int>(0, (a, b) => a + b);
  return invested == 0 ? 0 : ready / invested;
}
