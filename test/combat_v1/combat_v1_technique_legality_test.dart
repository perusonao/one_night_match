// Combat Ver.1 Phase 3: TECHNIQUE Core完成 + COUNTER受け入れ準備の検証
// （docs/combat_rules_v1.md、docs/design/combat_v1_phase1_design.md）。
//
// 対象:
// - 静的データvalidation（EnergyPool/EnergyCost/Technique/PlayerState invariant）
// - TECHNIQUE legalityの正式化（reasonCodeベース）
// - 失敗Commandのatomicity
// - 連続TECHNIQUE使用・DOWN/STAND
// - Phase境界（ROUGH通常解決、FINISHER/COUNTER未処理、Combo Speed不採用）
//
// 方針は既存のcombat_v1_engine_test.dart/combat_v1_deck_hand_test.dartと同じ:
// シャッフル結果に依存しない決定的なテストにするため、MatchState/PlayerState
// を直接組み立ててからCommand APIを呼ぶ。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_state_invariants.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';

import 'combat_v1_test_fixtures.dart';

/// `phase == action`・playerAが手番、というテスト用の最小状態を直接組み立てる
/// （combat_v1_engine_test.dartのbuildActionStateと同じ方針）。
CombatV1MatchState _buildState({
  CombatV1MatchPhase phase = CombatV1MatchPhase.action,
  List<CombatV1DeckEntry> handA = const [],
  List<CombatV1DeckEntry> drawPileA = const [],
  List<CombatV1DeckEntry> discardPileA = const [],
  List<CombatV1DeckEntry> handB = const [],
  int hpA = 150,
  int hpB = 150,
  Map<CombatV1EnergyAttribute, int> spentA = const {},
  CombatV1WrestlerPosture postureA = CombatV1WrestlerPosture.stand,
  CombatV1WrestlerPosture postureB = CombatV1WrestlerPosture.stand,
  int sharedHeat = 0,
  int techniquesUsedA = 0,
}) {
  final playerA = CombatV1PlayerState(
    wrestlerId: fixtureWrestlerA.id,
    wrestlerName: fixtureWrestlerA.name,
    maxHp: 150,
    hp: hpA,
    koc: 10,
    pinCardsHeld: 2,
    posture: postureA,
    energyPool: fixtureWrestlerA.energyPool,
    spentEnergy: spentA,
    hand: handA,
    drawPile: drawPileA,
    discardPile: discardPileA,
    techniquesUsedThisTurn: techniquesUsedA,
  );
  final playerB = CombatV1PlayerState(
    wrestlerId: fixtureWrestlerB.id,
    wrestlerName: fixtureWrestlerB.name,
    maxHp: 150,
    hp: hpB,
    koc: 10,
    pinCardsHeld: 2,
    posture: postureB,
    energyPool: fixtureWrestlerB.energyPool,
    hand: handB,
  );
  return CombatV1MatchState(
    matchId: 'phase3-test-match',
    playerA: playerA,
    playerB: playerB,
    activePlayerIndex: 0,
    sharedHeat: sharedHeat,
    turnNumber: 1,
    phase: phase,
  );
}

/// declareTechnique失敗時のatomicity検証用スナップショット
/// （docs/combat_rules_v1.md、■12 atomicity）。
class _StateSnapshot {
  _StateSnapshot(CombatV1MatchState s)
    : hpA = s.playerA.hp,
      hpB = s.playerB.hp,
      sharedHeat = s.sharedHeat,
      handA = s.playerA.hand.map((e) => e.instanceId).toList(),
      drawA = s.playerA.drawPile.map((e) => e.instanceId).toList(),
      discardA = s.playerA.discardPile.map((e) => e.instanceId).toList(),
      postureA = s.playerA.posture,
      postureB = s.playerB.posture,
      spentA = Map.of(s.playerA.spentEnergy),
      techniquesUsedA = s.playerA.techniquesUsedThisTurn,
      reshuffleA = s.playerA.reshuffleCount,
      activePlayerIndex = s.activePlayerIndex,
      turnNumber = s.turnNumber,
      phase = s.phase;

  final int hpA;
  final int hpB;
  final int sharedHeat;
  final List<String> handA;
  final List<String> drawA;
  final List<String> discardA;
  final CombatV1WrestlerPosture postureA;
  final CombatV1WrestlerPosture postureB;
  final Map<CombatV1EnergyAttribute, int> spentA;
  final int techniquesUsedA;
  final int reshuffleA;
  final int activePlayerIndex;
  final int turnNumber;
  final CombatV1MatchPhase phase;

  void expectUnchanged(CombatV1MatchState after) {
    expect(after.playerA.hp, hpA, reason: 'HP(A)が変化した');
    expect(after.playerB.hp, hpB, reason: 'HP(B)が変化した');
    expect(after.sharedHeat, sharedHeat, reason: 'sharedHeatが変化した');
    expect(
      after.playerA.hand.map((e) => e.instanceId).toList(),
      handA,
      reason: 'hand(A)が変化した',
    );
    expect(
      after.playerA.drawPile.map((e) => e.instanceId).toList(),
      drawA,
      reason: 'drawPile(A)が変化した',
    );
    expect(
      after.playerA.discardPile.map((e) => e.instanceId).toList(),
      discardA,
      reason: 'discardPile(A)が変化した',
    );
    expect(after.playerA.posture, postureA, reason: 'posture(A)が変化した');
    expect(after.playerB.posture, postureB, reason: 'posture(B)が変化した');
    expect(after.playerA.spentEnergy, equals(spentA), reason: 'spentEnergy(A)が変化した');
    expect(
      after.playerA.techniquesUsedThisTurn,
      techniquesUsedA,
      reason: 'techniquesUsedThisTurnが変化した',
    );
    expect(after.playerA.reshuffleCount, reshuffleA, reason: 'reshuffleCountが変化した');
    expect(
      after.activePlayerIndex,
      activePlayerIndex,
      reason: 'activePlayerIndexが変化した',
    );
    expect(after.turnNumber, turnNumber, reason: 'turnNumberが変化した');
    expect(after.phase, phase, reason: 'phaseが変化した');
  }
}

/// requiredOpponentState==standのテスト専用技（フィクスチャ標準カタログには
/// STAND限定技が無いため、このファイル内でのみ使うローカル技として定義）。
const CombatV1Technique _fxRequireStand = CombatV1Technique(
  id: 'fx_require_stand',
  name: 'テストSTAND限定技',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.strike,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
  damage: 10,
  heatGain: 10,
  requiredOpponentState: CombatV1WrestlerPosture.stand,
  family: CombatV1TechniqueFamily.knee,
);

/// ENERGY COSTにwildを直接指定した不正な静的データ（Phase 3で拒否対象、
/// docs/combat_rules_v1.md 5.1章）。
const CombatV1Technique _fxInvalidWildCost = CombatV1Technique(
  id: 'fx_invalid_wild_cost',
  name: 'テスト不正技（wild cost）',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.strike,
  energyCost: CombatV1EnergyCost({
    CombatV1EnergyAttribute.strike: 1,
    CombatV1EnergyAttribute.wild: 1,
  }),
  damage: 10,
  heatGain: 10,
  family: CombatV1TechniqueFamily.kick,
);

/// ENERGY COSTに負数を直接指定した不正な静的データ。
const CombatV1Technique _fxInvalidNegativeCost = CombatV1Technique(
  id: 'fx_invalid_negative_cost',
  name: 'テスト不正技（負数cost）',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.strike,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: -1}),
  damage: 10,
  heatGain: 10,
  family: CombatV1TechniqueFamily.knee,
);

/// ROUGH属性のテスト専用技（フィクスチャ標準カタログにはROUGH技が無いため
/// このファイル内でのみ使う）。Phase 3ではROUGHも通常のNORMAL技として解決
/// されるだけであることを示す（docs/combat_rules_v1.md 15章、Phase 8特殊
/// 処理は未実装）。
/// attribute=rough・family=choke（SSOT「23.4章 CHOKEはattribute横断」の
/// 具体例。同じCHOKE familyでもattribute=joint（絞め技）とattribute=rough
/// （反則的な首絞め）の両方が存在しうる）。
const CombatV1Technique _fxRoughNormal = CombatV1Technique(
  id: 'fx_rough_normal',
  name: 'テストラフ技',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.rough,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.rough: 1}),
  damage: 10,
  heatGain: 20,
  family: CombatV1TechniqueFamily.choke,
);

/// [fixtureCatalog]にこのファイル専用のローカル技を加えたカタログ。
CombatV1CardCatalog _catalogWith(Map<String, CombatV1Technique> extra) =>
    CombatV1CardCatalog(
      techniques: {...fixtureTechniques, ...extra},
      counters: fixtureCounters,
    );

void main() {
  group('静的データvalidation — CombatV1EnergyPool/EnergyCost（1〜5）', () {
    test('1. 正常EnergyPoolはvalid', () {
      expect(fixtureWrestlerA.energyPool.isValid, isTrue);
    });

    test('2. 負数を含むEnergyPoolはinvalid', () {
      const pool = CombatV1EnergyPool({CombatV1EnergyAttribute.strike: -1});
      expect(pool.isValid, isFalse);
    });

    test('3. 正常EnergyCostはvalid', () {
      const cost = CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2});
      expect(cost.isValid, isTrue);
    });

    test('4. 負数を含むEnergyCostはinvalid', () {
      const cost = CombatV1EnergyCost({CombatV1EnergyAttribute.strike: -1});
      expect(cost.isValid, isFalse);
    });

    test('5. wildを含むEnergyCostはinvalid（技のCostにwildは使用不可）', () {
      const cost = CombatV1EnergyCost({
        CombatV1EnergyAttribute.strike: 2,
        CombatV1EnergyAttribute.wild: 1,
      });
      expect(cost.isValid, isFalse);

      // wildが0の場合は「キーとして存在するが要求量0」であり無害。
      const zeroWildCost = CombatV1EnergyCost({
        CombatV1EnergyAttribute.strike: 2,
        CombatV1EnergyAttribute.wild: 0,
      });
      expect(zeroWildCost.isValid, isTrue);
    });

    test('通常のフィクスチャ技はisStaticDataValid==true', () {
      for (final technique in fixtureTechniques.values) {
        expect(
          technique.isStaticDataValid,
          isTrue,
          reason: '${technique.id}は静的データが有効であるべき',
        );
      }
    });

    test('wild costを持つ技はisStaticDataValid==false', () {
      expect(_fxInvalidWildCost.isStaticDataValid, isFalse);
    });

    test('負数costを持つ技はisStaticDataValid==false', () {
      expect(_fxInvalidNegativeCost.isStaticDataValid, isFalse);
    });
  });

  group('静的データvalidation — Match State invariant（6）', () {
    test('spentEnergyがenergyPool以内ならvalid', () {
      final player = CombatV1PlayerState(
        wrestlerId: fixtureWrestlerA.id,
        wrestlerName: fixtureWrestlerA.name,
        maxHp: 150,
        hp: 150,
        koc: 10,
        pinCardsHeld: 2,
        energyPool: fixtureWrestlerA.energyPool, // strike:3
        spentEnergy: const {CombatV1EnergyAttribute.strike: 3},
      );
      expect(validatePlayerStateInvariants(player).isValid, isTrue);
    });

    test('6. spentEnergyがenergyPoolを超えるとinvalid（spentExceedsPoolを検出）', () {
      final player = CombatV1PlayerState(
        wrestlerId: fixtureWrestlerA.id,
        wrestlerName: fixtureWrestlerA.name,
        maxHp: 150,
        hp: 150,
        koc: 10,
        pinCardsHeld: 2,
        energyPool: fixtureWrestlerA.energyPool, // strike:3
        spentEnergy: const {CombatV1EnergyAttribute.strike: 4}, // Poolの3を超過
      );
      final result = validatePlayerStateInvariants(player);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1PlayerStateInvariantErrorCode.spentExceedsPool),
      );
    });
  });

  group('TECHNIQUE legality — reasonCode（7〜19）', () {
    test('7. action phaseでNORMALは使用可（legal）', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
        ],
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isTrue);
      expect(check.reasonCode, CombatV1TechniqueLegalityReasonCode.legal);
    });

    test('8. SIGNATUREは使用可（legal）', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_signature_a',
            category: CombatV1CardCategory.signature,
          ),
        ],
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isTrue);
    });

    test('9. COUNTERは攻撃として使用不可（counterCannotAttack）', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_counter_a',
            category: CombatV1CardCategory.counter,
          ),
        ],
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.counterCannotAttack,
      );
    });

    test('10. FINISHERはPhase 3では使用不可（finisherNotImplemented）', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_finisher_a',
            category: CombatV1CardCategory.finisher,
          ),
        ],
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.finisherNotImplemented,
      );
      expect(
        () => declareAndResolveTechnique(state, 'a1', catalog: fixtureCatalog),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('11. 手札にないinstanceIdは不可（cardNotInHand）', () {
      final state = _buildState(handA: const []);
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'not_in_hand',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1TechniqueLegalityReasonCode.cardNotInHand);
    });

    test('12. 未知cardIdは不可（missingCatalogEntry）', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'totally_unknown_card_id',
            category: CombatV1CardCategory.normal,
          ),
        ],
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.missingCatalogEntry,
      );
    });

    test('13. entry.categoryとTechnique.categoryが不一致なら不可（categoryMismatch）', () {
      // fx_signature_aは本来category==signatureだが、DeckEntry側でnormalと
      // 偽装している状況（Deck validationをすり抜けてEngineに渡された想定の
      // 防御的テスト）。
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_signature_a',
            category: CombatV1CardCategory.normal,
          ),
        ],
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1TechniqueLegalityReasonCode.categoryMismatch);
    });

    test('14. ENERGY不足は不可（insufficientEnergy）', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
        ],
        spentA: const {CombatV1EnergyAttribute.strike: 3, CombatV1EnergyAttribute.wild: 2},
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1TechniqueLegalityReasonCode.insufficientEnergy);
    });

    test('15. STAND条件一致で使用可', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_require_stand',
            category: CombatV1CardCategory.normal,
          ),
        ],
        postureB: CombatV1WrestlerPosture.stand,
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'a1',
        catalog: _catalogWith({'fx_require_stand': _fxRequireStand}),
      );
      expect(check.legal, isTrue);
    });

    test('16. STAND条件不一致で使用不可（opponentStateMismatch）', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_require_stand',
            category: CombatV1CardCategory.normal,
          ),
        ],
        postureB: CombatV1WrestlerPosture.down,
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'a1',
        catalog: _catalogWith({'fx_require_stand': _fxRequireStand}),
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('17. DOWN条件一致で使用可', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_normal_ground', // requiredOpponentState == down
            category: CombatV1CardCategory.normal,
          ),
        ],
        postureB: CombatV1WrestlerPosture.down,
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isTrue);
    });

    test('18. DOWN条件不一致で使用不可（opponentStateMismatch）', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_normal_ground',
            category: CombatV1CardCategory.normal,
          ),
        ],
        postureB: CombatV1WrestlerPosture.stand,
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'a1',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.opponentStateMismatch,
      );
    });

    test('19. requiredOpponentState==nullならSTAND/DOWNどちらでも使用可', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike', // requiredOpponentState == null
        category: CombatV1CardCategory.normal,
      );
      final standState = _buildState(
        handA: [entry],
        postureB: CombatV1WrestlerPosture.stand,
      );
      final downState = _buildState(
        handA: [entry],
        postureB: CombatV1WrestlerPosture.down,
      );
      expect(
        CombatV1Engine.checkTechniqueLegality(
          standState,
          'a1',
          catalog: fixtureCatalog,
        ).legal,
        isTrue,
      );
      expect(
        CombatV1Engine.checkTechniqueLegality(
          downState,
          'a1',
          catalog: fixtureCatalog,
        ).legal,
        isTrue,
      );
    });

    test('技の静的データが不正なら使用不可（invalidTechniqueData）', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_invalid_wild_cost',
            category: CombatV1CardCategory.normal,
          ),
        ],
      );
      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        'a1',
        catalog: _catalogWith({'fx_invalid_wild_cost': _fxInvalidWildCost}),
      );
      expect(check.legal, isFalse);
      expect(
        check.reasonCode,
        CombatV1TechniqueLegalityReasonCode.invalidTechniqueData,
      );
    });
  });

  group('ENERGY — ターン開始/相手ターンの回復タイミング（25〜26）', () {
    test('25. ターン開始でspentEnergyが空へ戻る（全回復）', () {
      var state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck('e_a'),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck('e_b'),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(1),
      );
      state = state.withActive(
        state.playerA.copyWith(
          spentEnergy: const {CombatV1EnergyAttribute.strike: 3},
        ),
      );
      state = CombatV1Engine.discardCard(state, state.active.hand.first.instanceId);
      state = CombatV1Engine.endTurn(state, random: Random(2)); // → playerB discard
      state = CombatV1Engine.discardCard(state, state.active.hand.first.instanceId);
      state = CombatV1Engine.endTurn(state, random: Random(3)); // → playerA discard

      expect(state.activePlayerIndex, 0);
      expect(state.playerA.spentEnergy[CombatV1EnergyAttribute.strike] ?? 0, 0);
    });

    test('26. 相手のENERGYは相手ターン開始まで回復しない', () {
      var state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck('e2_a'),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck('e2_b'),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(1),
      );
      // playerBが使用済みという状況を直接組み立てる。
      state = state.withOpponent(
        state.playerB.copyWith(
          spentEnergy: const {CombatV1EnergyAttribute.strike: 2},
        ),
      );
      expect(state.playerB.spentEnergy[CombatV1EnergyAttribute.strike], 2);

      // playerA（active）がdiscard→endTurnしても、まだplayerBのターンが
      // 開始していない間はplayerBのspentEnergyは回復しない。
      state = CombatV1Engine.discardCard(state, state.active.hand.first.instanceId);
      // endTurn実行前時点ではまだplayerBは手番になっていないため、この時点の
      // spentEnergyを確認する（endTurn自体がplayerBのturn startを内部で
      // 実行してしまうため、endTurn呼び出し直前の状態で検証する）。
      expect(state.playerB.spentEnergy[CombatV1EnergyAttribute.strike], 2);
    });
  });

  group('TECHNIQUE解決 — techniquesUsedThisTurn（41）', () {
    test('41. 成功したTECHNIQUE使用ごとにtechniquesUsedThisTurnが+1される', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = _buildState(handA: [entry], techniquesUsedA: 0);

      final next = declareAndResolveTechnique(
        state,
        'a1',
        catalog: fixtureCatalog,
        random: Random(1),
      );

      expect(next.playerA.techniquesUsedThisTurn, 1);
    });
  });

  group('DOWN/STAND — 状態遷移（33〜35）', () {
    test('33. STAND→STAND（resultOpponentState==null）', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike', // resultOpponentState == null
        category: CombatV1CardCategory.normal,
      );
      final state = _buildState(
        handA: [entry],
        postureB: CombatV1WrestlerPosture.stand,
      );
      final next = declareAndResolveTechnique(state, 'a1', catalog: fixtureCatalog);
      expect(next.playerB.posture, CombatV1WrestlerPosture.stand);
    });

    test('34. STAND→DOWN', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_throw_down', // resultOpponentState == down
        category: CombatV1CardCategory.normal,
      );
      final state = _buildState(
        handA: [entry],
        postureB: CombatV1WrestlerPosture.stand,
      );
      final next = declareAndResolveTechnique(state, 'a1', catalog: fixtureCatalog);
      expect(next.playerB.posture, CombatV1WrestlerPosture.down);
    });

    test('35. DOWN→DOWN', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_ground', // requiredOpponentState==down, result==down
        category: CombatV1CardCategory.normal,
      );
      final state = _buildState(
        handA: [entry],
        postureB: CombatV1WrestlerPosture.down,
      );
      final next = declareAndResolveTechnique(state, 'a1', catalog: fixtureCatalog);
      expect(next.playerB.posture, CombatV1WrestlerPosture.down);
    });
  });

  group('連続TECHNIQUE（42〜48）', () {
    test('42. 同一ターンで2技以上使用できる', () {
      final entries = [
        const CombatV1DeckEntry(
          instanceId: 'a1',
          cardId: 'fx_normal_strike',
          category: CombatV1CardCategory.normal,
        ),
        const CombatV1DeckEntry(
          instanceId: 'a2',
          cardId: 'fx_normal_strike',
          category: CombatV1CardCategory.normal,
        ),
        const CombatV1DeckEntry(
          instanceId: 'a3',
          cardId: 'fx_normal_strike',
          category: CombatV1CardCategory.normal,
        ),
      ];
      // fixtureWrestlerAの打ENERGYは3なので、打1コストの技をちょうど3回使える。
      var state = _buildState(handA: entries);

      state = declareAndResolveTechnique(state, 'a1', catalog: fixtureCatalog, random: Random(1));
      expect(state.phase, CombatV1MatchPhase.action);
      state = declareAndResolveTechnique(state, 'a2', catalog: fixtureCatalog, random: Random(2));
      expect(state.phase, CombatV1MatchPhase.action);
      state = declareAndResolveTechnique(state, 'a3', catalog: fixtureCatalog, random: Random(3));

      expect(state.playerA.techniquesUsedThisTurn, 3);
      expect(state.playerA.availableEnergyFor(CombatV1EnergyAttribute.strike), 0);
    });

    test('43. 1技目で相手をDOWN化させ、DOWN限定の2技目を同一ターンで使用できる', () {
      final downMove = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_throw_down', // STAND→DOWN、投1
        category: CombatV1CardCategory.normal,
      );
      final groundMove = const CombatV1DeckEntry(
        instanceId: 'a2',
        cardId: 'fx_normal_ground', // requires DOWN、打1
        category: CombatV1CardCategory.normal,
      );
      var state = _buildState(
        handA: [downMove, groundMove],
        postureB: CombatV1WrestlerPosture.stand,
      );

      // DOWN化前は2技目はまだ使用不可。
      expect(
        CombatV1Engine.checkTechniqueLegality(state, 'a2', catalog: fixtureCatalog).legal,
        isFalse,
      );

      state = declareAndResolveTechnique(state, 'a1', catalog: fixtureCatalog, random: Random(1));
      expect(state.playerB.posture, CombatV1WrestlerPosture.down);

      // DOWN化後は2技目が使用可能になり、同一ターンで使用できる。
      state = declareAndResolveTechnique(state, 'a2', catalog: fixtureCatalog, random: Random(2));
      expect(state.phase, CombatV1MatchPhase.action);
      expect(state.playerA.techniquesUsedThisTurn, 2);
    });

    test('44. 1技目のdrawで引いた技を同一ターンで使用できる', () {
      final first = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final drawnTechnique = const CombatV1DeckEntry(
        instanceId: 'a2',
        cardId: 'fx_normal_strike_alt',
        category: CombatV1CardCategory.normal,
      );
      // drawnTechniqueの後にダミーを1枚残しておく（drawPileがa2を引いた直後に
      // 空にならないようにするため。2枚目のdeclareAndResolveTechnique時に山札が空だと
      // 捨て札の再構築が発生し、直前にdiscardしたa2自体が再構築対象に混ざって
      // しまい、このテストの本来の関心事（drawしたカードを同ターンに使える
      // こと）と無関係な副作用でdiscardPileの検証が揺れてしまうため）。
      final filler = const CombatV1DeckEntry(
        instanceId: 'filler',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      var state = _buildState(
        handA: [first],
        drawPileA: [drawnTechnique, filler],
      );

      state = declareAndResolveTechnique(state, 'a1', catalog: fixtureCatalog, random: Random(1));
      expect(state.playerA.hand.any((e) => e.instanceId == 'a2'), isTrue);

      state = declareAndResolveTechnique(state, 'a2', catalog: fixtureCatalog, random: Random(2));
      expect(state.playerA.discardPile.any((e) => e.instanceId == 'a2'), isTrue);
    });

    test('45. ENERGY枯渇後は該当技を使用できない', () {
      final first = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final second = const CombatV1DeckEntry(
        instanceId: 'a2',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      // 打ENERGYを使い切った状態（wildも0扱いになるよう消費済みにしておく）。
      final state = _buildState(
        handA: [first, second],
        spentA: const {
          CombatV1EnergyAttribute.strike: 3,
          CombatV1EnergyAttribute.wild: 2,
        },
      );
      final check = CombatV1Engine.checkTechniqueLegality(state, 'a1', catalog: fixtureCatalog);
      expect(check.legal, isFalse);
      expect(check.reasonCode, CombatV1TechniqueLegalityReasonCode.insufficientEnergy);
    });

    test('46. strike ENERGYが枯渇していてもthrow ENERGYが残っていれば別属性技は使用可', () {
      final strikeMove = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike', // 打1
        category: CombatV1CardCategory.normal,
      );
      final throwMove = const CombatV1DeckEntry(
        instanceId: 'a2',
        cardId: 'fx_normal_throw_alt', // 投1
        category: CombatV1CardCategory.normal,
      );
      final state = _buildState(
        handA: [strikeMove, throwMove],
        spentA: const {
          CombatV1EnergyAttribute.strike: 3,
          CombatV1EnergyAttribute.wild: 2,
        },
      );
      expect(
        CombatV1Engine.checkTechniqueLegality(state, 'a1', catalog: fixtureCatalog).legal,
        isFalse,
      );
      expect(
        CombatV1Engine.checkTechniqueLegality(state, 'a2', catalog: fixtureCatalog).legal,
        isTrue,
      );
    });

    test('47. 使用可能技が無ければhasAnyPlayableTechniqueはfalse', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = _buildState(
        handA: [entry],
        spentA: const {
          CombatV1EnergyAttribute.strike: 3,
          CombatV1EnergyAttribute.wild: 2,
        },
      );
      expect(
        CombatV1Engine.hasAnyPlayableTechnique(state, catalog: fixtureCatalog),
        isFalse,
      );
    });

    test('48. 別属性技が手札に残っていればhasAnyPlayableTechniqueはtrue', () {
      final strikeMove = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike', // 打1（枯渇）
        category: CombatV1CardCategory.normal,
      );
      final throwMove = const CombatV1DeckEntry(
        instanceId: 'a2',
        cardId: 'fx_normal_throw_alt', // 投1（残っている）
        category: CombatV1CardCategory.normal,
      );
      final state = _buildState(
        handA: [strikeMove, throwMove],
        spentA: const {
          CombatV1EnergyAttribute.strike: 3,
          CombatV1EnergyAttribute.wild: 2,
        },
      );
      expect(
        CombatV1Engine.hasAnyPlayableTechnique(state, catalog: fixtureCatalog),
        isTrue,
      );
    });
  });

  group('Atomicity — 失敗Commandはstateを一切変更しない（49〜56）', () {
    test('49. wrong phase失敗時state不変', () {
      final state = _buildState(
        phase: CombatV1MatchPhase.discard,
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
        ],
      );
      final snapshot = _StateSnapshot(state);
      expect(
        () => declareAndResolveTechnique(state, 'a1', catalog: fixtureCatalog),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(state);
    });

    test('50. card not in handでstate不変', () {
      final state = _buildState(handA: const []);
      final snapshot = _StateSnapshot(state);
      expect(
        () => declareAndResolveTechnique(state, 'not_in_hand', catalog: fixtureCatalog),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(state);
    });

    test('51. unknown cardIdでstate不変', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'totally_unknown_card_id',
            category: CombatV1CardCategory.normal,
          ),
        ],
      );
      final snapshot = _StateSnapshot(state);
      expect(
        () => declareAndResolveTechnique(state, 'a1', catalog: fixtureCatalog),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(state);
    });

    test('52. category mismatchでstate不変', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_signature_a',
            category: CombatV1CardCategory.normal, // 本来はsignature
          ),
        ],
      );
      final snapshot = _StateSnapshot(state);
      expect(
        () => declareAndResolveTechnique(state, 'a1', catalog: fixtureCatalog),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(state);
    });

    test('53. COUNTER cardでstate不変', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_counter_a',
            category: CombatV1CardCategory.counter,
          ),
        ],
      );
      final snapshot = _StateSnapshot(state);
      expect(
        () => declareAndResolveTechnique(state, 'a1', catalog: fixtureCatalog),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(state);
    });

    test('54. FINISHERでstate不変', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_finisher_a',
            category: CombatV1CardCategory.finisher,
          ),
        ],
      );
      final snapshot = _StateSnapshot(state);
      expect(
        () => declareAndResolveTechnique(state, 'a1', catalog: fixtureCatalog),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(state);
    });

    test('55. ENERGY不足でstate不変', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
        ],
        spentA: const {
          CombatV1EnergyAttribute.strike: 3,
          CombatV1EnergyAttribute.wild: 2,
        },
      );
      final snapshot = _StateSnapshot(state);
      expect(
        () => declareAndResolveTechnique(state, 'a1', catalog: fixtureCatalog),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(state);
    });

    test('56. 相手state条件不一致でstate不変', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_normal_ground', // requires down
            category: CombatV1CardCategory.normal,
          ),
        ],
        postureB: CombatV1WrestlerPosture.stand,
      );
      final snapshot = _StateSnapshot(state);
      expect(
        () => declareAndResolveTechnique(state, 'a1', catalog: fixtureCatalog),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(state);
    });

    test('invalid static Technique dataでstate不変', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_invalid_wild_cost',
            category: CombatV1CardCategory.normal,
          ),
        ],
      );
      final catalog = _catalogWith({'fx_invalid_wild_cost': _fxInvalidWildCost});
      final snapshot = _StateSnapshot(state);
      expect(
        () => declareAndResolveTechnique(state, 'a1', catalog: catalog),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
      snapshot.expectUnchanged(state);
    });
  });

  group('Phase境界 — Phase 3ではまだ実装しないもの（57〜61）', () {
    test(
      '57・58. ROUGH技はPhase 3〜7では通常のNORMAL技として解決される'
      '（ROUGH特殊処理はPhase 8で実装済み。詳細はcombat_v1_rough_test.dart参照）',
      () {
        final rough = const CombatV1DeckEntry(
          instanceId: 'a1',
          cardId: 'fx_rough_normal',
          category: CombatV1CardCategory.normal,
        );
        final followUp = const CombatV1DeckEntry(
          instanceId: 'a2',
          cardId: 'fx_normal_strike',
          category: CombatV1CardCategory.normal,
        );
        final catalog = _catalogWith({'fx_rough_normal': _fxRoughNormal});
        var state = _buildState(
          handA: [rough, followUp],
          hpB: 150,
          sharedHeat: 0,
        );

        state = declareAndResolveTechnique(
          state,
          'a1',
          catalog: catalog,
          random: Random(1),
        );
        // DMG/HEAT適用は通常のNORMAL技と同じ（ROUGHはDMG/HEATを変えない）。
        expect(state.playerB.hp, 140); // 150 - 10
        expect(state.sharedHeat, 20);
        // ROUGH技を宣言した事実は記録される（Phase 8、docs/combat_rules_v1.md
        // 15章）。ただしこれは「このターンのPIN不可」（自分向け）としてのみ
        // 働き、「次ターンTECHNIQUE最大1枚」制限は相手にのみ適用される
        // （15章）。
        expect(state.playerA.roughTechniqueUsedThisTurn, isTrue);
        expect(state.playerB.roughTechniqueLimitActive, isFalse);

        // ROUGH技を使用した本人（playerA）は、同一ターン内で追加の
        // TECHNIQUEを引き続き宣言できる（次ターン制限は相手のみが対象、
        // 15章「重要: 相手が技を一切使用できない、ではない」）。
        state = declareAndResolveTechnique(
          state,
          'a2',
          catalog: catalog,
          random: Random(2),
        );
        expect(state.playerA.techniquesUsedThisTurn, 2);
      },
    );

    test('59. FINISHERの本処理（DIRECT PIN等）は発生しない', () {
      // fx_finisher_bはdirectPin==trueを持つが、Phase
      // 3ではfinisherNotImplementedとして拒否されるだけで、DIRECT
      // PIN相当の処理（PINカード移動等）は一切発生しない。
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_finisher_b',
            category: CombatV1CardCategory.finisher,
          ),
        ],
      );
      final pinCardsBefore = state.playerA.pinCardsHeld;
      expect(
        CombatV1Engine.checkTechniqueLegality(state, 'a1', catalog: fixtureCatalog).reasonCode,
        CombatV1TechniqueLegalityReasonCode.finisherNotImplemented,
      );
      expect(state.playerA.pinCardsHeld, pinCardsBefore);
    });

    test('60. COUNTER応答（counterResponsePending）はPhase 4で追加された', () {
      // Phase 3時点ではCombatV1MatchPhaseにCOUNTER応答待ちフェーズが無い
      // ことを検証していたが、Phase 4でSSOT通りに追加された
      // （docs/combat_rules_v1.md 7.1章）。宣言→応答待ち→
      // COUNTER/decline解決の詳細なState Machineテストは
      // combat_v1_pending_state_machine_test.dart（Phase 4）を参照。
      expect(
        CombatV1MatchPhase.values.map((p) => p.name),
        contains('counterResponsePending'),
      );
    });

    test('61. Combo Speed相当の回数制限は存在しない（ENERGYのみが制限になる）', () {
      // fixtureWrestlerAの打ENERGYは3、＊は2。打1コストの技は、具体属性3回
      // ＋＊補完2回＝合計5回まで使用できる（固定回数の「コンボ速度」制限が
      // 存在せず、ENERGY残量だけが上限になることの裏付け）。
      final entries = [
        for (var i = 1; i <= 5; i++)
          CombatV1DeckEntry(
            instanceId: 'a$i',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
      ];
      var state = _buildState(handA: entries);
      for (var i = 1; i <= 5; i++) {
        state = declareAndResolveTechnique(
          state,
          'a$i',
          catalog: fixtureCatalog,
          random: Random(i),
        );
        expect(state.phase, CombatV1MatchPhase.action); // combo速度による強制終了は無い
      }
      expect(state.playerA.techniquesUsedThisTurn, 5);
      expect(state.playerA.availableEnergyFor(CombatV1EnergyAttribute.strike), 0);
      expect(state.playerA.availableEnergyFor(CombatV1EnergyAttribute.wild), 0);

      // 具体属性・＊ともに枯渇した後は、回数ではなくENERGY不足を理由に
      // 使用不可となる。
      expect(
        CombatV1Engine.hasAnyPlayableTechnique(state, catalog: fixtureCatalog),
        isFalse,
      );
    });
  });

  group('hasAnyPlayableTechnique — regression強化（33、Phase 3レビュー指摘対応）', () {
    test('COUNTERだけのhandはfalse', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_counter_a',
            category: CombatV1CardCategory.counter,
          ),
        ],
      );
      expect(
        CombatV1Engine.hasAnyPlayableTechnique(state, catalog: fixtureCatalog),
        isFalse,
      );
    });

    test('FINISHERだけのhandはfalse', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_finisher_a',
            category: CombatV1CardCategory.finisher,
          ),
        ],
      );
      expect(
        CombatV1Engine.hasAnyPlayableTechnique(state, catalog: fixtureCatalog),
        isFalse,
      );
    });

    test('相手state不一致の技だけのhandはfalse', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_normal_ground', // requiredOpponentState == down
            category: CombatV1CardCategory.normal,
          ),
        ],
        postureB: CombatV1WrestlerPosture.stand,
      );
      expect(
        CombatV1Engine.hasAnyPlayableTechnique(state, catalog: fixtureCatalog),
        isFalse,
      );
    });

    test('静的データが不正な技だけのhandはfalse', () {
      final state = _buildState(
        handA: [
          const CombatV1DeckEntry(
            instanceId: 'a1',
            cardId: 'fx_invalid_wild_cost',
            category: CombatV1CardCategory.normal,
          ),
        ],
      );
      expect(
        CombatV1Engine.hasAnyPlayableTechnique(
          state,
          catalog: _catalogWith({'fx_invalid_wild_cost': _fxInvalidWildCost}),
        ),
        isFalse,
      );
    });
  });
}
