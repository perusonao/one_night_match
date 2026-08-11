/// Combat Ver.1 Phase 12B-1 — Pure Aggregator
/// （docs/design/combat_v1_phase12b1_batch_core_aggregation.md 17〜18章）。
///
/// Aggregation logicをexecutionから完全に分離する。[CombatV1MatchSimulationResult]
/// （Phase 12A）を1件ずつ受け取り、matchup毎・wrestler毎の小さいmutable
/// counter bucketだけを保持する（`Map<CombatV1Matchup, ...>`・
/// `Map<String, ...>`、いずれもO(distinct matchup/wrestler数)のサイズ）——
/// O(match数)のメモリを消費しない（17章「Aggregate-Only Memory Strategy /
/// Streaming Aggregation」）。
///
/// [CombatV1BatchAggregationAccumulator]自身はPhase 12A/Core Engineを一切
/// importしない——`CombatV1MatchSimulationResult`（Phase 12Aのpublic result
/// 型）以外の外部stateに依存しないpure boundaryとして実装する。
library;

import '../../combat_v1_cpu_match_runner.dart';
import '../../combat_v1_engine.dart';
import '../combat_v1_match_simulation_result.dart';
import 'combat_v1_batch_aggregate.dart';
import 'combat_v1_batch_matchup.dart';

/// matchup単位のmutable counter bucket（internal、streaming aggregation用）。
class _MatchupBucket {
  int total = 0;
  int completed = 0;
  int safetyLimit = 0;
  int invariantViolation = 0;
  int playerAWins = 0;
  int playerBWins = 0;
  int normalPin = 0;
  int directPin = 0;
  int submission = 0;
  int submissionFinisher = 0;
  int other = 0;

  CombatV1MatchupAggregate toAggregate(CombatV1Matchup matchup) =>
      CombatV1MatchupAggregate(
        matchup: matchup,
        termination: CombatV1TerminationDistribution(
          totalMatches: total,
          completedMatches: completed,
          safetyLimitMatches: safetyLimit,
          invariantViolationMatches: invariantViolation,
        ),
        playerAWins: playerAWins,
        playerBWins: playerBWins,
        terminalCauseCounts: CombatV1TerminalCauseCounts(
          normalPin: normalPin,
          directPin: directPin,
          submission: submission,
          submissionFinisher: submissionFinisher,
          other: other,
        ),
      );
}

/// wrestler単位のmutable counter bucket（internal、streaming aggregation用）。
class _WrestlerBucket {
  int playerAAppearances = 0;
  int playerACompletedAppearances = 0;
  int playerAWins = 0;
  int playerBAppearances = 0;
  int playerBCompletedAppearances = 0;
  int playerBWins = 0;

  CombatV1WrestlerAggregate toAggregate(String wrestlerId) =>
      CombatV1WrestlerAggregate(
        wrestlerId: wrestlerId,
        playerAAppearances: playerAAppearances,
        playerACompletedAppearances: playerACompletedAppearances,
        playerAWins: playerAWins,
        playerBAppearances: playerBAppearances,
        playerBCompletedAppearances: playerBCompletedAppearances,
        playerBWins: playerBWins,
      );
}

/// [CombatV1MatchSimulationResult]をstreamingで受け取り、集約する
/// mutable accumulator（18章）。
///
/// Batch Runner（`CombatV1BatchSimulationRunner`）は、1試合実行するたびに
/// [add]を呼び、`result`への参照はそのループiteration内でしか保持しない
/// （17章）。[build]は最終的な[CombatV1BatchAggregateBundle]を構築し、あわせて
/// 内部invariant（15章）を検証する。
class CombatV1BatchAggregationAccumulator {
  final Set<String> _seenSimulationMatchIds = {};

  int _totalMatches = 0;
  int _completedMatches = 0;
  int _safetyLimitMatches = 0;
  int _invariantViolationMatches = 0;
  int _globalPlayerAWins = 0;
  int _globalPlayerBWins = 0;
  int _normalPin = 0;
  int _directPin = 0;
  int _submission = 0;
  int _submissionFinisher = 0;
  int _other = 0;

  final Map<CombatV1Matchup, _MatchupBucket> _matchupBuckets = {};
  final List<CombatV1Matchup> _matchupOrder = [];

  final Map<String, _WrestlerBucket> _wrestlerBuckets = {};
  final List<String> _wrestlerOrder = [];

  int _mirrorTotal = 0;
  int _mirrorCompleted = 0;
  int _mirrorSafetyLimit = 0;
  int _mirrorInvariantViolation = 0;
  int _mirrorPlayerAWins = 0;
  int _mirrorPlayerBWins = 0;

  /// [result]を1件aggregateする。同一の[CombatV1MatchSimulationResult.simulationMatchId]
  /// を2度[add]した場合はfail-fast（[CombatV1IllegalActionException]、15章
  /// 「Internal Invariants」——32-bit simulationMatchId hash衝突の理論
  /// リスクをここで検知する）。
  void add(CombatV1MatchSimulationResult result) {
    if (!_seenSimulationMatchIds.add(result.simulationMatchId)) {
      throw CombatV1IllegalActionException(
        'batch内でsimulationMatchIdが重複しています: '
        '${result.simulationMatchId}',
      );
    }

    final matchup = CombatV1Matchup(
      wrestlerAId: result.wrestlerAId,
      wrestlerBId: result.wrestlerBId,
    );
    final matchupBucket = _matchupBuckets.putIfAbsent(matchup, () {
      _matchupOrder.add(matchup);
      return _MatchupBucket();
    });
    final wrestlerABucket = _wrestlerBuckets.putIfAbsent(
      result.wrestlerAId,
      () {
        _wrestlerOrder.add(result.wrestlerAId);
        return _WrestlerBucket();
      },
    );
    final wrestlerBBucket = _wrestlerBuckets.putIfAbsent(
      result.wrestlerBId,
      () {
        _wrestlerOrder.add(result.wrestlerBId);
        return _WrestlerBucket();
      },
    );

    final isMirror = matchup.isMirror;

    _totalMatches++;
    matchupBucket.total++;
    wrestlerABucket.playerAAppearances++;
    wrestlerBBucket.playerBAppearances++;
    if (isMirror) _mirrorTotal++;

    switch (result.termination) {
      case CombatV1CpuMatchTermination.matchOver:
        _completedMatches++;
        matchupBucket.completed++;
        wrestlerABucket.playerACompletedAppearances++;
        wrestlerBBucket.playerBCompletedAppearances++;
        if (isMirror) _mirrorCompleted++;

        final winnerPlayerIndex = result.winnerPlayerIndex;
        if (winnerPlayerIndex != 0 && winnerPlayerIndex != 1) {
          throw CombatV1IllegalActionException(
            'termination==matchOverですがwinnerPlayerIndexが0/1のいずれでも'
            'ありません（simulationMatchId: ${result.simulationMatchId}, '
            'winnerPlayerIndex: $winnerPlayerIndex）',
          );
        }
        final terminalCause = result.terminalCause;
        if (terminalCause == null) {
          throw CombatV1IllegalActionException(
            'termination==matchOverですがterminalCauseがnullです'
            '（simulationMatchId: ${result.simulationMatchId}）',
          );
        }

        if (winnerPlayerIndex == 0) {
          _globalPlayerAWins++;
          matchupBucket.playerAWins++;
          wrestlerABucket.playerAWins++;
          if (isMirror) _mirrorPlayerAWins++;
        } else {
          _globalPlayerBWins++;
          matchupBucket.playerBWins++;
          wrestlerBBucket.playerBWins++;
          if (isMirror) _mirrorPlayerBWins++;
        }

        switch (terminalCause) {
          case CombatV1CpuMatchTerminalCause.normalPin:
            _normalPin++;
            matchupBucket.normalPin++;
          case CombatV1CpuMatchTerminalCause.directPin:
            _directPin++;
            matchupBucket.directPin++;
          case CombatV1CpuMatchTerminalCause.submission:
            _submission++;
            matchupBucket.submission++;
          case CombatV1CpuMatchTerminalCause.submissionFinisher:
            _submissionFinisher++;
            matchupBucket.submissionFinisher++;
          case CombatV1CpuMatchTerminalCause.other:
            _other++;
            matchupBucket.other++;
        }
      case CombatV1CpuMatchTermination.safetyLimit:
        _safetyLimitMatches++;
        matchupBucket.safetyLimit++;
        if (isMirror) _mirrorSafetyLimit++;
      case CombatV1CpuMatchTermination.invariantViolation:
        _invariantViolationMatches++;
        matchupBucket.invariantViolation++;
        if (isMirror) _mirrorInvariantViolation++;
    }
  }

  /// これまで[add]した全結果から[CombatV1BatchAggregateBundle]を構築し、
  /// あわせて内部invariant（15章）を検証する
  /// （[CombatV1IllegalActionException]でfail-fast）。
  CombatV1BatchAggregateBundle build() {
    final termination = CombatV1TerminationDistribution(
      totalMatches: _totalMatches,
      completedMatches: _completedMatches,
      safetyLimitMatches: _safetyLimitMatches,
      invariantViolationMatches: _invariantViolationMatches,
    );
    final terminalCauseCounts = CombatV1TerminalCauseCounts(
      normalPin: _normalPin,
      directPin: _directPin,
      submission: _submission,
      submissionFinisher: _submissionFinisher,
      other: _other,
    );
    final global = CombatV1GlobalAggregate(
      termination: termination,
      playerAWins: _globalPlayerAWins,
      playerBWins: _globalPlayerBWins,
      terminalCauseCounts: terminalCauseCounts,
    );

    final matchups = <CombatV1MatchupAggregate>[
      for (final matchup in _matchupOrder)
        _matchupBuckets[matchup]!.toAggregate(matchup),
    ];

    final wrestlers = <CombatV1WrestlerAggregate>[
      for (final wrestlerId in _wrestlerOrder)
        _wrestlerBuckets[wrestlerId]!.toAggregate(wrestlerId),
    ];

    final seat = CombatV1SeatAggregate(
      playerACompletedMatches: _completedMatches,
      playerBCompletedMatches: _completedMatches,
      playerAWins: _globalPlayerAWins,
      playerBWins: _globalPlayerBWins,
    );

    final mirror = CombatV1MirrorAggregate(
      termination: CombatV1TerminationDistribution(
        totalMatches: _mirrorTotal,
        completedMatches: _mirrorCompleted,
        safetyLimitMatches: _mirrorSafetyLimit,
        invariantViolationMatches: _mirrorInvariantViolation,
      ),
      playerAWins: _mirrorPlayerAWins,
      playerBWins: _mirrorPlayerBWins,
    );

    _verifyInternalInvariants(
      global: global,
      matchups: matchups,
      wrestlers: wrestlers,
    );

    return CombatV1BatchAggregateBundle(
      global: global,
      matchups: matchups,
      wrestlers: wrestlers,
      seat: seat,
      mirror: mirror,
    );
  }

  /// 15章「Internal Invariants」のうちaggregator scopeのものを検証する。
  /// 通常のロジックが正しい限り常に成立するはずの防御的チェックであり、
  /// [add]の分類ロジックにバグが混入した場合の安全網として機能する。
  void _verifyInternalInvariants({
    required CombatV1GlobalAggregate global,
    required List<CombatV1MatchupAggregate> matchups,
    required List<CombatV1WrestlerAggregate> wrestlers,
  }) {
    if (global.totalMatches !=
        global.completedMatches +
            global.safetyLimitMatches +
            global.invariantViolationMatches) {
      throw CombatV1IllegalActionException(
        '内部invariant違反: totalMatchesがcompleted+safetyLimit+'
        'invariantViolationと一致しません',
      );
    }
    if (global.completedMatches != global.playerAWins + global.playerBWins) {
      throw CombatV1IllegalActionException(
        '内部invariant違反: completedMatchesがplayerAWins+playerBWinsと'
        '一致しません',
      );
    }
    if (global.terminalCauseCounts.total != global.completedMatches) {
      throw CombatV1IllegalActionException(
        '内部invariant違反: terminalCause countsの合計がcompletedMatchesと'
        '一致しません',
      );
    }

    final matchupTotalSum = matchups.fold<int>(
      0,
      (sum, m) => sum + m.totalMatches,
    );
    if (matchupTotalSum != global.totalMatches) {
      throw CombatV1IllegalActionException(
        '内部invariant違反: matchup別totalMatchesの合計がglobal.totalMatchesと'
        '一致しません',
      );
    }

    final wrestlerAppearanceSum = wrestlers.fold<int>(
      0,
      (sum, w) => sum + w.appearances,
    );
    if (wrestlerAppearanceSum != 2 * global.totalMatches) {
      throw CombatV1IllegalActionException(
        '内部invariant違反: wrestler別appearancesの合計が'
        '2×global.totalMatchesと一致しません',
      );
    }
  }
}

/// [results]から[CombatV1BatchAggregateBundle]を構築するpure facade（18章）。
///
/// [CombatV1BatchAggregationAccumulator]を内部で使い、`add`をループするのみ
/// ——engineを一切実行していないsynthetic
/// `CombatV1MatchSimulationResult`の`Iterable`を渡すだけでaggregate結果を
/// 得られる（unit testable pure boundary）。
CombatV1BatchAggregateBundle combatV1AggregateBatchResults(
  Iterable<CombatV1MatchSimulationResult> results,
) {
  final accumulator = CombatV1BatchAggregationAccumulator();
  for (final result in results) {
    accumulator.add(result);
  }
  return accumulator.build();
}
