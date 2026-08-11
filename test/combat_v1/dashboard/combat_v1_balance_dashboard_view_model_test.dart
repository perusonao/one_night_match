// Balance Dashboard 1A: pure ViewModel mapper
// （lib/src/combat_v1/dashboard/combat_v1_balance_dashboard_view_model.dart）
// と formatting helper
// （lib/src/combat_v1/dashboard/combat_v1_balance_dashboard_formatting.dart）
// のtest。
//
// docs/design/combat_v1_balance_dashboard_1a.md 16章「Test Strategy」を
// 検証する。synthetic CombatV1BatchSimulationResultのみを使い、engineを
// 一切起動しない（fixtureは combat_v1_balance_dashboard_test_fixtures.dart
// を共有）。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/dashboard/combat_v1_balance_dashboard_formatting.dart';
import 'package:one_night_match/src/combat_v1/dashboard/combat_v1_balance_dashboard_view_model.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_policy.dart';

import 'combat_v1_balance_dashboard_test_fixtures.dart';

void main() {
  group('Formatting', () {
    test('percent: 通常値は小数点1桁 + %', () {
      expect(combatV1FormatPercent(0.637), '63.7%');
    });

    test('percent: 100%は100.0%', () {
      expect(combatV1FormatPercent(1.0), '100.0%');
    });

    test('percent: 0は0.0%', () {
      expect(combatV1FormatPercent(0.0), '0.0%');
    });

    test('percent: nullは—', () {
      expect(combatV1FormatPercent(null), '—');
    });

    test('nullable count: nullは—、非nullはそのまま', () {
      expect(combatV1FormatNullableCount(null), '—');
      expect(combatV1FormatNullableCount(5), '5');
    });

    test('nullable number: nullは—、非nullは小数点1桁', () {
      expect(combatV1FormatNullableNumber(null), '—');
      expect(combatV1FormatNullableNumber(3.14159), '3.1');
    });

    test('matches/sec: runtime 0以下は—', () {
      expect(combatV1FormatMatchesPerSecond(100, Duration.zero), '—');
    });

    test('matches/sec: 通常計算', () {
      expect(
        combatV1FormatMatchesPerSecond(1000, const Duration(seconds: 2)),
        '500.0',
      );
    });
  });

  group('Display name lookup', () {
    test('既知IDは registry の表示名を返す', () {
      expect(combatV1DashboardDisplayName('misaki'), '豪田ミサキ');
      expect(combatV1DashboardDisplayName('jack'), '黒蝶ジャック');
      expect(combatV1DashboardDisplayName('akari'), '火神アカリ');
      expect(combatV1DashboardDisplayName('reina'), '白銀レイナ');
    });

    test('未知IDはfail-fastする', () {
      expect(
        () => combatV1DashboardDisplayName('unknown-wrestler'),
        throwsStateError,
      );
    });
  });

  group('Policy label', () {
    test('randomLegal / firstLegal', () {
      expect(
        combatV1DashboardPolicyLabel(CombatV1SimulationPolicyKind.randomLegal),
        'Random Legal',
      );
      expect(
        combatV1DashboardPolicyLabel(CombatV1SimulationPolicyKind.firstLegal),
        'First Legal',
      );
    });
  });

  group('fromResult — runSummary', () {
    test('canonical wrestler order・config値をそのまま反映する', () {
      final viewModel = CombatV1BalanceDashboardViewModel.fromResult(
        combatV1DashboardTestResult(),
      );
      final run = viewModel.runSummary;
      expect(run.wrestlerIds, ['misaki', 'jack', 'akari', 'reina']);
      expect(run.matchesPerMatchup, 10);
      expect(run.masterSeed, 12345);
      expect(run.playerAPolicyLabel, 'Random Legal');
      expect(run.playerBPolicyLabel, 'Random Legal');
      expect(run.maxActions, 500);
      expect(run.rulesLabel, 'Default Combat V1');
      expect(run.requestedMatchCount, 16 * 10);
      expect(run.executedMatchCount, 16 * 10);
    });
  });

  group('fromResult — globalSummary', () {
    test('global aggregate + length statisticsをそのままmapする', () {
      final viewModel = CombatV1BalanceDashboardViewModel.fromResult(
        combatV1DashboardTestResult(),
      );
      final summary = viewModel.globalSummary;
      expect(summary.totalMatches, 16 * 10);
      expect(summary.completedMatches, 16 * 8);
      expect(summary.playerAWinRate, closeTo(60 / 128, 1e-9));
      expect(summary.playerBWinRate, closeTo(68 / 128, 1e-9));
      expect(summary.safetyLimitMatches, 3);
      expect(summary.invariantViolationMatches, 2);
      expect(summary.avgActions, 42.0);
      expect(summary.p90Actions, 60.0);
    });
  });

  group('fromResult — healthSummary（0/nonzero判定）', () {
    test('countが0ならnormal', () {
      final viewModel = CombatV1BalanceDashboardViewModel.fromResult(
        combatV1DashboardTestResult(
          globalSafetyLimit: 0,
          globalInvariantViolation: 0,
        ),
      );
      expect(
        viewModel.healthSummary.safetyLimit.status,
        CombatV1DashboardHealthStatus.normal,
      );
      expect(
        viewModel.healthSummary.invariantViolation.status,
        CombatV1DashboardHealthStatus.normal,
      );
    });

    test('safetyLimitが非0ならwarning、invariantViolationが非0ならerror', () {
      final viewModel = CombatV1BalanceDashboardViewModel.fromResult(
        combatV1DashboardTestResult(
          globalSafetyLimit: 3,
          globalInvariantViolation: 2,
        ),
      );
      expect(
        viewModel.healthSummary.safetyLimit.status,
        CombatV1DashboardHealthStatus.warning,
      );
      expect(viewModel.healthSummary.safetyLimit.count, 3);
      expect(
        viewModel.healthSummary.invariantViolation.status,
        CombatV1DashboardHealthStatus.error,
      );
      expect(viewModel.healthSummary.invariantViolation.count, 2);
    });
  });

  group('fromResult — wrestlerRows', () {
    test('canonical順で4件、displayName・win rateを正しくmapする', () {
      final viewModel = CombatV1BalanceDashboardViewModel.fromResult(
        combatV1DashboardTestResult(),
      );
      final rows = viewModel.wrestlerRows;
      expect(rows, hasLength(4));
      expect(rows.map((r) => r.wrestlerId), [
        'misaki',
        'jack',
        'akari',
        'reina',
      ]);
      expect(rows.map((r) => r.displayName), [
        '豪田ミサキ',
        '黒蝶ジャック',
        '火神アカリ',
        '白銀レイナ',
      ]);
      expect(rows[0].wins, 8); // misaki: 5 + 3
      expect(rows[0].completedAppearances, 16);
      expect(rows[0].completedWinRate, closeTo(8 / 16, 1e-9));
    });

    test('completedAppearances == 0のwrestlerはnull win rate（—表示対象）', () {
      final viewModel = CombatV1BalanceDashboardViewModel.fromResult(
        combatV1DashboardTestResult(),
      );
      final reina = viewModel.wrestlerRows.last;
      expect(reina.wrestlerId, 'reina');
      expect(reina.completedAppearances, 0);
      expect(reina.completedWinRate, isNull);
      expect(reina.playerAWinRate, isNull);
      expect(reina.playerBWinRate, isNull);
      expect(combatV1FormatPercent(reina.completedWinRate), '—');
    });
  });

  group('fromResult — matchupMatrix', () {
    test('4×4 = 16 cellsで、canonical wrestlerIdsをrow/columnに使う', () {
      final viewModel = CombatV1BalanceDashboardViewModel.fromResult(
        combatV1DashboardTestResult(),
      );
      final matrix = viewModel.matchupMatrix;
      expect(matrix.wrestlerIds, ['misaki', 'jack', 'akari', 'reina']);
      expect(matrix.rows, hasLength(4));
      for (final row in matrix.rows) {
        expect(row, hasLength(4));
      }
    });

    test('row=Player A・column=Player Bのsemanticsを正しくmapする', () {
      final viewModel = CombatV1BalanceDashboardViewModel.fromResult(
        combatV1DashboardTestResult(),
      );
      final matrix = viewModel.matchupMatrix;
      // row=0(misaki) col=1(jack) → misaki vs jack (misaki=PlayerA)
      final cell = matrix.rows[0][1];
      expect(cell.rowWrestlerId, 'misaki');
      expect(cell.columnWrestlerId, 'jack');
      expect(cell.matchup.wrestlerAId, 'misaki');
      expect(cell.matchup.wrestlerBId, 'jack');
      expect(
        cell.completedWinRateForRowWrestler,
        closeTo(combatV1DashboardTestPlayerAWinsFor('misaki', 'jack') / 8, 1e-9),
      );
    });

    test('A vs BとB vs Aは別cell（値が入れ替わる）', () {
      final viewModel = CombatV1BalanceDashboardViewModel.fromResult(
        combatV1DashboardTestResult(),
      );
      final matrix = viewModel.matchupMatrix;
      final misakiVsJack = matrix.rows[0][1];
      final jackVsMisaki = matrix.rows[1][0];
      expect(misakiVsJack.matchup.wrestlerAId, 'misaki');
      expect(misakiVsJack.matchup.wrestlerBId, 'jack');
      expect(jackVsMisaki.matchup.wrestlerAId, 'jack');
      expect(jackVsMisaki.matchup.wrestlerBId, 'misaki');
      // formulaがrow/column両方に依存するため、A視点勝率は入れ替えると
      // 一般に異なる値になる。
      expect(
        misakiVsJack.completedWinRateForRowWrestler,
        isNot(jackVsMisaki.completedWinRateForRowWrestler),
      );
    });

    test('diagonal（mirror）はisMirror==true、それ以外はfalse', () {
      final viewModel = CombatV1BalanceDashboardViewModel.fromResult(
        combatV1DashboardTestResult(),
      );
      final matrix = viewModel.matchupMatrix;
      for (var i = 0; i < 4; i++) {
        for (var j = 0; j < 4; j++) {
          expect(matrix.rows[i][j].isMirror, i == j);
        }
      }
    });

    test('safety/invariant件数がcellへ反映される（akari vs akari）', () {
      final viewModel = CombatV1BalanceDashboardViewModel.fromResult(
        combatV1DashboardTestResult(),
      );
      final akariVsAkari = viewModel.matchupMatrix.rows[2][2];
      expect(akariVsAkari.safetyLimitMatches, 1);
      expect(akariVsAkari.invariantViolationMatches, 1);
      final misakiVsMisaki = viewModel.matchupMatrix.rows[0][0];
      expect(misakiVsMisaki.safetyLimitMatches, 0);
      expect(misakiVsMisaki.invariantViolationMatches, 0);
    });

    test('対応するmatchupが欠落しているとfail-fastする', () {
      final ids = combatV1DashboardTestWrestlerIds;
      final incompleteMatchups = combatV1DashboardTestMatchups(wrestlerIds: ids)
        ..removeWhere(
          (m) =>
              m.matchup.wrestlerAId == 'reina' &&
              m.matchup.wrestlerBId == 'reina',
        );
      final broken = combatV1DashboardTestResult(matchups: incompleteMatchups);
      expect(
        () => CombatV1BalanceDashboardViewModel.fromResult(broken),
        throwsStateError,
      );
    });
  });

  group('fromResult — mirrorSummary', () {
    test('mirror aggregateをそのままmapする', () {
      final viewModel = CombatV1BalanceDashboardViewModel.fromResult(
        combatV1DashboardTestResult(),
      );
      final mirror = viewModel.mirrorSummary;
      expect(mirror.totalMatches, 40);
      expect(mirror.completedMatches, 32);
      expect(mirror.playerAWinRate, closeTo(15 / 32, 1e-9));
      expect(
        mirror.absoluteDeviationFromFiftyPercent,
        closeTo((15 / 32 - 0.5).abs(), 1e-9),
      );
      expect(mirror.safetyLimitRate, closeTo(1 / 40, 1e-9));
      expect(mirror.invariantViolationRate, closeTo(1 / 40, 1e-9));
    });
  });

  group('fromResult — seatSummary', () {
    test('seat aggregateをそのままmapする（A/B schema名を維持）', () {
      final viewModel = CombatV1BalanceDashboardViewModel.fromResult(
        combatV1DashboardTestResult(),
      );
      final seat = viewModel.seatSummary;
      expect(seat.playerACompletedMatches, 128);
      expect(seat.playerAWins, 60);
      expect(seat.playerAWinRate, closeTo(60 / 128, 1e-9));
      expect(seat.playerBCompletedMatches, 128);
      expect(seat.playerBWins, 68);
      expect(seat.playerBWinRate, closeTo(68 / 128, 1e-9));
    });
  });

  group('fromResult — lengthSummary', () {
    test('statistics.global.lengthをそのままmapする', () {
      final viewModel = CombatV1BalanceDashboardViewModel.fromResult(
        combatV1DashboardTestResult(),
      );
      final length = viewModel.lengthSummary;
      expect(length.actionCount.sampleCount, 128);
      expect(length.actionCount.mean, 42.0);
      expect(length.actionCount.median, 40.0);
      expect(length.actionCount.p90, 60.0);
      expect(length.actionCount.p95, 65.0);
      expect(length.actionCount.min, 10);
      expect(length.actionCount.max, 90);
      expect(length.finalTurnNumber.sampleCount, 128);
      expect(length.finalTurnNumber.mean, 21.0);
    });
  });

  group('statistics/core matchup alignment', () {
    test('result.matchupsとresult.statistics.matchupsが同じ順序である前提を'
        'mapperがそのまま利用する', () {
      final result = combatV1DashboardTestResult();
      expect(result.statistics.matchups.length, result.matchups.length);
      for (var i = 0; i < result.matchups.length; i++) {
        expect(
          result.statistics.matchups[i].matchup,
          result.matchups[i].matchup,
        );
      }
      // mapperはstatistics.matchupsを直接matrixへ組み込まない
      // （lengthはmatrixの主表示ではない、34章）が、順序整合が崩れていない
      // 前提を明示的に確認しておく。
      final viewModel = CombatV1BalanceDashboardViewModel.fromResult(result);
      expect(viewModel.matchupMatrix.rows, hasLength(4));
    });
  });
}
