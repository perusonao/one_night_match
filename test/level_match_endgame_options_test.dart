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

  group('BasicCardPolicy', () {
    test('Ver.0.9.2で正式採用、既定はunlimitedReuse', () {
      final m = LevelMatchEngine.create(
        playerWrestler: byId('wrestler_akari'),
        cpuWrestler: byId('wrestler_misaki'),
        moves: moves,
        random: Random(1),
        resourceMode: MatchResourceMode.energy,
      );
      expect(m.state.basicCardPolicy, BasicCardPolicy.unlimitedReuse);
    });

    test('discardAfterUseは使用後に手札から捨て札へ移動する', () {
      final m = LevelMatchEngine.create(
        playerWrestler: byId('wrestler_akari'),
        cpuWrestler: byId('wrestler_misaki'),
        moves: moves,
        random: Random(1),
        resourceMode: MatchResourceMode.energy,
        basicCardPolicy: BasicCardPolicy.discardAfterUse,
      );
      final player = m.state.player;
      final card = player.hand.firstWhere((c) => !c.isEnergyOnly);
      player.energyZone.add(
        EnergyCardState(instanceId: 'e1', attribute: card.attribute, name: '属'),
      );
      m.skipSetCard('player');
      m.skipLevelChange('player');
      m.useTechniqueCard('player', card.instanceId);
      expect(player.hand.any((c) => c.instanceId == card.instanceId), isFalse);
      expect(
        player.discardPile.any((c) => c.instanceId == card.instanceId),
        isTrue,
      );
    });

    test('recycleToDeck: 使用後は山札へ戻り、手札にも捨て札にも残らない', () {
      final m = LevelMatchEngine.create(
        playerWrestler: byId('wrestler_akari'),
        cpuWrestler: byId('wrestler_misaki'),
        moves: moves,
        random: Random(1),
        resourceMode: MatchResourceMode.energy,
        basicCardPolicy: BasicCardPolicy.recycleToDeck,
      );
      final player = m.state.player;
      final card = player.hand.firstWhere((c) => !c.isEnergyOnly);
      player.energyZone.add(
        EnergyCardState(instanceId: 'e1', attribute: card.attribute, name: '属'),
      );
      m.skipSetCard('player');
      m.skipLevelChange('player');
      m.useTechniqueCard('player', card.instanceId);
      expect(player.hand.any((c) => c.instanceId == card.instanceId), isFalse);
      expect(
        player.discardPile.any((c) => c.instanceId == card.instanceId),
        isFalse,
      );
      expect(player.deck.any((c) => c.instanceId == card.instanceId), isTrue);
    });

    test('unlimitedReuse: 使用後も手札に残り続ける', () {
      final m = LevelMatchEngine.create(
        playerWrestler: byId('wrestler_akari'),
        cpuWrestler: byId('wrestler_misaki'),
        moves: moves,
        random: Random(1),
        resourceMode: MatchResourceMode.energy,
        basicCardPolicy: BasicCardPolicy.unlimitedReuse,
      );
      final player = m.state.player;
      final card = player.hand.firstWhere((c) => !c.isEnergyOnly);
      player.energyZone.add(
        EnergyCardState(instanceId: 'e1', attribute: card.attribute, name: '属'),
      );
      m.skipSetCard('player');
      m.skipLevelChange('player');
      m.useTechniqueCard('player', card.instanceId);
      expect(player.hand.any((c) => c.instanceId == card.instanceId), isTrue);
    });

    test('reducedCost: 通常技のエネルギーコストが1軽減される（cost1→無料）', () {
      final m = LevelMatchEngine.create(
        playerWrestler: byId('wrestler_akari'),
        cpuWrestler: byId('wrestler_misaki'),
        moves: moves,
        random: Random(1),
        resourceMode: MatchResourceMode.energy,
        basicCardPolicy: BasicCardPolicy.reducedCost,
      );
      final player = m.state.player;
      final card = player.hand.firstWhere((c) => !c.isEnergyOnly);
      // エネルギーを一切セットしていない状態でも使用できるはず（無料化）。
      m.skipSetCard('player');
      m.skipLevelChange('player');
      expect(() => m.useTechniqueCard('player', card.instanceId), returnsNormally);
    });
  });

  group('EnergySurplusPolicy', () {
    LevelMatchEngine buildStuckState(EnergySurplusPolicy policy) {
      final m = LevelMatchEngine.create(
        playerWrestler: byId('wrestler_akari'),
        cpuWrestler: byId('wrestler_misaki'),
        moves: moves,
        random: Random(1),
        resourceMode: MatchResourceMode.energy,
        energySurplusPolicy: policy,
      );
      final player = m.state.player;
      // 手札の技カードを全て捨て、固有技も全て使用済みにして「候補0件」状態を再現。
      player.hand.removeWhere((c) => !c.isEnergyOnly);
      for (final lv in player.wrestler.levels) {
        for (final id in lv.moveIds) {
          player.moveUsageCounts[id] = 1;
        }
      }
      player.finisherUsed = true;
      player.energyZone.add(
        EnergyCardState(instanceId: 'e1', attribute: MoveAttribute.strike, name: '打'),
      );
      player.energyZone.add(
        EnergyCardState(instanceId: 'e2', attribute: MoveAttribute.strike, name: '打'),
      );
      m.skipSetCard('player');
      m.skipLevelChange('player');
      return m;
    }

    test('none: 余剰エネルギーがあってもそのままスキップする', () {
      final m = buildStuckState(EnergySurplusPolicy.none);
      final before = m.state.player.readyEnergyCounts[MoveAttribute.strike];
      m.autoAdvance();
      expect(m.state.player.readyEnergyCounts[MoveAttribute.strike], before);
    });

    test('heatConversion: 余剰エネルギー2枚をHEATに変換する', () {
      final m = buildStuckState(EnergySurplusPolicy.heatConversion);
      final heatBefore = m.state.sharedHeat;
      m.autoAdvance();
      expect(m.state.sharedHeat, greaterThan(heatBefore));
    });

    test('attributeConversion: 余剰属性から別属性へ変換される', () {
      final m = buildStuckState(EnergySurplusPolicy.attributeConversion);
      final countBefore = m.state.player.energyZone.length;
      m.autoAdvance();
      expect(m.state.player.energyZone.length, countBefore + 1);
    });

    test('burstAction: 相手にダメージを与える', () {
      final m = buildStuckState(EnergySurplusPolicy.burstAction);
      final hpBefore = m.state.cpu.currentHp;
      m.autoAdvance();
      expect(m.state.cpu.currentHp, lessThanOrEqualTo(hpBefore));
    });
  });

  test('新オプション有効時もCPU対CPUで例外なく最後まで進行する', () {
    for (final basicPolicy in BasicCardPolicy.values) {
      for (final energyPolicy in EnergySurplusPolicy.values) {
        final m = LevelMatchEngine.create(
          playerWrestler: byId('wrestler_reina'),
          cpuWrestler: byId('wrestler_jack'),
          moves: moves,
          random: Random(3),
          resourceMode: MatchResourceMode.energy,
          basicCardPolicy: basicPolicy,
          energySurplusPolicy: energyPolicy,
        );
        var guard = 0;
        while (!m.state.isGameOver && guard++ < 3000) {
          m.autoAdvance();
        }
        expect(
          m.state.isGameOver,
          isTrue,
          reason: '$basicPolicy / $energyPolicy で終了しない',
        );
      }
    }
  });
}
