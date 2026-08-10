// Combat Ver.1 Phase 11B: CombatV1DecisionPolicy（FirstLegal/RandomLegal）の
// テスト。
//
// FirstLegalは「自然な強いCPU」ではなく、deterministic baselineであること
// （優先順位・List入力順への非依存・同type内tie-break・fail-fast）を検証
// する。RandomLegalはtype-first random（物理action全体からの一様random
// ではない）ことをfake/seed固定Randomで直接検証する（「必ず正確に50%」の
// ようなfragile assertionはしない）。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_decision_policy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';

import 'combat_v1_test_fixtures.dart';

/// 常に指定したシーケンスを返すfake Random（`nextInt`の呼び出し引数と
/// 戻り値を記録する。テストでtype-first random selectionを決定的に検証
/// するための最小限のスタブ）。
class _ScriptedRandom implements Random {
  _ScriptedRandom(this._script);

  final List<int> _script;
  final List<int> boundsSeen = [];
  int _cursor = 0;

  @override
  int nextInt(int max) {
    boundsSeen.add(max);
    final value = _script[_cursor % _script.length];
    _cursor++;
    return value;
  }

  @override
  double nextDouble() => throw UnimplementedError();

  @override
  bool nextBool() => throw UnimplementedError();
}

void main() {
  group('CombatV1FirstLegalPolicy', () {
    const policy = CombatV1FirstLegalPolicy();

    test('emptyでfail-fastする', () {
      expect(
        () => policy.choose(_anyState(), const []),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('優先順位: PIN > Counter > declineCounter > standUp > Technique > '
        'REST > endTurn > discard', () {
      const endTurn = CombatV1EndTurnAction(actorPlayerIndex: 0);
      const technique = CombatV1TechniqueAction(
        actorPlayerIndex: 0,
        cardInstanceId: 't1',
      );
      const pin = CombatV1PinAction(actorPlayerIndex: 0);
      const rest = CombatV1RestAction(actorPlayerIndex: 0);
      const standUp = CombatV1StandUpAction(actorPlayerIndex: 0);
      const decline = CombatV1DeclineCounterAction(actorPlayerIndex: 1);
      const counter = CombatV1CounterAction(
        actorPlayerIndex: 1,
        cardInstanceId: 'c1',
      );
      const discard = CombatV1DiscardAction(
        actorPlayerIndex: 0,
        cardInstanceId: 'd1',
      );

      // PINが最優先。
      expect(
        policy.choose(_anyState(), [endTurn, technique, rest, pin, standUp]),
        pin,
      );
      // PIN無しならCounter。
      expect(
        policy.choose(_anyState(), [decline, counter, endTurn]),
        counter,
      );
      // PIN/Counter無しならdeclineCounter。
      expect(policy.choose(_anyState(), [endTurn, decline]), decline);
      // PIN/Counter/decline無しならstandUp。
      expect(policy.choose(_anyState(), [technique, standUp, rest]), standUp);
      // 上記が無ければTechnique。
      expect(policy.choose(_anyState(), [rest, technique, endTurn]), technique);
      // Technique無しならREST。
      expect(policy.choose(_anyState(), [endTurn, rest]), rest);
      // REST無しならendTurn。
      expect(policy.choose(_anyState(), [discard, endTurn]), endTurn);
      // 他が無ければdiscard。
      expect(policy.choose(_anyState(), [discard]), discard);
    });

    test('入力List順に依存しない（同じ集合なら順序を変えても同じ結果）', () {
      const technique1 = CombatV1TechniqueAction(
        actorPlayerIndex: 0,
        cardInstanceId: 'b',
      );
      const technique2 = CombatV1TechniqueAction(
        actorPlayerIndex: 0,
        cardInstanceId: 'a',
      );
      const endTurn = CombatV1EndTurnAction(actorPlayerIndex: 0);

      final forward = policy.choose(_anyState(), [technique1, technique2, endTurn]);
      final reversed = policy.choose(_anyState(), [endTurn, technique2, technique1]);
      final shuffled = policy.choose(_anyState(), [technique2, endTurn, technique1]);

      expect(forward, technique2); // cardInstanceId昇順tie-breakで'a'が選ばれる
      expect(reversed, forward);
      expect(shuffled, forward);
    });

    test('同typeはcardInstanceId昇順でdeterministicに選ぶ', () {
      const t3 = CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'z');
      const t1 = CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'a');
      const t2 = CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 'm');

      expect(policy.choose(_anyState(), [t3, t1, t2]), t1);
    });

    test('policy idは安定している', () {
      expect(policy.id, 'firstLegal');
    });
  });

  group('CombatV1RandomLegalPolicy', () {
    test('emptyでfail-fastする', () {
      final policy = CombatV1RandomLegalPolicy(Random(1));
      expect(
        () => policy.choose(_anyState(), const []),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('policy idは安定している', () {
      final policy = CombatV1RandomLegalPolicy(Random(1));
      expect(policy.id, 'randomLegal');
    });

    test('type-first random: type選択→type内選択の2段階でnextIntが呼ばれる', () {
      const t1 = CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 't1');
      const t2 = CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 't2');
      const pin = CombatV1PinAction(actorPlayerIndex: 0);
      const endTurn = CombatV1EndTurnAction(actorPlayerIndex: 0);

      // canonical順（discard,technique,counter,declineCounter,pin,rest,
      // standUp,endTurn）で今回存在するのはtechnique/pin/endTurnの3種→
      // インデックス0がtechnique。script[0]=0でtechnique typeを選び、
      // script[1]=1でtechnique内の2枚目(t2)を選ぶ。
      final random = _ScriptedRandom([0, 1]);
      final policy = CombatV1RandomLegalPolicy(random);

      final chosen = policy.choose(_anyState(), [t1, t2, pin, endTurn]);

      expect(chosen, t2);
      // 1回目=type数(3)からの選択、2回目=technique候補数(2)からの選択。
      expect(random.boundsSeen, [3, 2]);
    });

    test('カード枚数が多いtypeほど選ばれやすくならない'
        '（Technique8枚 vs PIN1件でもtype selectionはtype数のみに基づく）', () {
      final techniques = [
        for (var i = 0; i < 8; i++)
          CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 't$i'),
      ];
      const pin = CombatV1PinAction(actorPlayerIndex: 0);
      const endTurn = CombatV1EndTurnAction(actorPlayerIndex: 0);

      // script[0]=1 → canonical順(technique,pin,endTurn)のindex1=pinを選択。
      // script[1]=0 → pin type内の候補(1件)からindex0を選択。
      final random = _ScriptedRandom([1, 0]);
      final policy = CombatV1RandomLegalPolicy(random);

      final chosen = policy.choose(_anyState(), [...techniques, pin, endTurn]);

      expect(chosen, pin);
      // 1回目はtypeの数(3)、2回目はpin type内の候補数(1)がnextIntの引数に
      // なる。8という手札枚数はtype selectionには影響しない。
      expect(random.boundsSeen, [3, 1]);
    });

    test('Counter複数枚でもCounter-vs-declineのtype probability構造が変わらない', () {
      const c1 = CombatV1CounterAction(actorPlayerIndex: 1, cardInstanceId: 'c1');
      const c2 = CombatV1CounterAction(actorPlayerIndex: 1, cardInstanceId: 'c2');
      const c3 = CombatV1CounterAction(actorPlayerIndex: 1, cardInstanceId: 'c3');
      const decline = CombatV1DeclineCounterAction(actorPlayerIndex: 1);

      // canonical順でcounter/declineCounterの2 typeのみ存在 → index0=counter。
      final chooseCounterType = CombatV1RandomLegalPolicy(_ScriptedRandom([0, 2]));
      final chosen = chooseCounterType.choose(_anyState(), [c1, c2, c3, decline]);
      expect(chosen, c3); // counter type内の3枚目(index2)

      // index1=declineCounter typeを選ぶ場合、Counterの枚数に関わらず
      // 1回のnextIntで確定する（type内候補が1件のため2回目は`nextInt(1)`）。
      final randomB = _ScriptedRandom([1, 0]);
      final chooseDeclineType = CombatV1RandomLegalPolicy(randomB);
      final chosenB = chooseDeclineType.choose(_anyState(), [c1, c2, c3, decline]);
      expect(chosenB, decline);
      expect(randomB.boundsSeen, [2, 1]);
    });

    test('同seedなら選択sequenceが再現する', () {
      const t1 = CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 't1');
      const t2 = CombatV1TechniqueAction(actorPlayerIndex: 0, cardInstanceId: 't2');
      const endTurn = CombatV1EndTurnAction(actorPlayerIndex: 0);
      final legalActions = [t1, t2, endTurn];

      final policyA = CombatV1RandomLegalPolicy(Random(42));
      final policyB = CombatV1RandomLegalPolicy(Random(42));

      final sequenceA = [
        for (var i = 0; i < 10; i++) policyA.choose(_anyState(), legalActions),
      ];
      final sequenceB = [
        for (var i = 0; i < 10; i++) policyB.choose(_anyState(), legalActions),
      ];

      expect(sequenceA, sequenceB);
    });
  });
}

// choose()の実装はstate引数を参照しないため、有効な最小stateを1つ使い回す。
CombatV1MatchState _anyState() => buildMatchState();
