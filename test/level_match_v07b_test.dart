import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/level_match/level_match_engine.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Map<MoveAttribute, int> none() => {
    for (final a in MoveAttribute.values) a: 0,
  };

  MoveDefinition mv(
    String id,
    MoveAttribute attr,
    int power,
    int speed, {
    MoveCategory category = MoveCategory.normal,
    bool pin = false,
    List<MoveAttribute> counterTypes = const [],
    List<String> specialAbilities = const [],
    String? requiredPreviousState,
  }) => MoveDefinition(
    id: id,
    name: id,
    category: category,
    attribute: attr,
    power: power,
    heat: 2,
    requiredCards: none(),
    discardAfterUse: none(),
    speed: speed,
    canPin: pin,
    counterTypes: counterTypes,
    specialAbilities: specialAbilities,
    requiredPreviousState: requiredPreviousState,
  );

  final moves = <String, MoveDefinition>{
    'slowThrow': mv('slowThrow', MoveAttribute.throwMove, 20, 4, pin: true),
    'fastStrike': mv('fastStrike', MoveAttribute.strike, 15, 9),
    'counterMove': mv(
      'counterMove',
      MoveAttribute.counter,
      18,
      10,
      category: MoveCategory.counter,
      counterTypes: [MoveAttribute.throwMove],
    ),
    'chairLike': mv(
      'chairLike',
      MoveAttribute.rough,
      25,
      3,
      specialAbilities: ['cannotCounter'],
    ),
    'downReq': mv(
      'downReq',
      MoveAttribute.strike,
      12,
      7,
      requiredPreviousState: 'down',
    ),
  };

  WrestlerDefinition wrestler(String id) => WrestlerDefinition(
    id: id,
    name: id,
    subtitle: 't',
    type: EditorWrestlerType.babyface,
    maxHp: 100,
    themeColor: '#E91E63',
    levels: [
      WrestlerLevelDefinition(
        level: 1,
        displayName: 'L1',
        resistances: none(),
        moveIds: const [
          'slowThrow',
          'fastStrike',
          'counterMove',
          'downReq',
        ],
      ),
      WrestlerLevelDefinition(
        level: 2,
        displayName: 'L2',
        resistances: none(),
        moveIds: const ['slowThrow'],
      ),
      WrestlerLevelDefinition(
        level: 3,
        displayName: 'L3',
        resistances: none(),
        moveIds: const ['slowThrow'],
      ),
    ],
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  LevelMatchEngine engine() => LevelMatchEngine.create(
    playerWrestler: wrestler('player'),
    cpuWrestler: wrestler('cpu'),
    moves: moves,
    random: Random(5),
    playerStarts: true,
  );

  void toChoose(LevelMatchEngine m) {
    m.skipSetCard('player');
    m.skipLevelChange('player');
  }

  void setOpponentLast(LevelMatchEngine m, String id) {
    final move = moves[id]!;
    m.state.cpu
      ..lastUsedMoveId = id
      ..lastUsedMoveName = move.name
      ..lastUsedMoveSpeed = move.speed;
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('速度勝ち：速い技が上回る', () {
    final m = engine();
    setOpponentLast(m, 'slowThrow'); // speed 4
    expect(
      m.clashOutcome(m.state.player, moves['fastStrike']!),
      ClashOutcome.speedWin,
    );
  });

  test('速度負け：遅い技は威力半減・決着不可', () {
    final m = engine();
    setOpponentLast(m, 'fastStrike'); // speed 9
    toChoose(m);
    expect(
      m.clashOutcome(m.state.player, moves['slowThrow']!),
      ClashOutcome.speedLoss,
    );
    m.useMove('player', 'slowThrow'); // power20 → 半減10
    expect(m.state.cpu.currentHp, 90);
    // 決着（フォール）は発生しない。
    expect(m.state.pendingPin, isNull);
    expect(m.state.phase, isNot(LevelMatchPhase.pinDecision));
  });

  test('返し成立：投げ技を返し技で切り返す', () {
    final m = engine();
    setOpponentLast(m, 'slowThrow'); // throwMove
    toChoose(m);
    expect(
      m.clashOutcome(m.state.player, moves['counterMove']!),
      ClashOutcome.counter,
    );
    final heatBefore = m.state.sharedHeat;
    m.useMove('player', 'counterMove');
    // 相手の前ターン技がリセットされる。
    expect(m.state.cpu.lastUsedMoveId, isNull);
    // 返しHEATボーナス（+5）が乗る。
    expect(m.state.sharedHeat - heatBefore, greaterThanOrEqualTo(5));
  });

  test('カウンター不可の技は返せない', () {
    final m = engine();
    setOpponentLast(m, 'chairLike'); // specialAbilities cannotCounter
    expect(
      m.clashOutcome(m.state.player, moves['counterMove']!),
      isNot(ClashOutcome.counter),
    );
  });

  test('requiredPreviousState：ダウン中のみ使用可能', () {
    final m = engine();
    toChoose(m);
    expect(m.evaluateMove(m.state.player, moves['downReq']!).usable, isFalse);
    m.state.cpu.isDown = true;
    expect(m.evaluateMove(m.state.player, moves['downReq']!).usable, isTrue);
  });
}
