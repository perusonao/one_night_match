// Combat Ver.1 Phase 11B: CombatV1CpuMatchRunnerのテスト。
//
// bounded single CPU vs CPU matchの進行・termination区別・actionCount
// semantics・invariant strategy・RNG分離・Structured Action
// Observationを、fixture data（非Production）で検証する。Production
// wrestlerを使った4人統合test・multi-seed test・reproducibility
// testは`combat_v1_cpu_production_integration_test.dart`側に分離する。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_action_observer.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_cpu_match_runner.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_decision_policy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';

import 'combat_v1_test_fixtures.dart';

const CombatV1RulesConfig rules = fixtureRules;

/// safetyLimit到達を確実に検証するためのtest専用policy（Phase 11B項目
/// 40）。Production policyとして公開しない——決着を意図的に避け、
/// endTurn/standUp/discard/declineCounterのみを選び続ける。
class _AlwaysContinuePolicy implements CombatV1DecisionPolicy {
  const _AlwaysContinuePolicy();

  @override
  String get id => 'test-always-continue';

  static const List<CombatV1LegalActionKind> _avoidFinishOrder = [
    CombatV1LegalActionKind.endTurn,
    CombatV1LegalActionKind.standUp,
    CombatV1LegalActionKind.declineCounter,
    CombatV1LegalActionKind.discard,
  ];

  @override
  CombatV1LegalAction choose(
    CombatV1MatchState state,
    List<CombatV1LegalAction> legalActions,
  ) {
    if (legalActions.isEmpty) {
      throw CombatV1IllegalActionException('_AlwaysContinuePolicy: legalActionsが空です');
    }
    for (final kind in _avoidFinishOrder) {
      final match = legalActions.where((a) => a.kind == kind);
      if (match.isNotEmpty) return match.first;
    }
    return legalActions.first;
  }
}

/// 呼び出しごとに[state]を記録しつつ[_delegate]へ委譲するspy policy
/// （「actor毎に正しいpolicyが使われるか」を検証するため）。
class _RecordingPolicy implements CombatV1DecisionPolicy {
  _RecordingPolicy(this.id, this._delegate);

  @override
  final String id;
  final CombatV1DecisionPolicy _delegate;
  final List<CombatV1MatchState> statesSeen = [];
  final List<CombatV1LegalAction> chosenActions = [];

  @override
  CombatV1LegalAction choose(
    CombatV1MatchState state,
    List<CombatV1LegalAction> legalActions,
  ) {
    statesSeen.add(state);
    final chosen = _delegate.choose(state, legalActions);
    chosenActions.add(chosen);
    return chosen;
  }
}

class _RecordingObserver implements CombatV1ActionObserver {
  final List<CombatV1ActionObservation> observations = [];

  @override
  void onActionResolved(CombatV1ActionObservation observation) {
    observations.add(observation);
  }
}

void main() {
  group('A. start直後のinvariant違反はinvariantViolationとして即終了する', () {
    test('winnerPlayerIndexが0/1/null以外のstateはactionを1つも実行せず停止する', () {
      final malformed = buildMatchState(winnerPlayerIndex: 5);
      final runner = CombatV1CpuMatchRunner(catalog: fixtureCatalog, rules: rules);

      final result = runner.run(
        malformed,
        policyA: const CombatV1FirstLegalPolicy(),
        policyB: const CombatV1FirstLegalPolicy(),
      );

      expect(result.termination, CombatV1CpuMatchTermination.invariantViolation);
      expect(result.actionCount, 0);
      expect(result.lastAction, isNull);
      expect(result.invariantViolationMessage, isNotNull);
    });
  });

  group('C. matchOverで正常終了する（deterministic path）', () {
    test('defender koc不足の3カウントPINで即座に決着する', () {
      // 攻撃側がPIN宣言可能な状態（相手DOWN・今ターンTECHNIQUE成功済み）
      // を直接構築し、防御側kocを0にすることでPINが確実に3カウント
      // （即決着）になるようにする（determinePinCountResultは
      // 非randomな純粋関数、combat_v1_pin_rules.dart参照）。
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocB: 0,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final runner = CombatV1CpuMatchRunner(catalog: fixtureCatalog, rules: rules);

      final result = runner.run(
        state,
        policyA: const CombatV1FirstLegalPolicy(), // PINが最優先で選ばれる
        policyB: const CombatV1FirstLegalPolicy(),
        engineRandom: Random(1),
      );

      expect(result.termination, CombatV1CpuMatchTermination.matchOver);
      expect(result.actionCount, 1);
      expect(result.lastAction, isA<CombatV1PinAction>());
      expect(result.terminalCause, CombatV1CpuMatchTerminalCause.normalPin);
      expect(result.hasWinner, isTrue);
      expect(result.finalState.winnerPlayerIndex, 0);
    });
  });

  group('D/E. maxActions到達でsafetyLimit（matchOverとは区別する）', () {
    test('winnerを捏造せず、matchOverとは異なるterminationを返す', () {
      final state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck(fixtureWrestlerA.id),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck(fixtureWrestlerB.id),
        rules: rules,
        catalog: fixtureCatalog,
        random: Random(1),
      );
      final runner = CombatV1CpuMatchRunner(
        catalog: fixtureCatalog,
        rules: rules,
        maxActions: 12,
      );

      final result = runner.run(
        state,
        policyA: const _AlwaysContinuePolicy(),
        policyB: const _AlwaysContinuePolicy(),
        engineRandom: Random(2),
      );

      expect(result.termination, CombatV1CpuMatchTermination.safetyLimit);
      expect(result.actionCount, 12);
      expect(result.hasWinner, isFalse);
      expect(result.finalState.winnerPlayerIndex, isNull);
      expect(result.terminalCause, isNull);
    });
  });

  group('G. non-terminal正常stateで空Actionはfail-fastする', () {
    test('discardフェーズでhandが0枚のstateはinvariantViolationになる', () {
      final malformed = buildMatchState(
        phase: CombatV1MatchPhase.discard,
        handA: const [],
      );
      final runner = CombatV1CpuMatchRunner(catalog: fixtureCatalog, rules: rules);

      final result = runner.run(
        malformed,
        policyA: const CombatV1FirstLegalPolicy(),
        policyB: const CombatV1FirstLegalPolicy(),
      );

      expect(result.termination, CombatV1CpuMatchTermination.invariantViolation);
      expect(result.actionCount, 0);
      expect(result.invariantViolationMessage, contains('legal action'));
    });
  });

  group('policy A/Bをactive actorごとに正しく使用する', () {
    test('activePlayerIndex==0のときpolicyAが、==1のときpolicyBが呼ばれる', () {
      final recordingA = _RecordingPolicy('A', const CombatV1FirstLegalPolicy());
      final recordingB = _RecordingPolicy('B', const CombatV1FirstLegalPolicy());
      final runner = CombatV1CpuMatchRunner(
        catalog: fixtureCatalog,
        rules: rules,
        maxActions: 1,
      );

      final stateActiveA = buildMatchState();
      runner.run(stateActiveA, policyA: recordingA, policyB: recordingB);
      expect(recordingA.statesSeen.length, 1);
      expect(recordingB.statesSeen.length, 0);

      final recordingA2 = _RecordingPolicy('A', const CombatV1FirstLegalPolicy());
      final recordingB2 = _RecordingPolicy('B', const CombatV1FirstLegalPolicy());
      final stateActiveB = buildMatchState(activePlayerIndex: 1);
      runner.run(stateActiveB, policyA: recordingA2, policyB: recordingB2);
      expect(recordingA2.statesSeen.length, 0);
      expect(recordingB2.statesSeen.length, 1);
    });

    test('counterResponsePendingでは防御側のpolicyが使われる'
        '（activePlayerIndexは攻撃側のままでも）', () {
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
      final base = buildMatchState(
        handA: const [attack],
        handB: const [counter],
        activePlayerIndex: 0, // 攻撃側=playerA(policyA)
      );
      final pending = CombatV1Engine.declareTechnique(
        base,
        'atk1',
        catalog: fixtureCatalog,
      );

      final recordingA = _RecordingPolicy('A', const CombatV1FirstLegalPolicy());
      final recordingB = _RecordingPolicy('B', const CombatV1FirstLegalPolicy());
      final runner = CombatV1CpuMatchRunner(
        catalog: fixtureCatalog,
        rules: rules,
        maxActions: 1,
      );

      runner.run(pending, policyA: recordingA, policyB: recordingB, engineRandom: Random(1));

      // activePlayerIndexは攻撃側(playerA)のままだが、防御側(playerB)の
      // policyが応答に使われる。
      expect(pending.activePlayerIndex, 0);
      expect(recordingA.statesSeen.length, 0);
      expect(recordingB.statesSeen.length, 1);
    });
  });

  group('actionCount semantics（addendum項目1・15 A/B/C）', () {
    test('A. discardもactionCountに含まれる', () {
      final state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck(fixtureWrestlerA.id),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck(fixtureWrestlerB.id),
        rules: rules,
        catalog: fixtureCatalog,
        random: Random(3),
      );
      final runner = CombatV1CpuMatchRunner(
        catalog: fixtureCatalog,
        rules: rules,
        maxActions: 1,
      );

      final result = runner.run(
        state,
        policyA: const CombatV1FirstLegalPolicy(),
        policyB: const CombatV1FirstLegalPolicy(),
        engineRandom: Random(4),
      );

      expect(result.actionCount, 1);
      expect(result.lastAction, isA<CombatV1DiscardAction>());
    });

    test('B. declareTechniqueとCounter/declineは別actionとしてcountされる', () {
      const legalStrike = CombatV1DeckEntry(
        instanceId: 'legal-strike',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: const [legalStrike]);
      final runner = CombatV1CpuMatchRunner(
        catalog: fixtureCatalog,
        rules: rules,
        maxActions: 1,
      );

      final afterDeclare = runner.run(
        state,
        policyA: const CombatV1FirstLegalPolicy(),
        policyB: const CombatV1FirstLegalPolicy(),
        engineRandom: Random(1),
      );
      expect(afterDeclare.actionCount, 1);
      expect(afterDeclare.lastAction, isA<CombatV1TechniqueAction>());
      expect(afterDeclare.finalState.phase, CombatV1MatchPhase.counterResponsePending);

      final afterDecline = runner.run(
        afterDeclare.finalState,
        policyA: const CombatV1FirstLegalPolicy(),
        policyB: const CombatV1FirstLegalPolicy(),
        engineRandom: Random(2),
      );
      expect(afterDecline.actionCount, 1);
      expect(afterDecline.lastAction, isA<CombatV1DeclineCounterAction>());
    });

    test('C. automatic directPin resolutionは追加actionとしてcountされない', () {
      const directPinTechnique = CombatV1DeckEntry(
        instanceId: 'dp1',
        cardId: 'fx_normal_direct_pin', // directPin:true, cost throwing1
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(
        handA: const [directPinTechnique],
        handB: const [], // COUNTERが手札に無いのでdeclineCounter一択
        kocB: 0, // DIRECT PIN到達時に即3カウントで決着させる
      );
      final runner = CombatV1CpuMatchRunner(catalog: fixtureCatalog, rules: rules);

      final result = runner.run(
        state,
        policyA: const CombatV1FirstLegalPolicy(),
        policyB: const CombatV1FirstLegalPolicy(),
        engineRandom: Random(1),
      );

      // declareTechnique(1) + declineCounter(1、内部でDIRECT PIN自動解決) =
      // 2 action。PIN解決自体は追加countされない。
      expect(result.actionCount, 2);
      expect(result.termination, CombatV1CpuMatchTermination.matchOver);
      expect(result.terminalCause, CombatV1CpuMatchTerminalCause.directPin);
    });
  });

  group('Structured Action Observation（addendum項目7・15 L/M）', () {
    test('L. observerはaction前後のstateを受け取れる', () {
      final state = buildMatchState(); // action/STAND、legalはendTurnのみ想定
      final observer = _RecordingObserver();
      final runner = CombatV1CpuMatchRunner(
        catalog: fixtureCatalog,
        rules: rules,
        maxActions: 1,
      );

      runner.run(
        state,
        policyA: const CombatV1FirstLegalPolicy(),
        policyB: const CombatV1FirstLegalPolicy(),
        observer: observer,
      );

      expect(observer.observations.length, 1);
      final obs = observer.observations.single;
      expect(obs.actionIndex, 0);
      expect(obs.turnNumber, 1);
      expect(obs.actorPlayerIndex, 0);
      expect(obs.action, isA<CombatV1EndTurnAction>());
      expect(obs.stateBefore.turnNumber, 1);
      expect(obs.stateAfter.turnNumber, 2);
      expect(obs.stateAfter.activePlayerIndex, 1);
    });

    test('M. observerを渡さなくてもrunnerは正常動作する', () {
      final state = buildMatchState();
      final runner = CombatV1CpuMatchRunner(
        catalog: fixtureCatalog,
        rules: rules,
        maxActions: 1,
      );

      expect(
        () => runner.run(
          state,
          policyA: const CombatV1FirstLegalPolicy(),
          policyB: const CombatV1FirstLegalPolicy(),
        ),
        returnsNormally,
      );
    });
  });

  group('P. safetyLimit diagnostic metadata', () {
    test('actionCount/maxActions/finalTurnNumber/phase/activePlayer/'
        'pendingAttack有無/lastActionが確認できる', () {
      final state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck(fixtureWrestlerA.id),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck(fixtureWrestlerB.id),
        rules: rules,
        catalog: fixtureCatalog,
        random: Random(5),
      );
      final runner = CombatV1CpuMatchRunner(
        catalog: fixtureCatalog,
        rules: rules,
        maxActions: 9,
      );

      final result = runner.run(
        state,
        policyA: const _AlwaysContinuePolicy(),
        policyB: const _AlwaysContinuePolicy(),
        engineRandom: Random(6),
      );

      expect(result.termination, CombatV1CpuMatchTermination.safetyLimit);
      expect(result.actionCount, 9);
      expect(result.maxActions, 9);
      expect(result.finalTurnNumber, greaterThanOrEqualTo(1));
      expect(result.lastPhase, isNotNull);
      expect(result.lastActivePlayerIndex, anyOf(0, 1));
      expect(result.hasPendingAttack, isFalse);
      expect(result.lastAction, isNotNull);
    });
  });

  group('RNG分離（addendum項目4・15 H/I）', () {
    test('H. playerAの最初の意思決定はplayerBのRandom seedへ依存しない', () {
      CombatV1LegalAction? firstChoiceOfA(int seedB) {
        final state = CombatV1Engine.start(
          wrestlerA: fixtureWrestlerA,
          deckA: fixtureDeck(fixtureWrestlerA.id),
          wrestlerB: fixtureWrestlerB,
          deckB: fixtureDeck(fixtureWrestlerB.id),
          rules: rules,
          catalog: fixtureCatalog,
          random: Random(10), // start()のshuffle用seedは固定
        );
        final policyA = _RecordingPolicy(
          'A',
          CombatV1RandomLegalPolicy(Random(20)), // playerAのseedは固定
        );
        final policyB = CombatV1RandomLegalPolicy(Random(seedB));
        final runner = CombatV1CpuMatchRunner(
          catalog: fixtureCatalog,
          rules: rules,
          maxActions: 1, // playerAの最初の1手のみ
        );
        runner.run(state, policyA: policyA, policyB: policyB, engineRandom: Random(30));
        return policyA.chosenActions.singleOrNull;
      }

      final choiceWithSeedB1 = firstChoiceOfA(111);
      final choiceWithSeedB2 = firstChoiceOfA(222);

      expect(choiceWithSeedB1, isNotNull);
      expect(choiceWithSeedB1, choiceWithSeedB2);
    });

    test('I. engineRandomのseedを変えてもpolicy選択列とfinalStateは'
        '変化しない（reshuffleが発生しない短いbounded runの範囲で）', () {
      CombatV1CpuMatchResult runWith(Random engineRandom) {
        final state = CombatV1Engine.start(
          wrestlerA: fixtureWrestlerA,
          deckA: fixtureDeck(fixtureWrestlerA.id),
          wrestlerB: fixtureWrestlerB,
          deckB: fixtureDeck(fixtureWrestlerB.id),
          rules: rules,
          catalog: fixtureCatalog,
          random: Random(40), // start()のshuffle seedは固定（同じ初期手札）
        );
        final runner = CombatV1CpuMatchRunner(
          catalog: fixtureCatalog,
          rules: rules,
          maxActions: 4,
        );
        return runner.run(
          state,
          policyA: const CombatV1FirstLegalPolicy(),
          policyB: const CombatV1FirstLegalPolicy(),
          engineRandom: engineRandom,
        );
      }

      final resultA = runWith(Random(1));
      final resultB = runWith(Random(999999));

      expect(resultA.actionCount, resultB.actionCount);
      expect(resultA.termination, resultB.termination);
      expect(resultA.lastAction, resultB.lastAction);
      expect(resultA.finalState.turnNumber, resultB.finalState.turnNumber);
      expect(resultA.finalState.phase, resultB.finalState.phase);
    });
  });
}
