import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/level_match/level_match_simulator.dart';
import 'package:one_night_match/src/wrestler_editor/defaults.dart';

void main() {
  final moves = {for (final m in defaultEditorMoves) m.id: m};

  test('全試合が完了し、決着理由が決着系のみ', () {
    final report = LevelMatchSimulator(moves).run(
      wrestlers: defaultEditorWrestlers,
      matchesPerPair: 10,
      seed: 1,
    );
    expect(report.total, defaultEditorWrestlers.length * 3 * 10);
    // すべての試合が最後まで進む。
    expect(report.results.every((r) => r.completed), isTrue);
    // 決着理由は pinfall / submission / exhaustion / koStoppage のいずれか。
    // Ver.0.9.1: 山札切れ後にHPも尽きた側はkoStoppage（レフェリーストップ）で
    // 即決着する。
    for (final reason in report.finishReasonCounts.keys) {
      expect(
        ['pinfall', 'submission', 'exhaustion', 'koStoppage'],
        contains(reason),
      );
    }
  });

  test('フォール・ギブアップが実際に発生している', () {
    final report = LevelMatchSimulator(moves).run(
      wrestlers: defaultEditorWrestlers,
      matchesPerPair: 10,
      seed: 2,
    );
    final summary = report.toJson()['summary'] as Map<String, dynamic>;
    // 大半の試合でフォール試行が起きる。
    expect(summary['matchesWithAnyPinAttempt'] as double, greaterThan(0.5));
    // 3カウント決着が最頻。
    expect(summary['pinfallRate'] as double, greaterThan(0.3));
    // ギブアップも一定割合発生する。
    expect(
      summary['matchesWithAnySubmissionAttempt'] as double,
      greaterThan(0.1),
    );
  });

  test('決定的（同一シードで同一集計）', () {
    final a = LevelMatchSimulator(moves).run(
      wrestlers: defaultEditorWrestlers,
      matchesPerPair: 5,
      seed: 7,
    );
    final b = LevelMatchSimulator(moves).run(
      wrestlers: defaultEditorWrestlers,
      matchesPerPair: 5,
      seed: 7,
    );
    expect(a.finishReasonCounts, b.finishReasonCounts);
    expect(a.winsByWrestler, b.winsByWrestler);
  });
}
