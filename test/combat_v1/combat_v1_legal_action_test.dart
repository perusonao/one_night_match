// Combat Ver.1 Phase 11B: CombatV1LegalAction（sealed data model）のテスト。
//
// このファイルはEngine/Enumerator/Policy/Executorを一切呼び出さず、
// LegalAction自身が要求されたpayload（actorPlayerIndex・物理instanceId・
// kind）を正しく保持することだけを検証する。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';

void main() {
  group('A. sealed variantsが必要payloadを保持する', () {
    test('CombatV1DiscardActionはactorPlayerIndex/cardInstanceIdを保持する', () {
      const action = CombatV1DiscardAction(
        actorPlayerIndex: 0,
        cardInstanceId: 'inst-1',
      );
      expect(action.actorPlayerIndex, 0);
      expect(action.cardInstanceId, 'inst-1');
      expect(action.kind, CombatV1LegalActionKind.discard);
    });

    test('CombatV1TechniqueActionはactorPlayerIndex/cardInstanceIdを保持する', () {
      const action = CombatV1TechniqueAction(
        actorPlayerIndex: 1,
        cardInstanceId: 'inst-2',
      );
      expect(action.actorPlayerIndex, 1);
      expect(action.cardInstanceId, 'inst-2');
      expect(action.kind, CombatV1LegalActionKind.technique);
    });

    test('CombatV1CounterActionはactorPlayerIndex/cardInstanceIdを保持する', () {
      const action = CombatV1CounterAction(
        actorPlayerIndex: 1,
        cardInstanceId: 'inst-3',
      );
      expect(action.actorPlayerIndex, 1);
      expect(action.cardInstanceId, 'inst-3');
      expect(action.kind, CombatV1LegalActionKind.counter);
    });

    test('カードを使わないvariant（declineCounter/pin/rest/standUp/endTurn）は'
        'cardInstanceIdを持たない（null）', () {
      const declineCounter = CombatV1DeclineCounterAction(actorPlayerIndex: 1);
      const pin = CombatV1PinAction(actorPlayerIndex: 0);
      const rest = CombatV1RestAction(actorPlayerIndex: 0);
      const standUp = CombatV1StandUpAction(actorPlayerIndex: 0);
      const endTurn = CombatV1EndTurnAction(actorPlayerIndex: 0);

      expect(declineCounter.cardInstanceId, isNull);
      expect(pin.cardInstanceId, isNull);
      expect(rest.cardInstanceId, isNull);
      expect(standUp.cardInstanceId, isNull);
      expect(endTurn.cardInstanceId, isNull);

      expect(declineCounter.kind, CombatV1LegalActionKind.declineCounter);
      expect(pin.kind, CombatV1LegalActionKind.pin);
      expect(rest.kind, CombatV1LegalActionKind.rest);
      expect(standUp.kind, CombatV1LegalActionKind.standUp);
      expect(endTurn.kind, CombatV1LegalActionKind.endTurn);
    });
  });

  group('B. cardIdではなくphysical instanceIdを使用する', () {
    test('CombatV1TechniqueActionのcardInstanceIdは物理instanceId', () {
      // 同名カード（同じcardId）でも異なるinstanceIdを別Actionとして表現
      // できることを確認する。
      const actionA = CombatV1TechniqueAction(
        actorPlayerIndex: 0,
        cardInstanceId: 'wrestlerA_fx_normal_strike_#0',
      );
      const actionB = CombatV1TechniqueAction(
        actorPlayerIndex: 0,
        cardInstanceId: 'wrestlerA_fx_normal_strike_#1',
      );
      expect(actionA.cardInstanceId, isNot(actionB.cardInstanceId));
      expect(actionA, isNot(actionB));
    });
  });

  group('C. actorPlayerIndexの確認', () {
    test('actorPlayerIndexは0/1のいずれも保持できる', () {
      const forA = CombatV1EndTurnAction(actorPlayerIndex: 0);
      const forB = CombatV1EndTurnAction(actorPlayerIndex: 1);
      expect(forA.actorPlayerIndex, 0);
      expect(forB.actorPlayerIndex, 1);
    });

    test('COUNTER系のactorPlayerIndexは防御側を表現できる'
        '（Enumeratorが導出する値をそのまま保持するだけ）', () {
      // activePlayerIndex==0（攻撃側）のときの防御側は1。
      const counter = CombatV1CounterAction(
        actorPlayerIndex: 1,
        cardInstanceId: 'ctr-1',
      );
      const decline = CombatV1DeclineCounterAction(actorPlayerIndex: 1);
      expect(counter.actorPlayerIndex, 1);
      expect(decline.actorPlayerIndex, 1);
    });
  });

  group('value equality（テスト・重複排除の利便性のため）', () {
    test('同じフィールドを持つActionは等しい', () {
      const a1 = CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'x');
      const a2 = CombatV1DiscardAction(actorPlayerIndex: 0, cardInstanceId: 'x');
      expect(a1, a2);
      expect(a1.hashCode, a2.hashCode);
    });

    test('異なるvariant同士は等しくない', () {
      const pin = CombatV1PinAction(actorPlayerIndex: 0);
      const rest = CombatV1RestAction(actorPlayerIndex: 0);
      expect(pin, isNot(rest));
    });
  });
}
