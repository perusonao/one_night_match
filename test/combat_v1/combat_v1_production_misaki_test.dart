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
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_decks.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_production_catalog.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique_catalog.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_wrestler_catalog.dart';

const CombatV1RulesConfig rules = CombatV1RulesConfig();

/// Technique state legality検証専用の最小MatchStateを組み立てる
/// （`test/combat_v1/combat_v1_technique_legality_test.dart`の`_buildState`と
/// 同じ方針だが、fixtureWrestlerではなく実際の[misakiWrestler]（Production
/// ENERGY Pool）をplayerA/playerB双方に使う。Production
/// Technique自身のENERGY COSTが、ミサキの実際の保有量で無理なく支払えることも
/// 合わせて検証できるようにするため）。
CombatV1MatchState _buildMisakiLegalityState({
  required CombatV1WrestlerPosture opponentPosture,
  required List<CombatV1DeckEntry> handA,
  int sharedHeat = 0,
}) {
  final playerA = CombatV1PlayerState(
    wrestlerId: misakiWrestler.id,
    wrestlerName: misakiWrestler.name,
    maxHp: rules.startingHp,
    hp: rules.startingHp,
    koc: rules.startingKoc,
    pinCardsHeld: rules.startingPinCards,
    posture: CombatV1WrestlerPosture.stand,
    energyPool: misakiWrestler.energyPool,
    hand: handA,
  );
  final playerB = CombatV1PlayerState(
    wrestlerId: misakiWrestler.id,
    wrestlerName: misakiWrestler.name,
    maxHp: rules.startingHp,
    hp: rules.startingHp,
    koc: rules.startingKoc,
    pinCardsHeld: rules.startingPinCards,
    posture: opponentPosture,
    energyPool: misakiWrestler.energyPool,
  );
  return CombatV1MatchState(
    matchId: 'phase10a-legality-test',
    playerA: playerA,
    playerB: playerB,
    activePlayerIndex: 0,
    sharedHeat: sharedHeat,
    turnNumber: 1,
    phase: CombatV1MatchPhase.action,
  );
}

/// [cardId]を唯一のinstanceId `'a1'`としてplayerAの手札へ入れたlegality
/// チェック結果を返す。
CombatV1ActionCheck _checkLegality(
  String cardId, {
  required CombatV1WrestlerPosture opponentPosture,
  int sharedHeat = 0,
}) {
  final category = misakiTechniques[cardId]!.category;
  final state = _buildMisakiLegalityState(
    opponentPosture: opponentPosture,
    sharedHeat: sharedHeat,
    handA: [
      CombatV1DeckEntry(instanceId: 'a1', cardId: cardId, category: category),
    ],
  );
  return CombatV1Engine.checkTechniqueLegality(
    state,
    'a1',
    catalog: productionCardCatalog,
    rules: rules,
  );
}

void main() {

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
      expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
      expect(t.resultOpponentState, isNull);
    });

    test('ショルダータックル: 打1/DMG10/HEAT20/STAND→DOWN', () {
      final t = misakiTechniques['misaki_shoulder_tackle']!;
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 1);
      expect(t.damage, 10);
      expect(t.heatGain, 20);
      expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
      expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
    });

    test('ボディスラム: 投1/DMG10/HEAT10/STAND→STAND', () {
      final t = misakiTechniques['misaki_body_slam']!;
      expect(t.attribute, CombatV1EnergyAttribute.throwing);
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 1);
      expect(t.damage, 10);
      expect(t.heatGain, 10);
      expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
      expect(t.resultOpponentState, isNull);
    });

    test('ブレーンバスター: 投2/DMG20/HEAT20/STAND→DOWN', () {
      final t = misakiTechniques['misaki_brainbuster']!;
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 2);
      expect(t.damage, 20);
      expect(t.heatGain, 20);
      expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
      expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
    });

    test('バックドロップ: 投2/DMG20/HEAT20/STAND→DOWN', () {
      final t = misakiTechniques['misaki_backdrop']!;
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 2);
      expect(t.damage, 20);
      expect(t.heatGain, 20);
      expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
      expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
    });

    test('パワースラム: 投3/DMG30/HEAT30/STAND→DOWN', () {
      final t = misakiTechniques['misaki_power_slam']!;
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 3);
      expect(t.damage, 30);
      expect(t.heatGain, 30);
      expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
      expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
    });

    test('ラリアット: 打2/DMG20/HEAT20/STAND→DOWN', () {
      final t = misakiTechniques['misaki_lariat']!;
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 2);
      expect(t.damage, 20);
      expect(t.heatGain, 20);
      expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
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
      expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
      expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
    });

    test('剛腕ラリアット: SIGNATURE/打2/DMG20/HEAT30/STAND→DOWN', () {
      final t = misakiTechniques['misaki_strong_arm_lariat']!;
      expect(t.category, CombatV1CardCategory.signature);
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 2);
      expect(t.damage, 20);
      expect(t.heatGain, 30);
      expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
      expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
    });

    test('豪田ボム: FINISHER/投3/DMG30/HEAT40/STAND→DOWN', () {
      final t = misakiTechniques['misaki_goda_bomb']!;
      expect(t.category, CombatV1CardCategory.finisher);
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 3);
      expect(t.damage, 30);
      expect(t.heatGain, 40);
      expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
      expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
    });

    test('豪田ドライバー: FINISHER/投4/DMG40/HEAT50/STAND→DOWN', () {
      final t = misakiTechniques['misaki_goda_driver']!;
      expect(t.category, CombatV1CardCategory.finisher);
      expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 4);
      expect(t.damage, 40);
      expect(t.heatGain, 50);
      expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
      expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
    });

    test('STAND始動11技すべてがrequiredOpponentState==standを持つ（regression防止）', () {
      const standRequiredIds = [
        'misaki_reverse_chop',
        'misaki_shoulder_tackle',
        'misaki_body_slam',
        'misaki_brainbuster',
        'misaki_backdrop',
        'misaki_power_slam',
        'misaki_lariat',
        'misaki_mighty_backdrop',
        'misaki_strong_arm_lariat',
        'misaki_goda_bomb',
        'misaki_goda_driver',
      ];
      expect(standRequiredIds.length, 11);
      for (final id in standRequiredIds) {
        expect(
          misakiTechniques[id]!.requiredOpponentState,
          CombatV1WrestlerPosture.stand,
          reason: '$idはrequiredOpponentState==standである必要があります',
        );
      }
      // ギロチンドロップのみDOWN始動（8技目、19章）。
      expect(
        misakiTechniques['misaki_guillotine_drop']!.requiredOpponentState,
        CombatV1WrestlerPosture.down,
      );
      // 12技すべてがrequiredOpponentStateを明示的に持つ
      // （nullは「STAND/DOWNどちらでも可」を意味するため、未設定のまま
      // 残っている技が無いことを保証する）。
      for (final t in misakiTechniques.values) {
        expect(
          t.requiredOpponentState,
          isNotNull,
          reason: '${t.id}はrequiredOpponentStateが未設定です',
        );
      }
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

  group('R. Technique state legality（Codexレビュー指摘の再発防止）', () {
    test('A. 逆水平チョップ: opponent DOWN → illegal（opponentStateMismatch）', () {
      final check = _checkLegality(
        'misaki_reverse_chop',
        opponentPosture: CombatV1WrestlerPosture.down,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('B. ショルダータックル: opponent DOWN → illegal（opponentStateMismatch）', () {
      final check = _checkLegality(
        'misaki_shoulder_tackle',
        opponentPosture: CombatV1WrestlerPosture.down,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('C. ボディスラム（THROW/STAND始動）: opponent DOWN → illegal', () {
      final check = _checkLegality(
        'misaki_body_slam',
        opponentPosture: CombatV1WrestlerPosture.down,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('C. バックドロップ（THROW/STAND始動）: opponent DOWN → illegal', () {
      final check = _checkLegality(
        'misaki_backdrop',
        opponentPosture: CombatV1WrestlerPosture.down,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('D. 豪快バックドロップ（SIGNATURE）: opponent DOWN → illegal', () {
      final check = _checkLegality(
        'misaki_mighty_backdrop',
        opponentPosture: CombatV1WrestlerPosture.down,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('E. 豪田ボム（FINISHER）: HEAT解禁済みでもopponent DOWN → illegal', () {
      // sharedHeat=finisherHeatThresholdでFINISHER解禁条件は満たしたうえで、
      // state mismatchのみを検証する（HEAT不足によるfinisherHeatNotReachedと
      // 混同しないため）。
      final check = _checkLegality(
        'misaki_goda_bomb',
        opponentPosture: CombatV1WrestlerPosture.down,
        sharedHeat: rules.finisherHeatThreshold,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('E. 豪田ドライバー（FINISHER）: HEAT解禁済みでもopponent DOWN → illegal', () {
      final check = _checkLegality(
        'misaki_goda_driver',
        opponentPosture: CombatV1WrestlerPosture.down,
        sharedHeat: rules.finisherHeatThreshold,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('F. ギロチンドロップ: opponent DOWN → state条件はlegal（ENERGY等も充足）', () {
      final check = _checkLegality(
        'misaki_guillotine_drop',
        opponentPosture: CombatV1WrestlerPosture.down,
      );
      expect(check.legal, isTrue);
      expect(check.reasonCode, CombatV1TechniqueLegalityReasonCode.legal);
    });

    test('G. ギロチンドロップ: opponent STAND → illegal（opponentStateMismatch）', () {
      final check = _checkLegality(
        'misaki_guillotine_drop',
        opponentPosture: CombatV1WrestlerPosture.stand,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test(
      'table-driven: STAND始動11技すべてがopponent DOWNでopponentStateMismatch'
      '（requiredOpponentStateが誤ってnullへ戻るregressionを防止）',
      () {
        const standRequiredIds = [
          'misaki_reverse_chop',
          'misaki_shoulder_tackle',
          'misaki_body_slam',
          'misaki_brainbuster',
          'misaki_backdrop',
          'misaki_power_slam',
          'misaki_lariat',
          'misaki_mighty_backdrop',
          'misaki_strong_arm_lariat',
          'misaki_goda_bomb',
          'misaki_goda_driver',
        ];
        expect(standRequiredIds.length, 11);
        for (final id in standRequiredIds) {
          final isFinisher =
              misakiTechniques[id]!.category == CombatV1CardCategory.finisher;
          final check = _checkLegality(
            id,
            opponentPosture: CombatV1WrestlerPosture.down,
            sharedHeat: isFinisher ? rules.finisherHeatThreshold : 0,
          );
          expect(check.legal, isFalse, reason: id);
          expect(
            check.reasonCode,
            CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
            reason: id,
          );
        }
      },
    );
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
