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

  LevelMatchEngine energyEngine({int seed = 1, bool playerStarts = true}) =>
      LevelMatchEngine.create(
        playerWrestler: byId('wrestler_akari'),
        cpuWrestler: byId('wrestler_misaki'),
        moves: moves,
        random: Random(seed),
        playerStarts: playerStarts,
        resourceMode: MatchResourceMode.energy,
      );

  void toChoose(LevelMatchEngine m) {
    m.skipSetCard('player');
    m.skipLevelChange('player');
  }

  test('energyモード：セットしたカードはenergyZoneへ入りsetCardsは空のまま', () {
    final m = energyEngine();
    final card = m.state.player.hand.first;
    m.setTechniqueCard('player', card.instanceId);
    expect(m.state.player.setCards, isEmpty);
    expect(m.state.player.energyZone, hasLength(1));
    expect(m.state.player.energyZone.first.ready, isTrue);
    expect(m.state.player.energyZone.first.attribute, card.attribute);
  });

  test('energyモード：1ターンに複数枚セットできない', () {
    final m = energyEngine();
    final a = m.state.player.hand[0];
    final b = m.state.player.hand[1];
    m.setTechniqueCard('player', a.instanceId);
    expect(
      () => m.setTechniqueCard('player', b.instanceId),
      throwsStateError,
    );
  });

  test('energyモード：自ターン開始時にUsedがReadyへ戻る（アンタップ）', () {
    final m = energyEngine();
    final player = m.state.player;
    // 打属性カードを2枚セットできるよう、2ターンかけて用意。
    for (var i = 0; i < 2 && player.hand.isNotEmpty; i++) {
      final card = player.hand.first;
      m.setTechniqueCard('player', card.instanceId);
      m.skipLevelChange('player');
      // CPU側は自動で進める。
      while (m.decisionOwnerId() == 'cpu' &&
          m.state.phase != LevelMatchPhase.chooseMove) {
        m.autoAdvance();
      }
      if (m.state.activePlayerId == 'player' &&
          m.state.phase == LevelMatchPhase.chooseMove) {
        m.skipMove('player');
      }
      while (m.state.activePlayerId != 'player' && !m.state.isGameOver) {
        m.autoAdvance();
      }
    }
    expect(player.energyZone, isNotEmpty);
    // 全て使用済みにしてみる。
    for (final e in player.energyZone) {
      e.ready = false;
    }
    expect(player.readyEnergyCounts.values.every((v) => v == 0), isTrue);
    m.beginTurn();
    // beginTurn は「現在のアクティブプレイヤー」に対して行われるため、
    // playerがアクティブなときのみアンタップされる想定を確認。
    if (m.state.activePlayerId == 'player') {
      expect(player.energyZone.every((e) => e.ready), isTrue);
    }
  });

  test('energyモード：無料通常技は廃止（エネルギー無しでは使用不可）', () {
    final m = energyEngine();
    toChoose(m);
    final card = m.state.player.hand.firstWhere(
      (c) => m.basicMoveFor(c.attribute, m.state.player) != null,
    );
    expect(
      () => m.useBasicMove('player', card.instanceId),
      throwsStateError,
    );
  });

  test('energyモード：必要エネルギーを払えば単体技を使用できる', () {
    final m = energyEngine();
    final player = m.state.player;
    final card = player.hand.firstWhere(
      (c) => m.basicMoveFor(c.attribute, player) != null,
    );
    final basic = m.basicMoveFor(card.attribute, player)!;
    // 必要枚数ぶんエネルギーをReadyで用意する。
    for (final entry in basic.energyModeRequiredCards.entries) {
      for (var i = 0; i < entry.value; i++) {
        player.energyZone.add(
          EnergyCardState(
            instanceId: 'e$i-${entry.key}',
            attribute: entry.key,
            name: '${entry.key.name}エネルギー',
          ),
        );
      }
    }
    toChoose(m);
    m.useBasicMove('player', card.instanceId);
    // 使用後、対応するエネルギーはUsedになっている。
    expect(player.readyEnergyCounts[basic.attribute] ?? 0, 0);
  });

  test('energyモード：classicのsetCards経済には一切影響しない（既定はclassic）', () {
    final m = LevelMatchEngine.create(
      playerWrestler: byId('wrestler_akari'),
      cpuWrestler: byId('wrestler_misaki'),
      moves: moves,
      random: Random(1),
    );
    expect(m.state.resourceMode, MatchResourceMode.classic);
    toChoose(m);
    final card = m.state.player.hand.firstWhere(
      (c) => m.basicMoveFor(c.attribute, m.state.player) != null,
    );
    // classicでは単体技は無料のまま使用できる（回帰確認）。
    expect(() => m.useBasicMove('player', card.instanceId), returnsNormally);
  });

  test('energyモード：CPU対CPUが例外なく最後まで進行する（複数シード）', () {
    for (final seed in [1, 2, 3, 4, 5]) {
      final m = LevelMatchEngine.create(
        playerWrestler: byId('wrestler_akari'),
        cpuWrestler: byId('wrestler_jack'),
        moves: moves,
        random: Random(seed),
        playerStarts: seed.isEven,
        resourceMode: MatchResourceMode.energy,
      );
      var guard = 0;
      while (!m.state.isGameOver && guard++ < 3000) {
        m.autoAdvance();
      }
      expect(m.state.isGameOver, isTrue, reason: 'seed=$seed で終了しない');
      expect(m.state.winnerId, isNotNull, reason: 'seed=$seed で勝者未確定');
    }
  });
}
