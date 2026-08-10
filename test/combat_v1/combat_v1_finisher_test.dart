// Combat Ver.1 Phase 9: FINISHER解禁・FINISHER決着処理のテスト
// （docs/combat_rules_v1.md 12・13・10.2章）。
//
// Phase 9セッションでユーザーが確認した仕様:
// - FINISHER解禁条件: 共有HEAT >= CombatV1RulesConfig.finisherHeatThreshold
//   （既定200）。HEATは消費しない（12章）ため、一度解禁されたら再び不可には
//   ならない。
// - finisherTypeの3分岐（13章）:
//   - normal: 通常のTECHNIQUE成功解決のみ。自動PIN/SUBMISSIONは発生しない。
//     攻撃側はその後任意でdeclarePinを呼べる（既存の汎用legality判定を
//     そのまま使う、新規APIは追加しない）。
//   - directPin: 技成功と同一Command内でPINへ自動移行する（8章のPINカード
//     ルールにそのまま従う。既存のDIRECT PIN機構をfinisherType経由で流用）。
//   - submission: FINISHER専用SUBMISSION処理（10.2章）へ自動移行する。
//     通常SUBMISSIONとの唯一の相違点は、解決後の相手HPが0の場合、KOCの
//     保有量に関わらず即GIVE UPになること（10.2章「HP0: 即GIVE UP」）。
// - category==finisherの技はdirectPin/submissionHoldフィールドを参照しない
//   （finisherTypeのみが決着方式を決定する、2.4章）。
// - FINISHERはCOUNTER可能（Phase 9セッションでユーザーが確認）。COUNTER
//   成立時は他のTECHNIQUEと全く同じく完全無効化される。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_catalog_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_finisher_rules.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_state_invariants.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';

import 'combat_v1_test_fixtures.dart';

void main() {
  // fx_finisher_a: normal型。打2、DMG30、HEAT30、resultOpponentState無し
  // （STAND→STAND、family=lariat/strike group）。
  const normalFinisher = CombatV1DeckEntry(
    instanceId: 'atk_fin_normal',
    cardId: 'fx_finisher_a',
    category: CombatV1CardCategory.finisher,
  );
  // fx_finisher_b: directPin型。投2、DMG30、HEAT30、resultOpponentState
  // 無し（posture不変。DIRECT PIN自動移行には「解決後の相手posture==down」
  // が前提のため、これを検証するテストでは相手を事前にDOWNさせておく、
  // family=powerbomb/throwing group）。
  const directPinFinisher = CombatV1DeckEntry(
    instanceId: 'atk_fin_direct',
    cardId: 'fx_finisher_b',
    category: CombatV1CardCategory.finisher,
  );
  // fx_finisher_c: submission型。関2、DMG130、HEAT30
  // （family=crossface/submission group）。
  const submissionFinisher = CombatV1DeckEntry(
    instanceId: 'atk_fin_sub',
    cardId: 'fx_finisher_c',
    category: CombatV1CardCategory.finisher,
  );
  // fx_finisher_rough_normal: normal型・attribute==rough。ラフ2、DMG30、
  // HEAT30、STAND→DOWN（family=choke/submission group）。
  const roughFinisher = CombatV1DeckEntry(
    instanceId: 'atk_fin_rough',
    cardId: 'fx_finisher_rough_normal',
    category: CombatV1CardCategory.finisher,
  );
  // fx_counter_a: STRIKE group全体を返せる（fx_finisher_aのfamily=lariatは
  // strike groupに属する）。
  const strikeCounter = CombatV1DeckEntry(
    instanceId: 'ctr_strike',
    cardId: 'fx_counter_a',
    category: CombatV1CardCategory.counter,
  );

  group('A. HEAT解禁ゲート（checkTechniqueLegality）', () {
    test('sharedHeatが閾値(200)未満ならfinisherHeatNotReached', () {
      final state = buildMatchState(
        handA: const [normalFinisher],
        sharedHeat: 199,
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'atk_fin_normal',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.finisherHeatNotReached,
      );
    });

    test('sharedHeatがちょうど閾値(200)なら解禁される', () {
      final state = buildMatchState(
        handA: const [normalFinisher],
        sharedHeat: 200,
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'atk_fin_normal',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isTrue);
    });

    test('sharedHeatが閾値を超えていても解禁される', () {
      final state = buildMatchState(
        handA: const [normalFinisher],
        sharedHeat: 500,
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'atk_fin_normal',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isTrue);
    });

    test('NORMAL/SIGNATUREはHEATに関わらず従来どおり使用できる（regression）', () {
      const normalAttack = CombatV1DeckEntry(
        instanceId: 'atk_normal',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: const [normalAttack], sharedHeat: 0);
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'atk_normal',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isTrue);
    });

    test('finisherUnlocked: 純粋関数の境界値', () {
      expect(
        finisherUnlocked(sharedHeat: 199, rules: fixtureRules),
        isFalse,
      );
      expect(
        finisherUnlocked(sharedHeat: 200, rules: fixtureRules),
        isTrue,
      );
      expect(
        finisherUnlocked(sharedHeat: 1000, rules: fixtureRules),
        isTrue,
      );
    });
  });

  group('B. normal finisherType — 自動PIN/SUBMISSIONなし', () {
    test('成功してもPINへ自動移行しない。攻撃側がその後任意でdeclarePinできる', () {
      final state = buildMatchState(
        handA: const [normalFinisher],
        sharedHeat: 200,
        postureB: CombatV1WrestlerPosture.down, // 事前にDOWNさせておく
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_fin_normal',
        catalog: fixtureCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );

      // 通常のTECHNIQUE成功解決のみ発生する。
      expect(resolved.playerB.hp, 120); // 150 - 30(DMG)
      expect(resolved.sharedHeat, 230); // 200 + 30(HEAT)
      expect(resolved.playerB.posture, CombatV1WrestlerPosture.down); // 変化なし
      expect(resolved.winnerPlayerIndex, isNull);
      expect(resolved.phase, CombatV1MatchPhase.action);
      expect(resolved.activePlayerIndex, 0); // 攻守交代なし（攻撃継続可能）
      expect(resolved.log.any((l) => l.contains('へPINを仕掛けた')), isFalse);
      expect(resolved.log.any((l) => l.contains('へDIRECT PINを仕掛けた')), isFalse);
      expect(resolved.log.any((l) => l.contains('へSUBMISSIONを仕掛けた')), isFalse);

      // 攻撃側は事後に通常PINを任意で選択できる（既存の汎用declarePin）。
      expect(CombatV1Engine.hasPinOption(resolved, rules: fixtureRules), isTrue);
      final pinned = CombatV1Engine.declarePin(
        resolved,
        rules: fixtureRules,
        random: Random(2),
      );
      expect(pinned.log.any((l) => l.contains('へPINを仕掛けた')), isTrue);
      expect(pinned.playerB.koc, 7); // 10 - 3（1カウント）
    });
  });

  group('C. directPin finisherType — 成功と同一Commandで自動PIN', () {
    test('1カウント: PINカード移動・防御側1ドロー・攻守交代まで一括解決', () {
      final state = buildMatchState(
        handA: const [directPinFinisher],
        sharedHeat: 200,
        // fx_finisher_bはresultOpponentStateを持たないため、DIRECT PIN
        // 自動移行の前提（解決後の相手posture==down）を満たすよう、相手を
        // 事前にDOWNさせておく（8章「相手がDOWNで」）。
        postureB: CombatV1WrestlerPosture.down,
        kocB: 10, // >=3 → 1カウント
        pinCardsHeldA: 2,
        pinCardsHeldB: 2,
        drawPileB: const [
          CombatV1DeckEntry(
            instanceId: 'b_reserve',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
        ],
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_fin_direct',
        catalog: fixtureCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );

      expect(resolved.playerB.hp, 120); // 150 - 30(DMG)
      expect(resolved.playerB.posture, CombatV1WrestlerPosture.down);
      expect(resolved.sharedHeat, 230);
      expect(resolved.log.any((l) => l.contains('DIRECT PIN')), isTrue);

      // PIN側（1カウント）が動いたことを確認する。
      expect(resolved.playerB.koc, 7); // 10 - 3(pinCountOneKocCost)
      expect(resolved.playerA.pinCardsHeld, 1); // 攻撃側→防御側へ1枚移動
      expect(resolved.playerB.pinCardsHeld, 3);
      expect(
        resolved.playerB.hand.any((e) => e.instanceId == 'b_reserve'),
        isTrue,
      ); // 1カウントの追加ドロー
      expect(resolved.activePlayerIndex, 1); // 攻守交代
      expect(resolved.phase, CombatV1MatchPhase.discard);
      expect(resolved.winnerPlayerIndex, isNull);
    });

    test('3カウント相当（防御側KOC0）: PIN決着で試合終了、winnerPlayerIndexが攻撃側', () {
      final state = buildMatchState(
        handA: const [directPinFinisher],
        sharedHeat: 200,
        postureB: CombatV1WrestlerPosture.down, // DIRECT PIN前提（上記参照）
        kocB: 0,
        pinCardsHeldA: 2,
        pinCardsHeldB: 2,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_fin_direct',
        catalog: fixtureCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.winnerPlayerIndex, 0);
      expect(resolved.isOver, isTrue);
      expect(resolved.playerB.koc, 0); // 支払い不能なので変化しない
    });

    test(
      'Atomicity: 攻撃側pinCardsHeld==0のmalformed stateでは'
      'declineCounterがstateを一切変更せず例外送出',
      () {
        final state = buildMatchState(
          handA: const [directPinFinisher],
          sharedHeat: 200,
          postureB: CombatV1WrestlerPosture.down, // DIRECT PIN前提（上記参照）
          kocB: 10,
          pinCardsHeldA: 0, // 直接構築されたmalformed state（正規経路では発生しない）
          pinCardsHeldB: 4,
        );
        final declared = CombatV1Engine.declareTechnique(
          state,
          'atk_fin_direct',
          catalog: fixtureCatalog,
        );
        expect(
          () => CombatV1Engine.declineCounter(
            declared,
            rules: fixtureRules,
            random: Random(1),
          ),
          throwsA(isA<CombatV1IllegalActionException>()),
        );
        expect(declared.playerB.hp, 150); // DMGはcommitされていない
        expect(declared.playerA.pinCardsHeld, 0);
        expect(declared.lastSuccessfulTechnique, isNull);
      },
    );
  });

  group('D. submission finisherType — FINISHER専用SUBMISSION', () {
    test('相手HP1以上（閾値以下）: 通常SUBMISSIONと同じKOCベースESCAPEが働く', () {
      final state = buildMatchState(
        handA: const [submissionFinisher],
        sharedHeat: 200,
        hpB: 150, // 150 - 130(DMG) = 20（閾値50以下）
        kocB: 10,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_fin_sub',
        catalog: fixtureCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );

      expect(resolved.playerB.hp, 20);
      expect(resolved.log.any((l) => l.contains('FINISHER SUBMISSIONを仕掛けた')), isTrue);
      expect(resolved.playerB.koc, 9); // ESCAPE成功（KOC1消費）
      expect(resolved.winnerPlayerIndex, isNull);
      expect(resolved.activePlayerIndex, 1); // 攻守交代（PIN 1/2と同じ扱い）
      expect(resolved.phase, CombatV1MatchPhase.discard);
    });

    test('相手HP0まで落ちた場合: KOCの保有量に関わらず即GIVE UP（10.2章の唯一の例外）', () {
      final state = buildMatchState(
        handA: const [submissionFinisher],
        sharedHeat: 200,
        hpB: 100, // 100 - 130 → 0 clamp
        kocB: 100, // 大量にKOCを保有していてもESCAPEできない
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_fin_sub',
        catalog: fixtureCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );

      expect(resolved.playerB.hp, 0);
      expect(resolved.playerB.koc, 100); // 支払い不能ではなく、そもそも支払う機会が無い
      expect(resolved.winnerPlayerIndex, 0);
      expect(resolved.isOver, isTrue);
      expect(resolved.log.any((l) => l.contains('HP0でESCAPEできず')), isTrue);
    });

    test('通常SUBMISSION（10.1章）はHP0でもKOCがあればESCAPE可能——FINISHERとの相違点の regression確認', () {
      final normalSubmissionAttack = const CombatV1DeckEntry(
        instanceId: 'atk_normal_sub',
        cardId: 'fx_normal_submission_hold',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(
        handA: [normalSubmissionAttack],
        hpB: 50, // 50 - 110 → 0 clamp
        kocB: 5,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_normal_sub',
        catalog: fixtureCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerB.hp, 0);
      expect(resolved.playerB.koc, 4); // ESCAPE成功（FINISHERとは異なりHP0でも可能）
      expect(resolved.isOver, isFalse);
    });

    test('Atomicity: 防御側koc<0のmalformed stateではdeclineCounterがstateを一切変更せず例外送出', () {
      final state = buildMatchState(
        handA: const [submissionFinisher],
        sharedHeat: 200,
        hpB: 150,
        kocB: -1,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_fin_sub',
        catalog: fixtureCatalog,
      );
      expect(
        () => CombatV1Engine.declineCounter(
          declared,
          rules: fixtureRules,
          random: Random(1),
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(declared.playerB.hp, 150);
      expect(declared.lastSuccessfulTechnique, isNull);
    });

    group('determineFinisherSubmissionOutcome（純粋関数）', () {
      test('opponentHp<=0なら、defenderKocに関わらず常にgiveUp', () {
        expect(
          determineFinisherSubmissionOutcome(
            opponentHp: 0,
            defenderKoc: 999,
            rules: fixtureRules,
          ),
          CombatV1SubmissionOutcome.giveUp,
        );
      });

      test('opponentHp>=1かつdefenderKoc>=1ならescape（通常SUBMISSIONと同じ判定）', () {
        expect(
          determineFinisherSubmissionOutcome(
            opponentHp: 1,
            defenderKoc: 1,
            rules: fixtureRules,
          ),
          CombatV1SubmissionOutcome.escape,
        );
      });

      test('opponentHp>=1かつdefenderKoc==0ならgiveUp（通常SUBMISSIONと同じ判定）', () {
        expect(
          determineFinisherSubmissionOutcome(
            opponentHp: 1,
            defenderKoc: 0,
            rules: fixtureRules,
          ),
          CombatV1SubmissionOutcome.giveUp,
        );
      });
    });
  });

  group('E. COUNTER × FINISHER（Phase 9セッションで確認: COUNTER可能）', () {
    test('COUNTER成立でFINISHERは完全無効化される（DMG・HEAT・自動PIN/SUBMISSIONいずれも発生しない）', () {
      final state = buildMatchState(
        handA: const [normalFinisher],
        handB: const [strikeCounter],
        sharedHeat: 200,
        postureB: CombatV1WrestlerPosture.down,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_fin_normal',
        catalog: fixtureCatalog,
      );
      final check = CombatV1Engine.checkCounterLegality(
        declared,
        'ctr_strike',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      );
      expect(check.legal, isTrue);

      final resolved = CombatV1Engine.playCounter(
        declared,
        'ctr_strike',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(1),
      );

      expect(resolved.playerB.hp, 150); // DMGなし
      expect(resolved.sharedHeat, 200); // HEAT変化なし
      expect(resolved.lastSuccessfulTechnique, isNull); // 成立記録も更新しない
      expect(resolved.winnerPlayerIndex, isNull);
      expect(resolved.phase, CombatV1MatchPhase.action);
      expect(resolved.activePlayerIndex, 0); // 攻守交代なし
      // 双方1ドローされる（手札循環を維持し、COUNTERを手札破壊効果にしない）。
      expect(
        resolved.playerA.hand.length + resolved.playerA.discardPile.length,
        1, // 攻撃カードがdiscardへ+1ドロー
      );
    });
  });

  group('F. ROUGH × FINISHER — 既存ROUGHロジックがcategoryを問わず適用される', () {
    test('ROUGH属性のFINISHER（normal型）を使うと、そのターンの通常PINが以後ブロックされる', () {
      final state = buildMatchState(
        handA: const [roughFinisher],
        sharedHeat: 200,
        postureB: CombatV1WrestlerPosture.stand,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_fin_rough',
        catalog: fixtureCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );

      // ROUGH技（category==finisherでも）はattributeベースで
      // roughTechniqueUsedThisTurnをセットする（Phase 8ロジックの再利用）。
      expect(resolved.playerA.roughTechniqueUsedThisTurn, isTrue);
      expect(resolved.playerB.posture, CombatV1WrestlerPosture.down);

      final pinCheck = CombatV1Engine.checkPinLegality(resolved, rules: fixtureRules);
      expect(pinCheck.legal, isFalse);
      expect(
        pinCheck.reasonCode,
        CombatV1PinLegalityReasonCode.roughTechniqueUsedThisTurn,
      );
    });
  });

  group('G. カード保存則・不変条件（regression）', () {
    test('FINISHER（directPin）解決はTECHNIQUE/COUNTERカードの総数を変化させない', () {
      final state = buildMatchState(
        handA: const [directPinFinisher],
        sharedHeat: 200,
        postureB: CombatV1WrestlerPosture.down, // DIRECT PIN前提（Group C参照）
        kocB: 10,
      );
      int totalCards(CombatV1MatchState s) =>
          s.playerA.hand.length +
          s.playerA.drawPile.length +
          s.playerA.discardPile.length +
          s.playerB.hand.length +
          s.playerB.drawPile.length +
          s.playerB.discardPile.length;

      final before = totalCards(state);
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_fin_direct',
        catalog: fixtureCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(totalCards(resolved), before);
      expect(validatePlayerStateInvariants(resolved.playerA).isValid, isTrue);
      expect(validatePlayerStateInvariants(resolved.playerB).isValid, isTrue);
      expect(validateMatchStateInvariants(resolved, rules: fixtureRules).isValid, isTrue);
    });
  });

  group('H. Phase 1〜8 regression（フィクスチャデッキ・catalogに影響なし）', () {
    test('新規FINISHERフィクスチャ追加後もfixtureCatalogはvalid', () {
      final started = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck(fixtureWrestlerA.id),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck(fixtureWrestlerB.id),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(1),
      );
      expect(started.phase, CombatV1MatchPhase.discard);
      expect(started.sharedHeat, 0);
    });
  });

  // Phase 9 Codexレビュー指摘「Reject finishers without a resolution type」
  // （P2）対応: category==finisherかつfinisherType==nullの技が、assertが
  // 無効化されたビルドではruntime validationで拒否されず、HEAT解禁後に
  // normal FINISHER相当として黙って解決されてしまう問題への再発防止テスト。
  //
  // 通常のコンストラクタは、この不変条件をassertで強制しているため、Dart
  // assertionが有効な環境（flutter testを含む）では不正な組み合わせを
  // 直接構築できない。以下は[CombatV1Technique.unsafeForTesting]
  // （テスト専用、assertを迂回する別コンストラクタ）を使い、assertionが
  // 無効化されたビルドで不正データが構築されてしまった場合を再現する。
  group('I. category/finisherType不変条件（Phase 9 Codexレビュー指摘対応）', () {
    test(
      '通常のコンストラクタはfinisherType==nullのFINISHERをassertで拒否する'
      '（既存の防御、変更なし）',
      () {
        expect(
          () => CombatV1Technique(
            id: 'bad_finisher_ctor_assert',
            name: '不正フィニッシャー（コンストラクタassert確認用）',
            category: CombatV1CardCategory.finisher,
            attribute: CombatV1EnergyAttribute.strike,
            energyCost: const CombatV1EnergyCost({
              CombatV1EnergyAttribute.strike: 2,
            }),
            damage: 30,
            heatGain: 30,
            family: CombatV1TechniqueFamily.lariat,
            // finisherTypeを指定しない（null）。
          ),
          throwsA(isA<AssertionError>()),
        );
      },
    );

    test('hasConsistentFinisherType: category==finisherかつfinisherType==nullはfalse', () {
      const invalid = CombatV1Technique.unsafeForTesting(
        id: 'bad_finisher_null_type',
        name: '不正フィニッシャー（finisherType無し）',
        category: CombatV1CardCategory.finisher,
        attribute: CombatV1EnergyAttribute.strike,
        energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2}),
        damage: 30,
        heatGain: 30,
        family: CombatV1TechniqueFamily.lariat,
        // finisherType: null（既定値のまま）。
      );
      expect(invalid.hasConsistentFinisherType, isFalse);
      expect(invalid.isStaticDataValid, isFalse);
    });

    test(
      'hasConsistentFinisherType: category!=finisherかつfinisherType!=null'
      'もfalse（対称ケース）',
      () {
        const invalid = CombatV1Technique.unsafeForTesting(
          id: 'bad_normal_with_type',
          name: '不正NORMAL技（finisherType誤設定）',
          category: CombatV1CardCategory.normal,
          attribute: CombatV1EnergyAttribute.strike,
          energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
          damage: 10,
          heatGain: 10,
          family: CombatV1TechniqueFamily.elbow,
          finisherType: CombatV1FinisherType.normal,
        );
        expect(invalid.hasConsistentFinisherType, isFalse);
        expect(invalid.isStaticDataValid, isFalse);
      },
    );

    test('hasConsistentFinisherType: フィクスチャ技はすべて不変条件を満たす（regression）', () {
      for (final technique in fixtureTechniques.values) {
        expect(
          technique.hasConsistentFinisherType,
          isTrue,
          reason: '${technique.id}はcategory/finisherTypeの不変条件を満たすべき',
        );
      }
    });

    test(
      'checkTechniqueLegality: HEAT解禁済みでもfinisherType==nullのFINISHERは'
      'invalidTechniqueDataで拒否される',
      () {
        const invalidFinisher = CombatV1Technique.unsafeForTesting(
          id: 'bad_finisher_heat_ok',
          name: '不正フィニッシャー（HEAT解禁済み）',
          category: CombatV1CardCategory.finisher,
          attribute: CombatV1EnergyAttribute.strike,
          energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2}),
          damage: 30,
          heatGain: 30,
          family: CombatV1TechniqueFamily.lariat,
        );
        final catalog = CombatV1CardCatalog(
          techniques: {
            ...fixtureTechniques,
            invalidFinisher.id: invalidFinisher,
          },
          counters: fixtureCounters,
        );
        final entry = CombatV1DeckEntry(
          instanceId: 'atk_bad_finisher_heat_ok',
          cardId: invalidFinisher.id,
          category: CombatV1CardCategory.finisher,
        );
        final state = buildMatchState(
          handA: [entry],
          sharedHeat: 500, // HEATは十分に解禁済み
        );
        final check = CombatV1Engine.checkTechniqueLegality(
          state,
          'atk_bad_finisher_heat_ok',
          catalog: catalog,
        );
        expect(check.legal, isFalse);
        expect(
          check.reasonCode,
          CombatV1TechniqueLegalityReasonCode.invalidTechniqueData,
        );
      },
    );

    test(
      'checkTechniqueLegality: HEAT不足でもデータ不正が優先され'
      'invalidTechniqueDataで拒否される（finisherHeatNotReachedにはならない）',
      () {
        const invalidFinisher = CombatV1Technique.unsafeForTesting(
          id: 'bad_finisher_low_heat',
          name: '不正フィニッシャー（HEAT不足）',
          category: CombatV1CardCategory.finisher,
          attribute: CombatV1EnergyAttribute.strike,
          energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2}),
          damage: 30,
          heatGain: 30,
          family: CombatV1TechniqueFamily.lariat,
        );
        final catalog = CombatV1CardCatalog(
          techniques: {
            ...fixtureTechniques,
            invalidFinisher.id: invalidFinisher,
          },
          counters: fixtureCounters,
        );
        final entry = CombatV1DeckEntry(
          instanceId: 'atk_bad_finisher_low_heat',
          cardId: invalidFinisher.id,
          category: CombatV1CardCategory.finisher,
        );
        final state = buildMatchState(handA: [entry], sharedHeat: 0);
        final check = CombatV1Engine.checkTechniqueLegality(
          state,
          'atk_bad_finisher_low_heat',
          catalog: catalog,
        );
        expect(check.legal, isFalse);
        expect(
          check.reasonCode,
          CombatV1TechniqueLegalityReasonCode.invalidTechniqueData,
        );
      },
    );

    test('declareTechnique: 不正FINISHERの宣言は例外を送出しstateを一切変更しない（atomicity）', () {
      const invalidFinisher = CombatV1Technique.unsafeForTesting(
        id: 'bad_finisher_declare',
        name: '不正フィニッシャー（宣言テスト）',
        category: CombatV1CardCategory.finisher,
        attribute: CombatV1EnergyAttribute.strike,
        energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2}),
        damage: 30,
        heatGain: 30,
        family: CombatV1TechniqueFamily.lariat,
      );
      final catalog = CombatV1CardCatalog(
        techniques: {...fixtureTechniques, invalidFinisher.id: invalidFinisher},
        counters: fixtureCounters,
      );
      final entry = CombatV1DeckEntry(
        instanceId: 'atk_bad_finisher_declare',
        cardId: invalidFinisher.id,
        category: CombatV1CardCategory.finisher,
      );
      final state = buildMatchState(handA: [entry], sharedHeat: 500);

      expect(
        () => CombatV1Engine.declareTechnique(
          state,
          'atk_bad_finisher_declare',
          catalog: catalog,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      // state完全不変（宣言は一切コミットされていない）。
      expect(state.playerA.hand.length, 1);
      expect(state.playerA.hand.first.instanceId, 'atk_bad_finisher_declare');
      expect(state.playerA.spentEnergy, isEmpty);
      expect(state.phase, CombatV1MatchPhase.action);
      expect(state.sharedHeat, 500);
      expect(state.pendingAttack, isNull);
    });

    test(
      'validateCatalog: finisherType==nullのFINISHERは'
      'techniqueInvalidFinisherTypeで拒否される',
      () {
        const invalidFinisher = CombatV1Technique.unsafeForTesting(
          id: 'bad_finisher_catalog',
          name: '不正フィニッシャー（catalog検証）',
          category: CombatV1CardCategory.finisher,
          attribute: CombatV1EnergyAttribute.strike,
          energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2}),
          damage: 30,
          heatGain: 30,
          family: CombatV1TechniqueFamily.lariat,
        );
        final catalog = CombatV1CardCatalog(
          techniques: {invalidFinisher.id: invalidFinisher},
          counters: const {},
        );
        final result = validateCatalog(catalog);
        expect(result.isValid, isFalse);
        expect(
          result.errors.map((e) => e.code),
          contains(
            CombatV1CatalogValidationErrorCode.techniqueInvalidFinisherType,
          ),
        );
      },
    );

    test(
      'validateCatalog: category!=finisherなのにfinisherType!=nullも'
      'techniqueInvalidFinisherTypeで拒否される（対称ケース）',
      () {
        const invalidNormal = CombatV1Technique.unsafeForTesting(
          id: 'bad_normal_catalog',
          name: '不正NORMAL技（catalog検証）',
          category: CombatV1CardCategory.normal,
          attribute: CombatV1EnergyAttribute.strike,
          energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
          damage: 10,
          heatGain: 10,
          family: CombatV1TechniqueFamily.elbow,
          finisherType: CombatV1FinisherType.directPin,
        );
        final catalog = CombatV1CardCatalog(
          techniques: {invalidNormal.id: invalidNormal},
          counters: const {},
        );
        final result = validateCatalog(catalog);
        expect(result.isValid, isFalse);
        expect(
          result.errors.map((e) => e.code),
          contains(
            CombatV1CatalogValidationErrorCode.techniqueInvalidFinisherType,
          ),
        );
      },
    );

    test('validateCatalog: フィクスチャカタログはvalid（regression）', () {
      final result = validateCatalog(fixtureCatalog);
      expect(result.isValid, isTrue);
    });
  });

  group('J. normal/directPin/submission FINISHER正常系のregression（修正後も従来どおり合法）', () {
    test('normal FINISHER（fx_finisher_a）はHEAT解禁済みなら合法', () {
      final state = buildMatchState(
        handA: const [normalFinisher],
        sharedHeat: 200,
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'atk_fin_normal',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isTrue);
    });

    test('directPin FINISHER（fx_finisher_b）はHEAT解禁済みなら合法', () {
      final state = buildMatchState(
        handA: const [directPinFinisher],
        sharedHeat: 200,
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'atk_fin_direct',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isTrue);
    });

    test('submission FINISHER（fx_finisher_c）はHEAT解禁済みなら合法', () {
      final state = buildMatchState(
        handA: const [submissionFinisher],
        sharedHeat: 200,
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'atk_fin_sub',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isTrue);
    });
  });

  group('K. 非FINISHER Techniqueへのregressionなし', () {
    test('NORMAL/SIGNATURE技はfinisherType==nullのままisStaticDataValid==true（regression）', () {
      for (final technique in fixtureTechniques.values) {
        if (technique.category == CombatV1CardCategory.finisher) continue;
        expect(technique.finisherType, isNull);
        expect(technique.isStaticDataValid, isTrue, reason: technique.id);
      }
    });

    test('NORMAL技のcheckTechniqueLegalityはfinisherType関連チェックの影響を受けない', () {
      const normalAttack = CombatV1DeckEntry(
        instanceId: 'atk_normal_regress',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(
        handA: const [normalAttack],
        sharedHeat: 0,
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'atk_normal_regress',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isTrue);
    });
  });
}
