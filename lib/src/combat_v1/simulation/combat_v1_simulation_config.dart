/// Combat Ver.1 Phase 12A — Simulation Config
/// （docs/design/combat_v1_phase12a_simulation_core.md）。
///
/// 「同じ設定＋同じseedなら再現可能なCPU vs CPU対戦」を1試合または複数試合
/// 実行するための入力パラメータ。Phase 11Bの`CombatV1CpuMatchRunner`・
/// Phase 11Aの`CombatV1ProductionMatchStarter`をそのまま呼び出す上位層
/// （`combat_v1_simulation_runner.dart`）が消費する。
library;

import 'dart:math';

import '../combat_v1_decision_policy.dart';
import '../combat_v1_engine.dart';
import '../combat_v1_production_match_setup.dart';
import '../combat_v1_rules_config.dart';

/// Policyの安定したidと、match毎に導出されたPolicy専用Random
/// （RNG分離、`combat_v1_simulation_seed.dart`参照）を受け取って
/// [CombatV1DecisionPolicy]を生成するfactoryの組（Phase 12A「Policy
/// metadata」）。
///
/// `CombatV1RandomLegalPolicy`のようにconstructorでRandomを要求するPolicyを
/// Config側で単一インスタンスとして保持すると、複数試合で同じRandom
/// instance（＝同じ乱数sequence）を使い回してしまう。[create]をmatch毎に
/// 呼び出すことで、試合ごとに独立したPolicy Randomを注入できるようにする。
///
/// Phase 12Aでは`firstLegal`/`randomLegal`の2種のみを想定する——過剰な
/// Policy frameworkは作らない（heuristic policyはPhase 12B以降）。
class CombatV1SimulationPolicySpec {
  const CombatV1SimulationPolicySpec({required this.id, required this.create});

  /// [CombatV1DecisionPolicy.id]と同じ値（例: `'firstLegal'`/`'randomLegal'`）。
  /// Simulation ResultからどのPolicyで実行したかを構造的に判別するための
  /// 安定したID。
  final String id;

  /// このmatch専用に導出されたPolicy Random（[create]がRandomを使わない
  /// 実装であれば無視してよい、例: `CombatV1FirstLegalPolicy`）を受け取り、
  /// 対応する[CombatV1DecisionPolicy]を生成する。
  final CombatV1DecisionPolicy Function(Random policyRandom) create;

  /// [CombatV1FirstLegalPolicy]用のspec（deterministic、Randomは消費しない）。
  static const CombatV1SimulationPolicySpec firstLegal =
      CombatV1SimulationPolicySpec(id: 'firstLegal', create: _createFirstLegal);

  /// [CombatV1RandomLegalPolicy]用のspec（match毎に導出されたPolicy Random
  /// を注入する）。
  static const CombatV1SimulationPolicySpec randomLegal =
      CombatV1SimulationPolicySpec(id: 'randomLegal', create: _createRandomLegal);

  static CombatV1DecisionPolicy _createFirstLegal(Random policyRandom) =>
      const CombatV1FirstLegalPolicy();

  static CombatV1DecisionPolicy _createRandomLegal(Random policyRandom) =>
      CombatV1RandomLegalPolicy(policyRandom);
}

/// CPU vs CPU simulationの実行設定（Phase 12A）。immutable。
///
/// [CombatV1SimulationRunner]の入力。Randomインスタンス自体は保持しない
/// （[masterSeed]から`combat_v1_simulation_seed.dart`の`deriveV1SimulationSeeds`
/// を介して都度導出する——同じConfigを複数回runしても、Config自身が
/// 消費済みRandom stateを持ち越すことがないようにするため）。
///
/// コンストラクタで以下をfail-fast検証する（[CombatV1IllegalActionException]）:
///
/// - [wrestlerAId]/[wrestlerBId]が`combatV1ProductionWrestlerRegistry`に
///   存在すること（`CombatV1ProductionMatchStarter`と同じレジストリを使い、
///   同じ形で未知wrestlerを拒否する）
/// - [playerAPolicy]/[playerBPolicy]の`id`が空白のみでないこと
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
    if (playerAPolicy.id.trim().isEmpty) {
      throw CombatV1IllegalActionException(
        'playerAPolicy.idを空にすることはできません',
      );
    }
    if (playerBPolicy.id.trim().isEmpty) {
      throw CombatV1IllegalActionException(
        'playerBPolicy.idを空にすることはできません',
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

  final CombatV1SimulationPolicySpec playerAPolicy;
  final CombatV1SimulationPolicySpec playerBPolicy;

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
