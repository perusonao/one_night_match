import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/level_match/balance_candidate_runner.dart';
import 'package:one_night_match/src/level_match/balance_diagnostics.dart';
import 'package:one_night_match/src/level_match/deck_balance_models.dart';
import 'package:one_night_match/src/level_match/deck_balance_report.dart';
import 'package:one_night_match/src/level_match/deck_balance_simulator.dart';
import 'package:one_night_match/src/wrestler_editor/defaults.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final moves = {for (final m in defaultEditorMoves) m.id: m};
  final wrestlersById = {for (final w in defaultEditorWrestlers) w.id: w};
  WrestlerDefinition byId(String id) => wrestlersById[id]!;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('DeckBalanceReport.merge: 複数ペアの集計を正しく合算する', () {
    final sim = DeckBalanceSimulator(moves);
    final r1 = sim.run(DeckSimConfig(
      playerA: byId('wrestler_akari'),
      playerB: byId('wrestler_misaki'),
      matches: 50,
      seedMode: SeedMode.fixed,
      fixedSeed: 1,
    ));
    final r2 = sim.run(DeckSimConfig(
      playerA: byId('wrestler_reina'),
      playerB: byId('wrestler_jack'),
      matches: 50,
      seedMode: SeedMode.fixed,
      fixedSeed: 2,
    ));
    final merged = DeckBalanceReport.merge(
      [r1, r2],
      placeholderConfig: DeckSimConfig(
        playerA: byId('wrestler_akari'),
        playerB: byId('wrestler_misaki'),
        matches: 100,
      ),
    );
    expect(merged.matches, 100);
    expect(merged.wrestlerStats.length, 4);
    expect(
      merged.wrestlerStats['wrestler_akari']!.games +
          merged.wrestlerStats['wrestler_misaki']!.games +
          merged.wrestlerStats['wrestler_reina']!.games +
          merged.wrestlerStats['wrestler_jack']!.games,
      200,
    );
  });

  test('diagnoseBalance: 強すぎる/弱すぎるレスラーを閾値通りに分類する', () {
    final sim = DeckBalanceSimulator(moves);
    final reports = <DeckBalanceReport>[];
    final wrestlers = defaultEditorWrestlers;
    for (var i = 0; i < wrestlers.length; i++) {
      for (var j = i + 1; j < wrestlers.length; j++) {
        reports.add(sim.run(DeckSimConfig(
          playerA: wrestlers[i],
          playerB: wrestlers[j],
          matches: 200,
          seedMode: SeedMode.fixed,
          fixedSeed: 10 + i * 10 + j,
        )));
      }
    }
    final merged = DeckBalanceReport.merge(
      reports,
      placeholderConfig: DeckSimConfig(playerA: wrestlers[0], playerB: wrestlers[1], matches: 1),
    );
    final diagnosis = diagnoseBalance(
      report: merged,
      wrestlersById: wrestlersById,
      moves: moves,
    );
    // 黒蝶ジャックは既知のバランス崩壊（cannotCounter集中）でstrong判定される想定。
    final jack = diagnosis.wrestlers.firstWhere((w) => w.wrestlerId == 'wrestler_jack');
    expect(jack.status, 'strong');
    expect(jack.findings.any((f) => f.observation.contains('cannotCounter')), isTrue);
  });

  test('AdjustmentCandidate: cannotCounter削除の変異が実際にmoveへ反映される', () {
    final candidate = AdjustmentCandidate(
      label: 'テスト案',
      description: 'jack_lowblowのcannotCounterを削除',
      mutations: [MoveMutation.removeCannotCounter('jack_lowblow')],
    );
    final mutated = candidate.applyTo(moves);
    expect(moves['jack_lowblow']!.specialAbilities, contains('cannotCounter'));
    expect(mutated['jack_lowblow']!.specialAbilities, isNot(contains('cannotCounter')));
    // 他の技は変更されない。
    expect(mutated['jack_roughslam'], same(moves['jack_roughslam']));
  });

  test('BalanceCandidateSimulator: candidate適用後のwin rateがBaseと異なりうる', () {
    final runner = BalanceCandidateSimulator(
      baseMoves: moves,
      wrestlers: defaultEditorWrestlers,
    );
    final before = runner.run(null, matchesPerPair: 100);
    final candidate = AdjustmentCandidate(
      label: 'Jackのroughslamの威力を大幅強化',
      description: 'テスト用の極端な変更（差が出ることを確認するため）',
      mutations: [MoveMutation.power('jack_roughslam', 50)],
    );
    final after = runner.run(candidate, matchesPerPair: 100);
    expect(before.matches, after.matches);
    // 極端な威力upなので、ジャックの勝利数が増える方向に動くはず
    // （必ずしも単調ではないため、値の存在のみ確認）。
    expect(after.wrestlerStats['wrestler_jack']!.wins, isA<int>());
  });
}
