import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_deck.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_models.dart';
import 'package:one_night_match/src/technique_deck/technique_match_state.dart';

void main() {
  TechniqueDeckDefinition deckWithCards(String prefix, int count) =>
      TechniqueDeckDefinition(
        id: '${prefix}_deck',
        wrestlerId: prefix,
        name: '$prefixのデッキ',
        entries: [
          for (var i = 0; i < count; i++)
            TechniqueDeckEntry(
              instanceId: '${prefix}_card_$i',
              cardId: '${prefix}_card_$i',
              cardType: TechniqueDeckCardType.technique,
            ),
        ],
      );

  TechniqueMatchState freshMatch({
    int deckSizeA = 30,
    int deckSizeB = 30,
    int maxHpA = 100,
    int maxHpB = 100,
    int? startingHpA,
    int? startingHpB,
    int? seed,
  }) => TechniqueMatchEngine.start(
    wrestlerAId: 'wrestler_a',
    wrestlerAName: 'レスラーA',
    wrestlerAMaxHp: maxHpA,
    deckA: deckWithCards('a', deckSizeA),
    wrestlerBId: 'wrestler_b',
    wrestlerBName: 'レスラーB',
    wrestlerBMaxHp: maxHpB,
    deckB: deckWithCards('b', deckSizeB),
    startingHpA: startingHpA,
    startingHpB: startingHpB,
    random: seed != null ? Random(seed) : null,
  );

  group('TechniqueMatchEngine.start', () {
    test('両者とも5枚ドローし、山札は残り25枚になる', () {
      final state = freshMatch(seed: 1);
      expect(state.playerA.hand.length, 5);
      expect(state.playerA.drawPile.length, 25);
      expect(state.playerB.hand.length, 5);
      expect(state.playerB.drawPile.length, 25);
    });

    test('初期状態はプレイヤーA・ターン1・energySetフェーズ', () {
      final state = freshMatch(seed: 1);
      expect(state.activePlayerIndex, 0);
      expect(state.turnNumber, 1);
      expect(state.phase, TechniqueMatchPhase.energySet);
      expect(state.active.wrestlerName, 'レスラーA');
    });

    test('初期HPはmaxHp、posture はstand、HEATは0', () {
      final state = freshMatch(seed: 1);
      expect(state.playerA.hp, state.playerA.maxHp);
      expect(state.playerA.posture, WrestlerPosture.stand);
      expect(state.playerA.heat, 0);
    });

    test('startingHpを指定するとその値になる（maxHpでクランプ）', () {
      final state = freshMatch(startingHpA: 40, seed: 1);
      expect(state.playerA.hp, 40);
      final clamped = freshMatch(startingHpA: 9999, maxHpA: 100, seed: 1);
      expect(clamped.playerA.hp, 100);
    });
  });

  group('TechniqueMatchEngine.goDown / rest', () {
    test('ダウンするとpostureがdownになる', () {
      final state = freshMatch(seed: 1);
      final down = TechniqueMatchEngine.goDown(state);
      expect(down.playerA.posture, WrestlerPosture.down);
    });

    test('スタンド以外の状態でダウンしても変化しない', () {
      final state = freshMatch(seed: 1);
      final down = TechniqueMatchEngine.goDown(state);
      final downAgain = TechniqueMatchEngine.goDown(down);
      expect(downAgain.playerA.posture, WrestlerPosture.down);
      expect(downAgain.log.length, down.log.length); // 変化なし＝ログも増えない
    });

    test('スタンド中は休息できない（状態が変化しない）', () {
      final state = freshMatch(seed: 1);
      final rested = TechniqueMatchEngine.rest(state);
      expect(rested.playerA.hp, state.playerA.hp);
      expect(rested.activePlayerIndex, state.activePlayerIndex);
    });

    test('ダウン中に休息するとHPが回復力分回復し、ターンが終了する', () {
      final state = freshMatch(startingHpA: 50, seed: 1);
      final down = TechniqueMatchEngine.goDown(state);
      final rested = TechniqueMatchEngine.rest(down, random: Random(1));
      expect(rested.playerA.hp, 50 + defaultRecoveryPower);
      // 休息はターン終了を伴うため、手番はBへ移る。
      expect(rested.activePlayerIndex, 1);
    });

    test('休息によるHP回復はmaxHpでクランプされる', () {
      final state = freshMatch(startingHpA: 95, maxHpA: 100, seed: 1);
      final down = TechniqueMatchEngine.goDown(state);
      final rested = TechniqueMatchEngine.rest(down, random: Random(1));
      expect(rested.playerA.hp, 100);
    });
  });

  group('TechniqueMatchEngine.endTurn', () {
    test('ターン終了で手番が相手に移り、ターン数はBの間は変わらない', () {
      final state = freshMatch(seed: 1);
      final ended = TechniqueMatchEngine.endTurn(state, random: Random(1));
      expect(ended.activePlayerIndex, 1);
      expect(ended.turnNumber, 1);
    });

    test('Bのターン終了でAに戻り、ターン数が増える', () {
      final state = freshMatch(seed: 1);
      final afterA = TechniqueMatchEngine.endTurn(state, random: Random(1));
      final afterB = TechniqueMatchEngine.endTurn(afterA, random: Random(1));
      expect(afterB.activePlayerIndex, 0);
      expect(afterB.turnNumber, 2);
    });

    test('ターン終了後、新しいアクティブプレイヤーは1枚ドローする', () {
      final state = freshMatch(seed: 1);
      final ended = TechniqueMatchEngine.endTurn(state, random: Random(1));
      expect(ended.playerB.hand.length, 6); // 初期5枚+ドロー1枚
      expect(ended.playerB.drawPile.length, 24);
    });

    test('ダウンしたままターン終了しても、次の自分のターン開始時にスタンドへ戻る', () {
      final state = freshMatch(seed: 1);
      final down = TechniqueMatchEngine.goDown(state); // Aがダウン
      final afterA = TechniqueMatchEngine.endTurn(down, random: Random(1)); // Bの手番
      final afterB = TechniqueMatchEngine.endTurn(afterA, random: Random(1)); // Aの手番に戻る
      expect(afterB.activePlayerIndex, 0);
      expect(afterB.playerA.posture, WrestlerPosture.stand);
    });

    test('山札を使い切ると、そのドローで残り山札は0になる', () {
      // 山札を6枚（初期手札5枚+1枚）にすると、次の1ドローで山札が尽きる。
      final state = freshMatch(deckSizeA: 6, seed: 1);
      expect(state.playerA.drawPile.length, 1);
      final afterB = TechniqueMatchEngine.endTurn(state, random: Random(1));
      final afterA = TechniqueMatchEngine.endTurn(afterB, random: Random(1));
      expect(afterA.playerA.drawPile.length, 0);
      expect(afterA.playerA.hand.length, 6);
    });

    test('山札が0でも捨て札があれば再シャッフルして引ける（仕様書13章）', () {
      final base = freshMatch(seed: 1);
      final customA = base.playerA.copyWith(
        drawPile: const [],
        discardPile: const [
          TechniqueDeckEntry(
            instanceId: 'discarded_1',
            cardId: 'card_x',
            cardType: TechniqueDeckCardType.technique,
          ),
        ],
      );
      // Bを手番にしてendTurnすると、次の手番であるAの開始処理でドローが走る。
      final customState = base.copyWith(playerA: customA, activePlayerIndex: 1);
      final result = TechniqueMatchEngine.endTurn(customState, random: Random(2));
      expect(result.playerA.discardPile, isEmpty);
      expect(result.playerA.drawPile, isEmpty); // 1枚を再シャッフルして即ドローした
      expect(result.playerA.hand.length, customA.hand.length + 1);
    });

    test('山札・捨て札とも空ならドローできず手札は変化しない（無限ループにならない）', () {
      final base = freshMatch(seed: 1);
      final customA = base.playerA.copyWith(
        drawPile: const [],
        discardPile: const [],
      );
      final customState = base.copyWith(playerA: customA, activePlayerIndex: 1);
      final result = TechniqueMatchEngine.endTurn(customState, random: Random(2));
      expect(result.playerA.hand.length, customA.hand.length);
    });
  });

  group('TechniqueMatchPlayerState.copyWith', () {
    test('未指定のフィールドは既存値を保持する', () {
      const player = TechniqueMatchPlayerState(
        wrestlerId: 'w1',
        wrestlerName: 'テスト',
        maxHp: 100,
        hp: 80,
        heat: 5,
        posture: WrestlerPosture.down,
        recoveryPower: 20,
      );
      final updated = player.copyWith(hp: 90);
      expect(updated.hp, 90);
      expect(updated.heat, 5);
      expect(updated.posture, WrestlerPosture.down);
      expect(updated.wrestlerId, 'w1');
    });
  });
}
