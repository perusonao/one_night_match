// Combat Ver.1 Phase 8: ROUGH特殊処理の検証（docs/combat_rules_v1.md 15章）。
//
// Phase 8セッションでユーザーへ確認し、以下の4点を正式仕様として確定した
// （docs/design/combat_v1_open_questions.md参照）:
// - 「ROUGH使用ターンはPINできない」の“使用”は宣言時点の基準（使用ベース）。
//   COUNTERされたROUGH技も対象になる。
// - このPIN不可ルールは通常PIN（declarePin/checkPinLegality）のみが対象。
//   DIRECT PINは技成功と同一Command内で自動遷移するため対象外
//   （checkPinLegalityを経由しない）。
// - 「相手は次の自ターンにTECHNIQUE最大1枚」の“1枚”も宣言時点の基準
//   （使用ベース）。COUNTERされた技も1枚に含む。
// - 次ターン制限は、そのターンの終了とともに（消費の有無に関わらず）消滅
//   する。持ち越しはしない。
//
// テストはdocs/combat_rules_v1.md 15章のSSOT本文と、上記4点の確定仕様に
// 厳密に対応させる。旧EngineのROUGH/反則処理は一切参照しない。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_state_invariants.dart';

import 'combat_v1_test_fixtures.dart';

/// atomicity検証用の軽量スナップショット（combat_v1_technique_legality_test.dart
/// の`_StateSnapshot`と同じ方針。ROUGH固有フィールドを含める）。
class _RoughStateSnapshot {
  _RoughStateSnapshot(CombatV1MatchState s)
    : handLength = s.playerB.hand.length,
      techniquesUsed = s.playerB.techniquesUsedThisTurn,
      roughLimitActive = s.playerB.roughTechniqueLimitActive,
      roughUsed = s.playerB.roughTechniqueUsedThisTurn;

  final int handLength;
  final int techniquesUsed;
  final bool roughLimitActive;
  final bool roughUsed;

  void expectUnchanged(CombatV1MatchState s) {
    expect(s.playerB.hand.length, handLength);
    expect(s.playerB.techniquesUsedThisTurn, techniquesUsed);
    expect(s.playerB.roughTechniqueLimitActive, roughLimitActive);
    expect(s.playerB.roughTechniqueUsedThisTurn, roughUsed);
  }
}

void main() {
  const roughEntry = CombatV1DeckEntry(
    instanceId: 'a1',
    cardId: 'fx_rough_basic',
    category: CombatV1CardCategory.normal,
  );
  const roughDirectPinEntry = CombatV1DeckEntry(
    instanceId: 'a1',
    cardId: 'fx_rough_direct_pin',
    category: CombatV1CardCategory.normal,
  );
  const roughSubmissionEntry = CombatV1DeckEntry(
    instanceId: 'a1',
    cardId: 'fx_rough_submission_hold',
    category: CombatV1CardCategory.normal,
  );
  const roughCounter = CombatV1DeckEntry(
    instanceId: 'c1',
    cardId: 'fx_counter_submission',
    category: CombatV1CardCategory.counter,
  );

  group('A. ROUGH Technique正常使用（declareTechnique）', () {
    test('宣言直後、roughTechniqueUsedThisTurnがtrueになる（COUNTER応答待ち）', () {
      final state = buildMatchState(handA: const [roughEntry]);
      final declared = CombatV1Engine.declareTechnique(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      expect(declared.phase, CombatV1MatchPhase.counterResponsePending);
      expect(declared.playerA.roughTechniqueUsedThisTurn, isTrue);
      expect(declared.playerA.techniquesUsedThisTurn, 1);
      // 通常のTECHNIQUEと同じくENERGYが消費される。
      expect(declared.playerA.spentEnergy[CombatV1EnergyAttribute.rough], 1);
    });
  });

  group('B. ROUGH成功（declineCounter解決）', () {
    test('COUNTERされずに成立すると、lastSuccessfulTechnique.attributeがroughになる', () {
      final state = buildMatchState(handA: const [roughEntry], hpB: 150);
      final declared = CombatV1Engine.declareTechnique(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerB.hp, 140); // 150 - 10（DMGは通常技と同じ）
      expect(resolved.sharedHeat, 20);
      expect(resolved.playerB.posture, CombatV1WrestlerPosture.down);
      expect(
        resolved.lastSuccessfulTechnique?.attribute,
        CombatV1EnergyAttribute.rough,
      );
      expect(resolved.lastSuccessfulTechnique?.attackerPlayerIndex, 0);
    });
  });

  group('C. ROUGHがCOUNTERされる', () {
    test('COUNTER成立後もroughTechniqueUsedThisTurnはtrueのまま（使用ベース、取り消されない）', () {
      final state = buildMatchState(
        handA: const [roughEntry],
        handB: const [roughCounter],
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      final countered = CombatV1Engine.playCounter(
        declared,
        'c1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(countered.playerB.hp, 150); // DMG無効
      expect(countered.playerA.roughTechniqueUsedThisTurn, isTrue);
      expect(countered.playerA.techniquesUsedThisTurn, 1);
      // 「成功」はしていないため、lastSuccessfulTechniqueは更新されない
      // （Phase 4既存の使用/成功の区別、Phase 8でも維持）。
      expect(countered.lastSuccessfulTechnique, isNull);
    });

    test('COUNTERされたROUGHのみのターンが終了しても、次ターン制限はセットされない（成功していないため）', () {
      final state = buildMatchState(
        handA: const [roughEntry],
        handB: const [roughCounter],
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      final countered = CombatV1Engine.playCounter(
        declared,
        'c1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(1),
      );
      final afterTurn = CombatV1Engine.endTurn(countered, random: Random(2));
      expect(afterTurn.playerB.roughTechniqueLimitActive, isFalse);
    });
  });

  group('D. ROUGH使用後PIN（通常PIN、declarePin/checkPinLegality）', () {
    test('ROUGH技を使用（成功）したターンは通常PINできない', () {
      final state = buildMatchState(handA: const [roughEntry], hpB: 150);
      final declared = CombatV1Engine.declareTechnique(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      final check = CombatV1Engine.checkPinLegality(resolved, rules: fixtureRules);
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1PinLegalityReasonCode.roughTechniqueUsedThisTurn,
      );
      expect(
        () => CombatV1Engine.declarePin(resolved, rules: fixtureRules),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test(
      'COUNTERされたROUGH技も対象: 別の非ROUGH技が同ターンに成功していてもPIN不可'
      '（使用ベース、Phase 8セッションでユーザーが確定した方針）',
      () {
        const downEntry = CombatV1DeckEntry(
          instanceId: 'a2',
          cardId: 'fx_normal_throw_down',
          category: CombatV1CardCategory.normal,
        );
        var state = buildMatchState(
          handA: const [roughEntry, downEntry],
          handB: const [roughCounter],
          hpB: 150,
        );

        // 1. ROUGH技を宣言し、COUNTERされる（成立しない）。
        state = CombatV1Engine.declareTechnique(
          state,
          'a1',
          catalog: fixtureCatalog,
        );
        state = CombatV1Engine.playCounter(
          state,
          'c1',
          catalog: fixtureCatalog,
          rules: fixtureRules,
          random: Random(1),
        );
        expect(state.playerA.roughTechniqueUsedThisTurn, isTrue);

        // 2. 別の非ROUGH技を宣言し、COUNTERされずに成立させる
        //    （相手をDOWNさせ、このターンの成功済みTECHNIQUEを作る）。
        state = CombatV1Engine.declareTechnique(
          state,
          'a2',
          catalog: fixtureCatalog,
        );
        state = CombatV1Engine.declineCounter(
          state,
          rules: fixtureRules,
          random: Random(2),
        );
        expect(state.playerB.posture, CombatV1WrestlerPosture.down);
        expect(
          state.lastSuccessfulTechnique?.attribute,
          CombatV1EnergyAttribute.throwing,
        );

        // 3. 「相手DOWN」「このターン成功済み」は満たすが、ROUGH技を
        //    このターンに使用（COUNTERされたが宣言済み）しているため、
        //    通常PINはできない。
        final check = CombatV1Engine.checkPinLegality(state, rules: fixtureRules);
        expect(check.legal, isFalse);
        expect(
          check.reasonCode,
          CombatV1PinLegalityReasonCode.roughTechniqueUsedThisTurn,
        );
      },
    );

    test('ROUGHを使用していないターンは通常通りPIN可能（regression）', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      expect(state.playerA.roughTechniqueUsedThisTurn, isFalse);
      expect(CombatV1Engine.checkPinLegality(state, rules: fixtureRules).legal, isTrue);
    });
  });

  group('E. ROUGH + DIRECT PIN（両立、Phase 8セッションでユーザーが確定した方針）', () {
    test('attribute=rough かつ directPin=true の技は、通常PIN不可ルールの影響を受けず自動PINへ移行する', () {
      final state = buildMatchState(
        handA: const [roughDirectPinEntry],
        hpB: 150,
        kocB: 0, // 3カウント（KOC不足）で即決着させ、DIRECT PINが実際に発火したことを検証する
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      // DIRECT PINが正常に発火し、KOC不足の3カウントで即座に試合が終了する。
      // ROUGH-PIN不可ルールに阻まれていれば、DMGのみでisOverはfalseのまま。
      expect(resolved.isOver, isTrue);
      expect(resolved.winnerPlayerIndex, 0);
    });
  });

  group('F. ROUGH + SUBMISSION HOLD（両立、SUBMISSIONはROUGH使用フラグの影響を受けない）', () {
    test('attribute=rough かつ submissionHold=true の技は、HP閾値以下なら通常通りSUBMISSIONへ自動移行する', () {
      final state = buildMatchState(
        handA: const [roughSubmissionEntry],
        hpB: 150,
        kocB: 0, // KOC不足でGIVE UP即決着させ、SUBMISSIONが実際に発火したことを検証する
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(resolved.playerB.hp, 40); // 150 - 110、閾値50以下
      // SUBMISSION自動移行によりGIVE UPで試合が終了する
      // （checkPinLegalityを経由しないため、roughTechniqueUsedThisTurnの
      // 影響を受けない）。
      expect(resolved.isOver, isTrue);
      expect(resolved.winnerPlayerIndex, 0);
    });
  });

  group('G. ROUGH成功による次ターンTECHNIQUE最大1枚制限', () {
    test('endTurn時、直前の成功技がROUGHなら相手のroughTechniqueLimitActiveがtrueになる', () {
      final state = buildMatchState(handA: const [roughEntry], hpB: 150);
      final declared = CombatV1Engine.declareTechnique(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      final afterTurn = CombatV1Engine.endTurn(resolved, random: Random(2));
      expect(afterTurn.activePlayerIndex, 1);
      expect(afterTurn.playerB.roughTechniqueLimitActive, isTrue);
      expect(afterTurn.playerA.roughTechniqueLimitActive, isFalse);
      // 手番プレイヤー（B）のROUGH使用フラグ・techniquesUsedThisTurnは
      // ターン開始でリセットされている。
      expect(afterTurn.playerB.roughTechniqueUsedThisTurn, isFalse);
      expect(afterTurn.playerB.techniquesUsedThisTurn, 0);
    });

    test('制限中の相手は1枚宣言できるが、2枚目はroughTechniqueLimitReachedで拒否される', () {
      const fillerToDiscard = CombatV1DeckEntry(
        instanceId: 'fillerB',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      const techB1 = CombatV1DeckEntry(
        instanceId: 'b1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      const techB2 = CombatV1DeckEntry(
        instanceId: 'b2',
        cardId: 'fx_normal_strike_alt',
        category: CombatV1CardCategory.normal,
      );

      var state = buildMatchState(handA: const [roughEntry], hpB: 150);
      state = CombatV1Engine.declareTechnique(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      state = CombatV1Engine.declineCounter(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      state = CombatV1Engine.endTurn(state, random: Random(2));
      expect(state.playerB.roughTechniqueLimitActive, isTrue);

      // Bのターン開始直後はdiscardフェーズ。手札を直接差し替えて
      // 制限下でのTECHNIQUE宣言を検証する（drawPile依存を避けるため）。
      state = state.withActive(
        state.active.copyWith(
          hand: const [fillerToDiscard, techB1, techB2],
        ),
      );
      state = CombatV1Engine.discardCard(state, 'fillerB');
      expect(state.phase, CombatV1MatchPhase.action);
      // Aのfx_rough_basicはresultOpponentState=downを持つため、Bはこの
      // ターンDOWNのまま開始する。TECHNIQUE宣言の前にstandUpが必要
      // （docs/combat_rules_v1.md 11章、Phase 7のDOWN合法行動regression）。
      expect(state.playerB.posture, CombatV1WrestlerPosture.down);
      state = CombatV1Engine.standUp(state);
      expect(state.playerB.posture, CombatV1WrestlerPosture.stand);

      // 1枚目: 制限中でも宣言できる。
      expect(
        CombatV1Engine.checkTechniqueLegality(
          state,
          'b1',
          catalog: fixtureCatalog,
          rules: fixtureRules,
        ).legal,
        isTrue,
      );
      state = CombatV1Engine.declareTechnique(
        state,
        'b1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      );
      state = CombatV1Engine.declineCounter(
        state,
        rules: fixtureRules,
        random: Random(3),
      );
      expect(state.playerB.techniquesUsedThisTurn, 1);
      expect(state.playerB.roughTechniqueLimitActive, isTrue); // 持続中

      // 2枚目: 上限（既定1枚）に達しているため拒否される。
      final secondCheck = CombatV1Engine.checkTechniqueLegality(
        state,
        'b2',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      );
      expect(secondCheck.legal, isFalse);
      expect(
        secondCheck.reasonCode,
        CombatV1TechniqueLegalityReasonCode.roughTechniqueLimitReached,
      );
      expect(
        () => CombatV1Engine.declareTechnique(
          state,
          'b2',
          catalog: fixtureCatalog,
          rules: fixtureRules,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(
        CombatV1Engine.hasAnyPlayableTechnique(
          state,
          catalog: fixtureCatalog,
          rules: fixtureRules,
        ),
        isFalse,
      );
    });

    test('そのターン終了とともに（消費の有無に関わらず）制限は消滅する。持ち越さない', () {
      // Bはroughに制限されているが、TECHNIQUEを1枚も使わずターンを終える
      // （非ROUGHのTECHNIQUEでB自身のターンを終える）。
      const techB = CombatV1DeckEntry(
        instanceId: 'b1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      var state = buildMatchState(
        activePlayerIndex: 1,
        handB: const [techB],
        roughLimitActiveB: true,
        hpA: 150,
      );
      state = CombatV1Engine.declareTechnique(
        state,
        'b1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      );
      state = CombatV1Engine.declineCounter(
        state,
        rules: fixtureRules,
        random: Random(1),
      );
      final afterTurn = CombatV1Engine.endTurn(state, random: Random(2));
      // Bの制限はターン終了で消滅し、Aへ持ち越されない
      // （Bの成功技はstrike属性でありrough成功ではないため）。
      expect(afterTurn.playerB.roughTechniqueLimitActive, isFalse);
      expect(afterTurn.playerA.roughTechniqueLimitActive, isFalse);
    });
  });

  group('I. RESTとの関係', () {
    test('RESTによるターン終了でも、次ターン制限判定は同じ共有処理で行われる', () {
      // 直接state構築: activePlayerがこのターンROUGHを成功させた直後に
      // DOWNになっている状況を再現し、rest()がendTurn等と同じ
      // ROUGH判定を通ることを検証する（ユニットテストとしての直接構築）。
      final state = buildMatchState(
        postureA: CombatV1WrestlerPosture.down,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
          attribute: CombatV1EnergyAttribute.rough,
        ),
      );
      final rested = CombatV1Engine.rest(state, rules: fixtureRules, random: Random(1));
      expect(rested.playerB.roughTechniqueLimitActive, isTrue);
    });

    test('ROUGHで制限中でも、RESTはTECHNIQUE枚数として消費されず選択できる', () {
      final state = buildMatchState(
        activePlayerIndex: 1,
        postureB: CombatV1WrestlerPosture.down,
        roughLimitActiveB: true,
      );
      expect(CombatV1Engine.checkRestLegality(state).legal, isTrue);
      final rested = CombatV1Engine.rest(state, rules: fixtureRules, random: Random(1));
      // RESTはターンを終了させるため、Bの制限はこのターンの終了で消滅する
      // （消費されたのではなく、単にターンが終わったため）。
      expect(rested.playerB.roughTechniqueLimitActive, isFalse);
    });
  });

  group('J. standUpとの関係', () {
    test('standUpはターンを終了せず、ROUGH次ターン制限にも一切影響しない', () {
      final state = buildMatchState(
        activePlayerIndex: 1,
        postureB: CombatV1WrestlerPosture.down,
        roughLimitActiveB: true,
        techniquesUsedB: 0,
      );
      final stoodUp = CombatV1Engine.standUp(state);
      expect(stoodUp.activePlayerIndex, 1); // ターン不変
      expect(stoodUp.turnNumber, state.turnNumber);
      expect(stoodUp.playerB.techniquesUsedThisTurn, 0); // 消費しない
      expect(stoodUp.playerB.roughTechniqueLimitActive, isTrue); // 維持
    });

    test('ROUGHで制限中でも、standUpは通常通り実行できる', () {
      final state = buildMatchState(
        activePlayerIndex: 1,
        postureB: CombatV1WrestlerPosture.down,
        roughLimitActiveB: true,
      );
      expect(CombatV1Engine.checkStandUpLegality(state).legal, isTrue);
    });
  });

  group('K. game-over guard', () {
    test('試合終了後は、ROUGH固有の判定より先にmatchOverでTECHNIQUEが拒否される', () {
      final state = buildMatchState(
        handA: const [roughEntry],
        roughLimitActiveA: true,
        winnerPlayerIndex: 0,
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'a1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      );
      expect(check.reasonCode, CombatV1TechniqueLegalityReasonCode.matchOver);
    });

    test('試合終了後は、ROUGH使用によるPIN不可より先にmatchOverでPINが拒否される', () {
      final state = buildMatchState(
        roughUsedA: true,
        postureB: CombatV1WrestlerPosture.down,
        winnerPlayerIndex: 0,
      );
      final check = CombatV1Engine.checkPinLegality(state, rules: fixtureRules);
      expect(check.reasonCode, CombatV1PinLegalityReasonCode.matchOver);
    });
  });

  group('L. atomicity', () {
    test('roughTechniqueLimitReachedで拒否されるdeclareTechniqueはstateを一切変更しない', () {
      const tech = CombatV1DeckEntry(
        instanceId: 'b1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(
        activePlayerIndex: 1,
        handB: const [tech],
        roughLimitActiveB: true,
        techniquesUsedB: 1, // 既に上限まで使用済み
      );
      final snapshot = _RoughStateSnapshot(state);
      expect(
        () => CombatV1Engine.declareTechnique(
          state,
          'b1',
          catalog: fixtureCatalog,
          rules: fixtureRules,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      // CombatV1MatchStateはimmutableなため、[state]変数自体は例外後も
      // 元のインスタンスのまま——値が変化していないことをフィールド単位で
      // 確認する（他のatomicityテストと同じ方針）。
      snapshot.expectUnchanged(state);
    });
  });

  group('M. invariant', () {
    test('非手番プレイヤーのroughTechniqueLimitActive==trueはinvariant違反として検出される', () {
      final state = buildMatchState(
        activePlayerIndex: 0,
        roughLimitActiveB: true, // Bは非手番のはずが制限中＝構造的に不整合
      );
      final result = validateMatchStateInvariants(state, rules: fixtureRules);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(
          CombatV1MatchStateInvariantErrorCode
              .roughTechniqueLimitActiveOnInactivePlayer,
        ),
      );
    });

    test('手番プレイヤー側のroughTechniqueLimitActiveはinvariant違反にならない', () {
      final state = buildMatchState(
        activePlayerIndex: 0,
        roughLimitActiveA: true,
      );
      final result = validateMatchStateInvariants(state, rules: fixtureRules);
      expect(result.isValid, isTrue);
    });
  });

  group('N. card conservation', () {
    test('ROUGH技の宣言→成立でカード総数が変化しない', () {
      final state = buildMatchState(handA: const [roughEntry], hpB: 150);
      int totalCards(CombatV1MatchState s) =>
          s.playerA.hand.length +
          s.playerA.drawPile.length +
          s.playerA.discardPile.length +
          s.playerB.hand.length +
          s.playerB.drawPile.length +
          s.playerB.discardPile.length +
          (s.pendingAttack == null ? 0 : 1);

      final before = totalCards(state);
      final declared = CombatV1Engine.declareTechnique(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      expect(totalCards(declared), before);
      final resolved = CombatV1Engine.declineCounter(
        declared,
        rules: fixtureRules,
        random: Random(1),
      );
      expect(totalCards(resolved), before);
    });
  });

  group('O. Phase 1〜7 regression', () {
    test('新フィールドは既定でfalseであり、既存の通常PIN挙動に変化を与えない', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      expect(state.playerA.roughTechniqueUsedThisTurn, isFalse);
      expect(state.playerA.roughTechniqueLimitActive, isFalse);
      expect(CombatV1Engine.checkPinLegality(state, rules: fixtureRules).legal, isTrue);
    });

    test('新フィールドは既定でfalseであり、既存の通常TECHNIQUE宣言に変化を与えない', () {
      const tech = CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: const [tech]);
      expect(
        CombatV1Engine.checkTechniqueLegality(
          state,
          'a1',
          catalog: fixtureCatalog,
          rules: fixtureRules,
        ).legal,
        isTrue,
      );
    });
  });
}
