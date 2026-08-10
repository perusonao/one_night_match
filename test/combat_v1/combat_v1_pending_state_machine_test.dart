// Combat Ver.1 Phase 4: TECHNIQUE宣言→PendingAttack→counterResponsePending
// のState Machine検証（docs/combat_rules_v1.md 7.1章
// 「PendingAttack・counterResponsePending」、directPin/submissionHold
// 未発火の確認はdocs/combat_rules_v1.md 6章・13章、テスト項目31-D）。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';

import 'combat_v1_test_fixtures.dart';

void main() {
  group('TECHNIQUE宣言 — pending作成（31-D）', () {
    test('宣言はcounterResponsePendingへ入る', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry]);

      final next = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);

      expect(next.phase, CombatV1MatchPhase.counterResponsePending);
      expect(next.pendingAttack, isNotNull);
    });

    test('pendingは正しいattacker/defenderPlayerIndexと攻撃内容を保持する', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_throw_down', // damage20, heat20, backdrop相当のslam family
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry]);

      final next = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);
      final pending = next.pendingAttack!;

      expect(pending.attackerPlayerIndex, 0);
      expect(pending.defenderPlayerIndex, 1);
      expect(pending.attackCardInstance.instanceId, 'a1');
      expect(pending.attackCardId, 'fx_normal_throw_down');
      expect(pending.category, CombatV1CardCategory.normal);
      expect(pending.attribute, CombatV1EnergyAttribute.throwing);
      expect(pending.family, CombatV1TechniqueFamily.slam);
      expect(pending.damage, 20);
      expect(pending.heatGain, 20);
      expect(pending.resultOpponentState, CombatV1WrestlerPosture.down);
    });

    test('宣言はDMGを遅延させる（相手HP不変）', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike', // damage10
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry], hpB: 150);

      final next = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);

      expect(next.playerB.hp, 150);
    });

    test('宣言はHEATを遅延させる（sharedHeat不変）', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike', // heatGain10
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry], sharedHeat: 0);

      final next = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);

      expect(next.sharedHeat, 0);
    });

    test('宣言は相手posture変化を遅延させる', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_throw_down', // resultOpponentState==down
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(
        handA: [entry],
        postureB: CombatV1WrestlerPosture.stand,
      );

      final next = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);

      expect(next.playerB.posture, CombatV1WrestlerPosture.stand);
    });

    test('宣言はdiscardを遅延させる（攻撃カードはdiscardPileへまだ移動しない）', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry]);

      final next = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);

      expect(next.playerA.discardPile, isEmpty);
    });

    test('宣言はdrawを遅延させる（drawPileはまだ変化しない）', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final drawCard = const CombatV1DeckEntry(
        instanceId: 'reserve',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry], drawPileA: [drawCard]);

      final next = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);

      expect(next.playerA.drawPile.length, 1);
      expect(next.playerA.hand, isEmpty); // まだdrawしていないので空のまま
    });

    test('宣言は攻撃側のENERGYを消費する', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike', // 打1
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry]);

      final next = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);

      expect(next.playerA.spentEnergy[CombatV1EnergyAttribute.strike], 1);
    });

    test('宣言はtechniquesUsedThisTurnを+1する', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry], techniquesUsedA: 0);

      final next = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);

      expect(next.playerA.techniquesUsedThisTurn, 1);
    });

    test('攻撃カードはhandから離れる', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry]);

      final next = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);

      expect(next.playerA.hand.any((e) => e.instanceId == 'a1'), isFalse);
    });

    test('攻撃カードはhand/drawPile/discardPileいずれにも存在せずpendingが所有する', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry]);

      final next = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);

      expect(next.playerA.hand.any((e) => e.instanceId == 'a1'), isFalse);
      expect(next.playerA.drawPile.any((e) => e.instanceId == 'a1'), isFalse);
      expect(next.playerA.discardPile.any((e) => e.instanceId == 'a1'), isFalse);
      expect(next.pendingAttack!.attackCardInstance.instanceId, 'a1');
    });
  });

  group('Match Phase — counterResponsePendingからの遷移（docs/combat_rules_v1.md 7.1章）', () {
    test('宣言中はaction以外のCommand（declareTechnique/endTurn/discardCard）を拒否する', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final other = const CombatV1DeckEntry(
        instanceId: 'a2',
        cardId: 'fx_normal_strike_alt',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry, other]);
      final pending = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);

      expect(
        () => CombatV1Engine.declareTechnique(pending, 'a2', catalog: fixtureCatalog),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(
        () => CombatV1Engine.endTurn(pending),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      expect(
        () => CombatV1Engine.discardCard(pending, 'a2'),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('decline後はphaseがactionへ戻り、activePlayerIndexは宣言側のまま', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry], activePlayerIndex: 0);
      final pending = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);

      final resolved = CombatV1Engine.declineCounter(pending, random: Random(1));

      expect(resolved.phase, CombatV1MatchPhase.action);
      expect(resolved.activePlayerIndex, 0);
      expect(resolved.pendingAttack, isNull);
    });
  });

  group('directPin/submissionHold — 未COUNTER時も特殊処理は発火しない（34）', () {
    test('directPin==trueの技がdeclineで成立してもPIN関連フィールドは変化しない', () {
      // fx_finisher_bはfinisherType==directPinを持つがFINISHERのため
      // sharedHeatが解禁閾値未満だと使用不可（finisherHeatNotReached、
      // Phase 9）。ここではPhase 4当時と同じ意図で、NORMAL/SIGNATUREで
      // directPin相当のフラグを持つローカル技を使い、decline経路でも
      // 通常のDMG/HEAT/posture解決だけが起こることを検証する
      // （FINISHER自体のdirectPin/submissionHold本処理は
      // combat_v1_finisher_test.dartを参照）。
      const directPinNormal = _directPinNormalTechnique;
      final catalog = CombatV1CardCatalog(
        techniques: {...fixtureTechniques, directPinNormal.id: directPinNormal},
        counters: fixtureCounters,
      );
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'pm_direct_pin_normal',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry], hpB: 150);
      final pinCardsBefore = state.playerA.pinCardsHeld;
      final kocBefore = state.playerA.koc;

      final pending = CombatV1Engine.declareTechnique(state, 'a1', catalog: catalog);
      final resolved = CombatV1Engine.declineCounter(pending, random: Random(1));

      expect(resolved.playerB.hp, 150 - directPinNormal.damage);
      // PIN/KOC関連フィールドは一切変化しない（Phase5まで未実装）。
      expect(resolved.playerA.pinCardsHeld, pinCardsBefore);
      expect(resolved.playerA.koc, kocBefore);
    });

    test('submissionHold==trueの技がCOUNTER成立で無効化された場合もSUBMISSION関連の変化は無い', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_signature_b', // submissionHold==true, family=bodyPress
        category: CombatV1CardCategory.signature,
      );
      final counterEntry = const CombatV1DeckEntry(
        instanceId: 'c1',
        cardId: 'fx_counter_c', // families=[dropKick]。bodyPressとは非対応なので
        // このテストの主眼はCOUNTER成立可否ではなくSUBMISSION未発火の確認。
        category: CombatV1CardCategory.counter,
      );
      final state = buildMatchState(handA: [entry], handB: [counterEntry]);
      final pending = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);
      final kocBefore = state.playerB.koc;

      // COUNTERは不成立（family不一致）だが、declineでもSUBMISSION処理は
      // 発火しない（Phase 6まで未実装）ことを確認する。
      final resolved = CombatV1Engine.declineCounter(pending, random: Random(1));
      expect(resolved.playerB.koc, kocBefore);
    });
  });
}

const _directPinNormalTechnique = CombatV1Technique(
  id: 'pm_direct_pin_normal',
  name: 'テストDIRECT PIN技（NORMAL）',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.strike,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
  damage: 15,
  heatGain: 15,
  directPin: true,
  family: CombatV1TechniqueFamily.tackle,
);
