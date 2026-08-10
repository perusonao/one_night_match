// Combat Ver.1 Phase 4 Codexレビュー指摘M2: Phase 3確定仕様に対するgolden
// parity test。`declareAndResolveTechnique`ヘルパー自身をoracleにせず、
// Phase 3で確定していた期待値（HP・HEAT・posture・hand・drawPile・
// discardPile・spentEnergy等）をliteralで直接検証する。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';

import 'combat_v1_test_fixtures.dart';

void main() {
  group('golden parity — STAND→STAND（fx_normal_strike: 打1, DMG10, HEAT10）', () {
    test('宣言→decline後のHP/HEAT/postureがPhase 3確定値と一致する', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry], hpB: 150, sharedHeat: 0);

      final declared = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);
      final resolved = CombatV1Engine.declineCounter(declared, random: Random(1));

      // Phase 3確定値（1技golden）: HP150-10=140、HEAT0+10=10、posture不変。
      expect(resolved.playerB.hp, 140);
      expect(resolved.sharedHeat, 10);
      expect(resolved.playerB.posture, CombatV1WrestlerPosture.stand);
      expect(resolved.playerA.spentEnergy[CombatV1EnergyAttribute.strike], 1);
      expect(resolved.phase, CombatV1MatchPhase.action);
      expect(resolved.activePlayerIndex, 0);
    });
  });

  group('golden parity — STAND→DOWN（fx_normal_throw_down: 投1, DMG20, HEAT20）', () {
    test('宣言→decline後のposture/HP/HEATがPhase 3確定値と一致する', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_throw_down',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(
        handA: [entry],
        hpB: 150,
        sharedHeat: 0,
        postureB: CombatV1WrestlerPosture.stand,
      );

      final declared = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);
      final resolved = CombatV1Engine.declineCounter(declared, random: Random(1));

      expect(resolved.playerB.hp, 130); // 150-20
      expect(resolved.sharedHeat, 20);
      expect(resolved.playerB.posture, CombatV1WrestlerPosture.down);
      expect(resolved.playerA.spentEnergy[CombatV1EnergyAttribute.throwing], 1);
    });
  });

  group('golden parity — HP 0 clamp', () {
    test('DMGがHPを超えても0でクランプされ、負数にならない', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_throw_down', // DMG20
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry], hpB: 15);

      final declared = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);
      final resolved = CombatV1Engine.declineCounter(declared, random: Random(1));

      expect(resolved.playerB.hp, 0); // 15-20=-5だが0でクランプ
    });
  });

  group('golden parity — HEATの累積', () {
    test('2技分のHEATが正しく累積する（10+20=30）', () {
      final t1 = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike', // heatGain10
        category: CombatV1CardCategory.normal,
      );
      final t2 = const CombatV1DeckEntry(
        instanceId: 'a2',
        cardId: 'fx_normal_throw_down', // heatGain20
        category: CombatV1CardCategory.normal,
      );
      var state = buildMatchState(handA: [t1, t2], sharedHeat: 0);

      var declared = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);
      state = CombatV1Engine.declineCounter(declared, random: Random(1));
      expect(state.sharedHeat, 10);

      declared = CombatV1Engine.declareTechnique(state, 'a2', catalog: fixtureCatalog);
      state = CombatV1Engine.declineCounter(declared, random: Random(2));
      expect(state.sharedHeat, 30);
    });
  });

  group('golden parity — draw', () {
    test('decline成功後、攻撃側の手札が1枚drawされる', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final reserve = const CombatV1DeckEntry(
        instanceId: 'reserve',
        cardId: 'fx_normal_strike_alt',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry], drawPileA: [reserve]);

      final declared = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);
      final resolved = CombatV1Engine.declineCounter(declared, random: Random(1));

      expect(resolved.playerA.hand.length, 1);
      expect(resolved.playerA.hand.single.instanceId, 'reserve');
      expect(resolved.playerA.drawPile, isEmpty);
    });
  });

  group('golden parity — reshuffle', () {
    test('drawPile空・discardPileありでのdrawはreshuffleを起こし、'
        'reshuffleCountが+1、総枚数は保存される', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final oldDiscard = const CombatV1DeckEntry(
        instanceId: 'old_discard',
        cardId: 'fx_normal_strike_alt',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(
        handA: [entry],
        drawPileA: const [],
        discardPileA: [oldDiscard],
      );

      final declared = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);
      final resolved = CombatV1Engine.declineCounter(declared, random: Random(1));

      expect(resolved.playerA.reshuffleCount, 1);
      // 総枚数保存: 宣言前hand1(→discard) + discard1(oldDiscard) = 2枚が
      // 再構築後にdrawPile+hand+discardPileへ保存される。
      final total = resolved.playerA.drawPile.length +
          resolved.playerA.hand.length +
          resolved.playerA.discardPile.length;
      expect(total, 2);
    });
  });

  group('golden parity — full field-by-field比較（決定的な単一シナリオ、'
      'Phase 4 Codex再レビュー指摘M2対応: MatchStateの全field・'
      'playerA/B双方の全field・log内容全体を含めた真の全field比較）', () {
    test('宣言→decline後のMatchState全fieldがPhase 3確定仕様どおりの値になる', () {
      final attack = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_throw_down', // 投1, DMG20, HEAT20, STAND->DOWN
        category: CombatV1CardCategory.normal,
      );
      final reserve = const CombatV1DeckEntry(
        instanceId: 'reserve',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(
        handA: [attack],
        drawPileA: [reserve],
        hpB: 150,
        sharedHeat: 0,
        postureB: CombatV1WrestlerPosture.stand,
        techniquesUsedA: 0,
      );

      final declared = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);
      final resolved = CombatV1Engine.declineCounter(declared, random: Random(42));

      // ---- MatchState全体（matchId・phase・activePlayerIndex・turnNumber・
      // sharedHeat・pendingAttack・lastSuccessfulTechnique・log）----
      expect(resolved.matchId, 'phase4-test-match');
      expect(resolved.phase, CombatV1MatchPhase.action);
      expect(resolved.activePlayerIndex, 0);
      expect(resolved.turnNumber, 1);
      expect(resolved.sharedHeat, 20);
      expect(resolved.pendingAttack, isNull);
      expect(resolved.winnerPlayerIndex, isNull);
      expect(resolved.log, [
        'テストファイターAがテストダウン投げ技を宣言した',
        'テストファイターAの攻撃がCOUNTERされず成立した（DMG20、HEAT+20）',
        'テストファイターAがカードを1枚引いた',
      ]);

      // ---- lastSuccessfulTechnique（全field）----
      final snapshot = resolved.lastSuccessfulTechnique;
      expect(snapshot, isNotNull);
      expect(snapshot!.attackerPlayerIndex, 0);
      expect(snapshot.turnNumber, 1);
      expect(snapshot.cardInstanceId, 'a1');
      expect(snapshot.cardId, 'fx_normal_throw_down');
      expect(snapshot.category, CombatV1CardCategory.normal);
      expect(snapshot.attribute, CombatV1EnergyAttribute.throwing);
      expect(snapshot.family, CombatV1TechniqueFamily.slam);
      expect(snapshot.directPin, isFalse);
      expect(snapshot.submissionHold, isFalse);
      expect(snapshot.finisherType, isNull);
      expect(snapshot.resultOpponentState, CombatV1WrestlerPosture.down);

      // ---- playerA（攻撃側）全field ----
      final a = resolved.playerA;
      expect(a.wrestlerId, 'fx_wrestler_a');
      expect(a.wrestlerName, 'テストファイターA');
      expect(a.maxHp, 150);
      expect(a.hp, 150); // 攻撃側は被弾しない
      expect(a.koc, 10);
      expect(a.pinCardsHeld, 2);
      expect(a.posture, CombatV1WrestlerPosture.stand);
      expect(a.energyPool.amounts, {
        CombatV1EnergyAttribute.strike: 3,
        CombatV1EnergyAttribute.joint: 1,
        CombatV1EnergyAttribute.throwing: 2,
        CombatV1EnergyAttribute.aerial: 1,
        CombatV1EnergyAttribute.rough: 1,
        CombatV1EnergyAttribute.wild: 2,
      });
      expect(a.spentEnergy, {CombatV1EnergyAttribute.throwing: 1});
      expect(
        a.hand.map((e) => (e.instanceId, e.cardId, e.category)).toList(),
        [('reserve', 'fx_normal_strike', CombatV1CardCategory.normal)],
      );
      expect(a.drawPile, isEmpty);
      expect(
        a.discardPile.map((e) => (e.instanceId, e.cardId, e.category)).toList(),
        [('a1', 'fx_normal_throw_down', CombatV1CardCategory.normal)],
      );
      expect(a.reshuffleCount, 0);
      expect(a.techniquesUsedThisTurn, 1);

      // ---- playerB（防御側）全field ----
      final b = resolved.playerB;
      expect(b.wrestlerId, 'fx_wrestler_b');
      expect(b.wrestlerName, 'テストファイターB');
      expect(b.maxHp, 150);
      expect(b.hp, 130); // 150-20
      expect(b.koc, 10);
      expect(b.pinCardsHeld, 2);
      expect(b.posture, CombatV1WrestlerPosture.down);
      expect(b.energyPool.amounts, {
        CombatV1EnergyAttribute.strike: 2,
        CombatV1EnergyAttribute.joint: 2,
        CombatV1EnergyAttribute.throwing: 1,
        CombatV1EnergyAttribute.aerial: 1,
        CombatV1EnergyAttribute.rough: 0,
        CombatV1EnergyAttribute.wild: 2,
      });
      expect(b.spentEnergy, isEmpty);
      expect(b.hand, isEmpty);
      expect(b.drawPile, isEmpty);
      expect(b.discardPile, isEmpty);
      expect(b.reshuffleCount, 0);
      expect(b.techniquesUsedThisTurn, 0);
    });
  });
}
