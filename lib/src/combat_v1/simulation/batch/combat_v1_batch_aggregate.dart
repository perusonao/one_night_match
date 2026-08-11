/// Combat Ver.1 Phase 12B-1 — Aggregate result value types
/// （docs/design/combat_v1_phase12b1_batch_core_aggregation.md 19〜25章）。
///
/// [CombatV1BatchAggregationAccumulator]（`combat_v1_batch_aggregator.dart`）
/// が構築する、immutableなaggregation結果の型群。全fieldがimmutable・rateは
/// zero denominatorの場合`double?`の`null`（`0.0`へfabricationしない、13章
/// 「Denominator Semantics」）。
library;

import 'combat_v1_batch_matchup.dart';

/// termination（`matchOver`/`safetyLimit`/`invariantViolation`）の内訳
/// （19章「共有value type」）。Global・Matchup・Mirror aggregateが内部で
/// 保持し、フラットなdelegating getterも公開する。
class CombatV1TerminationDistribution {
  const CombatV1TerminationDistribution({
    required this.totalMatches,
    required this.completedMatches,
    required this.safetyLimitMatches,
    required this.invariantViolationMatches,
  });

  final int totalMatches;
  final int completedMatches;
  final int safetyLimitMatches;
  final int invariantViolationMatches;

  /// 分母は[totalMatches]（13章）。`totalMatches == 0`なら`null`。
  double? get completionRate =>
      totalMatches == 0 ? null : completedMatches / totalMatches;

  /// 分母は[totalMatches]（13章）。`totalMatches == 0`なら`null`。
  double? get safetyLimitRate =>
      totalMatches == 0 ? null : safetyLimitMatches / totalMatches;

  /// 分母は[totalMatches]（13章）。`totalMatches == 0`なら`null`。
  double? get invariantViolationRate =>
      totalMatches == 0 ? null : invariantViolationMatches / totalMatches;
}

/// terminal cause（`normalPin`/`directPin`/`submission`/`submissionFinisher`/
/// `other`）の内訳（25章）。分母は`completedMatches`——abnormal terminationは
/// 含まない。
class CombatV1TerminalCauseCounts {
  const CombatV1TerminalCauseCounts({
    required this.normalPin,
    required this.directPin,
    required this.submission,
    required this.submissionFinisher,
    required this.other,
  });

  final int normalPin;
  final int directPin;
  final int submission;
  final int submissionFinisher;
  final int other;

  /// 5種の合計。`completedMatches`と一致することを内部invariantとして
  /// `CombatV1BatchAggregationAccumulator.build`で検証する（15章）。
  int get total =>
      normalPin + directPin + submission + submissionFinisher + other;
}

/// batch全体のglobal aggregate（20章）。
class CombatV1GlobalAggregate {
  const CombatV1GlobalAggregate({
    required this.termination,
    required this.playerAWins,
    required this.playerBWins,
    required this.terminalCauseCounts,
  });

  final CombatV1TerminationDistribution termination;
  final int playerAWins;
  final int playerBWins;
  final CombatV1TerminalCauseCounts terminalCauseCounts;

  int get totalMatches => termination.totalMatches;
  int get completedMatches => termination.completedMatches;
  int get safetyLimitMatches => termination.safetyLimitMatches;
  int get invariantViolationMatches => termination.invariantViolationMatches;
  double? get completionRate => termination.completionRate;
  double? get safetyLimitRate => termination.safetyLimitRate;
  double? get invariantViolationRate => termination.invariantViolationRate;

  /// 分母は[completedMatches]（13章）。`completedMatches == 0`なら`null`。
  double? get playerAWinRateCompletedMatches =>
      completedMatches == 0 ? null : playerAWins / completedMatches;

  /// 分母は[completedMatches]（13章）。`completedMatches == 0`なら`null`。
  double? get playerBWinRateCompletedMatches =>
      completedMatches == 0 ? null : playerBWins / completedMatches;
}

/// 1 matchup（`CombatV1Matchup`）単位のaggregate（21章）。
///
/// matchup単位のrequested/executed match countは意図的に持たない——pure
/// aggregatorは「実際に観測したmatch result」のみからaggregateするため
/// （21章「requested/executed countについて」参照）。
class CombatV1MatchupAggregate {
  const CombatV1MatchupAggregate({
    required this.matchup,
    required this.termination,
    required this.playerAWins,
    required this.playerBWins,
    required this.terminalCauseCounts,
  });

  final CombatV1Matchup matchup;
  final CombatV1TerminationDistribution termination;
  final int playerAWins;
  final int playerBWins;
  final CombatV1TerminalCauseCounts terminalCauseCounts;

  int get totalMatches => termination.totalMatches;
  int get completedMatches => termination.completedMatches;
  int get safetyLimitMatches => termination.safetyLimitMatches;
  int get invariantViolationMatches => termination.invariantViolationMatches;

  /// 分母は[completedMatches]（13章）。`completedMatches == 0`なら`null`。
  double? get playerAWinRateCompletedMatches =>
      completedMatches == 0 ? null : playerAWins / completedMatches;

  /// 分母は[completedMatches]（13章）。`completedMatches == 0`なら`null`。
  double? get playerBWinRateCompletedMatches =>
      completedMatches == 0 ? null : playerBWins / completedMatches;
}

/// 1 wrestler単位のaggregate（22章）。opponent別詳細は[CombatV1MatchupAggregate]
/// から取得できるため、ここには持たせない（データ重複回避）。
class CombatV1WrestlerAggregate {
  const CombatV1WrestlerAggregate({
    required this.wrestlerId,
    required this.playerAAppearances,
    required this.playerACompletedAppearances,
    required this.playerAWins,
    required this.playerBAppearances,
    required this.playerBCompletedAppearances,
    required this.playerBWins,
  });

  final String wrestlerId;

  final int playerAAppearances;
  final int playerACompletedAppearances;
  final int playerAWins;

  final int playerBAppearances;
  final int playerBCompletedAppearances;
  final int playerBWins;

  int get appearances => playerAAppearances + playerBAppearances;
  int get completedAppearances =>
      playerACompletedAppearances + playerBCompletedAppearances;
  int get wins => playerAWins + playerBWins;

  /// 分母は[completedAppearances]（13章）。0なら`null`。
  double? get winRateCompletedMatches =>
      completedAppearances == 0 ? null : wins / completedAppearances;

  /// 分母は[playerACompletedAppearances]（13章）。0なら`null`。
  double? get playerAWinRateCompletedMatches => playerACompletedAppearances == 0
      ? null
      : playerAWins / playerACompletedAppearances;

  /// 分母は[playerBCompletedAppearances]（13章）。0なら`null`。
  double? get playerBWinRateCompletedMatches => playerBCompletedAppearances == 0
      ? null
      : playerBWins / playerBCompletedAppearances;
}

/// batch全体でのA seat/B seatバイアスの集約（23章）。
///
/// **current engine contract: Player A = first player, Player B = second
/// player**（Combat Ver.1のCore Engineは、`playerA`が常に先手として試合を
/// 開始する。Core Engineが変更されない限りこの契約はPhase 12B-1でも
/// 変わらない）。Public schemaの正本は常にA/Bとし、`firstPlayerWinRate`の
/// ような「先手/後手」を正本field名にはしない。
///
/// [playerACompletedMatches]/[playerBCompletedMatches]は常に
/// `CombatV1GlobalAggregate.completedMatches`と同じ値になる——batch全体の
/// 各completed matchは必ずplayerA側・playerB側を1つずつ持つため。両方を
/// 明示fieldとして持つのは、「A側/B側それぞれの分母」を対称に表現する
/// APIとするため。
class CombatV1SeatAggregate {
  const CombatV1SeatAggregate({
    required this.playerACompletedMatches,
    required this.playerBCompletedMatches,
    required this.playerAWins,
    required this.playerBWins,
  });

  final int playerACompletedMatches;
  final int playerBCompletedMatches;
  final int playerAWins;
  final int playerBWins;

  /// 分母は[playerACompletedMatches]（13章）。0なら`null`。
  double? get playerAWinRateCompletedMatches => playerACompletedMatches == 0
      ? null
      : playerAWins / playerACompletedMatches;

  /// 分母は[playerBCompletedMatches]（13章）。0なら`null`。
  double? get playerBWinRateCompletedMatches => playerBCompletedMatches == 0
      ? null
      : playerBWins / playerBCompletedMatches;
}

/// mirror match（`wrestlerAId == wrestlerBId`）のみを対象としたfirst-class
/// metric（24章）。global mirror aggregateのみを提供し、wrestler別mirrorの
/// 内訳は持たない（public schemaを膨らませないため）。
class CombatV1MirrorAggregate {
  const CombatV1MirrorAggregate({
    required this.termination,
    required this.playerAWins,
    required this.playerBWins,
  });

  final CombatV1TerminationDistribution termination;
  final int playerAWins;
  final int playerBWins;

  int get totalMatches => termination.totalMatches;
  int get completedMatches => termination.completedMatches;
  int get safetyLimitMatches => termination.safetyLimitMatches;
  double? get safetyLimitRate => termination.safetyLimitRate;

  /// 分母は[completedMatches]（13章）。0なら`null`。
  double? get playerAWinRateCompletedMatches =>
      completedMatches == 0 ? null : playerAWins / completedMatches;

  /// `(playerAWinRateCompletedMatches - 0.5).abs()`。
  /// [playerAWinRateCompletedMatches]が`null`なら`null`。
  double? get absoluteDeviationFromFiftyPercent {
    final rate = playerAWinRateCompletedMatches;
    return rate == null ? null : (rate - 0.5).abs();
  }
}

/// [CombatV1BatchAggregationAccumulator.build]/[combatV1AggregateBatchResults]
/// の戻り値（18章）。`CombatV1BatchSimulationResult`（Batch Runner側）が
/// これへ`config`/`requestedMatchCount`/`executedMatchCount`を追加して
/// 最終resultを組み立てる。
class CombatV1BatchAggregateBundle {
  CombatV1BatchAggregateBundle({
    required this.global,
    required List<CombatV1MatchupAggregate> matchups,
    required List<CombatV1WrestlerAggregate> wrestlers,
    required this.seat,
    required this.mirror,
  }) : matchups = List.unmodifiable(matchups),
       wrestlers = List.unmodifiable(wrestlers);

  final CombatV1GlobalAggregate global;

  /// canonical matrix順（初出順）、unmodifiable。
  final List<CombatV1MatchupAggregate> matchups;

  /// wrestlerId初出順、unmodifiable。
  final List<CombatV1WrestlerAggregate> wrestlers;

  final CombatV1SeatAggregate seat;
  final CombatV1MirrorAggregate mirror;
}
