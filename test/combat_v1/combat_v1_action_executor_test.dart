// Combat Ver.1 Phase 11B: CombatV1ActionExecutorのテスト。
//
// 8 Action variant全てが対応するEngine Commandへ正しく接続されること、
// actor mismatch・stale actionがfail-fastすることを検証する。Engine
// ルールの再実装が無いこと（既存Engineの結果とActor経由の結果が一致する
// こと）も併せて確認する。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_action_executor.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';

import 'combat_v1_test_fixtures.dart';

const CombatV1RulesConfig rules = fixtureRules;

CombatV1MatchState _execute(CombatV1MatchState state, CombatV1LegalAction action) =>
    CombatV1ActionExecutor.execute(
      state,
      action,
      catalog: fixtureCatalog,
      rules: rules,
      random: Random(7),
    );

void main() {
  group('8 Action variant mapping', () {
    test('DiscardAction → CombatV1Engine.discardCard', () {
      const card = CombatV1DeckEntry(
        instanceId: 'h1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(
        phase: CombatV1MatchPhase.discard,
        handA: [card],
      );

      final viaExecutor = _execute(
        state,
        const CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
      );
      final viaEngine = CombatV1Engine.discardCard(state, 'h1');

      expect(viaExecutor.playerA.hand, viaEngine.playerA.hand);
      expect(viaExecutor.playerA.discardPile, viaEngine.playerA.discardPile);
      expect(viaExecutor.phase, CombatV1MatchPhase.action);
    });

    test('TechniqueAction → declareTechnique', () {
      const card = CombatV1DeckEntry(
        instanceId: 'h1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [card]);

      final result = _execute(
        state,
        const CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
      );

      expect(result.phase, CombatV1MatchPhase.counterResponsePending);
      expect(result.pendingAttack?.attackCardInstance.instanceId, 'h1');
    });

    test('CounterAction → playCounter', () {
      const attack = CombatV1DeckEntry(
        instanceId: 'atk1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      const counter = CombatV1DeckEntry(
        instanceId: 'ctr1',
        cardId: 'fx_counter_a',
        category: CombatV1CardCategory.counter,
      );
      // drawPileへfillerを用意しておく（decline/counter直後の1
      // drawで、drawPile空→捨て札再構築が起き、直前に捨てたばかりの
      // カードが即座に引き戻されてしまうのを避けるため、
      // combat_v1_counter_resolution_test.dartと同じ理由）。
      const fillerA = CombatV1DeckEntry(
        instanceId: 'fillerA',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      const fillerB = CombatV1DeckEntry(
        instanceId: 'fillerB',
        cardId: 'fx_counter_a',
        category: CombatV1CardCategory.counter,
      );
      final state = buildMatchState(
        handA: const [attack],
        handB: const [counter],
        drawPileA: const [fillerA],
        drawPileB: const [fillerB],
      );
      final pending = CombatV1Engine.declareTechnique(
        state,
        'atk1',
        catalog: fixtureCatalog,
      );

      final result = _execute(
        pending,
        const CombatV1CounterAction(actorPlayerIndex: 1, cardInstanceId: 'ctr1'),
      );

      expect(result.pendingAttack, isNull);
      expect(result.phase, CombatV1MatchPhase.action);
      expect(
        result.playerB.discardPile.any((e) => e.instanceId == 'ctr1'),
        isTrue,
      );
    });

    test('DeclineCounterAction → declineCounter', () {
      const attack = CombatV1DeckEntry(
        instanceId: 'atk1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: const [attack]);
      final pending = CombatV1Engine.declareTechnique(
        state,
        'atk1',
        catalog: fixtureCatalog,
      );

      final result = _execute(
        pending,
        const CombatV1DeclineCounterAction(actorPlayerIndex: 1),
      );

      expect(result.pendingAttack, isNull);
      expect(result.playerB.hp, 140); // 150 - fx_normal_strike damage(10)
    });

    test('PinAction → declarePin', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );

      final result = _execute(state, const CombatV1PinAction(actorPlayerIndex: 0));

      // PINが解決され、pinCardsHeldがdeclarePin前後で移動しているはず
      // （legalityはcheckPinLegalityへ委譲済みなので、ここではCommandへ
      // 正しく到達したことのみ確認する）。
      expect(
        result.playerA.pinCardsHeld + result.playerB.pinCardsHeld,
        rules.totalPinCards,
      );
    });

    test('RestAction → rest（同一Command内でターン遷移まで進む）', () {
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        hpA: 100,
      );

      final result = _execute(state, const CombatV1RestAction(actorPlayerIndex: 0));

      expect(result.playerA.hp, 100 + rules.restHpRecovery);
      expect(result.playerA.posture, CombatV1WrestlerPosture.stand);
      // restはendTurnと同じ内部処理でターンを進めるため、activePlayerIndex
      // が相手へ移る。
      expect(result.activePlayerIndex, 1);
    });

    test('StandUpAction → standUp（ターンは終了しない）', () {
      final state = buildMatchState(postureA: CombatV1WrestlerPosture.down);

      final result = _execute(
        state,
        const CombatV1StandUpAction(actorPlayerIndex: 0),
      );

      expect(result.playerA.posture, CombatV1WrestlerPosture.stand);
      expect(result.activePlayerIndex, 0); // ターンは終了しない
    });

    test('EndTurnAction → endTurn', () {
      final state = buildMatchState();

      final result = _execute(state, const CombatV1EndTurnAction(actorPlayerIndex: 0));

      expect(result.activePlayerIndex, 1);
      expect(result.turnNumber, 2);
    });
  });

  group('actor mismatch', () {
    test('technique/pin/rest/standUp/endTurnで実際のactivePlayerIndexと'
        '異なるactorPlayerIndexを渡すとfail-fastする', () {
      final state = buildMatchState();
      expect(
        () => _execute(
          state,
          const CombatV1EndTurnAction(actorPlayerIndex: 1), // 本来は0
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('counter/declineCounterで攻撃側のplayerIndexを渡すとfail-fastする', () {
      const attack = CombatV1DeckEntry(
        instanceId: 'atk1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: const [attack]);
      final pending = CombatV1Engine.declareTechnique(
        state,
        'atk1',
        catalog: fixtureCatalog,
      );

      expect(
        () => _execute(
          pending,
          const CombatV1DeclineCounterAction(actorPlayerIndex: 0), // 本来は1(防御側)
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('stale action', () {
    test('discard済みで手札に存在しないinstanceIdを渡すとEngine側の'
        'legality違反としてfail-fastする（recoverableに握り潰さない）', () {
      const card = CombatV1DeckEntry(
        instanceId: 'h1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      var state = buildMatchState(
        phase: CombatV1MatchPhase.discard,
        handA: [card],
      );
      // 実際にh1を捨てた後のstate（古いActionはもう適用できないはず）。
      state = CombatV1Engine.discardCard(state, 'h1');

      expect(
        () => _execute(
          state,
          const CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'h1'),
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('physical instance ownership', () {
    test('別playerの手札にあるinstanceIdでdiscardしようとすると'
        'Engineが拒否する', () {
      const cardA = CombatV1DeckEntry(
        instanceId: 'onlyInB',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(
        phase: CombatV1MatchPhase.discard,
        handA: const [],
        handB: const [cardA],
      );

      expect(
        () => _execute(
          state,
          const CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'onlyInB'),
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });
}
