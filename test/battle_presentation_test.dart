import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/level_match/battle_presentation.dart';
import 'package:one_night_match/src/level_match/level_match_engine.dart';
import 'package:one_night_match/src/wrestler_editor/defaults.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final moves = {for (final m in defaultEditorMoves) m.id: m};
  WrestlerDefinition byId(String id) =>
      defaultEditorWrestlers.firstWhere((w) => w.id == id);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  LevelMatchEngine engine() => LevelMatchEngine.create(
        playerWrestler: byId('wrestler_akari'),
        cpuWrestler: byId('wrestler_misaki'),
        moves: moves,
        random: Random(1),
        playerStarts: true,
      );

  LevelMatchLogEntry log(
    String action,
    String message, {
    Map<String, dynamic> details = const {},
    String playerId = 'player',
  }) =>
      LevelMatchLogEntry(
        turn: 1,
        playerId: playerId,
        phase: 'test',
        action: action,
        message: message,
        details: details,
      );

  test('attackDeclared: 通常の固有技は宣言ビートのみ（カットイン無し）', () {
    final e = engine();
    final logs = [
      log('attackDeclared', 'x', details: {'moveId': 'akari_dropkick'}),
    ];
    final events = const BattleEventQueue().build(logs, e.state, moves);
    expect(events, hasLength(1));
    expect(events.single.kind, BattleBeatKind.announce);
    expect(events.single.text, contains('紅蓮ドロップキック'));
  });

  test('attackDeclared: フィニッシャーはカットイン→宣言の2ビート', () {
    final e = engine();
    final logs = [
      log('attackDeclared', 'x', details: {'moveId': 'high_speed_german'}),
    ];
    final events = const BattleEventQueue().build(logs, e.state, moves);
    expect(events, hasLength(2));
    expect(events.first.kind, BattleBeatKind.finisherCutin);
    expect(events.first.text, 'ハイスピード・ジャーマン');
    expect(events.last.kind, BattleBeatKind.announce);
  });

  test('clashResolution: outcomeごとにテキストと効果音が変わる', () {
    final e = engine();
    final counterEvents = const BattleEventQueue().build(
      [log('clashResolution', 'x', details: {'outcome': 'counter'})],
      e.state,
      moves,
    );
    expect(counterEvents.single.text, contains('返し成立'));
    expect(counterEvents.single.se, isNotNull);

    final speedLossEvents = const BattleEventQueue().build(
      [log('clashResolution', 'x', details: {'outcome': 'speedLoss'})],
      e.state,
      moves,
    );
    expect(speedLossEvents.single.text, contains('速度負け'));
    expect(speedLossEvents.single.se, isNull);
  });

  test('moveResolved: ヒット+ダメージのビートとHEATのビートに分割される', () {
    final e = engine();
    final events = const BattleEventQueue().build(
      [
        log('moveResolved', 'x', details: {
          'finalDamage': 20,
          'heatDelta': 3,
          'moveAttribute': 'strike',
          'isCounter': false,
        }),
      ],
      e.state,
      moves,
    );
    expect(events, hasLength(2));
    expect(events[0].kind, BattleBeatKind.hit);
    expect(events[0].text, contains('20ダメージ'));
    expect(events[1].kind, BattleBeatKind.heat);
    expect(events[1].text, contains('HEAT +3'));
  });

  test('moveResolved: HEAT増加が0のときはHEATビートを省略する', () {
    final e = engine();
    final events = const BattleEventQueue().build(
      [
        log('moveResolved', 'x', details: {
          'finalDamage': 5,
          'heatDelta': 0,
          'moveAttribute': 'strike',
          'isCounter': false,
        }),
      ],
      e.state,
      moves,
    );
    expect(events, hasLength(1));
  });

  test('pinAttempt→kickOut: フォール宣言→ONE→TWO→TH...→キックアウトの5ビート', () {
    final e = engine();
    final events = const BattleEventQueue().build(
      [
        log('pinAttempt', 'x'),
        log('kickOut', 'x'),
      ],
      e.state,
      moves,
    );
    expect(events.map((ev) => ev.kind).toList(), [
      BattleBeatKind.pinDeclare,
      BattleBeatKind.pinCount,
      BattleBeatKind.pinCount,
      BattleBeatKind.pinCount,
      BattleBeatKind.kickOutResult,
    ]);
  });

  test('pinAttempt→threeCount: フォール宣言→ONE→TWO→THREE→3カウントの5ビート', () {
    final e = engine();
    final events = const BattleEventQueue().build(
      [
        log('pinAttempt', 'x'),
        log('threeCount', 'x'),
      ],
      e.state,
      moves,
    );
    expect(events.map((ev) => ev.kind).toList(), [
      BattleBeatKind.pinDeclare,
      BattleBeatKind.pinCount,
      BattleBeatKind.pinCount,
      BattleBeatKind.pinCount,
      BattleBeatKind.pinResult,
    ]);
    expect(events.last.text, contains('3カウント'));
  });

  test('未知のログアクションは無視される（例外にならない）', () {
    final e = engine();
    final events = const BattleEventQueue().build(
      [log('someFutureAction', 'x')],
      e.state,
      moves,
    );
    expect(events, isEmpty);
  });
}
