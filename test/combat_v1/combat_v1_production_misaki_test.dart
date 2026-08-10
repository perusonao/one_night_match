/// Phase 10A Production Data integration test（豪田ミサキ）。
///
/// `test/combat_v1/combat_v1_test_fixtures.dart`のfixture（`fx_*`）は既存Core
/// Engine testsが引き続き参照するため変更しない（docs/combat_rules_v1.md 26章
/// 「Phase 10」の方針）。本ファイルは`lib/src/combat_v1/combat_v1_wrestler_catalog.dart`
/// ／`combat_v1_technique_catalog.dart`／`combat_v1_counter_catalog.dart`
/// ／`combat_v1_decks.dart`／`combat_v1_production_catalog.dart`が持つ、正式
/// Production Dataそのものを検証する（Core Engineルールのfixtureテストとは責務を分離する）。
library;

import 'dart:math';

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
import 'package:one_night_match/src/combat_v1/combat_v1_state_invariants.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique_catalog.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_wrestler_catalog.dart';

const CombatV1RulesConfig rules = CombatV1RulesConfig();

/// [state]が持つ、両playerの全カードゾーン（hand/drawPile/discardPile）＋
/// pendingが所有する攻撃カードのinstanceIdをすべて集めたリスト（test専用
/// helper、Productionコードへは追加しない）。GitHub Codex P1指摘
/// （player間instanceId衝突）の再発を、match全体で横断的に検証するために使う。
List<String> _allInstanceIds(CombatV1MatchState state) {
  final pending = state.pendingAttack;
  return [
    ...state.playerA.hand.map((e) => e.instanceId),
    ...state.playerA.drawPile.map((e) => e.instanceId),
    ...state.playerA.discardPile.map((e) => e.instanceId),
    ...state.playerB.hand.map((e) => e.instanceId),
    ...state.playerB.drawPile.map((e) => e.instanceId),
    ...state.playerB.discardPile.map((e) => e.instanceId),
    if (pending != null) pending.attackCardInstance.instanceId,
  ];
}

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
    late final deck = buildMisakiDeck(ownerId: 'player-a');

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

    test('A. 単一deck: instanceIdが30枚すべて一意', () {
      final ids = deck.entries.map((e) => e.instanceId).toSet();
      expect(ids.length, deck.size);
    });

    test('ownerIdが空文字だとArgumentErrorを送出する（GitHub Codex P1指摘対応）', () {
      expect(() => buildMisakiDeck(ownerId: ''), throwsArgumentError);
      expect(() => buildMisakiDeck(ownerId: '   '), throwsArgumentError);
    });

    test(
      'B. mirror match: 同じownerId未使用なら2デッキ計60枚のinstanceIdが'
      'すべて一意（GitHub Codex P1指摘の再発防止）',
      () {
        final deckA = buildMisakiDeck(ownerId: 'player-a');
        final deckB = buildMisakiDeck(ownerId: 'player-b');

        final idsA = deckA.entries.map((e) => e.instanceId).toSet();
        final idsB = deckB.entries.map((e) => e.instanceId).toSet();
        expect(idsA.length, 30);
        expect(idsB.length, 30);

        // cardId構成（技の内訳）は両者同一でよい。
        final cardIdsA = deckA.entries.map((e) => e.cardId).toList()..sort();
        final cardIdsB = deckB.entries.map((e) => e.cardId).toList()..sort();
        expect(cardIdsA, cardIdsB);

        // instanceIdはplayerを跨いで衝突してはならない。
        final allIds = [...idsA, ...idsB];
        expect(allIds.toSet().length, 60);
      },
    );
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
      final deck = buildMisakiDeck(ownerId: 'player-a');
      final result = validateDeck(
        deck,
        catalog: productionCardCatalog,
        rules: rules,
      );
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
    });
  });

  group('O/P. CombatV1Engine.start・card conservation', () {
    test('ミサキ同士のミラーマッチでstartが正常に完了する（C. Engine.start mirror match）', () {
      final state = CombatV1Engine.start(
        wrestlerA: misakiWrestler,
        deckA: buildMisakiDeck(ownerId: 'player-a'),
        wrestlerB: misakiWrestler,
        deckB: buildMisakiDeck(ownerId: 'player-b'),
        rules: rules,
        catalog: productionCardCatalog,
      );

      expect(state.playerA.wrestlerId, 'misaki');
      expect(state.playerB.wrestlerId, 'misaki');
      expect(state.phase, CombatV1MatchPhase.discard);
      expect(state.playerA.hp, rules.startingHp);
      expect(state.playerB.hp, rules.startingHp);

      // GitHub Codex P1指摘の再発防止: start直後の時点で、両playerの
      // 全カードゾーンを横断してinstanceId衝突がないこと。
      final result = validateMatchStateInvariants(state, rules: rules);
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
      expect(_allInstanceIds(state).toSet().length, 60);
    });

    test('start直後、両プレイヤーのカード総数がデッキ枚数(30)と一致する（card conservation）', () {
      final state = CombatV1Engine.start(
        wrestlerA: misakiWrestler,
        deckA: buildMisakiDeck(ownerId: 'player-a'),
        wrestlerB: misakiWrestler,
        deckB: buildMisakiDeck(ownerId: 'player-b'),
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
      // 60枚合計・instanceId一意もあわせて確認する。
      expect(totalA + totalB, 60);
      expect(_allInstanceIds(state).toSet().length, 60);
      // ターン開始プレイヤー（playerA）は開始時ドローを終えているため手札6枚
      // （初期5枚+ターン開始ドロー1枚、discardフェーズでまだ1枚捨てていない）。
      expect(state.playerA.hand.length, rules.startingHandSize + 1);
    });

    test(
      'D. declareTechnique→declineCounterの1経路を通しても'
      'instanceId衝突・pending ownership違反が起きない（GitHub Codex P1指摘対応）',
      () {
        final random = Random(20260810);
        final started = CombatV1Engine.start(
          wrestlerA: misakiWrestler,
          deckA: buildMisakiDeck(ownerId: 'player-a'),
          wrestlerB: misakiWrestler,
          deckB: buildMisakiDeck(ownerId: 'player-b'),
          rules: rules,
          catalog: productionCardCatalog,
          random: random,
        );

        // start直後はphase==discard（手札循環、docs/combat_rules_v1.md
        // 16.1章）。1枚捨ててactionフェーズへ進めないとdeclareTechniqueは
        // 呼べない。
        final discardEntry = started.playerA.hand.first;
        final afterDiscard = CombatV1Engine.discardCard(
          started,
          discardEntry.instanceId,
        );
        expect(afterDiscard.phase, CombatV1MatchPhase.action);

        // COUNTERはTECHNIQUEとして宣言できないため、手札からCOUNTER以外の
        // カードを1枚選ぶ（30枚中24枚がNORMAL/SIGNATURE/FINISHERのため、
        // 残り5枚の手札が全てCOUNTERになる確率は無視できるほど小さいが、
        // 万一の場合は分かりやすい失敗メッセージを出す）。
        final attackEntry = afterDiscard.playerA.hand.firstWhere(
          (e) => e.category != CombatV1CardCategory.counter,
          orElse: () => throw StateError(
            'テスト前提が崩れています: playerAの手札がCOUNTERのみです'
            '（${afterDiscard.playerA.hand.map((e) => e.cardId).join(', ')}）',
          ),
        );

        final declared = CombatV1Engine.declareTechnique(
          afterDiscard,
          attackEntry.instanceId,
          catalog: productionCardCatalog,
          rules: rules,
        );
        expect(declared.phase, CombatV1MatchPhase.counterResponsePending);
        expect(declared.pendingAttack, isNotNull);

        // pending中もinstanceId衝突・所有権違反が発生していないこと。
        final pendingResult = validateMatchStateInvariants(
          declared,
          rules: rules,
        );
        expect(pendingResult.isValid, isTrue, reason: pendingResult.errors.join(' / '));
        expect(_allInstanceIds(declared).toSet().length, 60);

        final resolved = CombatV1Engine.declineCounter(
          declared,
          rules: rules,
          random: random,
        );
        expect(resolved.phase, CombatV1MatchPhase.action);
        expect(resolved.pendingAttack, isNull);

        // decline成立後も、card conservation・instanceId一意性を維持する。
        final totalA =
            resolved.playerA.hand.length +
            resolved.playerA.drawPile.length +
            resolved.playerA.discardPile.length;
        final totalB =
            resolved.playerB.hand.length +
            resolved.playerB.drawPile.length +
            resolved.playerB.discardPile.length;
        expect(totalA, 30);
        expect(totalB, 30);

        final resolvedResult = validateMatchStateInvariants(
          resolved,
          rules: rules,
        );
        expect(resolvedResult.isValid, isTrue, reason: resolvedResult.errors.join(' / '));
        expect(_allInstanceIds(resolved).toSet().length, 60);

        // 攻撃カードは攻撃側（playerA）のdiscardへ移動している。
        expect(
          resolved.playerA.discardPile.any(
            (e) => e.instanceId == attackEntry.instanceId,
          ),
          isTrue,
        );
      },
    );

    test(
      'E. declareTechnique→playCounterの1経路（COUNTER mirror test）を'
      '通しても、両player全ゾーン+pendingでinstanceId衝突が起きない',
      () {
        // 手札の乱数shuffleに依存せず、攻撃側手札にmisaki_backdrop
        // （family=BACKDROP、Cost投2）、防御側手札にcounter_suplex_reversal
        // （counterableFamilies=[BACKDROP, SUPLEX]、attribute=throwing）を
        // 直接配置した最小構成で検証する。drawPileにも1枚ずつ用意し、
        // COUNTER成立後の1draw（7.1章）が空のdrawPile→discardPile
        // reshuffleで直前に捨てたカードをそのまま引き戻す曖昧なケースを避ける。
        final playerA = CombatV1PlayerState(
          wrestlerId: misakiWrestler.id,
          wrestlerName: misakiWrestler.name,
          maxHp: rules.startingHp,
          hp: rules.startingHp,
          koc: rules.startingKoc,
          pinCardsHeld: rules.startingPinCards,
          energyPool: misakiWrestler.energyPool,
          hand: const [
            CombatV1DeckEntry(
              instanceId: 'player-a_misaki_backdrop_#0',
              cardId: 'misaki_backdrop',
              category: CombatV1CardCategory.normal,
            ),
          ],
          drawPile: const [
            CombatV1DeckEntry(
              instanceId: 'player-a_misaki_lariat_#0',
              cardId: 'misaki_lariat',
              category: CombatV1CardCategory.normal,
            ),
          ],
        );
        final playerB = CombatV1PlayerState(
          wrestlerId: misakiWrestler.id,
          wrestlerName: misakiWrestler.name,
          maxHp: rules.startingHp,
          hp: rules.startingHp,
          koc: rules.startingKoc,
          pinCardsHeld: rules.startingPinCards,
          energyPool: misakiWrestler.energyPool,
          hand: const [
            CombatV1DeckEntry(
              instanceId: 'player-b_counter_suplex_reversal_#0',
              cardId: 'counter_suplex_reversal',
              category: CombatV1CardCategory.counter,
            ),
          ],
          drawPile: const [
            CombatV1DeckEntry(
              instanceId: 'player-b_misaki_power_slam_#0',
              cardId: 'misaki_power_slam',
              category: CombatV1CardCategory.normal,
            ),
          ],
        );
        final state = CombatV1MatchState(
          matchId: 'phase10a-counter-mirror-test',
          playerA: playerA,
          playerB: playerB,
          activePlayerIndex: 0,
          phase: CombatV1MatchPhase.action,
        );

        final declared = CombatV1Engine.declareTechnique(
          state,
          'player-a_misaki_backdrop_#0',
          catalog: productionCardCatalog,
          rules: rules,
        );
        expect(declared.phase, CombatV1MatchPhase.counterResponsePending);

        final countered = CombatV1Engine.playCounter(
          declared,
          'player-b_counter_suplex_reversal_#0',
          catalog: productionCardCatalog,
          rules: rules,
        );
        expect(countered.phase, CombatV1MatchPhase.action);
        expect(countered.pendingAttack, isNull);

        // 攻撃カード: 攻撃側(A)のdiscardへ。Counterカード: 防御側(B)のdiscardへ。
        expect(
          countered.playerA.discardPile.any(
            (e) => e.instanceId == 'player-a_misaki_backdrop_#0',
          ),
          isTrue,
        );
        expect(
          countered.playerB.discardPile.any(
            (e) => e.instanceId == 'player-b_counter_suplex_reversal_#0',
          ),
          isTrue,
        );

        final result = validateMatchStateInvariants(countered, rules: rules);
        expect(result.isValid, isTrue, reason: result.errors.join(' / '));
        // 元々4枚（A: backdrop+lariat、B: counter+power_slam）が
        // zone間を移動しただけで、instanceIdは4枚とも一意のまま保たれる。
        expect(_allInstanceIds(countered).toSet().length, 4);
      },
    );
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
