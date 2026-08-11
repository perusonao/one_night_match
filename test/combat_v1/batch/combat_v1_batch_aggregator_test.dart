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

/// [_result]と異なり、`termination`と各fieldの整合性を一切自動調整しない
/// 低レベルtest helper——M2 structured result invariant違反を意図的に
/// 組み立てるためのもの。
CombatV1MatchSimulationResult _rawResult({
  String id = 'raw',
  String wrestlerAId = 'misaki',
  String wrestlerBId = 'jack',
  int matchIndex = 0,
  required CombatV1CpuMatchTermination termination,
  CombatV1CpuMatchTerminalCause? terminalCause,
  int? winnerPlayerIndex,
  String? winnerWrestlerId,
  bool safetyLimitReached = false,
  String? invariantViolationMessage,
}) => CombatV1MatchSimulationResult(
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
  safetyLimitReached: safetyLimitReached,
  finalStateSummary: _summary(),
  terminalCause: terminalCause,
  winnerPlayerIndex: winnerPlayerIndex,
  winnerWrestlerId: winnerWrestlerId,
  invariantViolationMessage: invariantViolationMessage,
);

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

  group(
    'combatV1AggregateBatchResults — simulationMatchId is not tracked (M1)',
    () {
      test('同一simulationMatchIdの結果を2回addしても拒否されない（execution identityの'
          '正本は(matchup, localMatchIndex)であり、accumulatorはsimulationMatchIdの'
          'batch全体でのglobal uniquenessを検査しない——O(totalMatches)のidentity '
          'collectionを保持しないため）', () {
        final bundle = combatV1AggregateBatchResults([
          _result(id: 'dup'),
          _result(id: 'dup', matchIndex: 1),
        ]);
        // 拒否されず、両方ともaggregateへ計上される。
        expect(bundle.global.totalMatches, 2);
      });
    },
  );

  group(
    'combatV1AggregateBatchResults — structured result invariants (M2)',
    () {
      void expectRejected(CombatV1MatchSimulationResult result) {
        expect(
          () => combatV1AggregateBatchResults([result]),
          throwsA(isA<CombatV1IllegalActionException>()),
        );
      }

      group('matchOver', () {
        test('winner null → reject', () {
          expectRejected(
            _rawResult(
              termination: CombatV1CpuMatchTermination.matchOver,
              terminalCause: CombatV1CpuMatchTerminalCause.normalPin,
              winnerPlayerIndex: null,
              winnerWrestlerId: null,
            ),
          );
        });

        test('winner index invalid → reject', () {
          expectRejected(
            _rawResult(
              termination: CombatV1CpuMatchTermination.matchOver,
              terminalCause: CombatV1CpuMatchTerminalCause.normalPin,
              winnerPlayerIndex: 5,
              winnerWrestlerId: null,
            ),
          );
        });

        test('winnerWrestlerId null → reject', () {
          expectRejected(
            _rawResult(
              termination: CombatV1CpuMatchTermination.matchOver,
              terminalCause: CombatV1CpuMatchTerminalCause.normalPin,
              winnerPlayerIndex: 0,
              winnerWrestlerId: null,
            ),
          );
        });

        test('winnerWrestlerId mismatch → reject', () {
          expectRejected(
            _rawResult(
              wrestlerAId: 'misaki',
              wrestlerBId: 'jack',
              termination: CombatV1CpuMatchTermination.matchOver,
              terminalCause: CombatV1CpuMatchTerminalCause.normalPin,
              winnerPlayerIndex: 0,
              winnerWrestlerId: 'jack',
            ),
          );
        });

        test('terminalCause null → reject', () {
          expectRejected(
            _rawResult(
              termination: CombatV1CpuMatchTermination.matchOver,
              terminalCause: null,
              winnerPlayerIndex: 0,
              winnerWrestlerId: 'misaki',
            ),
          );
        });

        test('safetyLimitReached true → reject', () {
          expectRejected(
            _rawResult(
              termination: CombatV1CpuMatchTermination.matchOver,
              terminalCause: CombatV1CpuMatchTerminalCause.normalPin,
              winnerPlayerIndex: 0,
              winnerWrestlerId: 'misaki',
              safetyLimitReached: true,
            ),
          );
        });

        test('invariantViolationMessage非null → reject', () {
          expectRejected(
            _rawResult(
              termination: CombatV1CpuMatchTermination.matchOver,
              terminalCause: CombatV1CpuMatchTerminalCause.normalPin,
              winnerPlayerIndex: 0,
              winnerWrestlerId: 'misaki',
              invariantViolationMessage: 'unexpected',
            ),
          );
        });
      });

      group('safetyLimit', () {
        test('winnerあり → reject', () {
          expectRejected(
            _rawResult(
              termination: CombatV1CpuMatchTermination.safetyLimit,
              winnerPlayerIndex: 0,
              winnerWrestlerId: 'misaki',
              safetyLimitReached: true,
            ),
          );
        });

        test('winnerWrestlerIdあり（winnerPlayerIndexはnull） → reject', () {
          expectRejected(
            _rawResult(
              termination: CombatV1CpuMatchTermination.safetyLimit,
              winnerPlayerIndex: null,
              winnerWrestlerId: 'misaki',
              safetyLimitReached: true,
            ),
          );
        });

        test('terminalCauseあり → reject', () {
          expectRejected(
            _rawResult(
              termination: CombatV1CpuMatchTermination.safetyLimit,
              terminalCause: CombatV1CpuMatchTerminalCause.normalPin,
              safetyLimitReached: true,
            ),
          );
        });

        test('safetyLimitReached false → reject', () {
          expectRejected(
            _rawResult(
              termination: CombatV1CpuMatchTermination.safetyLimit,
              safetyLimitReached: false,
            ),
          );
        });

        test('invariantViolationMessage非null → reject', () {
          expectRejected(
            _rawResult(
              termination: CombatV1CpuMatchTermination.safetyLimit,
              safetyLimitReached: true,
              invariantViolationMessage: 'unexpected',
            ),
          );
        });
      });

      group('invariantViolation', () {
        test('winnerあり → reject', () {
          expectRejected(
            _rawResult(
              termination: CombatV1CpuMatchTermination.invariantViolation,
              winnerPlayerIndex: 0,
              winnerWrestlerId: 'misaki',
              invariantViolationMessage: 'engine bug',
            ),
          );
        });

        test('winnerWrestlerIdあり（winnerPlayerIndexはnull） → reject', () {
          expectRejected(
            _rawResult(
              termination: CombatV1CpuMatchTermination.invariantViolation,
              winnerPlayerIndex: null,
              winnerWrestlerId: 'misaki',
              invariantViolationMessage: 'engine bug',
            ),
          );
        });

        test('terminalCauseあり → reject', () {
          expectRejected(
            _rawResult(
              termination: CombatV1CpuMatchTermination.invariantViolation,
              terminalCause: CombatV1CpuMatchTerminalCause.normalPin,
              invariantViolationMessage: 'engine bug',
            ),
          );
        });

        test('safetyLimitReached true → reject', () {
          expectRejected(
            _rawResult(
              termination: CombatV1CpuMatchTermination.invariantViolation,
              safetyLimitReached: true,
              invariantViolationMessage: 'engine bug',
            ),
          );
        });

        test('invariantViolationMessage null → reject', () {
          expectRejected(
            _rawResult(
              termination: CombatV1CpuMatchTermination.invariantViolation,
              invariantViolationMessage: null,
            ),
          );
        });

        test('invariantViolationMessage空文字列 → reject', () {
          expectRejected(
            _rawResult(
              termination: CombatV1CpuMatchTermination.invariantViolation,
              invariantViolationMessage: '   ',
            ),
          );
        });

        test('正常系: winner/terminalCause/safetyLimitReachedすべて既定値なら受理される', () {
          final bundle = combatV1AggregateBatchResults([
            _rawResult(
              termination: CombatV1CpuMatchTermination.invariantViolation,
              invariantViolationMessage: 'engine bug',
            ),
          ]);
          expect(bundle.global.invariantViolationMatches, 1);
        });
      });
    },
  );

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

    test('build()で取得したbundleは、その後の追加addで一切変化しないsnapshot（m3）', () {
      final accumulator = CombatV1BatchAggregationAccumulator();
      accumulator.add(
        _result(
          id: 'm1',
          wrestlerAId: 'misaki',
          wrestlerBId: 'misaki',
          winnerPlayerIndex: 0,
        ),
      );
      final bundleA = accumulator.build();

      // bundleA取得後にさらに結果を追加する。
      accumulator.add(
        _result(
          id: 'm2',
          wrestlerAId: 'misaki',
          wrestlerBId: 'jack',
          winnerPlayerIndex: 1,
        ),
      );
      accumulator.add(
        _result(
          id: 'm3',
          wrestlerAId: 'akari',
          wrestlerBId: 'reina',
          termination: CombatV1CpuMatchTermination.safetyLimit,
        ),
      );
      final bundleB = accumulator.build();

      // bundleBは新しい内容を反映する。
      expect(bundleB.global.totalMatches, 3);
      expect(bundleB.matchups, hasLength(3));
      expect(bundleB.wrestlers, hasLength(4));
      expect(bundleB.global.safetyLimitMatches, 1);
      expect(bundleB.global.terminalCauseCounts.total, 2);

      // bundleAは追加addの影響を一切受けず、取得時点のまま。
      expect(bundleA.global.totalMatches, 1);
      expect(bundleA.global.completedMatches, 1);
      expect(bundleA.global.playerAWins, 1);
      expect(bundleA.global.playerBWins, 0);
      expect(bundleA.global.safetyLimitMatches, 0);
      expect(bundleA.global.terminalCauseCounts.total, 1);
      expect(bundleA.global.terminalCauseCounts.normalPin, 1);
      expect(bundleA.matchups, hasLength(1));
      expect(bundleA.matchups.single.totalMatches, 1);
      expect(bundleA.wrestlers, hasLength(1));
      expect(bundleA.wrestlers.single.wrestlerId, 'misaki');
      expect(bundleA.wrestlers.single.appearances, 2);
      expect(bundleA.mirror.totalMatches, 1);
      expect(bundleA.mirror.playerAWins, 1);
      expect(bundleA.seat.playerACompletedMatches, 1);
    });
  });
}
