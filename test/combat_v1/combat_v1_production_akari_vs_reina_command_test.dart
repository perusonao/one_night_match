/// Phase 10C Command integration test（Akari vs Reina、cross-wrestler）。
///
/// `combat_v1_production_akari_test.dart`（Akari vs Akari）・
/// `combat_v1_production_reina_test.dart`（Reina vs Reina）は同一レスラーの
/// ミラーマッチでdeclareTechnique→declineCounter／declareTechnique→
/// playCounterの経路を検証済み。本ファイルは異なるレスラー同士（Akari vs
/// Reina）でも同じCommand経路が破綻しないこと（card ownership・instanceId
/// uniqueness・card conservation・match invariant）を検証する。Core
/// Engine（`combat_v1_engine.dart`）は変更していない。
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_decks.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_production_catalog.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_state_invariants.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_wrestler_catalog.dart';

const CombatV1RulesConfig rules = CombatV1RulesConfig();

List<String> _allInstanceIds(CombatV1MatchState state) {
  final pending = state.pendingAttack;
  return [
    ...state.playerA.hand.map((e) => e.instanceId),
    ...state.playerA.drawPile.map((e) => e.instanceId),
    ...state.playerA.discardPile.map((e) => e.instanceId),
    ...state.playerB.hand.map((e) => e.instanceId),
    ...state.playerB.drawPile.map((e) => e.instanceId),
    ...state.playerB.discardPile.map((e) => e.instanceId),
    if (pending != null) pending.attackCardInstance.instanceId,
  ];
}

void main() {
  group('Akari(player-a) vs Reina(player-b): Engine.start + card conservation', () {
    test('start直後、match invariant・card conservation・instanceId一意性を満たす', () {
      final state = CombatV1Engine.start(
        wrestlerA: akariWrestler,
        deckA: buildAkariDeck(ownerId: 'player-a'),
        wrestlerB: reinaWrestler,
        deckB: buildReinaDeck(ownerId: 'player-b'),
        rules: rules,
        catalog: productionCardCatalog,
      );
      expect(state.playerA.wrestlerId, 'akari');
      expect(state.playerB.wrestlerId, 'reina');
      expect(state.phase, CombatV1MatchPhase.discard);

      final result = validateMatchStateInvariants(state, rules: rules);
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
      expect(_allInstanceIds(state).toSet().length, 60);

      final totalA =
          state.playerA.hand.length +
          state.playerA.drawPile.length +
          state.playerA.discardPile.length;
      final totalB =
          state.playerB.hand.length +
          state.playerB.drawPile.length +
          state.playerB.discardPile.length;
      expect(totalA, 30);
      expect(totalB, 30);
    });
  });

  group('Akari(player-a) vs Reina(player-b): Command integration', () {
    test(
      'declareTechnique→declineCounterの1経路を通してもinstanceId衝突・'
      'pending ownership違反が起きない',
      () {
        final random = Random(20260810);
        final started = CombatV1Engine.start(
          wrestlerA: akariWrestler,
          deckA: buildAkariDeck(ownerId: 'player-a'),
          wrestlerB: reinaWrestler,
          deckB: buildReinaDeck(ownerId: 'player-b'),
          rules: rules,
          catalog: productionCardCatalog,
          random: random,
        );

        final discardEntry = started.playerA.hand.first;
        final afterDiscard = CombatV1Engine.discardCard(
          started,
          discardEntry.instanceId,
        );
        expect(afterDiscard.phase, CombatV1MatchPhase.action);

        final attackEntry = afterDiscard.playerA.hand.firstWhere(
          (e) => e.category != CombatV1CardCategory.counter,
          orElse: () => throw StateError(
            'テスト前提が崩れています: playerAの手札がCOUNTERのみです'
            '（${afterDiscard.playerA.hand.map((e) => e.cardId).join(', ')}）',
          ),
        );

        final declared = CombatV1Engine.declareTechnique(
          afterDiscard,
          attackEntry.instanceId,
          catalog: productionCardCatalog,
          rules: rules,
        );
        expect(declared.phase, CombatV1MatchPhase.counterResponsePending);
        expect(declared.pendingAttack, isNotNull);

        final pendingResult = validateMatchStateInvariants(
          declared,
          rules: rules,
        );
        expect(
          pendingResult.isValid,
          isTrue,
          reason: pendingResult.errors.join(' / '),
        );
        expect(_allInstanceIds(declared).toSet().length, 60);

        final resolved = CombatV1Engine.declineCounter(
          declared,
          rules: rules,
          random: random,
        );
        expect(resolved.phase, CombatV1MatchPhase.action);
        expect(resolved.pendingAttack, isNull);

        final totalA =
            resolved.playerA.hand.length +
            resolved.playerA.drawPile.length +
            resolved.playerA.discardPile.length;
        final totalB =
            resolved.playerB.hand.length +
            resolved.playerB.drawPile.length +
            resolved.playerB.discardPile.length;
        expect(totalA, 30);
        expect(totalB, 30);

        final resolvedResult = validateMatchStateInvariants(
          resolved,
          rules: rules,
        );
        expect(
          resolvedResult.isValid,
          isTrue,
          reason: resolvedResult.errors.join(' / '),
        );
        expect(_allInstanceIds(resolved).toSet().length, 60);

        expect(
          resolved.playerA.discardPile.any(
            (e) => e.instanceId == attackEntry.instanceId,
          ),
          isTrue,
        );
      },
    );

    test(
      'declareTechnique→playCounterの1経路を通しても、両player全ゾーン+pendingで'
      'instanceId衝突が起きない（異なるレスラー同士のCOUNTER成立）',
      () {
        // 攻撃側（Akari, playerA）手札にakari_middle_kick
        // （family=kick、group=STRIKE）、防御側（Reina, playerB）手札に
        // counter_reina_silver_flash_counter…ではなくLARIAT専用のため、
        // Reinaが実際に保有するCounterのうちSTRIKE群を返せるものは無い
        // （Reinaの3 Counterはthrowing/joint/strikeのいずれもLARIAT・
        // CROSSFACE・FIGURE_FOUR・THROW群専用）。異なるレスラー同士でも
        // COUNTER matchingが正しく機能することを確認するため、Akariの
        // akari_swing_ddt（family=ddt、group=THROW）をReinaの広範囲型
        // counter_reina_leg_catch_guard（counterableGroups=[THROW]）で
        // 返す組み合わせを使う。
        final playerA = CombatV1PlayerState(
          wrestlerId: akariWrestler.id,
          wrestlerName: akariWrestler.name,
          maxHp: rules.startingHp,
          hp: rules.startingHp,
          koc: rules.startingKoc,
          pinCardsHeld: rules.startingPinCards,
          energyPool: akariWrestler.energyPool,
          hand: const [
            CombatV1DeckEntry(
              instanceId: 'player-a_akari_swing_ddt_#0',
              cardId: 'akari_swing_ddt',
              category: CombatV1CardCategory.normal,
            ),
          ],
          drawPile: const [
            CombatV1DeckEntry(
              instanceId: 'player-a_akari_elbow_smash_#0',
              cardId: 'akari_elbow_smash',
              category: CombatV1CardCategory.normal,
            ),
          ],
        );
        final playerB = CombatV1PlayerState(
          wrestlerId: reinaWrestler.id,
          wrestlerName: reinaWrestler.name,
          maxHp: rules.startingHp,
          hp: rules.startingHp,
          koc: rules.startingKoc,
          pinCardsHeld: rules.startingPinCards,
          energyPool: reinaWrestler.energyPool,
          hand: const [
            CombatV1DeckEntry(
              instanceId: 'player-b_counter_reina_leg_catch_guard_#0',
              cardId: 'counter_reina_leg_catch_guard',
              category: CombatV1CardCategory.counter,
            ),
          ],
          drawPile: const [
            CombatV1DeckEntry(
              instanceId: 'player-b_reina_side_headlock_#0',
              cardId: 'reina_side_headlock',
              category: CombatV1CardCategory.normal,
            ),
          ],
        );
        final state = CombatV1MatchState(
          matchId: 'phase10c-akari-vs-reina-counter-test',
          playerA: playerA,
          playerB: playerB,
          activePlayerIndex: 0,
          phase: CombatV1MatchPhase.action,
        );

        final declared = CombatV1Engine.declareTechnique(
          state,
          'player-a_akari_swing_ddt_#0',
          catalog: productionCardCatalog,
          rules: rules,
        );
        expect(declared.phase, CombatV1MatchPhase.counterResponsePending);

        final countered = CombatV1Engine.playCounter(
          declared,
          'player-b_counter_reina_leg_catch_guard_#0',
          catalog: productionCardCatalog,
          rules: rules,
        );
        expect(countered.phase, CombatV1MatchPhase.action);
        expect(countered.pendingAttack, isNull);

        expect(
          countered.playerA.discardPile.any(
            (e) => e.instanceId == 'player-a_akari_swing_ddt_#0',
          ),
          isTrue,
        );
        expect(
          countered.playerB.discardPile.any(
            (e) => e.instanceId == 'player-b_counter_reina_leg_catch_guard_#0',
          ),
          isTrue,
        );

        final result = validateMatchStateInvariants(countered, rules: rules);
        expect(result.isValid, isTrue, reason: result.errors.join(' / '));
        expect(_allInstanceIds(countered).toSet().length, 4);
      },
    );
  });
}
