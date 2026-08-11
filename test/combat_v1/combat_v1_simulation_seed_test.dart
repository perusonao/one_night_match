// Combat Ver.1 Phase 12A: Simulation seed derivation
// （lib/src/combat_v1/simulation/combat_v1_simulation_seed.dart）のtest。
//
// deterministic・versioned・pure functionであること、masterSeed/matchIndex/
// wrestler/policyの各要素がmatchSeedへ正しく反映されること、
// engine/A/B policy seedが分離していることを検証する。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_seed.dart';

CombatV1SimulationSeedSet _seeds({
  int masterSeed = 12345,
  int matchIndex = 0,
  String wrestlerAId = 'misaki',
  String wrestlerBId = 'jack',
  String playerAPolicyId = 'firstLegal',
  String playerBPolicyId = 'randomLegal',
}) => deriveV1SimulationSeeds(
  masterSeed: masterSeed,
  matchIndex: matchIndex,
  wrestlerAId: wrestlerAId,
  wrestlerBId: wrestlerBId,
  playerAPolicyId: playerAPolicyId,
  playerBPolicyId: playerBPolicyId,
);

String _id({
  int masterSeed = 12345,
  int matchIndex = 0,
  String wrestlerAId = 'misaki',
  String wrestlerBId = 'jack',
  String playerAPolicyId = 'firstLegal',
  String playerBPolicyId = 'randomLegal',
  int maxActions = 500,
  CombatV1RulesConfig rules = const CombatV1RulesConfig(),
}) => deriveV1SimulationMatchId(
  masterSeed: masterSeed,
  matchIndex: matchIndex,
  wrestlerAId: wrestlerAId,
  wrestlerBId: wrestlerBId,
  playerAPolicyId: playerAPolicyId,
  playerBPolicyId: playerBPolicyId,
  maxActions: maxActions,
  rules: rules,
);

void main() {
  group('A. 同じ入力→同じseed（pure function）', () {
    test('同じ引数を複数回呼んでも全fieldが一致する', () {
      final a = _seeds();
      final b = _seeds();

      expect(a.matchSeed, b.matchSeed);
      expect(a.engineSeed, b.engineSeed);
      expect(a.playerAPolicySeed, b.playerAPolicySeed);
      expect(a.playerBPolicySeed, b.playerBPolicySeed);
      expect(a.derivationVersion, b.derivationVersion);
    });
  });

  group('B. matchIndex違い→matchSeed違い', () {
    test('matchIndexだけを変えるとmatchSeedが変わる', () {
      final a = _seeds(matchIndex: 0);
      final b = _seeds(matchIndex: 1);

      expect(a.matchSeed, isNot(b.matchSeed));
    });

    test('matchIndexが安定していれば同じmatchSeedへ戻る', () {
      final a = _seeds(matchIndex: 5);
      final b = _seeds(matchIndex: 5);

      expect(a.matchSeed, b.matchSeed);
    });
  });

  group('C. engine/A/B seedが分離', () {
    test('同一matchSeedから導出される3本のseedは互いに異なる', () {
      final seeds = _seeds();

      expect(seeds.engineSeed, isNot(seeds.playerAPolicySeed));
      expect(seeds.engineSeed, isNot(seeds.playerBPolicySeed));
      expect(seeds.playerAPolicySeed, isNot(seeds.playerBPolicySeed));
    });
  });

  group('D. wrestler違い→matchSeed違い', () {
    test('wrestlerAIdが違えばmatchSeedが変わる', () {
      final a = _seeds(wrestlerAId: 'misaki');
      final b = _seeds(wrestlerAId: 'akari');

      expect(a.matchSeed, isNot(b.matchSeed));
    });

    test('wrestlerBIdが違えばmatchSeedが変わる', () {
      final a = _seeds(wrestlerBId: 'jack');
      final b = _seeds(wrestlerBId: 'reina');

      expect(a.matchSeed, isNot(b.matchSeed));
    });
  });

  group('E. policy違い→matchSeed違い', () {
    test('playerAPolicyIdが違えばmatchSeedが変わる', () {
      final a = _seeds(playerAPolicyId: 'firstLegal');
      final b = _seeds(playerAPolicyId: 'randomLegal');

      expect(a.matchSeed, isNot(b.matchSeed));
    });

    test('playerBPolicyIdが違えばmatchSeedが変わる', () {
      final a = _seeds(playerBPolicyId: 'firstLegal');
      final b = _seeds(playerBPolicyId: 'randomLegal');

      expect(a.matchSeed, isNot(b.matchSeed));
    });
  });

  group('F. masterSeed違い→matchSeed違い', () {
    test('masterSeedが違えばmatchSeedが変わる', () {
      final a = _seeds(masterSeed: 1);
      final b = _seeds(masterSeed: 2);

      expect(a.matchSeed, isNot(b.matchSeed));
    });
  });

  group('G. derivation versionが固定', () {
    test('derivationVersionは公開定数combatV1SeedDerivationVersionと一致する', () {
      final seeds = _seeds();
      expect(seeds.derivationVersion, combatV1SeedDerivationVersion);
      expect(combatV1SeedDerivationVersion, isPositive);
    });
  });

  group('H. matchIndex/masterSeedがresultへ複製される', () {
    test('引数と同じ値がそのままCombatV1SimulationSeedSetへ入る', () {
      final seeds = _seeds(masterSeed: 999, matchIndex: 7);
      expect(seeds.masterSeed, 999);
      expect(seeds.matchIndex, 7);
    });
  });

  group('I. simulationMatchId identity（Codex review Blocking Finding M3対応）', () {
    test('Test A: maxActionsのみ変更するとRNG seed群は不変で'
        'simulationMatchIdは異なる', () {
      // deriveV1SimulationSeedsはmaxActionsを引数に取らない——同一config
      // identity（masterSeed/matchIndex/wrestlerA・B/policyA・B）に対する
      // RNG seed群は、maxActionsの値に関わらず1通りしか存在しない
      // （型シグネチャ自体がこれを構造的に保証する）。
      final seeds = _seeds();
      expect(seeds.matchSeed, isNotNull);

      final idMaxActions500 = _id(maxActions: 500);
      final idMaxActions1 = _id(maxActions: 1);

      expect(idMaxActions500, isNot(idMaxActions1));
    });

    test('Test B: rulesのoutcome-affecting fieldを変更するとRNG seed群は'
        '不変でsimulationMatchIdは異なる', () {
      final seeds = _seeds();
      expect(seeds.matchSeed, isNotNull);

      const alteredRules = CombatV1RulesConfig(startingHp: 200);
      final idDefaultRules = _id();
      final idAlteredRules = _id(rules: alteredRules);

      expect(idDefaultRules, isNot(idAlteredRules));
    });

    test('Test C: CombatV1RulesConfigの各outcome-affecting fieldについて、'
        'そのfieldだけを変えるとsimulationMatchIdが変わる（table-driven、'
        'deckCompositionの4 subfieldを個別caseとして含む全22 case網羅、'
        'Codex review Minor Finding「deckComposition test granularity」'
        '対応）', () {
      // deriveV1SimulationSeedsはrulesを引数に取らない——このtable内の
      // どのcaseでもRNG seed群（matchSeed/engineSeed/playerAPolicySeed/
      // playerBPolicySeed）は不変であることが型シグネチャ自体で構造的に
      // 保証される（Test A/Bと同じ根拠）。
      final seeds = _seeds();
      expect(seeds.matchSeed, isNotNull);

      final baseId = _id();

      // deckCompositionは既定値（CombatV1DeckComposition()のdefault:
      // normal18/signature4/finisher2/counter6、combat_v1_deck.dart参照）
      // から、4 subfieldのうち1つだけを変更する——「deckComposition全体を
      // まとめて変更する1 case」ではなく、各subfieldが個別に
      // simulationMatchIdへ反映されることを直接確認する（Codex review
      // Minor Finding対応。実装（`_rulesIdentityComponents`）は既に
      // 4 subfieldを個別のtag/value pairとして列挙しているため、この
      // testはregression guardの強化——実装変更は不要）。
      const defaultNormalCount = 18;
      const defaultSignatureCount = 4;
      const defaultFinisherCount = 2;
      const defaultCounterCount = 6;
      final variants = <String, CombatV1RulesConfig>{
        'startingHp': const CombatV1RulesConfig(startingHp: 999),
        'startingKoc': const CombatV1RulesConfig(startingKoc: 99),
        'startingPinCards': const CombatV1RulesConfig(startingPinCards: 9),
        'startingHandSize': const CombatV1RulesConfig(startingHandSize: 9),
        'deckComposition.normalCount': const CombatV1RulesConfig(
          deckComposition: CombatV1DeckComposition(
            normalCount: 19,
            signatureCount: defaultSignatureCount,
            finisherCount: defaultFinisherCount,
            counterCount: defaultCounterCount,
          ),
        ),
        'deckComposition.signatureCount': const CombatV1RulesConfig(
          deckComposition: CombatV1DeckComposition(
            normalCount: defaultNormalCount,
            signatureCount: 5,
            finisherCount: defaultFinisherCount,
            counterCount: defaultCounterCount,
          ),
        ),
        'deckComposition.finisherCount': const CombatV1RulesConfig(
          deckComposition: CombatV1DeckComposition(
            normalCount: defaultNormalCount,
            signatureCount: defaultSignatureCount,
            finisherCount: 3,
            counterCount: defaultCounterCount,
          ),
        ),
        'deckComposition.counterCount': const CombatV1RulesConfig(
          deckComposition: CombatV1DeckComposition(
            normalCount: defaultNormalCount,
            signatureCount: defaultSignatureCount,
            finisherCount: defaultFinisherCount,
            counterCount: 7,
          ),
        ),
        'normalSameNameLimit': const CombatV1RulesConfig(
          normalSameNameLimit: 9,
        ),
        'signatureSameNameLimit': const CombatV1RulesConfig(
          signatureSameNameLimit: 9,
        ),
        'finisherSameNameLimit': const CombatV1RulesConfig(
          finisherSameNameLimit: 9,
        ),
        'counterSameNameLimit': const CombatV1RulesConfig(
          counterSameNameLimit: 9,
        ),
        'counterAllowsWildSubstitution': const CombatV1RulesConfig(
          counterAllowsWildSubstitution: true,
        ),
        'totalPinCards': const CombatV1RulesConfig(totalPinCards: 9),
        'pinCountOneKocCost': const CombatV1RulesConfig(
          pinCountOneKocCost: 9,
        ),
        'pinCountTwoKocCost': const CombatV1RulesConfig(
          pinCountTwoKocCost: 9,
        ),
        'pinCountTwoPointNineKocCost': const CombatV1RulesConfig(
          pinCountTwoPointNineKocCost: 9,
        ),
        'submissionHpThreshold': const CombatV1RulesConfig(
          submissionHpThreshold: 9,
        ),
        'submissionEscapeKocCost': const CombatV1RulesConfig(
          submissionEscapeKocCost: 9,
        ),
        'restHpRecovery': const CombatV1RulesConfig(restHpRecovery: 9),
        'roughRestrictedTechniqueLimit': const CombatV1RulesConfig(
          roughRestrictedTechniqueLimit: 9,
        ),
        'finisherHeatThreshold': const CombatV1RulesConfig(
          finisherHeatThreshold: 9,
        ),
      };

      for (final entry in variants.entries) {
        final variantId = _id(rules: entry.value);
        expect(
          variantId,
          isNot(baseId),
          reason:
              'field=${entry.key}: この1 fieldだけを変えても'
              'simulationMatchIdが変化しませんでした'
              '（identityへの反映漏れの可能性があります）',
        );
      }
    });

    test('Test D: 同一引数から呼び出せば同じsimulationMatchIdになる'
        '（determinism、pure function）', () {
      final a = _id();
      final b = _id();
      expect(a, b);
    });

    test('matchIndex/wrestler/policy差でもsimulationMatchIdが分離する'
        '（既存Codex review M2契約の維持確認）', () {
      expect(_id(matchIndex: 0), isNot(_id(matchIndex: 1)));
      expect(_id(wrestlerAId: 'misaki'), isNot(_id(wrestlerAId: 'akari')));
      expect(
        _id(playerAPolicyId: 'firstLegal'),
        isNot(_id(playerAPolicyId: 'randomLegal')),
      );
      expect(_id(masterSeed: 1), isNot(_id(masterSeed: 2)));
    });
  });
}
