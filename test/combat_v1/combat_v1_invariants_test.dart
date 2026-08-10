// Combat Ver.1 Phase 4 Codexレビュー指摘H1: PendingAttack/MatchState
// invariantの検証（`pendingStructuralConsistencyViolation`・
// `validateMatchStateInvariants`、テスト項目18・19）。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_pending_attack.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_state_invariants.dart';

import 'combat_v1_test_fixtures.dart';

const _attack = CombatV1DeckEntry(
  instanceId: 'atk1',
  cardId: 'fx_normal_strike',
  category: CombatV1CardCategory.normal,
);
const _counter = CombatV1DeckEntry(
  instanceId: 'ctr1',
  cardId: 'fx_counter_a',
  category: CombatV1CardCategory.counter,
);

CombatV1PendingAttack _validPending({
  int attackerPlayerIndex = 0,
  int defenderPlayerIndex = 1,
  CombatV1DeckEntry attackCardInstance = _attack,
  CombatV1CardCategory category = CombatV1CardCategory.normal,
}) => CombatV1PendingAttack(
  attackerPlayerIndex: attackerPlayerIndex,
  defenderPlayerIndex: defenderPlayerIndex,
  attackCardInstance: attackCardInstance,
  category: category,
  attribute: CombatV1EnergyAttribute.strike,
  family: CombatV1TechniqueFamily.elbow,
  energyCost: const CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
  damage: 10,
  heatGain: 10,
);

void main() {
  group('pendingStructuralConsistencyViolation — 整合性のあるstateはnull', () {
    test('pendingなし・phase==actionはconsistent', () {
      final state = buildMatchState(handA: const [_attack]);
      expect(pendingStructuralConsistencyViolation(state), isNull);
    });

    test('pending整合・phase==counterResponsePendingはconsistent', () {
      final state = buildMatchState(handA: const [_attack]).copyWith(
        phase: CombatV1MatchPhase.counterResponsePending,
        pendingAttack: _validPending(),
      );
      expect(pendingStructuralConsistencyViolation(state), isNull);
    });
  });

  group('pendingStructuralConsistencyViolation — 不整合を検出する（A〜F）', () {
    test('A: phase==counterResponsePendingだがpendingAttack==nullは不整合', () {
      final state = buildMatchState(
        phase: CombatV1MatchPhase.counterResponsePending,
        handA: const [_attack],
      );
      expect(pendingStructuralConsistencyViolation(state), isNotNull);
    });

    test('B: pendingAttackが存在するがphase!=counterResponsePendingは不整合', () {
      final state = buildMatchState(handA: const [_attack]).copyWith(
        pendingAttack: _validPending(),
      );
      expect(pendingStructuralConsistencyViolation(state), isNotNull);
    });

    test('C: pending.attackerPlayerIndexがstate.activePlayerIndexと不一致は不整合', () {
      final state = buildMatchState(handA: const [_attack]).copyWith(
        phase: CombatV1MatchPhase.counterResponsePending,
        pendingAttack: _validPending(attackerPlayerIndex: 1, defenderPlayerIndex: 0),
      );
      expect(pendingStructuralConsistencyViolation(state), isNotNull);
    });

    test('D: pending.defenderPlayerIndexが期待値(1-active)と不一致は不整合', () {
      final state = buildMatchState(handA: const [_attack]).copyWith(
        phase: CombatV1MatchPhase.counterResponsePending,
        pendingAttack: _validPending(attackerPlayerIndex: 0, defenderPlayerIndex: 0),
      );
      expect(pendingStructuralConsistencyViolation(state), isNotNull);
    });

    test('E: attacker/defenderPlayerIndexが0/1の範囲外は不整合', () {
      final state = buildMatchState(handA: const [_attack]).copyWith(
        phase: CombatV1MatchPhase.counterResponsePending,
        pendingAttack: _validPending(attackerPlayerIndex: 2, defenderPlayerIndex: 1),
      );
      expect(pendingStructuralConsistencyViolation(state), isNotNull);
    });

    test('F: attackerPlayerIndex == defenderPlayerIndexは不整合', () {
      final state = buildMatchState(handA: const [_attack]).copyWith(
        phase: CombatV1MatchPhase.counterResponsePending,
        pendingAttack: _validPending(attackerPlayerIndex: 0, defenderPlayerIndex: 0),
      );
      expect(pendingStructuralConsistencyViolation(state), isNotNull);
    });
  });

  group('validateMatchStateInvariants — 整合したstateはvalid', () {
    test('pendingなしの通常stateはvalid', () {
      final state = buildMatchState(handA: const [_attack]);
      expect(validateMatchStateInvariants(state).isValid, isTrue);
    });

    test('正しくpending中のstateはvalid', () {
      final state = buildMatchState(handB: const [_counter]).copyWith(
        phase: CombatV1MatchPhase.counterResponsePending,
        pendingAttack: _validPending(),
      );
      expect(validateMatchStateInvariants(state).isValid, isTrue);
    });
  });

  group('validateMatchStateInvariants — G/H: pending card ownership（19）', () {
    test('G: pendingが所有するはずのカードが攻撃側handにも存在すれば'
        'pendingCardStillInAttackerZoneを検出', () {
      // attackCardInstanceと同じinstanceIdのカードをplayerAのhandにも
      // 残したまま（本来は宣言時に除去されるはずの不整合）。
      final state = buildMatchState(handA: const [_attack]).copyWith(
        phase: CombatV1MatchPhase.counterResponsePending,
        pendingAttack: _validPending(),
      );
      final result = validateMatchStateInvariants(state);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1MatchStateInvariantErrorCode.pendingCardStillInAttackerZone),
      );
    });

    test('H: pendingが所有するカードのinstanceIdが防御側handにも存在すれば'
        'pendingCardInDefenderZoneを検出', () {
      final duplicated = const CombatV1DeckEntry(
        instanceId: 'atk1', // pendingと同じinstanceId
        cardId: 'fx_counter_a',
        category: CombatV1CardCategory.counter,
      );
      final state = buildMatchState(handB: [duplicated]).copyWith(
        phase: CombatV1MatchPhase.counterResponsePending,
        pendingAttack: _validPending(),
      );
      final result = validateMatchStateInvariants(state);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1MatchStateInvariantErrorCode.pendingCardInDefenderZone),
      );
    });
  });

  group('validateMatchStateInvariants — I: instanceId重複（19）', () {
    test('pending_card_duplicate_ownership_is_rejected: 同一instanceIdが'
        'pendingとhand/draw/discardのどこかに重複していれば'
        'duplicateCardInstanceIdを検出', () {
      final duplicated = const CombatV1DeckEntry(
        instanceId: 'atk1',
        cardId: 'fx_normal_strike_alt',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(drawPileA: [duplicated]).copyWith(
        phase: CombatV1MatchPhase.counterResponsePending,
        pendingAttack: _validPending(),
      );
      final result = validateMatchStateInvariants(state);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1MatchStateInvariantErrorCode.duplicateCardInstanceId),
      );
    });

    test('通常のhand/drawPile/discardPile間でinstanceIdが重複していても検出する'
        '（pendingが無くても機能する）', () {
      final dup1 = const CombatV1DeckEntry(
        instanceId: 'dup',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final dup2 = const CombatV1DeckEntry(
        instanceId: 'dup',
        cardId: 'fx_normal_strike_alt',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [dup1], drawPileA: [dup2]);
      final result = validateMatchStateInvariants(state);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1MatchStateInvariantErrorCode.duplicateCardInstanceId),
      );
    });
  });

  group('validateMatchStateInvariants — K: pending category整合性（19）', () {
    test('attackCardInstance.categoryとpending.categoryが不一致なら'
        'pendingCardCategoryMismatchを検出', () {
      final mismatched = const CombatV1DeckEntry(
        instanceId: 'atk1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.signature, // pending.category(normal)と不一致
      );
      final state = buildMatchState().copyWith(
        phase: CombatV1MatchPhase.counterResponsePending,
        pendingAttack: _validPending(
          attackCardInstance: mismatched,
          category: CombatV1CardCategory.normal,
        ),
      );
      final result = validateMatchStateInvariants(state);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1MatchStateInvariantErrorCode.pendingCardCategoryMismatch),
      );
    });
  });

  group('validateMatchStateInvariants — F/E: attacker==defender・範囲外index（19）', () {
    test('attacker == defenderはpendingAttackerEqualsDefenderを検出', () {
      final state = buildMatchState().copyWith(
        phase: CombatV1MatchPhase.counterResponsePending,
        pendingAttack: _validPending(attackerPlayerIndex: 0, defenderPlayerIndex: 0),
      );
      final result = validateMatchStateInvariants(state);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1MatchStateInvariantErrorCode.pendingAttackerEqualsDefender),
      );
    });

    test('playerIndexが範囲外はpendingPlayerIndexOutOfRangeを検出', () {
      final state = buildMatchState().copyWith(
        phase: CombatV1MatchPhase.counterResponsePending,
        pendingAttack: _validPending(attackerPlayerIndex: 5, defenderPlayerIndex: 1),
      );
      final result = validateMatchStateInvariants(state);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1MatchStateInvariantErrorCode.pendingPlayerIndexOutOfRange),
      );
    });
  });
}
