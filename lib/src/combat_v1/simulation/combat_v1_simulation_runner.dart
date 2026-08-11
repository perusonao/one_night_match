/// Combat Ver.1 Phase 12A — Simulation Runner
/// （docs/design/combat_v1_phase12a_simulation_core.md）。
///
/// 「同じ設定＋同じseedなら再現可能なCPU vs CPU対戦を、1試合または複数試合
/// 実行し、構造化されたSimulation Resultとして取得する」ための上位層。
/// Phase 11Bの`CombatV1CpuMatchRunner`・Phase 11Aの
/// `CombatV1ProductionMatchStarter`をそのまま呼び出すのみで、CPU対戦ロジック
/// 自体を再実装しない（2章）。
library;

import 'dart:math';

import '../combat_v1_cpu_match_runner.dart';
import '../combat_v1_engine.dart';
import '../combat_v1_production_catalog.dart';
import '../combat_v1_production_match_setup.dart';
import 'combat_v1_match_simulation_result.dart';
import 'combat_v1_simulation_config.dart';
import 'combat_v1_simulation_result.dart';
import 'combat_v1_simulation_seed.dart';

/// [masterSeed]/[matchIndex]/[playerSuffix]（`'a'`または`'b'`）から、
/// Production Match Setupの`playerAOwnerId`/`playerBOwnerId`へ渡す
/// physical instanceId namespaceを決定論的に生成する（Phase 12A「Owner
/// Namespace」8章）。
///
/// wrestlerIdそのものはownerIdとして使わない（同一wrestlerのmirror match
/// でplayerA/Bのcardが衝突する原因になるため）。現在時刻も使わない
/// （再現性を壊すため）。[masterSeed]を含めることで、複数のSimulationを
/// 跨いでもownerIdの意味が明確になるようにする。
String combatV1SimulationOwnerId({
  required int masterSeed,
  required int matchIndex,
  required String playerSuffix,
}) => 'sim-$masterSeed-$matchIndex-$playerSuffix';

/// [CombatV1SimulationConfig]から、bounded・deterministicなCPU vs CPU
/// simulationを実行するrunner（Phase 12A）。
///
/// このクラス自身はCPU対戦ロジック（合法手列挙・意思決定・Engine Command
/// 実行）を一切持たない。責務は以下のみ:
///
/// 1. [CombatV1SimulationConfig]・`matchIndex`から[deriveV1SimulationSeeds]
///    で試合固有のRNG seed群を導出する
/// 2. 同じ`config`・`matchIndex`から[deriveV1SimulationMatchId]で
///    canonical simulation identity（`maxActions`/`rules`を含む、RNG
///    seedとは独立した計算）を導出する
/// 3. [combatV1SimulationOwnerId]でowner namespaceを決定する
/// 4. `CombatV1ProductionMatchStarter.start`で試合を開始する
/// 5. `CombatV1CpuMatchRunner.run`で試合を進行させる
/// 6. 結果を[CombatV1MatchSimulationResult]/[CombatV1SimulationResult]へ
///    詰め替える
class CombatV1SimulationRunner {
  const CombatV1SimulationRunner();

  /// [config]に従って[CombatV1SimulationConfig.matchCount]試合を
  /// `matchIndex` 0始まりで順に実行する。
  CombatV1SimulationResult run(CombatV1SimulationConfig config) {
    final matches = <CombatV1MatchSimulationResult>[
      for (var matchIndex = 0; matchIndex < config.matchCount; matchIndex++)
        runSingleMatch(config, matchIndex),
    ];

    return CombatV1SimulationResult(
      config: config,
      matches: matches,
      requestedMatchCount: config.matchCount,
      executedMatchCount: matches.length,
    );
  }

  /// [config]の[matchIndex]番目の試合を1つ実行する。
  ///
  /// [CombatV1SimulationResult.matches]の各要素はこのメソッドの戻り値と
  /// 同一の経路で生成される——[run]から複数回呼ばれる場合も、単独で
  /// replay目的に呼ばれる場合も、同じ[config]・[matchIndex]なら常に同じ
  /// seed群・同じownerId・同じ結果になる（determinism契約、11章）。
  ///
  /// RNG分離（7章）: Engine Random（試合開始time deckシャッフルから
  /// `CombatV1CpuMatchRunner`のengineRandomまで、1試合を通して同一
  /// instance）・playerA Policy Random・playerB Policy Randomの3本を、
  /// それぞれ独立したseedから生成した独立な`Random`instanceとして注入する。
  CombatV1MatchSimulationResult runSingleMatch(
    CombatV1SimulationConfig config,
    int matchIndex,
  ) {
    if (matchIndex < 0) {
      throw CombatV1IllegalActionException(
        'matchIndexは0以上である必要があります: $matchIndex',
      );
    }

    final seeds = deriveV1SimulationSeeds(
      masterSeed: config.masterSeed,
      matchIndex: matchIndex,
      wrestlerAId: config.wrestlerAId,
      wrestlerBId: config.wrestlerBId,
      playerAPolicyId: config.playerAPolicy.policyId,
      playerBPolicyId: config.playerBPolicy.policyId,
    );

    // simulationMatchIdはRNG seed derivation（seeds）とは独立して算出する
    // ——maxActions/rulesはRandom sequenceを決定しないが、試合結果には
    // 実際に影響するため、canonical simulation identityへは反映する
    // 必要がある（Codex review M3対応）。
    final simulationMatchId = deriveV1SimulationMatchId(
      masterSeed: config.masterSeed,
      matchIndex: matchIndex,
      wrestlerAId: config.wrestlerAId,
      wrestlerBId: config.wrestlerBId,
      playerAPolicyId: config.playerAPolicy.policyId,
      playerBPolicyId: config.playerBPolicy.policyId,
      maxActions: config.maxActions,
      rules: config.rules,
    );

    // playerAOwnerId/playerBOwnerIdは1度だけ計算し、starterへ渡す値と
    // Resultへ記録する値を同じ変数から取る——Result用に別途再計算しない
    // ことで、両者の一致を構造的に保証する（Codex review M2対応）。
    final playerAOwnerId = combatV1SimulationOwnerId(
      masterSeed: config.masterSeed,
      matchIndex: matchIndex,
      playerSuffix: 'a',
    );
    final playerBOwnerId = combatV1SimulationOwnerId(
      masterSeed: config.masterSeed,
      matchIndex: matchIndex,
      playerSuffix: 'b',
    );

    // Engine Randomは試合開始（deckシャッフル・初期手札配布）からrunnerの
    // Engine Command実行まで、1本のRandom instanceを継続して使う——「Engine
    // Random」を試合全体で単一のRNG streamとして扱う（7章）。
    final engineRandom = Random(seeds.engineSeed);
    final playerAPolicyRandom = Random(seeds.playerAPolicySeed);
    final playerBPolicyRandom = Random(seeds.playerBPolicySeed);

    final initialState = CombatV1ProductionMatchStarter.start(
      CombatV1ProductionMatchConfig(
        wrestlerAId: config.wrestlerAId,
        wrestlerBId: config.wrestlerBId,
        playerAOwnerId: playerAOwnerId,
        playerBOwnerId: playerBOwnerId,
        rules: config.rules,
      ),
      random: engineRandom,
    );

    final policyA = config.playerAPolicy.createFresh(playerAPolicyRandom);
    final policyB = config.playerBPolicy.createFresh(playerBPolicyRandom);

    final runner = CombatV1CpuMatchRunner(
      catalog: productionCardCatalog,
      rules: config.rules,
      maxActions: config.maxActions,
    );

    final cpuResult = runner.run(
      initialState,
      policyA: policyA,
      policyB: policyB,
      engineRandom: engineRandom,
    );

    return CombatV1MatchSimulationResult.fromCpuResult(
      matchIndex: matchIndex,
      simulationMatchId: simulationMatchId,
      wrestlerAId: config.wrestlerAId,
      wrestlerBId: config.wrestlerBId,
      playerAOwnerId: playerAOwnerId,
      playerBOwnerId: playerBOwnerId,
      rules: config.rules,
      seeds: seeds,
      cpuResult: cpuResult,
    );
  }
}
