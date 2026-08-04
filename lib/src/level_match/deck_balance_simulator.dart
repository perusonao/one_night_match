import 'dart:math';

import '../wrestler_editor/models.dart';
import 'deck_balance_models.dart';
import 'deck_balance_report.dart';
import 'level_match_engine.dart';

const int kDeckSimStepCap = 5000;

/// Ver.1.0: デッキバランスシミュレーター本体。
/// LevelMatchEngineの上に薄く乗る「実行専任」クラス。集計ロジックは
/// deck_balance_report.dart（DeckBalanceReport/アキュムレータ）に分離し、
/// このクラスはログを1試合ぶん読み切って集計へ渡すだけに留める。
class DeckBalanceSimulator {
  const DeckBalanceSimulator(this.moves);
  final Map<String, MoveDefinition> moves;

  DeckBalanceReport run(DeckSimConfig config) {
    final report = DeckBalanceReport(config);
    final rng = Random();
    for (var i = 0; i < config.matches; i++) {
      final seed = config.seedMode == SeedMode.fixed
          ? config.fixedSeed + i
          : rng.nextInt(1 << 31);
      final playerStarts = i.isEven;
      final engine = LevelMatchEngine.create(
        playerWrestler: playerStarts ? config.playerA : config.playerB,
        cpuWrestler: playerStarts ? config.playerB : config.playerA,
        moves: moves,
        random: Random(seed),
        playerStarts: true,
        resourceMode: config.resourceMode,
        signatureOncePerMatch: config.signatureOncePerMatch,
        basicCardPolicy: config.basicCardPolicy,
        energySurplusPolicy: config.energySurplusPolicy,
        cpuDifficulty: config.cpuDifficulty,
        startingLevel: config.startingLevel,
        startingHeat: config.startingHeat,
        startingHp: config.startingHp,
      );
      var steps = 0;
      while (!engine.state.isGameOver && steps < kDeckSimStepCap) {
        engine.autoAdvance();
        steps++;
      }
      report.addMatch(engine.state, moves, seed: seed);
    }
    return report;
  }
}
