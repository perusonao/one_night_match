/// Phase 10B Production Data integration test（黒蝶ジャック）。
///
/// `test/combat_v1/combat_v1_test_fixtures.dart`のfixture（`fx_*`）は既存Core
/// Engine testsが引き続き参照するため変更しない（docs/combat_rules_v1.md 26章
/// 「Phase 10」の方針）。本ファイルは`lib/src/combat_v1/combat_v1_wrestler_catalog.dart`
/// ／`combat_v1_technique_catalog.dart`／`combat_v1_counter_catalog.dart`
/// ／`combat_v1_decks.dart`／`combat_v1_production_catalog.dart`が持つ、黒蝶ジャックの
/// 正式Production Dataそのものを検証する（`combat_v1_production_misaki_test.dart`と
/// 同じ構成に揃える）。加えて、Jack vs Jackミラーマッチ・Misaki vs Jack
/// クロスレスラーの回帰テスト（Phase 10A GitHub Codexレビュー指摘の再発防止）を含む。
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
/// （`combat_v1_production_misaki_test.dart`の`_buildMisakiLegalityState`と同じ
/// 方針だが、[jackWrestler]（Production ENERGY Pool）を使う）。
CombatV1MatchState _buildJackLegalityState({
  required CombatV1WrestlerPosture opponentPosture,
  required List<CombatV1DeckEntry> handA,
  int sharedHeat = 0,
}) {
  final playerA = CombatV1PlayerState(
    wrestlerId: jackWrestler.id,
    wrestlerName: jackWrestler.name,
    maxHp: rules.startingHp,
    hp: rules.startingHp,
    koc: rules.startingKoc,
    pinCardsHeld: rules.startingPinCards,
    posture: CombatV1WrestlerPosture.stand,
    energyPool: jackWrestler.energyPool,
    hand: handA,
  );
  final playerB = CombatV1PlayerState(
    wrestlerId: jackWrestler.id,
    wrestlerName: jackWrestler.name,
    maxHp: rules.startingHp,
    hp: rules.startingHp,
    koc: rules.startingKoc,
    pinCardsHeld: rules.startingPinCards,
    posture: opponentPosture,
    energyPool: jackWrestler.energyPool,
  );
  return CombatV1MatchState(
    matchId: 'phase10b-legality-test',
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
  final category = jackTechniques[cardId]!.category;
  final state = _buildJackLegalityState(
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
  group('A/B. ジャックTechnique 12定義', () {
    test('12技すべてがcatalogに存在する', () {
      expect(jackTechniques.length, 12);
    });

    test('全Technique IDが一意（Mapのキー自体が保証するが、id fieldとの整合も確認）', () {
      final ids = jackTechniques.values.map((t) => t.id).toSet();
      expect(ids.length, 12);
      expect(jackTechniques.keys.toSet(), ids);
    });
  });

  group('C. Technique family', () {
    const expectedFamilies = {
      'jack_choke_attack': CombatV1TechniqueFamily.choke,
      'jack_face_claw': CombatV1TechniqueFamily.claw,
      'jack_sneak_kick': CombatV1TechniqueFamily.kick,
      'jack_elbow': CombatV1TechniqueFamily.elbow,
      'jack_sneak_lariat': CombatV1TechniqueFamily.lariat,
      'jack_suplex': CombatV1TechniqueFamily.suplex,
      'jack_armlock': CombatV1TechniqueFamily.armbar,
      'jack_finishing_stomp': CombatV1TechniqueFamily.stomp,
      'jack_kurocho_crash': CombatV1TechniqueFamily.tackle,
      'jack_knee_drop': CombatV1TechniqueFamily.knee,
      'jack_kurocho_driver': CombatV1TechniqueFamily.driver,
      'jack_black_jack': CombatV1TechniqueFamily.lariat,
    };

    for (final entry in expectedFamilies.entries) {
      test('${entry.key} → ${entry.value.name}', () {
        expect(jackTechniques[entry.key]!.family, entry.value);
      });
    }
  });

  group(
    'D/E/F. Cost・DMG・HEAT・state（docs/combat_rules_v1.md 20章・Phase 10B確定値）',
    () {
      test('チョーク攻撃: ラフ1/DMG10/HEAT20/STAND→STAND（23.4章のCHOKE例）', () {
        final t = jackTechniques['jack_choke_attack']!;
        expect(t.category, CombatV1CardCategory.normal);
        expect(t.attribute, CombatV1EnergyAttribute.rough);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.rough), 1);
        expect(t.energyCost.total, 1);
        expect(t.damage, 10);
        expect(t.heatGain, 20);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, isNull);
      });

      test('顔面かきむしり: ラフ1/DMG10/HEAT20/STAND→STAND', () {
        final t = jackTechniques['jack_face_claw']!;
        expect(t.attribute, CombatV1EnergyAttribute.rough);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.rough), 1);
        expect(t.damage, 10);
        expect(t.heatGain, 20);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, isNull);
      });

      test('闇討ちキック: 打1/DMG10/HEAT10/STAND→STAND', () {
        final t = jackTechniques['jack_sneak_kick']!;
        expect(t.attribute, CombatV1EnergyAttribute.strike);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 1);
        expect(t.damage, 10);
        expect(t.heatGain, 10);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, isNull);
      });

      test('黒蝶エルボー: 打1/DMG10/HEAT10/STAND→STAND', () {
        final t = jackTechniques['jack_elbow']!;
        expect(t.attribute, CombatV1EnergyAttribute.strike);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 1);
        expect(t.damage, 10);
        expect(t.heatGain, 10);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, isNull);
      });

      test('闇討ちラリアット: 打2/DMG20/HEAT20/STAND→DOWN', () {
        final t = jackTechniques['jack_sneak_lariat']!;
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 2);
        expect(t.damage, 20);
        expect(t.heatGain, 20);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
      });

      test('黒蝶スープレックス: 投1/DMG10/HEAT10/STAND→STAND', () {
        final t = jackTechniques['jack_suplex']!;
        expect(t.attribute, CombatV1EnergyAttribute.throwing);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.throwing), 1);
        expect(t.damage, 10);
        expect(t.heatGain, 10);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, isNull);
      });

      test('アームロック: 関1/DMG10/HEAT10/STAND→STAND', () {
        final t = jackTechniques['jack_armlock']!;
        expect(t.attribute, CombatV1EnergyAttribute.joint);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.joint), 1);
        expect(t.damage, 10);
        expect(t.heatGain, 10);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, isNull);
      });

      test('とどめの踏みつけ: 打1/DMG10/HEAT20/DOWN→DOWN（20章「踏みつけは通常技」）', () {
        final t = jackTechniques['jack_finishing_stomp']!;
        expect(t.attribute, CombatV1EnergyAttribute.strike);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 1);
        expect(t.damage, 10);
        expect(t.heatGain, 20);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.down);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
      });

      test('黒蝶クラッシュ: SIGNATURE/ラフ2/DMG20/HEAT40/STAND→DOWN', () {
        final t = jackTechniques['jack_kurocho_crash']!;
        expect(t.category, CombatV1CardCategory.signature);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.rough), 2);
        expect(t.damage, 20);
        expect(t.heatGain, 40);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
      });

      test('黒蝶ニードロップ: SIGNATURE/打2/DMG20/HEAT30/STAND→DOWN', () {
        final t = jackTechniques['jack_knee_drop']!;
        expect(t.category, CombatV1CardCategory.signature);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 2);
        expect(t.damage, 20);
        expect(t.heatGain, 30);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
      });

      test('黒蝶ドライバー: FINISHER/ラフ3/DMG30/HEAT50/STAND→DOWN', () {
        final t = jackTechniques['jack_kurocho_driver']!;
        expect(t.category, CombatV1CardCategory.finisher);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.rough), 3);
        expect(t.damage, 30);
        expect(t.heatGain, 50);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
      });

      test('ブラック・ジャック: FINISHER/打3/DMG30/HEAT50/STAND→DOWN', () {
        final t = jackTechniques['jack_black_jack']!;
        expect(t.category, CombatV1CardCategory.finisher);
        expect(t.energyCost.amountFor(CombatV1EnergyAttribute.strike), 3);
        expect(t.damage, 30);
        expect(t.heatGain, 50);
        expect(t.requiredOpponentState, CombatV1WrestlerPosture.stand);
        expect(t.resultOpponentState, CombatV1WrestlerPosture.down);
      });

      test('STAND始動11技すべてがrequiredOpponentState==standを持つ（regression防止）', () {
        const standRequiredIds = [
          'jack_choke_attack',
          'jack_face_claw',
          'jack_sneak_kick',
          'jack_elbow',
          'jack_sneak_lariat',
          'jack_suplex',
          'jack_armlock',
          'jack_kurocho_crash',
          'jack_knee_drop',
          'jack_kurocho_driver',
          'jack_black_jack',
        ];
        expect(standRequiredIds.length, 11);
        for (final id in standRequiredIds) {
          expect(
            jackTechniques[id]!.requiredOpponentState,
            CombatV1WrestlerPosture.stand,
            reason: '$idはrequiredOpponentState==standである必要があります',
          );
        }
        // とどめの踏みつけのみDOWN始動（8技目）。
        expect(
          jackTechniques['jack_finishing_stomp']!.requiredOpponentState,
          CombatV1WrestlerPosture.down,
        );
        // 12技すべてがrequiredOpponentStateを明示的に持つ（nullは
        // 「STAND/DOWNどちらでも可」を意味するため、未設定のまま残っている
        // 技が無いことを保証する）。
        for (final t in jackTechniques.values) {
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
    test('黒蝶ドライバー: finisherType == directPin（Phase 10Bセッションでユーザー確定）', () {
      expect(
        jackTechniques['jack_kurocho_driver']!.finisherType,
        CombatV1FinisherType.directPin,
      );
    });

    test('ブラック・ジャック: finisherType == normal（Phase 10Bセッションでユーザー確定）', () {
      expect(
        jackTechniques['jack_black_jack']!.finisherType,
        CombatV1FinisherType.normal,
      );
    });

    test('NORMAL/SIGNATUREの全技はfinisherType == null', () {
      for (final t in jackTechniques.values) {
        if (t.category == CombatV1CardCategory.finisher) continue;
        expect(t.finisherType, isNull, reason: '${t.id}はcategory!=finisherです');
      }
    });

    test('全技のhasConsistentFinisherTypeがtrue', () {
      for (final t in jackTechniques.values) {
        expect(t.hasConsistentFinisherType, isTrue, reason: t.id);
      }
    });
  });

  group('R. Technique state legality（Codexレビュー指摘の再発防止）', () {
    test('A. チョーク攻撃: opponent DOWN → illegal（opponentStateMismatch）', () {
      final check = _checkLegality(
        'jack_choke_attack',
        opponentPosture: CombatV1WrestlerPosture.down,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('B. 闇討ちラリアット: opponent DOWN → illegal（opponentStateMismatch）', () {
      final check = _checkLegality(
        'jack_sneak_lariat',
        opponentPosture: CombatV1WrestlerPosture.down,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('C. 黒蝶クラッシュ（SIGNATURE）: opponent DOWN → illegal', () {
      final check = _checkLegality(
        'jack_kurocho_crash',
        opponentPosture: CombatV1WrestlerPosture.down,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('D. 黒蝶ドライバー（FINISHER）: HEAT解禁済みでもopponent DOWN → illegal', () {
      final check = _checkLegality(
        'jack_kurocho_driver',
        opponentPosture: CombatV1WrestlerPosture.down,
        sharedHeat: rules.finisherHeatThreshold,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('D. ブラック・ジャック（FINISHER）: HEAT解禁済みでもopponent DOWN → illegal', () {
      final check = _checkLegality(
        'jack_black_jack',
        opponentPosture: CombatV1WrestlerPosture.down,
        sharedHeat: rules.finisherHeatThreshold,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('E. とどめの踏みつけ: opponent DOWN → state条件はlegal（ENERGY等も充足）', () {
      final check = _checkLegality(
        'jack_finishing_stomp',
        opponentPosture: CombatV1WrestlerPosture.down,
      );
      expect(check.legal, isTrue);
      expect(check.reasonCode, CombatV1TechniqueLegalityReasonCode.legal);
    });

    test('F. とどめの踏みつけ: opponent STAND → illegal（opponentStateMismatch）', () {
      final check = _checkLegality(
        'jack_finishing_stomp',
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
          'jack_choke_attack',
          'jack_face_claw',
          'jack_sneak_kick',
          'jack_elbow',
          'jack_sneak_lariat',
          'jack_suplex',
          'jack_armlock',
          'jack_kurocho_crash',
          'jack_knee_drop',
          'jack_kurocho_driver',
          'jack_black_jack',
        ];
        expect(standRequiredIds.length, 11);
        for (final id in standRequiredIds) {
          final isFinisher =
              jackTechniques[id]!.category == CombatV1CardCategory.finisher;
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
      expect(jackCounters.length, 3);
      expect(jackCounters.keys.toSet(), {
        'counter_jack_sneak_guard',
        'counter_jack_reversal',
        'counter_jack_choke_break',
      });
    });

    test('広範囲型（闇討ちガード）: attribute=打, counterableGroups=[STRIKE]', () {
      final c = jackCounters['counter_jack_sneak_guard']!;
      expect(c.attribute, CombatV1EnergyAttribute.strike);
      expect(c.counterableGroups, [CombatV1TechniqueFamilyGroup.strike]);
      expect(c.counterableFamilies, isEmpty);
    });

    test(
      '中範囲型（黒蝶リバーサル）: attribute=ラフ, families=[SUPLEX,BACKDROP,POWERBOMB,DRIVER]',
      () {
        final c = jackCounters['counter_jack_reversal']!;
        expect(c.attribute, CombatV1EnergyAttribute.rough);
        expect(c.counterableFamilies, [
          CombatV1TechniqueFamily.suplex,
          CombatV1TechniqueFamily.backdrop,
          CombatV1TechniqueFamily.powerbomb,
          CombatV1TechniqueFamily.driver,
        ]);
        expect(c.counterableGroups, isEmpty);
      },
    );

    test('専門型（チョークブレイク）: attribute=打, families=[CHOKE,CLAW]', () {
      final c = jackCounters['counter_jack_choke_break']!;
      expect(c.attribute, CombatV1EnergyAttribute.strike);
      expect(c.counterableFamilies, [
        CombatV1TechniqueFamily.choke,
        CombatV1TechniqueFamily.claw,
      ]);
      expect(c.counterableGroups, isEmpty);
    });
  });

  group('I. ENERGY Pool', () {
    test('打3/関1/投1/飛0/ラフ4/＊1＝合計10', () {
      final pool = jackWrestler.energyPool;
      expect(pool.amountFor(CombatV1EnergyAttribute.strike), 3);
      expect(pool.amountFor(CombatV1EnergyAttribute.joint), 1);
      expect(pool.amountFor(CombatV1EnergyAttribute.throwing), 1);
      expect(pool.amountFor(CombatV1EnergyAttribute.aerial), 0);
      expect(pool.amountFor(CombatV1EnergyAttribute.rough), 4);
      expect(pool.amountFor(CombatV1EnergyAttribute.wild), 1);
      expect(pool.amounts.values.fold(0, (a, b) => a + b), 10);
      expect(pool.isValid, isTrue);
    });

    test('Wrestler ID/nameが正式値', () {
      expect(jackWrestler.id, 'jack');
      expect(jackWrestler.name, '黒蝶ジャック');
    });
  });

  group('J/K/L. Deck 30枚・18/4/2/6・同名上限', () {
    late final deck = buildJackDeck(ownerId: 'player-a');

    test('合計30枚', () {
      expect(deck.size, 30);
    });

    test('NORMAL18/SIGNATURE4/FINISHER2/COUNTER6', () {
      expect(deck.countOf(CombatV1CardCategory.normal), 18);
      expect(deck.countOf(CombatV1CardCategory.signature), 4);
      expect(deck.countOf(CombatV1CardCategory.finisher), 2);
      expect(deck.countOf(CombatV1CardCategory.counter), 6);
    });

    test('ROUGH技は20章の確定基準どおり5枚（チョーク×1+顔面×1+クラッシュ×2+ドライバー×1）', () {
      final roughCardIds = {
        'jack_choke_attack',
        'jack_face_claw',
        'jack_kurocho_crash',
        'jack_kurocho_driver',
      };
      final roughCount = deck.entries
          .where((e) => roughCardIds.contains(e.cardId))
          .length;
      expect(roughCount, 5);
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
      expect(counts['jack_choke_attack'], 1);
      expect(counts['jack_face_claw'], 1);
      expect(counts['jack_sneak_kick'], 3);
      expect(counts['jack_elbow'], 3);
      expect(counts['jack_sneak_lariat'], 3);
      expect(counts['jack_suplex'], 2);
      expect(counts['jack_armlock'], 2);
      expect(counts['jack_finishing_stomp'], 3);
      expect(counts['jack_kurocho_crash'], 2);
      expect(counts['jack_knee_drop'], 2);
      expect(counts['jack_kurocho_driver'], 1);
      expect(counts['jack_black_jack'], 1);
      expect(counts['counter_jack_sneak_guard'], 2);
      expect(counts['counter_jack_reversal'], 2);
      expect(counts['counter_jack_choke_break'], 2);
    });

    test('A. 単一deck: instanceIdが30枚すべて一意', () {
      final ids = deck.entries.map((e) => e.instanceId).toSet();
      expect(ids.length, deck.size);
    });

    test('ownerIdが空文字だとArgumentErrorを送出する', () {
      expect(() => buildJackDeck(ownerId: ''), throwsArgumentError);
      expect(() => buildJackDeck(ownerId: '   '), throwsArgumentError);
    });

    test(
      'B. Jack vs Jack mirror match: 同じownerId未使用なら2デッキ計60枚のinstanceIdが'
      'すべて一意（GitHub Codex P1指摘の再発防止をジャックでも確認）',
      () {
        final deckA = buildJackDeck(ownerId: 'player-a');
        final deckB = buildJackDeck(ownerId: 'player-b');

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
    test('productionCardCatalog（ミサキ+ジャック）はvalidateCatalogを通過する', () {
      final result = validateCatalog(productionCardCatalog);
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
    });

    test('Technique/Counter間でcardId衝突がない', () {
      final techniqueIds = jackTechniques.keys.toSet();
      final counterIds = jackCounters.keys.toSet();
      expect(techniqueIds.intersection(counterIds), isEmpty);
    });

    test('ミサキとジャックのTechnique/Counter IDが衝突しない', () {
      expect(
        misakiTechniques.keys.toSet().intersection(jackTechniques.keys.toSet()),
        isEmpty,
      );
      expect(
        misakiCounters.keys.toSet().intersection(jackCounters.keys.toSet()),
        isEmpty,
      );
    });
  });

  group('N. Deck validation', () {
    test('buildJackDeck()はvalidateDeckを通過する', () {
      final deck = buildJackDeck(ownerId: 'player-a');
      final result = validateDeck(deck, catalog: productionCardCatalog, rules: rules);
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
    });
  });

  group('O/P. CombatV1Engine.start・card conservation（Jack vs Jack）', () {
    test('ジャック同士のミラーマッチでstartが正常に完了する（C. Engine.start mirror match）', () {
      final state = CombatV1Engine.start(
        wrestlerA: jackWrestler,
        deckA: buildJackDeck(ownerId: 'player-a'),
        wrestlerB: jackWrestler,
        deckB: buildJackDeck(ownerId: 'player-b'),
        rules: rules,
        catalog: productionCardCatalog,
      );

      expect(state.playerA.wrestlerId, 'jack');
      expect(state.playerB.wrestlerId, 'jack');
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
        wrestlerA: jackWrestler,
        deckA: buildJackDeck(ownerId: 'player-a'),
        wrestlerB: jackWrestler,
        deckB: buildJackDeck(ownerId: 'player-b'),
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
      'D. declareTechnique→declineCounterの1経路を通しても'
      'instanceId衝突・pending ownership違反が起きない（Jack vs Jack）',
      () {
        final random = Random(20260810);
        final started = CombatV1Engine.start(
          wrestlerA: jackWrestler,
          deckA: buildJackDeck(ownerId: 'player-a'),
          wrestlerB: jackWrestler,
          deckB: buildJackDeck(ownerId: 'player-b'),
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
      'E. declareTechnique→playCounterの1経路（COUNTER mirror test）を'
      '通しても、両player全ゾーン+pendingでinstanceId衝突が起きない（Jack vs Jack）',
      () {
        // 攻撃側手札にjack_suplex（family=SUPLEX、Cost投1）、防御側手札に
        // counter_jack_reversal（counterableFamilies=[SUPLEX,BACKDROP,
        // POWERBOMB,DRIVER]、attribute=rough）を直接配置した最小構成で検証する。
        final playerA = CombatV1PlayerState(
          wrestlerId: jackWrestler.id,
          wrestlerName: jackWrestler.name,
          maxHp: rules.startingHp,
          hp: rules.startingHp,
          koc: rules.startingKoc,
          pinCardsHeld: rules.startingPinCards,
          energyPool: jackWrestler.energyPool,
          hand: const [
            CombatV1DeckEntry(
              instanceId: 'player-a_jack_suplex_#0',
              cardId: 'jack_suplex',
              category: CombatV1CardCategory.normal,
            ),
          ],
          drawPile: const [
            CombatV1DeckEntry(
              instanceId: 'player-a_jack_elbow_#0',
              cardId: 'jack_elbow',
              category: CombatV1CardCategory.normal,
            ),
          ],
        );
        final playerB = CombatV1PlayerState(
          wrestlerId: jackWrestler.id,
          wrestlerName: jackWrestler.name,
          maxHp: rules.startingHp,
          hp: rules.startingHp,
          koc: rules.startingKoc,
          pinCardsHeld: rules.startingPinCards,
          energyPool: jackWrestler.energyPool,
          hand: const [
            CombatV1DeckEntry(
              instanceId: 'player-b_counter_jack_reversal_#0',
              cardId: 'counter_jack_reversal',
              category: CombatV1CardCategory.counter,
            ),
          ],
          drawPile: const [
            CombatV1DeckEntry(
              instanceId: 'player-b_jack_sneak_kick_#0',
              cardId: 'jack_sneak_kick',
              category: CombatV1CardCategory.normal,
            ),
          ],
        );
        final state = CombatV1MatchState(
          matchId: 'phase10b-counter-mirror-test',
          playerA: playerA,
          playerB: playerB,
          activePlayerIndex: 0,
          phase: CombatV1MatchPhase.action,
        );

        final declared = CombatV1Engine.declareTechnique(
          state,
          'player-a_jack_suplex_#0',
          catalog: productionCardCatalog,
          rules: rules,
        );
        expect(declared.phase, CombatV1MatchPhase.counterResponsePending);

        final countered = CombatV1Engine.playCounter(
          declared,
          'player-b_counter_jack_reversal_#0',
          catalog: productionCardCatalog,
          rules: rules,
        );
        expect(countered.phase, CombatV1MatchPhase.action);
        expect(countered.pendingAttack, isNull);

        expect(
          countered.playerA.discardPile.any(
            (e) => e.instanceId == 'player-a_jack_suplex_#0',
          ),
          isTrue,
        );
        expect(
          countered.playerB.discardPile.any(
            (e) => e.instanceId == 'player-b_counter_jack_reversal_#0',
          ),
          isTrue,
        );

        final result = validateMatchStateInvariants(countered, rules: rules);
        expect(result.isValid, isTrue, reason: result.errors.join(' / '));
        expect(_allInstanceIds(countered).toSet().length, 4);
      },
    );
  });

  group('S. Misaki vs Jack（異なるレスラー同士でもowner namespaceが安全）', () {
    test('Misaki(player-a) vs Jack(player-b)でEngine.startが正常に完了する', () {
      final state = CombatV1Engine.start(
        wrestlerA: misakiWrestler,
        deckA: buildMisakiDeck(ownerId: 'player-a'),
        wrestlerB: jackWrestler,
        deckB: buildJackDeck(ownerId: 'player-b'),
        rules: rules,
        catalog: productionCardCatalog,
      );

      expect(state.playerA.wrestlerId, 'misaki');
      expect(state.playerB.wrestlerId, 'jack');
      expect(state.phase, CombatV1MatchPhase.discard);

      final result = validateMatchStateInvariants(state, rules: rules);
      expect(result.isValid, isTrue, reason: result.errors.join(' / '));
      expect(_allInstanceIds(state).toSet().length, 60);

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
    });
  });

  group('Q. Production DataをDomain lookupできる（Simulator/UI非依存）', () {
    test('productionCardCatalog.containsCardIdで全12技・3 Counterを参照できる', () {
      for (final id in jackTechniques.keys) {
        expect(productionCardCatalog.containsCardId(id), isTrue, reason: id);
      }
      for (final id in jackCounters.keys) {
        expect(productionCardCatalog.containsCardId(id), isTrue, reason: id);
      }
    });

    test('categoryOfが各カードの正しいcategoryを返す', () {
      expect(
        productionCardCatalog.categoryOf('jack_sneak_kick'),
        CombatV1CardCategory.normal,
      );
      expect(
        productionCardCatalog.categoryOf('jack_kurocho_crash'),
        CombatV1CardCategory.signature,
      );
      expect(
        productionCardCatalog.categoryOf('jack_kurocho_driver'),
        CombatV1CardCategory.finisher,
      );
      expect(
        productionCardCatalog.categoryOf('counter_jack_sneak_guard'),
        CombatV1CardCategory.counter,
      );
    });
  });
}
