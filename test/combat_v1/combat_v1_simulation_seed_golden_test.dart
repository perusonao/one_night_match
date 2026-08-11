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

      expect(randomLegalSeeds.matchSeed, 2055530322);
      expect(randomLegalSeeds.engineSeed, 2949872999);
      expect(randomLegalSeeds.playerAPolicySeed, 3367343140);
      expect(randomLegalSeeds.playerBPolicySeed, 2388187724);

      expect(firstLegalSeeds.matchSeed, isNot(randomLegalSeeds.matchSeed));
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

      expect(index1.matchSeed, 1429601233);
      expect(index1.engineSeed, 2031354303);
      expect(index1.playerAPolicySeed, 2682025283);
      expect(index1.playerBPolicySeed, 1290699076);

      expect(index0.matchSeed, isNot(index1.matchSeed));

      // Engine / policyA / policyB domain separation:
      // 同一matchSeedから導出された3本のseedは、固定literal同士としても
      // 互いに異なる。
      expect(index0.engineSeed, isNot(index0.playerAPolicySeed));
      expect(index0.engineSeed, isNot(index0.playerBPolicySeed));
      expect(index0.playerAPolicySeed, isNot(index0.playerBPolicySeed));
    });
  });
}
