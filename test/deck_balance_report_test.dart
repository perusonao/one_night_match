import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/level_match/deck_balance_models.dart';
import 'package:one_night_match/src/level_match/deck_balance_simulator.dart';
import 'package:one_night_match/src/level_match/level_match_engine.dart';
import 'package:one_night_match/src/wrestler_editor/defaults.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final moves = {for (final m in defaultEditorMoves) m.id: m};
  WrestlerDefinition byId(String id) =>
      defaultEditorWrestlers.firstWhere((w) => w.id == id);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('100試合実行し、全試合が決着し集計が整合する', () {
    final sim = DeckBalanceSimulator(moves);
    final report = sim.run(DeckSimConfig(
      playerA: byId('wrestler_akari'),
      playerB: byId('wrestler_misaki'),
      matches: 100,
      seedMode: SeedMode.fixed,
      fixedSeed: 1,
    ));

    expect(report.matches, 100);
    expect(report.aWins + report.bWins + report.draws, 100);
    expect(report.avgTurns, greaterThan(0));

    // 固有技は両レスラー分が登録され、eligibleMatchesは全試合数と一致する。
    final dropkick = report.moveStats['akari_dropkick'];
    expect(dropkick, isNotNull);
    expect(dropkick!.eligibleMatches, 100);
    expect(dropkick.totalUses, greaterThan(0));
    expect(dropkick.level, isNotNull);

    // レスラー統計もplayerA/playerB両方揃う。
    expect(report.wrestlerStats['wrestler_akari']?.games, 100);
    expect(report.wrestlerStats['wrestler_misaki']?.games, 100);

    // 観戦性スコアは0-100に収まる。
    for (final s in report.entertainmentScores) {
      expect(s, inInclusiveRange(0, 100));
    }

    final json = report.toJson(moves);
    expect(json['summary'], isNotNull);
    expect((json['moves'] as Map).isNotEmpty, isTrue);

    final findings = report.generateAiReport(moves);
    // findingsは空でも構わないが、呼び出しが例外を出さないことを確認。
    expect(findings, isA<List>());

    expect(report.toCsvMoves().split('\n').length, greaterThan(1));
    expect(report.toCsvWrestlers().split('\n').length, greaterThan(1));
    expect(report.toCsvSummary().split('\n').length, greaterThan(1));
  });

  test('固定Seedは再現性がある（同一Seedなら同一集計）', () {
    final sim = DeckBalanceSimulator(moves);
    final config = DeckSimConfig(
      playerA: byId('wrestler_reina'),
      playerB: byId('wrestler_jack'),
      matches: 30,
      seedMode: SeedMode.fixed,
      fixedSeed: 5,
    );
    final r1 = sim.run(config);
    final r2 = sim.run(config);
    expect(r1.aWins, r2.aWins);
    expect(r1.bWins, r2.bWins);
    expect(r1.avgTurns, r2.avgTurns);
  });

  test('CpuDifficulty=random は使用可能な範囲で正常終了する', () {
    final sim = DeckBalanceSimulator(moves);
    final report = sim.run(DeckSimConfig(
      playerA: byId('wrestler_akari'),
      playerB: byId('wrestler_misaki'),
      matches: 20,
      seedMode: SeedMode.fixed,
      fixedSeed: 9,
      cpuDifficulty: CpuDifficulty.random,
    ));
    expect(report.matches, 20);
  });

  test('startingLevel/Heat/Hp指定が集計にも反映される', () {
    final sim = DeckBalanceSimulator(moves);
    final report = sim.run(DeckSimConfig(
      playerA: byId('wrestler_akari'),
      playerB: byId('wrestler_misaki'),
      matches: 10,
      seedMode: SeedMode.fixed,
      fixedSeed: 2,
      startingLevel: 3,
      startingHeat: 30,
      startingHp: 50,
    ));
    expect(report.wrestlerStats['wrestler_akari']?.avgLevel, greaterThanOrEqualTo(3));
  });
}
