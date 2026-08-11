/// Combat Ver.1 Phase 12B-1 — Batch Simulation Runner
/// （docs/design/combat_v1_phase12b1_batch_core_aggregation.md 3・10・11・
/// 15章）。
///
/// [CombatV1BatchSimulationConfig]から、Production wrestlerのordered matchup
/// matrixをdeterministicに実行し、streamingでaggregateする上位層。Phase 12A
/// の`CombatV1SimulationRunner.runSingleMatch`をそのまま呼び出すのみで、
/// CPU対戦ロジック・seed derivation・simulationMatchId derivationを一切
/// 再実装しない（4章「Phase 12A Boundary」）。
library;

import '../../combat_v1_deck.dart';
import '../../combat_v1_engine.dart';
import '../../combat_v1_rules_config.dart';
import '../combat_v1_match_simulation_result.dart';
import '../combat_v1_simulation_config.dart';
import '../combat_v1_simulation_runner.dart';
import 'combat_v1_batch_aggregate.dart';
import 'combat_v1_batch_aggregator.dart';
import 'combat_v1_batch_length_statistics.dart';
import 'combat_v1_batch_length_statistics_accumulator.dart';
import 'combat_v1_batch_matchup.dart';
import 'combat_v1_batch_simulation_config.dart';
import 'combat_v1_batch_simulation_result.dart';

/// [CombatV1BatchSimulationConfig]から、bounded・deterministicなbatch CPU
/// vs CPU simulationを実行するrunner（Phase 12B-1）。
///
/// このクラス自身はCPU対戦ロジック・1試合単位のseed/identity
/// derivationを一切持たない。責務は以下のみ:
///
/// 1. [CombatV1BatchSimulationConfig.wrestlerIds]から
///    [combatV1GenerateMatchupMatrix]でordered matchup matrixを生成する
/// 2. 各matchupについて、local matchIndex `0..matchesPerMatchup-1`で
///    Phase 12Aの`CombatV1SimulationRunner.runSingleMatch`を呼ぶ
/// 3. 返ってきた結果が、要求したmatchup/pairing/masterSeed/maxActions/
///    rules/matchIndexと一致することをPhase 12B自身の構造的invariantとして
///    検証する（15章）
/// 4. [CombatV1BatchAggregationAccumulator]へ結果を渡し、参照をすぐ破棄する
///    （17章「Streaming Aggregation」——個別match resultを保持しない）
/// 5. 集約結果を[CombatV1BatchSimulationResult]へ詰め替える
class CombatV1BatchSimulationRunner {
  const CombatV1BatchSimulationRunner();

  /// [config]に従ってordered matchup matrix全体を実行し、集約結果を返す。
  CombatV1BatchSimulationResult run(CombatV1BatchSimulationConfig config) {
    final matrix = combatV1GenerateMatchupMatrix(config.wrestlerIds);
    final requestedMatchCount = matrix.length * config.matchesPerMatchup;

    const simulationRunner = CombatV1SimulationRunner();
    final accumulator = CombatV1BatchAggregationAccumulator();
    final statisticsAccumulator = CombatV1BatchDescriptiveStatisticsAccumulator();

    var executedMatchCount = 0;
    for (final matchup in matrix) {
      final simulationConfig = CombatV1SimulationConfig(
        wrestlerAId: matchup.wrestlerAId,
        wrestlerBId: matchup.wrestlerBId,
        playerAPolicy: config.playerAPolicy,
        playerBPolicy: config.playerBPolicy,
        matchCount: config.matchesPerMatchup,
        masterSeed: config.masterSeed,
        maxActions: config.maxActions,
        rules: config.rules,
      );

      for (
        var localMatchIndex = 0;
        localMatchIndex < config.matchesPerMatchup;
        localMatchIndex++
      ) {
        final result = simulationRunner.runSingleMatch(
          simulationConfig,
          localMatchIndex,
        );
        _verifyMatchResultInvariants(
          result: result,
          matchup: matchup,
          config: config,
          localMatchIndex: localMatchIndex,
        );
        accumulator.add(result);
        statisticsAccumulator.add(result);
        executedMatchCount++;
      }
    }

    if (executedMatchCount != requestedMatchCount) {
      throw CombatV1IllegalActionException(
        '内部invariant違反: executedMatchCount($executedMatchCount)が'
        'requestedMatchCount($requestedMatchCount)と一致しません',
      );
    }

    final bundle = accumulator.build();
    final statistics = statisticsAccumulator.build();
    _verifyStatisticsInvariants(bundle: bundle, statistics: statistics);

    return CombatV1BatchSimulationResult(
      config: config,
      requestedMatchCount: requestedMatchCount,
      executedMatchCount: executedMatchCount,
      global: bundle.global,
      matchups: bundle.matchups,
      wrestlers: bundle.wrestlers,
      seat: bundle.seat,
      mirror: bundle.mirror,
      statistics: statistics,
    );
  }

  /// Phase 12B-2A `statistics`（[CombatV1BatchDescriptiveStatistics]）が、
  /// 同じrun内で構築したPhase 12B-1 core aggregate（[bundle]）と構造的に
  /// 対応することを検証する（docs/design/
  /// combat_v1_phase12b2a_match_length_statistics.md 17章「Internal
  /// Invariants」／18章「Matchup Statistics Order」）。
  void _verifyStatisticsInvariants({
    required CombatV1BatchAggregateBundle bundle,
    required CombatV1BatchDescriptiveStatistics statistics,
  }) {
    if (statistics.global.length.actionCount.sampleCount !=
        bundle.global.completedMatches) {
      throw CombatV1IllegalActionException(
        '内部invariant違反: statistics.global.length.actionCount.'
        'sampleCountがglobal.completedMatchesと一致しません',
      );
    }
    if (statistics.global.length.finalTurnNumber.sampleCount !=
        bundle.global.completedMatches) {
      throw CombatV1IllegalActionException(
        '内部invariant違反: statistics.global.length.finalTurnNumber.'
        'sampleCountがglobal.completedMatchesと一致しません',
      );
    }
    if (statistics.matchups.length != bundle.matchups.length) {
      throw CombatV1IllegalActionException(
        '内部invariant違反: statistics.matchups件数(${statistics.matchups.length})'
        'がbundle.matchups件数(${bundle.matchups.length})と一致しません',
      );
    }
    for (var i = 0; i < bundle.matchups.length; i++) {
      final coreEntry = bundle.matchups[i];
      final statsEntry = statistics.matchups[i];
      if (statsEntry.matchup != coreEntry.matchup) {
        throw CombatV1IllegalActionException(
          '内部invariant違反: statistics.matchups[$i]のmatchup'
          '(${statsEntry.matchup})がbundle.matchups[$i]'
          '(${coreEntry.matchup})と一致しません',
        );
      }
      if (statsEntry.length.actionCount.sampleCount !=
          coreEntry.completedMatches) {
        throw CombatV1IllegalActionException(
          '内部invariant違反: statistics.matchups[$i].length.actionCount.'
          'sampleCountが対応するmatchup.completedMatchesと一致しません'
          '（matchup: ${coreEntry.matchup}）',
        );
      }
      if (statsEntry.length.finalTurnNumber.sampleCount !=
          coreEntry.completedMatches) {
        throw CombatV1IllegalActionException(
          '内部invariant違反: statistics.matchups[$i].length.'
          'finalTurnNumber.sampleCountが対応するmatchup.completedMatchesと'
          '一致しません（matchup: ${coreEntry.matchup}）',
        );
      }
    }
  }

  /// [result]が、要求した[matchup]・[config]（pairing/masterSeed/maxActions/
  /// rules）・[localMatchIndex]と構造的に一致することを検証する（15章
  /// 「Internal Invariants」——Phase 12B自身のstructural invariant違反は
  /// fail-fastする。Engine invariantViolation（14章）とは別概念）。
  void _verifyMatchResultInvariants({
    required CombatV1MatchSimulationResult result,
    required CombatV1Matchup matchup,
    required CombatV1BatchSimulationConfig config,
    required int localMatchIndex,
  }) {
    if (result.wrestlerAId != matchup.wrestlerAId ||
        result.wrestlerBId != matchup.wrestlerBId) {
      throw CombatV1IllegalActionException(
        '内部invariant違反: simulation resultのwrestlerA/Bが要求したmatchupと'
        '一致しません（matchup: ${matchup.wrestlerAId} vs '
        '${matchup.wrestlerBId}, result: ${result.wrestlerAId} vs '
        '${result.wrestlerBId}）',
      );
    }
    if (result.playerAPolicyId != config.playerAPolicy.policyId ||
        result.playerBPolicyId != config.playerBPolicy.policyId) {
      throw CombatV1IllegalActionException(
        '内部invariant違反: simulation resultのpolicyIdがbatch pairingと'
        '一致しません（simulationMatchId: ${result.simulationMatchId}）',
      );
    }
    if (result.masterSeed != config.masterSeed) {
      throw CombatV1IllegalActionException(
        '内部invariant違反: simulation resultのmasterSeedがconfigと'
        '一致しません（simulationMatchId: ${result.simulationMatchId}）',
      );
    }
    if (result.maxActions != config.maxActions) {
      throw CombatV1IllegalActionException(
        '内部invariant違反: simulation resultのmaxActionsがconfigと'
        '一致しません（simulationMatchId: ${result.simulationMatchId}）',
      );
    }
    if (!_rulesConfigValueEquals(result.rules, config.rules)) {
      throw CombatV1IllegalActionException(
        '内部invariant違反: simulation resultのrulesがconfigと一致しません'
        '（simulationMatchId: ${result.simulationMatchId}）',
      );
    }
    if (result.matchIndex != localMatchIndex) {
      throw CombatV1IllegalActionException(
        '内部invariant違反: simulation resultのmatchIndexが期待したlocal '
        'matchIndexと一致しません（expected: $localMatchIndex, actual: '
        '${result.matchIndex}, simulationMatchId: '
        '${result.simulationMatchId}）',
      );
    }
  }
}

/// [CombatV1RulesConfig]の全outcome-affecting fieldをfield-by-fieldで比較
/// する（15章「Internal Invariants」——object identity/hashCodeに依存しない
/// explicit value comparison helper。`CombatV1RulesConfig`は`==`をoverride
/// していないため、既定のidentity比較のままでは異なるinstanceを常に
/// 不一致と判定してしまう）。
///
/// field一覧は`combat_v1_simulation_seed.dart`の`_rulesIdentityComponents`
/// （Phase 12A、simulationMatchId算出用）と同じ22 field（`deckComposition`の
/// 4 subfieldを含む）。
bool _rulesConfigValueEquals(CombatV1RulesConfig a, CombatV1RulesConfig b) {
  if (identical(a, b)) return true;
  return a.startingHp == b.startingHp &&
      a.startingKoc == b.startingKoc &&
      a.startingPinCards == b.startingPinCards &&
      a.startingHandSize == b.startingHandSize &&
      _deckCompositionValueEquals(a.deckComposition, b.deckComposition) &&
      a.normalSameNameLimit == b.normalSameNameLimit &&
      a.signatureSameNameLimit == b.signatureSameNameLimit &&
      a.finisherSameNameLimit == b.finisherSameNameLimit &&
      a.counterSameNameLimit == b.counterSameNameLimit &&
      a.counterAllowsWildSubstitution == b.counterAllowsWildSubstitution &&
      a.totalPinCards == b.totalPinCards &&
      a.pinCountOneKocCost == b.pinCountOneKocCost &&
      a.pinCountTwoKocCost == b.pinCountTwoKocCost &&
      a.pinCountTwoPointNineKocCost == b.pinCountTwoPointNineKocCost &&
      a.submissionHpThreshold == b.submissionHpThreshold &&
      a.submissionEscapeKocCost == b.submissionEscapeKocCost &&
      a.restHpRecovery == b.restHpRecovery &&
      a.roughRestrictedTechniqueLimit == b.roughRestrictedTechniqueLimit &&
      a.finisherHeatThreshold == b.finisherHeatThreshold;
}

bool _deckCompositionValueEquals(
  CombatV1DeckComposition a,
  CombatV1DeckComposition b,
) =>
    identical(a, b) ||
    (a.normalCount == b.normalCount &&
        a.signatureCount == b.signatureCount &&
        a.finisherCount == b.finisherCount &&
        a.counterCount == b.counterCount);
