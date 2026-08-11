// Combat Ver.1 Phase 12B-1: Pure Aggregator
// （lib/src/combat_v1/simulation/batch/combat_v1_batch_aggregator.dart）の
// test。
//
// docs/design/combat_v1_phase12b1_batch_core_aggregation.md 17・18章、および
// 37章「TESTS — PURE AGGREGATION」を検証する。synthetic
// CombatV1MatchSimulationResultのみを使い、engineを一切実行しない
// （大規模engine simulationをaggregation unit testの代替にしない）。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_cpu_match_runner.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_aggregator.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_match_simulation_result.dart';

const CombatV1RulesConfig _rules = CombatV1RulesConfig();

CombatV1MatchFinalStateSummary _summary() =>
    const CombatV1MatchFinalStateSummary(
      playerAHp: 100,
      playerBHp: 50,
      playerAKoc: 5,
      playerBKoc: 5,
      playerAPosture: CombatV1WrestlerPosture.stand,
      playerBPosture: CombatV1WrestlerPosture.down,
      playerAPinCardsHeld: 2,
      playerBPinCardsHeld: 2,
      playerAHandSize: 5,
      playerADrawPileSize: 10,
      playerADiscardPileSize: 3,
      playerBHandSize: 5,
      playerBDrawPileSize: 10,
      playerBDiscardPileSize: 3,
      playerAReshuffleCount: 0,
      playerBReshuffleCount: 0,
      sharedHeat: 100,
      finalPhase: CombatV1MatchPhase.action,
      activePlayerIndex: 0,
      hasPendingAttack: false,
    );

/// synthetic [CombatV1MatchSimulationResult]を組み立てるtest helper
/// （engineを一切実行しない）。
CombatV1MatchSimulationResult _result({
  required String id,
  String wrestlerAId = 'misaki',
  String wrestlerBId = 'jack',
  int matchIndex = 0,
  CombatV1CpuMatchTermination termination =
      CombatV1CpuMatchTermination.matchOver,
  CombatV1CpuMatchTerminalCause? terminalCause =
      CombatV1CpuMatchTerminalCause.normalPin,
  int? winnerPlayerIndex = 0,
  String? invariantViolationMessage,
}) {
  final winnerWrestlerId = switch (winnerPlayerIndex) {
    0 => wrestlerAId,
    1 => wrestlerBId,
    _ => null,
  };
  return CombatV1MatchSimulationResult(
    matchIndex: matchIndex,
    simulationMatchId: id,
    wrestlerAId: wrestlerAId,
    wrestlerBId: wrestlerBId,
    playerAOwnerId: 'sim-1-$matchIndex-a',
    playerBOwnerId: 'sim-1-$matchIndex-b',
    playerAPolicyId: 'randomLegal',
    playerBPolicyId: 'randomLegal',
    masterSeed: 1,
    matchSeed: 2,
    engineSeed: 3,
    playerAPolicySeed: 4,
    playerBPolicySeed: 5,
    seedDerivationVersion: 1,
    maxActions: 500,
    rules: _rules,
    termination: termination,
    actionCount: 10,
    finalTurnNumber: 5,
    safetyLimitReached: termination == CombatV1CpuMatchTermination.safetyLimit,
    finalStateSummary: _summary(),
    terminalCause: termination == CombatV1CpuMatchTermination.matchOver
        ? terminalCause
        : null,
    winnerPlayerIndex: termination == CombatV1CpuMatchTermination.matchOver
        ? winnerPlayerIndex
        : null,
    winnerWrestlerId: termination == CombatV1CpuMatchTermination.matchOver
        ? winnerWrestlerId
        : null,
    invariantViolationMessage: invariantViolationMessage,
  );
}

void main() {
  group('combatV1AggregateBatchResults — termination / denominator', () {
    test('total/completed/safety/invariantの内訳', () {
      final bundle = combatV1AggregateBatchResults([
        _result(id: 'm1', termination: CombatV1CpuMatchTermination.matchOver),
        _result(id: 'm2', termination: CombatV1CpuMatchTermination.matchOver),
        _result(id: 'm3', termination: CombatV1CpuMatchTermination.safetyLimit),
        _result(
          id: 'm4',
          termination: CombatV1CpuMatchTermination.invariantViolation,
          invariantViolationMessage: 'test',
        ),
      ]);

      expect(bundle.global.totalMatches, 4);
      expect(bundle.global.completedMatches, 2);
      expect(bundle.global.safetyLimitMatches, 1);
      expect(bundle.global.invariantViolationMatches, 1);
      expect(bundle.global.completionRate, 0.5);
      expect(bundle.global.safetyLimitRate, 0.25);
      expect(bundle.global.invariantViolationRate, 0.25);
    });

    test('A wins / B wins集計', () {
      final bundle = combatV1AggregateBatchResults([
        _result(id: 'm1', winnerPlayerIndex: 0),
        _result(id: 'm2', winnerPlayerIndex: 0),
        _result(id: 'm3', winnerPlayerIndex: 1),
      ]);

      expect(bundle.global.playerAWins, 2);
      expect(bundle.global.playerBWins, 1);
      expect(
        bundle.global.playerAWinRateCompletedMatches,
        closeTo(2 / 3, 1e-9),
      );
      expect(
        bundle.global.playerBWinRateCompletedMatches,
        closeTo(1 / 3, 1e-9),
      );
    });

    test('completedMatches == 0ならwin rateはnull（0.0にfabricationしない）', () {
      final bundle = combatV1AggregateBatchResults([
        _result(id: 'm1', termination: CombatV1CpuMatchTermination.safetyLimit),
      ]);

      expect(bundle.global.completedMatches, 0);
      expect(bundle.global.playerAWinRateCompletedMatches, isNull);
      expect(bundle.global.playerBWinRateCompletedMatches, isNull);
    });

    test('空のIterableならtotalMatches == 0でrateはすべてnull', () {
      final bundle = combatV1AggregateBatchResults(const []);
      expect(bundle.global.totalMatches, 0);
      expect(bundle.global.completionRate, isNull);
      expect(bundle.global.safetyLimitRate, isNull);
      expect(bundle.global.invariantViolationRate, isNull);
      expect(bundle.global.playerAWinRateCompletedMatches, isNull);
    });

    test('safetyLimit/invariantViolationはwinner countへ加算しない', () {
      final bundle = combatV1AggregateBatchResults([
        _result(id: 'm1', termination: CombatV1CpuMatchTermination.safetyLimit),
        _result(
          id: 'm2',
          termination: CombatV1CpuMatchTermination.invariantViolation,
          invariantViolationMessage: 'x',
        ),
      ]);
      expect(bundle.global.playerAWins, 0);
      expect(bundle.global.playerBWins, 0);
    });
  });

  group('combatV1AggregateBatchResults — matchup grouping', () {
    test('matchup毎に分類・初出順を保持', () {
      final bundle = combatV1AggregateBatchResults([
        _result(
          id: 'm1',
          wrestlerAId: 'misaki',
          wrestlerBId: 'jack',
          winnerPlayerIndex: 0,
        ),
        _result(
          id: 'm2',
          wrestlerAId: 'akari',
          wrestlerBId: 'reina',
          winnerPlayerIndex: 1,
        ),
        _result(
          id: 'm3',
          wrestlerAId: 'misaki',
          wrestlerBId: 'jack',
          winnerPlayerIndex: 1,
        ),
      ]);

      expect(bundle.matchups, hasLength(2));
      expect(bundle.matchups[0].matchup.wrestlerAId, 'misaki');
      expect(bundle.matchups[0].matchup.wrestlerBId, 'jack');
      expect(bundle.matchups[0].totalMatches, 2);
      expect(bundle.matchups[0].playerAWins, 1);
      expect(bundle.matchups[0].playerBWins, 1);

      expect(bundle.matchups[1].matchup.wrestlerAId, 'akari');
      expect(bundle.matchups[1].matchup.wrestlerBId, 'reina');
      expect(bundle.matchups[1].totalMatches, 1);
      expect(bundle.matchups[1].playerBWins, 1);
    });

    test('A vs BとB vs Aは別matchupとして分類される', () {
      final bundle = combatV1AggregateBatchResults([
        _result(id: 'm1', wrestlerAId: 'akari', wrestlerBId: 'reina'),
        _result(id: 'm2', wrestlerAId: 'reina', wrestlerBId: 'akari'),
      ]);
      expect(bundle.matchups, hasLength(2));
    });
  });

  group('combatV1AggregateBatchResults — wrestler grouping / A・B seat帰属', () {
    test('wrestler別appearances/wins（A seat・B seat両方から集計）', () {
      final bundle = combatV1AggregateBatchResults([
        // misaki が A seatで勝利
        _result(
          id: 'm1',
          wrestlerAId: 'misaki',
          wrestlerBId: 'jack',
          winnerPlayerIndex: 0,
        ),
        // misaki が B seatで敗北（jackが勝利）
        _result(
          id: 'm2',
          wrestlerAId: 'jack',
          wrestlerBId: 'misaki',
          winnerPlayerIndex: 0,
        ),
      ]);

      final misaki = bundle.wrestlers.firstWhere(
        (w) => w.wrestlerId == 'misaki',
      );
      expect(misaki.playerAAppearances, 1);
      expect(misaki.playerAWins, 1);
      expect(misaki.playerBAppearances, 1);
      expect(misaki.playerBWins, 0);
      expect(misaki.appearances, 2);
      expect(misaki.wins, 1);
      expect(misaki.winRateCompletedMatches, closeTo(0.5, 1e-9));
      expect(misaki.playerAWinRateCompletedMatches, 1.0);
      expect(misaki.playerBWinRateCompletedMatches, 0.0);

      final jack = bundle.wrestlers.firstWhere((w) => w.wrestlerId == 'jack');
      expect(jack.playerAAppearances, 1);
      expect(jack.playerAWins, 1);
      expect(jack.playerBAppearances, 1);
      expect(jack.playerBWins, 0);
    });

    test('wrestler初出順を保持する', () {
      final bundle = combatV1AggregateBatchResults([
        _result(id: 'm1', wrestlerAId: 'reina', wrestlerBId: 'akari'),
        _result(id: 'm2', wrestlerAId: 'misaki', wrestlerBId: 'jack'),
      ]);
      expect(bundle.wrestlers.map((w) => w.wrestlerId).toList(), [
        'reina',
        'akari',
        'misaki',
        'jack',
      ]);
    });

    test('mirror matchでは同一wrestlerがA/B両方のappearancesを得る', () {
      final bundle = combatV1AggregateBatchResults([
        _result(
          id: 'm1',
          wrestlerAId: 'misaki',
          wrestlerBId: 'misaki',
          winnerPlayerIndex: 0,
        ),
      ]);
      final misaki = bundle.wrestlers.single;
      expect(misaki.playerAAppearances, 1);
      expect(misaki.playerBAppearances, 1);
      expect(misaki.appearances, 2);
    });

    test('completedAppearances == 0ならwrestler win rateはnull', () {
      final bundle = combatV1AggregateBatchResults([
        _result(id: 'm1', termination: CombatV1CpuMatchTermination.safetyLimit),
      ]);
      final misaki = bundle.wrestlers.firstWhere(
        (w) => w.wrestlerId == 'misaki',
      );
      expect(misaki.winRateCompletedMatches, isNull);
      expect(misaki.playerAWinRateCompletedMatches, isNull);
      final jack = bundle.wrestlers.firstWhere((w) => w.wrestlerId == 'jack');
      expect(jack.playerBWinRateCompletedMatches, isNull);
    });
  });

  group('combatV1AggregateBatchResults — seat aggregate', () {
    test('seat.playerA/BCompletedMatchesはglobal.completedMatchesと一致', () {
      final bundle = combatV1AggregateBatchResults([
        _result(id: 'm1', winnerPlayerIndex: 0),
        _result(id: 'm2', winnerPlayerIndex: 1),
        _result(id: 'm3', termination: CombatV1CpuMatchTermination.safetyLimit),
      ]);
      expect(
        bundle.seat.playerACompletedMatches,
        bundle.global.completedMatches,
      );
      expect(
        bundle.seat.playerBCompletedMatches,
        bundle.global.completedMatches,
      );
      expect(bundle.seat.playerAWins, bundle.global.playerAWins);
      expect(bundle.seat.playerBWins, bundle.global.playerBWins);
    });
  });

  group('combatV1AggregateBatchResults — mirror aggregate', () {
    test('mirror matchのみを集計する', () {
      final bundle = combatV1AggregateBatchResults([
        _result(
          id: 'm1',
          wrestlerAId: 'misaki',
          wrestlerBId: 'misaki',
          winnerPlayerIndex: 0,
        ),
        _result(
          id: 'm2',
          wrestlerAId: 'misaki',
          wrestlerBId: 'jack',
          winnerPlayerIndex: 1,
        ),
        _result(
          id: 'm3',
          wrestlerAId: 'jack',
          wrestlerBId: 'jack',
          termination: CombatV1CpuMatchTermination.safetyLimit,
        ),
      ]);

      expect(bundle.mirror.totalMatches, 2);
      expect(bundle.mirror.completedMatches, 1);
      expect(bundle.mirror.safetyLimitMatches, 1);
      expect(bundle.mirror.playerAWins, 1);
      expect(bundle.mirror.playerBWins, 0);
      expect(bundle.mirror.playerAWinRateCompletedMatches, 1.0);
    });

    test('absoluteDeviationFromFiftyPercent', () {
      final bundle = combatV1AggregateBatchResults([
        _result(
          id: 'm1',
          wrestlerAId: 'misaki',
          wrestlerBId: 'misaki',
          winnerPlayerIndex: 0,
        ),
        _result(
          id: 'm2',
          wrestlerAId: 'misaki',
          wrestlerBId: 'misaki',
          winnerPlayerIndex: 0,
        ),
        _result(
          id: 'm3',
          wrestlerAId: 'misaki',
          wrestlerBId: 'misaki',
          winnerPlayerIndex: 1,
        ),
        _result(
          id: 'm4',
          wrestlerAId: 'misaki',
          wrestlerBId: 'misaki',
          winnerPlayerIndex: 1,
        ),
      ]);
      // playerAWinRateCompletedMatches == 0.5 → deviation == 0.0
      expect(bundle.mirror.playerAWinRateCompletedMatches, 0.5);
      expect(
        bundle.mirror.absoluteDeviationFromFiftyPercent,
        closeTo(0.0, 1e-9),
      );
    });

    test('mirrorが0件ならabsoluteDeviationFromFiftyPercentはnull', () {
      final bundle = combatV1AggregateBatchResults([
        _result(id: 'm1', wrestlerAId: 'misaki', wrestlerBId: 'jack'),
      ]);
      expect(bundle.mirror.totalMatches, 0);
      expect(bundle.mirror.playerAWinRateCompletedMatches, isNull);
      expect(bundle.mirror.absoluteDeviationFromFiftyPercent, isNull);
    });
  });

  group('combatV1AggregateBatchResults — terminal cause distribution', () {
    test('5種のterminal causeを分類する', () {
      final bundle = combatV1AggregateBatchResults([
        _result(
          id: 'm1',
          terminalCause: CombatV1CpuMatchTerminalCause.normalPin,
        ),
        _result(
          id: 'm2',
          terminalCause: CombatV1CpuMatchTerminalCause.directPin,
        ),
        _result(
          id: 'm3',
          terminalCause: CombatV1CpuMatchTerminalCause.submission,
        ),
        _result(
          id: 'm4',
          terminalCause: CombatV1CpuMatchTerminalCause.submissionFinisher,
        ),
        _result(id: 'm5', terminalCause: CombatV1CpuMatchTerminalCause.other),
      ]);
      expect(bundle.global.terminalCauseCounts.normalPin, 1);
      expect(bundle.global.terminalCauseCounts.directPin, 1);
      expect(bundle.global.terminalCauseCounts.submission, 1);
      expect(bundle.global.terminalCauseCounts.submissionFinisher, 1);
      expect(bundle.global.terminalCauseCounts.other, 1);
      expect(bundle.global.terminalCauseCounts.total, 5);
      expect(
        bundle.global.terminalCauseCounts.total,
        bundle.global.completedMatches,
      );
    });

    test('abnormal terminationはterminalCauseへ含めない', () {
      final bundle = combatV1AggregateBatchResults([
        _result(id: 'm1', termination: CombatV1CpuMatchTermination.safetyLimit),
        _result(
          id: 'm2',
          termination: CombatV1CpuMatchTermination.invariantViolation,
          invariantViolationMessage: 'x',
        ),
      ]);
      expect(bundle.global.terminalCauseCounts.total, 0);
    });
  });

  group('combatV1AggregateBatchResults — aggregate sum invariants', () {
    test('global.totalMatches == Σ matchup.totalMatches', () {
      final bundle = combatV1AggregateBatchResults([
        _result(id: 'm1', wrestlerAId: 'misaki', wrestlerBId: 'jack'),
        _result(id: 'm2', wrestlerAId: 'misaki', wrestlerBId: 'jack'),
        _result(id: 'm3', wrestlerAId: 'akari', wrestlerBId: 'reina'),
      ]);
      final sum = bundle.matchups.fold<int>(0, (s, m) => s + m.totalMatches);
      expect(sum, bundle.global.totalMatches);
    });

    test('Σ wrestler.appearances == 2 × global.totalMatches', () {
      final bundle = combatV1AggregateBatchResults([
        _result(id: 'm1', wrestlerAId: 'misaki', wrestlerBId: 'jack'),
        _result(id: 'm2', wrestlerAId: 'akari', wrestlerBId: 'akari'),
      ]);
      final sum = bundle.wrestlers.fold<int>(0, (s, w) => s + w.appearances);
      expect(sum, 2 * bundle.global.totalMatches);
    });
  });

  group('combatV1AggregateBatchResults — duplicate simulationMatchId', () {
    test('重複したsimulationMatchIdはfail-fast', () {
      expect(
        () => combatV1AggregateBatchResults([
          _result(id: 'dup'),
          _result(id: 'dup', matchIndex: 1),
        ]),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('CombatV1BatchAggregationAccumulator — streaming', () {
    test('addを1件ずつ呼んでも一括aggregateと同じ結果になる', () {
      final results = [
        _result(
          id: 'm1',
          wrestlerAId: 'misaki',
          wrestlerBId: 'jack',
          winnerPlayerIndex: 0,
        ),
        _result(
          id: 'm2',
          wrestlerAId: 'misaki',
          wrestlerBId: 'jack',
          winnerPlayerIndex: 1,
        ),
        _result(id: 'm3', termination: CombatV1CpuMatchTermination.safetyLimit),
      ];

      final accumulator = CombatV1BatchAggregationAccumulator();
      for (final r in results) {
        accumulator.add(r);
      }
      final streamed = accumulator.build();
      final batch = combatV1AggregateBatchResults(results);

      expect(streamed.global.totalMatches, batch.global.totalMatches);
      expect(streamed.global.completedMatches, batch.global.completedMatches);
      expect(streamed.global.playerAWins, batch.global.playerAWins);
      expect(streamed.matchups.length, batch.matchups.length);
    });
  });
}
