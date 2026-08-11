// Combat Ver.1 Phase 12A: seed derivation version 1 — golden vector test
// （lib/src/combat_v1/simulation/combat_v1_simulation_seed.dart）。
//
// deriveV1SimulationSeedsの既知入力→既知出力を、実装からその場で計算する
// のではなく固定literalとしてpinする。将来seed derivation version 1の
// アルゴリズムが意図せず変化した場合、この既存golden testがfailすることで
// 検出できるようにする（Codex review「Golden Seed Tests」対応）。
//
// golden値は本テスト追加時に、Dart VM（`dart run`）と dart2js
// （`dart compile js` + Node.jsで実行）の両方で実際に算出し、bit単位で
// 一致することを確認済み——`_fnv1a32`/`_mix32`の乗算を、32-bit×32-bitの
// 素朴な乗算ではなく16-bit分割の安全乗算（`_mul32`）へ変更したことで
// 実現した（Codex review指摘前は、32-bit×32-bit乗算の中間結果が
// JavaScriptのdouble精度（53-bit）を超え、dart2js実行時にVMと異なる
// 結果になっていた）。
//
// このファイルは7個の`test()`を持つ（一部のtestは1回の`test()`内で
// `deriveV1SimulationSeeds`を複数回呼び出して比較するため、derivation
// シナリオの総数は7より多い——「golden test数」と「derivation
// シナリオ数」は別概念）。
//
// Codex review M2対応でCombatV1SimulationSeedSetへ`simulationMatchId`
// （Simulator独自のdeterministic match identity）を追加した際も、
// 既存の`matchSeed`/`engineSeed`/`playerAPolicySeed`/`playerBPolicySeed`
// golden値は一切変更していない——`simulationMatchId`は`matchSeed`から
// 独立した新しいlane（`'matchId'`）を追加しただけであり、既存laneの
// 導出には影響しないため（`combat_v1_simulation_seed.dart`参照）。
// `simulationMatchId`のgolden値もVM/dart2js双方で算出し一致を確認済み。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_seed.dart';

void main() {
  group('golden vectors（version 1、固定literal）', () {
    test('normal positive masterSeed', () {
      final seeds = deriveV1SimulationSeeds(
        masterSeed: 42,
        matchIndex: 0,
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
        playerAPolicyId: 'firstLegal',
        playerBPolicyId: 'randomLegal',
      );

      expect(seeds.matchSeed, 345040212);
      expect(seeds.engineSeed, 2713258433);
      expect(seeds.playerAPolicySeed, 2123471078);
      expect(seeds.playerBPolicySeed, 1074261339);
      expect(seeds.derivationVersion, 1);
      expect(seeds.simulationMatchId, 'sim-v1-42-0-8a17b86a');
    });

    test('masterSeed = 0', () {
      final seeds = deriveV1SimulationSeeds(
        masterSeed: 0,
        matchIndex: 0,
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
        playerAPolicyId: 'firstLegal',
        playerBPolicyId: 'randomLegal',
      );

      expect(seeds.matchSeed, 2984682244);
      expect(seeds.engineSeed, 750850432);
      expect(seeds.playerAPolicySeed, 800294435);
      expect(seeds.playerBPolicySeed, 2306995920);
      expect(seeds.derivationVersion, 1);
      expect(seeds.simulationMatchId, 'sim-v1-0-0-ed31878c');
    });

    test('negative masterSeed', () {
      final seeds = deriveV1SimulationSeeds(
        masterSeed: -42,
        matchIndex: 0,
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
        playerAPolicyId: 'firstLegal',
        playerBPolicyId: 'randomLegal',
      );

      expect(seeds.matchSeed, 3217244944);
      expect(seeds.engineSeed, 3502328591);
      expect(seeds.playerAPolicySeed, 1099503209);
      expect(seeds.playerBPolicySeed, 2386984010);
      expect(seeds.derivationVersion, 1);
      expect(seeds.simulationMatchId, 'sim-v1--42-0-cabbf1fe');
    });

    test('mirror wrestler matchup（wrestlerA == wrestlerB、policyA == policyB）', () {
      final seeds = deriveV1SimulationSeeds(
        masterSeed: 42,
        matchIndex: 0,
        wrestlerAId: 'misaki',
        wrestlerBId: 'misaki',
        playerAPolicyId: 'firstLegal',
        playerBPolicyId: 'firstLegal',
      );

      expect(seeds.matchSeed, 1949367299);
      expect(seeds.engineSeed, 2012685435);
      expect(seeds.playerAPolicySeed, 2615525560);
      expect(seeds.playerBPolicySeed, 1862135148);
      expect(seeds.derivationVersion, 1);
      expect(seeds.simulationMatchId, 'sim-v1-42-0-11158bcb');
    });

    test('wrestlerA/Bが異なるケース（akari vs reina、両者randomLegal）', () {
      final seeds = deriveV1SimulationSeeds(
        masterSeed: 42,
        matchIndex: 0,
        wrestlerAId: 'akari',
        wrestlerBId: 'reina',
        playerAPolicyId: 'randomLegal',
        playerBPolicyId: 'randomLegal',
      );

      expect(seeds.matchSeed, 3508630494);
      expect(seeds.engineSeed, 4152295943);
      expect(seeds.playerAPolicySeed, 1095915854);
      expect(seeds.playerBPolicySeed, 932260771);
      expect(seeds.derivationVersion, 1);
      expect(seeds.simulationMatchId, 'sim-v1-42-0-008b5a7c');
    });

    test('policy identity差: playerAPolicyIdだけがfirstLegal/randomLegalで'
        '異なるとmatchSeedが変わる（両方をgolden値として固定）', () {
      final firstLegalSeeds = deriveV1SimulationSeeds(
        masterSeed: 42,
        matchIndex: 0,
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
        playerAPolicyId: 'firstLegal',
        playerBPolicyId: 'firstLegal',
      );
      final randomLegalSeeds = deriveV1SimulationSeeds(
        masterSeed: 42,
        matchIndex: 0,
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
        playerAPolicyId: 'randomLegal',
        playerBPolicyId: 'firstLegal',
      );

      expect(firstLegalSeeds.matchSeed, 929616156);
      expect(firstLegalSeeds.engineSeed, 3218238242);
      expect(firstLegalSeeds.playerAPolicySeed, 2357484454);
      expect(firstLegalSeeds.playerBPolicySeed, 4008073396);
      expect(firstLegalSeeds.simulationMatchId, 'sim-v1-42-0-149f88b1');

      expect(randomLegalSeeds.matchSeed, 2055530322);
      expect(randomLegalSeeds.engineSeed, 2949872999);
      expect(randomLegalSeeds.playerAPolicySeed, 3367343140);
      expect(randomLegalSeeds.playerBPolicySeed, 2388187724);
      expect(randomLegalSeeds.simulationMatchId, 'sim-v1-42-0-c5ad94d5');

      expect(firstLegalSeeds.matchSeed, isNot(randomLegalSeeds.matchSeed));
      expect(
        firstLegalSeeds.simulationMatchId,
        isNot(randomLegalSeeds.simulationMatchId),
      );
    });

    test('matchIndex差: matchIndex 0/1でmatchSeedが変わる（両方をgolden値として'
        '固定、Engine/policyA/policyB domain separationも同時に確認）', () {
      final index0 = deriveV1SimulationSeeds(
        masterSeed: 42,
        matchIndex: 0,
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
        playerAPolicyId: 'firstLegal',
        playerBPolicyId: 'randomLegal',
      );
      final index1 = deriveV1SimulationSeeds(
        masterSeed: 42,
        matchIndex: 1,
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
        playerAPolicyId: 'firstLegal',
        playerBPolicyId: 'randomLegal',
      );

      expect(index0.matchSeed, 345040212);
      expect(index0.engineSeed, 2713258433);
      expect(index0.playerAPolicySeed, 2123471078);
      expect(index0.playerBPolicySeed, 1074261339);
      expect(index0.simulationMatchId, 'sim-v1-42-0-8a17b86a');

      expect(index1.matchSeed, 1429601233);
      expect(index1.engineSeed, 2031354303);
      expect(index1.playerAPolicySeed, 2682025283);
      expect(index1.playerBPolicySeed, 1290699076);
      expect(index1.simulationMatchId, 'sim-v1-42-1-94e4960c');

      expect(index0.matchSeed, isNot(index1.matchSeed));
      expect(index0.simulationMatchId, isNot(index1.simulationMatchId));

      // Engine / policyA / policyB domain separation:
      // 同一matchSeedから導出された3本のseedは、固定literal同士としても
      // 互いに異なる。
      expect(index0.engineSeed, isNot(index0.playerAPolicySeed));
      expect(index0.engineSeed, isNot(index0.playerBPolicySeed));
      expect(index0.playerAPolicySeed, isNot(index0.playerBPolicySeed));
    });
  });
}
