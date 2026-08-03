import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/level_match/level_match_engine.dart';
import 'package:one_night_match/src/wrestler_editor/defaults.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final moves = {for (final m in defaultEditorMoves) m.id: m};

  LevelMatchEngine engine() => LevelMatchEngine.create(
    playerWrestler: defaultEditorWrestlers[0],
    cpuWrestler: defaultEditorWrestlers[1],
    moves: moves,
    random: Random(3),
    playerStarts: true,
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Ver.0.7 データ構造', () {
    test('新フィールドがJSON往復する', () {
      final move = MoveDefinition(
        id: 'x',
        name: 'テスト技',
        category: MoveCategory.normal,
        attribute: MoveAttribute.throwMove,
        power: 20,
        heat: 3,
        requiredCards: {MoveAttribute.throwMove: 2},
        discardAfterUse: {},
        speed: 4,
        canPin: true,
        canKO: true,
        counterTypes: const [MoveAttribute.throwMove],
        cannotCounterTypes: const [MoveAttribute.strike],
        specialAbilities: const ['cannotRopeBreak', 'highAngle'],
        causesDownFlag: true,
        consumesSetCards: true,
      );
      final restored = MoveDefinition.fromJson(
        Map<String, dynamic>.from(move.toJson()),
      );
      expect(restored.speed, 4);
      expect(restored.canPin, isTrue);
      expect(restored.counterTypes, [MoveAttribute.throwMove]);
      expect(restored.cannotCounterTypes, [MoveAttribute.strike]);
      expect(restored.specialAbilities, contains('highAngle'));
      expect(restored.causesDown, isTrue);
    });

    test('未知フィールドを無視し、旧データは speed 既定値5', () {
      final legacy = {
        'id': 'old',
        'name': '旧技',
        'category': 'normal',
        'attribute': 'strike',
        'power': 10,
        'heat': 2,
        'requiredCards': {'strike': 1},
        'discardAfterUse': {},
        'unknownFuture': 999,
      };
      final move = MoveDefinition.fromJson(legacy);
      expect(move.speed, 5);
      expect(move.consumesSetCards, isTrue);
    });
  });

  group('Ver.0.7 単体技', () {
    test('単体技カタログが全属性そろい、決着不可', () {
      expect(defaultBasicMoves, isNotEmpty);
      for (final m in defaultBasicMoves) {
        expect(m.isBasic, isTrue);
        expect(m.offersPin, isFalse);
        expect(m.offersSubmission, isFalse);
        expect(m.causesDown, isFalse);
      }
      // 主要属性の単体技が引ける。
      expect(basicMoveIdByAttribute[MoveAttribute.strike], isNotNull);
      expect(basicMoveIdByAttribute[MoveAttribute.throwMove], isNotNull);
    });

    test('固有技（投げ）はフォール可能', () {
      final brainbuster = moves['brainbuster']!;
      expect(brainbuster.isBasic, isFalse);
      expect(brainbuster.offersPin, isTrue);
    });

    test('手札から単体技を使うと手札消費・ダメージ・ターン移行', () {
      final match = engine();
      match.skipSetCard('player');
      match.skipLevelChange('player');
      final handBefore = match.state.player.hand.length;
      final cpuHpBefore = match.state.cpu.currentHp;
      // ダメージが確実に通る投げ属性のカードを優先（無ければ先頭）。
      final card = match.state.player.hand.firstWhere(
        (c) => c.attribute == MoveAttribute.throwMove,
        orElse: () => match.state.player.hand.first,
      );
      match.useBasicMove('player', card.instanceId);
      match.respondTake('cpu');
      expect(match.state.player.hand.length, handBefore - 1);
      expect(match.state.cpu.currentHp, lessThanOrEqualTo(cpuHpBefore));
      // 単体技は決着を発生させない → 相手ターンへ。
      expect(match.state.pendingPin, isNull);
      expect(match.state.pendingSubmission, isNull);
      expect(match.state.activePlayerId, 'cpu');
      expect(match.state.player.lastUsedMoveName, isNotNull);
      expect(match.state.player.lastUsedWasBasic, isTrue);
    });
  });
}
