/// Phase 10A Production Data integration test（豪田ミサキ）。
///
/// `test/combat_v1/combat_v1_test_fixtures.dart`のfixture（`fx_*`）は既存Core
/// Engine testsが引き続き参照するため変更しない（docs/combat_rules_v1.md 26章
/// 「Phase 10」の方針）。本ファイルは`lib/src/combat_v1/combat_v1_wrestler_catalog.dart`
/// ／`combat_v1_technique_catalog.dart`／`combat_v1_counter_catalog.dart`
/// ／`combat_v1_decks.dart`／`combat_v1_production_catalog.dart`が持つ、正式
/// Production Dataそのものを検証する（Core Engineルールのfixtureテストとは責務を分離する）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_catalog_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_counter_catalog.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_decks.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_production_catalog.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique_catalog.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_wrestler_catalog.dart';

void main() {
  const rules = CombatV1RulesConfig();

  group('A/B. ミサキTechnique 12定義', () {
    test('12技すべてがcatalogに存在する', () {
      expect(misakiTechniques.length, 12);
    });

    test('全Technique IDが一意（Mapのキー自体が保証するが、id fieldとの整合も確認）', () {
      final ids = misakiTechniques.values.map((t) => t.id).toSet();
      expect(ids.length, 12);
      expect(misakiTechniques.keys.toSet(), ids);
    });
  });

  group('C. Technique family', () {
    const expectedFamilies = {
      'misaki_reverse_chop': CombatV1TechniqueFamily.chop,
      'misaki_shoulder_tackle': CombatV1TechniqueFamily.tackle,
      'misaki_body_slam': CombatV1TechniqueFamily.slam,
      'misaki_brainbuster': CombatV1TechniqueFamily.suplex,
      'misaki_backdrop': CombatV1TechniqueFamily.backdrop,
      'misaki_power_slam': CombatV1TechniqueFamily.slam,
      'misaki_lariat': CombatV1TechniqueFamily.lariat,
      'misaki_guillotine_drop': CombatV1TechniqueFamily.guillotineDrop,
      'misaki_mighty_backdrop': CombatV1TechniqueFamily.backdrop,
      'misaki_strong_arm_lariat': CombatV1TechniqueFamily.lariat,
      'misaki_goda_bomb': CombatV1TechniqueFamily.powerbomb,
      'misaki_goda_driver': CombatV1TechniqueFamily.driver,
    };

    for (final entry in expectedFamilies.entries) {
      test('${entry.key} → ${entry.value.name}', () {
        expect(misakiTechniques[entry.key]!.family, entry.value);
      });
    }
  });

  group('D/E/F. Cost・DMG・HEAT・state（docs/combat_rules_v1.md 19章）', () {
    test('逆水平チョップ: 打1/DMG10/HEAT10/STAND→STAND', () {
      final t = misakiTechniques['misaki_reverse_chop']!;
      expect(t.category, CombatV1CardCategory.normal);
      expect(t.attribute, CombatV1EnergyAttribute.strike);
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 1);
      expect(t.energyCost.total, 1);
      expect(t.damage, 10);
      expect(t.heatGain, 10);
      expect(t.requiredOpponentState, isNull);
      expect(t.resultOpponentState, isNull);
    });

    test('ショルダータックル: 打1/DMG10/HEAT20/STAND→DOWN', () {
      final t = misakiTechniques['misaki_shoulder_tackle']!;
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 1);
      expect(t.damage, 10);
      expect(t.heatGain, 20);
      expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
    });

    test('ボディスラム: 投1/DMG10/HEAT10/STAND→STAND', () {
      final t = misakiTechniques['misaki_body_slam']!;
      expect(t.attribute, CombatV1EnergyAttribute.throwing);
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 1);
      expect(t.damage, 10);
      expect(t.heatGain, 10);
      expect(t.resultOpponentState, isNull);
    });

    test('ブレーンバスター: 投2/DMG20/HEAT20/STAND→DOWN', () {
      final t = misakiTechniques['misaki_brainbuster']!;
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 2);
      expect(t.damage, 20);
      expect(t.heatGain, 20);
      expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
    });

    test('バックドロップ: 投2/DMG20/HEAT20/STAND→DOWN', () {
      final t = misakiTechniques['misaki_backdrop']!;
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 2);
      expect(t.damage, 20);
      expect(t.heatGain, 20);
      expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
    });

    test('パワースラム: 投3/DMG30/HEAT30/STAND→DOWN', () {
      final t = misakiTechniques['misaki_power_slam']!;
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 3);
      expect(t.damage, 30);
      expect(t.heatGain, 30);
      expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
    });

    test('ラリアット: 打2/DMG20/HEAT20/STAND→DOWN', () {
      final t = misakiTechniques['misaki_lariat']!;
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 2);
      expect(t.damage, 20);
      expect(t.heatGain, 20);
      expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
    });

    test('ギロチンドロップ: 打1/DMG10/HEAT20/DOWN→DOWN', () {
      final t = misakiTechniques['misaki_guillotine_drop']!;
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 1);
      expect(t.damage, 10);
      expect(t.heatGain, 20);
      expect(t.requiredOpponentState, CombatV1WrestlerPosture.down);
      expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
    });

    test('豪快バックドロップ: SIGNATURE/投3/DMG30/HEAT40/STAND→DOWN', () {
      final t = misakiTechniques['misaki_mighty_backdrop']!;
      expect(t.category, CombatV1CardCategory.signature);
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 3);
      expect(t.damage, 30);
      expect(t.heatGain, 40);
      expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
    });

    test('剛腕ラリアット: SIGNATURE/打2/DMG20/HEAT30/STAND→DOWN', () {
      final t = misakiTechniques['misaki_strong_arm_lariat']!;
      expect(t.category, CombatV1CardCategory.signature);
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 2);
      expect(t.damage, 20);
      expect(t.heatGain, 30);
      expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
    });

    test('豪田ボム: FINISHER/投3/DMG30/HEAT40/STAND→DOWN', () {
      final t = misakiTechniques['misaki_goda_bomb']!;
      expect(t.category, CombatV1CardCategory.finisher);
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 3);
      expect(t.damage, 30);
      expect(t.heatGain, 40);
      expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
    });

    test('豪田ドライバー: FINISHER/投4/DMG40/HEAT50/STAND→DOWN', () {
      final t = misakiTechniques['misaki_goda_driver']!;
      expect(t.category, CombatV1CardCategory.finisher);
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 4);
      expect(t.damage, 40);
      expect(t.heatGain, 50);
      expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
    });
  });

  group('G. FINISHER type', () {
    test('豪田ボム: finisherType == directPin（19章「DIRECT PIN」注記から確定）', () {
      expect(
        misakiTechniques['misaki_goda_bomb']!.finisherType,
        CombatV1FinisherType.directPin,
      );
    });

    test('豪田ドライバー: finisherType == normal（Phase 10Aセッションでユーザー確定）', () {
      expect(
        misakiTechniques['misaki_goda_driver']!.finisherType,
        CombatV1FinisherType.normal,
      );
    });

    test('NORMAL/SIGNATUREの全技はfinisherType == null', () {
      for (final t in misakiTechniques.values) {
        if (t.category == CombatV1CardCategory.finisher) continue;
        expect(t.finisherType, isNull, reason: '${t.id}はcategory!=finisherです');
      }
    });

    test('全技のhasConsistentFinisherTypeがtrue', () {
      for (final t in misakiTechniques.values) {
        expect(t.hasConsistentFinisherType, isTrue, reason: t.id);
      }
    });
  });

  group('H. Counter 3定義', () {
    test('3種すべてが存在する', () {
      expect(misakiCounters.length, 3);
      expect(misakiCounters.keys.toSet(), {
        'counter_strike_guard',
        'counter_suplex_reversal',
        'counter_powerbomb_escape',
      });
    });

    test('広範囲型（ガード＆エルボー）: attribute=打, counterableGroups=[STRIKE]', () {
      final c = misakiCounters['counter_strike_guard']!;
      expect(c.attribute, CombatV1EnergyAttribute.strike);
      expect(c.counterableGroups, [CombatV1TechniqueFamilyGroup.strike]);
      expect(c.counterableFamilies, isEmpty);
    });

    test('中範囲型（スープレックス切り返し）: attribute=投, families=[BACKDROP, SUPLEX]', () {
      final c = misakiCounters['counter_suplex_reversal']!;
      expect(c.attribute, CombatV1EnergyAttribute.throwing);
      expect(c.counterableFamilies, [
        CombatV1TechniqueFamily.backdrop,
        CombatV1TechniqueFamily.suplex,
      ]);
      expect(c.counterableGroups, isEmpty);
    });

    test('専門型（フランケンシュタイナー返し）: attribute=投, families=[POWERBOMB]', () {
      final c = misakiCounters['counter_powerbomb_escape']!;
      expect(c.attribute, CombatV1EnergyAttribute.throwing);
      expect(c.counterableFamilies, [CombatV1TechniqueFamily.powerbomb]);
      expect(c.counterableGroups, isEmpty);
    });
  });

  group('I. ENERGY Pool', () {
    test('打3/関0/投4/飛0/ラフ1/＊1＝合計9', () {
      final pool = misakiWrestler.energyPool;
      expect(pool.amountFor(CombatV1EnergyAttribute.strike), 3);
      expect(pool.amountFor(CombatV1EnergyAttribute.joint), 0);
      expect(pool.amountFor(CombatV1EnergyAttribute.throwing), 4);
      expect(pool.amountFor(CombatV1EnergyAttribute.aerial), 0);
      expect(pool.amountFor(CombatV1EnergyAttribute.rough), 1);
      expect(pool.amountFor(CombatV1EnergyAttribute.wild), 1);
      expect(pool.amounts.values.fold(0, (a, b) => a + b), 9);
      expect(pool.isValid, isTrue);
    });

    test('Wrestler ID/nameが正式値', () {
      expect(misakiWrestler.id, 'misaki');
      expect(misakiWrestler.name, '豪田ミサキ');
    });
  });

  group('J/K/L. Deck 30枚・18/4/2/6・同名上限', () {
    late final deck = buildMisakiDeck();

    test('合計30枚', () {
      expect(deck.size, 30);
    });

    test('NORMAL18/SIGNATURE4/FINISHER2/COUNTER6', () {
      expect(deck.countOf(CombatV1CardCategory.normal), 18);
      expect(deck.countOf(CombatV1CardCategory.signature), 4);
      expect(deck.countOf(CombatV1CardCategory.finisher), 2);
      expect(deck.countOf(CombatV1CardCategory.counter), 6);
    });

    test('同名カード枚数が上限以内（NORMAL<=3/SIGNATURE<=2/FINISHER<=1/COUNTER<=2）', () {
      final counts = <String, int>{};
      for (final entry in deck.entries) {
        counts[entry.cardId] = (counts[entry.cardId] ?? 0) + 1;
      }
      for (final e in counts.entries) {
        final category = productionCardCatalog.categoryOf(e.key)!;
        expect(
          e.value,
          lessThanOrEqualTo(rules.sameNameLimitFor(category)),
          reason: e.key,
        );
      }
      // 期待値どおりの内訳であることも確認する
      expect(counts['misaki_reverse_chop'], 3);
      expect(counts['misaki_body_slam'], 3);
      expect(counts['misaki_shoulder_tackle'], 2);
      expect(counts['misaki_brainbuster'], 2);
      expect(counts['misaki_backdrop'], 2);
      expect(counts['misaki_power_slam'], 2);
      expect(counts['misaki_lariat'], 2);
      expect(counts['misaki_guillotine_drop'], 2);
      expect(counts['misaki_mighty_backdrop'], 2);
      expect(counts['misaki_strong_arm_lariat'], 2);
      expect(counts['misaki_goda_bomb'], 1);
      expect(counts['misaki_goda_driver'], 1);
      expect(counts['counter_strike_guard'], 2);
      expect(counts['counter_suplex_reversal'], 2);
      expect(counts['counter_powerbomb_escape'], 2);
    });

    test('instanceIdが全て一意', () {
      final ids = deck.entries.map((e) => e.instanceId).toSet();
      expect(ids.length, deck.size);
    });
  });

  group('M. Catalog validation', () {
    test('productionCardCatalogはvalidateCatalogを通過する', () {
      final result = validateCatalog(productionCardCatalog);
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
    });

    test('Technique/Counter間でcardId衝突がない', () {
      final techniqueIds = misakiTechniques.keys.toSet();
      final counterIds = misakiCounters.keys.toSet();
      expect(techniqueIds.intersection(counterIds), isEmpty);
    });
  });

  group('N. Deck validation', () {
    test('buildMisakiDeck()はvalidateDeckを通過する', () {
      final deck = buildMisakiDeck();
      final result = validateDeck(
        deck,
        catalog: productionCardCatalog,
        rules: rules,
      );
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
    });
  });

  group('O/P. CombatV1Engine.start・card conservation', () {
    test('ミサキ同士のミラーマッチでstartが正常に完了する', () {
      final state = CombatV1Engine.start(
        wrestlerA: misakiWrestler,
        deckA: buildMisakiDeck(),
        wrestlerB: misakiWrestler,
        deckB: buildMisakiDeck(),
        rules: rules,
        catalog: productionCardCatalog,
      );

      expect(state.playerA.wrestlerId, 'misaki');
      expect(state.playerB.wrestlerId, 'misaki');
      expect(state.phase, CombatV1MatchPhase.discard);
      expect(state.playerA.hp, rules.startingHp);
      expect(state.playerB.hp, rules.startingHp);
    });

    test('start直後、両プレイヤーのカード総数がデッキ枚数(30)と一致する（card conservation）', () {
      final state = CombatV1Engine.start(
        wrestlerA: misakiWrestler,
        deckA: buildMisakiDeck(),
        wrestlerB: misakiWrestler,
        deckB: buildMisakiDeck(),
        rules: rules,
        catalog: productionCardCatalog,
      );

      final totalA =
          state.playerA.hand.length +
          state.playerA.drawPile.length +
          state.playerA.discardPile.length;
      final totalB =
          state.playerB.hand.length +
          state.playerB.drawPile.length +
          state.playerB.discardPile.length;

      expect(totalA, 30);
      expect(totalB, 30);
      // ターン開始プレイヤー（playerA）は開始時ドローを終えているため手札6枚
      // （初期5枚+ターン開始ドロー1枚、discardフェーズでまだ1枚捨てていない）。
      expect(state.playerA.hand.length, rules.startingHandSize + 1);
    });
  });

  group('Q. Production DataをDomain lookupできる（Simulator/UI非依存）', () {
    test('productionCardCatalog.containsCardIdで全12技・3 Counterを参照できる', () {
      for (final id in misakiTechniques.keys) {
        expect(productionCardCatalog.containsCardId(id), isTrue, reason: id);
      }
      for (final id in misakiCounters.keys) {
        expect(productionCardCatalog.containsCardId(id), isTrue, reason: id);
      }
    });

    test('categoryOfが各カードの正しいcategoryを返す', () {
      expect(
        productionCardCatalog.categoryOf('misaki_reverse_chop'),
        CombatV1CardCategory.normal,
      );
      expect(
        productionCardCatalog.categoryOf('misaki_mighty_backdrop'),
        CombatV1CardCategory.signature,
      );
      expect(
        productionCardCatalog.categoryOf('misaki_goda_bomb'),
        CombatV1CardCategory.finisher,
      );
      expect(
        productionCardCatalog.categoryOf('counter_strike_guard'),
        CombatV1CardCategory.counter,
      );
    });
  });
}
