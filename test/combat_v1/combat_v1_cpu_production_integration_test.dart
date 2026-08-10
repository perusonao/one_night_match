// Combat Ver.1 Phase 11B: Production Match Setup（Phase 11A）を使った
// CPU基盤の統合テスト。
//
// misaki/jack/akari/reinaの4 Production Wrestler全てでenumerate→choose→
// executeが成功すること、代表的なmatchup（cross-wrestler・mirror）で
// bounded runnerが必ずmatchOver/safetyLimitのいずれかを返すこと、
// 複数seedでのproperty-likeな安定性、reproducibility、card
// conservationを検証する。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_action_executor.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_cpu_match_runner.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_decision_policy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action_enumerator.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_production_catalog.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_production_match_setup.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_state_invariants.dart';

const CombatV1RulesConfig rules = CombatV1RulesConfig();
const List<String> productionWrestlerIds = ['misaki', 'jack', 'akari', 'reina'];

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

void _expectCardConservation(CombatV1MatchState state) {
  final ids = _allInstanceIds(state);
  expect(ids.toSet().length, ids.length, reason: 'instanceIdが重複しています');

  final pendingOwnerA =
      state.pendingAttack?.attackerPlayerIndex == 0 ? 1 : 0;
  final pendingOwnerB =
      state.pendingAttack?.attackerPlayerIndex == 1 ? 1 : 0;
  final totalA =
      state.playerA.hand.length +
      state.playerA.drawPile.length +
      state.playerA.discardPile.length +
      pendingOwnerA;
  final totalB =
      state.playerB.hand.length +
      state.playerB.drawPile.length +
      state.playerB.discardPile.length +
      pendingOwnerB;
  expect(totalA, 30, reason: 'playerAの物理カード合計が30枚ではありません');
  expect(totalB, 30, reason: 'playerBの物理カード合計が30枚ではありません');
}

CombatV1MatchState _startMatch({
  required String wrestlerAId,
  required String wrestlerBId,
  required Random random,
}) => CombatV1ProductionMatchStarter.start(
  CombatV1ProductionMatchConfig(
    wrestlerAId: wrestlerAId,
    wrestlerBId: wrestlerBId,
    playerAOwnerId: 'player-a',
    playerBOwnerId: 'player-b',
    rules: rules,
  ),
  random: random,
);

void _expectMatchAndPlayerInvariants(CombatV1MatchState state) {
  final matchResult = validateMatchStateInvariants(state, rules: rules);
  expect(matchResult.isValid, isTrue, reason: matchResult.errors.join(' / '));

  final playerAResult = validatePlayerStateInvariants(state.playerA);
  expect(playerAResult.isValid, isTrue, reason: playerAResult.errors.join(' / '));

  final playerBResult = validatePlayerStateInvariants(state.playerB);
  expect(playerBResult.isValid, isTrue, reason: playerBResult.errors.join(' / '));
}

void main() {
  group('41. 4 Production Wrestler decision test（discard→Technique実行まで）', () {
    for (final wrestlerId in productionWrestlerIds) {
      test('$wrestlerId: Production Wrestler → Deck → Catalog → Enumerator → '
          'Executor → EngineのTechnique経路が実際に接続される', () {
        var state = _startMatch(
          wrestlerAId: wrestlerId,
          wrestlerBId: 'misaki',
          random: Random(1),
        );
        expect(state.phase, CombatV1MatchPhase.discard);

        // 1〜3. discard phaseで合法discardを取得して実行する。
        final discardActions = CombatV1LegalActionEnumerator.enumerate(
          state,
          catalog: productionCardCatalog,
          rules: rules,
        );
        expect(discardActions, isNotEmpty);
        final discardAction = discardActions.first as CombatV1DiscardAction;
        // 7. physical instanceIdを確認（cardIdではなく物理instanceIdである
        // こと）。
        expect(
          state.playerA.hand.any((e) => e.instanceId == discardAction.cardInstanceId),
          isTrue,
        );

        state = CombatV1ActionExecutor.execute(
          state,
          discardAction,
          catalog: productionCardCatalog,
          rules: rules,
        );

        // 4. action phaseへ到達する。
        expect(state.phase, CombatV1MatchPhase.action);

        // 5〜6. LegalActionEnumeratorで合法手を取得し、少なくとも1つ
        // 合法Techniqueが存在することを確認する。
        final actionPhaseActions = CombatV1LegalActionEnumerator.enumerate(
          state,
          catalog: productionCardCatalog,
          rules: rules,
        );
        final techniqueActions =
            actionPhaseActions.whereType<CombatV1TechniqueAction>().toList()
              ..sort((a, b) => a.cardInstanceId.compareTo(b.cardInstanceId));
        expect(
          techniqueActions,
          isNotEmpty,
          reason: '$wrestlerIdの初期手札にlegalなTechniqueが1枚も無い'
              '（Production Deckの構成上、通常のstarting handでは発生しない想定）',
        );
        final techniqueAction = techniqueActions.first;
        expect(
          state.playerA.hand.any((e) => e.instanceId == techniqueAction.cardInstanceId),
          isTrue,
        );

        // 8〜9. Technique actionをExecutorで実行し、Engineにillegalとして
        // 拒否されないことを確認する。
        expect(
          () => state = CombatV1ActionExecutor.execute(
            state,
            techniqueAction,
            catalog: productionCardCatalog,
            rules: rules,
            random: Random(2),
          ),
          returnsNormally,
        );

        // 10. Technique宣言後の正しいphaseへ遷移する
        // （counterResponsePending、docs/combat_rules_v1.md 7.1章）。
        expect(state.phase, CombatV1MatchPhase.counterResponsePending);
        expect(state.pendingAttack?.attackCardInstance.instanceId, techniqueAction.cardInstanceId);

        // 11〜14. state/player invariant・card conservation・instanceId
        // uniquenessを確認する。
        _expectMatchAndPlayerInvariants(state);
        _expectCardConservation(state);
      });
    }
  });

  group('42. Production match integration（CPU Runner）', () {
    void runMatchupAndVerify(
      String wrestlerAId,
      String wrestlerBId,
      int seed,
    ) {
      final state = _startMatch(
        wrestlerAId: wrestlerAId,
        wrestlerBId: wrestlerBId,
        random: Random(seed),
      );
      final runner = CombatV1CpuMatchRunner(
        catalog: productionCardCatalog,
        rules: rules,
      );

      final result = runner.run(
        state,
        policyA: CombatV1RandomLegalPolicy(Random(seed * 2 + 1)),
        policyB: CombatV1RandomLegalPolicy(Random(seed * 2 + 2)),
        engineRandom: Random(seed * 2 + 3),
      );

      // B. bounded runnerが必ずmatchOver/safetyLimitのいずれかを返す
      // （invariantViolationにはならない）。
      expect(
        result.termination,
        anyOf(
          CombatV1CpuMatchTermination.matchOver,
          CombatV1CpuMatchTermination.safetyLimit,
        ),
        reason: result.invariantViolationMessage ?? '',
      );
      expect(result.actionCount, lessThanOrEqualTo(500));

      if (result.termination == CombatV1CpuMatchTermination.matchOver) {
        expect(result.finalState.winnerPlayerIndex, anyOf(0, 1));
      } else {
        expect(result.finalState.winnerPlayerIndex, isNull);
      }

      // C. どちらでもinvariant/card conservationが壊れない。
      final invariantResult = validateMatchStateInvariants(
        result.finalState,
        rules: rules,
      );
      expect(invariantResult.isValid, isTrue, reason: invariantResult.errors.join(' / '));
      _expectCardConservation(result.finalState);
    }

    test('A. Misaki vs Jack', () => runMatchupAndVerify('misaki', 'jack', 100));
    test('B. Akari vs Reina', () => runMatchupAndVerify('akari', 'reina', 200));
    test('C. mirror: Misaki vs Misaki', () => runMatchupAndVerify('misaki', 'misaki', 300));
  });

  group('43. Multiple seed tests（RandomLegal、seed 0..19）', () {
    test('exceptionなし・bounded result・invariant維持・actions<=500・'
        'matchOverならwinner valid・safetyLimitならwinner捏造なし', () {
      var matchOverCount = 0;
      var safetyLimitCount = 0;

      for (var seed = 0; seed < 20; seed++) {
        final state = _startMatch(
          wrestlerAId: 'misaki',
          wrestlerBId: 'jack',
          random: Random(seed),
        );
        final runner = CombatV1CpuMatchRunner(
          catalog: productionCardCatalog,
          rules: rules,
        );

        final result = runner.run(
          state,
          policyA: CombatV1RandomLegalPolicy(Random(seed * 3 + 1)),
          policyB: CombatV1RandomLegalPolicy(Random(seed * 3 + 2)),
          engineRandom: Random(seed * 3 + 3),
        );

        expect(
          result.termination,
          isNot(CombatV1CpuMatchTermination.invariantViolation),
          reason: 'seed=$seed: ${result.invariantViolationMessage}',
        );
        expect(result.actionCount, lessThanOrEqualTo(500), reason: 'seed=$seed');

        final invariantResult = validateMatchStateInvariants(
          result.finalState,
          rules: rules,
        );
        expect(invariantResult.isValid, isTrue, reason: 'seed=$seed: ${invariantResult.errors.join(' / ')}');
        _expectCardConservation(result.finalState);

        if (result.termination == CombatV1CpuMatchTermination.matchOver) {
          matchOverCount++;
          expect(result.finalState.winnerPlayerIndex, anyOf(0, 1), reason: 'seed=$seed');
        } else {
          safetyLimitCount++;
          expect(result.finalState.winnerPlayerIndex, isNull, reason: 'seed=$seed');
        }
      }

      // 全seedでmatchOverを要求しない（safetyLimitで終わるseedがあってもよい）。
      expect(matchOverCount + safetyLimitCount, 20);
    });
  });

  group('44. Random reproducibility test', () {
    test('同matchup・同config・同decision/engine seed・同policyなら'
        'termination/winner/actionCount/turnCountが再現する', () {
      CombatV1CpuMatchResult run() {
        final state = _startMatch(
          wrestlerAId: 'akari',
          wrestlerBId: 'reina',
          random: Random(77),
        );
        final runner = CombatV1CpuMatchRunner(
          catalog: productionCardCatalog,
          rules: rules,
        );
        return runner.run(
          state,
          policyA: CombatV1RandomLegalPolicy(Random(1001)),
          policyB: CombatV1RandomLegalPolicy(Random(1002)),
          engineRandom: Random(1003),
        );
      }

      final resultA = run();
      final resultB = run();

      expect(resultA.termination, resultB.termination);
      expect(resultA.finalState.winnerPlayerIndex, resultB.finalState.winnerPlayerIndex);
      expect(resultA.actionCount, resultB.actionCount);
      expect(resultA.finalTurnNumber, resultB.finalTurnNumber);
    });
  });

  group('45. Card conservation', () {
    test('CPU match中もphysical card invariantを維持する（各player30枚・'
        'instanceId unique）', () {
      final state = _startMatch(
        wrestlerAId: 'jack',
        wrestlerBId: 'reina',
        random: Random(55),
      );
      _expectCardConservation(state);

      final runner = CombatV1CpuMatchRunner(
        catalog: productionCardCatalog,
        rules: rules,
      );
      final result = runner.run(
        state,
        policyA: CombatV1RandomLegalPolicy(Random(56)),
        policyB: CombatV1RandomLegalPolicy(Random(57)),
        engineRandom: Random(58),
      );

      _expectCardConservation(result.finalState);
    });
  });
}
