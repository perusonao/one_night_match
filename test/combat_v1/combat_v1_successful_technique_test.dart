// Combat Ver.1 Phase 4 Codexレビュー指摘H2/H3: lastSuccessfulTechnique
// の更新条件、および directPin/submissionHold/finisherType metadataの
// snapshot検証。Phase 5/6/9への接続準備であり、これらの値による分岐処理
// （PIN移行・SUBMISSION判定・FINISHER解禁等）はこのテストでも一切検証・
// 発火させない。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_pending_attack.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';

import 'combat_v1_test_fixtures.dart';

/// NORMALカテゴリでdirectPin==trueを持つテスト専用技（フィクスチャ標準
/// カタログのFINISHERはPhase 4では宣言できないため、NORMAL側で用意する）。
const _directPinNormal = CombatV1Technique(
  id: 'st_direct_pin_normal',
  name: 'テストDIRECT PIN技',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.strike,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
  damage: 10,
  heatGain: 10,
  directPin: true,
  family: CombatV1TechniqueFamily.tackle,
);

void main() {
  group('lastSuccessfulTechnique — 更新条件（10・12・13）', () {
    test('decline成功のみがlastSuccessfulTechniqueを更新する', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike', // family=elbow
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry]);
      expect(state.lastSuccessfulTechnique, isNull);

      final declared = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);
      expect(declared.lastSuccessfulTechnique, isNull); // 宣言時点ではまだ更新しない

      final resolved = CombatV1Engine.declineCounter(declared, random: Random(1));
      final snapshot = resolved.lastSuccessfulTechnique;
      expect(snapshot, isNotNull);
      expect(snapshot!.attackerPlayerIndex, 0);
      expect(snapshot.cardInstanceId, 'a1');
      expect(snapshot.cardId, 'fx_normal_strike');
      expect(snapshot.family, CombatV1TechniqueFamily.elbow);
      expect(snapshot.attribute, CombatV1EnergyAttribute.strike);
      expect(snapshot.category, CombatV1CardCategory.normal);
    });

    test('COUNTERされたTechniqueはlastSuccessfulTechniqueを更新しない', () {
      final attack = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike', // family=elbow(STRIKE)
        category: CombatV1CardCategory.normal,
      );
      final counter = const CombatV1DeckEntry(
        instanceId: 'c1',
        cardId: 'fx_counter_a', // groups=[strike]、対応する
        category: CombatV1CardCategory.counter,
      );
      final state = buildMatchState(handA: [attack], handB: [counter]);
      expect(state.lastSuccessfulTechnique, isNull);

      final declared = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);
      final resolved = CombatV1Engine.playCounter(
        declared,
        'c1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(1),
      );

      expect(resolved.lastSuccessfulTechnique, isNull);
    });

    test('既存のlastSuccessfulTechniqueは、後続のCOUNTER成立で上書きされない', () {
      // 1. fx_normal_strikeをdeclare→declineで成立させ、lastSuccessfulを
      // Aにする。
      final first = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      var state = buildMatchState(handA: [first]);
      var declared = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);
      state = CombatV1Engine.declineCounter(declared, random: Random(1));
      final afterFirst = state.lastSuccessfulTechnique;
      expect(afterFirst, isNotNull);
      expect(afterFirst!.cardInstanceId, 'a1');

      // 2. 別の技（fx_normal_strike_alt、family=chop、STRIKE group）を
      // declare→COUNTER成立させる。
      final second = const CombatV1DeckEntry(
        instanceId: 'a2',
        cardId: 'fx_normal_strike_alt',
        category: CombatV1CardCategory.normal,
      );
      final counter = const CombatV1DeckEntry(
        instanceId: 'c1',
        cardId: 'fx_counter_a', // groups=[strike]
        category: CombatV1CardCategory.counter,
      );
      // handA/handBを直接差し替える（buildMatchStateはactivePlayerIndex等
      // 既定値を保つため、既存stateのplayerA/playerBを部分的に更新する）。
      state = state.withActive(state.playerA.copyWith(hand: [second]));
      state = state.withOpponent(state.playerB.copyWith(hand: [counter]));

      declared = CombatV1Engine.declareTechnique(state, 'a2', catalog: fixtureCatalog);
      state = CombatV1Engine.playCounter(
        declared,
        'c1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(2),
      );

      // lastSuccessfulTechniqueはAのまま（Bで上書きされない）。
      expect(state.lastSuccessfulTechnique!.cardInstanceId, 'a1');
    });

    test('techniquesUsedThisTurnはCOUNTER成立でも維持される（used != successful、28）', () {
      final attack = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final counter = const CombatV1DeckEntry(
        instanceId: 'c1',
        cardId: 'fx_counter_a',
        category: CombatV1CardCategory.counter,
      );
      final state = buildMatchState(handA: [attack], handB: [counter]);
      final declared = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);
      expect(declared.playerA.techniquesUsedThisTurn, 1); // 宣言時点で+1済み

      final resolved = CombatV1Engine.playCounter(
        declared,
        'c1',
        catalog: fixtureCatalog,
        rules: fixtureRules,
        random: Random(1),
      );
      // COUNTERされてもtechniquesUsedThisTurnは1のまま（戻らない）。
      expect(resolved.playerA.techniquesUsedThisTurn, 1);
      // が、lastSuccessfulTechniqueは更新されない（used != successful）。
      expect(resolved.lastSuccessfulTechnique, isNull);
    });
  });

  group('metadata snapshot — directPin（26、Phase 5接続準備）', () {
    test('directPin==trueの技がdeclineで成立すると、pending/lastSuccessfulの'
        'directPinがtrueになる。ただしPIN関連フィールドは一切変化しない', () {
      final catalog = CombatV1CardCatalog(
        techniques: {...fixtureTechniques, _directPinNormal.id: _directPinNormal},
        counters: fixtureCounters,
      );
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'st_direct_pin_normal',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry]);
      final pinCardsBefore = state.playerA.pinCardsHeld;
      final kocBefore = state.playerB.koc;

      final declared = CombatV1Engine.declareTechnique(state, 'a1', catalog: catalog);
      expect(declared.pendingAttack!.directPin, isTrue);

      final resolved = CombatV1Engine.declineCounter(declared, random: Random(1));
      expect(resolved.lastSuccessfulTechnique!.directPin, isTrue);

      // PIN処理は一切発火しない（Phase 5まで未実装）。
      expect(resolved.playerA.pinCardsHeld, pinCardsBefore);
      expect(resolved.playerB.koc, kocBefore);
      expect(resolved.phase, CombatV1MatchPhase.action); // phase=pin等へ移行しない
    });
  });

  group('metadata snapshot — submissionHold（27、Phase 6接続準備）', () {
    test('submissionHold==trueの技がdeclineで成立すると、pending/lastSuccessfulの'
        'submissionHoldがtrueになる。ただしSUBMISSION関連フィールドは一切変化しない', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_signature_b', // submissionHold==true, family=bodyPress
        category: CombatV1CardCategory.signature,
      );
      final state = buildMatchState(handA: [entry]);
      final kocBefore = state.playerB.koc;

      final declared = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);
      expect(declared.pendingAttack!.submissionHold, isTrue);

      final resolved = CombatV1Engine.declineCounter(declared, random: Random(1));
      expect(resolved.lastSuccessfulTechnique!.submissionHold, isTrue);
      expect(resolved.playerB.koc, kocBefore); // SUBMISSION ESCAPE等は発火しない
    });
  });

  group('metadata snapshot — finisherType（29、Phase 9接続準備）', () {
    test('NORMAL/SIGNATURE技のfinisherTypeは常にnullのままsnapshotされる', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'a1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry]);
      final declared = CombatV1Engine.declareTechnique(state, 'a1', catalog: fixtureCatalog);
      expect(declared.pendingAttack!.finisherType, isNull);

      final resolved = CombatV1Engine.declineCounter(declared, random: Random(1));
      expect(resolved.lastSuccessfulTechnique!.finisherType, isNull);
    });

    test('CombatV1PendingAttackはDomainモデルとしてfinisherTypeを保持できる'
        '（Phase 9接続準備。FINISHER宣言自体はPhase 4でも引き続き禁止のまま、'
        'Engine経由では到達しない直接構築での確認）', () {
      final pending = CombatV1PendingAttack(
        attackerPlayerIndex: 0,
        defenderPlayerIndex: 1,
        attackCardInstance: const CombatV1DeckEntry(
          instanceId: 'finisher_instance',
          cardId: 'fx_finisher_a',
          category: CombatV1CardCategory.finisher,
        ),
        category: CombatV1CardCategory.finisher,
        attribute: CombatV1EnergyAttribute.strike,
        family: CombatV1TechniqueFamily.lariat,
        energyCost: const CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2}),
        damage: 30,
        heatGain: 30,
        finisherType: CombatV1FinisherType.normal,
      );
      expect(pending.finisherType, CombatV1FinisherType.normal);
    });
  });
}
