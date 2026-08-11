/// Combat Ver.1 Playable 1A — Match Config
/// （docs/design/combat_v1_playable_match_ui.md）。
///
/// Human（Player A / index 0）vs CPU（Player B / index 1）の1試合を
/// `CombatV1PlayableMatchController`で進行させるための入力パラメータ。
/// `CombatV1ProductionMatchStarter`（Phase 11A）をそのまま呼び出す
/// 上位層が消費する——`CombatV1SimulationConfig`（Phase 12A）へは依存
/// させない（Simulation packageへの依存方向を持ち込まないため、
/// docs/design/combat_v1_playable_match_ui.md 12章）。
library;

import 'dart:math';

import '../combat_v1_decision_policy.dart';
import '../combat_v1_engine.dart';
import '../combat_v1_production_match_setup.dart';
import '../combat_v1_rules_config.dart';

/// Playableで利用可能なCPU Policyを、Phase 11Bの2種類のbuilt-in policyへ
/// 閉じたenum（`CombatV1SimulationPolicyKind`、Phase 12Aと同じ設計思想）。
///
/// [CombatV1PlayableMatchConfig.cpuPolicyKind]の型として使う。enumで
/// あるため、任意のfactory closureをpublic API経由で注入することは構造上
/// 不可能——scripted/custom policyが必要なtestはtest code側で直接
/// `CombatV1DecisionPolicy`を実装する（public configへ再導入しない）。
enum CombatV1PlayableCpuPolicyKind {
  /// [CombatV1FirstLegalPolicy]（deterministic baseline、Randomは消費
  /// しない）。testでの決定論的検証向け。
  firstLegal,

  /// [CombatV1RandomLegalPolicy]（type-first random policy）。Playable
  /// productionの既定値。
  randomLegal;

  /// このkindに対応する[policyRandom]から、新規[CombatV1DecisionPolicy]
  /// instanceを生成する。呼び出すたびに必ず新しいinstanceを返す。
  CombatV1DecisionPolicy createFresh(Random policyRandom) => switch (this) {
    CombatV1PlayableCpuPolicyKind.firstLegal => const CombatV1FirstLegalPolicy(),
    CombatV1PlayableCpuPolicyKind.randomLegal =>
      CombatV1RandomLegalPolicy(policyRandom),
  };
}

/// [engineSeed]・[playerSuffix]（例: `'human'`/`'cpu'`）から、
/// `CombatV1ProductionMatchConfig.playerAOwnerId`/`playerBOwnerId`へ渡す
/// physical instanceId namespaceを決定論的に生成する
/// （docs/design/combat_v1_playable_match_ui.md 10章、Phase 12Aの
/// `combatV1SimulationOwnerId`と同じ設計思想を、Playable専用に独立して
/// 実装したもの）。
///
/// wrestlerIdそのものはownerIdとして使わない（mirror matchでHuman/CPUの
/// cardが衝突する原因になるため）。現在時刻も使わない（再現性を壊すため）。
String combatV1PlayableOwnerId({
  required int engineSeed,
  required String playerSuffix,
}) => 'playable-$engineSeed-$playerSuffix';

/// Playable 1A Match開始設定（docs/design/combat_v1_playable_match_ui.md
/// 4章）。immutable。
///
/// [humanWrestlerId]がplayerA（index 0）、[cpuWrestlerId]がplayerB
/// （index 1）——Playable 1Aでは固定（UI wrestler selectorは今回不要）。
/// 同じwrestlerId同士（mirror match）も禁止しない。
///
/// コンストラクタで以下をfail-fast検証する
/// （[CombatV1IllegalActionException]、`CombatV1SimulationConfig`と同じ
/// 方針）:
///
/// - [humanWrestlerId]/[cpuWrestlerId]が`combatV1ProductionWrestlerRegistry`
///   に存在すること
/// - [maxActions] > 0
class CombatV1PlayableMatchConfig {
  CombatV1PlayableMatchConfig({
    required this.humanWrestlerId,
    required this.cpuWrestlerId,
    required this.engineSeed,
    required this.cpuPolicySeed,
    this.maxActions = 500,
    this.rules = const CombatV1RulesConfig(),
    this.cpuPolicyKind = CombatV1PlayableCpuPolicyKind.randomLegal,
  }) {
    if (!combatV1ProductionWrestlerRegistry.containsKey(humanWrestlerId)) {
      throw CombatV1IllegalActionException(
        '未知のProduction wrestlerIdです（humanWrestlerId）: $humanWrestlerId',
      );
    }
    if (!combatV1ProductionWrestlerRegistry.containsKey(cpuWrestlerId)) {
      throw CombatV1IllegalActionException(
        '未知のProduction wrestlerIdです（cpuWrestlerId）: $cpuWrestlerId',
      );
    }
    if (maxActions <= 0) {
      throw CombatV1IllegalActionException(
        'maxActionsは1以上である必要があります: $maxActions',
      );
    }
  }

  /// `combatV1ProductionWrestlerRegistry`のキー。Human（playerA / index 0）
  /// が使用するwrestler。
  final String humanWrestlerId;

  /// CPU（playerB / index 1）が使用するwrestler。[humanWrestlerId]と同じ
  /// 値（mirror match）も許容する。
  final String cpuWrestlerId;

  /// `CombatV1Engine` Command（shuffle/draw/PIN/COUNTER解決）専用の
  /// Random seed。試合を通じて単一の`Random`instanceとして使い回す
  /// （docs/design/combat_v1_playable_match_ui.md 10章）。
  final int engineSeed;

  /// CPU decision policy専用のRandom seed。[engineSeed]とは常に独立した
  /// `Random`instanceを構築するために使う（11章）。
  final int cpuPolicySeed;

  /// controller safety guard（既定500、ゲームルールのturn limitではない）。
  final int maxActions;

  final CombatV1RulesConfig rules;

  /// CPU decision policyの種類（既定`randomLegal`、12章）。
  final CombatV1PlayableCpuPolicyKind cpuPolicyKind;
}
