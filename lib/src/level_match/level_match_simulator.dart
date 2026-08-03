import 'dart:math';

import '../wrestler_editor/models.dart';
import 'level_match_engine.dart';

/// Ver.0.6: CPU対CPUの自動対戦シミュレータ（検証ツール）。
///
/// 「フォール／ギブアップが発生しているか」を数値で検証するため、
/// 多数の試合を最後まで自動進行させ、結果を集計・JSON化する。純粋Dart。

const int kSimStepCap = 5000; // 1試合あたりの安全上限ステップ

/// 1試合分の結果サマリ。
class SimMatchResult {
  const SimMatchResult({
    required this.playerWrestler,
    required this.cpuWrestler,
    required this.winnerId,
    required this.winnerWrestler,
    required this.finishReason,
    required this.turns,
    required this.finalHeat,
    required this.finishingMove,
    required this.pinAttempts,
    required this.kickOuts,
    required this.submissionAttempts,
    required this.submissionEscapes,
    required this.ropeBreaks,
    required this.finisherKickOuts,
    required this.playerFinisherUsed,
    required this.cpuFinisherUsed,
    required this.anyExhausted,
    required this.steps,
    required this.completed,
    required this.playerStarts,
    required this.firstWrestler,
    required this.finisherDecided,
  });

  final String playerWrestler;
  final String cpuWrestler;
  final String? winnerId;
  final String? winnerWrestler;
  final String finishReason;
  final int turns;
  final int finalHeat;
  final String? finishingMove;
  final int pinAttempts;
  final int kickOuts;
  final int submissionAttempts;
  final int submissionEscapes;
  final int ropeBreaks;
  final int finisherKickOuts;
  final bool playerFinisherUsed;
  final bool cpuFinisherUsed;
  final bool anyExhausted;
  final int steps;
  final bool completed;

  // Ver.0.7.2: 先手/後手・フィニッシャー決着の集計用。
  final bool playerStarts;
  final String firstWrestler;
  final bool finisherDecided;

  bool get winnerWasFirst =>
      winnerWrestler != null && winnerWrestler == firstWrestler;
  bool get anyFinisherUsed => playerFinisherUsed || cpuFinisherUsed;

  Map<String, dynamic> toJson() => {
    'playerWrestler': playerWrestler,
    'cpuWrestler': cpuWrestler,
    'firstWrestler': firstWrestler,
    'winnerId': winnerId,
    'winnerWrestler': winnerWrestler,
    'winnerWasFirst': winnerWasFirst,
    'finishReason': finishReason,
    'finisherDecided': finisherDecided,
    'turns': turns,
    'finalHeat': finalHeat,
    'finishingMove': finishingMove,
    'pinAttempts': pinAttempts,
    'kickOuts': kickOuts,
    'submissionAttempts': submissionAttempts,
    'submissionEscapes': submissionEscapes,
    'ropeBreaks': ropeBreaks,
    'finisherKickOuts': finisherKickOuts,
    'playerFinisherUsed': playerFinisherUsed,
    'cpuFinisherUsed': cpuFinisherUsed,
    'anyExhausted': anyExhausted,
    'steps': steps,
    'completed': completed,
  };
}

/// 複数試合の集計レポート。
class SimReport {
  SimReport(this.results, {required this.config});

  final List<SimMatchResult> results;
  final Map<String, dynamic> config;

  int get total => results.length;

  double _rate(bool Function(SimMatchResult) test) =>
      total == 0 ? 0 : results.where(test).length / total;

  double _avg(num Function(SimMatchResult) pick) => total == 0
      ? 0
      : results.map(pick).fold<num>(0, (a, b) => a + b) / total;

  Map<String, int> get finishReasonCounts {
    final counts = <String, int>{};
    for (final r in results) {
      counts[r.finishReason] = (counts[r.finishReason] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> get winsByWrestler {
    final counts = <String, int>{};
    for (final r in results) {
      final name = r.winnerWrestler;
      if (name != null) counts[name] = (counts[name] ?? 0) + 1;
    }
    return counts;
  }

  /// レスラー別集計（総勝率・先手/後手勝率・平均HEAT・フィニッシャー・決着種別）。
  Map<String, dynamic> get byWrestler {
    final names = <String>{
      for (final r in results) ...[r.playerWrestler, r.cpuWrestler],
    };
    final out = <String, dynamic>{};
    for (final name in names) {
      final inMatches = results
          .where((r) => r.playerWrestler == name || r.cpuWrestler == name)
          .toList();
      final wins = inMatches.where((r) => r.winnerWrestler == name).toList();
      final firstMatches =
          inMatches.where((r) => r.firstWrestler == name).toList();
      final secondMatches =
          inMatches.where((r) => r.firstWrestler != name).toList();
      double rate(int a, int b) => b == 0 ? 0 : a / b;
      out[name] = {
        'games': inMatches.length,
        'wins': wins.length,
        'winRate': rate(wins.length, inMatches.length),
        'firstWinRate': rate(
          firstMatches.where((r) => r.winnerWrestler == name).length,
          firstMatches.length,
        ),
        'secondWinRate': rate(
          secondMatches.where((r) => r.winnerWrestler == name).length,
          secondMatches.length,
        ),
        'avgHeat': inMatches.isEmpty
            ? 0
            : inMatches.map((r) => r.finalHeat).fold<num>(0, (a, b) => a + b) /
                  inMatches.length,
        'finisherUseRate': rate(
          inMatches
              .where(
                (r) =>
                    (r.playerWrestler == name && r.playerFinisherUsed) ||
                    (r.cpuWrestler == name && r.cpuFinisherUsed),
              )
              .length,
          inMatches.length,
        ),
        'finisherWins':
            wins.where((r) => r.finisherDecided).length,
        'pinfallWins': wins.where((r) => r.finishReason == 'pinfall').length,
        'submissionWins':
            wins.where((r) => r.finishReason == 'submission').length,
        'exhaustionWins':
            wins.where((r) => r.finishReason == 'exhaustion').length,
      };
    }
    return out;
  }

  /// 対戦カード別集計（勝敗・先手勝率・平均ターン・決着方法）。
  List<Map<String, dynamic>> get byMatchup {
    final pairs = <String, List<SimMatchResult>>{};
    for (final r in results) {
      final key = ([r.playerWrestler, r.cpuWrestler]..sort()).join(' vs ');
      pairs.putIfAbsent(key, () => []).add(r);
    }
    return [
      for (final entry in pairs.entries)
        () {
          final list = entry.value;
          final names = entry.key.split(' vs ');
          final a = names[0], b = names[1];
          final finish = <String, int>{};
          for (final r in list) {
            finish[r.finishReason] = (finish[r.finishReason] ?? 0) + 1;
          }
          return {
            'matchup': entry.key,
            'games': list.length,
            '${a}Wins': list.where((r) => r.winnerWrestler == a).length,
            '${b}Wins': list.where((r) => r.winnerWrestler == b).length,
            'firstWins': list.where((r) => r.winnerWasFirst).length,
            'avgTurns': list.isEmpty
                ? 0
                : list.map((r) => r.turns).fold<num>(0, (x, y) => x + y) /
                      list.length,
            'finishMethods': finish,
          };
        }(),
    ];
  }

  Map<String, dynamic> toJson() {
    final reasons = finishReasonCounts;
    Map<String, double> reasonRates() =>
        {for (final e in reasons.entries) e.key: total == 0 ? 0 : e.value / total};
    return {
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'version': '0.7.2',
      'config': config,
      'summary': {
        'totalMatches': total,
        'completedMatches': results.where((r) => r.completed).length,
        'finishReasonCounts': reasons,
        'finishReasonRates': reasonRates(),
        'pinfallRate': _rate((r) => r.finishReason == 'pinfall'),
        'submissionRate': _rate((r) => r.finishReason == 'submission'),
        'exhaustionRate': _rate((r) => r.finishReason == 'exhaustion'),
        'matchesWithAnyPinAttempt': _rate((r) => r.pinAttempts > 0),
        'matchesWithAnySubmissionAttempt':
            _rate((r) => r.submissionAttempts > 0),
        // Ver.0.7.2: フィニッシャー指標
        'finisherUseRate': _rate((r) => r.anyFinisherUsed),
        'finisherDecisionRate': _rate((r) => r.finisherDecided),
        'firstWinRate': _rate((r) => r.winnerWasFirst),
        'avgTurns': _avg((r) => r.turns),
        'avgPinAttempts': _avg((r) => r.pinAttempts),
        'avgKickOuts': _avg((r) => r.kickOuts),
        'avgSubmissionAttempts': _avg((r) => r.submissionAttempts),
        'avgRopeBreaks': _avg((r) => r.ropeBreaks),
        'avgFinalHeat': _avg((r) => r.finalHeat),
        'exhaustionOccurredRate': _rate((r) => r.anyExhausted),
        'winsByWrestler': winsByWrestler,
      },
      'byWrestler': byWrestler,
      'byMatchup': byMatchup,
      'matches': results.map((r) => r.toJson()).toList(),
    };
  }

  /// 1試合1行のCSV（表計算・外部分析用）。
  String toCsv() {
    const headers = [
      'firstWrestler',
      'playerWrestler',
      'cpuWrestler',
      'winnerWrestler',
      'winnerWasFirst',
      'finishReason',
      'finisherDecided',
      'turns',
      'finalHeat',
      'pinAttempts',
      'kickOuts',
      'submissionAttempts',
      'ropeBreaks',
    ];
    final rows = <String>[headers.join(',')];
    for (final r in results) {
      rows.add([
        r.firstWrestler,
        r.playerWrestler,
        r.cpuWrestler,
        r.winnerWrestler ?? '',
        r.winnerWasFirst,
        r.finishReason,
        r.finisherDecided,
        r.turns,
        r.finalHeat,
        r.pinAttempts,
        r.kickOuts,
        r.submissionAttempts,
        r.ropeBreaks,
      ].join(','));
    }
    return rows.join('\n');
  }
}

class LevelMatchSimulator {
  const LevelMatchSimulator(this.moves);
  final Map<String, MoveDefinition> moves;

  /// 1試合を最後まで自動進行させて結果を返す。
  SimMatchResult playOne({
    required WrestlerDefinition player,
    required WrestlerDefinition cpu,
    required int seed,
    bool playerStarts = true,
  }) {
    final engine = LevelMatchEngine.create(
      playerWrestler: player,
      cpuWrestler: cpu,
      moves: moves,
      random: Random(seed),
      playerStarts: playerStarts,
    );
    final state = engine.state;
    var steps = 0;
    while (!state.isGameOver && steps < kSimStepCap) {
      final owner = engine.decisionOwnerId();
      if (owner == null) break; // 進行不能（通常は起きない）
      engine.autoAdvance();
      steps++;
    }
    final completed = state.isGameOver;
    final winner = state.winnerId == null
        ? null
        : state.byId(state.winnerId!).wrestler.name;
    // 決着技がフィニッシャーだったか。
    final finishId = state.finishMoveId;
    final finisherDecided =
        winner != null &&
        finishId != null &&
        moves[finishId]?.category == MoveCategory.finisher;
    return SimMatchResult(
      playerWrestler: player.name,
      cpuWrestler: cpu.name,
      playerStarts: playerStarts,
      firstWrestler: playerStarts ? player.name : cpu.name,
      winnerId: state.winnerId,
      winnerWrestler: winner,
      finisherDecided: finisherDecided,
      finishReason: state.finishReason?.name ?? 'unfinished',
      turns: state.turnNumber,
      finalHeat: state.sharedHeat,
      finishingMove: state.finishingMove ?? state.lastMove,
      pinAttempts: state.pinAttemptCount,
      kickOuts: state.kickOutTotalCount,
      submissionAttempts: state.submissionAttemptCount,
      submissionEscapes: state.submissionEscapeTotalCount,
      ropeBreaks: state.ropeBreakTotalCount,
      finisherKickOuts: state.finisherKickOutTotalCount,
      playerFinisherUsed: state.player.finisherUsed,
      cpuFinisherUsed: state.cpu.finisherUsed,
      anyExhausted: state.player.isExhausted || state.cpu.isExhausted,
      steps: steps,
      completed: completed,
    );
  }

  /// 全レスラーの総当たり（両手番）を matchesPerPair 回ずつ回す。
  SimReport run({
    required List<WrestlerDefinition> wrestlers,
    int matchesPerPair = 5,
    int seed = 0,
  }) {
    final results = <SimMatchResult>[];
    var counter = seed;
    for (var i = 0; i < wrestlers.length; i++) {
      for (var j = 0; j < wrestlers.length; j++) {
        if (i == j) continue;
        for (var k = 0; k < matchesPerPair; k++) {
          results.add(
            playOne(
              player: wrestlers[i],
              cpu: wrestlers[j],
              seed: counter++,
              // Ver.0.7.2: 先手/後手を交互にして両方の勝率を測る。
              playerStarts: k.isEven,
            ),
          );
        }
      }
    }
    return SimReport(
      results,
      config: {
        'wrestlers': wrestlers.map((w) => w.name).toList(),
        'matchesPerPair': matchesPerPair,
        'seed': seed,
        'pairings': wrestlers.length * (wrestlers.length - 1),
      },
    );
  }
}
