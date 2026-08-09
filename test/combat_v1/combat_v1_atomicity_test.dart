// Combat Ver.1 Phase 4: COUNTER関連Invalid Commandのatomicity検証
// （不正Command呼び出し時のfail-fast方針は
// docs/design/combat_v1_phase1_design.md 4章、テスト項目31-H）。
//
// Phase 3 Codexレビューで、atomicity testのsnapshotがMatchState全体を
// 比較していない点が指摘された（Phase 3レビューM4）。Phase
// 4では[_FullStateSnapshot]でplayerA/playerB全field・sharedHeat・
// activePlayerIndex・turnNumber・phase・pendingAttack・logを含めて
// 意味的完全同値であることを検証する。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_counter.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';

import 'combat_v1_test_fixtures.dart';

/// [CombatV1MatchState]の全fieldを比較するsnapshot（Phase 3 Codexレビュー
/// M4「atomicity testのsnapshotがMatchState全体を比較していない」への
/// Phase 4対応）。
class _FullStateSnapshot {
  _FullStateSnapshot(CombatV1MatchState s)
    : playerA = _PlayerSnapshot(s.playerA),
      playerB = _PlayerSnapshot(s.playerB),
      activePlayerIndex = s.activePlayerIndex,
      sharedHeat = s.sharedHeat,
      turnNumber = s.turnNumber,
      phase = s.phase,
      pendingAttackCardInstanceId = s.pendingAttack?.attackCardInstance.instanceId,
      logLength = s.log.length;

  final _PlayerSnapshot playerA;
  final _PlayerSnapshot playerB;
  final int activePlayerIndex;
  final int sharedHeat;
  final int turnNumber;
  final CombatV1MatchPhase phase;
  final String? pendingAttackCardInstanceId;
  final int logLength;

  void expectUnchanged(CombatV1MatchState after, {String? reason}) {
    playerA.expectUnchanged(after.playerA, label: 'playerA', reason: reason);
    playerB.expectUnchanged(after.playerB, label: 'playerB', reason: reason);
    expect(after.activePlayerIndex, activePlayerIndex, reason: '$reason: activePlayerIndex');
    expect(after.sharedHeat, sharedHeat, reason: '$reason: sharedHeat');
    expect(after.turnNumber, turnNumber, reason: '$reason: turnNumber');
    expect(after.phase, phase, reason: '$reason: phase');
    expect(
      after.pendingAttack?.attackCardInstance.instanceId,
      pendingAttackCardInstanceId,
      reason: '$reason: pendingAttack',
    );
    expect(after.log.length, logLength, reason: '$reason: log');
  }
}

class _PlayerSnapshot {
  _PlayerSnapshot(CombatV1PlayerState p)
    : hp = p.hp,
      koc = p.koc,
      pinCardsHeld = p.pinCardsHeld,
      posture = p.posture,
      spentEnergy = Map.of(p.spentEnergy),
      hand = p.hand.map((e) => e.instanceId).toList(),
      drawPile = p.drawPile.map((e) => e.instanceId).toList(),
      discardPile = p.discardPile.map((e) => e.instanceId).toList(),
      reshuffleCount = p.reshuffleCount,
      techniquesUsedThisTurn = p.techniquesUsedThisTurn;

  final int hp;
  final int koc;
  final int pinCardsHeld;
  final CombatV1WrestlerPosture posture;
  final Map<CombatV1EnergyAttribute, int> spentEnergy;
  final List<String> hand;
  final List<String> drawPile;
  final List<String> discardPile;
  final int reshuffleCount;
  final int techniquesUsedThisTurn;

  void expectUnchanged(CombatV1PlayerState after, {required String label, String? reason}) {
    expect(after.hp, hp, reason: '$reason: $label.hp');
    expect(after.koc, koc, reason: '$reason: $label.koc');
    expect(after.pinCardsHeld, pinCardsHeld, reason: '$reason: $label.pinCardsHeld');
    expect(after.posture, posture, reason: '$reason: $label.posture');
    expect(after.spentEnergy, equals(spentEnergy), reason: '$reason: $label.spentEnergy');
    expect(
      after.hand.map((e) => e.instanceId).toList(),
      hand,
      reason: '$reason: $label.hand',
    );
    expect(
      after.drawPile.map((e) => e.instanceId).toList(),
      drawPile,
      reason: '$reason: $label.drawPile',
    );
    expect(
      after.discardPile.map((e) => e.instanceId).toList(),
      discardPile,
      reason: '$reason: $label.discardPile',
    );
    expect(after.reshuffleCount, reshuffleCount, reason: '$reason: $label.reshuffleCount');
    expect(
      after.techniquesUsedThisTurn,
      techniquesUsedThisTurn,
      reason: '$reason: $label.techniquesUsedThisTurn',
    );
  }
}

void main() {
  const attack = CombatV1DeckEntry(
    instanceId: 'atk1',
    cardId: 'fx_normal_strike', // 打1, family=elbow(STRIKE)
    category: CombatV1CardCategory.normal,
  );
  const matchingCounter = CombatV1DeckEntry(
    instanceId: 'ctr1',
    cardId: 'fx_counter_a', // attribute=strike, groups=[strike]
    category: CombatV1CardCategory.counter,
  );
  const mismatchCounter = CombatV1DeckEntry(
    instanceId: 'ctr_narrow',
    cardId: 'fx_counter_c', // families=[dropKick]のみ
    category: CombatV1CardCategory.counter,
  );

  CombatV1MatchState pendingState({
    List<CombatV1DeckEntry> handB = const [matchingCounter],
    Map<CombatV1EnergyAttribute, int> spentB = const {},
  }) {
    final state = buildMatchState(
      handA: const [attack],
      handB: handB,
      spentB: spentB,
    );
    return CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
  }

  test('pendingなし（phase==action）でplayCounter/declineCounterは失敗しstate完全不変', () {
    final state = buildMatchState(handA: const [attack], handB: const [matchingCounter]);
    final snapshot = _FullStateSnapshot(state);

    expect(
      () => CombatV1Engine.playCounter(
        state,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      ),
      throwsA(isA<CombatV1IllegalActionException>()),
    );
    snapshot.expectUnchanged(state, reason: 'pendingなしplayCounter');

    expect(
      () => CombatV1Engine.declineCounter(state),
      throwsA(isA<CombatV1IllegalActionException>()),
    );
    snapshot.expectUnchanged(state, reason: 'pendingなしdeclineCounter');
  });

  test('wrong phase（discard中）でplayCounterは失敗しstate完全不変', () {
    final state = buildMatchState(
      phase: CombatV1MatchPhase.discard,
      handA: const [attack],
      handB: const [matchingCounter],
    );
    final snapshot = _FullStateSnapshot(state);

    expect(
      () => CombatV1Engine.playCounter(
        state,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      ),
      throwsA(isA<CombatV1IllegalActionException>()),
    );
    snapshot.expectUnchanged(state, reason: 'wrong phase');
  });

  test('攻撃側自身の手札のカードでplayCounterを試みると失敗しstate完全不変（wrong responder）', () {
    // 攻撃側(playerA)がmatchingCounterを保持していた状況を構築する
    // （防御側の手札は空）。
    final state = buildMatchState(
      handA: const [attack, matchingCounter],
      handB: const [],
    );
    final wrongResponderPending =
        CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);
    final snapshot = _FullStateSnapshot(wrongResponderPending);

    expect(
      () => CombatV1Engine.playCounter(
        wrongResponderPending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      ),
      throwsA(isA<CombatV1IllegalActionException>()),
    );
    snapshot.expectUnchanged(wrongResponderPending, reason: 'wrong responder');
  });

  test('Counterがhandに無い場合playCounterは失敗しstate完全不変', () {
    final pending = pendingState(handB: const []);
    final snapshot = _FullStateSnapshot(pending);

    expect(
      () => CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      ),
      throwsA(isA<CombatV1IllegalActionException>()),
    );
    snapshot.expectUnchanged(pending, reason: 'Counterがhandに無い');
  });

  test('Catalog missing（未知cardId）でplayCounterは失敗しstate完全不変', () {
    final pending = pendingState(
      handB: const [
        CombatV1DeckEntry(
          instanceId: 'unknown',
          cardId: 'does_not_exist',
          category: CombatV1CardCategory.counter,
        ),
      ],
    );
    final snapshot = _FullStateSnapshot(pending);

    expect(
      () => CombatV1Engine.playCounter(
        pending,
        'unknown',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      ),
      throwsA(isA<CombatV1IllegalActionException>()),
    );
    snapshot.expectUnchanged(pending, reason: 'Catalog missing');
  });

  test('COUNTERではないカード（TECHNIQUE）でplayCounterは失敗しstate完全不変', () {
    final pending = pendingState(
      handB: const [
        CombatV1DeckEntry(
          instanceId: 'not_a_counter',
          cardId: 'fx_normal_strike',
          category: CombatV1CardCategory.normal,
        ),
      ],
    );
    final snapshot = _FullStateSnapshot(pending);

    expect(
      () => CombatV1Engine.playCounter(
        pending,
        'not_a_counter',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      ),
      throwsA(isA<CombatV1IllegalActionException>()),
    );
    snapshot.expectUnchanged(pending, reason: 'COUNTERではないカード');
  });

  test('family mismatchでplayCounterは失敗しstate完全不変', () {
    final pending = pendingState(handB: const [mismatchCounter]);
    final snapshot = _FullStateSnapshot(pending);

    expect(
      () => CombatV1Engine.playCounter(
        pending,
        'ctr_narrow',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      ),
      throwsA(isA<CombatV1IllegalActionException>()),
    );
    snapshot.expectUnchanged(pending, reason: 'family mismatch');
  });

  test('group mismatchでplayCounterは失敗しstate完全不変', () {
    final state = buildMatchState(
      handA: const [
        CombatV1DeckEntry(
          instanceId: 'atk_throw',
          cardId: 'fx_normal_throw_down', // family=slam(THROW)
          category: CombatV1CardCategory.normal,
        ),
      ],
      handB: const [matchingCounter], // groups=[strike]のみ
    );
    final pending = CombatV1Engine.declareTechnique(state, 'atk_throw', catalog: fixtureCatalog);
    final snapshot = _FullStateSnapshot(pending);

    expect(
      () => CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      ),
      throwsA(isA<CombatV1IllegalActionException>()),
    );
    snapshot.expectUnchanged(pending, reason: 'group mismatch');
  });

  test('ENERGY不足でplayCounterは失敗しstate完全不変', () {
    final pending = pendingState(spentB: const {CombatV1EnergyAttribute.strike: 2});
    final snapshot = _FullStateSnapshot(pending);

    expect(
      () => CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      ),
      throwsA(isA<CombatV1IllegalActionException>()),
    );
    snapshot.expectUnchanged(pending, reason: 'ENERGY不足');
  });

  test('wild disabledでwild補完が必要な場合playCounterは失敗しstate完全不変', () {
    final pending = pendingState(
      spentB: const {
        CombatV1EnergyAttribute.strike: 2, // 残り0（打2使い切り）
      },
    );
    final snapshot = _FullStateSnapshot(pending);
    const rulesNoWild = CombatV1RulesConfig(); // counterAllowsWildSubstitution: false

    expect(
      () => CombatV1Engine.playCounter(
        pending,
        'ctr1',
        catalog: fixtureCatalog,
        rules: rulesNoWild,
      ),
      throwsA(isA<CombatV1IllegalActionException>()),
    );
    snapshot.expectUnchanged(pending, reason: 'wild disabled');
  });

  test('invalid Counter data（catalog上attribute==wild）でplayCounterは失敗しstate完全不変', () {
    final catalog = CombatV1CardCatalog(
      techniques: fixtureTechniques,
      counters: {
        ...fixtureCounters,
        'ctr_wild': const CombatV1Counter(
          id: 'ctr_wild',
          name: '不正カウンター',
          attribute: CombatV1EnergyAttribute.wild,
          counterableGroups: [CombatV1TechniqueFamilyGroup.strike],
        ),
      },
    );
    final pending = pendingState(
      handB: const [
        CombatV1DeckEntry(
          instanceId: 'ctr_wild_instance',
          cardId: 'ctr_wild',
          category: CombatV1CardCategory.counter,
        ),
      ],
    );
    final snapshot = _FullStateSnapshot(pending);

    expect(
      () => CombatV1Engine.playCounter(
        pending,
        'ctr_wild_instance',
        catalog: catalog,
        rules: fixtureRules,
      ),
      throwsA(isA<CombatV1IllegalActionException>()),
    );
    snapshot.expectUnchanged(pending, reason: 'invalid Counter data');
  });

  test('COUNTER成立後の二重応答（playCounter）は失敗しstate完全不変', () {
    final pending = pendingState();
    final resolved = CombatV1Engine.playCounter(
      pending,
      'ctr1',
      catalog: fixtureCatalog,
      rules: fixtureRules,
      random: Random(1),
    );
    final snapshot = _FullStateSnapshot(resolved);

    expect(
      () => CombatV1Engine.playCounter(
        resolved,
        'ctr1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
      ),
      throwsA(isA<CombatV1IllegalActionException>()),
    );
    snapshot.expectUnchanged(resolved, reason: '二重response');
  });
}
