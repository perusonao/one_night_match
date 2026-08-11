/// Combat Ver.1 Phase 12A — Simulation Config
/// （docs/design/combat_v1_phase12a_simulation_core.md）。
///
/// 「同じ設定＋同じseedなら再現可能なCPU vs CPU対戦」を1試合または複数試合
/// 実行するための入力パラメータ。Phase 11Bの`CombatV1CpuMatchRunner`・
/// Phase 11Aの`CombatV1ProductionMatchStarter`をそのまま呼び出す上位層
/// （`combat_v1_simulation_runner.dart`）が消費する。
library;

import '../combat_v1_engine.dart';
import '../combat_v1_production_match_setup.dart';
import '../combat_v1_rules_config.dart';
import 'combat_v1_simulation_policy.dart';

/// CPU vs CPU simulationの実行設定（Phase 12A）。immutable。
///
/// [CombatV1SimulationRunner]の入力。Randomインスタンス自体は保持しない
/// （[masterSeed]から`combat_v1_simulation_seed.dart`の`deriveV1SimulationSeeds`
/// を介して都度導出する——同じConfigを複数回runしても、Config自身が
/// 消費済みRandom stateを持ち越すことがないようにするため）。
///
/// [playerAPolicy]/[playerBPolicy]は[CombatV1SimulationPolicyKind]（closed
/// enum、Phase 11Bの`CombatV1FirstLegalPolicy`/`CombatV1RandomLegalPolicy`
/// のみ）——任意のfactory closureを注入できる設計は採用しない
/// （Codex review Major Finding M1対応、`combat_v1_simulation_policy.dart`
/// 参照）。enumであるためidのvalidationは不要——値そのものが構造的に
/// validである。
///
/// コンストラクタで以下をfail-fast検証する（[CombatV1IllegalActionException]）:
///
/// - [wrestlerAId]/[wrestlerBId]が`combatV1ProductionWrestlerRegistry`に
///   存在すること（`CombatV1ProductionMatchStarter`と同じレジストリを使い、
///   同じ形で未知wrestlerを拒否する）
/// - [matchCount] > 0
/// - [maxActions] > 0
class CombatV1SimulationConfig {
  CombatV1SimulationConfig({
    required this.wrestlerAId,
    required this.wrestlerBId,
    required this.playerAPolicy,
    required this.playerBPolicy,
    required this.matchCount,
    required this.masterSeed,
    this.maxActions = 500,
    this.rules = const CombatV1RulesConfig(),
  }) {
    if (!combatV1ProductionWrestlerRegistry.containsKey(wrestlerAId)) {
      throw CombatV1IllegalActionException(
        '未知のProduction wrestlerIdです（wrestlerAId）: $wrestlerAId',
      );
    }
    if (!combatV1ProductionWrestlerRegistry.containsKey(wrestlerBId)) {
      throw CombatV1IllegalActionException(
        '未知のProduction wrestlerIdです（wrestlerBId）: $wrestlerBId',
      );
    }
    if (matchCount <= 0) {
      throw CombatV1IllegalActionException(
        'matchCountは1以上である必要があります: $matchCount',
      );
    }
    if (maxActions <= 0) {
      throw CombatV1IllegalActionException(
        'maxActionsは1以上である必要があります: $maxActions',
      );
    }
  }

  /// `combatV1ProductionWrestlerRegistry`のキー（例: `'misaki'`）。playerA
  /// （player index 0）が使用するwrestler。
  final String wrestlerAId;

  /// playerB（player index 1）が使用するwrestler。[wrestlerAId]と同じ値
  /// （mirror match）も許容する。
  final String wrestlerBId;

  final CombatV1SimulationPolicyKind playerAPolicy;
  final CombatV1SimulationPolicyKind playerBPolicy;

  /// 実行する試合数。
  final int matchCount;

  /// このSimulation全体のroot seed。`deriveV1SimulationSeeds`を介して、
  /// 各試合固有のseed群（matchSeed/engineSeed/policy seed）へ決定論的に
  /// 分岐する。
  final int masterSeed;

  /// `CombatV1CpuMatchRunner.maxActions`へそのまま渡すrunner safety guard。
  final int maxActions;

  final CombatV1RulesConfig rules;
}
