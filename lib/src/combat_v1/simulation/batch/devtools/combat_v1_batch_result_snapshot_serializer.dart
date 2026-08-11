/// Combat Ver.1 Phase 12B-1 — Development Result Snapshot Serializer
/// （development/verification専用。正式なCSV/JSON Export APIではない）。
///
/// [combatV1BatchResultSnapshotJson]は、既に完成した
/// [CombatV1BatchSimulationResult]（aggregate-only、streaming
/// aggregationが完了した後の最終resultのみ）から、`dart:convert`の
/// `jsonEncode`へそのまま渡せる`Map<String, Object?>`を組み立てる**pure
/// function**。個別`CombatV1MatchSimulationResult`・`simulationMatchId`・
/// seed・replay metadata・action traceを一切必要としない——入力は完成済みの
/// `CombatV1BatchSimulationResult`のみであり、Batch Runner/Accumulatorの
/// streaming aggregation・M1 memory契約（O(distinct matchup + wrestler
/// 数)）に一切影響しない。
///
/// Domain（`CombatV1BatchSimulationResult`とその集約型群）へ`toJson()`を
/// 生やさない——file I/O・JSON化の責務はこのfile（devtools層）に閉じる。
/// 実際にファイルへ書き出す処理は`combat_v1_batch_result_snapshot_writer.dart`
/// （`dart:io`を使うthin wrapper）が別途持つ——このfile自体は`dart:io`を
/// importしない。
library;

import '../../../combat_v1_deck.dart';
import '../../../combat_v1_rules_config.dart';
import '../combat_v1_batch_aggregate.dart';
import '../combat_v1_batch_simulation_result.dart';

/// [result]から、development snapshot用のJSON-serializableな
/// `Map<String, Object?>`を組み立てる。
///
/// [generatedAt]はsnapshotファイルの識別・監査用metadataとしてのみ使う——
/// simulation identity・seed derivationには一切関与しない（Phase 12Aの
/// `simulationMatchId`/seed derivationは現在時刻に依存しないpure
/// functionのままであり、この関数もそれを変更しない）。
///
/// 同一の[result]・同一の[generatedAt]からは常に同一のMapを返す
/// （pure function）。
Map<String, Object?> combatV1BatchResultSnapshotJson(
  CombatV1BatchSimulationResult result, {
  required DateTime generatedAt,
}) {
  final config = result.config;

  return {
    'metadata': {
      'generatedAt': generatedAt.toIso8601String(),
      'game': 'one_night_match',
      'simulator': 'combat_v1_batch_simulation',
      'phase': '12B-1',
      'masterSeed': config.masterSeed,
      'matchesPerMatchup': config.matchesPerMatchup,
      'requestedMatchCount': result.requestedMatchCount,
      'executedMatchCount': result.executedMatchCount,
      'maxActions': config.maxActions,
      'wrestlerIds': config.wrestlerIds,
      'playerAPolicy': config.playerAPolicy.name,
      'playerBPolicy': config.playerBPolicy.name,
      'rules': _rulesJson(config.rules),
    },
    'global': _globalJson(result.global),
    'orderedMatchups': [for (final m in result.matchups) _matchupJson(m)],
    'wrestlers': [for (final w in result.wrestlers) _wrestlerJson(w)],
    'seat': _seatJson(result.seat),
    'mirror': _mirrorJson(result.mirror),
  };
}

Map<String, Object?> _terminalCauseCountsJson(
  CombatV1TerminalCauseCounts counts,
) => {
  'normalPin': counts.normalPin,
  'directPin': counts.directPin,
  'submission': counts.submission,
  'submissionFinisher': counts.submissionFinisher,
  'other': counts.other,
};

Map<String, Object?> _globalJson(CombatV1GlobalAggregate global) => {
  'totalMatches': global.totalMatches,
  'completedMatches': global.completedMatches,
  'safetyLimitMatches': global.safetyLimitMatches,
  'invariantViolationMatches': global.invariantViolationMatches,
  'completionRate': global.completionRate,
  'safetyLimitRate': global.safetyLimitRate,
  'invariantViolationRate': global.invariantViolationRate,
  'playerAWins': global.playerAWins,
  'playerBWins': global.playerBWins,
  'playerAWinRateCompletedMatches': global.playerAWinRateCompletedMatches,
  'playerBWinRateCompletedMatches': global.playerBWinRateCompletedMatches,
  'terminalCauses': _terminalCauseCountsJson(global.terminalCauseCounts),
};

Map<String, Object?> _matchupJson(CombatV1MatchupAggregate matchup) => {
  'wrestlerAId': matchup.matchup.wrestlerAId,
  'wrestlerBId': matchup.matchup.wrestlerBId,
  'totalMatches': matchup.totalMatches,
  'completedMatches': matchup.completedMatches,
  'safetyLimitMatches': matchup.safetyLimitMatches,
  'invariantViolationMatches': matchup.invariantViolationMatches,
  // matchup.completionRate/safetyLimitRate/invariantViolationRateは
  // CombatV1MatchupAggregateのdelegating getter（M4対応、Global aggregate
  // と同型のdirect API）からそのまま読み取るのみ——serializer側でrate計算を
  // 再実装しない。
  'completionRate': matchup.completionRate,
  'safetyLimitRate': matchup.safetyLimitRate,
  'invariantViolationRate': matchup.invariantViolationRate,
  'playerAWins': matchup.playerAWins,
  'playerBWins': matchup.playerBWins,
  'playerAWinRateCompletedMatches': matchup.playerAWinRateCompletedMatches,
  'playerBWinRateCompletedMatches': matchup.playerBWinRateCompletedMatches,
  'terminalCauseCounts': _terminalCauseCountsJson(matchup.terminalCauseCounts),
};

Map<String, Object?> _wrestlerJson(CombatV1WrestlerAggregate wrestler) => {
  'wrestlerId': wrestler.wrestlerId,
  'appearances': wrestler.appearances,
  'completedAppearances': wrestler.completedAppearances,
  'wins': wrestler.wins,
  'winRateCompletedMatches': wrestler.winRateCompletedMatches,
  'playerASeat': {
    'appearances': wrestler.playerAAppearances,
    'completedAppearances': wrestler.playerACompletedAppearances,
    'wins': wrestler.playerAWins,
    'winRateCompletedMatches': wrestler.playerAWinRateCompletedMatches,
  },
  'playerBSeat': {
    'appearances': wrestler.playerBAppearances,
    'completedAppearances': wrestler.playerBCompletedAppearances,
    'wins': wrestler.playerBWins,
    'winRateCompletedMatches': wrestler.playerBWinRateCompletedMatches,
  },
};

Map<String, Object?> _seatJson(CombatV1SeatAggregate seat) => {
  'playerACompletedMatches': seat.playerACompletedMatches,
  'playerBCompletedMatches': seat.playerBCompletedMatches,
  'playerAWins': seat.playerAWins,
  'playerBWins': seat.playerBWins,
  'playerAWinRateCompletedMatches': seat.playerAWinRateCompletedMatches,
  'playerBWinRateCompletedMatches': seat.playerBWinRateCompletedMatches,
  // API正本のfield名はA/Bのまま——先手/後手命名（firstPlayer等）への変更は
  // しない。以下はあくまで人間可読なmetadata注釈。
  'currentRuleInterpretation': 'Player A starts first',
};

Map<String, Object?> _mirrorJson(CombatV1MirrorAggregate mirror) => {
  'totalMatches': mirror.totalMatches,
  'completedMatches': mirror.completedMatches,
  'safetyLimitMatches': mirror.safetyLimitMatches,
  'invariantViolationMatches': mirror.termination.invariantViolationMatches,
  'playerAWins': mirror.playerAWins,
  'playerBWins': mirror.playerBWins,
  'playerAWinRateCompletedMatches': mirror.playerAWinRateCompletedMatches,
  'absoluteDeviationFromFiftyPercent': mirror.absoluteDeviationFromFiftyPercent,
  'safetyLimitRate': mirror.safetyLimitRate,
};

/// [CombatV1RulesConfig]の全outcome-affecting values（Phase 12Aの
/// `simulationMatchId` identity・`combat_v1_batch_simulation_runner.dart`の
/// `_rulesConfigValueEquals`と同じ22 field、`deckComposition`の4
/// subfieldを含む）をJSONへ展開する。`rules.toString()`は使わない。
Map<String, Object?> _rulesJson(CombatV1RulesConfig rules) => {
  'startingHp': rules.startingHp,
  'startingKoc': rules.startingKoc,
  'startingPinCards': rules.startingPinCards,
  'startingHandSize': rules.startingHandSize,
  'deckComposition': _deckCompositionJson(rules.deckComposition),
  'normalSameNameLimit': rules.normalSameNameLimit,
  'signatureSameNameLimit': rules.signatureSameNameLimit,
  'finisherSameNameLimit': rules.finisherSameNameLimit,
  'counterSameNameLimit': rules.counterSameNameLimit,
  'counterAllowsWildSubstitution': rules.counterAllowsWildSubstitution,
  'totalPinCards': rules.totalPinCards,
  'pinCountOneKocCost': rules.pinCountOneKocCost,
  'pinCountTwoKocCost': rules.pinCountTwoKocCost,
  'pinCountTwoPointNineKocCost': rules.pinCountTwoPointNineKocCost,
  'submissionHpThreshold': rules.submissionHpThreshold,
  'submissionEscapeKocCost': rules.submissionEscapeKocCost,
  'restHpRecovery': rules.restHpRecovery,
  'roughRestrictedTechniqueLimit': rules.roughRestrictedTechniqueLimit,
  'finisherHeatThreshold': rules.finisherHeatThreshold,
};

Map<String, Object?> _deckCompositionJson(CombatV1DeckComposition deck) => {
  'normalCount': deck.normalCount,
  'signatureCount': deck.signatureCount,
  'finisherCount': deck.finisherCount,
  'counterCount': deck.counterCount,
};
