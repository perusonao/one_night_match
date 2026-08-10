// Combat Ver.1 Phase 4: COUNTER関連Invalid Commandのatomicity検証
// （不正Command呼び出し時のfail-fast方針は
// docs/design/combat_v1_phase1_design.md 4章、テスト項目31-H）。
//
// Phase 3 Codexレビューで、atomicity testのsnapshotがMatchState全体を
// 比較していない点が指摘された（Phase 3レビューM4）。Phase 4では
// [_FullStateSnapshot]でplayerA/playerB全field（wrestlerId/wrestlerName/
// maxHp/hp/koc/pinCardsHeld/posture/energyPool/spentEnergy/hand/drawPile/
// discardPile/reshuffleCount/techniquesUsedThisTurn）・matchId・
// sharedHeat・activePlayerIndex・turnNumber・phase・pendingAttack全field・
// lastSuccessfulTechnique・log内容全体を含めて意味的完全同値であることを
// 検証する（単なるinstanceId一覧やlist長ではなく、値そのものを比較する。
// Phase 4 Codexレビュー指摘M1）。Phase 5で`winnerPlayerIndex`・
// `lastSuccessfulTechnique.turnNumber`を追加した。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_counter.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_pending_attack.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_state_invariants.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_successful_technique_snapshot.dart';

import 'combat_v1_test_fixtures.dart';

/// カード1枚を(instanceId, cardId, category)のタプルとして比較する
/// （instanceIdだけでなくcardId/categoryも意味的に一致することを要求する、
/// Phase 4 Codexレビュー指摘M1）。
(String, String, CombatV1CardCategory) _cardTuple(CombatV1DeckEntry e) =>
    (e.instanceId, e.cardId, e.category);

List<(String, String, CombatV1CardCategory)> _cardTuples(
  List<CombatV1DeckEntry> entries,
) => entries.map(_cardTuple).toList();

/// [CombatV1MatchState]の全fieldを比較するsnapshot（Phase 3 Codexレビュー
/// M4／Phase 4 Codexレビュー指摘M1対応）。
class _FullStateSnapshot {
  _FullStateSnapshot(CombatV1MatchState s)
    : matchId = s.matchId,
      playerA = _PlayerSnapshot(s.playerA),
      playerB = _PlayerSnapshot(s.playerB),
      activePlayerIndex = s.activePlayerIndex,
      sharedHeat = s.sharedHeat,
      turnNumber = s.turnNumber,
      phase = s.phase,
      pendingAttack = s.pendingAttack == null
          ? null
          : _PendingAttackSnapshot(s.pendingAttack!),
      lastSuccessfulTechnique = s.lastSuccessfulTechnique == null
          ? null
          : _LastSuccessfulTechniqueSnapshot(s.lastSuccessfulTechnique!),
      winnerPlayerIndex = s.winnerPlayerIndex,
      log = List.of(s.log);

  final String matchId;
  final _PlayerSnapshot playerA;
  final _PlayerSnapshot playerB;
  final int activePlayerIndex;
  final int sharedHeat;
  final int turnNumber;
  final CombatV1MatchPhase phase;
  final _PendingAttackSnapshot? pendingAttack;
  final _LastSuccessfulTechniqueSnapshot? lastSuccessfulTechnique;
  final int? winnerPlayerIndex;
  final List<String> log;

  void expectUnchanged(CombatV1MatchState after, {String? reason}) {
    expect(after.matchId, matchId, reason: '$reason: matchId');
    playerA.expectUnchanged(after.playerA, label: 'playerA', reason: reason);
    playerB.expectUnchanged(after.playerB, label: 'playerB', reason: reason);
    expect(after.activePlayerIndex, activePlayerIndex, reason: '$reason: activePlayerIndex');
    expect(after.sharedHeat, sharedHeat, reason: '$reason: sharedHeat');
    expect(after.turnNumber, turnNumber, reason: '$reason: turnNumber');
    expect(after.phase, phase, reason: '$reason: phase');
    if (pendingAttack == null) {
      expect(after.pendingAttack, isNull, reason: '$reason: pendingAttack');
    } else {
      expect(after.pendingAttack, isNotNull, reason: '$reason: pendingAttack');
      pendingAttack!.expectUnchanged(after.pendingAttack!, reason: reason);
    }
    if (lastSuccessfulTechnique == null) {
      expect(
        after.lastSuccessfulTechnique,
        isNull,
        reason: '$reason: lastSuccessfulTechnique',
      );
    } else {
      expect(
        after.lastSuccessfulTechnique,
        isNotNull,
        reason: '$reason: lastSuccessfulTechnique',
      );
      lastSuccessfulTechnique!.expectUnchanged(
        after.lastSuccessfulTechnique!,
        reason: reason,
      );
    }
    expect(
      after.winnerPlayerIndex,
      winnerPlayerIndex,
      reason: '$reason: winnerPlayerIndex',
    );
    expect(List.of(after.log), log, reason: '$reason: log');
  }
}

/// [CombatV1SuccessfulTechniqueSnapshot]の全fieldを比較するsnapshot
/// （Phase 4 Codex再レビュー指摘M1対応。旧実装は`cardInstanceId`のみを
/// 比較しており、他fieldの意図しない変化を検出できなかった。Phase
/// 5で`turnNumber`を追加）。
class _LastSuccessfulTechniqueSnapshot {
  _LastSuccessfulTechniqueSnapshot(CombatV1SuccessfulTechniqueSnapshot s)
    : attackerPlayerIndex = s.attackerPlayerIndex,
      turnNumber = s.turnNumber,
      cardInstanceId = s.cardInstanceId,
      cardId = s.cardId,
      category = s.category,
      attribute = s.attribute,
      family = s.family,
      directPin = s.directPin,
      submissionHold = s.submissionHold,
      finisherType = s.finisherType,
      resultOpponentState = s.resultOpponentState;

  final int attackerPlayerIndex;
  final int turnNumber;
  final String cardInstanceId;
  final String cardId;
  final CombatV1CardCategory category;
  final CombatV1EnergyAttribute attribute;
  final CombatV1TechniqueFamily family;
  final bool directPin;
  final bool submissionHold;
  final CombatV1FinisherType? finisherType;
  final CombatV1WrestlerPosture? resultOpponentState;

  void expectUnchanged(CombatV1SuccessfulTechniqueSnapshot after, {String? reason}) {
    expect(
      after.attackerPlayerIndex,
      attackerPlayerIndex,
      reason: '$reason: lastSuccessfulTechnique.attackerPlayerIndex',
    );
    expect(
      after.turnNumber,
      turnNumber,
      reason: '$reason: lastSuccessfulTechnique.turnNumber',
    );
    expect(
      after.cardInstanceId,
      cardInstanceId,
      reason: '$reason: lastSuccessfulTechnique.cardInstanceId',
    );
    expect(after.cardId, cardId, reason: '$reason: lastSuccessfulTechnique.cardId');
    expect(after.category, category, reason: '$reason: lastSuccessfulTechnique.category');
    expect(after.attribute, attribute, reason: '$reason: lastSuccessfulTechnique.attribute');
    expect(after.family, family, reason: '$reason: lastSuccessfulTechnique.family');
    expect(after.directPin, directPin, reason: '$reason: lastSuccessfulTechnique.directPin');
    expect(
      after.submissionHold,
      submissionHold,
      reason: '$reason: lastSuccessfulTechnique.submissionHold',
    );
    expect(
      after.finisherType,
      finisherType,
      reason: '$reason: lastSuccessfulTechnique.finisherType',
    );
    expect(
      after.resultOpponentState,
      resultOpponentState,
      reason: '$reason: lastSuccessfulTechnique.resultOpponentState',
    );
  }
}

class _PendingAttackSnapshot {
  _PendingAttackSnapshot(CombatV1PendingAttack p)
    : attackerPlayerIndex = p.attackerPlayerIndex,
      defenderPlayerIndex = p.defenderPlayerIndex,
      attackCard = _cardTuple(p.attackCardInstance),
      category = p.category,
      attribute = p.attribute,
      family = p.family,
      energyCostAmounts = Map.of(p.energyCost.amounts),
      damage = p.damage,
      heatGain = p.heatGain,
      requiredOpponentState = p.requiredOpponentState,
      resultOpponentState = p.resultOpponentState,
      directPin = p.directPin,
      submissionHold = p.submissionHold,
      finisherType = p.finisherType;

  final int attackerPlayerIndex;
  final int defenderPlayerIndex;
  final (String, String, CombatV1CardCategory) attackCard;
  final CombatV1CardCategory category;
  final CombatV1EnergyAttribute attribute;
  final CombatV1TechniqueFamily family;
  final Map<CombatV1EnergyAttribute, int> energyCostAmounts;
  final int damage;
  final int heatGain;
  final CombatV1WrestlerPosture? requiredOpponentState;
  final CombatV1WrestlerPosture? resultOpponentState;
  final bool directPin;
  final bool submissionHold;
  final CombatV1FinisherType? finisherType;

  void expectUnchanged(CombatV1PendingAttack after, {String? reason}) {
    expect(after.attackerPlayerIndex, attackerPlayerIndex, reason: '$reason: pending.attacker');
    expect(after.defenderPlayerIndex, defenderPlayerIndex, reason: '$reason: pending.defender');
    expect(_cardTuple(after.attackCardInstance), attackCard, reason: '$reason: pending.card');
    expect(after.category, category, reason: '$reason: pending.category');
    expect(after.attribute, attribute, reason: '$reason: pending.attribute');
    expect(after.family, family, reason: '$reason: pending.family');
    expect(
      after.energyCost.amounts,
      equals(energyCostAmounts),
      reason: '$reason: pending.energyCost',
    );
    expect(after.damage, damage, reason: '$reason: pending.damage');
    expect(after.heatGain, heatGain, reason: '$reason: pending.heatGain');
    expect(
      after.requiredOpponentState,
      requiredOpponentState,
      reason: '$reason: pending.requiredOpponentState',
    );
    expect(
      after.resultOpponentState,
      resultOpponentState,
      reason: '$reason: pending.resultOpponentState',
    );
    expect(after.directPin, directPin, reason: '$reason: pending.directPin');
    expect(after.submissionHold, submissionHold, reason: '$reason: pending.submissionHold');
    expect(after.finisherType, finisherType, reason: '$reason: pending.finisherType');
  }
}

class _PlayerSnapshot {
  _PlayerSnapshot(CombatV1PlayerState p)
    : wrestlerId = p.wrestlerId,
      wrestlerName = p.wrestlerName,
      maxHp = p.maxHp,
      hp = p.hp,
      koc = p.koc,
      pinCardsHeld = p.pinCardsHeld,
      posture = p.posture,
      energyPoolAmounts = Map.of(p.energyPool.amounts),
      spentEnergy = Map.of(p.spentEnergy),
      hand = _cardTuples(p.hand),
      drawPile = _cardTuples(p.drawPile),
      discardPile = _cardTuples(p.discardPile),
      reshuffleCount = p.reshuffleCount,
      techniquesUsedThisTurn = p.techniquesUsedThisTurn;

  final String wrestlerId;
  final String wrestlerName;
  final int maxHp;
  final int hp;
  final int koc;
  final int pinCardsHeld;
  final CombatV1WrestlerPosture posture;
  final Map<CombatV1EnergyAttribute, int> energyPoolAmounts;
  final Map<CombatV1EnergyAttribute, int> spentEnergy;
  final List<(String, String, CombatV1CardCategory)> hand;
  final List<(String, String, CombatV1CardCategory)> drawPile;
  final List<(String, String, CombatV1CardCategory)> discardPile;
  final int reshuffleCount;
  final int techniquesUsedThisTurn;

  void expectUnchanged(CombatV1PlayerState after, {required String label, String? reason}) {
    expect(after.wrestlerId, wrestlerId, reason: '$reason: $label.wrestlerId');
    expect(after.wrestlerName, wrestlerName, reason: '$reason: $label.wrestlerName');
    expect(after.maxHp, maxHp, reason: '$reason: $label.maxHp');
    expect(after.hp, hp, reason: '$reason: $label.hp');
    expect(after.koc, koc, reason: '$reason: $label.koc');
    expect(after.pinCardsHeld, pinCardsHeld, reason: '$reason: $label.pinCardsHeld');
    expect(after.posture, posture, reason: '$reason: $label.posture');
    expect(
      after.energyPool.amounts,
      equals(energyPoolAmounts),
      reason: '$reason: $label.energyPool',
    );
    expect(after.spentEnergy, equals(spentEnergy), reason: '$reason: $label.spentEnergy');
    expect(_cardTuples(after.hand), hand, reason: '$reason: $label.hand');
    expect(_cardTuples(after.drawPile), drawPile, reason: '$reason: $label.drawPile');
    expect(_cardTuples(after.discardPile), discardPile, reason: '$reason: $label.discardPile');
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
  const directPinAttack = CombatV1DeckEntry(
    instanceId: 'atk_dp',
    cardId: 'fx_normal_direct_pin', // 投1, STAND->DOWN, directPin=true
    category: CombatV1CardCategory.normal,
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
        'ctr_wild': CombatV1Counter(
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

  group('malformed pending — Command実行前ガード（18、Phase 4 Codexレビュー指摘H1）', () {
    test('malformed_pending_attacker_index_is_rejected: '
        'pending.attackerPlayerIndexがstate.activePlayerIndexと不一致なら拒否', () {
      final pending = pendingState();
      // activePlayerIndex==0のまま、pending.attackerPlayerIndexだけ1に
      // すり替えた不正なpendingへ差し替える（本来到達しない直接構築）。
      final malformedPending = CombatV1PendingAttack(
        attackerPlayerIndex: 1, // 本来0であるべき
        defenderPlayerIndex: 0,
        attackCardInstance: pending.pendingAttack!.attackCardInstance,
        category: pending.pendingAttack!.category,
        attribute: pending.pendingAttack!.attribute,
        family: pending.pendingAttack!.family,
        energyCost: pending.pendingAttack!.energyCost,
        damage: pending.pendingAttack!.damage,
        heatGain: pending.pendingAttack!.heatGain,
      );
      final malformedState = pending.copyWith(pendingAttack: malformedPending);
      final snapshot = _FullStateSnapshot(malformedState);

      expect(
        () => CombatV1Engine.playCounter(
          malformedState,
          'ctr1',
          catalog: fixtureCatalog,
          rules: fixtureRules,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(malformedState, reason: 'malformed attacker index (playCounter)');

      expect(
        () => CombatV1Engine.declineCounter(malformedState),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(malformedState, reason: 'malformed attacker index (declineCounter)');
    });

    test('malformed_pending_defender_index_is_rejected: '
        'pending.defenderPlayerIndexが期待値と不一致なら拒否', () {
      final pending = pendingState();
      // activePlayerIndex==0のまま、pending.defenderPlayerIndexを
      // attackerPlayerIndexと同じ0にすり替えた不正なpending。
      final malformedPending = CombatV1PendingAttack(
        attackerPlayerIndex: 0,
        defenderPlayerIndex: 0, // 本来1であるべき
        attackCardInstance: pending.pendingAttack!.attackCardInstance,
        category: pending.pendingAttack!.category,
        attribute: pending.pendingAttack!.attribute,
        family: pending.pendingAttack!.family,
        energyCost: pending.pendingAttack!.energyCost,
        damage: pending.pendingAttack!.damage,
        heatGain: pending.pendingAttack!.heatGain,
      );
      final malformedState = pending.copyWith(pendingAttack: malformedPending);
      final snapshot = _FullStateSnapshot(malformedState);

      expect(
        () => CombatV1Engine.playCounter(
          malformedState,
          'ctr1',
          catalog: fixtureCatalog,
          rules: fixtureRules,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(malformedState, reason: 'malformed defender index (playCounter)');

      expect(
        () => CombatV1Engine.declineCounter(malformedState),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(malformedState, reason: 'malformed defender index (declineCounter)');
    });

    test('phase_pending_invariant_mismatch_is_rejected（Given A: '
        'phase=action かつ pendingAttackが存在する不整合state）', () {
      final pending = pendingState();
      // phaseだけをactionへ戻し、pendingAttackはそのまま残した不整合state
      // （本来到達しない直接構築）。
      final malformedState = pending.copyWith(phase: CombatV1MatchPhase.action);
      final snapshot = _FullStateSnapshot(malformedState);

      expect(
        () => CombatV1Engine.declareTechnique(
          malformedState,
          malformedState.active.hand.isEmpty ? 'dummy' : malformedState.active.hand.first.instanceId,
          catalog: fixtureCatalog,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(malformedState, reason: 'phase=action with pendingAttack present');
    });

    test('phase_pending_invariant_mismatch_is_rejected（Given B: '
        'phase=counterResponsePending かつ pendingAttack=null）', () {
      final malformedState = buildMatchState(
        phase: CombatV1MatchPhase.counterResponsePending,
        handA: const [attack],
        handB: const [matchingCounter],
      );
      final snapshot = _FullStateSnapshot(malformedState);

      expect(
        () => CombatV1Engine.playCounter(
          malformedState,
          'ctr1',
          catalog: fixtureCatalog,
          rules: fixtureRules,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(malformedState, reason: 'phase=pending, pendingAttack=null (playCounter)');

      expect(
        () => CombatV1Engine.declineCounter(malformedState),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(
        malformedState,
        reason: 'phase=pending, pendingAttack=null (declineCounter)',
      );
    });
  });

  group('malformed pending card ownership — Command実行前ガード'
      '（Phase 4 Codex再レビュー指摘H1残件: pendingAttackOwnershipViolation）', () {
    // 各シナリオは「pendingが所有するはずの攻撃カードが、本来あり得ない
    // ゾーンにも存在する（A〜F）」または「pending.attackCardInstance.category
    // がpending.categoryと不一致（G）」という、宣言時のコミット処理が
    // 本来到達させない不整合stateを直接構築する（テーブル駆動）。
    final scenarios = <String, CombatV1MatchState Function(CombatV1MatchState pending)>{
      'A: attacker handに残存': (pending) => pending.copyWith(
        playerA: pending.playerA.copyWith(
          hand: [...pending.playerA.hand, pending.pendingAttack!.attackCardInstance],
        ),
      ),
      'B: attacker drawPileに残存': (pending) => pending.copyWith(
        playerA: pending.playerA.copyWith(
          drawPile: [...pending.playerA.drawPile, pending.pendingAttack!.attackCardInstance],
        ),
      ),
      'C: attacker discardPileに残存': (pending) => pending.copyWith(
        playerA: pending.playerA.copyWith(
          discardPile: [...pending.playerA.discardPile, pending.pendingAttack!.attackCardInstance],
        ),
      ),
      'D: defender handに重複instanceId': (pending) => pending.copyWith(
        playerB: pending.playerB.copyWith(
          hand: [...pending.playerB.hand, pending.pendingAttack!.attackCardInstance],
        ),
      ),
      'E: defender drawPileに重複instanceId': (pending) => pending.copyWith(
        playerB: pending.playerB.copyWith(
          drawPile: [...pending.playerB.drawPile, pending.pendingAttack!.attackCardInstance],
        ),
      ),
      'F: defender discardPileに重複instanceId': (pending) => pending.copyWith(
        playerB: pending.playerB.copyWith(
          discardPile: [...pending.playerB.discardPile, pending.pendingAttack!.attackCardInstance],
        ),
      ),
      'G: attackCardInstance.categoryがpending.categoryと不一致': (pending) {
        final original = pending.pendingAttack!;
        final mismatched = CombatV1PendingAttack(
          attackerPlayerIndex: original.attackerPlayerIndex,
          defenderPlayerIndex: original.defenderPlayerIndex,
          attackCardInstance: CombatV1DeckEntry(
            instanceId: original.attackCardInstance.instanceId,
            cardId: original.attackCardInstance.cardId,
            category: CombatV1CardCategory.signature, // original.category(normal)と不一致
          ),
          category: original.category,
          attribute: original.attribute,
          family: original.family,
          energyCost: original.energyCost,
          damage: original.damage,
          heatGain: original.heatGain,
        );
        return pending.copyWith(pendingAttack: mismatched);
      },
    };

    for (final entry in scenarios.entries) {
      test('${entry.key}: playCounter/declineCounterが拒否されstate完全不変'
          '（既存のlastSuccessfulTechniqueも含め不変）', () {
        // lastSuccessfulTechniqueがすでに非nullの状態から出発し、malformed
        // ownership拒否がその値まで含めて完全に不変であることを検証する
        // （M1: lastSuccessfulTechniqueの全field比較）。
        var base = declareAndResolveTechnique(
          buildMatchState(handA: const [
            CombatV1DeckEntry(
              instanceId: 'warmup',
              cardId: 'fx_normal_strike',
              category: CombatV1CardCategory.normal,
            ),
          ]),
          'warmup',
          catalog: fixtureCatalog,
          random: Random(1),
        );
        expect(base.lastSuccessfulTechnique, isNotNull);

        base = base.withActive(base.active.copyWith(hand: const [attack]));
        base = base.withOpponent(base.opponent.copyWith(hand: const [matchingCounter]));
        final pending = CombatV1Engine.declareTechnique(base, 'atk1', catalog: fixtureCatalog);

        final malformedState = entry.value(pending);
        final snapshot = _FullStateSnapshot(malformedState);

        expect(
          () => CombatV1Engine.playCounter(
            malformedState,
            'ctr1',
            catalog: fixtureCatalog,
            rules: fixtureRules,
          ),
          throwsA(isA<CombatV1IllegalActionException>()),
        );
        snapshot.expectUnchanged(malformedState, reason: '${entry.key} (playCounter)');

        expect(
          () => CombatV1Engine.declineCounter(malformedState),
          throwsA(isA<CombatV1IllegalActionException>()),
        );
        snapshot.expectUnchanged(malformedState, reason: '${entry.key} (declineCounter)');
      });
    }
  });

  group('Phase 5: 不正PIN Commandのatomicity（docs/combat_rules_v1.md 8章）', () {
    test('wrong phase（discard中）でdeclarePinは失敗しstate完全不変', () {
      final state = buildMatchState(
        phase: CombatV1MatchPhase.discard,
        postureB: CombatV1WrestlerPosture.down,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final snapshot = _FullStateSnapshot(state);

      expect(
        () => CombatV1Engine.declarePin(state, rules: fixtureRules),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(state, reason: 'wrong phase declarePin');
    });

    test('相手がSTANDでdeclarePinは失敗しstate完全不変（KOC/PINカードも不変）', () {
      final state = buildMatchState(
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final snapshot = _FullStateSnapshot(state);

      expect(
        () => CombatV1Engine.declarePin(state, rules: fixtureRules),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(state, reason: 'opponentNotDown declarePin');
    });

    test('このターン中の成功記録が無い場合、declarePinは失敗しstate完全不変', () {
      final state = buildMatchState(postureB: CombatV1WrestlerPosture.down);
      final snapshot = _FullStateSnapshot(state);

      expect(
        () => CombatV1Engine.declarePin(state, rules: fixtureRules),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(state, reason: 'noSuccessfulTechniqueThisTurn declarePin');
    });

    test('試合終了後（winnerPlayerIndex設定済み）は全戦闘Commandが拒否されstate完全不変', () {
      final endedState = buildMatchState(
        handA: const [attack],
        handB: const [matchingCounter],
      ).copyWith(winnerPlayerIndex: 0);
      final snapshot = _FullStateSnapshot(endedState);

      expect(
        () => CombatV1Engine.declareTechnique(
          endedState,
          'atk1',
          catalog: fixtureCatalog,
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(endedState, reason: 'matchOver declareTechnique');

      expect(
        () => CombatV1Engine.declarePin(endedState, rules: fixtureRules),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(endedState, reason: 'matchOver declarePin');

      expect(
        () => CombatV1Engine.endTurn(endedState),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(endedState, reason: 'matchOver endTurn');

      expect(
        () => CombatV1Engine.discardCard(endedState, 'atk1'),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(endedState, reason: 'matchOver discardCard');
    });
  });

  group('Phase 5 Codexレビュー修正: PIN state invariant guard atomicity（H1/H2）', () {
    final directPinCatalog = CombatV1CardCatalog(
      techniques: fixtureTechniques,
      counters: fixtureCounters,
    );

    test('A: attacker pinCardsHeld=0（defender=4）はcheckPinLegality/declarePinとも拒否されstate完全不変', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        pinCardsHeldA: 0,
        pinCardsHeldB: 4,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final snapshot = _FullStateSnapshot(state);

      expect(CombatV1Engine.checkPinLegality(state, rules: fixtureRules).legal, isFalse);
      expect(
        () => CombatV1Engine.declarePin(state, rules: fixtureRules),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(state, reason: 'A: attacker pinCardsHeld=0');
    });

    test('B: PINカード合計=3はdeclarePinが拒否されstate完全不変', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        pinCardsHeldA: 1,
        pinCardsHeldB: 2,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final snapshot = _FullStateSnapshot(state);

      expect(
        () => CombatV1Engine.declarePin(state, rules: fixtureRules),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(state, reason: 'B: PINカード合計=3');
    });

    test('C: PINカード合計=5はdeclarePinが拒否されstate完全不変', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        pinCardsHeldA: 2,
        pinCardsHeldB: 3,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final snapshot = _FullStateSnapshot(state);

      expect(
        () => CombatV1Engine.declarePin(state, rules: fixtureRules),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(state, reason: 'C: PINカード合計=5');
    });

    test('D: defender koc=-1はdeclarePinが拒否され、3カウント勝利にせずwinner未設定・state完全不変', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocB: -1,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final snapshot = _FullStateSnapshot(state);

      expect(
        () => CombatV1Engine.declarePin(state, rules: fixtureRules),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(state, reason: 'D: defender koc=-1');
      expect(state.winnerPlayerIndex, isNull);
    });

    test('E: attacker koc=-1はdeclarePinが拒否されstate完全不変', () {
      final state = buildMatchState(
        postureB: CombatV1WrestlerPosture.down,
        kocA: -1,
        lastSuccessfulTechnique: fixtureSuccessfulTechnique(
          attackerPlayerIndex: 0,
          turnNumber: 1,
        ),
      );
      final snapshot = _FullStateSnapshot(state);

      expect(
        () => CombatV1Engine.declarePin(state, rules: fixtureRules),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(state, reason: 'E: attacker koc=-1');
    });

    test('F: DIRECT PIN予定TechniqueでPhase 5 invariant違反stateはdeclineCounterごと拒否され、'
        'Technique成功処理を含め全state完全不変', () {
      final state = buildMatchState(
        handA: const [directPinAttack],
        kocB: -1, // 防御側kocが不正（Phase 5 invariant違反）
      );
      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk_dp',
        catalog: directPinCatalog,
      );
      final snapshot = _FullStateSnapshot(declared);

      expect(
        () => CombatV1Engine.declineCounter(
          declared,
          rules: fixtureRules,
          random: Random(1),
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      // DMG/HEAT/posture/discard/draw/lastSuccessfulTechnique/koc/
      // pinCardsHeld/winner/phase/logのすべてが宣言直後のstateから
      // 完全に不変であること（Technique成功だけ残してPINだけ拒否する
      // 設計にはなっていないことの確認）。
      snapshot.expectUnchanged(declared, reason: 'F: DIRECT PIN malformed invariant');
      expect(declared.playerB.posture, CombatV1WrestlerPosture.stand);
      expect(declared.lastSuccessfulTechnique, isNull);
      expect(declared.winnerPlayerIndex, isNull);
    });

    test('G: winnerPlayerIndex=-1はvalidateMatchStateInvariantsでinvalid', () {
      final state = buildMatchState().copyWith(winnerPlayerIndex: -1);
      final result = validateMatchStateInvariants(state, rules: fixtureRules);
      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.code == CombatV1MatchStateInvariantErrorCode.winnerPlayerIndexOutOfRange,
        ),
        isTrue,
      );
    });

    test('H: winnerPlayerIndex=2はvalidateMatchStateInvariantsでinvalid', () {
      final state = buildMatchState().copyWith(winnerPlayerIndex: 2);
      final result = validateMatchStateInvariants(state, rules: fixtureRules);
      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.code == CombatV1MatchStateInvariantErrorCode.winnerPlayerIndexOutOfRange,
        ),
        isTrue,
      );
    });

    test('I: winnerPlayerIndex=null/0/1はいずれもwinnerPlayerIndexOutOfRangeを生成しない', () {
      for (final winner in [null, 0, 1]) {
        final state = buildMatchState().copyWith(winnerPlayerIndex: winner);
        final result = validateMatchStateInvariants(state, rules: fixtureRules);
        expect(
          result.errors.any(
            (e) => e.code == CombatV1MatchStateInvariantErrorCode.winnerPlayerIndexOutOfRange,
          ),
          isFalse,
          reason: 'winnerPlayerIndex=$winner',
        );
      }
    });
  });
}
