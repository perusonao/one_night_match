// Combat Ver.1 Phase 6: SUBMISSION / GIVE UP / ESCAPE のテスト
// （docs/combat_rules_v1.md 10.1章「通常SUBMISSION」）。
//
// Phase 6セッションでユーザーが確定した仕様:
// - 突入方法: 自動トリガーのみ。submissionHold=trueの技がCOUNTERされず
//   成功し、解決後の相手HPが閾値（既定50）以下ならDIRECT PINと同じ仕組みで
//   同一Command内（declineCounter）で自動的にSUBMISSIONへ移行する。
//   declareSubmissionのような独立APIは追加しない。
// - ESCAPE/GIVE UP判定: 完全自動。防御側KOC>=1なら自動的にKOC1を支払い
//   ESCAPE成功。KOC==0なら自動的にGIVE UPで試合終了。防御側の選択肢はない
//   （PINのKICK OUT自動判定と同じ思想）。pendingSubmissionのような入力待ち
//   フェーズは導入しない。
// - ESCAPE成功後: 攻撃側のターンを終了する（PIN 1/2カウントと同じ扱い）。
// - directPin=trueとsubmissionHold=trueは同一技に同時設定できない
//   （Catalog validationで排他）。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_catalog_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_state_invariants.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_submission_rules.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';

import 'combat_v1_test_fixtures.dart';

void main() {
  const submissionAttack = CombatV1DeckEntry(
    instanceId: 'atk_sub',
    cardId: 'fx_normal_submission_hold', // 関1, DMG110, submissionHold=true
    category: CombatV1CardCategory.normal,
  );
  const nonSubmissionAttack = CombatV1DeckEntry(
    instanceId: 'atk_normal',
    cardId: 'fx_normal_strike', // 打1, DMG10, submissionHold=false
    category: CombatV1CardCategory.normal,
  );
  const matchingCounter = CombatV1DeckEntry(
    instanceId: 'ctr_sub',
    cardId: 'fx_counter_submission', // SUBMISSION groupを返せる
    category: CombatV1CardCategory.counter,
  );

  final submissionCatalog = CombatV1CardCatalog(
    techniques: fixtureTechniques,
    counters: fixtureCounters,
  );

  group('A. submissionHold=false（regression）', () {
    test('通常技の成功はSUBMISSIONを一切発生させない（HPが閾値以下でも）', () {
      final state = buildMatchState(
        handA: const [nonSubmissionAttack],
        hpB: 40, // すでに閾値(50)以下
        kocB: 1, // KOC不足でGIVE UPになりうる値だが、発火しないことを検証
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_normal',
        catalog: submissionCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );

      expect(resolved.playerB.hp, 30); // 40 - 10(DMG)
      expect(resolved.winnerPlayerIndex, isNull);
      expect(resolved.playerB.koc, 1); // KOC未消費
      expect(resolved.phase, CombatV1MatchPhase.action);
      expect(resolved.activePlayerIndex, 0); // 攻守交代なし
      expect(resolved.log.any((l) => l.contains('へSUBMISSIONを仕掛けた')), isFalse);
    });
  });

  group('B. submissionHold=true成功 → SUBMISSION自動移行（ESCAPE成功）', () {
    test('相手HPが閾値以下になった場合、同一Command内でESCAPEまで解決する', () {
      final state = buildMatchState(
        handA: const [submissionAttack],
        hpB: 150,
        kocB: 10,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_sub',
        catalog: submissionCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );

      // Technique成功（DMG・HEAT・attacker draw）は通常どおり発生。
      expect(resolved.playerB.hp, 40); // 150 - 110(DMG)
      expect(resolved.sharedHeat, 20);
      expect(resolved.lastSuccessfulTechnique, isNotNull);
      expect(resolved.lastSuccessfulTechnique!.submissionHold, isTrue);

      // KOC10 → ESCAPE成功（KOC1消費）→ ターン終了してplayerBの新しい
      // ターン（discardフェーズ）へ進む。
      expect(resolved.playerB.koc, 9);
      expect(resolved.activePlayerIndex, 1);
      expect(resolved.phase, CombatV1MatchPhase.discard);
      expect(resolved.turnNumber, 2);
      expect(resolved.isOver, isFalse);
      expect(resolved.log.any((l) => l.contains('へSUBMISSIONを仕掛けた')), isTrue);
      expect(resolved.log.any((l) => l.contains('ESCAPE')), isTrue);
    });

    test('境界: 相手HPがちょうど閾値(50)ならSUBMISSIONへ移行する', () {
      final state = buildMatchState(
        handA: const [submissionAttack],
        hpB: 160, // 160 - 110 = 50（ちょうど閾値）
        kocB: 10,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_sub',
        catalog: submissionCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerB.hp, 50);
      expect(resolved.playerB.koc, 9); // ESCAPEが発生している
      expect(resolved.log.any((l) => l.contains('へSUBMISSIONを仕掛けた')), isTrue);
    });

    test('HP0でもKOCがあればESCAPE可能（10.1章）', () {
      final state = buildMatchState(
        handA: const [submissionAttack],
        hpB: 50, // 50 - 110 → 0 clamp
        kocB: 5,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_sub',
        catalog: submissionCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerB.hp, 0);
      expect(resolved.playerB.koc, 4);
      expect(resolved.isOver, isFalse);
    });
  });

  group('C. submissionHold=true成功だがHP>閾値 → SUBMISSION発生しない', () {
    test('DMG後も相手HPが閾値を超えていればSUBMISSIONへ移行しない', () {
      final state = buildMatchState(
        handA: const [submissionAttack],
        hpB: 200,
        kocB: 10,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_sub',
        catalog: submissionCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );

      expect(resolved.playerB.hp, 90); // 200 - 110、閾値50超
      expect(resolved.playerB.koc, 10); // KOC未消費
      expect(resolved.winnerPlayerIndex, isNull);
      expect(resolved.phase, CombatV1MatchPhase.action);
      expect(resolved.activePlayerIndex, 0); // 攻守交代なし（攻撃継続可能）
      expect(resolved.log.any((l) => l.contains('へSUBMISSIONを仕掛けた')), isFalse);
    });
  });

  group('D. COUNTERされたsubmissionHold → SUBMISSION発生しない', () {
    test('COUNTER成立時はDMG・HEAT・SUBMISSIONのいずれも発生しない', () {
      final state = buildMatchState(
        handA: const [submissionAttack],
        handB: const [matchingCounter],
        hpB: 40, // 閾値以下だが、COUNTERされるので無関係
        kocB: 10,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_sub',
        catalog: submissionCatalog,
      );
      final resolved = CombatV1Engine.playCounter(
        declared,
        'ctr_sub',
        catalog: submissionCatalog,
        rules: fixtureRules,
        random: Random(1),
      );

      expect(resolved.playerB.hp, 40); // 変化なし
      expect(resolved.lastSuccessfulTechnique, isNull);
      expect(resolved.winnerPlayerIndex, isNull);
      expect(resolved.playerB.koc, 10); // KOC未消費
      expect(resolved.phase, CombatV1MatchPhase.action);
      expect(resolved.activePlayerIndex, 0); // 攻守交代なし
      expect(resolved.log.any((l) => l.contains('へSUBMISSIONを仕掛けた')), isFalse);
    });
  });

  group('E. ESCAPE resource exact payment', () {
    test('exact KOC: KOC1ちょうどならESCAPEで0になる（負にならない）', () {
      final state = buildMatchState(
        handA: const [submissionAttack],
        hpB: 150,
        kocB: 1,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_sub',
        catalog: submissionCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerB.koc, 0);
      expect(resolved.isOver, isFalse);
      expect(
        validatePlayerStateInvariants(resolved.playerB).isValid,
        isTrue,
      );
    });

    test('非常に大きいKOC（100）でもESCAPEはKOC1のみ消費される', () {
      final state = buildMatchState(
        handA: const [submissionAttack],
        hpB: 150,
        kocB: 100,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_sub',
        catalog: submissionCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerB.koc, 99);
    });
  });

  group('F. resource shortage → GIVE UP', () {
    test('KOC0ならGIVE UPで試合が終了する', () {
      final state = buildMatchState(
        handA: const [submissionAttack],
        hpB: 150,
        kocB: 0,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_sub',
        catalog: submissionCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerB.koc, 0); // 支払い不能なのでKOCは変化しない
      expect(resolved.winnerPlayerIndex, 0); // 攻撃側（playerA）の勝利
      expect(resolved.isOver, isTrue);
      // GIVE UP後はターン終了処理を経ない（試合が終了しているため）。
      expect(resolved.phase, CombatV1MatchPhase.action);
      expect(resolved.activePlayerIndex, 0);
    });

    test('KOCは負数にならない（Command経由でnegativeを生成できない）', () {
      final state = buildMatchState(
        handA: const [submissionAttack],
        hpB: 150,
        kocB: 0,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_sub',
        catalog: submissionCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerB.koc, greaterThanOrEqualTo(0));
    });
  });

  group('G. winner/isOver（Phase 5モデルの再利用）', () {
    test('GIVE UP勝利は攻撃側のplayerIndexをそのまま使う（新しいwinner表現を作らない）', () {
      // 手番（攻撃側）はplayerB（activePlayerIndex=1）。
      final state = buildMatchState(
        handB: const [submissionAttack],
        activePlayerIndex: 1,
        hpA: 150,
        kocA: 0,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_sub',
        catalog: submissionCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.winnerPlayerIndex, 1);
      expect(resolved.isOver, isTrue);
    });
  });

  group('H. game-over guard', () {
    test('試合終了後は以後のCommandがすべて拒否される', () {
      final state = buildMatchState(
        handA: const [submissionAttack, nonSubmissionAttack],
        hpB: 150,
        kocB: 0,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_sub',
        catalog: submissionCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.isOver, isTrue);

      expect(
        () => CombatV1Engine.declareTechnique(
          resolved,
          'atk_normal',
          catalog: submissionCatalog,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(
        () => CombatV1Engine.endTurn(resolved),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(
        () => CombatV1Engine.discardCard(resolved, 'x'),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('I. stale snapshot対策', () {
    test('前ターンのsubmissionHold成功記録は、以後の非submissionHold技成功で再発火しない', () {
      // ターン1でsubmissionHold技を使うがHP>閾値のため発火しない
      // （lastSuccessfulTechnique.submissionHold=trueだけが記録として残る）。
      var state = buildMatchState(
        handA: const [submissionAttack],
        hpB: 200,
        kocB: 10,
      );
      final declaredSub = CombatV1Engine.declareTechnique(
        state,
        'atk_sub',
        catalog: submissionCatalog,
      );
      state = CombatV1Engine.declineCounter(
        declaredSub,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(state.lastSuccessfulTechnique!.submissionHold, isTrue);
      expect(state.winnerPlayerIndex, isNull);

      // 相手のターンを経ずに、同じ攻撃側が別の非submissionHold技を使う
      // （手札にnonSubmissionAttackを追加）。DMG後の相手HPが閾値以下に
      // なっても、直近成立技（B）はsubmissionHold=falseなので発火しない。
      state = state.withActive(
        state.active.copyWith(hand: [...state.active.hand, nonSubmissionAttack]),
      );
      state = state.withOpponent(state.opponent.copyWith(hp: 45));

      final declaredNormal = CombatV1Engine.declareTechnique(
        state,
        'atk_normal',
        catalog: submissionCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declaredNormal,
        rules: fixtureRules,
        random: Random(2),
      );

      expect(resolved.lastSuccessfulTechnique!.submissionHold, isFalse);
      expect(resolved.playerB.hp, 35); // 45 - 10(DMG)、閾値以下だが無関係
      expect(resolved.winnerPlayerIndex, isNull);
      expect(resolved.playerB.koc, 10); // KOC未消費
      expect(resolved.phase, CombatV1MatchPhase.action);
      expect(resolved.activePlayerIndex, 0);
    });
  });

  group('J. directPin/submissionHold排他', () {
    test('Catalog validation: 同一技でdirectPin=trueかつsubmissionHold=trueは拒否される', () {
      final catalog = CombatV1CardCatalog(
        techniques: {
          'bad_both': const CombatV1Technique(
            id: 'bad_both',
            name: '不正技（両方true）',
            category: CombatV1CardCategory.normal,
            attribute: CombatV1EnergyAttribute.throwing,
            energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 1}),
            damage: 20,
            heatGain: 20,
            directPin: true,
            submissionHold: true,
            family: CombatV1TechniqueFamily.backdrop,
          ),
        },
        counters: const {},
      );
      final result = validateCatalog(catalog);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(
          CombatV1CatalogValidationErrorCode
              .techniqueDirectPinSubmissionHoldConflict,
        ),
      );
    });

    test('category==finisherの技はdirectPin/submissionHoldが両方trueでも対象外', () {
      // finisherTypeが決着方式を決定し、directPin/submissionHoldは
      // 参照されない（docs/design/combat_v1_phase1_design.md 2.4章）ため、
      // 両方trueでも排他エラーの対象にしない。
      final catalog = CombatV1CardCatalog(
        techniques: {
          'finisher_ok': const CombatV1Technique(
            id: 'finisher_ok',
            name: 'フィニッシャー',
            category: CombatV1CardCategory.finisher,
            attribute: CombatV1EnergyAttribute.throwing,
            energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 2}),
            damage: 30,
            heatGain: 30,
            directPin: true,
            submissionHold: true,
            finisherType: CombatV1FinisherType.submission,
            family: CombatV1TechniqueFamily.driver,
          ),
        },
        counters: const {},
      );
      final result = validateCatalog(catalog);
      expect(
        result.errors.map((e) => e.code),
        isNot(
          contains(
            CombatV1CatalogValidationErrorCode
                .techniqueDirectPinSubmissionHoldConflict,
          ),
        ),
      );
    });

    test('フィクスチャカタログはvalid（新規追加技を含めても排他ルールに抵触しない）', () {
      final result = validateCatalog(submissionCatalog);
      expect(result.isValid, isTrue);
    });

    test('防御的挙動: Catalog validationを経由せず両方trueの技を直接使ってもDIRECT PINが優先されSUBMISSIONは発生しない', () {
      // validateCatalogはstart()経由でのみ強制されるため、テストのように
      // 直接カタログを構築すればCatalog validationをすり抜けられる。
      // Engine側（_resolvePendingAttack）はdirectPin/submissionHoldを
      // else-ifで判定するため、万一両方trueの技が渡ってもdirectPinが優先され、
      // SUBMISSION側には分岐しないことを確認する（防御的設計）。
      const bothFlagsTechnique = CombatV1Technique(
        id: 'bad_both_defensive',
        name: '不正技（両方true、防御的挙動確認用）',
        category: CombatV1CardCategory.normal,
        attribute: CombatV1EnergyAttribute.throwing,
        energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 1}),
        damage: 110,
        heatGain: 20,
        resultOpponentState: CombatV1WrestlerPosture.down,
        directPin: true,
        submissionHold: true,
        family: CombatV1TechniqueFamily.backdrop,
      );
      final bypassCatalog = CombatV1CardCatalog(
        techniques: {'bad_both_defensive': bothFlagsTechnique},
        counters: const {},
      );
      const attackEntry = CombatV1DeckEntry(
        instanceId: 'atk_both',
        cardId: 'bad_both_defensive',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(
        handA: const [attackEntry],
        hpB: 150,
        kocB: 10,
        pinCardsHeldA: 2,
        pinCardsHeldB: 2,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_both',
        catalog: bypassCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );

      // DIRECT PIN側が優先され、PINカード・KOCがPIN側のロジックで動く。
      expect(resolved.playerB.hp, 40);
      expect(resolved.playerB.posture, CombatV1WrestlerPosture.down);
      expect(resolved.log.any((l) => l.contains('DIRECT PIN')), isTrue);
      expect(resolved.log.any((l) => l.contains('へSUBMISSIONを仕掛けた')), isFalse);
      // PIN側（KOC>=3で1カウント）が動いたことをKOC消費量から確認する。
      expect(resolved.playerB.koc, 7);
    });
  });

  group('K. Atomicity（不正SUBMISSION state）', () {
    test('防御側kocが負数のmalformed stateではdeclineCounterがstateを一切変更せず例外送出', () {
      final state = buildMatchState(
        handA: const [submissionAttack],
        hpB: 150,
        kocB: -1, // 直接構築されたmalformed state（正規経路では発生しない）
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_sub',
        catalog: submissionCatalog,
      );

      expect(
        () => CombatV1Engine.declineCounter(
          declared,
          rules: fixtureRules,
          random: Random(1),
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      // 例外前後でstateそのものが不変であること（declared自体は宣言済み
      // pending状態だが、その先のTechnique成功commitは一切発生していない）。
      expect(declared.playerB.hp, 150);
      expect(declared.playerB.koc, -1);
      expect(declared.lastSuccessfulTechnique, isNull);
      expect(declared.winnerPlayerIndex, isNull);
      expect(declared.phase, CombatV1MatchPhase.counterResponsePending);
    });
  });

  group('L. Invariant（combat_v1_submission_rules.dart / state_invariants）', () {
    test('submissionEligible: HP<=閾値でtrue、閾値超でfalse', () {
      expect(
        submissionEligible(opponentHp: 50, rules: fixtureRules),
        isTrue,
      );
      expect(
        submissionEligible(opponentHp: 0, rules: fixtureRules),
        isTrue,
      );
      expect(
        submissionEligible(opponentHp: 51, rules: fixtureRules),
        isFalse,
      );
    });

    test('determineSubmissionOutcome: KOC>=1でescape、KOC0でgiveUp', () {
      expect(
        determineSubmissionOutcome(defenderKoc: 1, rules: fixtureRules),
        CombatV1SubmissionOutcome.escape,
      );
      expect(
        determineSubmissionOutcome(defenderKoc: 10, rules: fixtureRules),
        CombatV1SubmissionOutcome.escape,
      );
      expect(
        determineSubmissionOutcome(defenderKoc: 0, rules: fixtureRules),
        CombatV1SubmissionOutcome.giveUp,
      );
    });

    test('submissionStateConsistencyViolation: koc>=0ならnull、負数なら理由を返す', () {
      final validState = buildMatchState(kocB: 0);
      expect(
        submissionStateConsistencyViolation(defender: validState.playerB),
        isNull,
      );
      final invalidState = buildMatchState(kocB: -1);
      expect(
        submissionStateConsistencyViolation(defender: invalidState.playerB),
        isNotNull,
      );
    });
  });

  group('M. Regression: card conservation', () {
    test('SUBMISSION解決（ESCAPE）はTECHNIQUE/COUNTERカードの総数を変化させない', () {
      final state = buildMatchState(
        handA: const [submissionAttack],
        hpB: 150,
        kocB: 10,
        drawPileA: const [
          CombatV1DeckEntry(
            instanceId: 'a_reserve',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
        ],
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
        'atk_sub',
        catalog: submissionCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(totalCards(resolved), before);
    });

    test('GIVE UP決着でもカード総数は変化しない', () {
      final state = buildMatchState(
        handA: const [submissionAttack],
        hpB: 150,
        kocB: 0,
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
        'atk_sub',
        catalog: submissionCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(totalCards(resolved), before);
    });
  });

  group('N. State Machine（ESCAPE後のturn）', () {
    test('ESCAPE成功後: 防御側の新しいターン（discard）へ進み、ENERGY全回復・1ドローされる', () {
      final state = buildMatchState(
        handA: const [submissionAttack],
        hpB: 150,
        kocB: 10,
        turnNumber: 3,
        spentB: const {CombatV1EnergyAttribute.strike: 1},
        techniquesUsedB: 2,
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
        'atk_sub',
        catalog: submissionCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );

      expect(resolved.activePlayerIndex, 1);
      expect(resolved.phase, CombatV1MatchPhase.discard);
      expect(resolved.turnNumber, 4);
      expect(resolved.playerB.spentEnergy, isEmpty);
      expect(resolved.playerB.techniquesUsedThisTurn, 0);
      expect(
        resolved.playerB.hand.any((e) => e.instanceId == 'b_reserve'),
        isTrue,
      );
    });

    test('SUBMISSIONはPINカードを一切操作しない（10章）', () {
      final state = buildMatchState(
        handA: const [submissionAttack],
        hpB: 150,
        kocB: 10,
        pinCardsHeldA: 2,
        pinCardsHeldB: 2,
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_sub',
        catalog: submissionCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerA.pinCardsHeld, 2);
      expect(resolved.playerB.pinCardsHeld, 2);
    });
  });

  group('O. Phase 1〜5 regression（フィクスチャデッキ・catalogに影響なし）', () {
    test('フィクスチャ30枚デッキは引き続きvalidである', () {
      final deck = fixtureDeck('wrestler_regression');
      final result = validateDeck(deck, catalog: fixtureCatalog, rules: fixtureRules);
      expect(result.isValid, isTrue);
    });

    test('match開始（start）は新規fixtureTechnique/Counter追加後も正常に動作する', () {
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
      expect(started.playerA.hp, 150);
      expect(started.playerB.hp, 150);
    });
  });
}
