import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_deck.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_models.dart';
import 'package:one_night_match/src/technique_deck/technique_match_state.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart' show MoveAttribute;

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
      // Phase 8.5A: ダウンは技によってのみ発生する仕様のため、goDown()は
      // 廃止済み。ここでは技成立を経由せず、状態遷移のテストとして
      // 直接ダウン状態を作る。
      final down = state.copyWith(
        playerA: state.playerA.copyWith(posture: WrestlerPosture.down),
      );
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
      expect(result.playerA.reshuffleCount, 1);
    });

    test(
      '山札再構築の上限（maxDeckReshuffles）に達した状態でさらに山札が尽きると'
      '時間切れ引き分けになる',
      () {
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
          reshuffleCount: maxDeckReshuffles, // 既に上限まで再構築済み
        );
        final customState = base.copyWith(playerA: customA, activePlayerIndex: 1);
        final result = TechniqueMatchEngine.endTurn(customState, random: Random(2));
        expect(result.isDraw, isTrue);
        expect(result.winnerIndex, isNull);
        expect(result.winReason, contains('時間切れ'));
        expect(result.isOver, isTrue);
        // ドローは行われない（手札・山札・捨て札とも変化しない）。
        expect(result.playerA.hand, customA.hand);
        expect(result.playerA.discardPile, customA.discardPile);
      },
    );

    test('上限未満の再構築ならドローが行われ、時間切れにはならない', () {
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
        reshuffleCount: maxDeckReshuffles - 1, // まだ1回余裕がある
      );
      final customState = base.copyWith(playerA: customA, activePlayerIndex: 1);
      final result = TechniqueMatchEngine.endTurn(customState, random: Random(2));
      expect(result.isDraw, isFalse);
      expect(result.playerA.reshuffleCount, maxDeckReshuffles);
      expect(result.playerA.hand.length, customA.hand.length + 1);
    });

    test('試合終了後（時間切れ引き分け）はendTurnが無効化される', () {
      final base = freshMatch(seed: 1);
      final draw = base.copyWith(isDraw: true, winReason: '時間切れ引き分け（テスト）');
      expect(TechniqueMatchEngine.endTurn(draw), same(draw));
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

  group('Phase 4: エネルギーセット・技の使用', () {
    TechniqueDeckCardCatalog catalog() => const TechniqueDeckCardCatalog(
      techniques: [
        TechniqueDeckTechniqueCard(
          id: 'normal_strike',
          name: '通常打撃技',
          category: TechniqueCardCategory.normal,
          attribute: MoveAttribute.strike,
          attackEnergyCost: {MoveAttribute.strike: 1},
          power: 10,
          heatDelta: 5,
          causesDown: true,
        ),
        TechniqueDeckTechniqueCard(
          id: 'down_only',
          name: 'ダウン限定技',
          category: TechniqueCardCategory.normal,
          attribute: MoveAttribute.strike,
          targetState: TechniqueTargetState.down,
          power: 15,
        ),
        TechniqueDeckTechniqueCard(
          id: 'stand_only',
          name: 'スタンド限定技',
          category: TechniqueCardCategory.normal,
          attribute: MoveAttribute.strike,
          targetState: TechniqueTargetState.stand,
          power: 5,
        ),
        TechniqueDeckTechniqueCard(
          id: 'sig_akari',
          name: '固有技（アカリ専用）',
          category: TechniqueCardCategory.signature,
          attribute: MoveAttribute.strike,
          allowedWrestlerIds: ['wrestler_a'],
          minimumLevel: 1,
          power: 20,
        ),
        TechniqueDeckTechniqueCard(
          id: 'lv2_move',
          name: 'レベル2技',
          category: TechniqueCardCategory.normal,
          attribute: MoveAttribute.strike,
          minimumLevel: 2,
          power: 30,
        ),
        TechniqueDeckTechniqueCard(
          id: 'lethal_move',
          name: '大技',
          category: TechniqueCardCategory.normal,
          attribute: MoveAttribute.strike,
          power: 9999,
        ),
      ],
      energies: [
        TechniqueEnergyCard(
          id: 'energy_strike',
          attribute: MoveAttribute.strike,
          name: '打エネルギー',
        ),
      ],
      defenseCards: [],
    );

    TechniqueDeckDefinition deckWithSpecificCards(
      String wrestlerId,
      List<String> cardIds,
    ) => TechniqueDeckDefinition(
      id: '${wrestlerId}_deck',
      wrestlerId: wrestlerId,
      entries: [
        for (var i = 0; i < cardIds.length; i++)
          TechniqueDeckEntry(
            instanceId: '${wrestlerId}_entry_$i',
            cardId: cardIds[i],
            cardType: TechniqueDeckCardType.technique,
          ),
      ],
    );

    TechniqueMatchState matchWithHand(List<String> cardIdsA) {
      final deckA = deckWithSpecificCards('wrestler_a', cardIdsA);
      final deckB = deckWithCards('b', 30);
      return TechniqueMatchEngine.start(
        wrestlerAId: 'wrestler_a',
        wrestlerAName: 'レスラーA',
        wrestlerAMaxHp: 100,
        deckA: deckA,
        wrestlerBId: 'wrestler_b',
        wrestlerBName: 'レスラーB',
        wrestlerBMaxHp: 100,
        deckB: deckB,
        handSize: cardIdsA.length,
        random: Random(1),
      );
    }

    test('エネルギーカードは技カードとしては使用できない', () {
      final state = matchWithHand(['normal_strike']);
      final result = TechniqueMatchEngine.setEnergy(
        state,
        state.active.hand.first,
        catalog(),
      );
      // normal_strikeは技カードなのでエネルギーとしてセットできない。
      expect(result.success, isFalse);
    });

    test('エネルギーカードをセットするとenergyPoolに加算され手札から消える', () {
      final deckA = deckWithSpecificCards('wrestler_a', ['energy_strike']);
      final state = TechniqueMatchEngine.start(
        wrestlerAId: 'wrestler_a',
        wrestlerAName: 'レスラーA',
        wrestlerAMaxHp: 100,
        deckA: deckA,
        wrestlerBId: 'wrestler_b',
        wrestlerBName: 'レスラーB',
        wrestlerBMaxHp: 100,
        deckB: deckWithCards('b', 30),
        handSize: 1,
        random: Random(1),
      );
      final entry = state.active.hand.first;
      final result = TechniqueMatchEngine.setEnergy(state, entry, catalog());
      expect(result.success, isTrue);
      expect(result.state.active.energyPool[MoveAttribute.strike], 1);
      expect(result.state.active.hand, isEmpty);
    });

    // UI改善+CPU実装ラウンドで確定した仕様: 技エネルギーは1ターンに1枚のみ
    // セット可能。エンジンレベル（setEnergy）で強制する。
    test('技エネルギーは1ターンに1枚のみセット可能（2枚目は拒否される）', () {
      final deckA = deckWithSpecificCards(
        'wrestler_a',
        ['energy_strike', 'energy_strike'],
      );
      final state = TechniqueMatchEngine.start(
        wrestlerAId: 'wrestler_a',
        wrestlerAName: 'レスラーA',
        wrestlerAMaxHp: 100,
        deckA: deckA,
        wrestlerBId: 'wrestler_b',
        wrestlerBName: 'レスラーB',
        wrestlerBMaxHp: 100,
        deckB: deckWithCards('b', 30),
        handSize: 2,
        random: Random(1),
      );
      expect(state.energySetThisTurn, isFalse);

      final firstEntry = state.active.hand.first;
      final firstResult = TechniqueMatchEngine.setEnergy(state, firstEntry, catalog());
      expect(firstResult.success, isTrue);
      expect(firstResult.state.energySetThisTurn, isTrue);
      expect(firstResult.state.active.energyPool[MoveAttribute.strike], 1);

      final secondEntry = firstResult.state.active.hand.first;
      final secondResult = TechniqueMatchEngine.setEnergy(
        firstResult.state,
        secondEntry,
        catalog(),
      );
      expect(secondResult.success, isFalse);
      expect(secondResult.failureReason, contains('1ターンに1枚'));
      // 2枚目は拒否され、状態は変化していない（1枚のまま・手札にも残る）。
      expect(secondResult.state.active.energyPool[MoveAttribute.strike], 1);
      expect(secondResult.state.active.hand, contains(secondEntry));
    });

    test('ターンを終了すると技エネルギーの1ターン1枚制限がリセットされる', () {
      final deckA = deckWithSpecificCards('wrestler_a', ['energy_strike']);
      final state = TechniqueMatchEngine.start(
        wrestlerAId: 'wrestler_a',
        wrestlerAName: 'レスラーA',
        wrestlerAMaxHp: 100,
        deckA: deckA,
        wrestlerBId: 'wrestler_b',
        wrestlerBName: 'レスラーB',
        wrestlerBMaxHp: 100,
        deckB: deckWithCards('b', 30),
        handSize: 1,
        random: Random(1),
      );
      final entry = state.active.hand.first;
      final afterSet = TechniqueMatchEngine.setEnergy(state, entry, catalog()).state;
      expect(afterSet.energySetThisTurn, isTrue);

      // Bのターンへ、そして再びAのターンへ戻る。
      final afterB = TechniqueMatchEngine.endTurn(afterSet, random: Random(2));
      expect(afterB.activePlayerIndex, 1);
      final backToA = TechniqueMatchEngine.endTurn(afterB, random: Random(3));
      expect(backToA.activePlayerIndex, 0);
      expect(backToA.energySetThisTurn, isFalse);
    });

    test('エネルギー不足の技は使用できない', () {
      final state = matchWithHand(['normal_strike']);
      final check = TechniqueMatchEngine.canUseMove(
        state,
        state.active.hand.first,
        catalog(),
      );
      expect(check.canUse, isFalse);
      expect(check.reason, contains('エネルギー'));
    });

    test('エネルギーを満たすと技を使用でき、ダメージ・HEAT・ダウンが即時反映される', () {
      var state = matchWithHand(['normal_strike']);
      // 手動でエネルギーをセットする代わりに、直接energyPoolを持つ状態を作る。
      state = state.copyWith(
        playerA: state.playerA.copyWith(
          energyPool: const {MoveAttribute.strike: 1},
        ),
      );
      final entry = state.active.hand.first;
      // 現行フロー: declareAttack（宣言・エネルギー消費）→ resolveHit（返技
      // されなかった場合の成立・ダメージ適用）。
      final declared = TechniqueMatchEngine.declareAttack(state, entry, catalog());
      expect(declared.success, isTrue);
      final updated = TechniqueMatchEngine.resolveHit(declared.state, catalog());
      expect(updated.playerB.hp, 90); // 100 - 10
      expect(updated.playerA.heat, 5);
      expect(updated.playerB.posture, WrestlerPosture.down);
      expect(updated.playerA.hand, isEmpty);
      expect(updated.playerA.discardPile, [entry]);
      expect(updated.playerA.spentEnergy[MoveAttribute.strike], 1);
      expect(updated.playerA.availableEnergyFor(MoveAttribute.strike), 0);
    });

    test('HPが0になると疲労状態になる（0未満にはならない）', () {
      var state = matchWithHand(['lethal_move']);
      final entry = state.active.hand.first;
      final declared = TechniqueMatchEngine.declareAttack(state, entry, catalog());
      expect(declared.success, isTrue);
      final updated = TechniqueMatchEngine.resolveHit(declared.state, catalog());
      expect(updated.playerB.hp, 0);
      expect(updated.playerB.posture, WrestlerPosture.fatigued);
    });

    test('スタンド限定技はダウン中の相手には使用できない', () {
      var state = matchWithHand(['stand_only']);
      state = state.copyWith(
        playerB: state.playerB.copyWith(posture: WrestlerPosture.down),
      );
      final check = TechniqueMatchEngine.canUseMove(
        state,
        state.active.hand.first,
        catalog(),
      );
      expect(check.canUse, isFalse);
      expect(check.reason, contains('スタンド'));
    });

    test('ダウン限定技はスタンド中の相手には使用できない', () {
      final state = matchWithHand(['down_only']);
      final check = TechniqueMatchEngine.canUseMove(
        state,
        state.active.hand.first,
        catalog(),
      );
      expect(check.canUse, isFalse);
      expect(check.reason, contains('ダウン'));
    });

    test('ダウン限定技は疲労中の相手にも使用できる', () {
      var state = matchWithHand(['down_only']);
      state = state.copyWith(
        playerB: state.playerB.copyWith(posture: WrestlerPosture.fatigued),
      );
      final check = TechniqueMatchEngine.canUseMove(
        state,
        state.active.hand.first,
        catalog(),
      );
      expect(check.canUse, isTrue);
    });

    test('固有技は許可されたレスラー以外は使用できない', () {
      final state = matchWithHand(['sig_akari']).copyWith(activePlayerIndex: 1);
      // Bの手札にはsig_akariが無いため、代わりに直接手札へ差し込んで検証する。
      final withHand = state.copyWith(
        playerB: state.playerB.copyWith(
          hand: [
            const TechniqueDeckEntry(
              instanceId: 'x',
              cardId: 'sig_akari',
              cardType: TechniqueDeckCardType.technique,
            ),
          ],
        ),
      );
      final check = TechniqueMatchEngine.canUseMove(
        withHand,
        withHand.active.hand.first,
        catalog(),
      );
      expect(check.canUse, isFalse);
      expect(check.reason, contains('使用できません'));
    });

    test('固有技は許可されたレスラーなら使用できる', () {
      final state = matchWithHand(['sig_akari']);
      final check = TechniqueMatchEngine.canUseMove(
        state,
        state.active.hand.first,
        catalog(),
      );
      expect(check.canUse, isTrue);
    });

    test('レベル不足の技は使用できない', () {
      final state = matchWithHand(['lv2_move']);
      final check = TechniqueMatchEngine.canUseMove(
        state,
        state.active.hand.first,
        catalog(),
      );
      expect(check.canUse, isFalse);
      expect(check.reason, contains('レベル'));
    });

    test('手札に無いカードは使用できない', () {
      final state = matchWithHand(['normal_strike']);
      const notInHand = TechniqueDeckEntry(
        instanceId: 'not_in_hand',
        cardId: 'down_only',
        cardType: TechniqueDeckCardType.technique,
      );
      final check = TechniqueMatchEngine.canUseMove(state, notInHand, catalog());
      expect(check.canUse, isFalse);
      expect(check.reason, contains('手札'));
    });

    test('検証に失敗した場合、declareAttackは状態を変化させない', () {
      final state = matchWithHand(['lv2_move']);
      final entry = state.active.hand.first;
      final result = TechniqueMatchEngine.declareAttack(state, entry, catalog());
      expect(result.success, isFalse);
      expect(result.state, same(state));
    });
  });

  group('Phase 5: ラリー（返技・連続攻撃）', () {
    TechniqueDeckCardCatalog catalog() => const TechniqueDeckCardCatalog(
      techniques: [
        TechniqueDeckTechniqueCard(
          id: 'strike_move',
          name: '打撃技',
          category: TechniqueCardCategory.normal,
          attribute: MoveAttribute.strike,
          attackEnergyCost: {MoveAttribute.strike: 1},
          reversalEnergyCost: {MoveAttribute.counter: 1},
          power: 10,
          heatDelta: 5,
          causesDown: true,
        ),
        TechniqueDeckTechniqueCard(
          id: 'throw_move',
          name: '投げ技',
          category: TechniqueCardCategory.normal,
          attribute: MoveAttribute.throwMove,
          attackEnergyCost: {MoveAttribute.throwMove: 1},
          reversalEnergyCost: {MoveAttribute.counter: 1},
          power: 15,
        ),
      ],
      energies: [],
      defenseCards: [],
    );

    TechniqueDeckDefinition deckWithSpecificCards(
      String wrestlerId,
      List<String> cardIds,
    ) => TechniqueDeckDefinition(
      id: '${wrestlerId}_deck',
      wrestlerId: wrestlerId,
      entries: [
        for (var i = 0; i < cardIds.length; i++)
          TechniqueDeckEntry(
            instanceId: '${wrestlerId}_entry_$i',
            cardId: cardIds[i],
            cardType: TechniqueDeckCardType.technique,
          ),
      ],
    );

    TechniqueMatchState startWith({
      List<String> handA = const [],
      List<String> handB = const [],
      Map<MoveAttribute, int> energyA = const {},
      Map<MoveAttribute, int> energyB = const {},
    }) {
      final handSize = handA.length > handB.length ? handA.length : handB.length;
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'wrestler_a',
        wrestlerAName: 'レスラーA',
        wrestlerAMaxHp: 100,
        deckA: deckWithSpecificCards('wrestler_a', handA),
        wrestlerBId: 'wrestler_b',
        wrestlerBName: 'レスラーB',
        wrestlerBMaxHp: 100,
        deckB: deckWithSpecificCards('wrestler_b', handB),
        handSize: handSize == 0 ? 1 : handSize,
        random: Random(1),
      );
      state = state.copyWith(
        playerA: state.playerA.copyWith(energyPool: energyA),
        playerB: state.playerB.copyWith(energyPool: energyB),
      );
      return state;
    }

    test('返技条件を満たしていれば返技できる（ダメージ無効・攻守交代・返技カード消費）', () {
      // 【ゲームサイクル整理ラウンド 優先度2】返技には手札の返技候補カードが
      // 必要になった。Bにthrow_move（reversalEnergyCost: counter1）を持たせる。
      final state = startWith(
        handA: ['strike_move'],
        handB: ['throw_move'],
        energyA: const {MoveAttribute.strike: 1},
        energyB: const {MoveAttribute.counter: 1},
      );
      final declared = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      );
      expect(declared.success, isTrue);
      expect(declared.state.pendingAttack?.chain, 1);
      expect(declared.state.rallyAttackerIndex, 0);

      final counterEntry = declared.state.playerB.hand.first;
      final countered = TechniqueMatchEngine.counterAttack(
        declared.state,
        counterEntry,
        catalog(),
      );
      expect(countered.success, isTrue);
      expect(countered.state.pendingAttack, isNull);
      expect(countered.state.rallyAttackerIndex, 1); // 攻守交代
      expect(countered.state.playerB.hp, 100); // ダメージ無効
      expect(countered.state.playerB.heat, 0); // HEAT加算なし
      expect(countered.state.playerB.posture, WrestlerPosture.stand); // ダウンなし
      expect(countered.state.playerB.availableEnergyFor(MoveAttribute.counter), 0);
      expect(countered.state.playerB.hand.contains(counterEntry), isFalse); // カード消費
      expect(countered.state.playerB.discardPile.contains(counterEntry), isTrue);
    });

    test('返技候補カードが手札に無ければ返技できない', () {
      final state = startWith(
        handA: ['strike_move'],
        energyA: const {MoveAttribute.strike: 1},
        energyB: const {MoveAttribute.counter: 1}, // エネルギーはあってもカードが無い。
      );
      final declared = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      );
      const dummyEntry = TechniqueDeckEntry(
        instanceId: 'dummy',
        cardId: 'throw_move',
        cardType: TechniqueDeckCardType.technique,
      );
      final countered = TechniqueMatchEngine.counterAttack(
        declared.state,
        dummyEntry,
        catalog(),
      );
      expect(countered.success, isFalse);
      expect(countered.failureReason, contains('手札にありません'));
      expect(countered.state, same(declared.state)); // 状態は変化しない
      expect(
        TechniqueMatchEngine.checkCounterEligibility(declared.state, catalog()).canCounter,
        isFalse,
      );
    });

    test('返技エネルギー不足だと返技できない（候補カードはあるがエネルギーが無い）', () {
      final state = startWith(
        handA: ['strike_move'],
        handB: ['throw_move'],
        energyA: const {MoveAttribute.strike: 1},
        // Bは返技エネルギーを持たない。
      );
      final declared = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      );
      final countered = TechniqueMatchEngine.counterAttack(
        declared.state,
        declared.state.playerB.hand.first,
        catalog(),
      );
      expect(countered.success, isFalse);
      expect(countered.failureReason, contains('返技エネルギー'));
      expect(countered.state, same(declared.state)); // 状態は変化しない
    });

    test('返技成功後、新しい攻撃側（元の防御側）が技を宣言してラリーが続く', () {
      final state = startWith(
        handA: ['strike_move', 'strike_move'],
        handB: ['throw_move', 'throw_move'],
        energyA: const {MoveAttribute.strike: 1, MoveAttribute.counter: 1},
        energyB: const {
          MoveAttribute.throwMove: 1,
          MoveAttribute.counter: 1,
        },
      );
      final afterDeclare1 = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      ).state;
      final afterCounter1 = TechniqueMatchEngine.counterAttack(
        afterDeclare1,
        afterDeclare1.playerB.hand.first,
        catalog(),
      ).state;
      expect(afterCounter1.rallyAttackerIndex, 1);

      final afterDeclare2 = TechniqueMatchEngine.declareAttack(
        afterCounter1,
        afterCounter1.playerB.hand.first,
        catalog(),
      );
      expect(afterDeclare2.success, isTrue);
      expect(afterDeclare2.state.pendingAttack?.chain, 2);
      expect(afterDeclare2.state.pendingAttack?.attackerIndex, 1);

      // さらにAが返技すると再度攻守交代する（ラリー継続の確認）。
      final afterCounter2 = TechniqueMatchEngine.counterAttack(
        afterDeclare2.state,
        afterDeclare2.state.playerA.hand.first,
        catalog(),
      );
      expect(afterCounter2.success, isTrue);
      expect(afterCounter2.state.rallyAttackerIndex, 0);
      expect(afterCounter2.state.rallyChain, 2); // Chainは宣言のたびに増える
    });

    test('返技しない場合は技が成立し、ダメージ・HEAT・ダウンが即時反映される（Phase 8.5A: フォール／ギブアップを伴わなければラリーは継続する）', () {
      final state = startWith(
        handA: ['strike_move'],
        energyA: const {MoveAttribute.strike: 1},
      );
      final declared = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      ).state;
      final resolved = TechniqueMatchEngine.resolveHit(declared, catalog());

      expect(resolved.playerB.hp, 90); // 100 - 10
      expect(resolved.playerA.heat, 5);
      expect(resolved.playerB.posture, WrestlerPosture.down);
      expect(resolved.pendingAttack, isNull);
      // Combo Speed Rulesにより、フォール／ギブアップを伴わない通常のヒット
      // ではラリーが終了しない。攻撃側は同じ攻撃側のまま残る。
      expect(resolved.rallyAttackerIndex, 0);
      expect(resolved.rallyChain, 1);
      expect(resolved.activePlayerIndex, 0); // 公式なターンはAのまま
    });

    test('Chain Limitに到達すると宣言できずラリーが強制終了する', () {
      final base = startWith(
        handA: ['strike_move'],
        energyA: const {MoveAttribute.strike: 1},
      );
      final atLimit = base.copyWith(
        rallyAttackerIndex: 0,
        rallyChain: TechniqueMatchEngine.maxRallyChain,
      );
      final result = TechniqueMatchEngine.declareAttack(
        atLimit,
        atLimit.playerA.hand.first,
        catalog(),
      );
      expect(result.success, isFalse);
      expect(result.failureReason, contains('Chain Limit'));
      expect(result.state.rallyAttackerIndex, isNull);
      expect(result.state.rallyChain, 0);
      expect(result.state.log.last, contains('Chain Limit'));
    });

    test('保留中の攻撃がある間は新たな宣言ができない', () {
      final state = startWith(
        handA: ['strike_move'],
        energyA: const {MoveAttribute.strike: 1},
      );
      final declared = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      ).state;
      // 手札は既に空だが、pendingAttackガードは手札チェックより先に働く
      // ことを確認するため、ダミーのエントリを渡す。
      const dummyEntry = TechniqueDeckEntry(
        instanceId: 'dummy',
        cardId: 'strike_move',
        cardType: TechniqueDeckCardType.technique,
      );
      final result = TechniqueMatchEngine.declareAttack(
        declared,
        dummyEntry,
        catalog(),
      );
      expect(result.success, isFalse);
      expect(result.failureReason, contains('返技'));
    });

    test('保留中の攻撃が無ければcounterAttackは失敗する', () {
      final state = startWith(handA: ['strike_move']);
      const dummyEntry = TechniqueDeckEntry(
        instanceId: 'dummy',
        cardId: 'strike_move',
        cardType: TechniqueDeckCardType.technique,
      );
      final result = TechniqueMatchEngine.counterAttack(state, dummyEntry, catalog());
      expect(result.success, isFalse);
      expect(result.failureReason, contains('返技可能な攻撃がありません'));
    });

    test('endRallyでラリーを終了できる（攻守交代後、追撃しない場合）', () {
      final state = startWith(
        handA: ['strike_move'],
        handB: ['throw_move'],
        energyA: const {MoveAttribute.strike: 1},
        energyB: const {MoveAttribute.counter: 1},
      );
      final declared = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      ).state;
      final afterCounter = TechniqueMatchEngine.counterAttack(
        declared,
        declared.playerB.hand.first,
        catalog(),
      ).state;
      expect(afterCounter.isRallyActive, isTrue);

      final ended = TechniqueMatchEngine.endRally(afterCounter);
      expect(ended.isRallyActive, isFalse);
      expect(ended.rallyChain, 0);
      expect(ended.log.last, contains('ラリーを終了した'));
    });

    test('hasUsableMoveは攻撃側に使用可能な技があるかを判定する', () {
      final withMove = startWith(
        handA: ['strike_move'],
        energyA: const {MoveAttribute.strike: 1},
      );
      expect(TechniqueMatchEngine.hasUsableMove(withMove, catalog()), isTrue);

      final withoutEnergy = startWith(handA: ['strike_move']);
      expect(
        TechniqueMatchEngine.hasUsableMove(withoutEnergy, catalog()),
        isFalse,
      );

      final withoutHand = startWith();
      expect(
        TechniqueMatchEngine.hasUsableMove(withoutHand, catalog()),
        isFalse,
      );
    });

    test('ログにChain番号と宣言・返技・成立が記録される', () {
      final state = startWith(
        handA: ['strike_move'],
        energyA: const {MoveAttribute.strike: 1},
      );
      final declared = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      ).state;
      expect(declared.log.last, contains('[Chain 1]'));
      expect(declared.log.last, contains('宣言した'));

      final resolved = TechniqueMatchEngine.resolveHit(declared, catalog());
      expect(resolved.log.any((l) => l.contains('Hit!')), isTrue);
      expect(resolved.log.any((l) => l.contains('ダメージ')), isTrue);
      // Phase 8.5A: フォール／ギブアップを伴わない通常のヒットはラリーを
      // 終了させないため「ラリー終了」ログは出ない。
      expect(resolved.log.any((l) => l.contains('ラリー終了')), isFalse);
    });
  });

  group('Phase 8.5A: Combo Speed Rules', () {
    // comboSpeedは既定値10（defaultComboSpeed）。speedを明示した技カードで
    // 残りSpeedの消費・不足判定・攻守交代時の全回復を検証する。
    TechniqueDeckCardCatalog catalog() => const TechniqueDeckCardCatalog(
      techniques: [
        TechniqueDeckTechniqueCard(
          id: 'speed6_move',
          name: '重い技',
          category: TechniqueCardCategory.normal,
          attribute: MoveAttribute.strike,
          attackEnergyCost: {MoveAttribute.strike: 1},
          reversalEnergyCost: {MoveAttribute.counter: 1},
          power: 5,
          speed: 6,
        ),
        TechniqueDeckTechniqueCard(
          id: 'speed11_move',
          name: 'Speed超過技',
          category: TechniqueCardCategory.normal,
          attribute: MoveAttribute.strike,
          attackEnergyCost: {MoveAttribute.strike: 1},
          power: 5,
          speed: 11,
        ),
        TechniqueDeckTechniqueCard(
          id: 'speed1_move',
          name: '軽い技',
          category: TechniqueCardCategory.normal,
          attribute: MoveAttribute.throwMove,
          attackEnergyCost: {MoveAttribute.throwMove: 1},
          reversalEnergyCost: {MoveAttribute.counter: 1},
          power: 5,
          speed: 1,
        ),
      ],
      energies: [],
      defenseCards: [],
    );

    TechniqueDeckDefinition deckWithSpecificCards(
      String wrestlerId,
      List<String> cardIds,
    ) => TechniqueDeckDefinition(
      id: '${wrestlerId}_deck',
      wrestlerId: wrestlerId,
      entries: [
        for (var i = 0; i < cardIds.length; i++)
          TechniqueDeckEntry(
            instanceId: '${wrestlerId}_entry_$i',
            cardId: cardIds[i],
            cardType: TechniqueDeckCardType.technique,
          ),
      ],
    );

    TechniqueMatchState startWith({
      List<String> handA = const [],
      List<String> handB = const [],
      Map<MoveAttribute, int> energyA = const {},
      Map<MoveAttribute, int> energyB = const {},
    }) {
      final handSize = handA.length > handB.length ? handA.length : handB.length;
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'wrestler_a',
        wrestlerAName: 'レスラーA',
        wrestlerAMaxHp: 100,
        deckA: deckWithSpecificCards('wrestler_a', handA),
        wrestlerBId: 'wrestler_b',
        wrestlerBName: 'レスラーB',
        wrestlerBMaxHp: 100,
        deckB: deckWithSpecificCards('wrestler_b', handB),
        handSize: handSize == 0 ? 1 : handSize,
        random: Random(1),
      );
      state = state.copyWith(
        playerA: state.playerA.copyWith(energyPool: energyA),
        playerB: state.playerB.copyWith(energyPool: energyB),
      );
      return state;
    }

    test('新しいラリー開始時、comboSpeedを超えるSpeedコストの技は使用できない', () {
      final state = startWith(
        handA: ['speed11_move'],
        energyA: const {MoveAttribute.strike: 1},
      );
      final check = TechniqueMatchEngine.canDeclareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      );
      expect(check.canUse, isFalse);
      expect(check.reason, contains('Speed'));
    });

    test('技を宣言するたびに残りSpeedが減り、足りなくなると追撃できない', () {
      final state = startWith(
        handA: ['speed6_move', 'speed6_move'],
        energyA: const {MoveAttribute.strike: 2},
      );
      final afterFirst = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      ).state;
      expect(afterFirst.rallyRemainingSpeed, 4); // 10 - 6

      final resolved = TechniqueMatchEngine.resolveHit(afterFirst, catalog());
      expect(resolved.rallyRemainingSpeed, 4); // ヒット解決では変化しない
      expect(resolved.rallyAttackerIndex, 0); // ラリーは継続する

      final secondCheck = TechniqueMatchEngine.canDeclareAttack(
        resolved,
        resolved.playerA.hand.first,
        catalog(),
      );
      expect(secondCheck.canUse, isFalse); // 残り4 < 必要6
      expect(secondCheck.reason, contains('Speed'));
    });

    test('残りSpeedが足りれば連続で技を使用できる（1ターン複数技）', () {
      final state = startWith(
        handA: ['speed1_move', 'speed1_move'],
        energyA: const {MoveAttribute.throwMove: 2},
      );
      final afterFirst = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      ).state;
      final resolved1 = TechniqueMatchEngine.resolveHit(afterFirst, catalog());
      expect(resolved1.rallyAttackerIndex, 0);
      expect(resolved1.rallyRemainingSpeed, 9); // 10 - 1

      final afterSecond = TechniqueMatchEngine.declareAttack(
        resolved1,
        resolved1.playerA.hand.first,
        catalog(),
      ).state;
      final resolved2 = TechniqueMatchEngine.resolveHit(afterSecond, catalog());
      expect(resolved2.rallyRemainingSpeed, 8); // 10 - 1 - 1
      expect(resolved2.rallyChain, 2);
    });

    test('攻守交代（返技成功）すると新しい攻撃側のComboSpeedが全回復する（残りは引き継がない）', () {
      final state = startWith(
        handA: ['speed6_move'],
        handB: ['speed1_move'],
        energyA: const {MoveAttribute.strike: 1},
        energyB: const {MoveAttribute.counter: 1},
      );
      final declared = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      ).state;
      expect(declared.rallyRemainingSpeed, 4); // 10 - 6

      final countered = TechniqueMatchEngine.counterAttack(
        declared,
        declared.playerB.hand.first,
        catalog(),
      ).state;
      expect(countered.rallyAttackerIndex, 1);
      expect(countered.rallyRemainingSpeed, 10); // 新攻撃側は全回復（引き継がない）
    });

    // 【次フェーズ Stage6】SPEED-vs-COUNTER判定は既定でOFF。
    // enableSpeedGate:trueを明示した場合のみ、返技の実効SPEEDが攻撃技の
    // 実効SPEEDを下回っていると返技できなくなる。
    test('enableSpeedGate未指定（既定false）では、返技のSPEEDが低くても返技できる', () {
      final state = startWith(
        handA: ['speed6_move'],
        handB: ['speed1_move'],
        energyA: const {MoveAttribute.strike: 1},
        energyB: const {MoveAttribute.counter: 1},
      );
      final declared = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      ).state;
      final check = TechniqueMatchEngine.canCounterWithEntry(
        declared,
        declared.playerB.hand.first,
        catalog(),
      );
      expect(check.canCounter, isTrue);
    });

    test('enableSpeedGate:trueだと、攻撃技よりSPEEDが低い返技は使用できない', () {
      final state = startWith(
        handA: ['speed6_move'],
        handB: ['speed1_move'],
        energyA: const {MoveAttribute.strike: 1},
        energyB: const {MoveAttribute.counter: 1},
      );
      final declared = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      ).state;
      final check = TechniqueMatchEngine.canCounterWithEntry(
        declared,
        declared.playerB.hand.first,
        catalog(),
        enableSpeedGate: true,
      );
      expect(check.canCounter, isFalse);
      expect(check.reason, contains('SPEED'));

      final candidates = TechniqueMatchEngine.counterCandidates(
        declared,
        catalog(),
        enableSpeedGate: true,
      );
      expect(candidates, isEmpty);
    });

    test('enableSpeedGate:trueでも、返技のSPEEDが攻撃技以上なら返技できる', () {
      final state = startWith(
        handA: ['speed1_move'],
        handB: ['speed6_move'],
        energyA: const {MoveAttribute.throwMove: 1},
        energyB: const {MoveAttribute.counter: 1},
      );
      final declared = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      ).state;
      final check = TechniqueMatchEngine.canCounterWithEntry(
        declared,
        declared.playerB.hand.first,
        catalog(),
        enableSpeedGate: true,
      );
      expect(check.canCounter, isTrue);
    });
  });

  group('TechniqueMatchEngine.calculateEffectiveSpeed（次フェーズ Stage6）', () {
    test('comboCount=1（1発目）なら実効SPEEDはcardSpeedそのまま', () {
      expect(TechniqueMatchEngine.calculateEffectiveSpeed(5, 1), 5);
    });

    test('comboCountが増えるほど実効SPEEDが下がる', () {
      expect(TechniqueMatchEngine.calculateEffectiveSpeed(5, 2), 4);
      expect(TechniqueMatchEngine.calculateEffectiveSpeed(5, 3), 3);
    });

    test('この関数自体はどの判定ロジックからも呼ばれていない（未活性の確認）', () {
      // 通常のSpeedゲート（既存の攻撃可否判定）はremainingSpeedベースで
      // あり、calculateEffectiveSpeedとは無関係に動作し続けることを
      // 回帰確認する（新関数の追加が既存挙動へ影響しないことの担保）。
      const catalog = TechniqueDeckCardCatalog(
        techniques: [
          TechniqueDeckTechniqueCard(
            id: 'plain_move',
            name: '技',
            attribute: MoveAttribute.strike,
            attackEnergyCost: {MoveAttribute.strike: 1},
            power: 5,
            speed: 3,
          ),
        ],
        energies: [],
        defenseCards: [],
      );
      final state = TechniqueMatchEngine.start(
        wrestlerAId: 'wrestler_a',
        wrestlerAName: 'レスラーA',
        wrestlerAMaxHp: 100,
        deckA: TechniqueDeckDefinition(
          id: 'deck_a',
          wrestlerId: 'wrestler_a',
          entries: const [
            TechniqueDeckEntry(
              instanceId: 'a1',
              cardId: 'plain_move',
              cardType: TechniqueDeckCardType.technique,
            ),
          ],
        ),
        wrestlerBId: 'wrestler_b',
        wrestlerBName: 'レスラーB',
        wrestlerBMaxHp: 100,
        deckB: const TechniqueDeckDefinition(id: 'deck_b', wrestlerId: 'wrestler_b', entries: []),
        handSize: 1,
        random: Random(1),
      );
      final withEnergy = state.copyWith(
        playerA: state.playerA.copyWith(energyPool: const {MoveAttribute.strike: 1}),
      );
      final check = TechniqueMatchEngine.canDeclareAttack(
        withEnergy,
        withEnergy.playerA.hand.first,
        catalog,
      );
      expect(check.canUse, isTrue);
    });
  });

  group('Phase 6: フォール・ギブアップの回避判定', () {
    TechniqueDeckCardCatalog catalog() => const TechniqueDeckCardCatalog(
      techniques: [
        TechniqueDeckTechniqueCard(
          id: 'fall_move',
          name: 'フォール技',
          category: TechniqueCardCategory.normal,
          attribute: MoveAttribute.strike,
          attackEnergyCost: {MoveAttribute.strike: 1},
          reversalEnergyCost: {MoveAttribute.counter: 1},
          power: 10,
          hasPinEffect: true,
          kickOutThreshold: 20,
          kickOutHpRate: 0.5,
        ),
        TechniqueDeckTechniqueCard(
          id: 'giveup_move',
          name: 'ギブアップ技',
          category: TechniqueCardCategory.normal,
          attribute: MoveAttribute.strike,
          attackEnergyCost: {MoveAttribute.strike: 1},
          reversalEnergyCost: {MoveAttribute.counter: 1},
          power: 5,
          hasSubmissionEffect: true,
          giveUpThreshold: 20,
          giveUpHpCost: 15,
        ),
        TechniqueDeckTechniqueCard(
          id: 'fall_and_giveup_move',
          name: 'フォール兼ギブアップ技',
          category: TechniqueCardCategory.normal,
          attribute: MoveAttribute.strike,
          attackEnergyCost: {MoveAttribute.strike: 1},
          power: 10,
          hasPinEffect: true,
          hasSubmissionEffect: true,
          kickOutThreshold: 20,
          kickOutHpRate: 0.5,
          giveUpThreshold: 20,
          giveUpHpCost: 15,
        ),
        TechniqueDeckTechniqueCard(
          id: 'finisher_fall_move',
          name: 'フィニッシャー（フォール付き）',
          category: TechniqueCardCategory.finisher,
          attribute: MoveAttribute.strike,
          allowedWrestlerIds: ['wrestler_a'],
          attackEnergyCost: {MoveAttribute.strike: 1},
          power: 10,
          hasPinEffect: true,
          hasFinisherEffect: true,
          kickOutThreshold: 20,
          kickOutHpRate: 0.5,
        ),
        TechniqueDeckTechniqueCard(
          id: 'fall_move_no_hp_option',
          name: 'HP消費未対応のフォール技',
          category: TechniqueCardCategory.normal,
          attribute: MoveAttribute.strike,
          attackEnergyCost: {MoveAttribute.strike: 1},
          power: 10,
          hasPinEffect: true,
          // kickOutThreshold / kickOutHpRate は未設定。
        ),
        TechniqueDeckTechniqueCard(
          id: 'fall_move_full_hp_rate',
          name: 'HP全消費フォール技',
          category: TechniqueCardCategory.normal,
          attribute: MoveAttribute.strike,
          attackEnergyCost: {MoveAttribute.strike: 1},
          power: 10,
          hasPinEffect: true,
          kickOutThreshold: 20,
          kickOutHpRate: 1.0,
        ),
      ],
      energies: [],
      defenseCards: [
        TechniqueDefenseCard(
          id: 'kickout_normal',
          name: '通常キックアウト',
          type: TechniqueDeckCardType.kickOut,
          kickOutCategory: KickOutCardCategory.normal,
        ),
        TechniqueDefenseCard(
          id: 'kickout_finisher',
          name: '特殊キックアウト',
          type: TechniqueDeckCardType.kickOut,
          kickOutCategory: KickOutCardCategory.finisherEscape,
        ),
        TechniqueDefenseCard(
          id: 'ropebreak_card',
          name: 'ロープブレイク',
          type: TechniqueDeckCardType.ropeBreak,
        ),
      ],
    );

    TechniqueDeckDefinition deckWithSpecificCards(
      String wrestlerId,
      List<String> cardIds,
    ) => TechniqueDeckDefinition(
      id: '${wrestlerId}_deck',
      wrestlerId: wrestlerId,
      entries: [
        for (var i = 0; i < cardIds.length; i++)
          TechniqueDeckEntry(
            instanceId: '${wrestlerId}_entry_$i',
            cardId: cardIds[i],
            cardType: TechniqueDeckCardType.technique,
          ),
      ],
    );

    TechniqueMatchState startWith({
      List<String> handA = const [],
      List<String> handB = const [],
      Map<MoveAttribute, int> energyA = const {},
      Map<MoveAttribute, int> energyB = const {},
      int hpB = 100,
    }) {
      final handSize = handA.length > handB.length ? handA.length : handB.length;
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'wrestler_a',
        wrestlerAName: 'レスラーA',
        wrestlerAMaxHp: 100,
        deckA: deckWithSpecificCards('wrestler_a', handA),
        wrestlerBId: 'wrestler_b',
        wrestlerBName: 'レスラーB',
        wrestlerBMaxHp: 100,
        deckB: deckWithSpecificCards('wrestler_b', handB),
        startingHpB: hpB,
        handSize: handSize == 0 ? 1 : handSize,
        random: Random(1),
      );
      state = state.copyWith(
        playerA: state.playerA.copyWith(energyPool: energyA),
        playerB: state.playerB.copyWith(energyPool: energyB),
      );
      return state;
    }

    /// [declareAttack]→[resolveHit] を実際に通して`pendingEscape`まで
    /// 到達させる（decision dialogまでのend-to-end確認用）。
    TechniqueMatchState resolveToEscape(String cardId, {int hpB = 100}) {
      final state = startWith(
        handA: [cardId],
        energyA: const {MoveAttribute.strike: 1},
        hpB: hpB,
      );
      final declared = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      ).state;
      return TechniqueMatchEngine.resolveHit(declared, catalog());
    }

    test('hasPinEffectの技が成立するとpendingEscapeがfallでセットされる', () {
      final resolved = resolveToEscape('fall_move');
      expect(resolved.pendingEscape, isNotNull);
      expect(resolved.pendingEscape!.kind, TechniqueEscapeKind.fall);
      expect(resolved.pendingEscape!.attackerIndex, 0);
      expect(resolved.pendingEscape!.defenderIndex, 1);
      expect(resolved.log.any((l) => l.contains('フォールの危機')), isTrue);
    });

    test('hasSubmissionEffectの技が成立するとpendingEscapeがgiveUpでセットされる', () {
      final resolved = resolveToEscape('giveup_move');
      expect(resolved.pendingEscape, isNotNull);
      expect(resolved.pendingEscape!.kind, TechniqueEscapeKind.giveUp);
      expect(resolved.log.any((l) => l.contains('ギブアップの危機')), isTrue);
    });

    test('フォールとギブアップ両方が立っている場合はフォールが優先される', () {
      final resolved = resolveToEscape('fall_and_giveup_move');
      expect(resolved.pendingEscape!.kind, TechniqueEscapeKind.fall);
    });

    test(
      'hasFinisherEffectが立つ技は通常のdeclareAttackでは宣言できない'
      '（Phase 7でdeclareFinisher専用になったため、pendingEscapeもセットされない）',
      () {
        final resolved = resolveToEscape('finisher_fall_move');
        expect(resolved.pendingEscape, isNull);
        // declareAttack自体が失敗するため、技は不成立でダメージも発生しない。
        expect(resolved.playerB.hp, 100);
      },
    );

    test('キックアウトカードでフォールを回避できる（手札→除外。捨て札には入らない）', () {
      var state = resolveToEscape('fall_move');
      const entry = TechniqueDeckEntry(
        instanceId: 'k1',
        cardId: 'kickout_normal',
        cardType: TechniqueDeckCardType.kickOut,
      );
      state = state.copyWith(
        playerB: state.playerB.copyWith(hand: [entry]),
      );
      final check = TechniqueMatchEngine.canEscapeWithDefenseCard(
        state,
        entry,
        catalog(),
      );
      expect(check.canEscape, isTrue);

      final result = TechniqueMatchEngine.escapeWithDefenseCard(
        state,
        entry,
        catalog(),
      );
      expect(result.success, isTrue);
      expect(result.state.pendingEscape, isNull);
      expect(result.state.playerB.hand, isEmpty);
      // 捨て札ではなく除外（removedPile）へ送られる。山札再構築で何度も
      // 手札に戻ってこないようにするため（Phase 6完了後のプレイテストで
      // 判明した「防御側が実質無敵化する」問題への対応）。
      expect(result.state.playerB.discardPile, isEmpty);
      expect(result.state.playerB.removedPile, [entry]);
      expect(result.state.winnerIndex, isNull);
    });

    test('特殊キックアウトカードは通常のフォールには使用できない', () {
      var state = resolveToEscape('fall_move');
      const entry = TechniqueDeckEntry(
        instanceId: 'k2',
        cardId: 'kickout_finisher',
        cardType: TechniqueDeckCardType.kickOut,
      );
      state = state.copyWith(
        playerB: state.playerB.copyWith(hand: [entry]),
      );
      final check = TechniqueMatchEngine.canEscapeWithDefenseCard(
        state,
        entry,
        catalog(),
      );
      expect(check.canEscape, isFalse);
      expect(check.reason, contains('通常キックアウト'));
    });

    test('ロープブレイクカードでギブアップを回避できる', () {
      var state = resolveToEscape('giveup_move');
      const entry = TechniqueDeckEntry(
        instanceId: 'r1',
        cardId: 'ropebreak_card',
        cardType: TechniqueDeckCardType.ropeBreak,
      );
      state = state.copyWith(
        playerB: state.playerB.copyWith(hand: [entry]),
      );
      final result = TechniqueMatchEngine.escapeWithDefenseCard(
        state,
        entry,
        catalog(),
      );
      expect(result.success, isTrue);
      expect(result.state.pendingEscape, isNull);
    });

    test('キックアウトカードはギブアップには使用できない（カード種別不一致）', () {
      var state = resolveToEscape('giveup_move');
      const entry = TechniqueDeckEntry(
        instanceId: 'k3',
        cardId: 'kickout_normal',
        cardType: TechniqueDeckCardType.kickOut,
      );
      state = state.copyWith(
        playerB: state.playerB.copyWith(hand: [entry]),
      );
      final check = TechniqueMatchEngine.canEscapeWithDefenseCard(
        state,
        entry,
        catalog(),
      );
      expect(check.canEscape, isFalse);
      expect(check.reason, contains('ロープブレイク'));
    });

    test(
      '返技エネルギーはフォール／ギブアップの回避には使えない'
      '（TechniqueMatchEngineにcanEscapeWithReversalEnergy等のAPIは存在しない、'
      'ユーザー指示による仕様変更）',
      () {
        // 返技エネルギーは`counterAttack`（ラリー中の返技）専用のリソースと
        // して分離された。カード／HP消費のいずれも使えない（不足している）
        // 状況では、返技エネルギーが潤沢にあっても回避手段はconcedeのみ。
        var state = resolveToEscape('fall_move', hpB: 5);
        state = state.copyWith(
          playerB: state.playerB.copyWith(
            energyPool: const {MoveAttribute.counter: 99},
          ),
        );
        expect(
          TechniqueMatchEngine.canEscapeWithDefenseCard(
            state,
            const TechniqueDeckEntry(
              instanceId: 'dummy',
              cardId: 'kickout_normal',
              cardType: TechniqueDeckCardType.kickOut,
            ),
            catalog(),
          ).canEscape,
          isFalse, // 手札に無いので使えない
        );
        expect(TechniqueMatchEngine.canEscapeWithHp(state, catalog()).canEscape, isFalse);
        final result = TechniqueMatchEngine.concede(state);
        expect(result.winnerIndex, 0);
      },
    );

    test('HP消費でフォールを回避できる（現在HPの割合を消費、閾値以上のみ）', () {
      // fall_move（威力10）を受けてHPは100→90になった状態でpendingEscapeへ
      // 到達する。
      final state = resolveToEscape('fall_move', hpB: 100);
      expect(state.playerB.hp, 90);
      final check = TechniqueMatchEngine.canEscapeWithHp(state, catalog());
      expect(check.canEscape, isTrue); // 現在HP90 >= threshold20

      final result = TechniqueMatchEngine.escapeWithHp(state, catalog());
      expect(result.success, isTrue);
      expect(result.state.pendingEscape, isNull);
      // 90 * 0.5 = 45消費 → 残り45
      expect(result.state.playerB.hp, 45);
      expect(result.state.playerB.posture, isNot(WrestlerPosture.fatigued));
    });

    test('HPが閾値未満だとHP消費によるキックアウトはできない', () {
      final state = resolveToEscape('fall_move', hpB: 10);
      final check = TechniqueMatchEngine.canEscapeWithHp(state, catalog());
      expect(check.canEscape, isFalse);
      expect(check.reason, contains('20未満'));
    });

    test('HP消費でHPが0になっても回避は成功し疲労状態になる', () {
      // kickOutHpRate: 1.0（現在HP全消費）の技を使い、HP0への遷移を確認する。
      var state = startWith(handA: []);
      state = state.copyWith(
        playerB: state.playerB.copyWith(hp: 20),
        pendingEscape: const TechniquePendingEscape(
          attackerIndex: 0,
          defenderIndex: 1,
          cardId: 'fall_move_full_hp_rate',
          kind: TechniqueEscapeKind.fall,
        ),
      );
      final result = TechniqueMatchEngine.escapeWithHp(state, catalog());
      expect(result.success, isTrue);
      expect(result.state.playerB.hp, 0);
      expect(result.state.playerB.posture, WrestlerPosture.fatigued);
      // HP0になっても回避自体は成功しているため、勝敗は決していない。
      expect(result.state.winnerIndex, isNull);
    });

    test('HP消費に対応していない技はHP消費による回避ができない', () {
      final state = startWith(handA: []).copyWith(
        pendingEscape: const TechniquePendingEscape(
          attackerIndex: 0,
          defenderIndex: 1,
          cardId: 'fall_move_no_hp_option',
          kind: TechniqueEscapeKind.fall,
        ),
      );
      final check = TechniqueMatchEngine.canEscapeWithHp(state, catalog());
      expect(check.canEscape, isFalse);
      expect(check.reason, contains('対応していません'));
    });

    test('HP消費でギブアップを回避できる（固定値を消費）', () {
      final state = resolveToEscape('giveup_move', hpB: 100);
      final result = TechniqueMatchEngine.escapeWithHp(state, catalog());
      expect(result.success, isTrue);
      // giveup_moveの威力5でHP95、そこからgiveUpHpCost=15固定消費 → 80
      expect(result.state.playerB.hp, 80);
    });

    test('回避せず諦めると攻撃側の勝利で試合が終了する', () {
      final state = resolveToEscape('fall_move');
      final conceded = TechniqueMatchEngine.concede(state);
      expect(conceded.winnerIndex, 0);
      expect(conceded.winReason, 'フォール勝利');
      expect(conceded.pendingEscape, isNull);
      expect(conceded.isOver, isTrue);
    });

    test('ギブアップを諦めるとギブアップ勝利になる', () {
      final state = resolveToEscape('giveup_move');
      final conceded = TechniqueMatchEngine.concede(state);
      expect(conceded.winReason, 'ギブアップ勝利');
    });

    test('pendingEscapeが無い状態でconcedeしても何も起きない', () {
      final state = startWith(handA: []);
      final result = TechniqueMatchEngine.concede(state);
      expect(result, same(state));
    });

    test('決着判定待ちの間はendTurn/setEnergyが無効化される', () {
      final state = resolveToEscape('fall_move');
      expect(TechniqueMatchEngine.endTurn(state), same(state));

      const dummyEnergyEntry = TechniqueDeckEntry(
        instanceId: 'dummy_energy',
        cardId: 'energy_strike',
        cardType: TechniqueDeckCardType.energy,
      );
      final energyResult = TechniqueMatchEngine.setEnergy(
        state,
        dummyEnergyEntry,
        catalog(),
      );
      expect(energyResult.success, isFalse);
      expect(energyResult.state, same(state));
    });

    test('試合終了後はendTurn/setEnergy/declareAttackが無効化される', () {
      final resolved = resolveToEscape('fall_move');
      final over = TechniqueMatchEngine.concede(resolved);
      expect(over.winnerIndex, isNotNull);

      expect(TechniqueMatchEngine.endTurn(over), same(over));

      const dummyEnergyEntry = TechniqueDeckEntry(
        instanceId: 'dummy_energy',
        cardId: 'energy_strike',
        cardType: TechniqueDeckCardType.energy,
      );
      final energyResult = TechniqueMatchEngine.setEnergy(
        over,
        dummyEnergyEntry,
        catalog(),
      );
      expect(energyResult.success, isFalse);

      const dummyAttackEntry = TechniqueDeckEntry(
        instanceId: 'dummy_attack',
        cardId: 'fall_move',
        cardType: TechniqueDeckCardType.technique,
      );
      final attackResult = TechniqueMatchEngine.declareAttack(
        over,
        dummyAttackEntry,
        catalog(),
      );
      expect(attackResult.success, isFalse);
      expect(attackResult.failureReason, contains('終了'));
    });

    test('決着判定待ちの間はdeclareAttackが無効化される', () {
      final state = resolveToEscape('fall_move');
      const dummyAttackEntry = TechniqueDeckEntry(
        instanceId: 'dummy_attack',
        cardId: 'fall_move',
        cardType: TechniqueDeckCardType.technique,
      );
      final result = TechniqueMatchEngine.declareAttack(
        state,
        dummyAttackEntry,
        catalog(),
      );
      expect(result.success, isFalse);
      expect(result.failureReason, contains('決着'));
    });
  });

  group('Phase 6完了後の追加: downBonusPower・removedPile', () {
    TechniqueDeckCardCatalog catalog() => const TechniqueDeckCardCatalog(
      techniques: [
        TechniqueDeckTechniqueCard(
          id: 'submission_any',
          name: '関節技（スタンドでも可）',
          category: TechniqueCardCategory.normal,
          attribute: MoveAttribute.submission,
          attackEnergyCost: {MoveAttribute.submission: 1},
          power: 6,
          downBonusPower: 6,
        ),
      ],
      energies: [],
      defenseCards: [],
    );

    TechniqueDeckDefinition deckWith(String cardId) => TechniqueDeckDefinition(
      id: 'd',
      wrestlerId: 'wrestler_a',
      entries: [
        TechniqueDeckEntry(
          instanceId: 'e1',
          cardId: cardId,
          cardType: TechniqueDeckCardType.technique,
        ),
      ],
    );

    TechniqueMatchState stateWith({required WrestlerPosture defenderPosture}) {
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'wrestler_a',
        wrestlerAName: 'レスラーA',
        wrestlerAMaxHp: 100,
        deckA: deckWith('submission_any'),
        wrestlerBId: 'wrestler_b',
        wrestlerBName: 'レスラーB',
        wrestlerBMaxHp: 100,
        deckB: deckWith('submission_any'),
        handSize: 1,
        random: Random(1),
      );
      state = state.copyWith(
        playerA: state.playerA.copyWith(
          energyPool: const {MoveAttribute.submission: 1},
        ),
        playerB: state.playerB.copyWith(posture: defenderPosture),
      );
      return state;
    }

    test('相手がスタンド中は基礎威力のみ（downBonusPowerは加算されない）', () {
      final state = stateWith(defenderPosture: WrestlerPosture.stand);
      final declared = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      );
      expect(declared.success, isTrue);
      final result = TechniqueMatchEngine.resolveHit(declared.state, catalog());
      expect(result.playerB.hp, 94); // 100 - 6
    });

    test('相手がダウン中はdownBonusPowerが加算される', () {
      final state = stateWith(defenderPosture: WrestlerPosture.down);
      final declared = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      );
      expect(declared.success, isTrue);
      final result = TechniqueMatchEngine.resolveHit(declared.state, catalog());
      expect(result.playerB.hp, 88); // 100 - (6 + 6)
    });

    test('相手が疲労中もdown系状態としてdownBonusPowerが加算される', () {
      final state = stateWith(defenderPosture: WrestlerPosture.fatigued);
      final declared = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog(),
      );
      expect(declared.success, isTrue);
      final result = TechniqueMatchEngine.resolveHit(declared.state, catalog());
      expect(result.playerB.hp, 88); // 100 - (6 + 6)
    });
  });

  group('Phase 7: フィニッシャー', () {
    TechniqueDeckCardCatalog catalog() => const TechniqueDeckCardCatalog(
      techniques: [
        TechniqueDeckTechniqueCard(
          id: 'finisher_a',
          name: 'テストフィニッシャー',
          category: TechniqueCardCategory.finisher,
          attribute: MoveAttribute.strike,
          allowedWrestlerIds: ['wrestler_a'],
          minimumLevel: 1,
          attackEnergyCost: {MoveAttribute.strike: 2},
          reversalEnergyCost: {MoveAttribute.strike: 5}, // 通常返技専用、無関係
          power: 25,
          heatDelta: 10,
          hasFinisherEffect: true,
          finisherRequirements: {'minimumHeat': 20},
        ),
        TechniqueDeckTechniqueCard(
          id: 'other_finisher',
          name: '別のフィニッシャー',
          category: TechniqueCardCategory.finisher,
          attribute: MoveAttribute.strike,
          allowedWrestlerIds: ['wrestler_b'], // Aは使用不可
          minimumLevel: 1,
          attackEnergyCost: {MoveAttribute.strike: 1},
          power: 20,
          heatDelta: 10,
          hasFinisherEffect: true,
        ),
      ],
      energies: [],
      defenseCards: [
        TechniqueDefenseCard(
          id: 'escape_card',
          name: 'エスケープ',
          type: TechniqueDeckCardType.escape,
        ),
        TechniqueDefenseCard(
          id: 'reversal_card',
          name: 'リバーサル',
          type: TechniqueDeckCardType.reversal,
        ),
        TechniqueDefenseCard(
          id: 'special_kickout_card',
          name: '特殊キックアウト',
          type: TechniqueDeckCardType.kickOut,
          kickOutCategory: KickOutCardCategory.finisherEscape,
        ),
        TechniqueDefenseCard(
          id: 'normal_kickout_card',
          name: '通常キックアウト',
          type: TechniqueDeckCardType.kickOut,
          kickOutCategory: KickOutCardCategory.normal,
        ),
        TechniqueDefenseCard(
          id: 'ropebreak_card',
          name: 'ロープブレイク',
          type: TechniqueDeckCardType.ropeBreak,
        ),
      ],
    );

    TechniqueMatchState stateWithFinisherInHand({
      int heatA = 20,
      int hpB = 100,
      List<TechniqueDeckEntry> handB = const [],
      Map<MoveAttribute, int> energyA = const {MoveAttribute.strike: 2},
    }) {
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'wrestler_a',
        wrestlerAName: 'レスラーA',
        wrestlerAMaxHp: 100,
        deckA: const TechniqueDeckDefinition(
          id: 'a',
          wrestlerId: 'wrestler_a',
          entries: [
            TechniqueDeckEntry(
              instanceId: 'fin1',
              cardId: 'finisher_a',
              cardType: TechniqueDeckCardType.technique,
            ),
          ],
        ),
        wrestlerBId: 'wrestler_b',
        wrestlerBName: 'レスラーB',
        wrestlerBMaxHp: 100,
        deckB: const TechniqueDeckDefinition(
          id: 'b',
          wrestlerId: 'wrestler_b',
          entries: [],
        ),
        handSize: 1,
        random: Random(1),
      );
      state = state.copyWith(
        playerA: state.playerA.copyWith(energyPool: energyA, heat: heatA),
        playerB: state.playerB.copyWith(hp: hpB, hand: handB),
      );
      return state;
    }

    test('発動条件（minimumHeat）を満たさないと宣言できない', () {
      final state = stateWithFinisherInHand(heatA: 10);
      final check = TechniqueMatchEngine.canDeclareFinisher(
        state,
        state.playerA.hand.first,
        catalog(),
      );
      expect(check.canDeclare, isFalse);
      expect(check.reason, contains('HEAT'));
    });

    test('使用可能レスラーでなければ宣言できない', () {
      var state = stateWithFinisherInHand();
      const entry = TechniqueDeckEntry(
        instanceId: 'other1',
        cardId: 'other_finisher',
        cardType: TechniqueDeckCardType.technique,
      );
      state = state.copyWith(playerA: state.playerA.copyWith(hand: [entry]));
      final check = TechniqueMatchEngine.canDeclareFinisher(state, entry, catalog());
      expect(check.canDeclare, isFalse);
      expect(check.reason, contains('使用できません'));
    });

    test('条件を満たせば宣言でき、手札から除かれるが捨て札にも山札にも入らない', () {
      final state = stateWithFinisherInHand();
      final entry = state.playerA.hand.first;
      final result = TechniqueMatchEngine.declareFinisher(state, entry, catalog());
      expect(result.success, isTrue);
      final s = result.state;
      expect(s.pendingFinisher, isNotNull);
      expect(s.pendingFinisher!.stage, TechniqueFinisherStage.responsePending);
      expect(s.pendingFinisher!.attackerIndex, 0);
      expect(s.pendingFinisher!.defenderIndex, 1);
      expect(s.playerA.hand, isEmpty);
      expect(s.playerA.discardPile, isEmpty);
      expect(s.playerA.drawPile, isEmpty);
      // 攻撃エネルギーは消費される。
      expect(s.playerA.availableEnergyFor(MoveAttribute.strike), 0);
      expect(s.isRallyActive, isFalse); // 宣言時点でラリーは終了扱い
    });

    test('通常のdeclareAttackではフィニッシャーを宣言できない', () {
      final state = stateWithFinisherInHand();
      final entry = state.playerA.hand.first;
      final result = TechniqueMatchEngine.declareAttack(state, entry, catalog());
      expect(result.success, isFalse);
    });

    test('エスケープカードで発動をキャンセルできる（ダメージなし・山札へ戻る）', () {
      const escapeEntry = TechniqueDeckEntry(
        instanceId: 'e1',
        cardId: 'escape_card',
        cardType: TechniqueDeckCardType.escape,
      );
      final base = stateWithFinisherInHand(handB: const [escapeEntry]);
      final declared = TechniqueMatchEngine.declareFinisher(
        base,
        base.playerA.hand.first,
        catalog(),
      ).state;

      final check = TechniqueMatchEngine.canCancelFinisher(
        declared,
        escapeEntry,
        catalog(),
      );
      expect(check.canCancel, isTrue);

      final result = TechniqueMatchEngine.cancelFinisher(
        declared,
        escapeEntry,
        catalog(),
        random: Random(1),
      );
      expect(result.success, isTrue);
      final s = result.state;
      expect(s.pendingFinisher, isNull);
      expect(s.playerB.hp, 100); // ダメージなし
      expect(s.playerA.heat, 20); // HEAT変動なし
      expect(s.playerB.hand, isEmpty);
      expect(s.playerB.discardPile, [escapeEntry]); // エスケープカードは捨て札
      // フィニッシャーカードは山札へ戻る（捨て札には入らない）。
      expect(s.playerA.drawPile.length, 1);
      expect(s.playerA.drawPile.first.cardId, 'finisher_a');
      expect(s.playerA.discardPile, isEmpty);
      expect(s.isRallyActive, isFalse);
    });

    test('リバーサルカードで発動をキャンセルすると主導権が移動する', () {
      const reversalEntry = TechniqueDeckEntry(
        instanceId: 'r1',
        cardId: 'reversal_card',
        cardType: TechniqueDeckCardType.reversal,
      );
      final base = stateWithFinisherInHand(handB: const [reversalEntry]);
      final declared = TechniqueMatchEngine.declareFinisher(
        base,
        base.playerA.hand.first,
        catalog(),
      ).state;

      final result = TechniqueMatchEngine.cancelFinisher(
        declared,
        reversalEntry,
        catalog(),
        random: Random(1),
      );
      expect(result.success, isTrue);
      final s = result.state;
      expect(s.pendingFinisher, isNull);
      expect(s.playerB.hp, 100);
      expect(s.rallyAttackerIndex, 1); // 主導権がBへ移った
      expect(s.playerA.drawPile.length, 1); // フィニッシャーは山札へ
    });

    test('キャンセルされないと成立し、ダメージ・HEATが反映されescapePendingへ移行する', () {
      final base = stateWithFinisherInHand();
      final declared = TechniqueMatchEngine.declareFinisher(
        base,
        base.playerA.hand.first,
        catalog(),
      ).state;
      final resolved = TechniqueMatchEngine.resolveFinisher(declared, catalog());
      expect(resolved.playerB.hp, 75); // 100 - 25
      expect(resolved.playerA.heat, 30); // 20 + 10
      expect(resolved.pendingFinisher, isNotNull);
      expect(resolved.pendingFinisher!.stage, TechniqueFinisherStage.escapePending);
      // 成立したフィニッシャーカードは捨て札へ。
      expect(resolved.playerA.discardPile.any((e) => e.cardId == 'finisher_a'), isTrue);
      expect(resolved.winnerIndex, isNull);
    });

    test('特殊キックアウトカードで脱出できる（除外され、勝敗はつかない）', () {
      const specialEntry = TechniqueDeckEntry(
        instanceId: 's1',
        cardId: 'special_kickout_card',
        cardType: TechniqueDeckCardType.kickOut,
      );
      final base = stateWithFinisherInHand(handB: const [specialEntry]);
      final declared = TechniqueMatchEngine.declareFinisher(
        base,
        base.playerA.hand.first,
        catalog(),
      ).state;
      final resolved = TechniqueMatchEngine.resolveFinisher(declared, catalog());

      final check = TechniqueMatchEngine.canEscapeFinisher(resolved, specialEntry, catalog());
      expect(check.canEscape, isTrue);

      final result = TechniqueMatchEngine.escapeFinisher(resolved, specialEntry, catalog());
      expect(result.success, isTrue);
      expect(result.state.pendingFinisher, isNull);
      expect(result.state.winnerIndex, isNull);
      expect(result.state.playerB.removedPile, [specialEntry]);
      expect(result.state.playerB.discardPile, isEmpty);
    });

    test('通常キックアウト・ロープブレイクではフィニッシャーから脱出できない', () {
      const normalKickout = TechniqueDeckEntry(
        instanceId: 'nk1',
        cardId: 'normal_kickout_card',
        cardType: TechniqueDeckCardType.kickOut,
      );
      const ropebreak = TechniqueDeckEntry(
        instanceId: 'rb1',
        cardId: 'ropebreak_card',
        cardType: TechniqueDeckCardType.ropeBreak,
      );
      final base = stateWithFinisherInHand(
        handB: const [normalKickout, ropebreak],
      );
      final declared = TechniqueMatchEngine.declareFinisher(
        base,
        base.playerA.hand.first,
        catalog(),
      ).state;
      final resolved = TechniqueMatchEngine.resolveFinisher(declared, catalog());

      expect(
        TechniqueMatchEngine.canEscapeFinisher(resolved, normalKickout, catalog()).canEscape,
        isFalse,
      );
      expect(
        TechniqueMatchEngine.canEscapeFinisher(resolved, ropebreak, catalog()).canEscape,
        isFalse,
      );
    });

    test('脱出できない（諦める）と残りHPに関係なく攻撃側の勝利になる', () {
      final base = stateWithFinisherInHand(hpB: 100);
      final declared = TechniqueMatchEngine.declareFinisher(
        base,
        base.playerA.hand.first,
        catalog(),
      ).state;
      final resolved = TechniqueMatchEngine.resolveFinisher(declared, catalog());
      final conceded = TechniqueMatchEngine.concedeFinisher(resolved);
      expect(conceded.winnerIndex, 0);
      expect(conceded.winReason, 'フィニッシャー勝利');
      expect(conceded.pendingFinisher, isNull);
    });

    test('フィニッシャー判定待ちの間はendTurn/setEnergy/declareAttackが無効化される', () {
      final base = stateWithFinisherInHand();
      final declared = TechniqueMatchEngine.declareFinisher(
        base,
        base.playerA.hand.first,
        catalog(),
      ).state;
      expect(TechniqueMatchEngine.endTurn(declared), same(declared));

      const dummyEntry = TechniqueDeckEntry(
        instanceId: 'dummy',
        cardId: 'escape_card',
        cardType: TechniqueDeckCardType.escape,
      );
      final setEnergyResult = TechniqueMatchEngine.setEnergy(declared, dummyEntry, catalog());
      expect(setEnergyResult.success, isFalse);

      final declareResult = TechniqueMatchEngine.declareAttack(declared, dummyEntry, catalog());
      expect(declareResult.success, isFalse);
      expect(declareResult.failureReason, contains('フィニッシャー'));
    });

    test('pendingFinisherが無い状態でcancelFinisher/resolveFinisher/escapeFinisher/concedeFinisherを呼んでも何も起きない', () {
      final state = stateWithFinisherInHand();
      const dummyEntry = TechniqueDeckEntry(
        instanceId: 'dummy',
        cardId: 'escape_card',
        cardType: TechniqueDeckCardType.escape,
      );
      expect(
        TechniqueMatchEngine.cancelFinisher(state, dummyEntry, catalog()).state,
        same(state),
      );
      expect(TechniqueMatchEngine.resolveFinisher(state, catalog()), same(state));
      expect(
        TechniqueMatchEngine.escapeFinisher(state, dummyEntry, catalog()).state,
        same(state),
      );
      expect(TechniqueMatchEngine.concedeFinisher(state), same(state));
    });
  });
}
