import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/level_match/level_match_engine.dart';
import 'package:one_night_match/src/wrestler_editor/defaults.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final moves = {for (final m in defaultEditorMoves) m.id: m};
  WrestlerDefinition byId(String id) =>
      defaultEditorWrestlers.firstWhere((w) => w.id == id);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('CpuDifficulty: 既定はnormal', () {
    final m = LevelMatchEngine.create(
      playerWrestler: byId('wrestler_akari'),
      cpuWrestler: byId('wrestler_misaki'),
      moves: moves,
      random: Random(1),
    );
    expect(m.state.cpuDifficulty, CpuDifficulty.normal);
  });

  test('CpuDifficulty全パターンでCPU対CPUが例外なく最後まで進行する', () {
    for (final difficulty in CpuDifficulty.values) {
      for (final seed in [1, 7, 42]) {
        final m = LevelMatchEngine.create(
          playerWrestler: byId('wrestler_reina'),
          cpuWrestler: byId('wrestler_jack'),
          moves: moves,
          random: Random(seed),
          resourceMode: MatchResourceMode.energy,
          cpuDifficulty: difficulty,
        );
        var guard = 0;
        while (!m.state.isGameOver && guard++ < 3000) {
          m.autoAdvance();
        }
        expect(
          m.state.isGameOver,
          isTrue,
          reason: '$difficulty / seed=$seed で終了しない',
        );
      }
    }
  });

  test('startingLevel/Heat/Hp: 指定した開始状態が反映される', () {
    final m = LevelMatchEngine.create(
      playerWrestler: byId('wrestler_akari'),
      cpuWrestler: byId('wrestler_misaki'),
      moves: moves,
      random: Random(1),
      resourceMode: MatchResourceMode.energy,
      startingLevel: 3,
      startingHeat: 40,
      startingHp: 60,
    );
    expect(m.state.player.currentLevel, 3);
    expect(m.state.cpu.currentLevel, 3);
    expect(m.state.player.unlockedLevels, containsAll([1, 2, 3]));
    expect(m.state.sharedHeat, 40);
    expect(m.state.player.currentHp, 60);
    expect(m.state.cpu.currentHp, 60);
  });

  test('startingLevel: 存在しないレベルを指定しても安全に丸められる', () {
    final m = LevelMatchEngine.create(
      playerWrestler: byId('wrestler_akari'),
      cpuWrestler: byId('wrestler_misaki'),
      moves: moves,
      random: Random(1),
      resourceMode: MatchResourceMode.energy,
      startingLevel: 6,
    );
    expect(m.state.player.currentLevel, lessThanOrEqualTo(3));
  });
}
