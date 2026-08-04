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
      final result = TechniqueMatchEngine.useMove(state, entry, catalog());
      expect(result.success, isTrue);
      final updated = result.state;
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
      final result = TechniqueMatchEngine.useMove(state, entry, catalog());
      expect(result.success, isTrue);
      expect(result.state.playerB.hp, 0);
      expect(result.state.playerB.posture, WrestlerPosture.fatigued);
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

    test('検証に失敗した場合、useMoveは状態を変化させない', () {
      final state = matchWithHand(['lv2_move']);
      final entry = state.active.hand.first;
      final result = TechniqueMatchEngine.useMove(state, entry, catalog());
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

    test('返技条件を満たしていれば返技できる（ダメージ無効・攻守交代）', () {
      final state = startWith(
        handA: ['strike_move'],
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

      final countered = TechniqueMatchEngine.counterAttack(
        declared.state,
        catalog(),
      );
      expect(countered.success, isTrue);
      expect(countered.state.pendingAttack, isNull);
      expect(countered.state.rallyAttackerIndex, 1); // 攻守交代
      expect(countered.state.playerB.hp, 100); // ダメージ無効
      expect(countered.state.playerB.heat, 0); // HEAT加算なし
      expect(countered.state.playerB.posture, WrestlerPosture.stand); // ダウンなし
      expect(countered.state.playerB.availableEnergyFor(MoveAttribute.counter), 0);
    });

    test('返技エネルギー不足だと返技できない', () {
      final state = startWith(
        handA: ['strike_move'],
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
        catalog(),
      );
      expect(countered.success, isFalse);
      expect(countered.failureReason, contains('返技エネルギー'));
      expect(countered.state, same(declared.state)); // 状態は変化しない
    });

    test('返技成功後、新しい攻撃側（元の防御側）が技を宣言してラリーが続く', () {
      final state = startWith(
        handA: ['strike_move'],
        handB: ['throw_move'],
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
        catalog(),
      );
      expect(afterCounter2.success, isTrue);
      expect(afterCounter2.state.rallyAttackerIndex, 0);
      expect(afterCounter2.state.rallyChain, 2); // Chainは宣言のたびに増える
    });

    test('返技しない場合は技が成立し、ダメージ・HEAT・ダウンが即時反映されラリーが終了する', () {
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
      expect(resolved.rallyAttackerIndex, isNull);
      expect(resolved.rallyChain, 0);
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
      final result = TechniqueMatchEngine.counterAttack(state, catalog());
      expect(result.success, isFalse);
      expect(result.failureReason, contains('返技可能な攻撃がありません'));
    });

    test('endRallyでラリーを終了できる（攻守交代後、追撃しない場合）', () {
      final state = startWith(
        handA: ['strike_move'],
        energyA: const {MoveAttribute.strike: 1},
        energyB: const {MoveAttribute.counter: 1},
      );
      final afterCounter = TechniqueMatchEngine.counterAttack(
        TechniqueMatchEngine.declareAttack(
          state,
          state.playerA.hand.first,
          catalog(),
        ).state,
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
      expect(resolved.log.any((l) => l.contains('ラリー終了')), isTrue);
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

    test('hasFinisherEffectが立つ技はPhase 6の対象外（pendingEscapeはセットされない）', () {
      final resolved = resolveToEscape('finisher_fall_move');
      expect(resolved.pendingEscape, isNull);
      // 通常の技として即座に成立・ダメージ反映されている。
      expect(resolved.playerB.hp, 90);
    });

    test('キックアウトカードでフォールを回避できる（手札→捨て札）', () {
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
      expect(result.state.playerB.discardPile, [entry]);
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

    test('返技エネルギーを消費してフォールを回避できる', () {
      var state = resolveToEscape('fall_move');
      state = state.copyWith(
        playerB: state.playerB.copyWith(
          energyPool: const {MoveAttribute.counter: 1},
        ),
      );
      final check = TechniqueMatchEngine.canEscapeWithReversalEnergy(
        state,
        catalog(),
      );
      expect(check.canEscape, isTrue);

      final result = TechniqueMatchEngine.escapeWithReversalEnergy(
        state,
        catalog(),
      );
      expect(result.success, isTrue);
      expect(result.state.pendingEscape, isNull);
      expect(
        result.state.playerB.availableEnergyFor(MoveAttribute.counter),
        0,
      );
    });

    test('返技エネルギーが不足しているとフォールを回避できない', () {
      final state = resolveToEscape('fall_move');
      final check = TechniqueMatchEngine.canEscapeWithReversalEnergy(
        state,
        catalog(),
      );
      expect(check.canEscape, isFalse);
      expect(check.reason, contains('返技エネルギー'));

      final result = TechniqueMatchEngine.escapeWithReversalEnergy(
        state,
        catalog(),
      );
      expect(result.success, isFalse);
      expect(result.state, same(state));
    });

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

    test('決着判定待ちの間はgoDown/rest/endTurn/setEnergyが無効化される', () {
      final state = resolveToEscape('fall_move');
      expect(TechniqueMatchEngine.goDown(state), same(state));
      expect(TechniqueMatchEngine.rest(state), same(state));
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

    test('試合終了後はgoDown/rest/endTurn/setEnergy/declareAttackが無効化される', () {
      final resolved = resolveToEscape('fall_move');
      final over = TechniqueMatchEngine.concede(resolved);
      expect(over.winnerIndex, isNotNull);

      expect(TechniqueMatchEngine.goDown(over), same(over));
      expect(TechniqueMatchEngine.rest(over), same(over));
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
}
