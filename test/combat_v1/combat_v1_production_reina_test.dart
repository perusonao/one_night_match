/// Phase 10C Production Data integration test（白銀レイナ）。
///
/// `test/combat_v1/combat_v1_test_fixtures.dart`のfixture（`fx_*`）は既存Core
/// Engine testsが引き続き参照するため変更しない（docs/combat_rules_v1.md 26章
/// 「Phase 10」の方針）。本ファイルは`lib/src/combat_v1/combat_v1_wrestler_catalog.dart`
/// ／`combat_v1_technique_catalog.dart`／`combat_v1_counter_catalog.dart`
/// ／`combat_v1_decks.dart`／`combat_v1_production_catalog.dart`が持つ、正式
/// Production Dataそのものを検証する（Core Engineルールのfixtureテストとは責務を分離する）。
/// 値はPhase 10C Production Data Final Specification（Phase 10C-0.5、A1〜A10・
/// A7最終回答）を厳密に反映する。
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
/// helper、Productionコードへは追加しない）。
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
/// （`combat_v1_production_misaki_test.dart`の`_buildMisakiLegalityState`と
/// 同じ方針だが、実際の[reinaWrestler]（Production ENERGY Pool）を使う）。
CombatV1MatchState _buildReinaLegalityState({
  required CombatV1WrestlerPosture opponentPosture,
  required List<CombatV1DeckEntry> handA,
  int sharedHeat = 0,
}) {
  final playerA = CombatV1PlayerState(
    wrestlerId: reinaWrestler.id,
    wrestlerName: reinaWrestler.name,
    maxHp: rules.startingHp,
    hp: rules.startingHp,
    koc: rules.startingKoc,
    pinCardsHeld: rules.startingPinCards,
    posture: CombatV1WrestlerPosture.stand,
    energyPool: reinaWrestler.energyPool,
    hand: handA,
  );
  final playerB = CombatV1PlayerState(
    wrestlerId: reinaWrestler.id,
    wrestlerName: reinaWrestler.name,
    maxHp: rules.startingHp,
    hp: rules.startingHp,
    koc: rules.startingKoc,
    pinCardsHeld: rules.startingPinCards,
    posture: opponentPosture,
    energyPool: reinaWrestler.energyPool,
  );
  return CombatV1MatchState(
    matchId: 'phase10c-reina-legality-test',
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
  final category = reinaTechniques[cardId]!.category;
  final state = _buildReinaLegalityState(
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
  group('A/B. レイナTechnique 12定義', () {
    test('12技すべてがcatalogに存在する', () {
      expect(reinaTechniques.length, 12);
    });

    test('全Technique IDが一意（Mapのキー自体が保証するが、id fieldとの整合も確認）', () {
      final ids = reinaTechniques.values.map((t) => t.id).toSet();
      expect(ids.length, 12);
      expect(reinaTechniques.keys.toSet(), ids);
    });
  });

  group('C. Technique family', () {
    const expectedFamilies = {
      'reina_side_headlock': CombatV1TechniqueFamily.headlock,
      'reina_leg_figure_four': CombatV1TechniqueFamily.figureFour,
      'reina_dragon_screw': CombatV1TechniqueFamily.legTakedown,
      'reina_drop_toehold': CombatV1TechniqueFamily.legTakedown,
      'reina_elbow': CombatV1TechniqueFamily.elbow,
      'reina_abdominal_stretch': CombatV1TechniqueFamily.stretch,
      'reina_arm_breaker': CombatV1TechniqueFamily.armbar,
      'reina_ude_hishigi': CombatV1TechniqueFamily.armbar,
      'reina_silver_crossface': CombatV1TechniqueFamily.crossface,
      'reina_figure_four_lock': CombatV1TechniqueFamily.figureFour,
      'reina_ice_lock': CombatV1TechniqueFamily.legLock,
      'reina_eternal_cross': CombatV1TechniqueFamily.crossface,
    };

    for (final entry in expectedFamilies.entries) {
      test('${entry.key} → ${entry.value.name}', () {
        expect(reinaTechniques[entry.key]!.family, entry.value);
      });
    }

    test('アイスロックのfamilyはlegLock（figureFour三重重複回避、A7最終回答）', () {
      expect(
        reinaTechniques['reina_ice_lock']!.family,
        CombatV1TechniqueFamily.legLock,
      );
      expect(
        reinaTechniques['reina_ice_lock']!.family,
        isNot(CombatV1TechniqueFamily.figureFour),
      );
    });
  });

  group(
    'D/E/F. Cost・DMG・HEAT・state（Phase 10C Production Data Final Specification 6章）',
    () {
      test('サイドヘッドロック: 関1/DMG10/HEAT10/STAND→STAND', () {
        final t = reinaTechniques['reina_side_headlock']!;
        expect(t.category, CombatV1CardCategory.normal);
        expect(t.attribute, CombatV1EnergyAttribute.joint);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.joint), 1);
        expect(t.energyCost.total, 1);
        expect(t.damage, 10);
        expect(t.heatGain, 10);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, isNull);
        expect(t.directPin, isFalse);
        expect(t.submissionHold, isFalse);
      });

      test('足四の字: 関1/DMG10/HEAT10/STAND→STAND', () {
        final t = reinaTechniques['reina_leg_figure_four']!;
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.joint), 1);
        expect(t.damage, 10);
        expect(t.heatGain, 10);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, isNull);
        expect(t.submissionHold, isFalse);
      });

      test('ドラゴンスクリュー: 投1/DMG10/HEAT20/STAND→DOWN', () {
        final t = reinaTechniques['reina_dragon_screw']!;
        expect(t.attribute, CombatV1EnergyAttribute.throwing);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 1);
        expect(t.damage, 10);
        expect(t.heatGain, 20);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
      });

      test('ドロップトーホールド: 投1/DMG10/HEAT20/STAND→DOWN', () {
        final t = reinaTechniques['reina_drop_toehold']!;
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 1);
        expect(t.damage, 10);
        expect(t.heatGain, 20);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
      });

      test('エルボー: 打1/DMG10/HEAT10/STAND→STAND', () {
        final t = reinaTechniques['reina_elbow']!;
        expect(t.attribute, CombatV1EnergyAttribute.strike);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 1);
        expect(t.damage, 10);
        expect(t.heatGain, 10);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, isNull);
      });

      test('アブドミナルストレッチ: 関1/DMG10/HEAT10/STAND→STAND（A7最終回答）', () {
        final t = reinaTechniques['reina_abdominal_stretch']!;
        expect(t.attribute, CombatV1EnergyAttribute.joint);
        expect(t.family, CombatV1TechniqueFamily.stretch);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.joint), 1);
        expect(t.damage, 10);
        expect(t.heatGain, 10);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, isNull);
        expect(t.submissionHold, isFalse);
      });

      test('アームブリーカー: 関1/DMG10/HEAT10/STAND→STAND', () {
        final t = reinaTechniques['reina_arm_breaker']!;
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.joint), 1);
        expect(t.damage, 10);
        expect(t.heatGain, 10);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, isNull);
        expect(t.submissionHold, isFalse);
      });

      test('腕ひしぎ: 関2/DMG20/HEAT20/DOWN→DOWN/submissionHold=true', () {
        final t = reinaTechniques['reina_ude_hishigi']!;
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.joint), 2);
        expect(t.damage, 20);
        expect(t.heatGain, 20);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.down);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
        expect(t.directPin, isFalse);
        expect(t.submissionHold, isTrue);
      });

      test('白銀クロスフェイス: SIGNATURE/関2/DMG20/HEAT30/STAND→DOWN/submissionHold=true', () {
        final t = reinaTechniques['reina_silver_crossface']!;
        expect(t.category, CombatV1CardCategory.signature);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.joint), 2);
        expect(t.damage, 20);
        expect(t.heatGain, 30);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
        expect(t.submissionHold, isTrue);
      });

      test('フィギュアフォー: SIGNATURE/関3/DMG30/HEAT40/STAND→DOWN/submissionHold=false', () {
        final t = reinaTechniques['reina_figure_four_lock']!;
        expect(t.category, CombatV1CardCategory.signature);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.joint), 3);
        expect(t.damage, 30);
        expect(t.heatGain, 40);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
        expect(t.submissionHold, isFalse);
      });

      test('アイスロック: FINISHER/関3/DMG30/HEAT40/STAND→DOWN', () {
        final t = reinaTechniques['reina_ice_lock']!;
        expect(t.category, CombatV1CardCategory.finisher);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.joint), 3);
        expect(t.damage, 30);
        expect(t.heatGain, 40);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
      });

      test('エターナルクロス: FINISHER/関4/DMG40/HEAT50/STAND→DOWN', () {
        final t = reinaTechniques['reina_eternal_cross']!;
        expect(t.category, CombatV1CardCategory.finisher);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.joint), 4);
        expect(t.damage, 40);
        expect(t.heatGain, 50);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
      });

      test('STAND始動11技すべてがrequiredOpponentState==standを持つ（regression防止）', () {
        const standRequiredIds = [
          'reina_side_headlock',
          'reina_leg_figure_four',
          'reina_dragon_screw',
          'reina_drop_toehold',
          'reina_elbow',
          'reina_abdominal_stretch',
          'reina_arm_breaker',
          'reina_silver_crossface',
          'reina_figure_four_lock',
          'reina_ice_lock',
          'reina_eternal_cross',
        ];
        expect(standRequiredIds.length, 11);
        for (final id in standRequiredIds) {
          expect(
            reinaTechniques[id]!.requiredOpponentState,
            CombatV1WrestlerPosture.stand,
            reason: '$idはrequiredOpponentState==standである必要があります',
          );
        }
        // 腕ひしぎのみDOWN始動。
        expect(
          reinaTechniques['reina_ude_hishigi']!.requiredOpponentState,
          CombatV1WrestlerPosture.down,
        );
        // 12技すべてがrequiredOpponentStateを明示的に持つ
        // （nullは「STAND/DOWNどちらでも可」を意味するため、未設定のまま
        // 残っている技が無いことを保証する）。
        for (final t in reinaTechniques.values) {
          expect(
            t.requiredOpponentState,
            isNotNull,
            reason: '${t.id}はrequiredOpponentStateが未設定です',
          );
        }
      });

      test('submissionHold=trueは腕ひしぎ・白銀クロスフェイスの2種のみ（A9で確定）', () {
        const submissionHoldIds = {'reina_ude_hishigi', 'reina_silver_crossface'};
        for (final t in reinaTechniques.values) {
          expect(
            t.submissionHold,
            submissionHoldIds.contains(t.id),
            reason: t.id,
          );
        }
        // 頻出NORMAL（足四の字・サイドヘッドロック、×3枚）にはsubmissionHold
        // を付与しない方針（A9で明示的に確定）。
        expect(
          reinaTechniques['reina_leg_figure_four']!.submissionHold,
          isFalse,
        );
        expect(
          reinaTechniques['reina_side_headlock']!.submissionHold,
          isFalse,
        );
      });
    },
  );

  group('G. FINISHER type', () {
    test('アイスロック: finisherType == submission', () {
      expect(
        reinaTechniques['reina_ice_lock']!.finisherType,
        CombatV1FinisherType.submission,
      );
    });

    test('エターナルクロス: finisherType == normal', () {
      expect(
        reinaTechniques['reina_eternal_cross']!.finisherType,
        CombatV1FinisherType.normal,
      );
    });

    test('NORMAL/SIGNATUREの全技はfinisherType == null', () {
      for (final t in reinaTechniques.values) {
        if (t.category == CombatV1CardCategory.finisher) continue;
        expect(t.finisherType, isNull, reason: '${t.id}はcategory!=finisherです');
      }
    });

    test('全技のhasConsistentFinisherTypeがtrue', () {
      for (final t in reinaTechniques.values) {
        expect(t.hasConsistentFinisherType, isTrue, reason: t.id);
      }
    });

    test('FINISHERはdirectPin/submissionHoldのstray設定を持たない', () {
      for (final t in reinaTechniques.values) {
        if (t.category != CombatV1CardCategory.finisher) continue;
        expect(t.directPin, isFalse, reason: t.id);
        expect(t.submissionHold, isFalse, reason: t.id);
      }
    });
  });

  group('R. Technique state legality（Codexレビュー指摘の再発防止）', () {
    test('A. サイドヘッドロック: opponent DOWN → illegal（opponentStateMismatch）', () {
      final check = _checkLegality(
        'reina_side_headlock',
        opponentPosture: CombatV1WrestlerPosture.down,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('B. 腕ひしぎ: opponent STAND → illegal（opponentStateMismatch）', () {
      final check = _checkLegality(
        'reina_ude_hishigi',
        opponentPosture: CombatV1WrestlerPosture.stand,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('C. 腕ひしぎ: opponent DOWN → state条件はlegal（ENERGY等も充足）', () {
      final check = _checkLegality(
        'reina_ude_hishigi',
        opponentPosture: CombatV1WrestlerPosture.down,
      );
      expect(check.legal, isTrue);
      expect(check.reasonCode, CombatV1TechniqueLegalityReasonCode.legal);
    });

    test('D. アイスロック（FINISHER）: HEAT解禁済みでもopponent DOWN → illegal', () {
      final check = _checkLegality(
        'reina_ice_lock',
        opponentPosture: CombatV1WrestlerPosture.down,
        sharedHeat: rules.finisherHeatThreshold,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('E. アイスロック（FINISHER）: HEAT解禁済み・opponent STANDならlegal', () {
      final check = _checkLegality(
        'reina_ice_lock',
        opponentPosture: CombatV1WrestlerPosture.stand,
        sharedHeat: rules.finisherHeatThreshold,
      );
      expect(check.legal, isTrue);
      expect(check.reasonCode, CombatV1TechniqueLegalityReasonCode.legal);
    });

    test('F. アイスロック: HEAT不足なら finisherHeatNotReached', () {
      final check = _checkLegality(
        'reina_ice_lock',
        opponentPosture: CombatV1WrestlerPosture.stand,
        sharedHeat: rules.finisherHeatThreshold - 10,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.finisherHeatNotReached,
      );
    });

    test('G. エターナルクロス（FINISHER）: HEAT解禁済みでもopponent DOWN → illegal', () {
      final check = _checkLegality(
        'reina_eternal_cross',
        opponentPosture: CombatV1WrestlerPosture.down,
        sharedHeat: rules.finisherHeatThreshold,
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
          'reina_side_headlock',
          'reina_leg_figure_four',
          'reina_dragon_screw',
          'reina_drop_toehold',
          'reina_elbow',
          'reina_abdominal_stretch',
          'reina_arm_breaker',
          'reina_silver_crossface',
          'reina_figure_four_lock',
          'reina_ice_lock',
          'reina_eternal_cross',
        ];
        expect(standRequiredIds.length, 11);
        for (final id in standRequiredIds) {
          final isFinisher =
              reinaTechniques[id]!.category == CombatV1CardCategory.finisher;
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

    test('table-driven: DOWN始動1技がopponent STANDでopponentStateMismatch', () {
      final check = _checkLegality(
        'reina_ude_hishigi',
        opponentPosture: CombatV1WrestlerPosture.stand,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });
  });

  group('H. Counter 3定義', () {
    test('3種すべてが存在する', () {
      expect(reinaCounters.length, 3);
      expect(reinaCounters.keys.toSet(), {
        'counter_reina_leg_catch_guard',
        'counter_reina_silver_lock_reversal',
        'counter_reina_silver_flash_counter',
      });
    });

    test('広範囲型（足取りガード）: attribute=投, counterableGroups=[THROW]', () {
      final c = reinaCounters['counter_reina_leg_catch_guard']!;
      expect(c.attribute, CombatV1EnergyAttribute.throwing);
      expect(c.counterableGroups, [CombatV1TechniqueFamilyGroup.throwing]);
      expect(c.counterableFamilies, isEmpty);
    });

    test('中範囲型（白銀ロックリバーサル）: attribute=関, families=[CROSSFACE, FIGURE_FOUR]', () {
      final c = reinaCounters['counter_reina_silver_lock_reversal']!;
      expect(c.attribute, CombatV1EnergyAttribute.joint);
      expect(c.counterableFamilies, [
        CombatV1TechniqueFamily.crossface,
        CombatV1TechniqueFamily.figureFour,
      ]);
      expect(c.counterableGroups, isEmpty);
    });

    test('専門型（銀閃カウンター）: attribute=打, families=[LARIAT]', () {
      final c = reinaCounters['counter_reina_silver_flash_counter']!;
      expect(c.attribute, CombatV1EnergyAttribute.strike);
      expect(c.counterableFamilies, [CombatV1TechniqueFamily.lariat]);
      expect(c.counterableGroups, isEmpty);
    });

    test('支払い属性はいずれもwildではなく、Reinaが実際に保有する属性', () {
      for (final c in reinaCounters.values) {
        expect(c.attribute, isNot(CombatV1EnergyAttribute.wild));
        expect(
          reinaWrestler.energyPool.amountFor(c.attribute),
          greaterThan(0),
          reason: c.id,
        );
      }
    });

    test('stretch専用Counterは存在しない（A7最終回答で許容済みの仕様）', () {
      for (final c in reinaCounters.values) {
        expect(
          c.counterableFamilies,
          isNot(contains(CombatV1TechniqueFamily.stretch)),
          reason: c.id,
        );
      }
    });
  });

  group('I. ENERGY Pool', () {
    test('打2/関4/投3/飛0/ラフ0/＊1＝合計10', () {
      final pool = reinaWrestler.energyPool;
      expect(pool.amountFor(CombatV1EnergyAttribute.strike), 2);
      expect(pool.amountFor(CombatV1EnergyAttribute.joint), 4);
      expect(pool.amountFor(CombatV1EnergyAttribute.throwing), 3);
      expect(pool.amountFor(CombatV1EnergyAttribute.aerial), 0);
      expect(pool.amountFor(CombatV1EnergyAttribute.rough), 0);
      expect(pool.amountFor(CombatV1EnergyAttribute.wild), 1);
      expect(pool.amounts.values.fold(0, (a, b) => a + b), 10);
      expect(pool.isValid, isTrue);
    });

    test('Wrestler ID/nameが正式値', () {
      expect(reinaWrestler.id, 'reina');
      expect(reinaWrestler.name, '白銀レイナ');
    });
  });

  group('J/K/L. Deck 30枚・18/4/2/6・同名上限', () {
    late final deck = buildReinaDeck(ownerId: 'player-a');

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
      expect(counts['reina_side_headlock'], 3);
      expect(counts['reina_leg_figure_four'], 3);
      expect(counts['reina_dragon_screw'], 2);
      expect(counts['reina_drop_toehold'], 2);
      expect(counts['reina_elbow'], 2);
      expect(counts['reina_abdominal_stretch'], 2);
      expect(counts['reina_arm_breaker'], 2);
      expect(counts['reina_ude_hishigi'], 2);
      expect(counts['reina_silver_crossface'], 2);
      expect(counts['reina_figure_four_lock'], 2);
      expect(counts['reina_ice_lock'], 1);
      expect(counts['reina_eternal_cross'], 1);
      expect(counts['counter_reina_leg_catch_guard'], 2);
      expect(counts['counter_reina_silver_lock_reversal'], 2);
      expect(counts['counter_reina_silver_flash_counter'], 2);
    });

    test('A. 単一deck: instanceIdが30枚すべて一意', () {
      final ids = deck.entries.map((e) => e.instanceId).toSet();
      expect(ids.length, deck.size);
    });

    test('ownerIdが空文字だとArgumentErrorを送出する', () {
      expect(() => buildReinaDeck(ownerId: ''), throwsArgumentError);
      expect(() => buildReinaDeck(ownerId: '   '), throwsArgumentError);
    });

    test('B. mirror match: 同じownerId未使用なら2デッキ計60枚のinstanceIdがすべて一意', () {
      final deckA = buildReinaDeck(ownerId: 'player-a');
      final deckB = buildReinaDeck(ownerId: 'player-b');

      final idsA = deckA.entries.map((e) => e.instanceId).toSet();
      final idsB = deckB.entries.map((e) => e.instanceId).toSet();
      expect(idsA.length, 30);
      expect(idsB.length, 30);

      final cardIdsA = deckA.entries.map((e) => e.cardId).toList()..sort();
      final cardIdsB = deckB.entries.map((e) => e.cardId).toList()..sort();
      expect(cardIdsA, cardIdsB);

      final allIds = [...idsA, ...idsB];
      expect(allIds.toSet().length, 60);
    });
  });

  group('M. Catalog validation', () {
    test('productionCardCatalogはvalidateCatalogを通過する', () {
      final result = validateCatalog(productionCardCatalog);
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
    });

    test('Technique/Counter間でcardId衝突がない', () {
      final techniqueIds = reinaTechniques.keys.toSet();
      final counterIds = reinaCounters.keys.toSet();
      expect(techniqueIds.intersection(counterIds), isEmpty);
    });
  });

  group('N. Deck validation', () {
    test('buildReinaDeck()はvalidateDeckを通過する', () {
      final deck = buildReinaDeck(ownerId: 'player-a');
      final result = validateDeck(
        deck,
        catalog: productionCardCatalog,
        rules: rules,
      );
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
    });

    test('buildReinaDeck()はwrestlerId=reinaを明示しても引き続きvalid', () {
      final result = validateDeck(
        buildReinaDeck(ownerId: 'player-a'),
        catalog: productionCardCatalog,
        rules: rules,
        wrestlerId: reinaWrestler.id,
      );
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
    });
  });

  group('O/P. CombatV1Engine.start・card conservation', () {
    test('レイナ同士のミラーマッチでstartが正常に完了する', () {
      final state = CombatV1Engine.start(
        wrestlerA: reinaWrestler,
        deckA: buildReinaDeck(ownerId: 'player-a'),
        wrestlerB: reinaWrestler,
        deckB: buildReinaDeck(ownerId: 'player-b'),
        rules: rules,
        catalog: productionCardCatalog,
      );

      expect(state.playerA.wrestlerId, 'reina');
      expect(state.playerB.wrestlerId, 'reina');
      expect(state.phase, CombatV1MatchPhase.discard);
      expect(state.playerA.hp, rules.startingHp);
      expect(state.playerB.hp, rules.startingHp);

      final result = validateMatchStateInvariants(state, rules: rules);
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
      expect(_allInstanceIds(state).toSet().length, 60);
    });

    test('start直後、両プレイヤーのカード総数がデッキ枚数(30)と一致する（card conservation）', () {
      final state = CombatV1Engine.start(
        wrestlerA: reinaWrestler,
        deckA: buildReinaDeck(ownerId: 'player-a'),
        wrestlerB: reinaWrestler,
        deckB: buildReinaDeck(ownerId: 'player-b'),
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
      expect(totalA + totalB, 60);
      expect(_allInstanceIds(state).toSet().length, 60);
      expect(state.playerA.hand.length, rules.startingHandSize + 1);
    });

    test(
      'declareTechnique→declineCounterの1経路を通してもinstanceId衝突・'
      'pending ownership違反が起きない',
      () {
        final random = Random(20260810);
        final started = CombatV1Engine.start(
          wrestlerA: reinaWrestler,
          deckA: buildReinaDeck(ownerId: 'player-a'),
          wrestlerB: reinaWrestler,
          deckB: buildReinaDeck(ownerId: 'player-b'),
          rules: rules,
          catalog: productionCardCatalog,
          random: random,
        );

        final discardEntry = started.playerA.hand.first;
        final afterDiscard = CombatV1Engine.discardCard(
          started,
          discardEntry.instanceId,
        );
        expect(afterDiscard.phase, CombatV1MatchPhase.action);

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

        final pendingResult = validateMatchStateInvariants(
          declared,
          rules: rules,
        );
        expect(
          pendingResult.isValid,
          isTrue,
          reason: pendingResult.errors.join(' / '),
        );
        expect(_allInstanceIds(declared).toSet().length, 60);

        final resolved = CombatV1Engine.declineCounter(
          declared,
          rules: rules,
          random: random,
        );
        expect(resolved.phase, CombatV1MatchPhase.action);
        expect(resolved.pendingAttack, isNull);

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
        expect(
          resolvedResult.isValid,
          isTrue,
          reason: resolvedResult.errors.join(' / '),
        );
        expect(_allInstanceIds(resolved).toSet().length, 60);

        expect(
          resolved.playerA.discardPile.any(
            (e) => e.instanceId == attackEntry.instanceId,
          ),
          isTrue,
        );
      },
    );

    test(
      'declareTechnique→playCounterの1経路（COUNTER mirror test）を'
      '通しても、両player全ゾーン+pendingでinstanceId衝突が起きない',
      () {
        // 攻撃側手札にreina_dragon_screw（family=legTakedown、group=THROW）、
        // 防御側手札にcounter_reina_leg_catch_guard
        // （counterableGroups=[THROW]）を直接配置し、COUNTER成立まで
        // 通す最小構成でcard flow/instanceId整合を検証する。
        final playerA = CombatV1PlayerState(
          wrestlerId: reinaWrestler.id,
          wrestlerName: reinaWrestler.name,
          maxHp: rules.startingHp,
          hp: rules.startingHp,
          koc: rules.startingKoc,
          pinCardsHeld: rules.startingPinCards,
          energyPool: reinaWrestler.energyPool,
          hand: const [
            CombatV1DeckEntry(
              instanceId: 'player-a_reina_dragon_screw_#0',
              cardId: 'reina_dragon_screw',
              category: CombatV1CardCategory.normal,
            ),
          ],
          drawPile: const [
            CombatV1DeckEntry(
              instanceId: 'player-a_reina_elbow_#0',
              cardId: 'reina_elbow',
              category: CombatV1CardCategory.normal,
            ),
          ],
        );
        final playerB = CombatV1PlayerState(
          wrestlerId: reinaWrestler.id,
          wrestlerName: reinaWrestler.name,
          maxHp: rules.startingHp,
          hp: rules.startingHp,
          koc: rules.startingKoc,
          pinCardsHeld: rules.startingPinCards,
          energyPool: reinaWrestler.energyPool,
          hand: const [
            CombatV1DeckEntry(
              instanceId: 'player-b_counter_reina_leg_catch_guard_#0',
              cardId: 'counter_reina_leg_catch_guard',
              category: CombatV1CardCategory.counter,
            ),
          ],
          drawPile: const [
            CombatV1DeckEntry(
              instanceId: 'player-b_reina_side_headlock_#0',
              cardId: 'reina_side_headlock',
              category: CombatV1CardCategory.normal,
            ),
          ],
        );
        final state = CombatV1MatchState(
          matchId: 'phase10c-reina-counter-mirror-test',
          playerA: playerA,
          playerB: playerB,
          activePlayerIndex: 0,
          phase: CombatV1MatchPhase.action,
        );

        final declared = CombatV1Engine.declareTechnique(
          state,
          'player-a_reina_dragon_screw_#0',
          catalog: productionCardCatalog,
          rules: rules,
        );
        expect(declared.phase, CombatV1MatchPhase.counterResponsePending);

        final countered = CombatV1Engine.playCounter(
          declared,
          'player-b_counter_reina_leg_catch_guard_#0',
          catalog: productionCardCatalog,
          rules: rules,
        );
        expect(countered.phase, CombatV1MatchPhase.action);
        expect(countered.pendingAttack, isNull);

        expect(
          countered.playerA.discardPile.any(
            (e) => e.instanceId == 'player-a_reina_dragon_screw_#0',
          ),
          isTrue,
        );
        expect(
          countered.playerB.discardPile.any(
            (e) => e.instanceId == 'player-b_counter_reina_leg_catch_guard_#0',
          ),
          isTrue,
        );

        final result = validateMatchStateInvariants(countered, rules: rules);
        expect(result.isValid, isTrue, reason: result.errors.join(' / '));
        expect(_allInstanceIds(countered).toSet().length, 4);
      },
    );
  });

  group('Q. Production DataをDomain lookupできる（Simulator/UI非依存）', () {
    test('productionCardCatalog.containsCardIdで全12技・3 Counterを参照できる', () {
      for (final id in reinaTechniques.keys) {
        expect(productionCardCatalog.containsCardId(id), isTrue, reason: id);
      }
      for (final id in reinaCounters.keys) {
        expect(productionCardCatalog.containsCardId(id), isTrue, reason: id);
      }
    });

    test('categoryOfが各カードの正しいcategoryを返す', () {
      expect(
        productionCardCatalog.categoryOf('reina_side_headlock'),
        CombatV1CardCategory.normal,
      );
      expect(
        productionCardCatalog.categoryOf('reina_silver_crossface'),
        CombatV1CardCategory.signature,
      );
      expect(
        productionCardCatalog.categoryOf('reina_ice_lock'),
        CombatV1CardCategory.finisher,
      );
      expect(
        productionCardCatalog.categoryOf('counter_reina_leg_catch_guard'),
        CombatV1CardCategory.counter,
      );
    });
  });
}
