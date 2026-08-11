/// Combat Ver.1 Phase 12B-1 — Batch Simulation Config
/// （docs/design/combat_v1_phase12b1_batch_core_aggregation.md 5・8・9章）。
///
/// Production 4 wrestler（misaki/jack/akari/reina）についてordered matchup
/// matrixを決定論的に実行するための入力パラメータ。
/// [CombatV1BatchSimulationRunner]（`combat_v1_batch_simulation_runner.dart`）
/// の入力。
library;

import '../../combat_v1_engine.dart';
import '../../combat_v1_production_match_setup.dart';
import '../../combat_v1_rules_config.dart';
import '../combat_v1_simulation_policy.dart';
import 'combat_v1_batch_matchup.dart';

/// Production default wrestler order（misaki → jack → akari → reina、5章）。
///
/// `combatV1ProductionWrestlerRegistry`（`Map<String, ...>`）のiteration
/// orderへは一切依存しない、明示的なcanonical ordered listとして固定
/// literalで持つ。
const List<String> combatV1DefaultBatchWrestlerIds = [
  'misaki',
  'jack',
  'akari',
  'reina',
];

/// CPU vs CPU batch simulationの実行設定（Phase 12B-1、8章）。immutable。
///
/// コンストラクタで以下をfail-fast検証する（[CombatV1IllegalActionException]、
/// 9章）:
///
/// - [wrestlerIds]が空でないこと
/// - 各wrestlerIdが空白のみでないこと
/// - [wrestlerIds]内に重複がないこと
/// - 各wrestlerIdが`combatV1ProductionWrestlerRegistry`（Phase 11A）に
///   存在すること
/// - [matchesPerMatchup] > 0
/// - [maxActions] > 0
class CombatV1BatchSimulationConfig {
  CombatV1BatchSimulationConfig({
    List<String> wrestlerIds = combatV1DefaultBatchWrestlerIds,
    required this.matchesPerMatchup,
    required this.masterSeed,
    this.pairing = CombatV1PolicyPairing.randomVsRandom,
    this.maxActions = 500,
    this.rules = const CombatV1RulesConfig(),
  }) : wrestlerIds = List.unmodifiable(wrestlerIds) {
    if (wrestlerIds.isEmpty) {
      throw CombatV1IllegalActionException('wrestlerIdsを空にすることはできません');
    }
    final seenWrestlerIds = <String>{};
    for (final wrestlerId in wrestlerIds) {
      if (wrestlerId.trim().isEmpty) {
        throw CombatV1IllegalActionException('wrestlerIdsに空白のみのIDを含めることはできません');
      }
      if (!seenWrestlerIds.add(wrestlerId)) {
        throw CombatV1IllegalActionException(
          'wrestlerIdsに重複したwrestlerIdが含まれています: $wrestlerId',
        );
      }
      if (!combatV1ProductionWrestlerRegistry.containsKey(wrestlerId)) {
        throw CombatV1IllegalActionException(
          '未知のProduction wrestlerIdです（wrestlerIds）: $wrestlerId',
        );
      }
    }
    if (matchesPerMatchup <= 0) {
      throw CombatV1IllegalActionException(
        'matchesPerMatchupは1以上である必要があります: $matchesPerMatchup',
      );
    }
    if (maxActions <= 0) {
      throw CombatV1IllegalActionException(
        'maxActionsは1以上である必要があります: $maxActions',
      );
    }
  }

  /// matrix生成（`combatV1GenerateMatchupMatrix`）へそのまま渡す、canonical
  /// order付きのwrestlerId列。defaultは[combatV1DefaultBatchWrestlerIds]。
  final List<String> wrestlerIds;

  /// 各matchup（`wrestlerIds.length`の2乗通り）につき実行する試合数。
  final int matchesPerMatchup;

  /// batch全体のroot seed（`CombatV1BatchSimulationConfig`から
  /// `CombatV1SimulationConfig`を組み立てる際、そのまま`masterSeed`として
  /// 渡す）。
  final int masterSeed;

  /// 1 batchにつき1 pairing（7章）。defaultは
  /// [CombatV1PolicyPairing.randomVsRandom]。
  final CombatV1PolicyPairing pairing;

  /// `CombatV1SimulationConfig.maxActions`へそのまま渡すrunner safety guard。
  final int maxActions;

  final CombatV1RulesConfig rules;

  /// [pairing.playerAPolicy]への delegating getter。
  CombatV1SimulationPolicyKind get playerAPolicy => pairing.playerAPolicy;

  /// [pairing.playerBPolicy]への delegating getter。
  CombatV1SimulationPolicyKind get playerBPolicy => pairing.playerBPolicy;
}
