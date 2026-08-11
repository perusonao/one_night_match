/// Combat Ver.1 Phase 12B-1 — Pure Aggregator
/// （docs/design/combat_v1_phase12b1_batch_core_aggregation.md 17〜18章、
/// Codex review Blocking Finding M1/M2対応）。
///
/// Aggregation logicをexecutionから完全に分離する。[CombatV1MatchSimulationResult]
/// （Phase 12A）を1件ずつ受け取り、matchup毎・wrestler毎の小さいmutable
/// counter bucketだけを保持する（`Map<CombatV1Matchup, ...>`・
/// `Map<String, ...>`、いずれもO(distinct matchup/wrestler数)のサイズ）——
/// O(match数)のメモリを消費しない（17章「Aggregate-Only Memory Strategy /
/// Streaming Aggregation」）。
///
/// **M1対応（simulationMatchId非保持）**: このaccumulatorは
/// `simulationMatchId`（や、その他試合数に比例するidentity）を1件も
/// 保持しない——batch全体のsimulationMatchId setを保持してglobal
/// duplicate検出を行う設計は、production batch executionのmemoryを
/// O(totalMatches)にしてしまうため採用しない。Phase 12B-1における
/// execution identityの正本は`(CombatV1Matchup, localMatchIndex)`
/// ——`CombatV1BatchSimulationRunner`がmatrix/local indexを決定論的に
/// 生成する構造そのものが実行計画上の重複を防ぐ（17章参照）。
/// `simulationMatchId`はPhase 12A由来のreplay/audit identityとしては
/// 引き続き各resultに保持されるが、このaccumulatorレベルでのglobal
/// uniqueness検査の対象にはしない。
///
/// **M2対応（structured result invariant検証）**: [add]は、矛盾した
/// [CombatV1MatchSimulationResult]（例: `termination==matchOver`なのに
/// `winnerPlayerIndex`がnull）を集計へ混入させない——Phase 12Aの実際の
/// structured termination契約（`CombatV1CpuMatchRunner`/
/// `CombatV1MatchSimulationResult.fromCpuResult`）と整合する検証を
/// [_validateStructuredResultInvariants]で行う。
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
///
/// 保持するmutable stateは、matchup毎・wrestler毎の小さいcounter bucket
/// （`Map<CombatV1Matchup, _MatchupBucket>`・`Map<String, _WrestlerBucket>`）
/// とglobal/mirror用のスカラーcounterのみ——`O(distinct matchup数 +
/// distinct wrestler数)`。試合数に比例して増えるcollection（全
/// simulationMatchIdのSet・全match resultのList等）は一切保持しない
/// （M1対応、上記library doc参照）。
class CombatV1BatchAggregationAccumulator {
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

  /// [result]を1件aggregateする。集計の前に
  /// [_validateStructuredResultInvariants]で、Phase 12Aの実際の
  /// structured termination契約と矛盾しないことを検証する
  /// （[CombatV1IllegalActionException]でfail-fast、M2対応）。
  ///
  /// simulationMatchIdのbatch全体でのglobal duplicate検査は行わない
  /// （M1対応、class doc参照）——execution identityの正本は
  /// `(CombatV1Matchup, localMatchIndex)`であり、それは
  /// `CombatV1BatchSimulationRunner`の実行計画（matrix × local index
  /// loop）自体が構造的に重複させない。
  void add(CombatV1MatchSimulationResult result) {
    _validateStructuredResultInvariants(result);

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

        // winnerPlayerIndex∈{0,1}・terminalCause非nullは
        // _validateStructuredResultInvariantsが呼び出し時点で既に
        // 保証済み（M2対応）。
        final winnerPlayerIndex = result.winnerPlayerIndex;
        final terminalCause = result.terminalCause!;

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

  /// [result]が、Phase 12Aの実際のstructured termination契約
  /// （`CombatV1CpuMatchRunner`/`CombatV1MatchSimulationResult.fromCpuResult`）
  /// と矛盾しないことを検証する（Codex review Blocking Finding M2/M3対応）。
  ///
  /// Phase 12Aが実際に保証する制約のみを検証し、保証していない制約は
  /// 追加しない。
  ///
  /// - `termination == matchOver`: [CombatV1MatchSimulationResult.winnerPlayerIndex]
  ///   が0/1、[CombatV1MatchSimulationResult.terminalCause]が非null、
  ///   [CombatV1MatchSimulationResult.safetyLimitReached] == false、
  ///   [CombatV1MatchSimulationResult.invariantViolationMessage] == null
  ///   （いずれも`CombatV1CpuMatchResult`/`fromCpuResult`が常に保証する
  ///   組み合わせ）
  /// - `termination == safetyLimit`: winnerPlayerIndex == null、
  ///   terminalCause == null、safetyLimitReached == true、
  ///   invariantViolationMessage == null（`CombatV1CpuMatchRunner.run`は
  ///   `state.isOver`が`false`の場合のみsafetyLimitを返すため、winnerは
  ///   常にnull）
  /// - `termination == invariantViolation`: terminalCause == null、
  ///   safetyLimitReached == false、invariantViolationMessageが非null・
  ///   非空（いずれも`CombatV1CpuMatchRunner`の全invariantViolation経路で
  ///   常に成立）。**winnerPlayerIndex/winnerWrestlerIdは以下の2形状の
  ///   どちらも許容する（Codex review Blocking Finding M3対応。当初は
  ///   両方`null`のみを許容していたが、これはPhase 12Aの実際の契約より
  ///   厳格すぎることが再reviewで判明した）**:
  ///
  ///   - Shape A（no winner）: `winnerPlayerIndex == null` かつ
  ///     `winnerWrestlerId == null`
  ///   - Shape B（winner preserved from final state）:
  ///     `winnerPlayerIndex`が0または1、かつ`winnerWrestlerId`がそれに
  ///     対応するwrestlerIdと一致
  ///
  ///   `CombatV1CpuMatchRunner._buildResult`のcheckpoint 3
  ///   （result返却直前の最終invariant再検証）は、既に`matchOver`と
  ///   判定された直後のstate（`winnerPlayerIndex`が既に0/1でセット
  ///   済み・`state.isOver == true`）を`invariantViolation`へ再分類する
  ///   経路を持つ。この経路では`finalState`自体は変更されないため、
  ///   `finalState.winnerPlayerIndex`はセットされたままとなり、
  ///   `CombatV1MatchSimulationResult.fromCpuResult`はそれをそのまま
  ///   Resultへ転記する（Shape B）。これはcorrupted resultではなく、
  ///   Phase 12Aが正規に返し得るstructured abnormal result——「決着は
  ///   していた（winnerが確定していた）が、その後の最終invariant検証で
  ///   Core Engine側の別のinvariant違反が見つかったため、公式には
  ///   `matchOver`ではなく`invariantViolation`として報告する」という
  ///   意味論を持つ。Phase 12B-1はこれを拒否しない——ただし14章
  ///   「Aggregation Semantics」の通り、Shape Bのwinner
  ///   metadataは勝敗集計（`playerAWins`/`playerBWins`/wrestler wins/
  ///   `completedMatches`/`terminalCause`カウント）へは一切使わない
  ///   （`add`の`switch`で`invariantViolation`ケースがこれらへ加算する
  ///   経路を持たないことで構造的に保証する）。
  ///
  ///   Shape A/B以外（例: `winnerPlayerIndex`が非nullなのに
  ///   `winnerWrestlerId`が対応しない、`winnerPlayerIndex`が0/1/null
  ///   以外）は、termination共通チェック（下記実装）で引き続き拒否する。
  void _validateStructuredResultInvariants(
    CombatV1MatchSimulationResult result,
  ) {
    final id = result.simulationMatchId;
    final winnerPlayerIndex = result.winnerPlayerIndex;
    final winnerWrestlerId = result.winnerWrestlerId;

    // termination共通: winnerWrestlerIdはwinnerPlayerIndexに対応する
    // wrestlerIdと一致していなければならない
    // （`CombatV1MatchSimulationResult.fromCpuResult`のmapping）。
    final expectedWinnerWrestlerId = switch (winnerPlayerIndex) {
      0 => result.wrestlerAId,
      1 => result.wrestlerBId,
      null => null,
      _ => throw CombatV1IllegalActionException(
        'winnerPlayerIndexが0/1/nullのいずれでもありません'
        '（simulationMatchId: $id, winnerPlayerIndex: $winnerPlayerIndex）',
      ),
    };
    if (winnerWrestlerId != expectedWinnerWrestlerId) {
      throw CombatV1IllegalActionException(
        'winnerWrestlerIdがwinnerPlayerIndexに対応するwrestlerIdと'
        '一致しません（simulationMatchId: $id, winnerPlayerIndex: '
        '$winnerPlayerIndex, winnerWrestlerId: $winnerWrestlerId, '
        'expected: $expectedWinnerWrestlerId）',
      );
    }

    switch (result.termination) {
      case CombatV1CpuMatchTermination.matchOver:
        if (winnerPlayerIndex != 0 && winnerPlayerIndex != 1) {
          throw CombatV1IllegalActionException(
            'termination==matchOverですがwinnerPlayerIndexが0/1のいずれでも'
            'ありません（simulationMatchId: $id, winnerPlayerIndex: '
            '$winnerPlayerIndex）',
          );
        }
        if (result.terminalCause == null) {
          throw CombatV1IllegalActionException(
            'termination==matchOverですがterminalCauseがnullです'
            '（simulationMatchId: $id）',
          );
        }
        if (result.safetyLimitReached) {
          throw CombatV1IllegalActionException(
            'termination==matchOverですがsafetyLimitReached==trueです'
            '（simulationMatchId: $id）',
          );
        }
        if (result.invariantViolationMessage != null) {
          throw CombatV1IllegalActionException(
            'termination==matchOverですがinvariantViolationMessageが'
            '非nullです（simulationMatchId: $id）',
          );
        }
      case CombatV1CpuMatchTermination.safetyLimit:
        if (winnerPlayerIndex != null) {
          throw CombatV1IllegalActionException(
            'termination==safetyLimitですがwinnerPlayerIndexが非nullです'
            '（simulationMatchId: $id, winnerPlayerIndex: '
            '$winnerPlayerIndex）',
          );
        }
        if (result.terminalCause != null) {
          throw CombatV1IllegalActionException(
            'termination==safetyLimitですがterminalCauseが非nullです'
            '（simulationMatchId: $id）',
          );
        }
        if (!result.safetyLimitReached) {
          throw CombatV1IllegalActionException(
            'termination==safetyLimitですがsafetyLimitReached==falseです'
            '（simulationMatchId: $id）',
          );
        }
        if (result.invariantViolationMessage != null) {
          throw CombatV1IllegalActionException(
            'termination==safetyLimitですがinvariantViolationMessageが'
            '非nullです（simulationMatchId: $id）',
          );
        }
      case CombatV1CpuMatchTermination.invariantViolation:
        // winnerPlayerIndex/winnerWrestlerIdは、Shape A（both null）・
        // Shape B（final stateのwinnerがそのまま保持され、0/1 +
        // 対応するwrestlerIdのペア）のいずれも許容する——両方とも上の
        // termination共通チェックで既に「0/1/nullのいずれか」かつ
        // 「winnerWrestlerIdとの対応が正しいこと」を検証済み。ここでは
        // これ以上winnerPlayerIndexの値を制限しない（Codex review
        // Blocking Finding M3対応、下記doc参照）。
        if (result.terminalCause != null) {
          throw CombatV1IllegalActionException(
            'termination==invariantViolationですがterminalCauseが非nullです'
            '（simulationMatchId: $id）',
          );
        }
        if (result.safetyLimitReached) {
          throw CombatV1IllegalActionException(
            'termination==invariantViolationですがsafetyLimitReached=='
            'trueです（simulationMatchId: $id）',
          );
        }
        final message = result.invariantViolationMessage;
        if (message == null || message.trim().isEmpty) {
          throw CombatV1IllegalActionException(
            'termination==invariantViolationですがinvariantViolationMessage'
            'が空です（simulationMatchId: $id）',
          );
        }
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
