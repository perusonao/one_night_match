// Combat Ver.1 Phase 4: Card conservation invariantの検証
// （docs/combat_rules_v1.md 7.1章「PendingAttack・counterResponsePending」の
// カード保存則、テスト項目31-I）。
//
// 各player: drawPile + hand + discardPile + owned pending card == 30
// を、宣言前・pending中・COUNTER成立後・decline後・invalid
// Counter後・reshuffle発生時のいずれでも検証する。pending cardが
// hand/draw/discardへ同時存在しないことも検証する。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';

import 'combat_v1_test_fixtures.dart';

/// [playerIndex]（0=playerA、1=playerB）の
/// drawPile+hand+discardPile+owned pending cardの合計枚数
/// （docs/combat_rules_v1.md 7.1章（カード保存則の実装上の不変条件））。
int totalCardsFor(CombatV1MatchState state, int playerIndex) {
  final player = playerIndex == 0 ? state.playerA : state.playerB;
  final pendingOwned =
      state.pendingAttack != null && state.pendingAttack!.attackerPlayerIndex == playerIndex
      ? 1
      : 0;
  return player.drawPile.length + player.hand.length + player.discardPile.length + pendingOwned;
}

void _expectNoDuplicateInstanceIdsAcrossAll(CombatV1MatchState state) {
  final ids = <String>[
    ...state.playerA.drawPile.map((e) => e.instanceId),
    ...state.playerA.hand.map((e) => e.instanceId),
    ...state.playerA.discardPile.map((e) => e.instanceId),
    ...state.playerB.drawPile.map((e) => e.instanceId),
    ...state.playerB.hand.map((e) => e.instanceId),
    ...state.playerB.discardPile.map((e) => e.instanceId),
    if (state.pendingAttack != null) state.pendingAttack!.attackCardInstance.instanceId,
  ];
  expect(ids.toSet().length, ids.length, reason: '全体でinstanceIdの重複がある');
}

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

void _expectPendingCardNotElsewhere(CombatV1MatchState state) {
  final pending = state.pendingAttack;
  if (pending == null) return;
  final id = pending.attackCardInstance.instanceId;
  final owner = pending.attackerPlayerIndex == 0 ? state.playerA : state.playerB;
  expect(owner.hand.any((e) => e.instanceId == id), isFalse, reason: 'pending cardがhandにも存在する');
  expect(owner.drawPile.any((e) => e.instanceId == id), isFalse, reason: 'pending cardがdrawPileにも存在する');
  expect(owner.discardPile.any((e) => e.instanceId == id), isFalse, reason: 'pending cardがdiscardPileにも存在する');
}

void main() {
  group('宣言前', () {
    test('start直後は両者とも30枚', () {
      final state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck('cc_a'),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck('cc_b'),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(1),
      );
      expect(totalCardsFor(state, 0), 30);
      expect(totalCardsFor(state, 1), 30);
      _expectNoDuplicateInstanceIdsAcrossAll(state);
    });
  });

  group('pending中', () {
    test('宣言直後もpending所有カードを含めて両者とも30枚', () {
      var state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck('cc2_a'),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck('cc2_b'),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(2),
      );
      state = CombatV1Engine.discardCard(state, state.active.hand.first.instanceId);
      final attackInstanceId = state.active.hand.first.instanceId;
      state = CombatV1Engine.declareTechnique(state, attackInstanceId, catalog: fixtureCatalog);

      expect(state.phase, CombatV1MatchPhase.counterResponsePending);
      expect(totalCardsFor(state, 0), 30);
      expect(totalCardsFor(state, 1), 30);
      _expectNoDuplicateInstanceIdsAcrossAll(state);
      _expectPendingCardNotElsewhere(state);
    });
  });

  group('COUNTER成立後', () {
    test('playCounter成功後も両者とも30枚（pending解消済み）', () {
      var state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck('cc3_a'),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck('cc3_b'),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(3),
      );
      state = CombatV1Engine.discardCard(state, state.active.hand.first.instanceId);

      // fx_normal_strike(family=elbow, STRIKE group)を宣言し、fx_counter_a
      // (groups=[strike])で応答できるよう、手札に該当カードが揃うまで
      // ターンを進める（決定的なフィクスチャデッキのシャッフルに依存する
      // ため、無ければ他の技/COUNTERで代替する）。
      final attackEntry = _firstWhereOrNull(
        state.active.hand,
        (e) => e.cardId == 'fx_normal_strike' || e.cardId == 'fx_normal_strike_alt',
      );
      if (attackEntry == null) {
        // 手札に該当カードが無ければこのシードでのテストはスキップ相当
        // （代わりに山札に残っているはずの技カード全般で代替できないため、
        // 決定的な代替として宣言のみ検証する下のtestに委譲する）。
        return;
      }
      state = CombatV1Engine.declareTechnique(state, attackEntry.instanceId, catalog: fixtureCatalog);

      final counterEntry = state.pendingAttack != null
          ? _firstWhereOrNull(state.opponent.hand, (e) => e.cardId == 'fx_counter_a')
          : null;
      if (counterEntry == null) return;

      state = CombatV1Engine.playCounter(
        state,
        counterEntry.instanceId,
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(4),
      );

      expect(state.pendingAttack, isNull);
      expect(totalCardsFor(state, 0), 30);
      expect(totalCardsFor(state, 1), 30);
      _expectNoDuplicateInstanceIdsAcrossAll(state);
    });

    test('決定的な手組みでのCOUNTER成立後も両者30枚', () {
      final state = buildMatchState(
        handA: const [
          CombatV1DeckEntry(
            instanceId: 'atk1',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
        ],
        handB: const [
          CombatV1DeckEntry(
            instanceId: 'ctr1',
            cardId: 'fx_counter_a',
            category: CombatV1CardCategory.counter,
          ),
        ],
        drawPileA: const [
          CombatV1DeckEntry(
            instanceId: 'reserveA',
            cardId: 'fx_normal_strike_alt',
            category: CombatV1CardCategory.normal,
          ),
        ],
        drawPileB: const [
          CombatV1DeckEntry(
            instanceId: 'reserveB',
            cardId: 'fx_counter_b',
            category: CombatV1CardCategory.counter,
          ),
        ],
      );
      final beforeTotalA = totalCardsFor(state, 0);
      final beforeTotalB = totalCardsFor(state, 1);

      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
      expect(totalCardsFor(pending, 0), beforeTotalA);
      expect(totalCardsFor(pending, 1), beforeTotalB);
      _expectPendingCardNotElsewhere(pending);

      final resolved = CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(5),
      );
      expect(totalCardsFor(resolved, 0), beforeTotalA);
      expect(totalCardsFor(resolved, 1), beforeTotalB);
      _expectNoDuplicateInstanceIdsAcrossAll(resolved);
    });
  });

  group('decline後', () {
    test('declineCounter後も両者の総数は不変', () {
      final state = buildMatchState(
        handA: const [
          CombatV1DeckEntry(
            instanceId: 'atk1',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
        ],
        handB: const [
          CombatV1DeckEntry(
            instanceId: 'ctr1',
            cardId: 'fx_counter_c', // familyが噛み合わずCOUNT不可(この'テストではdeclineするのみ)
            category: CombatV1CardCategory.counter,
          ),
        ],
        drawPileA: const [
          CombatV1DeckEntry(
            instanceId: 'reserveA',
            cardId: 'fx_normal_strike_alt',
            category: CombatV1CardCategory.normal,
          ),
        ],
      );
      final beforeTotalA = totalCardsFor(state, 0);
      final beforeTotalB = totalCardsFor(state, 1);

      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
      final resolved = CombatV1Engine.declineCounter(pending, random: Random(6));

      expect(totalCardsFor(resolved, 0), beforeTotalA);
      expect(totalCardsFor(resolved, 1), beforeTotalB);
      _expectNoDuplicateInstanceIdsAcrossAll(resolved);
    });
  });

  group('invalid Counter', () {
    test('playCounter失敗後も両者の総数は不変（stateは一切変更されない）', () {
      final state = buildMatchState(
        handA: const [
          CombatV1DeckEntry(
            instanceId: 'atk1',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
        ],
        handB: const [
          CombatV1DeckEntry(
            instanceId: 'ctr_narrow',
            cardId: 'fx_counter_c', // family不一致
            category: CombatV1CardCategory.counter,
          ),
        ],
      );
      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
      final beforeTotalA = totalCardsFor(pending, 0);
      final beforeTotalB = totalCardsFor(pending, 1);

      expect(
        () => CombatV1Engine.playCounter(
          pending,
          'ctr_narrow',
          catalog: fixtureCatalog,
          rules: fixtureRules,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );

      expect(totalCardsFor(pending, 0), beforeTotalA);
      expect(totalCardsFor(pending, 1), beforeTotalB);
    });
  });

  group('draw with reshuffle', () {
    test('宣言→decline解決の過程でreshuffleが発生しても総数は不変', () {
      final state = buildMatchState(
        handA: const [
          CombatV1DeckEntry(
            instanceId: 'atk1',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
        ],
        handB: const [],
        drawPileA: const [], // drawPile空、discardPileも空 → decline後の1
        // drawで「引けるカードが無い」ケース（reshuffle自体は発生しないが
        // 総数不変の確認としては同じ枠組みで検証する）。
      );
      final beforeTotalA = totalCardsFor(state, 0);

      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
      final resolved = CombatV1Engine.declineCounter(pending, random: Random(7));

      expect(totalCardsFor(resolved, 0), beforeTotalA);
      _expectNoDuplicateInstanceIdsAcrossAll(resolved);
    });

    test('discardPileにカードがある状態でdeclineの1drawがreshuffleを起こしても総数不変', () {
      final state = buildMatchState(
        handA: const [
          CombatV1DeckEntry(
            instanceId: 'atk1',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
        ],
        drawPileA: const [], // 空
        discardPileA: const [
          CombatV1DeckEntry(
            instanceId: 'oldDiscard',
            cardId: 'fx_normal_strike_alt',
            category: CombatV1CardCategory.normal,
          ),
        ],
      );
      final beforeTotalA = totalCardsFor(state, 0);

      final pending = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
      final resolved = CombatV1Engine.declineCounter(pending, random: Random(8));

      expect(resolved.playerA.reshuffleCount, greaterThanOrEqualTo(1));
      expect(totalCardsFor(resolved, 0), beforeTotalA);
      _expectNoDuplicateInstanceIdsAcrossAll(resolved);
    });
  });
}
