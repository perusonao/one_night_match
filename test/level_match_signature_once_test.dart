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

  test('signatureOncePerMatch: 既定はfalse（従来通り無制限）', () {
    final m = LevelMatchEngine.create(
      playerWrestler: byId('wrestler_akari'),
      cpuWrestler: byId('wrestler_misaki'),
      moves: moves,
      random: Random(1),
    );
    expect(m.state.signatureOncePerMatch, isFalse);
  });

  test('signatureOncePerMatch=true: 固有技は1回使うと再使用不可になる', () {
    final m = LevelMatchEngine.create(
      playerWrestler: byId('wrestler_akari'),
      cpuWrestler: byId('wrestler_misaki'),
      moves: moves,
      random: Random(1),
      resourceMode: MatchResourceMode.energy,
      signatureOncePerMatch: true,
    );
    final player = m.state.player;
    final sig = moves['akari_dropkick']!;
    expect(sig.category, MoveCategory.normal);
    player.energyZone.add(
      EnergyCardState(instanceId: 'e1', attribute: MoveAttribute.strike, name: '打'),
    );
    player.energyZone.add(
      EnergyCardState(instanceId: 'e2', attribute: MoveAttribute.strike, name: '打'),
    );
    m.skipSetCard('player');
    m.skipLevelChange('player');
    expect(m.evaluateMove(player, sig).usable, isTrue);
    m.useMove('player', sig.id);
    m.respondTake('cpu');
    // 使用済みになった固有技は、エネルギーが足りていても再使用できない。
    final avail = m.evaluateMove(player, sig);
    expect(avail.usable, isFalse);
    expect(avail.reasons, contains('固有技は1試合1回までです（使用済み）'));
  });

  test('signatureOncePerMatch=true: レベルアップしても回数は回復しない', () {
    final m = LevelMatchEngine.create(
      playerWrestler: byId('wrestler_akari'),
      cpuWrestler: byId('wrestler_misaki'),
      moves: moves,
      random: Random(1),
      resourceMode: MatchResourceMode.energy,
      signatureOncePerMatch: true,
    );
    final player = m.state.player;
    final sig = moves['akari_dropkick']!;
    player.moveUsageCounts[sig.id] = 1; // 使用済み扱いを直接再現
    player.currentLevel = 2;
    player.unlockedLevels.addAll({1, 2});
    // Level変更を経ても使用済みのまま。
    expect(m.evaluateMove(player, sig).usable, isFalse);
  });

  test('signatureOncePerMatch=true: フィニッシャーは元々1回のみのため挙動は変わらない', () {
    final fin = moves['high_speed_german']!;
    expect(fin.category, MoveCategory.finisher);
    expect(fin.usageLimit, 1);
  });

  test('signatureOncePerMatch=true: CPU対CPUで例外なく最後まで進行する', () {
    for (final seed in [2, 5, 9]) {
      final m = LevelMatchEngine.create(
        playerWrestler: byId('wrestler_reina'),
        cpuWrestler: byId('wrestler_jack'),
        moves: moves,
        random: Random(seed),
        playerStarts: seed.isEven,
        resourceMode: MatchResourceMode.energy,
        signatureOncePerMatch: true,
      );
      var guard = 0;
      while (!m.state.isGameOver && guard++ < 3000) {
        m.autoAdvance();
      }
      expect(m.state.isGameOver, isTrue, reason: 'seed=$seed で終了しない');
    }
  });
}
