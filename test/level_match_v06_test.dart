import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/level_match/level_match_engine.dart';
import 'package:one_night_match/src/level_match/level_match_finish_models.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Map<MoveAttribute, int> cards({
    int strike = 0,
    int throwMove = 0,
    int submission = 0,
    int counter = 0,
    int rough = 0,
    int aerial = 0,
  }) => {
    MoveAttribute.strike: strike,
    MoveAttribute.throwMove: throwMove,
    MoveAttribute.submission: submission,
    MoveAttribute.counter: counter,
    MoveAttribute.rough: rough,
    MoveAttribute.aerial: aerial,
  };

  final moves = <String, MoveDefinition>{
    'throwPin': MoveDefinition(
      id: 'throwPin',
      name: '投げ技',
      category: MoveCategory.normal,
      attribute: MoveAttribute.throwMove,
      power: 20,
      heat: 3,
      requiredCards: cards(throwMove: 1),
      discardAfterUse: cards(),
      canAttemptPin: true,
      pinPower: 6,
    ),
    'finPin': MoveDefinition(
      id: 'finPin',
      name: 'フィニッシャー',
      category: MoveCategory.finisher,
      attribute: MoveAttribute.throwMove,
      power: 36,
      heat: 8,
      requiredCards: cards(throwMove: 2),
      discardAfterUse: cards(throwMove: 1),
      usageLimit: 1,
      markUsedAfterUse: true,
      additionalChecks: const [AdditionalCheckType.pinfall],
      canAttemptPin: true,
      pinPower: 8,
      pinBonusOnFinisher: 15,
    ),
  };

  WrestlerLevelDefinition level(int number, {String? finisher}) =>
      WrestlerLevelDefinition(
        level: number,
        displayName: 'Level $number',
        resistances: cards(),
        moveIds: const ['throwPin'],
        finisherId: finisher,
      );

  WrestlerDefinition wrestler(String id) => WrestlerDefinition(
    id: id,
    name: id,
    subtitle: 'test',
    type: EditorWrestlerType.babyface,
    maxHp: 100,
    themeColor: '#E91E63',
    levels: [level(1), level(2), level(3, finisher: 'finPin')],
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  LevelMatchEngine engine() => LevelMatchEngine.create(
    playerWrestler: wrestler('player'),
    cpuWrestler: wrestler('cpu'),
    moves: moves,
    random: Random(1),
    playerStarts: true,
  );

  void advanceToMove(LevelMatchEngine match, {int throwSet = 0}) {
    for (var i = 0; i < throwSet; i++) {
      match.state.player.setCards.add(
        TechniqueResourceCard('s$i', MoveAttribute.throwMove),
      );
    }
    match.skipSetCard('player');
    match.skipLevelChange('player');
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Ver.0.6 累積キックアウト', () {
    test('キックアウト成功で次回HPコスト+5・HEAT+5', () {
      final match = engine();
      advanceToMove(match, throwSet: 1);
      final heatBefore = match.state.sharedHeat;
      match.useMove('player', 'throwPin');
      match.declarePin('player');
      match.state.cpu.currentHp = 90;
      match.kickOut('cpu', DefenseMethod.hp);
      expect(match.state.cpu.kickOutPenalty, kKickOutPenaltyStep);
      expect(match.state.sharedHeat - heatBefore, greaterThanOrEqualTo(5));
    });

    test('累積ペナルティが次のフォールの必要HPに反映される', () {
      final match = engine();
      // 1回目
      advanceToMove(match, throwSet: 1);
      match.useMove('player', 'throwPin');
      match.declarePin('player');
      match.state.cpu.currentHp = 90;
      match.kickOut('cpu', DefenseMethod.hp);
      // CPUの手番を流す
      match.skipSetCard('cpu');
      match.skipLevelChange('cpu');
      match.skipMove('cpu');
      // 2回目のフォール
      match.state.player.setCards.add(
        const TechniqueResourceCard('s2', MoveAttribute.throwMove),
      );
      match.skipSetCard('player');
      match.skipLevelChange('player');
      match.useMove('player', 'throwPin');
      final pin = match.state.pendingPin!;
      expect(
        pin.hpKickOutCost,
        requiredHpCostFor(pin.strength.total) + kKickOutPenaltyStep,
      );
    });
  });

  test('フィニッシャーのHPキックアウトは固定40コスト', () {
    final match = engine();
    match.state.player
      ..currentLevel = 3
      ..unlockedLevels.add(3);
    advanceToMove(match, throwSet: 3);
    match.useMove('player', 'finPin');
    final pin = match.state.pendingPin!;
    expect(pin.fromFinisher, isTrue);
    expect(pin.hpKickOutCost, kFinisherKickOutHpCost);
  });

  group('Ver.0.6 CPU積極フォール', () {
    PendingPin craft() => PendingPin(
      attackerId: 'cpu',
      defenderId: 'player',
      moveId: 'throwPin',
      moveName: '投げ技',
      strength: const PinStrength(
        total: 20,
        base: 6,
        damage: 14,
        finisherBonus: 0,
        fatigueBonus: 0,
        downBonus: 0,
      ),
      hpKickOutCost: 10,
      fromFinisher: false,
      targetWasDown: false,
    );

    test('相手HP70以下ならフォールを宣言する', () {
      final match = engine();
      match.state
        ..pendingPin = craft()
        ..phase = LevelMatchPhase.kickOutDecision; // placeholder
      match.state.phase = LevelMatchPhase.pinDecision;
      match.state.activePlayerId = 'cpu';
      match.state.player.currentHp = 70;
      expect(match.cpuActionPending, isTrue);
      match.runCpuTurn();
      expect(match.state.phase, LevelMatchPhase.kickOutDecision);
    });

    test('相手HPが高い（80）ならフォールを見送る', () {
      final match = engine();
      match.state.pendingPin = craft();
      match.state.phase = LevelMatchPhase.pinDecision;
      match.state.activePlayerId = 'cpu';
      match.state.player.currentHp = 80;
      match.runCpuTurn();
      expect(match.state.pendingPin, isNull); // 見送り→クリア
    });
  });

  group('Ver.0.6 疲労（山札切れ廃止）', () {
    test('山札切れは敗北でなく疲労: HP-5・isExhausted', () {
      final match = engine();
      match.state.player.deck.clear();
      match.skipSetCard('player');
      match.skipLevelChange('player');
      match.skipMove('player');
      // CPUの手番を流す
      match.skipSetCard('cpu');
      match.skipLevelChange('cpu');
      match.skipMove('cpu');
      // プレイヤーのターン開始 → 山札切れ → 疲労
      expect(match.state.isGameOver, isFalse);
      expect(match.state.finishReason, isNull);
      expect(match.state.player.isExhausted, isTrue);
      expect(match.state.player.currentHp, 100 - kExhaustionHpLoss);
    });

    test('安全弁: 高ターン数でHP優位側の勝利に決着', () {
      final match = engine();
      match.state.turnNumber = kMaxTurnSafetyCap + 1;
      match.state.player.currentHp = 80;
      match.state.cpu.currentHp = 40;
      match.beginTurn();
      expect(match.state.isGameOver, isTrue);
      expect(match.state.finishReason, LevelFinishReason.exhaustion);
      expect(match.state.winnerId, 'player');
    });
  });
}
