import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/level_match/level_match_simulator.dart';
import 'package:one_night_match/src/wrestler_editor/defaults.dart';

/// Ver.0.7.3: フィニッシャー経済＆勝率バランスの回帰テスト。
///
/// 「切り札が実際に使われる／決着する」ことと、複数シード集計で
/// 各レスラーの総合勝率が概ね均衡することを守る。乱数の綾で単一シードは
/// 揺れるため、複数シードを合算して評価する。
void main() {
  final moves = {for (final m in defaultEditorMoves) m.id: m};

  ({
    double use,
    double decision,
    double turns,
    Map<String, double> winRates,
  })
  aggregate(List<int> seeds, int perPair) {
    var use = 0.0, dec = 0.0, turns = 0.0;
    final wins = <String, int>{};
    final games = <String, int>{};
    for (final seed in seeds) {
      final report = LevelMatchSimulator(
        moves,
      ).run(wrestlers: defaultEditorWrestlers, matchesPerPair: perPair, seed: seed);
      final json = report.toJson();
      final summary = json['summary'] as Map<String, dynamic>;
      use += summary['finisherUseRate'] as double;
      dec += summary['finisherDecisionRate'] as double;
      turns += summary['avgTurns'] as double;
      for (final entry in (json['byWrestler'] as Map).entries) {
        final m = entry.value as Map;
        wins[entry.key as String] =
            (wins[entry.key] ?? 0) + (m['wins'] as int);
        games[entry.key] = (games[entry.key] ?? 0) + (m['games'] as int);
      }
    }
    final n = seeds.length;
    return (
      use: use / n,
      decision: dec / n,
      turns: turns / n,
      winRates: {
        for (final id in wins.keys) id: wins[id]! / games[id]!,
      },
    );
  }

  test('切り札が実際に使われ、決着に絡む', () {
    final r = aggregate(const [111, 2222, 33333, 44444, 55555], 20);
    // フィニッシャー使用率は目標帯（40-70%）付近で機能している。
    expect(r.use, greaterThan(0.40));
    expect(r.use, lessThan(0.80));
    // フィニッシャー決着率は目標帯（20-40%）。
    expect(r.decision, greaterThan(0.15));
    expect(r.decision, lessThan(0.45));
  });

  test('総合勝率が概ね均衡する（複数シード集計）', () {
    final r = aggregate(const [111, 2222, 33333, 44444, 55555], 20);
    // 4人とも極端な支配・崩壊がない（40-60%に収まる）。
    for (final entry in r.winRates.entries) {
      expect(
        entry.value,
        inInclusiveRange(0.40, 0.60),
        reason: '${entry.key} の勝率 ${(entry.value * 100).toStringAsFixed(1)}% が均衡帯外',
      );
    }
  });
}
