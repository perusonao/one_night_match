// Combat Ver.1 Phase 12A: CombatV1SimulationRunner
// （lib/src/combat_v1/simulation/combat_v1_simulation_runner.dart）のtest。
//
// Phase 11Bの`CombatV1ProductionMatchStarter`/`CombatV1CpuMatchRunner`を
// そのまま呼び出す上位層として、1試合実行・複数試合実行・determinism・
// RNG分離のwiring・replay・safetyLimit保持・4 Production Wrestler起動を
// 検証する。Phase 11B自身のCPU対戦ロジック（合法手列挙・decline counter・
// terminal cause分類等）の網羅的な再テストは行わない——Simulation境界として
// 必要な確認のみを追加する。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_cpu_match_runner.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_decision_policy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_production_catalog.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_production_match_setup.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_match_simulation_result.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_policy.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_runner.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_seed.dart';

const CombatV1RulesConfig _rules = CombatV1RulesConfig();
const List<String> _productionWrestlerIds = ['misaki', 'jack', 'akari', 'reina'];

CombatV1SimulationConfig _config({
  String wrestlerAId = 'misaki',
  String wrestlerBId = 'jack',
  CombatV1SimulationPolicyKind? playerAPolicy,
  CombatV1SimulationPolicyKind? playerBPolicy,
  int matchCount = 1,
  int masterSeed = 100,
  int maxActions = 500,
}) => CombatV1SimulationConfig(
  wrestlerAId: wrestlerAId,
  wrestlerBId: wrestlerBId,
  playerAPolicy: playerAPolicy ?? CombatV1SimulationPolicyKind.randomLegal,
  playerBPolicy: playerBPolicy ?? CombatV1SimulationPolicyKind.randomLegal,
  matchCount: matchCount,
  masterSeed: masterSeed,
  maxActions: maxActions,
);

/// [CombatV1SimulationRunner.runSingleMatch]と全く同じ手順（公開されている
/// seed derivation・owner namespace関数のみを使う）で、生の
/// [CombatV1MatchState]まで再構築する。[CombatV1MatchSimulationResult]は
/// full action trace・finalState自体を保持しない設計（9章）のため、card
/// conservation・instanceId uniquenessの検証にはこの生stateが必要になる。
CombatV1MatchState _rawFinalState(
  CombatV1SimulationConfig config,
  int matchIndex,
) {
  final seeds = deriveV1SimulationSeeds(
    masterSeed: config.masterSeed,
    matchIndex: matchIndex,
    wrestlerAId: config.wrestlerAId,
    wrestlerBId: config.wrestlerBId,
    playerAPolicyId: config.playerAPolicy.policyId,
    playerBPolicyId: config.playerBPolicy.policyId,
  );

  final engineRandom = Random(seeds.engineSeed);
  final initialState = CombatV1ProductionMatchStarter.start(
    CombatV1ProductionMatchConfig(
      wrestlerAId: config.wrestlerAId,
      wrestlerBId: config.wrestlerBId,
      playerAOwnerId: combatV1SimulationOwnerId(
        masterSeed: config.masterSeed,
        matchIndex: matchIndex,
        playerSuffix: 'a',
      ),
      playerBOwnerId: combatV1SimulationOwnerId(
        masterSeed: config.masterSeed,
        matchIndex: matchIndex,
        playerSuffix: 'b',
      ),
      rules: config.rules,
    ),
    random: engineRandom,
  );

  final policyA = config.playerAPolicy.createFresh(
    Random(seeds.playerAPolicySeed),
  );
  final policyB = config.playerBPolicy.createFresh(
    Random(seeds.playerBPolicySeed),
  );

  final cpuRunner = CombatV1CpuMatchRunner(
    catalog: productionCardCatalog,
    rules: config.rules,
    maxActions: config.maxActions,
  );

  return cpuRunner
      .run(
        initialState,
        policyA: policyA,
        policyB: policyB,
        engineRandom: engineRandom,
      )
      .finalState;
}

/// RNG separation testing専用policy（F. RNG separation参照）。決定自体は
/// 常に[CombatV1FirstLegalPolicy]へ委譲する（deterministic）が、その前に
/// 自前のPolicy Randomから[burnCount]回`nextInt`を消費する——「playerAの
/// Policy Random消費回数」だけを変化させ、選択結果自体は固定したまま
/// Engine Random/finalStateへの漏れを検出するためのtest policy。
class _BurnThenFirstLegalPolicy implements CombatV1DecisionPolicy {
  _BurnThenFirstLegalPolicy(this._policyRandom, this.burnCount);

  final Random _policyRandom;
  final int burnCount;

  @override
  String get id => 'burnThenFirstLegal';

  @override
  CombatV1LegalAction choose(
    CombatV1MatchState state,
    List<CombatV1LegalAction> legalActions,
  ) {
    for (var i = 0; i < burnCount; i++) {
      _policyRandom.nextInt(1 << 30);
    }
    return const CombatV1FirstLegalPolicy().choose(state, legalActions);
  }
}

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

  final pendingOwnerA = state.pendingAttack?.attackerPlayerIndex == 0 ? 1 : 0;
  final pendingOwnerB = state.pendingAttack?.attackerPlayerIndex == 1 ? 1 : 0;
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

void main() {
  group('C. Single Match', () {
    test('Production matchを1試合実行でき、metadata/final state summaryが得られる', () {
      final config = _config(masterSeed: 100);
      const runner = CombatV1SimulationRunner();
      final result = runner.runSingleMatch(config, 0);

      expect(result.matchIndex, 0);
      expect(result.wrestlerAId, 'misaki');
      expect(result.wrestlerBId, 'jack');
      expect(result.playerAPolicyId, 'randomLegal');
      expect(result.playerBPolicyId, 'randomLegal');
      expect(result.masterSeed, 100);
      expect(result.seedDerivationVersion, combatV1SeedDerivationVersion);
      expect(result.maxActions, 500);
      expect(result.actionCount, greaterThan(0));
      expect(result.actionCount, lessThanOrEqualTo(500));

      expect(
        result.termination,
        anyOf(
          CombatV1CpuMatchTermination.matchOver,
          CombatV1CpuMatchTermination.safetyLimit,
        ),
        reason: result.invariantViolationMessage ?? '',
      );

      if (result.termination == CombatV1CpuMatchTermination.matchOver) {
        expect(result.winnerPlayerIndex, anyOf(0, 1));
        expect(result.winnerWrestlerId, anyOf('misaki', 'jack'));
        expect(result.terminalCause, isNotNull);
      } else {
        expect(result.winnerPlayerIndex, isNull);
        expect(result.winnerWrestlerId, isNull);
        expect(result.terminalCause, isNull);
      }

      expect(result.finalStateSummary.playerAHp, greaterThanOrEqualTo(0));
      expect(result.finalStateSummary.playerBHp, greaterThanOrEqualTo(0));
    });
  });

  group('D. Multiple Matches', () {
    test('matchCountと実行件数一致・matchIndexが安定', () {
      final config = _config(matchCount: 5, masterSeed: 555);
      const runner = CombatV1SimulationRunner();
      final result = runner.run(config);

      expect(result.requestedMatchCount, 5);
      expect(result.executedMatchCount, 5);
      expect(result.matches.length, 5);
      for (var i = 0; i < 5; i++) {
        expect(result.matches[i].matchIndex, i);
      }
    });

    test('各matchのowner namespaceが衝突しない', () {
      const matchCount = 10;
      const masterSeed = 777;
      final ownerIds = <String>{};
      for (var i = 0; i < matchCount; i++) {
        final a = combatV1SimulationOwnerId(
          masterSeed: masterSeed,
          matchIndex: i,
          playerSuffix: 'a',
        );
        final b = combatV1SimulationOwnerId(
          masterSeed: masterSeed,
          matchIndex: i,
          playerSuffix: 'b',
        );
        expect(ownerIds.contains(a), isFalse, reason: 'owner id重複: $a');
        expect(ownerIds.contains(b), isFalse, reason: 'owner id重複: $b');
        expect(a, isNot(b));
        ownerIds
          ..add(a)
          ..add(b);
      }
      expect(ownerIds.length, matchCount * 2);
    });

    test('各match seedが一意', () {
      final config = _config(matchCount: 10, masterSeed: 888);
      const runner = CombatV1SimulationRunner();
      final result = runner.run(config);

      final matchSeeds = result.matches.map((m) => m.matchSeed).toSet();
      expect(matchSeeds.length, config.matchCount);
    });

    test('card conservation・instanceId uniqueness（複数matchで各30枚維持）', () {
      final config = _config(matchCount: 3, masterSeed: 909);
      for (var i = 0; i < config.matchCount; i++) {
        _expectCardConservation(_rawFinalState(config, i));
      }
    });
  });

  group('E. Determinism', () {
    test('同一config/masterSeed/matchIndexなら同一結果（engine matchIdは比較対象に含めない）', () {
      final config = _config(masterSeed: 4242);
      const runner = CombatV1SimulationRunner();

      final resultA = runner.runSingleMatch(config, 0);
      final resultB = runner.runSingleMatch(config, 0);

      expect(resultA.termination, resultB.termination);
      expect(resultA.terminalCause, resultB.terminalCause);
      expect(resultA.winnerPlayerIndex, resultB.winnerPlayerIndex);
      expect(resultA.winnerWrestlerId, resultB.winnerWrestlerId);
      expect(resultA.actionCount, resultB.actionCount);
      expect(resultA.finalTurnNumber, resultB.finalTurnNumber);
      expect(resultA.finalStateSummary, resultB.finalStateSummary);
      expect(resultA.matchSeed, resultB.matchSeed);
      expect(resultA.engineSeed, resultB.engineSeed);
      expect(resultA.playerAPolicySeed, resultB.playerAPolicySeed);
      expect(resultA.playerBPolicySeed, resultB.playerBPolicySeed);
    });

    test('RandomLegal policyでも再現する', () {
      final config = _config(
        wrestlerAId: 'akari',
        wrestlerBId: 'reina',
        masterSeed: 5150,
        playerAPolicy: CombatV1SimulationPolicyKind.randomLegal,
        playerBPolicy: CombatV1SimulationPolicyKind.randomLegal,
      );
      const runner = CombatV1SimulationRunner();
      final a = runner.runSingleMatch(config, 0);
      final b = runner.runSingleMatch(config, 0);

      expect(a.termination, b.termination);
      expect(a.actionCount, b.actionCount);
      expect(a.finalStateSummary, b.finalStateSummary);
    });

    test('FirstLegal policyでも再現する', () {
      final config = _config(
        wrestlerAId: 'jack',
        wrestlerBId: 'reina',
        masterSeed: 6161,
        playerAPolicy: CombatV1SimulationPolicyKind.firstLegal,
        playerBPolicy: CombatV1SimulationPolicyKind.firstLegal,
      );
      const runner = CombatV1SimulationRunner();
      final a = runner.runSingleMatch(config, 0);
      final b = runner.runSingleMatch(config, 0);

      expect(a.termination, b.termination);
      expect(a.actionCount, b.actionCount);
      expect(a.finalStateSummary, b.finalStateSummary);
    });

    test('複数seedでexceptionなし・bounded・invariantViolationにならない', () {
      for (var masterSeed = 0; masterSeed < 15; masterSeed++) {
        final config = _config(masterSeed: masterSeed);
        const runner = CombatV1SimulationRunner();
        final result = runner.runSingleMatch(config, 0);

        expect(
          result.termination,
          isNot(CombatV1CpuMatchTermination.invariantViolation),
          reason: 'masterSeed=$masterSeed: ${result.invariantViolationMessage}',
        );
        expect(result.actionCount, lessThanOrEqualTo(config.maxActions));
      }
    });
  });

  group('F. RNG separation（Simulation Runner内のwiring確認）', () {
    // CombatV1SimulationRunnerはengineSeed/playerAPolicySeed/playerBPolicySeed
    // それぞれから独立したRandom instanceを生成し、Phase 11B
    // CombatV1CpuMatchRunnerへ渡す（7章）。ここではconfig単位のseed
    // derivationではなく、Runnerが実際に使うwiring（Random(engineSeed)/
    // Random(playerAPolicySeed)/Random(playerBPolicySeed)を独立instanceとして
    // 生成し、他のRandomを一切共有しない）を直接検証する。
    CombatV1LegalAction? firstActionWith({
      required int engineSeed,
      required int playerASeed,
      required int playerBSeed,
    }) {
      final engineRandom = Random(engineSeed);
      final state = CombatV1ProductionMatchStarter.start(
        CombatV1ProductionMatchConfig(
          wrestlerAId: 'misaki',
          wrestlerBId: 'jack',
          playerAOwnerId: 'rng-sep-a',
          playerBOwnerId: 'rng-sep-b',
          rules: _rules,
        ),
        random: engineRandom,
      );
      final runner = CombatV1CpuMatchRunner(
        catalog: productionCardCatalog,
        rules: _rules,
        // discard phaseの最初の1手（playerA）のみを観測する。
        maxActions: 1,
      );
      final result = runner.run(
        state,
        policyA: CombatV1RandomLegalPolicy(Random(playerASeed)),
        policyB: CombatV1RandomLegalPolicy(Random(playerBSeed)),
        engineRandom: engineRandom,
      );
      return result.lastAction;
    }

    test('playerB Policy Randomのseedを変えてもplayerAの最初の意思決定は変化しない', () {
      final a1 = firstActionWith(engineSeed: 10, playerASeed: 20, playerBSeed: 30);
      final a2 = firstActionWith(engineSeed: 10, playerASeed: 20, playerBSeed: 999);
      expect(a1, a2);
    });

    test(
      'playerAのPolicy Random消費回数が変化してもEngine Random/finalStateは変化しない',
      () {
        // engineSeedを変えると初期手札の配布自体が変わってしまう（＝Engine
        // Randomが正しくshuffle/dealへ影響している証拠であり、RNG分離違反
        // ではない）ため、そのアプローチではEngine Random独立性を検証
        // できない。代わりに、playerAの選択結果自体は固定
        // （`CombatV1FirstLegalPolicy`委譲でdeterministic）にしたまま、
        // playerA用policy Randomの「消費回数」だけを変える
        // `_BurnThenFirstLegalPolicy`を使う。選択結果が同じであるにも
        // 関わらずEngine側のfinalStateが変化すれば、playerAのRandom消費が
        // Engine Randomへ漏れていることになる。
        CombatV1MatchState runWith(int burnCount) {
          final engineRandom = Random(555);
          final state = CombatV1ProductionMatchStarter.start(
            CombatV1ProductionMatchConfig(
              wrestlerAId: 'misaki',
              wrestlerBId: 'jack',
              playerAOwnerId: 'rng-sep-burn-a',
              playerBOwnerId: 'rng-sep-burn-b',
              rules: _rules,
            ),
            random: engineRandom,
          );
          final runner = CombatV1CpuMatchRunner(
            catalog: productionCardCatalog,
            rules: _rules,
            maxActions: 40,
          );
          final result = runner.run(
            state,
            policyA: _BurnThenFirstLegalPolicy(Random(20), burnCount),
            policyB: const CombatV1FirstLegalPolicy(),
            engineRandom: engineRandom,
          );
          return result.finalState;
        }

        final stateNoBurn = runWith(0);
        final stateBurned = runWith(500);

        expect(
          CombatV1MatchFinalStateSummary.fromState(stateBurned),
          CombatV1MatchFinalStateSummary.fromState(stateNoBurn),
        );
      },
    );
  });

  group('G. Replay', () {
    test('Simulation Resultのconfig + matchIndexから対象matchを再実行でき、'
        'winner/termination/actionCount/final state summaryが一致する', () {
      final config = _config(
        wrestlerAId: 'akari',
        wrestlerBId: 'reina',
        masterSeed: 8080,
        matchCount: 3,
      );
      const runner = CombatV1SimulationRunner();
      final simulationResult = runner.run(config);

      final target = simulationResult.matches[1];
      final replay = runner.runSingleMatch(
        simulationResult.config,
        target.matchIndex,
      );

      expect(replay.termination, target.termination);
      expect(replay.winnerPlayerIndex, target.winnerPlayerIndex);
      expect(replay.winnerWrestlerId, target.winnerWrestlerId);
      expect(replay.actionCount, target.actionCount);
      expect(replay.finalTurnNumber, target.finalTurnNumber);
      expect(replay.finalStateSummary, target.finalStateSummary);
      expect(replay.matchSeed, target.matchSeed);
      expect(replay.engineSeed, target.engineSeed);
      expect(replay.playerAPolicySeed, target.playerAPolicySeed);
      expect(replay.playerBPolicySeed, target.playerBPolicySeed);
    });
  });

  group('H. Safety Limit', () {
    test('maxActionsを低く設定するとsafetyLimitがSimulation Resultへ正しく保持される', () {
      final config = _config(maxActions: 1, masterSeed: 321);
      const runner = CombatV1SimulationRunner();
      final result = runner.runSingleMatch(config, 0);

      expect(result.termination, CombatV1CpuMatchTermination.safetyLimit);
      expect(result.safetyLimitReached, isTrue);
      expect(result.winnerPlayerIndex, isNull);
      expect(result.winnerWrestlerId, isNull);
      expect(result.terminalCause, isNull);
      expect(result.actionCount, lessThanOrEqualTo(1));
      expect(result.maxActions, 1);
    });
  });

  group('I. Production Wrestler起動確認（4体）', () {
    test('misaki/jack/akari/reinaすべてがSimulation Runner経由で1試合以上起動できる', () {
      const runner = CombatV1SimulationRunner();
      for (var i = 0; i < _productionWrestlerIds.length; i++) {
        final wrestlerId = _productionWrestlerIds[i];
        final config = _config(
          wrestlerAId: wrestlerId,
          wrestlerBId: 'misaki',
          masterSeed: 1000 + i,
        );
        final result = runner.runSingleMatch(config, 0);
        expect(
          result.termination,
          isNot(CombatV1CpuMatchTermination.invariantViolation),
          reason: '$wrestlerId: ${result.invariantViolationMessage}',
        );
      }
    });
  });
}
