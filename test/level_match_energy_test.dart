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

  void cpuToChoose(LevelMatchEngine m) {
    m.skipSetCard('cpu');
    m.skipLevelChange('cpu');
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

  test('energyモード：単体技(basic_*)は完全に廃止（エネルギーがあっても使用不可）', () {
    final m = energyEngine();
    final player = m.state.player;
    final card = player.hand.firstWhere(
      (c) => m.basicMoveFor(c.attribute, player) != null,
    );
    final basic = m.basicMoveFor(card.attribute, player)!;
    // 必要枚数ぶんエネルギーをReadyで用意しても、単体技自体が使用不可。
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
    expect(
      () => m.useBasicMove('player', card.instanceId),
      throwsStateError,
    );
  });

  test('energyモード：単体技は対応（迎撃）としても使えない', () {
    final m = energyEngine(playerStarts: false);
    final player = m.state.player;
    final cpu = m.state.cpu;
    final cpuThrow = moves['misaki_bodyslam']!;
    cpu.energyZone.add(
      EnergyCardState(instanceId: 'cpu-e', attribute: MoveAttribute.throwMove, name: '投エネルギー'),
    );
    cpuToChoose(m);
    m.useMove('cpu', cpuThrow.id);
    expect(m.state.phase, LevelMatchPhase.responseSelection);
    final basic = m.basicMoveFor(MoveAttribute.strike, player)!;
    expect(
      m.responseAvailability(player, basic, isBasic: true).usable,
      isFalse,
    );
  });

  test('energyモード：固有技はReadyエネルギーを消費して使用でき、消費後はUsedになる', () {
    final m = energyEngine();
    final player = m.state.player;
    // アカリLv1固有技 akari_dropkick は 打×1 のコスト。
    final sig = moves['akari_dropkick']!;
    expect(sig.energyModeRequiredCards[MoveAttribute.strike], 1);
    player.energyZone.add(
      EnergyCardState(instanceId: 'e-strike', attribute: MoveAttribute.strike, name: '打エネルギー'),
    );
    toChoose(m);
    expect(m.evaluateMove(player, sig).usable, isTrue);
    m.useMove('player', sig.id);
    expect(player.readyEnergyCounts[MoveAttribute.strike] ?? 0, 0);
    expect(player.energyZone.single.ready, isFalse);
    // ログにエネルギー消費の内訳が記録されている（未使用属性も0として含む）。
    final log = m.state.logs.firstWhere((l) => l.action == 'attackDeclared');
    expect((log.details['energyCost'] as Map)['strike'], 1);
    expect(log.details['energySpent'], ['e-strike']);
    expect((log.details['readyEnergyBefore'] as Map)['strike'], 1);
    expect((log.details['readyEnergyAfter'] as Map)['strike'], 0);
  });

  test('energyモード：返し技（counterカテゴリ）は返エネルギーが必要で、無ければ対応不可', () {
    final m = energyEngine(playerStarts: false);
    final player = m.state.player;
    final cpu = m.state.cpu;
    // レベル3まで上げてcounter_brainbusterを解禁。
    player.currentLevel = 3;
    player.unlockedLevels.addAll({2, 3});
    // CPUに投げ技を使わせるため、投エネルギーを用意して固有技を宣言させる。
    final cpuThrow = moves['misaki_bodyslam']!;
    cpu.energyZone.add(
      EnergyCardState(instanceId: 'cpu-throw', attribute: MoveAttribute.throwMove, name: '投エネルギー'),
    );
    cpuToChoose(m);
    m.useMove('cpu', cpuThrow.id);
    expect(m.state.phase, LevelMatchPhase.responseSelection);
    final counterMove = moves['counter_brainbuster']!;
    expect(counterMove.energyModeRequiredCards[MoveAttribute.counter], 1);
    // 返エネルギーが無ければ「対応できません」。
    expect(
      m.responseAvailability(player, counterMove, isBasic: false).usable,
      isFalse,
    );
    // 返エネルギーを用意すれば対応でき、使用後はUsedになる。
    player.energyZone.add(
      EnergyCardState(instanceId: 'e-counter', attribute: MoveAttribute.counter, name: '返エネルギー'),
    );
    expect(
      m.responseAvailability(player, counterMove, isBasic: false).usable,
      isTrue,
    );
    m.respondWithMove('player', counterMove.id);
    // 消費直後の内訳はログで検証する（返し成立でCPUのターンが終わり、
    // 直後にplayerの自ターンが始まってエネルギーが全回復するため、
    // 消費「後」の状態を試合状態から直接見るとアンタップ済みになってしまう）。
    final log =
        m.state.logs.firstWhere((l) => l.action == 'respondEnergyConsumed');
    expect(log.details['isCounterMove'], isTrue);
    expect(log.details['energySpent'], ['e-counter']);
    expect((log.details['readyEnergyBefore'] as Map)['counter'], 1);
    expect((log.details['readyEnergyAfter'] as Map)['counter'], 0);
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
