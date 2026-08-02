import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/level_match/level_match_engine.dart';
import 'package:one_night_match/src/level_match/level_match_screens.dart';
import 'package:one_night_match/src/wrestler_editor/defaults.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart';
import 'package:one_night_match/src/wrestler_editor/repository.dart';
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
    'jab': MoveDefinition(
      id: 'jab',
      name: 'ジャブ',
      category: MoveCategory.normal,
      attribute: MoveAttribute.strike,
      power: 15,
      heat: 2,
      requiredCards: cards(strike: 1),
      discardAfterUse: cards(),
    ),
    'combo': MoveDefinition(
      id: 'combo',
      name: 'コンビネーション',
      category: MoveCategory.normal,
      attribute: MoveAttribute.throwMove,
      power: 20,
      heat: 3,
      requiredCards: cards(strike: 1, throwMove: 1),
      discardAfterUse: cards(),
    ),
    'fin': MoveDefinition(
      id: 'fin',
      name: '必殺技',
      category: MoveCategory.finisher,
      attribute: MoveAttribute.throwMove,
      power: 30,
      heat: 5,
      requiredCards: cards(throwMove: 2),
      discardAfterUse: cards(throwMove: 1),
      usageLimit: 1,
      markUsedAfterUse: true,
    ),
    'future': MoveDefinition(
      id: 'future',
      name: '未来技',
      category: MoveCategory.normal,
      attribute: MoveAttribute.aerial,
      power: 10,
      heat: 1,
      requiredCards: cards(),
      discardAfterUse: cards(),
      conditions: const [RuleCondition(type: 'futureCondition')],
    ),
  };

  WrestlerLevelDefinition level(
    int number, {
    List<String> moveIds = const ['jab', 'combo'],
    String? finisher,
    UnlockConditionGroup? unlock,
    Map<MoveAttribute, int>? resistances,
  }) => WrestlerLevelDefinition(
    level: number,
    displayName: 'Level $number',
    unlockCondition: unlock,
    resistances: resistances ?? cards(strike: 5, throwMove: 10),
    moveIds: moveIds,
    finisherId: finisher,
  );

  WrestlerDefinition wrestler(
    String id, {
    List<WrestlerLevelDefinition>? levels,
  }) => WrestlerDefinition(
    id: id,
    name: id,
    subtitle: 'test',
    type: EditorWrestlerType.babyface,
    maxHp: 100,
    themeColor: '#E91E63',
    levels:
        levels ??
        [
          level(1),
          level(
            2,
            unlock: const UnlockConditionGroup(
              operator: ConditionOperator.and,
              conditions: [
                UnlockCondition(
                  type: UnlockConditionType.heatAtLeast,
                  value: 10,
                ),
              ],
            ),
          ),
          level(
            3,
            finisher: 'fin',
            unlock: const UnlockConditionGroup(
              operator: ConditionOperator.and,
              conditions: [
                UnlockCondition(
                  type: UnlockConditionType.previousLevelUnlocked,
                ),
                UnlockCondition(
                  type: UnlockConditionType.turnAtLeast,
                  value: 3,
                ),
              ],
            ),
          ),
        ],
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  LevelMatchEngine engine() => LevelMatchEngine.create(
    playerWrestler: wrestler('playerWrestler'),
    cpuWrestler: wrestler('cpuWrestler'),
    moves: moves,
    random: Random(1),
    playerStarts: true,
  );

  TechniqueResourceCard addHand(
    LevelMatchEngine match,
    MoveAttribute attribute,
    String id,
  ) {
    final card = TechniqueResourceCard(id, attribute);
    match.state.player.hand.add(card);
    return card;
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('技カードセット', () {
    test('手札から1枚だけセットできる', () {
      final match = engine();
      final card = addHand(match, MoveAttribute.strike, 'manual');
      match.setTechniqueCard('player', card.instanceId);
      expect(match.state.player.setCards, contains(card));
      expect(
        () => match.setTechniqueCard(
          'player',
          match.state.player.hand.first.instanceId,
        ),
        throwsStateError,
      );
    });

    test('6枚上限と7枚目交換', () {
      final match = engine();
      match.state.player.setCards.addAll([
        for (var i = 0; i < 6; i++)
          TechniqueResourceCard('set$i', MoveAttribute.strike),
      ]);
      final card = addHand(match, MoveAttribute.throwMove, 'seventh');
      expect(
        () => match.setTechniqueCard('player', card.instanceId),
        throwsStateError,
      );
      match.setTechniqueCard(
        'player',
        card.instanceId,
        replaceInstanceId: 'set0',
      );
      expect(match.state.player.setCards, hasLength(6));
      expect(match.state.player.setReplacementCount, 1);
    });

    test('レベル変更後もセット状態を維持', () {
      final match = engine();
      final card = addHand(match, MoveAttribute.strike, 'keep');
      match.setTechniqueCard('player', card.instanceId);
      match.state.player.unlockedLevels.add(2);
      match.changeLevel('player', 2);
      expect(match.state.player.setCards.single.instanceId, 'keep');
      expect(match.state.phase, LevelMatchPhase.chooseMove);
    });
  });

  group('技使用可否', () {
    test('必要カード、複数属性、1枚不足を判定', () {
      final match = engine();
      final actor = match.state.player;
      actor.setCards.add(
        const TechniqueResourceCard('s', MoveAttribute.strike),
      );
      expect(match.evaluateMove(actor, moves['jab']!).usable, isTrue);
      expect(match.evaluateMove(actor, moves['combo']!).usable, isFalse);
      actor.setCards.add(
        const TechniqueResourceCard('t', MoveAttribute.throwMove),
      );
      expect(match.evaluateMove(actor, moves['combo']!).usable, isTrue);
    });

    test('現在レベル外、未対応条件、使用済みフィニッシャーを禁止', () {
      final match = engine();
      final actor = match.state.player;
      actor.setCards.addAll([
        const TechniqueResourceCard('t1', MoveAttribute.throwMove),
        const TechniqueResourceCard('t2', MoveAttribute.throwMove),
      ]);
      expect(match.evaluateMove(actor, moves['fin']!).usable, isFalse);
      expect(
        match.evaluateMove(actor, moves['future']!).reasons.join(),
        contains('未対応'),
      );
      actor.currentLevel = 3;
      actor.finisherUsed = true;
      expect(match.evaluateMove(actor, moves['fin']!).usable, isFalse);
    });

    test('破棄カード不足を禁止', () {
      final match = engine();
      final actor = match.state.player..currentLevel = 3;
      actor.setCards.addAll([
        const TechniqueResourceCard('t1', MoveAttribute.throwMove),
        const TechniqueResourceCard('t2', MoveAttribute.throwMove),
      ]);
      expect(match.evaluateMove(actor, moves['fin']!).usable, isTrue);
      actor.setCards.removeLast();
      expect(match.evaluateMove(actor, moves['fin']!).usable, isFalse);
    });
  });

  group('ダメージ・HEAT・フィニッシャー', () {
    test('属性耐性を引き最低0、HPは0未満にならない', () {
      final match = engine();
      final actor = match.state.player;
      actor.setCards.add(
        const TechniqueResourceCard('s', MoveAttribute.strike),
      );
      match.skipSetCard('player');
      match.skipLevelChange('player');
      match.useMove('player', 'jab');
      expect(match.state.cpu.currentHp, 90);
      expect(match.state.sharedHeat, 3);

      final zeroMove = MoveDefinition(
        id: 'zero',
        name: 'zero',
        category: MoveCategory.normal,
        attribute: MoveAttribute.strike,
        power: 1,
        heat: 0,
        requiredCards: cards(),
        discardAfterUse: cards(),
      );
      final second = engine();
      second.moves['zero'] = zeroMove;
      final oldLevel = second.state.player.wrestler.levels.first;
      final custom = wrestler(
        'custom',
        levels: [
          level(1, moveIds: const ['zero']),
          ...second.state.player.wrestler.levels.skip(1),
        ],
      );
      final customEngine = LevelMatchEngine.create(
        playerWrestler: custom,
        cpuWrestler: wrestler('cpu'),
        moves: {...moves, 'zero': zeroMove},
        playerStarts: true,
      );
      customEngine.skipSetCard('player');
      customEngine.skipLevelChange('player');
      customEngine.useMove('player', 'zero');
      expect(customEngine.state.lastDamage, 0);
      expect(oldLevel.level, 1);
    });

    test('フィニッシャーは破棄・使用済み・HEATボーナス・2回目禁止', () {
      final match = engine();
      final actor = match.state.player
        ..currentLevel = 3
        ..setCards.addAll([
          const TechniqueResourceCard('t1', MoveAttribute.throwMove),
          const TechniqueResourceCard('t2', MoveAttribute.throwMove),
        ]);
      match.skipSetCard('player');
      match.skipLevelChange('player');
      match.useMove('player', 'fin');
      expect(actor.finisherUsed, isTrue);
      expect(actor.setCards, hasLength(1));
      expect(match.state.sharedHeat, 9);
      expect(match.evaluateMove(actor, moves['fin']!).usable, isFalse);
    });
  });

  group('レベル解放・変更', () {
    test('HP・HEAT・ターン・属性回数・previousLevelを評価', () {
      final custom = wrestler(
        'conditions',
        levels: [
          level(1),
          level(
            2,
            unlock: const UnlockConditionGroup(
              operator: ConditionOperator.and,
              conditions: [
                UnlockCondition(type: UnlockConditionType.hpAtMost, value: 50),
                UnlockCondition(
                  type: UnlockConditionType.heatAtLeast,
                  value: 10,
                ),
                UnlockCondition(
                  type: UnlockConditionType.turnAtLeast,
                  value: 2,
                ),
                UnlockCondition(
                  type: UnlockConditionType.attributeSuccessAtLeast,
                  value: 1,
                  attribute: MoveAttribute.strike,
                ),
              ],
            ),
          ),
          level(
            3,
            unlock: const UnlockConditionGroup(
              operator: ConditionOperator.and,
              conditions: [
                UnlockCondition(
                  type: UnlockConditionType.previousLevelUnlocked,
                ),
              ],
            ),
          ),
        ],
      );
      final match = LevelMatchEngine.create(
        playerWrestler: custom,
        cpuWrestler: wrestler('cpu'),
        moves: moves,
        playerStarts: true,
      );
      final actor = match.state.player
        ..currentHp = 50
        ..attributeSuccessCounts[MoveAttribute.strike] = 1;
      match.state.sharedHeat = 10;
      match.state.turnNumber = 2;
      expect(
        match.evaluateUnlockCondition(actor, custom.levels[1]).satisfied,
        isTrue,
      );
      actor.unlockedLevels.add(2);
      expect(
        match.evaluateUnlockCondition(actor, custom.levels[2]).satisfied,
        isTrue,
      );
    });

    test('OR条件、永続解放、未対応条件を安全側で禁止', () {
      final match = engine();
      final actor = match.state.player;
      final orLevel = level(
        2,
        unlock: const UnlockConditionGroup(
          operator: ConditionOperator.or,
          conditions: [
            UnlockCondition(type: UnlockConditionType.heatAtLeast, value: 999),
            UnlockCondition(type: UnlockConditionType.hpAtLeast, value: 1),
          ],
        ),
      );
      expect(match.evaluateUnlockCondition(actor, orLevel).satisfied, isTrue);
      actor.unlockedLevels.add(2);
      actor.currentHp = 0;
      match.evaluateUnlocks(actor);
      expect(actor.unlockedLevels, contains(2));
      final unsupported = level(
        3,
        unlock: const UnlockConditionGroup(
          operator: ConditionOperator.or,
          conditions: [UnlockCondition(type: UnlockConditionType.bleeding)],
        ),
      );
      final evaluation = match.evaluateUnlockCondition(actor, unsupported);
      expect(evaluation.supported, isFalse);
      expect(evaluation.satisfied, isFalse);
    });

    test('解放済みへ1回変更、未解放は禁止、下位へ戻れる', () {
      final match = engine();
      final actor = match.state.player..unlockedLevels.add(2);
      match.skipSetCard('player');
      match.changeLevel('player', 2);
      expect(actor.currentLevel, 2);
      expect(match.state.phase, LevelMatchPhase.chooseMove);
      expect(() => match.changeLevel('player', 3), throwsStateError);
      match.state.phase = LevelMatchPhase.levelChange;
      actor.levelChangeUsedThisTurn = false;
      match.changeLevel('player', 1);
      expect(actor.currentLevel, 1);
    });
  });

  test('試合JSON往復相当・壊れた履歴を1件だけ無視', () async {
    final match = engine();
    final json = jsonEncode(match.state.toJson());
    expect(jsonDecode(json)['game']['version'], '0.6');
    SharedPreferences.setMockInitialValues({
      LevelMatchHistoryStore.key: ['broken', json],
    });
    final loaded = await LevelMatchHistoryStore().load();
    expect(loaded, hasLength(1));
    expect((loaded.single['game'] as Map)['mode'], 'levelCardMatch');
  });

  testWidgets('新ルール説明からレスラー選択画面を開ける', (tester) async {
    SharedPreferences.setMockInitialValues({
      LocalWrestlerRepository.storageKey: jsonEncode(
        defaultEditorWrestlers.map((item) => item.toJson()).toList(),
      ),
    });
    await tester.pumpWidget(const MaterialApp(home: LevelMatchIntroScreen()));
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pump();
    expect(find.text('レスラーを選ぶ'), findsOneWidget);
    await tester.tap(find.text('レスラーを選ぶ'));
    await tester.pumpAndSettle();
    expect(find.text('Ver.0.6 レスラー選択'), findsOneWidget);
    expect(find.text('火神アカリ'), findsOneWidget);
    expect(find.text('✓ 対戦可能'), findsWidgets);
  });
}
