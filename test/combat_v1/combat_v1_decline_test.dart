// Combat Ver.1 Phase 4: declineCounter（COUNTERしない場合の攻撃成立）の検証
// （docs/combat_rules_v1.md 7.1章、テスト項目31-F）。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';

import 'combat_v1_test_fixtures.dart';

void main() {
  const attack = CombatV1DeckEntry(
    instanceId: 'atk1',
    cardId: 'fx_normal_throw_down', // damage20, heat20, STAND->DOWN
    category: CombatV1CardCategory.normal,
  );
  const counter = CombatV1DeckEntry(
    instanceId: 'ctr1',
    cardId: 'fx_counter_a', // groups=[strike]、backdrop/slam系とは非対応
    category: CombatV1CardCategory.counter,
  );

  CombatV1MatchState pendingState({
    int hpB = 150,
    int sharedHeat = 0,
    CombatV1WrestlerPosture postureB = CombatV1WrestlerPosture.stand,
    List<CombatV1DeckEntry> drawPileA = const [],
    List<CombatV1DeckEntry> handB = const [counter],
  }) {
    final state = buildMatchState(
      handA: const [attack],
      handB: handB,
      hpB: hpB,
      sharedHeat: sharedHeat,
      postureB: postureB,
      drawPileA: drawPileA,
    );
    return CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
  }

  group('declineCounter — 攻撃成立', () {
    test('DMGが適用される', () {
      final pending = pendingState(hpB: 150);
      final after = CombatV1Engine.declineCounter(pending, random: Random(1));
      expect(after.playerB.hp, 130); // 150 - 20
    });

    test('HPは0未満にならない（クランプ）', () {
      final pending = pendingState(hpB: 5);
      final after = CombatV1Engine.declineCounter(pending, random: Random(1));
      expect(after.playerB.hp, 0);
    });

    test('sharedHeatが加算される', () {
      final pending = pendingState(sharedHeat: 0);
      final after = CombatV1Engine.declineCounter(pending, random: Random(1));
      expect(after.sharedHeat, 20);
    });

    test('相手postureが変化する', () {
      final pending = pendingState(postureB: CombatV1WrestlerPosture.stand);
      final after = CombatV1Engine.declineCounter(pending, random: Random(1));
      expect(after.playerB.posture, CombatV1WrestlerPosture.down);
    });

    test('攻撃カードは攻撃側のdiscardへ移動する', () {
      // drawPileAへfillerを用意しておく（decline直後の1
      // drawで、drawPile空→捨て札再構築が起きて直前に捨てたばかりの攻撃
      // カードが即座に引き戻されてしまうのを避けるため、Phase
      // 3のtest 44と同じ理由）。
      final filler = const CombatV1DeckEntry(
        instanceId: 'filler',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final pending = pendingState(drawPileA: [filler]);
      final after = CombatV1Engine.declineCounter(pending, random: Random(1));
      expect(after.playerA.discardPile.any((e) => e.instanceId == 'atk1'), isTrue);
    });

    test('攻撃側が1枚drawする', () {
      final reserve = const CombatV1DeckEntry(
        instanceId: 'reserve',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final pending = pendingState(drawPileA: [reserve]);
      final after = CombatV1Engine.declineCounter(pending, random: Random(1));
      expect(after.playerA.hand.any((e) => e.instanceId == 'reserve'), isTrue);
      expect(after.playerA.drawPile, isEmpty);
    });

    test('防御側はdrawしない（COUNTER成功時とは異なりdefenderの手札構成は'
        'discard/drawの影響を受けない）', () {
      final pending = pendingState(handB: const [counter]);
      final handBSizeBefore = pending.playerB.hand.length;
      final after = CombatV1Engine.declineCounter(pending, random: Random(1));
      expect(after.playerB.hand.length, handBSizeBefore);
    });

    test('pendingがクリアされ、phaseがactionへ戻る', () {
      final pending = pendingState();
      final after = CombatV1Engine.declineCounter(pending, random: Random(1));
      expect(after.pendingAttack, isNull);
      expect(after.phase, CombatV1MatchPhase.action);
    });

    test('activePlayerIndexは宣言側のまま', () {
      final pending = pendingState();
      final after = CombatV1Engine.declineCounter(pending, random: Random(1));
      expect(after.activePlayerIndex, 0);
    });

    test('decline経路の結果はPhase 3の即時成功解決と同じ（declareAndResolveTechniqueヘルパー'
        'と同一の最終状態になる）', () {
      final state = buildMatchState(handA: const [attack], hpB: 150, sharedHeat: 0);
      final viaHelper = declareAndResolveTechnique(
        state,
        'atk1',
        catalog: fixtureCatalog,
        random: Random(1),
      );
      expect(viaHelper.playerB.hp, 130);
      expect(viaHelper.sharedHeat, 20);
      expect(viaHelper.playerB.posture, CombatV1WrestlerPosture.down);
      expect(viaHelper.phase, CombatV1MatchPhase.action);
    });
  });
}
