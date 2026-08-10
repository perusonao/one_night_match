/// Phase 10C Production Data integration test（火神アカリ）。
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
/// 同じ方針だが、実際の[akariWrestler]（Production ENERGY Pool）を使う）。
CombatV1MatchState _buildAkariLegalityState({
  required CombatV1WrestlerPosture opponentPosture,
  required List<CombatV1DeckEntry> handA,
  int sharedHeat = 0,
}) {
  final playerA = CombatV1PlayerState(
    wrestlerId: akariWrestler.id,
    wrestlerName: akariWrestler.name,
    maxHp: rules.startingHp,
    hp: rules.startingHp,
    koc: rules.startingKoc,
    pinCardsHeld: rules.startingPinCards,
    posture: CombatV1WrestlerPosture.stand,
    energyPool: akariWrestler.energyPool,
    hand: handA,
  );
  final playerB = CombatV1PlayerState(
    wrestlerId: akariWrestler.id,
    wrestlerName: akariWrestler.name,
    maxHp: rules.startingHp,
    hp: rules.startingHp,
    koc: rules.startingKoc,
    pinCardsHeld: rules.startingPinCards,
    posture: opponentPosture,
    energyPool: akariWrestler.energyPool,
  );
  return CombatV1MatchState(
    matchId: 'phase10c-akari-legality-test',
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
  final category = akariTechniques[cardId]!.category;
  final state = _buildAkariLegalityState(
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
  group('A/B. アカリTechnique 12定義', () {
    test('12技すべてがcatalogに存在する', () {
      expect(akariTechniques.length, 12);
    });

    test('全Technique IDが一意（Mapのキー自体が保証するが、id fieldとの整合も確認）', () {
      final ids = akariTechniques.values.map((t) => t.id).toSet();
      expect(ids.length, 12);
      expect(akariTechniques.keys.toSet(), ids);
    });
  });

  group('C. Technique family', () {
    const expectedFamilies = {
      'akari_elbow_smash': CombatV1TechniqueFamily.elbow,
      'akari_middle_kick': CombatV1TechniqueFamily.kick,
      'akari_dropkick': CombatV1TechniqueFamily.dropKick,
      'akari_running_knee': CombatV1TechniqueFamily.knee,
      'akari_arm_whip': CombatV1TechniqueFamily.armDrag,
      'akari_flying_crossbody': CombatV1TechniqueFamily.bodyPress,
      'akari_swing_ddt': CombatV1TechniqueFamily.ddt,
      'akari_arm_catch': CombatV1TechniqueFamily.armbar,
      'akari_phoenix_armdrag': CombatV1TechniqueFamily.armDrag,
      'akari_soul_highkick': CombatV1TechniqueFamily.kick,
      'akari_phoenix_splash': CombatV1TechniqueFamily.splash,
      'akari_red_flare_kick': CombatV1TechniqueFamily.kick,
    };

    for (final entry in expectedFamilies.entries) {
      test('${entry.key} → ${entry.value.name}', () {
        expect(akariTechniques[entry.key]!.family, entry.value);
      });
    }
  });

  group(
    'D/E/F. Cost・DMG・HEAT・state（Phase 10C Production Data Final Specification 2章）',
    () {
      test('エルボースマッシュ: 打1/DMG10/HEAT10/STAND→STAND', () {
        final t = akariTechniques['akari_elbow_smash']!;
        expect(t.category, CombatV1CardCategory.normal);
        expect(t.attribute, CombatV1EnergyAttribute.strike);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 1);
        expect(t.energyCost.total, 1);
        expect(t.damage, 10);
        expect(t.heatGain, 10);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, isNull);
        expect(t.directPin, isFalse);
        expect(t.submissionHold, isFalse);
      });

      test('ミドルキック: 打1/DMG10/HEAT10/STAND→STAND', () {
        final t = akariTechniques['akari_middle_kick']!;
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 1);
        expect(t.damage, 10);
        expect(t.heatGain, 10);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, isNull);
      });

      test('ドロップキック: 飛1/DMG10/HEAT20/STAND→DOWN', () {
        final t = akariTechniques['akari_dropkick']!;
        expect(t.attribute, CombatV1EnergyAttribute.aerial);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.aerial), 1);
        expect(t.damage, 10);
        expect(t.heatGain, 20);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
      });

      test('ランニングニー: 打2/DMG20/HEAT20/STAND→DOWN', () {
        final t = akariTechniques['akari_running_knee']!;
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 2);
        expect(t.damage, 20);
        expect(t.heatGain, 20);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
      });

      test('アームホイップ: 投1/DMG10/HEAT10/STAND→STAND', () {
        final t = akariTechniques['akari_arm_whip']!;
        expect(t.attribute, CombatV1EnergyAttribute.throwing);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 1);
        expect(t.damage, 10);
        expect(t.heatGain, 10);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, isNull);
      });

      test('フライングクロスボディ: 飛2/DMG20/HEAT20/DOWN→DOWN', () {
        final t = akariTechniques['akari_flying_crossbody']!;
        expect(t.attribute, CombatV1EnergyAttribute.aerial);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.aerial), 2);
        expect(t.damage, 20);
        expect(t.heatGain, 20);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.down);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
      });

      test('スイングDDT: 投2/DMG20/HEAT20/STAND→DOWN', () {
        final t = akariTechniques['akari_swing_ddt']!;
        expect(t.attribute, CombatV1EnergyAttribute.throwing);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 2);
        expect(t.damage, 20);
        expect(t.heatGain, 20);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
      });

      test('アームキャッチ: 関1/DMG10/HEAT10/STAND→STAND/submissionHold=true', () {
        final t = akariTechniques['akari_arm_catch']!;
        expect(t.attribute, CombatV1EnergyAttribute.joint);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.joint), 1);
        expect(t.damage, 10);
        expect(t.heatGain, 10);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, isNull);
        expect(t.directPin, isFalse);
        expect(t.submissionHold, isTrue);
      });

      test('フェニックス・アームドラッグ: SIGNATURE/投2/DMG20/HEAT30/STAND→DOWN', () {
        final t = akariTechniques['akari_phoenix_armdrag']!;
        expect(t.category, CombatV1CardCategory.signature);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 2);
        expect(t.damage, 20);
        expect(t.heatGain, 30);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
      });

      test('ソウルハイキック: SIGNATURE/打3/DMG30/HEAT40/STAND→DOWN', () {
        final t = akariTechniques['akari_soul_highkick']!;
        expect(t.category, CombatV1CardCategory.signature);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 3);
        expect(t.damage, 30);
        expect(t.heatGain, 40);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
      });

      test('フェニックススプラッシュ: FINISHER/飛3/DMG30/HEAT40/DOWN→DOWN', () {
        final t = akariTechniques['akari_phoenix_splash']!;
        expect(t.category, CombatV1CardCategory.finisher);
        expect(t.attribute, CombatV1EnergyAttribute.aerial);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.aerial), 3);
        expect(t.damage, 30);
        expect(t.heatGain, 40);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.down);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
      });

      test('レッドフレアキック: FINISHER/打3/DMG30/HEAT50/STAND→DOWN', () {
        final t = akariTechniques['akari_red_flare_kick']!;
        expect(t.category, CombatV1CardCategory.finisher);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 3);
        expect(t.damage, 30);
        expect(t.heatGain, 50);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
      });

      test('STAND始動10技すべてがrequiredOpponentState==standを持つ（regression防止）', () {
        const standRequiredIds = [
          'akari_elbow_smash',
          'akari_middle_kick',
          'akari_dropkick',
          'akari_running_knee',
          'akari_arm_whip',
          'akari_swing_ddt',
          'akari_arm_catch',
          'akari_phoenix_armdrag',
          'akari_soul_highkick',
          'akari_red_flare_kick',
        ];
        expect(standRequiredIds.length, 10);
        for (final id in standRequiredIds) {
          expect(
            akariTechniques[id]!.requiredOpponentState,
            CombatV1WrestlerPosture.stand,
            reason: '$idはrequiredOpponentState==standである必要があります',
          );
        }
        // フライングクロスボディ・フェニックススプラッシュのみDOWN始動
        // （2章、Akariのコンボ構造「ダウンを奪う→飛び技」）。
        for (final id in ['akari_flying_crossbody', 'akari_phoenix_splash']) {
          expect(
            akariTechniques[id]!.requiredOpponentState,
            CombatV1WrestlerPosture.down,
            reason: id,
          );
        }
        // 12技すべてがrequiredOpponentStateを明示的に持つ
        // （nullは「STAND/DOWNどちらでも可」を意味するため、未設定のまま
        // 残っている技が無いことを保証する）。
        for (final t in akariTechniques.values) {
          expect(
            t.requiredOpponentState,
            isNotNull,
            reason: '${t.id}はrequiredOpponentStateが未設定です',
          );
        }
      });
    },
  );

  group('G. FINISHER type', () {
    test('フェニックススプラッシュ: finisherType == directPin', () {
      expect(
        akariTechniques['akari_phoenix_splash']!.finisherType,
        CombatV1FinisherType.directPin,
      );
    });

    test('レッドフレアキック: finisherType == normal', () {
      expect(
        akariTechniques['akari_red_flare_kick']!.finisherType,
        CombatV1FinisherType.normal,
      );
    });

    test('NORMAL/SIGNATUREの全技はfinisherType == null', () {
      for (final t in akariTechniques.values) {
        if (t.category == CombatV1CardCategory.finisher) continue;
        expect(t.finisherType, isNull, reason: '${t.id}はcategory!=finisherです');
      }
    });

    test('全技のhasConsistentFinisherTypeがtrue', () {
      for (final t in akariTechniques.values) {
        expect(t.hasConsistentFinisherType, isTrue, reason: t.id);
      }
    });

    test('FINISHERはdirectPin/submissionHoldのstray設定を持たない', () {
      for (final t in akariTechniques.values) {
        if (t.category != CombatV1CardCategory.finisher) continue;
        expect(t.directPin, isFalse, reason: t.id);
        expect(t.submissionHold, isFalse, reason: t.id);
      }
    });
  });

  group('R. Technique state legality（Codexレビュー指摘の再発防止）', () {
    test('A. エルボースマッシュ: opponent DOWN → illegal（opponentStateMismatch）', () {
      final check = _checkLegality(
        'akari_elbow_smash',
        opponentPosture: CombatV1WrestlerPosture.down,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('B. フライングクロスボディ: opponent STAND → illegal（opponentStateMismatch）', () {
      final check = _checkLegality(
        'akari_flying_crossbody',
        opponentPosture: CombatV1WrestlerPosture.stand,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('C. フライングクロスボディ: opponent DOWN → state条件はlegal（ENERGY等も充足）', () {
      final check = _checkLegality(
        'akari_flying_crossbody',
        opponentPosture: CombatV1WrestlerPosture.down,
      );
      expect(check.legal, isTrue);
      expect(check.reasonCode, CombatV1TechniqueLegalityReasonCode.legal);
    });

    test('D. フェニックススプラッシュ（FINISHER）: HEAT解禁済みでもopponent STAND → illegal', () {
      final check = _checkLegality(
        'akari_phoenix_splash',
        opponentPosture: CombatV1WrestlerPosture.stand,
        sharedHeat: rules.finisherHeatThreshold,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test(
      'E. フェニックススプラッシュ（FINISHER）: HEAT解禁済み・opponent DOWNならlegal'
      '（飛3コストは保有プール飛2+wild1で支払い可能）',
      () {
        final check = _checkLegality(
          'akari_phoenix_splash',
          opponentPosture: CombatV1WrestlerPosture.down,
          sharedHeat: rules.finisherHeatThreshold,
        );
        expect(check.legal, isTrue);
        expect(check.reasonCode, CombatV1TechniqueLegalityReasonCode.legal);
      },
    );

    test('F. フェニックススプラッシュ: HEAT不足なら finisherHeatNotReached', () {
      final check = _checkLegality(
        'akari_phoenix_splash',
        opponentPosture: CombatV1WrestlerPosture.down,
        sharedHeat: rules.finisherHeatThreshold - 10,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.finisherHeatNotReached,
      );
    });

    test('G. レッドフレアキック（FINISHER）: HEAT解禁済みでもopponent DOWN → illegal', () {
      final check = _checkLegality(
        'akari_red_flare_kick',
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
      'table-driven: STAND始動10技すべてがopponent DOWNでopponentStateMismatch'
      '（requiredOpponentStateが誤ってnullへ戻るregressionを防止）',
      () {
        const standRequiredIds = [
          'akari_elbow_smash',
          'akari_middle_kick',
          'akari_dropkick',
          'akari_running_knee',
          'akari_arm_whip',
          'akari_swing_ddt',
          'akari_arm_catch',
          'akari_phoenix_armdrag',
          'akari_soul_highkick',
          'akari_red_flare_kick',
        ];
        expect(standRequiredIds.length, 10);
        for (final id in standRequiredIds) {
          final isFinisher =
              akariTechniques[id]!.category == CombatV1CardCategory.finisher;
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

    test(
      'table-driven: DOWN始動2技すべてがopponent STANDでopponentStateMismatch',
      () {
        const downRequiredIds = ['akari_flying_crossbody', 'akari_phoenix_splash'];
        for (final id in downRequiredIds) {
          final isFinisher =
              akariTechniques[id]!.category == CombatV1CardCategory.finisher;
          final check = _checkLegality(
            id,
            opponentPosture: CombatV1WrestlerPosture.stand,
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
      expect(akariCounters.length, 3);
      expect(akariCounters.keys.toSet(), {
        'counter_akari_crimson_guard',
        'counter_akari_phoenix_throw_reversal',
        'counter_akari_sky_intercept',
      });
    });

    test('広範囲型（紅蓮ガード）: attribute=打, counterableGroups=[STRIKE]', () {
      final c = akariCounters['counter_akari_crimson_guard']!;
      expect(c.attribute, CombatV1EnergyAttribute.strike);
      expect(c.counterableGroups, [CombatV1TechniqueFamilyGroup.strike]);
      expect(c.counterableFamilies, isEmpty);
    });

    test('中範囲型（フェニックス投げ返し）: attribute=投, families=[BACKDROP, SUPLEX]', () {
      final c = akariCounters['counter_akari_phoenix_throw_reversal']!;
      expect(c.attribute, CombatV1EnergyAttribute.throwing);
      expect(c.counterableFamilies, [
        CombatV1TechniqueFamily.backdrop,
        CombatV1TechniqueFamily.suplex,
      ]);
      expect(c.counterableGroups, isEmpty);
    });

    test('専門型（スカイインターセプト）: attribute=飛, families=[SPLASH]', () {
      final c = akariCounters['counter_akari_sky_intercept']!;
      expect(c.attribute, CombatV1EnergyAttribute.aerial);
      expect(c.counterableFamilies, [CombatV1TechniqueFamily.splash]);
      expect(c.counterableGroups, isEmpty);
    });

    test('支払い属性はいずれもwildではなく、Akariが実際に保有する属性', () {
      for (final c in akariCounters.values) {
        expect(c.attribute, isNot(CombatV1EnergyAttribute.wild));
        expect(
          akariWrestler.energyPool.amountFor(c.attribute),
          greaterThan(0),
          reason: c.id,
        );
      }
    });
  });

  group('I. ENERGY Pool', () {
    test('打5/関1/投2/飛2/ラフ0/＊1＝合計11', () {
      final pool = akariWrestler.energyPool;
      expect(pool.amountFor(CombatV1EnergyAttribute.strike), 5);
      expect(pool.amountFor(CombatV1EnergyAttribute.joint), 1);
      expect(pool.amountFor(CombatV1EnergyAttribute.throwing), 2);
      expect(pool.amountFor(CombatV1EnergyAttribute.aerial), 2);
      expect(pool.amountFor(CombatV1EnergyAttribute.rough), 0);
      expect(pool.amountFor(CombatV1EnergyAttribute.wild), 1);
      expect(pool.amounts.values.fold(0, (a, b) => a + b), 11);
      expect(pool.isValid, isTrue);
    });

    test('Wrestler ID/nameが正式値', () {
      expect(akariWrestler.id, 'akari');
      expect(akariWrestler.name, '火神アカリ');
    });
  });

  group('J/K/L. Deck 30枚・18/4/2/6・同名上限', () {
    late final deck = buildAkariDeck(ownerId: 'player-a');

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
      expect(counts['akari_elbow_smash'], 3);
      expect(counts['akari_middle_kick'], 3);
      expect(counts['akari_dropkick'], 2);
      expect(counts['akari_running_knee'], 2);
      expect(counts['akari_arm_whip'], 2);
      expect(counts['akari_flying_crossbody'], 2);
      expect(counts['akari_swing_ddt'], 2);
      expect(counts['akari_arm_catch'], 2);
      expect(counts['akari_phoenix_armdrag'], 2);
      expect(counts['akari_soul_highkick'], 2);
      expect(counts['akari_phoenix_splash'], 1);
      expect(counts['akari_red_flare_kick'], 1);
      expect(counts['counter_akari_crimson_guard'], 2);
      expect(counts['counter_akari_phoenix_throw_reversal'], 2);
      expect(counts['counter_akari_sky_intercept'], 2);
    });

    test('A. 単一deck: instanceIdが30枚すべて一意', () {
      final ids = deck.entries.map((e) => e.instanceId).toSet();
      expect(ids.length, deck.size);
    });

    test('ownerIdが空文字だとArgumentErrorを送出する', () {
      expect(() => buildAkariDeck(ownerId: ''), throwsArgumentError);
      expect(() => buildAkariDeck(ownerId: '   '), throwsArgumentError);
    });

    test('B. mirror match: 同じownerId未使用なら2デッキ計60枚のinstanceIdがすべて一意', () {
      final deckA = buildAkariDeck(ownerId: 'player-a');
      final deckB = buildAkariDeck(ownerId: 'player-b');

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
      final techniqueIds = akariTechniques.keys.toSet();
      final counterIds = akariCounters.keys.toSet();
      expect(techniqueIds.intersection(counterIds), isEmpty);
    });
  });

  group('N. Deck validation', () {
    test('buildAkariDeck()はvalidateDeckを通過する', () {
      final deck = buildAkariDeck(ownerId: 'player-a');
      final result = validateDeck(
        deck,
        catalog: productionCardCatalog,
        rules: rules,
      );
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
    });

    test('buildAkariDeck()はwrestlerId=akariを明示しても引き続きvalid', () {
      final result = validateDeck(
        buildAkariDeck(ownerId: 'player-a'),
        catalog: productionCardCatalog,
        rules: rules,
        wrestlerId: akariWrestler.id,
      );
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
    });
  });

  group('O/P. CombatV1Engine.start・card conservation', () {
    test('アカリ同士のミラーマッチでstartが正常に完了する', () {
      final state = CombatV1Engine.start(
        wrestlerA: akariWrestler,
        deckA: buildAkariDeck(ownerId: 'player-a'),
        wrestlerB: akariWrestler,
        deckB: buildAkariDeck(ownerId: 'player-b'),
        rules: rules,
        catalog: productionCardCatalog,
      );

      expect(state.playerA.wrestlerId, 'akari');
      expect(state.playerB.wrestlerId, 'akari');
      expect(state.phase, CombatV1MatchPhase.discard);
      expect(state.playerA.hp, rules.startingHp);
      expect(state.playerB.hp, rules.startingHp);

      final result = validateMatchStateInvariants(state, rules: rules);
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
      expect(_allInstanceIds(state).toSet().length, 60);
    });

    test('start直後、両プレイヤーのカード総数がデッキ枚数(30)と一致する（card conservation）', () {
      final state = CombatV1Engine.start(
        wrestlerA: akariWrestler,
        deckA: buildAkariDeck(ownerId: 'player-a'),
        wrestlerB: akariWrestler,
        deckB: buildAkariDeck(ownerId: 'player-b'),
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
          wrestlerA: akariWrestler,
          deckA: buildAkariDeck(ownerId: 'player-a'),
          wrestlerB: akariWrestler,
          deckB: buildAkariDeck(ownerId: 'player-b'),
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
        // 攻撃側手札にakari_middle_kick（family=kick、group=STRIKE）、
        // 防御側手札にcounter_akari_crimson_guard
        // （counterableGroups=[STRIKE]）を直接配置し、COUNTER成立まで
        // 通す最小構成でcard flow/instanceId整合を検証する。
        final playerA = CombatV1PlayerState(
          wrestlerId: akariWrestler.id,
          wrestlerName: akariWrestler.name,
          maxHp: rules.startingHp,
          hp: rules.startingHp,
          koc: rules.startingKoc,
          pinCardsHeld: rules.startingPinCards,
          energyPool: akariWrestler.energyPool,
          hand: const [
            CombatV1DeckEntry(
              instanceId: 'player-a_akari_middle_kick_#1',
              cardId: 'akari_middle_kick',
              category: CombatV1CardCategory.normal,
            ),
          ],
          drawPile: const [
            CombatV1DeckEntry(
              instanceId: 'player-a_akari_arm_whip_#0',
              cardId: 'akari_arm_whip',
              category: CombatV1CardCategory.normal,
            ),
          ],
        );
        final playerB = CombatV1PlayerState(
          wrestlerId: akariWrestler.id,
          wrestlerName: akariWrestler.name,
          maxHp: rules.startingHp,
          hp: rules.startingHp,
          koc: rules.startingKoc,
          pinCardsHeld: rules.startingPinCards,
          energyPool: akariWrestler.energyPool,
          hand: const [
            CombatV1DeckEntry(
              instanceId: 'player-b_counter_akari_crimson_guard_#0',
              cardId: 'counter_akari_crimson_guard',
              category: CombatV1CardCategory.counter,
            ),
          ],
          drawPile: const [
            CombatV1DeckEntry(
              instanceId: 'player-b_akari_elbow_smash_#0',
              cardId: 'akari_elbow_smash',
              category: CombatV1CardCategory.normal,
            ),
          ],
        );
        final state = CombatV1MatchState(
          matchId: 'phase10c-akari-counter-mirror-test',
          playerA: playerA,
          playerB: playerB,
          activePlayerIndex: 0,
          phase: CombatV1MatchPhase.action,
        );

        final declared = CombatV1Engine.declareTechnique(
          state,
          'player-a_akari_middle_kick_#1',
          catalog: productionCardCatalog,
          rules: rules,
        );
        expect(declared.phase, CombatV1MatchPhase.counterResponsePending);

        final countered = CombatV1Engine.playCounter(
          declared,
          'player-b_counter_akari_crimson_guard_#0',
          catalog: productionCardCatalog,
          rules: rules,
        );
        expect(countered.phase, CombatV1MatchPhase.action);
        expect(countered.pendingAttack, isNull);

        expect(
          countered.playerA.discardPile.any(
            (e) => e.instanceId == 'player-a_akari_middle_kick_#1',
          ),
          isTrue,
        );
        expect(
          countered.playerB.discardPile.any(
            (e) => e.instanceId == 'player-b_counter_akari_crimson_guard_#0',
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
      for (final id in akariTechniques.keys) {
        expect(productionCardCatalog.containsCardId(id), isTrue, reason: id);
      }
      for (final id in akariCounters.keys) {
        expect(productionCardCatalog.containsCardId(id), isTrue, reason: id);
      }
    });

    test('categoryOfが各カードの正しいcategoryを返す', () {
      expect(
        productionCardCatalog.categoryOf('akari_elbow_smash'),
        CombatV1CardCategory.normal,
      );
      expect(
        productionCardCatalog.categoryOf('akari_phoenix_armdrag'),
        CombatV1CardCategory.signature,
      );
      expect(
        productionCardCatalog.categoryOf('akari_phoenix_splash'),
        CombatV1CardCategory.finisher,
      );
      expect(
        productionCardCatalog.categoryOf('counter_akari_crimson_guard'),
        CombatV1CardCategory.counter,
      );
    });
  });
}
