/// Balance Dashboard 1A — pure ViewModel mapper
/// （docs/design/combat_v1_balance_dashboard_1a.md 8章「ViewModel」）。
///
/// [CombatV1BalanceDashboardViewModel.fromResult]は、
/// `CombatV1BatchSimulationResult`（Phase 12B-1/12B-2A domain result）を、
/// Dashboard UIが扱いやすいread-only structureへ変換するpure mapper。
///
/// - engine実行・I/O・DateTime.now()等の副作用を一切持たない
/// - `CombatV1BatchSimulationResult`のtreeをUI widget側で直接探索させない
///   （常にこのViewModel経由でアクセスする）
/// - Development Snapshot JSON（`devtools/`配下）を経由しない・importしない
///   （7章「Do Not Import dart:io Writer」）
library;

import '../combat_v1_production_match_setup.dart';
import '../simulation/batch/combat_v1_batch_aggregate.dart';
import '../simulation/batch/combat_v1_batch_length_statistics.dart';
import '../simulation/batch/combat_v1_batch_matchup.dart';
import '../simulation/batch/combat_v1_batch_simulation_result.dart';
import '../simulation/combat_v1_simulation_policy.dart';

/// [wrestlerId]から表示名を解決する唯一のsource of truth
/// （16章「Display Name Source」）。
///
/// `combatV1ProductionWrestlerRegistry`に存在しないIDはfail-fastする——
/// Dashboard 1Aは常にProduction registryに存在するIDのみを扱うため、この
/// 分岐は正常系では到達しない。
String combatV1DashboardDisplayName(String wrestlerId) {
  final entry = combatV1ProductionWrestlerRegistry[wrestlerId];
  if (entry == null) {
    throw StateError(
      '未知のProduction wrestlerIdです（Dashboard display name lookup）: '
      '$wrestlerId',
    );
  }
  return entry.wrestler.name;
}

/// [kind]のUI表示label（`RandomLegal`/`FirstLegal`のenum名から機械的に
/// 導出せず、明示的なlabel mapを持つ——将来enum名が変わってもUI表示文言
/// はこのfileでのみ制御する）。
String combatV1DashboardPolicyLabel(CombatV1SimulationPolicyKind kind) =>
    switch (kind) {
      CombatV1SimulationPolicyKind.firstLegal => 'First Legal',
      CombatV1SimulationPolicyKind.randomLegal => 'Random Legal',
    };

/// engine/runtime healthの0/nonzero判定（15章「Health Semantics」）。
///
/// balance threshold heuristic（win rateによる強弱判定）ではない——Dashboard
/// 1Aでは使用しない・追加しない（31章）。
enum CombatV1DashboardHealthStatus { normal, warning, error }

/// 1つのhealth指標（safety limit / invariant violation）のcount・rate・
/// statusをまとめたread-only structure。
class CombatV1DashboardHealthMetric {
  const CombatV1DashboardHealthMetric({
    required this.count,
    required this.rate,
    required this.status,
  });

  final int count;
  final double? rate;
  final CombatV1DashboardHealthStatus status;
}

/// Run metadata（27章「Run Metadata」）。Dashboard 1Aのfixed configの
/// snapshot——domainの`CombatV1BatchSimulationConfig`から抽出したread-only
/// structure。
class CombatV1DashboardRunSummary {
  const CombatV1DashboardRunSummary({
    required this.wrestlerIds,
    required this.matchesPerMatchup,
    required this.requestedMatchCount,
    required this.executedMatchCount,
    required this.masterSeed,
    required this.playerAPolicyLabel,
    required this.playerBPolicyLabel,
    required this.maxActions,
    required this.rulesLabel,
  });

  /// canonical順（misaki, jack, akari, reina）。
  final List<String> wrestlerIds;
  final int matchesPerMatchup;
  final int requestedMatchCount;
  final int executedMatchCount;
  final int masterSeed;
  final String playerAPolicyLabel;
  final String playerBPolicyLabel;
  final int maxActions;
  final String rulesLabel;
}

/// Global summary（29章「Summary Cards」）。
class CombatV1DashboardGlobalSummary {
  const CombatV1DashboardGlobalSummary({
    required this.totalMatches,
    required this.completedMatches,
    required this.completionRate,
    required this.playerAWinRate,
    required this.playerBWinRate,
    required this.safetyLimitMatches,
    required this.safetyLimitRate,
    required this.invariantViolationMatches,
    required this.invariantViolationRate,
    required this.avgActions,
    required this.p90Actions,
  });

  final int totalMatches;
  final int completedMatches;
  final double? completionRate;
  final double? playerAWinRate;
  final double? playerBWinRate;
  final int safetyLimitMatches;
  final double? safetyLimitRate;
  final int invariantViolationMatches;
  final double? invariantViolationRate;
  final double? avgActions;
  final double? p90Actions;
}

/// Global health summary（30章「Health Semantics」）。
class CombatV1DashboardHealthSummary {
  const CombatV1DashboardHealthSummary({
    required this.safetyLimit,
    required this.invariantViolation,
  });

  final CombatV1DashboardHealthMetric safetyLimit;
  final CombatV1DashboardHealthMetric invariantViolation;
}

/// Wrestler summary table 1行分（32章「Wrestler Summary」）。ランク付けなし。
class CombatV1DashboardWrestlerRow {
  const CombatV1DashboardWrestlerRow({
    required this.wrestlerId,
    required this.displayName,
    required this.completedWinRate,
    required this.wins,
    required this.completedAppearances,
    required this.playerAWinRate,
    required this.playerBWinRate,
  });

  final String wrestlerId;
  final String displayName;
  final double? completedWinRate;
  final int wins;
  final int completedAppearances;
  final double? playerAWinRate;
  final double? playerBWinRate;
}

/// Matchup matrixの1cell（33・34章「Matchup Matrix / Matrix Cell」）。
///
/// [rowWrestlerId]がPlayer A、[columnWrestlerId]がPlayer Bとして戦った
/// matchupを表す。[matchup]はdomainの`CombatV1Matchup`（immutable value
/// object）をそのまま保持する——複製構造を追加で持たせない。
class CombatV1DashboardMatchupCell {
  const CombatV1DashboardMatchupCell({
    required this.matchup,
    required this.rowWrestlerId,
    required this.columnWrestlerId,
    required this.completedWinRateForRowWrestler,
    required this.completedMatches,
    required this.safetyLimitMatches,
    required this.invariantViolationMatches,
    required this.isMirror,
  });

  final CombatV1Matchup matchup;
  final String rowWrestlerId;
  final String columnWrestlerId;

  /// 行側wrestler（Player A）がPlayer Aとして勝ったcompleted試合の割合
  /// （`playerAWinRateCompletedMatches`）。
  final double? completedWinRateForRowWrestler;
  final int completedMatches;
  final int safetyLimitMatches;
  final int invariantViolationMatches;
  final bool isMirror;
}

/// 4×4 ordered matchup matrix。行＝Player A、列＝Player B（33章）。
class CombatV1DashboardMatchupMatrix {
  const CombatV1DashboardMatchupMatrix({
    required this.wrestlerIds,
    required this.rows,
  });

  /// canonical順（行・列共通）。
  final List<String> wrestlerIds;

  /// `rows[i][j]` = `wrestlerIds[i]`（Player A）vs `wrestlerIds[j]`
  /// （Player B）。
  final List<List<CombatV1DashboardMatchupCell>> rows;
}

/// Mirror panel（37章）。
class CombatV1DashboardMirrorSummary {
  const CombatV1DashboardMirrorSummary({
    required this.totalMatches,
    required this.completedMatches,
    required this.playerAWinRate,
    required this.absoluteDeviationFromFiftyPercent,
    required this.safetyLimitRate,
    required this.invariantViolationRate,
  });

  final int totalMatches;
  final int completedMatches;
  final double? playerAWinRate;
  final double? absoluteDeviationFromFiftyPercent;
  final double? safetyLimitRate;
  final double? invariantViolationRate;
}

/// Player A/B panel（38章）。「現在のEngineではPlayer Aがstarting player」
/// という注釈はUI側で表示してよい——このstructure自体はA/B schema名を
/// そのまま維持する（first/secondへrenameしない）。
class CombatV1DashboardSeatSummary {
  const CombatV1DashboardSeatSummary({
    required this.playerACompletedMatches,
    required this.playerAWins,
    required this.playerAWinRate,
    required this.playerBCompletedMatches,
    required this.playerBWins,
    required this.playerBWinRate,
  });

  final int playerACompletedMatches;
  final int playerAWins;
  final double? playerAWinRate;
  final int playerBCompletedMatches;
  final int playerBWins;
  final double? playerBWinRate;
}

/// 1分布（actionCount / finalTurnNumber）のdescriptive statistics
/// （39章「Length Panel」）。
class CombatV1DashboardDistributionSummary {
  const CombatV1DashboardDistributionSummary({
    required this.sampleCount,
    required this.mean,
    required this.median,
    required this.p90,
    required this.p95,
    required this.min,
    required this.max,
  });

  final int sampleCount;
  final double? mean;
  final double? median;
  final double? p90;
  final double? p95;
  final int? min;
  final int? max;
}

/// Length panel全体（39章）。completed-only。
class CombatV1DashboardLengthSummary {
  const CombatV1DashboardLengthSummary({
    required this.actionCount,
    required this.finalTurnNumber,
  });

  final CombatV1DashboardDistributionSummary actionCount;

  /// 最終stateの1始まりturn番号——完了したturn数ではない
  /// （39章「finalTurnNumberの説明」）。
  final CombatV1DashboardDistributionSummary finalTurnNumber;
}

/// Dashboard 1AのUI用read-only structure全体（14章「View Model Layer」）。
class CombatV1BalanceDashboardViewModel {
  const CombatV1BalanceDashboardViewModel({
    required this.runSummary,
    required this.globalSummary,
    required this.healthSummary,
    required this.wrestlerRows,
    required this.matchupMatrix,
    required this.mirrorSummary,
    required this.seatSummary,
    required this.lengthSummary,
  });

  final CombatV1DashboardRunSummary runSummary;
  final CombatV1DashboardGlobalSummary globalSummary;
  final CombatV1DashboardHealthSummary healthSummary;

  /// canonical順（misaki, jack, akari, reina）、4件。
  final List<CombatV1DashboardWrestlerRow> wrestlerRows;
  final CombatV1DashboardMatchupMatrix matchupMatrix;
  final CombatV1DashboardMirrorSummary mirrorSummary;
  final CombatV1DashboardSeatSummary seatSummary;
  final CombatV1DashboardLengthSummary lengthSummary;

  /// [result]からDashboard ViewModelを構築する（唯一のpublic entry
  /// point）。
  factory CombatV1BalanceDashboardViewModel.fromResult(
    CombatV1BatchSimulationResult result,
  ) {
    return CombatV1BalanceDashboardViewModel(
      runSummary: _mapRunSummary(result),
      globalSummary: _mapGlobalSummary(result),
      healthSummary: _mapHealthSummary(result),
      wrestlerRows: _mapWrestlerRows(result),
      matchupMatrix: _mapMatchupMatrix(result),
      mirrorSummary: _mapMirrorSummary(result),
      seatSummary: _mapSeatSummary(result),
      lengthSummary: _mapLengthSummary(result.statistics.global.length),
    );
  }

  static CombatV1DashboardRunSummary _mapRunSummary(
    CombatV1BatchSimulationResult result,
  ) {
    final config = result.config;
    return CombatV1DashboardRunSummary(
      wrestlerIds: List.unmodifiable(config.wrestlerIds),
      matchesPerMatchup: config.matchesPerMatchup,
      requestedMatchCount: result.requestedMatchCount,
      executedMatchCount: result.executedMatchCount,
      masterSeed: config.masterSeed,
      playerAPolicyLabel: combatV1DashboardPolicyLabel(config.playerAPolicy),
      playerBPolicyLabel: combatV1DashboardPolicyLabel(config.playerBPolicy),
      maxActions: config.maxActions,
      // Dashboard 1Aは`const CombatV1RulesConfig()`（Core Engine既定値）
      // のみを扱う（rules editorはDashboard 1Bへ、45章「No Editable
      // Config」）。そのため常に固定labelとする。
      rulesLabel: 'Default Combat V1',
    );
  }

  static CombatV1DashboardGlobalSummary _mapGlobalSummary(
    CombatV1BatchSimulationResult result,
  ) {
    final global = result.global;
    final actionStats = result.statistics.global.length.actionCount;
    return CombatV1DashboardGlobalSummary(
      totalMatches: global.totalMatches,
      completedMatches: global.completedMatches,
      completionRate: global.completionRate,
      playerAWinRate: global.playerAWinRateCompletedMatches,
      playerBWinRate: global.playerBWinRateCompletedMatches,
      safetyLimitMatches: global.safetyLimitMatches,
      safetyLimitRate: global.safetyLimitRate,
      invariantViolationMatches: global.invariantViolationMatches,
      invariantViolationRate: global.invariantViolationRate,
      avgActions: actionStats.mean,
      p90Actions: actionStats.p90,
    );
  }

  static CombatV1DashboardHealthSummary _mapHealthSummary(
    CombatV1BatchSimulationResult result,
  ) {
    final global = result.global;
    return CombatV1DashboardHealthSummary(
      safetyLimit: CombatV1DashboardHealthMetric(
        count: global.safetyLimitMatches,
        rate: global.safetyLimitRate,
        status: global.safetyLimitMatches == 0
            ? CombatV1DashboardHealthStatus.normal
            : CombatV1DashboardHealthStatus.warning,
      ),
      invariantViolation: CombatV1DashboardHealthMetric(
        count: global.invariantViolationMatches,
        rate: global.invariantViolationRate,
        status: global.invariantViolationMatches == 0
            ? CombatV1DashboardHealthStatus.normal
            : CombatV1DashboardHealthStatus.error,
      ),
    );
  }

  static List<CombatV1DashboardWrestlerRow> _mapWrestlerRows(
    CombatV1BatchSimulationResult result,
  ) {
    return List.unmodifiable(
      result.wrestlers.map(
        (wrestler) => CombatV1DashboardWrestlerRow(
          wrestlerId: wrestler.wrestlerId,
          displayName: combatV1DashboardDisplayName(wrestler.wrestlerId),
          completedWinRate: wrestler.winRateCompletedMatches,
          wins: wrestler.wins,
          completedAppearances: wrestler.completedAppearances,
          playerAWinRate: wrestler.playerAWinRateCompletedMatches,
          playerBWinRate: wrestler.playerBWinRateCompletedMatches,
        ),
      ),
    );
  }

  static CombatV1DashboardMatchupMatrix _mapMatchupMatrix(
    CombatV1BatchSimulationResult result,
  ) {
    final wrestlerIds = List<String>.unmodifiable(result.config.wrestlerIds);
    final byMatchup = <CombatV1Matchup, CombatV1MatchupAggregate>{
      for (final aggregate in result.matchups) aggregate.matchup: aggregate,
    };

    final rows = <List<CombatV1DashboardMatchupCell>>[];
    for (final rowWrestlerId in wrestlerIds) {
      final rowCells = <CombatV1DashboardMatchupCell>[];
      for (final columnWrestlerId in wrestlerIds) {
        final matchup = CombatV1Matchup(
          wrestlerAId: rowWrestlerId,
          wrestlerBId: columnWrestlerId,
        );
        final aggregate = byMatchup[matchup];
        if (aggregate == null) {
          // Batch Runnerは`config.wrestlerIds`の全Cartesian
          // product（N×N）を必ず生成するため（Phase 12B-1
          // `combatV1GenerateMatchupMatrix`）、この分岐は構造的に到達
          // しない。到達した場合はdomain resultとViewModelの前提が
          // 崩れているため、silent fallbackせずfail-fastする。
          throw StateError(
            'Dashboard matrix構築中に対応するmatchupが見つかりません: '
            '$rowWrestlerId vs $columnWrestlerId',
          );
        }
        rowCells.add(
          CombatV1DashboardMatchupCell(
            matchup: matchup,
            rowWrestlerId: rowWrestlerId,
            columnWrestlerId: columnWrestlerId,
            completedWinRateForRowWrestler:
                aggregate.playerAWinRateCompletedMatches,
            completedMatches: aggregate.completedMatches,
            safetyLimitMatches: aggregate.safetyLimitMatches,
            invariantViolationMatches: aggregate.invariantViolationMatches,
            isMirror: matchup.isMirror,
          ),
        );
      }
      rows.add(List.unmodifiable(rowCells));
    }

    return CombatV1DashboardMatchupMatrix(
      wrestlerIds: wrestlerIds,
      rows: List.unmodifiable(rows),
    );
  }

  static CombatV1DashboardMirrorSummary _mapMirrorSummary(
    CombatV1BatchSimulationResult result,
  ) {
    final mirror = result.mirror;
    return CombatV1DashboardMirrorSummary(
      totalMatches: mirror.totalMatches,
      completedMatches: mirror.completedMatches,
      playerAWinRate: mirror.playerAWinRateCompletedMatches,
      absoluteDeviationFromFiftyPercent:
          mirror.absoluteDeviationFromFiftyPercent,
      safetyLimitRate: mirror.safetyLimitRate,
      invariantViolationRate: mirror.termination.invariantViolationRate,
    );
  }

  static CombatV1DashboardSeatSummary _mapSeatSummary(
    CombatV1BatchSimulationResult result,
  ) {
    final seat = result.seat;
    return CombatV1DashboardSeatSummary(
      playerACompletedMatches: seat.playerACompletedMatches,
      playerAWins: seat.playerAWins,
      playerAWinRate: seat.playerAWinRateCompletedMatches,
      playerBCompletedMatches: seat.playerBCompletedMatches,
      playerBWins: seat.playerBWins,
      playerBWinRate: seat.playerBWinRateCompletedMatches,
    );
  }

  static CombatV1DashboardLengthSummary _mapLengthSummary(
    CombatV1MatchLengthStatistics length,
  ) {
    return CombatV1DashboardLengthSummary(
      actionCount: _mapDistribution(length.actionCount),
      finalTurnNumber: _mapDistribution(length.finalTurnNumber),
    );
  }

  static CombatV1DashboardDistributionSummary _mapDistribution(
    CombatV1NumericDistributionSummary summary,
  ) {
    return CombatV1DashboardDistributionSummary(
      sampleCount: summary.sampleCount,
      mean: summary.mean,
      median: summary.median,
      p90: summary.p90,
      p95: summary.p95,
      min: summary.min,
      max: summary.max,
    );
  }
}
