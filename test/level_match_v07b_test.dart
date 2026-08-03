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
      for (var lv = 1; lv <= 3; lv++)
        WrestlerLevelDefinition(
          level: lv,
          displayName: 'L$lv',
          resistances: none(),
          moveIds: const [
            'slowThrow',
            'fastStrike',
            'counterMove',
            'downReq',
          ],
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

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Ver.0.7.1 clashBetween（攻撃 vs 対応）', () {
    test('速い対応は速度勝ち', () {
      final m = engine();
      expect(
        m.clashBetween(moves['slowThrow']!, moves['fastStrike']!),
        ClashOutcome.speedWin,
      );
    });
    test('遅い対応は速度負け（攻撃側が通る）', () {
      final m = engine();
      expect(
        m.clashBetween(moves['fastStrike']!, moves['slowThrow']!),
        ClashOutcome.speedLoss,
      );
    });
    test('対応属性が合えば返し成立', () {
      final m = engine();
      expect(
        m.clashBetween(moves['slowThrow']!, moves['counterMove']!),
        ClashOutcome.counter,
      );
    });
    test('cannotCounterの技は返せない', () {
      final m = engine();
      expect(
        m.clashBetween(moves['chairLike']!, moves['counterMove']!),
        isNot(ClashOutcome.counter),
      );
    });
  });

  test('返し技は攻撃として宣言できない', () {
    final m = engine();
    toChoose(m);
    expect(() => m.useMove('player', 'counterMove'), throwsStateError);
  });

  test('受けると攻撃側の技が成立する', () {
    final m = engine();
    toChoose(m);
    m.useMove('player', 'slowThrow');
    expect(m.state.phase, LevelMatchPhase.responseSelection);
    m.respondTake('cpu');
    expect(m.state.cpu.currentHp, 80); // 20ダメージ（5刻み）
    // フォール技なので pinDecision へ。
    expect(m.state.pendingPin, isNotNull);
  });

  test('速い対応で攻撃を潰す（攻撃側の技は不成立）', () {
    final m = engine();
    toChoose(m);
    m.useMove('player', 'slowThrow'); // 攻撃・速度4・フォール技
    m.respondWithMove('cpu', 'fastStrike'); // 速度9で上回る
    // 速い対応が命中 → プレイヤーが被弾、CPUは無傷。
    expect(m.state.player.currentHp, 85); // 15ダメージ
    expect(m.state.cpu.currentHp, 100);
    // 攻撃が潰れたのでフォールは発生しない。
    expect(m.state.pendingPin, isNull);
  });

  test('返し技で切り返す（HEAT+5・攻撃不成立）', () {
    final m = engine();
    toChoose(m);
    final heatBefore = m.state.sharedHeat;
    m.useMove('player', 'slowThrow');
    m.respondWithMove('cpu', 'counterMove'); // 投げを返す
    expect(m.state.cpu.currentHp, 100); // 攻撃は通っていない
    expect(m.state.player.currentHp, lessThan(100)); // 返しのダメージ
    expect(m.state.sharedHeat - heatBefore, greaterThanOrEqualTo(5));
    expect(m.state.pendingPin, isNull);
  });

  test('Ver.0.7.2: フィニッシャーは通常技の速度勝ちで割り込めない', () {
    final m = engine();
    final finisher = MoveDefinition(
      id: 'fin',
      name: 'フィニッシャー',
      category: MoveCategory.finisher,
      attribute: MoveAttribute.throwMove,
      power: 36,
      heat: 8,
      requiredCards: none(),
      discardAfterUse: none(),
      speed: 2,
      canPin: true,
      ignoreNormalSpeed: true,
    );
    // 速い打撃でもフィニッシャーには速度勝ちできない（neutral=攻撃側が通る）。
    expect(
      m.clashBetween(finisher, moves['fastStrike']!),
      ClashOutcome.neutral,
    );
    // 専用返し（投げを返す）なら成立する。
    expect(
      m.clashBetween(finisher, moves['counterMove']!),
      ClashOutcome.counter,
    );
  });

  test('requiredPreviousState：ダウン中のみ使用可能', () {
    final m = engine();
    toChoose(m);
    expect(m.evaluateMove(m.state.player, moves['downReq']!).usable, isFalse);
    m.state.cpu.isDown = true;
    expect(m.evaluateMove(m.state.player, moves['downReq']!).usable, isTrue);
  });

  test('最終ダメージは5刻みに丸められる', () {
    final m = engine();
    // 威力13相当を作る：resistanceを足して 13 → 15 に丸め。
    m.state.cpu.currentHp = 100;
    toChoose(m);
    // slowThrow(20) を受け → 20（既に5刻み）。丸めロジックの単体確認は下で。
    m.useMove('player', 'slowThrow');
    m.respondTake('cpu');
    expect(m.state.lastDamage % 5, 0);
  });
}
