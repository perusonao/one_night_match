import '../wrestler_editor/models.dart';
import 'level_match_engine.dart';

/// Ver.1.0 デッキバランスシミュレーター。
///
/// シミュレーションエンジン（deck_balance_simulator.dart）・集計/レポート
/// （deck_balance_report.dart）・UI（deck_balance_screen.dart）を分離し、
/// レスラー・技が増えても集計項目を追加しやすい構成にする。
/// このファイルは設定値・純粋なデータモデルのみを持つ（ロジックを持たない）。

enum SeedMode { fixed, random }

/// 1回のシミュレーション実行設定。
class DeckSimConfig {
  const DeckSimConfig({
    required this.playerA,
    required this.playerB,
    this.cpuDifficulty = CpuDifficulty.normal,
    this.matches = 1000,
    this.seedMode = SeedMode.random,
    this.fixedSeed = 0,
    this.resourceMode = MatchResourceMode.energy,
    this.signatureOncePerMatch,
    this.basicCardPolicy = BasicCardPolicy.unlimitedReuse,
    this.energySurplusPolicy = EnergySurplusPolicy.none,
    this.startingLevel,
    this.startingHeat,
    this.startingHp,
  });

  final WrestlerDefinition playerA;
  final WrestlerDefinition playerB;
  final CpuDifficulty cpuDifficulty;
  final int matches;
  final SeedMode seedMode;
  final int fixedSeed;
  final MatchResourceMode resourceMode;
  final bool? signatureOncePerMatch;
  final BasicCardPolicy basicCardPolicy;
  final EnergySurplusPolicy energySurplusPolicy;
  final int? startingLevel;
  final int? startingHeat;
  final int? startingHp;

  Map<String, dynamic> toJson() => {
    'playerA': playerA.name,
    'playerB': playerB.name,
    'cpuDifficulty': cpuDifficulty.name,
    'matches': matches,
    'seedMode': seedMode.name,
    'fixedSeed': fixedSeed,
    'resourceMode': resourceMode.name,
    'signatureOncePerMatch': signatureOncePerMatch,
    'basicCardPolicy': basicCardPolicy.name,
    'energySurplusPolicy': energySurplusPolicy.name,
    'startingLevel': startingLevel,
    'startingHeat': startingHeat,
    'startingHp': startingHp,
  };
}

/// 技1つぶんの集計（可変・蓄積用）。実装④「技分析」の元データ。
class MoveAccumulator {
  MoveAccumulator(this.moveId, this.name, this.category, this.attribute);

  final String moveId;
  final String name;
  final MoveCategory category;
  final MoveAttribute attribute;

  int eligibleMatches = 0; // この技を持つ側が登場した試合数
  int matchesUsedAtLeastOnce = 0;
  int totalUses = 0;
  int attemptedCount = 0; // attackDeclared（返される分も含む）
  int landedCount = 0; // moveResolvedとして成立した回数
  int finishCount = 0; // この技で試合が決まった回数
  int totalDamage = 0;
  int totalHeatGain = 0;
  int totalCost = 0;
  int turnSum = 0; // 使用ターンの合計（平均タイミング用）
  int matchTurnsSumWhenUsed = 0; // 使用試合の総ターン数合計（タイミング比率用）
  int winsWhenUsed = 0; // 使用した側が勝利した試合数（延べ、1試合で複数回使っても1）
  int? level;

  double get usageRate => eligibleMatches == 0
      ? 0
      : matchesUsedAtLeastOnce / eligibleMatches;
  double get unusedRate => 1 - usageRate;
  double get avgDamage => totalUses == 0 ? 0 : totalDamage / totalUses;
  double get avgHeatGain => totalUses == 0 ? 0 : totalHeatGain / totalUses;
  double get avgCost => totalUses == 0 ? 0 : totalCost / totalUses;
  double get winRateWhenUsed =>
      matchesUsedAtLeastOnce == 0 ? 0 : winsWhenUsed / matchesUsedAtLeastOnce;
  double get counterRate =>
      attemptedCount == 0 ? 0 : 1 - (landedCount / attemptedCount);
  double get finishRate => totalUses == 0 ? 0 : finishCount / totalUses;
  double get avgTimingRatio => totalUses == 0 || matchTurnsSumWhenUsed == 0
      ? 0
      : (turnSum / totalUses) / (matchTurnsSumWhenUsed / totalUses);

  /// 試合への貢献度: 使用率×平均ダメージ×使用時勝率を0-100へ正規化した目安値。
  double get contributionScore =>
      (usageRate * (avgDamage / 40).clamp(0, 1) * (0.5 + winRateWhenUsed / 2) * 100)
          .clamp(0, 100);

  /// 期待値: この技を持つ側が1試合で平均どれだけダメージを持ち込むか
  /// （使用有無を問わず、対象試合数で正規化）。
  double get expectedValuePerMatch =>
      eligibleMatches == 0 ? 0 : totalDamage / eligibleMatches;

  /// AI評価: _scoreMoveForと同じ形の静的（状況非依存）評価値。
  /// 実プレイ中の動的スコアではなく、技の素の性能を横並び比較するための目安。
  double aiEvaluation(MoveDefinition move) {
    var score = move.power.toDouble() + move.heat;
    if (move.offersPin) score += 8;
    if (move.offersSubmission) score += 8;
    score += move.speed;
    final cost = move.energyModeRequiredCards.values.fold(0, (a, b) => a + b);
    if (cost > 0) score += move.power / cost;
    return score;
  }
}

/// レスラー1体ぶんの集計。実装⑤「レスラー分析」の元データ。
class WrestlerAccumulator {
  WrestlerAccumulator(this.wrestlerId, this.name);

  final String wrestlerId;
  final String name;

  int games = 0;
  int wins = 0;
  int turnSum = 0;
  int levelSum = 0;
  int damageDealtSum = 0;
  int damageTakenSum = 0;
  int pinAttempts = 0;
  int submissionAttempts = 0;
  int koWins = 0;
  int finisherAttempts = 0;
  int finisherLands = 0;
  int finisherWins = 0;
  int basicUses = 0;
  int signatureUses = 0;
  int finisherUses = 0;
  final Map<MoveAttribute, int> attributeDamage = {};
  final Map<MoveAttribute, int> attributeEnergyInvested = {};
  final Map<MoveAttribute, int> attributeEnergyReadyAtEnd = {};
  int entertainmentScoreSum = 0;
  int counterAttempts = 0; // このレスラーが返し技を試みた回数
  int counterSuccesses = 0; // 上記のうちclash outcome=counterで成立した回数
  int counteredAgainstCount = 0; // 相手の返し技で自分の技が返された回数

  double get winRate => games == 0 ? 0 : wins / games;
  double get avgTurns => games == 0 ? 0 : turnSum / games;
  double get avgLevel => games == 0 ? 0 : levelSum / games;
  double get avgDamageDealt => games == 0 ? 0 : damageDealtSum / games;
  double get avgDamageTaken => games == 0 ? 0 : damageTakenSum / games;
  double get pinRate => games == 0 ? 0 : pinAttempts / games;
  double get submissionRate => games == 0 ? 0 : submissionAttempts / games;
  double get koRate => games == 0 ? 0 : koWins / games;
  double get finisherSuccessRate =>
      finisherLands == 0 ? 0 : finisherWins / finisherLands;
  double get basicDependencyRate {
    final total = basicUses + signatureUses + finisherUses;
    return total == 0 ? 0 : basicUses / total;
  }

  double get signatureDependencyRate {
    final total = basicUses + signatureUses + finisherUses;
    return total == 0 ? 0 : signatureUses / total;
  }

  double get avgEntertainmentScore =>
      games == 0 ? 0 : entertainmentScoreSum / games;

  double get counterSuccessRate =>
      counterAttempts == 0 ? 0 : counterSuccesses / counterAttempts;

  /// 相手に返し技で潰された割合（自分の総攻撃試行に対する比率の目安として
  /// 「1試合あたり回数」を返す。全レスラーの平均と比較して外れ値を見る）。
  double get counteredAgainstPerGame =>
      games == 0 ? 0 : counteredAgainstCount / games;

  MoveAttribute? get favoriteAttribute {
    if (attributeDamage.isEmpty) return null;
    return attributeDamage.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }

  MoveAttribute? get weakestAttribute {
    if (attributeDamage.isEmpty) return null;
    return attributeDamage.entries
        .reduce((a, b) => a.value <= b.value ? a : b)
        .key;
  }
}

/// 実装⑦「観戦性スコア」。1試合ぶんの評価結果。
class EntertainmentScore {
  const EntertainmentScore({
    required this.score,
    required this.stars,
    required this.label,
    required this.breakdown,
  });

  final int score; // 0-100
  final int stars; // 1-5
  final String label;
  final Map<String, int> breakdown;

  Map<String, dynamic> toJson() => {
    'score': score,
    'stars': stars,
    'label': label,
    'breakdown': breakdown,
  };
}
