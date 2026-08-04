import 'dart:convert';
import 'dart:math';

import '../wrestler_editor/models.dart';
import 'deck_balance_models.dart';
import 'level_match_engine.dart';

/// AIレポート（実装⑥）の1件の指摘。ルールベースの静的分析
/// （事前に定義した閾値ロジック）であり、LLM呼び出しではない
/// ——シミュレーション自体の再現性・オフライン実行性を優先した設計。
class AiFinding {
  const AiFinding({
    required this.subject,
    required this.observation,
    required this.suggestion,
    this.severity = 'info',
  });
  final String subject; // 対象（レスラー名 or 技名 or 全体）
  final String observation; // 観察された事実
  final String suggestion; // 具体的な改善案
  final String severity; // info / warn / critical

  Map<String, dynamic> toJson() => {
    'subject': subject,
    'observation': observation,
    'suggestion': suggestion,
    'severity': severity,
  };
}

/// Ver.1.0: デッキバランスシミュレーターの集計結果本体。
/// 1回のDeckSimConfig実行から生まれるすべての統計・技分析・レスラー分析・
/// AIレポート・観戦性スコアをここに集約する。エンジン（deck_balance_
/// simulator.dart）とUI（deck_balance_screen.dart）の間に立つ純粋な
/// 集計レイヤーであり、両者から独立してテスト・拡張できる。
class DeckBalanceReport {
  DeckBalanceReport(this.config);

  final DeckSimConfig config;

  int matches = 0;
  int draws = 0;
  int aWins = 0;
  int bWins = 0;
  final List<int> turnsList = [];
  final Map<String, int> finishReasonCounts = {};
  int pinTotal = 0;
  int subTotal = 0;
  int noUsableMoveTotal = 0;
  int leadChangesTotal = 0;
  int matchesWithComeback = 0;
  int counterAttempts = 0;
  int counterSuccesses = 0;
  final Map<MoveAttribute, int> energyInvestedTotals = {};
  final Map<MoveAttribute, int> energyReadyAtEndTotals = {};
  int finisherAttemptedSides = 0;
  int finisherLandedSides = 0;
  int finisherWonSides = 0;
  int sidesTotal = 0;
  int heatSumEnd = 0;
  int distinctMovesSidesSum = 0;
  final List<int> entertainmentScores = [];

  final Map<String, MoveAccumulator> moveStats = {};
  final Map<String, WrestlerAccumulator> wrestlerStats = {};

  bool _eligibilityRegistered = false;

  MoveAccumulator _moveStat(String id, MoveDefinition move) =>
      moveStats.putIfAbsent(
        id,
        () => MoveAccumulator(id, move.name, move.category, move.attribute),
      );

  WrestlerAccumulator _wrestlerStat(WrestlerDefinition w) =>
      wrestlerStats.putIfAbsent(w.id, () => WrestlerAccumulator(w.id, w.name));

  void _registerEligibility(Map<String, MoveDefinition> moves) {
    if (_eligibilityRegistered) return;
    _eligibilityRegistered = true;
    for (final w in [config.playerA, config.playerB]) {
      final ids = <String>{};
      for (final lv in w.levels) {
        ids.addAll(lv.moveIds);
        if (lv.finisherId != null) ids.add(lv.finisherId!);
        if (lv.counterMoveId != null) ids.add(lv.counterMoveId!);
      }
      ids.addAll(w.basicMoveIds.values);
      // 固有の通常技を持たない属性は、共通通常技(basic_*)がフォールバック
      // で使われるためそちらも対象に含める。
      for (final attr in MoveAttribute.values) {
        if (!w.basicMoveIds.containsKey(attr)) {
          for (final m in moves.values) {
            if (m.category == MoveCategory.basic &&
                m.attribute == attr &&
                m.id.startsWith('basic_')) {
              ids.add(m.id);
              break;
            }
          }
        }
      }
      for (final id in ids) {
        final move = moves[id];
        if (move == null) continue;
        final stat = _moveStat(id, move);
        stat.eligibleMatches = config.matches;
        for (final lv in w.levels) {
          if (lv.moveIds.contains(id) ||
              lv.finisherId == id ||
              lv.counterMoveId == id) {
            stat.level ??= lv.level;
            break;
          }
        }
      }
    }
  }

  /// 1試合ぶんのログを読み切り、全アキュムレータへ反映する。
  void addMatch(
    LevelMatchState st,
    Map<String, MoveDefinition> moves, {
    required int seed,
  }) {
    _registerEligibility(moves);
    matches++;
    final reason = st.finishReason?.name ?? 'unfinished';
    finishReasonCounts[reason] = (finishReasonCounts[reason] ?? 0) + 1;
    turnsList.add(st.turnNumber);
    pinTotal += st.pinAttemptCount;
    subTotal += st.submissionAttemptCount;

    // playerA/Bどちらが'player'/'cpu'側だったかを解決する。
    final aIsPlayer = st.player.wrestler.id == config.playerA.id;
    final aState = aIsPlayer ? st.player : st.cpu;
    if (st.winnerId == null) {
      draws++;
    } else {
      final winnerIsA = st.byId(st.winnerId!).wrestler.id == config.playerA.id;
      if (winnerIsA) {
        aWins++;
      } else {
        bWins++;
      }
    }

    final aStat = _wrestlerStat(config.playerA);
    final bStat = _wrestlerStat(config.playerB);
    aStat.games++;
    bStat.games++;
    aStat.turnSum += st.turnNumber;
    bStat.turnSum += st.turnNumber;
    if (st.winnerId != null &&
        st.byId(st.winnerId!).wrestler.id == config.playerA.id) {
      aStat.wins++;
    } else if (st.winnerId != null) {
      bStat.wins++;
    }
    if (reason == 'koStoppage') {
      final loser = aState.currentHp <= 0 ? aStat : bStat;
      // KOで負けた側=相手が勝者。koWinsは「勝った側」に計上。
      (loser == aStat ? bStat : aStat).koWins++;
    }
    aStat.pinAttempts += st.pinAttemptCount;
    bStat.pinAttempts += st.pinAttemptCount;
    aStat.submissionAttempts += st.submissionAttemptCount;
    bStat.submissionAttempts += st.submissionAttemptCount;

    // ---- ログ走査（1パス） ----
    final maxLevel = {'player': 1, 'cpu': 1};
    final hp = {'player': st.player.wrestler.maxHp, 'cpu': st.cpu.wrestler.maxHp};
    var lead = 0;
    var leadChanges = 0;
    final distinctMoves = {'player': <String>{}, 'cpu': <String>{}};
    final finisherAttempted = {'player': false, 'cpu': false};
    final finisherLanded = {'player': false, 'cpu': false};
    var counterCountThisMatch = 0;
    var levelChangeCount = 0;
    var lateGameMoveCount = 0;
    final totalTurns = st.turnNumber == 0 ? 1 : st.turnNumber;

    for (final log in st.logs) {
      switch (log.action) {
        case 'noUsableMove':
          noUsableMoveTotal++;
          break;
        case 'changeLevel':
          levelChangeCount++;
          final after = (log.details['levelAfter'] as num?)?.toInt();
          if (after != null) {
            maxLevel[log.playerId] = max(maxLevel[log.playerId] ?? 1, after);
          }
          break;
        case 'attackDeclared':
          {
            final moveId = log.details['moveId'] as String?;
            final move = moveId == null ? null : moves[moveId];
            if (move != null) {
              _moveStat(moveId!, move).attemptedCount++;
              if (move.category == MoveCategory.finisher) {
                finisherAttempted[log.playerId] = true;
                finisherAttemptedSides++;
              }
            }
            break;
          }
        case 'clashResolution':
          {
            final responseMoveId = log.details['responseMove'] as String?;
            final outcome = log.details['outcome'] as String?;
            final responseMove =
                responseMoveId == null ? null : moves[responseMoveId];
            final responderSide = log.playerId; // _logで responder を渡している
            final responderWrestler = responderSide == (aIsPlayer ? 'player' : 'cpu')
                ? config.playerA
                : config.playerB;
            final responderStat =
                responderWrestler.id == config.playerA.id ? aStat : bStat;
            final attackerStat = responderStat == aStat ? bStat : aStat;
            if (responseMove != null && responseMove.isCounterMove) {
              counterAttempts++;
              responderStat.counterAttempts++;
              if (outcome == 'counter') {
                counterSuccesses++;
                counterCountThisMatch++;
                responderStat.counterSuccesses++;
                attackerStat.counteredAgainstCount++;
              }
            }
            break;
          }
        case 'moveResolved':
          {
            final side = log.playerId;
            final moveId = log.details['selectedMove'] as String?;
            final damage = (log.details['finalDamage'] as num?)?.toInt() ?? 0;
            final heatDelta = (log.details['heatDelta'] as num?)?.toInt() ?? 0;
            final move = moveId == null ? null : moves[moveId];
            if (move != null && moveId != null) {
              distinctMoves[side]?.add(moveId);
              final stat = _moveStat(moveId, move);
              stat.totalUses++;
              stat.landedCount++;
              stat.totalDamage += damage;
              stat.totalHeatGain += heatDelta;
              stat.turnSum += log.turn;
              stat.matchTurnsSumWhenUsed += totalTurns;
              final cost = move.energyModeRequiredCards.values.fold(
                0,
                (a, b) => a + b,
              );
              stat.totalCost += cost;
              final wrestler = side == (aIsPlayer ? 'player' : 'cpu')
                  ? config.playerA
                  : config.playerB;
              switch (move.category) {
                case MoveCategory.basic:
                  (wrestler.id == config.playerA.id ? aStat : bStat)
                      .basicUses++;
                  break;
                case MoveCategory.normal:
                  (wrestler.id == config.playerA.id ? aStat : bStat)
                      .signatureUses++;
                  break;
                case MoveCategory.finisher:
                  (wrestler.id == config.playerA.id ? aStat : bStat)
                      .finisherUses++;
                  finisherLanded[side] = true;
                  finisherLandedSides++;
                  break;
                case MoveCategory.counter:
                  break;
              }
              final ws = wrestler.id == config.playerA.id ? aStat : bStat;
              ws.attributeDamage[move.attribute] =
                  (ws.attributeDamage[move.attribute] ?? 0) + damage;
              ws.damageDealtSum += damage;
              final defenderSide = side == 'player' ? 'cpu' : 'player';
              final defenderWrestler = defenderSide == (aIsPlayer ? 'player' : 'cpu')
                  ? config.playerA
                  : config.playerB;
              (defenderWrestler.id == config.playerA.id ? aStat : bStat)
                  .damageTakenSum += damage;
              if (log.turn / totalTurns >= 0.7) lateGameMoveCount++;
            }
            final defenderSide = side == 'player' ? 'cpu' : 'player';
            final targetHpAfter = (log.details['targetHpAfter'] as num?)?.toInt();
            if (targetHpAfter != null) {
              hp[defenderSide] = targetHpAfter;
              final diff = hp['player']! - hp['cpu']!;
              final newLead = diff > 5 ? 1 : (diff < -5 ? -1 : lead);
              if (lead != 0 && newLead != 0 && newLead != lead) leadChanges++;
              lead = newLead;
            }
            break;
          }
        case 'gameOver':
          {
            final finMoveId = st.finishMoveId;
            if (finMoveId != null) {
              final move = moves[finMoveId];
              if (move != null) {
                _moveStat(finMoveId, move).finishCount++;
              }
              if (move?.category == MoveCategory.finisher) {
                finisherWonSides++;
              }
            }
            break;
          }
      }
    }

    // startingLevel指定時は変更ログが1件も出ないことがあるため、最終到達
    // レベルを下限として反映する。
    maxLevel['player'] = max(maxLevel['player'] ?? 1, st.player.currentLevel);
    maxLevel['cpu'] = max(maxLevel['cpu'] ?? 1, st.cpu.currentLevel);
    heatSumEnd += st.sharedHeat;
    distinctMovesSidesSum += distinctMoves.values.fold<int>(
      0,
      (a, s) => a + s.length,
    );

    for (final side in ['player', 'cpu']) {
      sidesTotal++;
      final wrestler = side == (aIsPlayer ? 'player' : 'cpu')
          ? config.playerA
          : config.playerB;
      final ws = wrestler.id == config.playerA.id ? aStat : bStat;
      ws.levelSum += maxLevel[side] ?? 1;
      if (finisherAttempted[side] == true) ws.finisherAttempts++;
      if (finisherLanded[side] == true) ws.finisherLands++;
      if (finisherLanded[side] == true &&
          st.winnerId == (side == 'player' ? st.player.playerId : st.cpu.playerId)) {
        ws.finisherWins++;
      }
      final p = side == 'player' ? st.player : st.cpu;
      for (final e in p.energyZone) {
        energyInvestedTotals[e.attribute] =
            (energyInvestedTotals[e.attribute] ?? 0) + 1;
        ws.attributeEnergyInvested[e.attribute] =
            (ws.attributeEnergyInvested[e.attribute] ?? 0) + 1;
        if (e.ready) {
          energyReadyAtEndTotals[e.attribute] =
              (energyReadyAtEndTotals[e.attribute] ?? 0) + 1;
          ws.attributeEnergyReadyAtEnd[e.attribute] =
              (ws.attributeEnergyReadyAtEnd[e.attribute] ?? 0) + 1;
        }
      }
    }
    if (leadChanges > 0) matchesWithComeback++;
    leadChangesTotal += leadChanges;

    // 使用回数を(試合単位で)確定させ、勝ったかどうかを技統計へ反映する。
    final winnerId = st.winnerId;
    for (final side in ['player', 'cpu']) {
      for (final moveId in distinctMoves[side] ?? const <String>{}) {
        final move = moves[moveId];
        if (move == null) continue;
        final stat = _moveStat(moveId, move);
        stat.matchesUsedAtLeastOnce++;
        if (winnerId != null) {
          final winnerSide =
              winnerId == st.player.playerId ? 'player' : 'cpu';
          if (winnerSide == side) stat.winsWhenUsed++;
        }
      }
    }

    final score = _scoreEntertainment(
      distinctMovesTotal: distinctMoves.values.fold<int>(
        0,
        (a, s) => a + s.length,
      ),
      finisherLands: finisherLanded.values.where((v) => v).length,
      leadChanges: leadChanges,
      counterCount: counterCountThisMatch,
      levelChangeCount: levelChangeCount,
      pinAttempts: st.pinAttemptCount,
      submissionAttempts: st.submissionAttemptCount,
      hpMargin: (st.player.currentHp - st.cpu.currentHp).abs(),
      finalHeat: st.sharedHeat,
      lateGameMoveCount: lateGameMoveCount,
      decisive: st.winnerId != null,
    );
    entertainmentScores.add(score.score);
    aStat.entertainmentScoreSum += score.score;
    bStat.entertainmentScoreSum += score.score;
  }

  /// Ver.1.1: 複数の対戦カード（複数DeckSimConfig）のレポートを1つに
  /// マージする。ロースター全体の勝率ランキング・技ランキング・AIレポート
  /// などを、既存の単一ペア用ロジックをそのまま再利用して得るための集約。
  /// マージ後のconfigはプレースホルダ（playerA/Bは代表値）であり、
  /// 個別ペアの対戦カード設定としては意味を持たない。
  static DeckBalanceReport merge(
    List<DeckBalanceReport> reports, {
    required DeckSimConfig placeholderConfig,
  }) {
    final merged = DeckBalanceReport(placeholderConfig);
    for (final r in reports) {
      merged.matches += r.matches;
      merged.draws += r.draws;
      merged.aWins += r.aWins;
      merged.bWins += r.bWins;
      merged.turnsList.addAll(r.turnsList);
      r.finishReasonCounts.forEach((k, v) =>
          merged.finishReasonCounts[k] = (merged.finishReasonCounts[k] ?? 0) + v);
      merged.pinTotal += r.pinTotal;
      merged.subTotal += r.subTotal;
      merged.noUsableMoveTotal += r.noUsableMoveTotal;
      merged.leadChangesTotal += r.leadChangesTotal;
      merged.matchesWithComeback += r.matchesWithComeback;
      merged.counterAttempts += r.counterAttempts;
      merged.counterSuccesses += r.counterSuccesses;
      r.energyInvestedTotals.forEach((k, v) =>
          merged.energyInvestedTotals[k] = (merged.energyInvestedTotals[k] ?? 0) + v);
      r.energyReadyAtEndTotals.forEach((k, v) =>
          merged.energyReadyAtEndTotals[k] = (merged.energyReadyAtEndTotals[k] ?? 0) + v);
      merged.finisherAttemptedSides += r.finisherAttemptedSides;
      merged.finisherLandedSides += r.finisherLandedSides;
      merged.finisherWonSides += r.finisherWonSides;
      merged.sidesTotal += r.sidesTotal;
      merged.heatSumEnd += r.heatSumEnd;
      merged.distinctMovesSidesSum += r.distinctMovesSidesSum;
      merged.entertainmentScores.addAll(r.entertainmentScores);

      for (final e in r.moveStats.entries) {
        final acc = merged.moveStats.putIfAbsent(
          e.key,
          () => MoveAccumulator(e.key, e.value.name, e.value.category, e.value.attribute)
            ..level = e.value.level,
        );
        acc.eligibleMatches += e.value.eligibleMatches;
        acc.matchesUsedAtLeastOnce += e.value.matchesUsedAtLeastOnce;
        acc.totalUses += e.value.totalUses;
        acc.attemptedCount += e.value.attemptedCount;
        acc.landedCount += e.value.landedCount;
        acc.finishCount += e.value.finishCount;
        acc.totalDamage += e.value.totalDamage;
        acc.totalHeatGain += e.value.totalHeatGain;
        acc.totalCost += e.value.totalCost;
        acc.turnSum += e.value.turnSum;
        acc.matchTurnsSumWhenUsed += e.value.matchTurnsSumWhenUsed;
        acc.winsWhenUsed += e.value.winsWhenUsed;
      }
      for (final e in r.wrestlerStats.entries) {
        final acc = merged.wrestlerStats.putIfAbsent(
          e.key,
          () => WrestlerAccumulator(e.key, e.value.name),
        );
        acc.games += e.value.games;
        acc.wins += e.value.wins;
        acc.turnSum += e.value.turnSum;
        acc.levelSum += e.value.levelSum;
        acc.damageDealtSum += e.value.damageDealtSum;
        acc.damageTakenSum += e.value.damageTakenSum;
        acc.pinAttempts += e.value.pinAttempts;
        acc.submissionAttempts += e.value.submissionAttempts;
        acc.koWins += e.value.koWins;
        acc.finisherAttempts += e.value.finisherAttempts;
        acc.finisherLands += e.value.finisherLands;
        acc.finisherWins += e.value.finisherWins;
        acc.basicUses += e.value.basicUses;
        acc.signatureUses += e.value.signatureUses;
        acc.finisherUses += e.value.finisherUses;
        acc.entertainmentScoreSum += e.value.entertainmentScoreSum;
        acc.counterAttempts += e.value.counterAttempts;
        acc.counterSuccesses += e.value.counterSuccesses;
        acc.counteredAgainstCount += e.value.counteredAgainstCount;
        e.value.attributeDamage.forEach((k, v) =>
            acc.attributeDamage[k] = (acc.attributeDamage[k] ?? 0) + v);
        e.value.attributeEnergyInvested.forEach((k, v) =>
            acc.attributeEnergyInvested[k] = (acc.attributeEnergyInvested[k] ?? 0) + v);
        e.value.attributeEnergyReadyAtEnd.forEach((k, v) =>
            acc.attributeEnergyReadyAtEnd[k] = (acc.attributeEnergyReadyAtEnd[k] ?? 0) + v);
      }
    }
    return merged;
  }

  /// 実装⑦: 観戦性スコア（100点満点）。各要素の上限点を合計し、
  /// 一方的な展開へはペナルティを課す。閾値・配点はヒューリスティックで
  /// あり、将来のプレイテスト結果に応じて調整可能な単純加算式にしてある。
  EntertainmentScore _scoreEntertainment({
    required int distinctMovesTotal,
    required int finisherLands,
    required int leadChanges,
    required int counterCount,
    required int levelChangeCount,
    required int pinAttempts,
    required int submissionAttempts,
    required int hpMargin,
    required int finalHeat,
    required int lateGameMoveCount,
    required bool decisive,
  }) {
    final breakdown = <String, int>{
      'moveVariety': (min(distinctMovesTotal, 10) * 2),
      'finisherDrama': (min(finisherLands, 3) * 5),
      'comebacks': (min(leadChanges, 5) * 3),
      'counters': (min(counterCount, 4) * 2).round(),
      'levelUps': (min(levelChangeCount, 4) * 2).round(),
      'falls': (min(pinAttempts, 3) * 3).round(),
      'submissions': (min(submissionAttempts, 3) * 3).round(),
      'closeness': max(0, 10 - (hpMargin / 10).round()),
      'heatBuildup': min((finalHeat / 30).round(), 10),
      'lateGameAction': min(lateGameMoveCount, 5) * 2,
    };
    var total = breakdown.values.fold<int>(0, (a, b) => a + b);
    if (!decisive) total -= 10;
    if (hpMargin >= 90) {
      total -= 15;
      breakdown['lopsidedPenalty'] = -15;
    } else if (hpMargin >= 70) {
      total -= 8;
      breakdown['lopsidedPenalty'] = -8;
    }
    total = total.clamp(0, 100);
    final String label;
    final int stars;
    if (total >= 90) {
      label = '年間ベストバウト候補';
      stars = 5;
    } else if (total >= 80) {
      label = '大熱戦';
      stars = 5;
    } else if (total >= 65) {
      label = '見応えのある好勝負';
      stars = 4;
    } else if (total >= 50) {
      label = '堅実な試合';
      stars = 3;
    } else if (total >= 35) {
      label = '単調な試合';
      stars = 2;
    } else {
      label = '退屈な展開';
      stars = 1;
    }
    return EntertainmentScore(
      score: total,
      stars: stars,
      label: label,
      breakdown: breakdown,
    );
  }

  // ---- 全体集計（実装③） ----
  double _pct(num a, num b) => b == 0 ? 0 : a / b;
  double _avg(num a, num b) => b == 0 ? 0 : a / b;

  double get winRateA => _pct(aWins, matches);
  double get winRateB => _pct(bWins, matches);
  double get drawRate => _pct(draws, matches);
  double get avgTurns =>
      turnsList.isEmpty ? 0 : turnsList.reduce((a, b) => a + b) / turnsList.length;
  double get avgHeat => _avg(heatSumEnd, matches);
  double get pinRate => _avg(pinTotal, matches);
  double get submissionRate => _avg(subTotal, matches);
  double get koRate => _pct(finishReasonCounts['koStoppage'] ?? 0, matches);
  double get refereeStopRate => koRate; // koStoppage=レフェリーストップと同義
  double get timeUpRate => _pct(finishReasonCounts['draw'] ?? 0, matches);
  double get comebackRate => _pct(matchesWithComeback, matches);
  double get avgComebacks => _avg(leadChangesTotal, matches);
  double get avgDistinctMoves => _avg(distinctMovesSidesSum, sidesTotal);
  double get counterSuccessRate => _pct(counterSuccesses, counterAttempts);
  double get noUsableMoveRate => _avg(noUsableMoveTotal, matches);
  double get avgEntertainmentScore => entertainmentScores.isEmpty
      ? 0
      : entertainmentScores.reduce((a, b) => a + b) / entertainmentScores.length;
  double get finisherTriggerRate => _pct(finisherAttemptedSides, sidesTotal);
  double get finisherSuccessRate => _pct(finisherWonSides, finisherLandedSides);
  double energySurplusRateFor(MoveAttribute attr) => _pct(
    energyReadyAtEndTotals[attr] ?? 0,
    energyInvestedTotals[attr] ?? 0,
  );
  double get overallEnergySurplusRate {
    final invested = energyInvestedTotals.values.fold<int>(0, (a, b) => a + b);
    final ready = energyReadyAtEndTotals.values.fold<int>(0, (a, b) => a + b);
    return _pct(ready, invested);
  }

  List<MapEntry<String, MoveAccumulator>> get moveRankingByUsage =>
      moveStats.entries.toList()
        ..sort((a, b) => b.value.totalUses.compareTo(a.value.totalUses));

  List<MapEntry<String, MoveAccumulator>> get unusedMoveRanking =>
      moveStats.entries.where((e) => e.value.eligibleMatches > 0).toList()
        ..sort((a, b) => b.value.unusedRate.compareTo(a.value.unusedRate));

  List<MapEntry<String, WrestlerAccumulator>> get wrestlerWinRateRanking =>
      wrestlerStats.entries.toList()
        ..sort((a, b) => b.value.winRate.compareTo(a.value.winRate));

  /// 実装⑥: AIレポート（ルールベースの静的分析）。
  List<AiFinding> generateAiReport(Map<String, MoveDefinition> moves) {
    final findings = <AiFinding>[];
    for (final entry in wrestlerStats.entries) {
      final w = entry.value;
      if (w.games == 0) continue;
      if (w.basicDependencyRate >= 0.5) {
        findings.add(AiFinding(
          subject: w.name,
          observation:
              '通常技依存率が${(w.basicDependencyRate * 100).toStringAsFixed(0)}%と高く、固有技を活かしきれていません。',
          suggestion: '固有技のコストを1軽減する、または通常技の威力を抑えて相対的な魅力を上げることを検討してください。',
          severity: 'warn',
        ));
      }
      if (w.finisherAttempts > 0 && w.finisherSuccessRate < 0.15) {
        findings.add(AiFinding(
          subject: w.name,
          observation:
              'フィニッシャー成功率が${(w.finisherSuccessRate * 100).toStringAsFixed(0)}%と低めです。',
          suggestion: 'フィニッシャーのpinPower/submissionPowerを上げる、またはキックアウトコストを重くすることを検討してください。',
          severity: 'warn',
        ));
      }
      final weak = w.weakestAttribute;
      if (weak != null && (w.attributeDamage[weak] ?? 0) == 0) {
        findings.add(AiFinding(
          subject: w.name,
          observation: '${_attrLabel(weak)}属性のダメージがほぼ0で、その属性の技が機能していません。',
          suggestion: '${_attrLabel(weak)}属性の通常技カードを増やす、または該当技の威力を見直してください。',
          severity: 'info',
        ));
      }
      final surplusAttrs = w.attributeEnergyInvested.entries
          .where((e) => e.value > 0)
          .where((e) {
        final ready = w.attributeEnergyReadyAtEnd[e.key] ?? 0;
        return ready / e.value >= 0.7;
      }).toList();
      if (surplusAttrs.isNotEmpty) {
        final labels = surplusAttrs.map((e) => _attrLabel(e.key)).join('・');
        findings.add(AiFinding(
          subject: w.name,
          observation: '$labels属性のエネルギーが余りやすい傾向があります。',
          suggestion: '$labels属性を使う通常技を追加する、またはHEAT獲得量を+5するアクションの追加を検討してください。',
          severity: 'info',
        ));
      }
    }
    for (final entry in unusedMoveRanking.take(5)) {
      final stat = entry.value;
      if (stat.eligibleMatches == 0 || stat.unusedRate < 0.9) continue;
      findings.add(AiFinding(
        subject: stat.name,
        observation: '未使用率${(stat.unusedRate * 100).toStringAsFixed(0)}%でほぼ使用されていません。',
        suggestion: '${stat.name}のコストを1軽減する、威力を上げる、またはフォール/ギブアップを付与することを検討してください。',
        severity: 'critical',
      ));
    }
    return findings;
  }

  String _attrLabel(MoveAttribute a) => switch (a) {
    MoveAttribute.strike => '打',
    MoveAttribute.throwMove => '投',
    MoveAttribute.submission => '関',
    MoveAttribute.counter => '返',
    MoveAttribute.rough => 'ラフ',
    MoveAttribute.aerial => '飛',
  };

  Map<String, dynamic> toJson(Map<String, MoveDefinition> moves) => {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'version': '1.0',
    'config': config.toJson(),
    'summary': {
      'matches': matches,
      'winRateA': winRateA,
      'winRateB': winRateB,
      'drawRate': drawRate,
      'avgTurns': avgTurns,
      'avgHeat': avgHeat,
      'avgDistinctMoves': avgDistinctMoves,
      'finishReasonCounts': finishReasonCounts,
      'pinRate': pinRate,
      'submissionRate': submissionRate,
      'koRate': koRate,
      'refereeStopRate': refereeStopRate,
      'timeUpRate': timeUpRate,
      'comebackRate': comebackRate,
      'avgComebacks': avgComebacks,
      'counterSuccessRate': counterSuccessRate,
      'noUsableMoveRate': noUsableMoveRate,
      'overallEnergySurplusRate': overallEnergySurplusRate,
      'energySurplusByAttribute': {
        for (final a in MoveAttribute.values) a.name: energySurplusRateFor(a),
      },
      'finisherTriggerRate': finisherTriggerRate,
      'finisherSuccessRate': finisherSuccessRate,
      'avgEntertainmentScore': avgEntertainmentScore,
    },
    'wrestlers': {
      for (final e in wrestlerStats.entries)
        e.key: {
          'name': e.value.name,
          'games': e.value.games,
          'winRate': e.value.winRate,
          'avgTurns': e.value.avgTurns,
          'avgLevel': e.value.avgLevel,
          'avgDamageDealt': e.value.avgDamageDealt,
          'avgDamageTaken': e.value.avgDamageTaken,
          'pinRate': e.value.pinRate,
          'submissionRate': e.value.submissionRate,
          'koRate': e.value.koRate,
          'finisherSuccessRate': e.value.finisherSuccessRate,
          'favoriteAttribute': e.value.favoriteAttribute?.name,
          'weakestAttribute': e.value.weakestAttribute?.name,
          'basicDependencyRate': e.value.basicDependencyRate,
          'signatureDependencyRate': e.value.signatureDependencyRate,
          'avgEntertainmentScore': e.value.avgEntertainmentScore,
        },
    },
    'moves': {
      for (final e in moveStats.entries)
        e.key: {
          'name': e.value.name,
          'category': e.value.category.name,
          'attribute': e.value.attribute.name,
          'level': e.value.level,
          'usageRate': e.value.usageRate,
          'unusedRate': e.value.unusedRate,
          'avgDamage': e.value.avgDamage,
          'avgHeatGain': e.value.avgHeatGain,
          'avgCost': e.value.avgCost,
          'winRateWhenUsed': e.value.winRateWhenUsed,
          'counterRate': e.value.counterRate,
          'finishRate': e.value.finishRate,
          'contributionScore': e.value.contributionScore,
          'expectedValuePerMatch': e.value.expectedValuePerMatch,
          'aiEvaluation': moves[e.key] == null
              ? null
              : e.value.aiEvaluation(moves[e.key]!),
        },
    },
    'aiReport': generateAiReport(moves).map((f) => f.toJson()).toList(),
  };

  String toCsvMoves() {
    const headers = [
      'moveId', 'name', 'category', 'attribute', 'level',
      'usageRate', 'unusedRate', 'avgDamage', 'avgHeatGain', 'avgCost',
      'winRateWhenUsed', 'counterRate', 'finishRate', 'contributionScore',
      'expectedValuePerMatch',
    ];
    final rows = <String>[headers.join(',')];
    for (final e in moveStats.entries) {
      final s = e.value;
      rows.add([
        e.key, s.name, s.category.name, s.attribute.name, s.level ?? '',
        s.usageRate.toStringAsFixed(3), s.unusedRate.toStringAsFixed(3),
        s.avgDamage.toStringAsFixed(2), s.avgHeatGain.toStringAsFixed(2),
        s.avgCost.toStringAsFixed(2), s.winRateWhenUsed.toStringAsFixed(3),
        s.counterRate.toStringAsFixed(3), s.finishRate.toStringAsFixed(3),
        s.contributionScore.toStringAsFixed(1),
        s.expectedValuePerMatch.toStringAsFixed(2),
      ].join(','));
    }
    return rows.join('\n');
  }

  String toCsvWrestlers() {
    const headers = [
      'wrestlerId', 'name', 'games', 'winRate', 'avgTurns', 'avgLevel',
      'avgDamageDealt', 'avgDamageTaken', 'pinRate', 'submissionRate',
      'koRate', 'finisherSuccessRate', 'basicDependencyRate',
      'signatureDependencyRate', 'avgEntertainmentScore',
    ];
    final rows = <String>[headers.join(',')];
    for (final e in wrestlerStats.entries) {
      final s = e.value;
      rows.add([
        e.key, s.name, s.games, s.winRate.toStringAsFixed(3),
        s.avgTurns.toStringAsFixed(2), s.avgLevel.toStringAsFixed(2),
        s.avgDamageDealt.toStringAsFixed(2), s.avgDamageTaken.toStringAsFixed(2),
        s.pinRate.toStringAsFixed(2), s.submissionRate.toStringAsFixed(2),
        s.koRate.toStringAsFixed(3), s.finisherSuccessRate.toStringAsFixed(3),
        s.basicDependencyRate.toStringAsFixed(3),
        s.signatureDependencyRate.toStringAsFixed(3),
        s.avgEntertainmentScore.toStringAsFixed(1),
      ].join(','));
    }
    return rows.join('\n');
  }

  String toCsvSummary() {
    final rows = <String>[
      'metric,value',
      'matches,$matches',
      'winRateA,${winRateA.toStringAsFixed(3)}',
      'winRateB,${winRateB.toStringAsFixed(3)}',
      'drawRate,${drawRate.toStringAsFixed(3)}',
      'avgTurns,${avgTurns.toStringAsFixed(2)}',
      'pinRate,${pinRate.toStringAsFixed(2)}',
      'submissionRate,${submissionRate.toStringAsFixed(2)}',
      'koRate,${koRate.toStringAsFixed(3)}',
      'timeUpRate,${timeUpRate.toStringAsFixed(3)}',
      'comebackRate,${comebackRate.toStringAsFixed(3)}',
      'avgComebacks,${avgComebacks.toStringAsFixed(2)}',
      'counterSuccessRate,${counterSuccessRate.toStringAsFixed(3)}',
      'noUsableMoveRate,${noUsableMoveRate.toStringAsFixed(3)}',
      'overallEnergySurplusRate,${overallEnergySurplusRate.toStringAsFixed(3)}',
      'finisherTriggerRate,${finisherTriggerRate.toStringAsFixed(3)}',
      'finisherSuccessRate,${finisherSuccessRate.toStringAsFixed(3)}',
      'avgEntertainmentScore,${avgEntertainmentScore.toStringAsFixed(1)}',
    ];
    return rows.join('\n');
  }

  String prettyJson(Map<String, MoveDefinition> moves) =>
      const JsonEncoder.withIndent('  ').convert(toJson(moves));
}
