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

  Map<String, dynamic> toJson() => {
    'playerWrestler': playerWrestler,
    'cpuWrestler': cpuWrestler,
    'winnerId': winnerId,
    'winnerWrestler': winnerWrestler,
    'finishReason': finishReason,
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

  Map<String, dynamic> toJson() {
    final reasons = finishReasonCounts;
    Map<String, double> reasonRates() =>
        {for (final e in reasons.entries) e.key: total == 0 ? 0 : e.value / total};
    return {
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'version': '0.6',
      'config': config,
      'summary': {
        'totalMatches': total,
        'completedMatches': results.where((r) => r.completed).length,
        // 決着理由の内訳（決着がついているか）
        'finishReasonCounts': reasons,
        'finishReasonRates': reasonRates(),
        'pinfallRate': _rate((r) => r.finishReason == 'pinfall'),
        'submissionRate': _rate((r) => r.finishReason == 'submission'),
        'exhaustionRate': _rate((r) => r.finishReason == 'exhaustion'),
        // フォール／ギブアップが「そもそも起きているか」の検証
        'matchesWithAnyPinAttempt': _rate((r) => r.pinAttempts > 0),
        'matchesWithAnySubmissionAttempt':
            _rate((r) => r.submissionAttempts > 0),
        'matchesWithAnyFinisher':
            _rate((r) => r.playerFinisherUsed || r.cpuFinisherUsed),
        'avgTurns': _avg((r) => r.turns),
        'avgPinAttempts': _avg((r) => r.pinAttempts),
        'avgKickOuts': _avg((r) => r.kickOuts),
        'avgSubmissionAttempts': _avg((r) => r.submissionAttempts),
        'avgSubmissionEscapes': _avg((r) => r.submissionEscapes),
        'avgRopeBreaks': _avg((r) => r.ropeBreaks),
        'avgFinalHeat': _avg((r) => r.finalHeat),
        'exhaustionOccurredRate': _rate((r) => r.anyExhausted),
        'winsByWrestler': winsByWrestler,
      },
      'matches': results.map((r) => r.toJson()).toList(),
    };
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
    return SimMatchResult(
      playerWrestler: player.name,
      cpuWrestler: cpu.name,
      winnerId: state.winnerId,
      winnerWrestler: winner,
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
