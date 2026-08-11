// Combat Ver.1 Phase 12A: seed / simulation identity derivation — golden
// vector test（lib/src/combat_v1/simulation/combat_v1_simulation_seed.dart）。
//
// deriveV1SimulationSeeds / deriveV1SimulationMatchIdの既知入力→既知出力
// を、実装からその場で計算するのではなく固定literalとしてpinする。将来
// アルゴリズムが意図せず変化した場合、この既存golden testがfailすることで
// 検出できるようにする（Codex review「Golden Seed Tests」対応）。
//
// このファイルは2つのgroupへ分かれる（Codex review Blocking Finding M3
// 「RNG derivationとsimulation identity derivationを分離する」対応）:
//
// - 「A. RNG seed golden vectors」: [deriveV1SimulationSeeds]のgolden値。
//   M3修正でsimulation identityの算出方式を全面的に変更したが、この
//   groupのmatchSeed/engineSeed/playerAPolicySeed/playerBPolicySeedの
//   golden literalは1つも変更していない——[deriveV1SimulationMatchId]
//   が[deriveV1SimulationSeeds]から完全に独立したpure functionに
//   なったため（旧実装は`matchSeed`から`'matchId'` laneを派生させて
//   いたが、これを廃止した）。
// - 「B. simulationMatchId golden vectors」: [deriveV1SimulationMatchId]
//   のgolden値。M3で`maxActions`/`CombatV1RulesConfig`を識別子へ追加
//   したため、simulationMatchIdの算出方式自体が変わり、golden値も
//   全面的に更新されている（旧PR時点のgolden値とは異なる——Codex review
//   が明示的に許容した変更）。
//
// golden値は本テスト更新時に、Dart VM（`dart run`）と dart2js
// （`dart compile js` + Node.jsで実行）の両方で実際に算出し、bit単位で
// 一致することを確認済み。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_seed.dart';

const CombatV1RulesConfig _defaultRules = CombatV1RulesConfig();

void main() {
  group('A. RNG seed golden vectors（deriveV1SimulationSeeds、version 1）', () {
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

  group('B. simulationMatchId golden vectors（deriveV1SimulationMatchId、'
      'Codex review M3対応）', () {
    test('normal positive masterSeed（maxActions=500、既定rules）', () {
      final id = deriveV1SimulationMatchId(
        masterSeed: 42,
        matchIndex: 0,
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
        playerAPolicyId: 'firstLegal',
        playerBPolicyId: 'randomLegal',
        maxActions: 500,
        rules: _defaultRules,
      );
      expect(id, 'sim-v1-42-0-7441be9f');
    });

    test('masterSeed = 0', () {
      final id = deriveV1SimulationMatchId(
        masterSeed: 0,
        matchIndex: 0,
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
        playerAPolicyId: 'firstLegal',
        playerBPolicyId: 'randomLegal',
        maxActions: 500,
        rules: _defaultRules,
      );
      expect(id, 'sim-v1-0-0-c9222a21');
    });

    test('negative masterSeed', () {
      final id = deriveV1SimulationMatchId(
        masterSeed: -42,
        matchIndex: 0,
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
        playerAPolicyId: 'firstLegal',
        playerBPolicyId: 'randomLegal',
        maxActions: 500,
        rules: _defaultRules,
      );
      expect(id, 'sim-v1--42-0-b03f517a');
    });

    test('mirror wrestler matchup', () {
      final id = deriveV1SimulationMatchId(
        masterSeed: 42,
        matchIndex: 0,
        wrestlerAId: 'misaki',
        wrestlerBId: 'misaki',
        playerAPolicyId: 'firstLegal',
        playerBPolicyId: 'firstLegal',
        maxActions: 500,
        rules: _defaultRules,
      );
      expect(id, 'sim-v1-42-0-1d4173c7');
    });

    test('wrestlerA/Bが異なるケース（akari vs reina）', () {
      final id = deriveV1SimulationMatchId(
        masterSeed: 42,
        matchIndex: 0,
        wrestlerAId: 'akari',
        wrestlerBId: 'reina',
        playerAPolicyId: 'randomLegal',
        playerBPolicyId: 'randomLegal',
        maxActions: 500,
        rules: _defaultRules,
      );
      expect(id, 'sim-v1-42-0-39fa9b48');
    });

    test('policy identity差: playerAPolicyIdだけが異なると別IDになる', () {
      final firstLegalId = deriveV1SimulationMatchId(
        masterSeed: 42,
        matchIndex: 0,
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
        playerAPolicyId: 'firstLegal',
        playerBPolicyId: 'firstLegal',
        maxActions: 500,
        rules: _defaultRules,
      );
      final randomLegalId = deriveV1SimulationMatchId(
        masterSeed: 42,
        matchIndex: 0,
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
        playerAPolicyId: 'randomLegal',
        playerBPolicyId: 'firstLegal',
        maxActions: 500,
        rules: _defaultRules,
      );

      expect(firstLegalId, 'sim-v1-42-0-8a780ef7');
      expect(randomLegalId, 'sim-v1-42-0-384a6d9a');
      expect(firstLegalId, isNot(randomLegalId));
    });

    test('matchIndex差: matchIndex 0/1で別IDになる', () {
      final index0Id = deriveV1SimulationMatchId(
        masterSeed: 42,
        matchIndex: 0,
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
        playerAPolicyId: 'firstLegal',
        playerBPolicyId: 'randomLegal',
        maxActions: 500,
        rules: _defaultRules,
      );
      final index1Id = deriveV1SimulationMatchId(
        masterSeed: 42,
        matchIndex: 1,
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
        playerAPolicyId: 'firstLegal',
        playerBPolicyId: 'randomLegal',
        maxActions: 500,
        rules: _defaultRules,
      );

      expect(index0Id, 'sim-v1-42-0-7441be9f');
      expect(index1Id, 'sim-v1-42-1-7d7237c5');
      expect(index0Id, isNot(index1Id));
    });
  });
}
