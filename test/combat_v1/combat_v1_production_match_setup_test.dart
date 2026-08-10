/// Phase 11A: Production Match Setup（`combat_v1_production_match_setup.dart`）
/// のテスト。
///
/// これまでtest毎に個別に組み立てていた「wrestler catalog→対応deck
/// builder→ownerId→productionCardCatalog→CombatV1Engine.start」の手順が、
/// `CombatV1ProductionMatchStarter.start(CombatV1ProductionMatchConfig)`
/// という単一のSSOT経路から実行できることを検証する。Core Engine
/// （`combat_v1_engine.dart`）自体は変更していないため、既存のCore
/// regressionテスト（`combat_v1_production_wrestler_deck_integrity_test.dart`
/// 等）は変更せずそのまま残す。
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_production_match_setup.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_state_invariants.dart';

const CombatV1RulesConfig rules = CombatV1RulesConfig();

const List<String> productionWrestlerIds = ['misaki', 'jack', 'akari', 'reina'];

List<String> _allInstanceIds(CombatV1MatchState state) {
  final pending = state.pendingAttack;
  return [
    ...state.playerA.hand.map((e) => e.instanceId),
    ...state.playerA.drawPile.map((e) => e.instanceId),
    ...state.playerA.discardPile.map((e) => e.instanceId),
    ...state.playerB.hand.map((e) => e.instanceId),
    ...state.playerB.drawPile.map((e) => e.instanceId),
    ...state.playerB.discardPile.map((e) => e.instanceId),
    if (pending != null) pending.attackCardInstance.instanceId,
  ];
}

void _expectValidProductionMatch(
  CombatV1MatchState state, {
  required String wrestlerAId,
  required String wrestlerBId,
}) {
  expect(state.playerA.wrestlerId, wrestlerAId);
  expect(state.playerB.wrestlerId, wrestlerBId);
  expect(state.phase, CombatV1MatchPhase.discard);

  final result = validateMatchStateInvariants(state, rules: rules);
  expect(result.isValid, isTrue, reason: result.errors.join(' / '));

  expect(_allInstanceIds(state).toSet().length, 60);

  final totalA =
      state.playerA.hand.length +
      state.playerA.drawPile.length +
      state.playerA.discardPile.length;
  final totalB =
      state.playerB.hand.length +
      state.playerB.drawPile.length +
      state.playerB.discardPile.length;
  expect(totalA, 30);
  expect(totalB, 30);
}

void main() {
  group('CombatV1ProductionWrestlerEntry registry', () {
    test('misaki/jack/akari/reinaの4人が登録されている', () {
      expect(
        combatV1ProductionWrestlerRegistry.keys.toSet(),
        productionWrestlerIds.toSet(),
      );
    });

    test('各entryのwrestler.idはレジストリのキーと一致する', () {
      for (final id in productionWrestlerIds) {
        expect(combatV1ProductionWrestlerRegistry[id]!.wrestler.id, id);
      }
    });
  });

  group('A. Misaki vs Jack（cross-wrestler） → start成功', () {
    test('CombatV1ProductionMatchStarter.startで開始できる', () {
      final state = CombatV1ProductionMatchStarter.start(
        const CombatV1ProductionMatchConfig(
          wrestlerAId: 'misaki',
          wrestlerBId: 'jack',
          playerAOwnerId: 'player-a',
          playerBOwnerId: 'player-b',
        ),
        random: Random(1),
      );
      _expectValidProductionMatch(
        state,
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
      );
    });
  });

  group('B. Akari vs Reina（cross-wrestler） → start成功', () {
    test('CombatV1ProductionMatchStarter.startで開始できる', () {
      final state = CombatV1ProductionMatchStarter.start(
        const CombatV1ProductionMatchConfig(
          wrestlerAId: 'akari',
          wrestlerBId: 'reina',
          playerAOwnerId: 'player-a',
          playerBOwnerId: 'player-b',
        ),
        random: Random(2),
      );
      _expectValidProductionMatch(
        state,
        wrestlerAId: 'akari',
        wrestlerBId: 'reina',
      );
    });
  });

  group('C. mirror match: Misaki vs Misaki → start成功（禁止しない）', () {
    test('CombatV1ProductionMatchStarter.startで開始できる', () {
      final state = CombatV1ProductionMatchStarter.start(
        const CombatV1ProductionMatchConfig(
          wrestlerAId: 'misaki',
          wrestlerBId: 'misaki',
          playerAOwnerId: 'player-a',
          playerBOwnerId: 'player-b',
        ),
        random: Random(3),
      );
      _expectValidProductionMatch(
        state,
        wrestlerAId: 'misaki',
        wrestlerBId: 'misaki',
      );
    });
  });

  group('D. mirror match: Reina vs Reina → start成功（禁止しない）', () {
    test('CombatV1ProductionMatchStarter.startで開始できる', () {
      final state = CombatV1ProductionMatchStarter.start(
        const CombatV1ProductionMatchConfig(
          wrestlerAId: 'reina',
          wrestlerBId: 'reina',
          playerAOwnerId: 'player-a',
          playerBOwnerId: 'player-b',
        ),
        random: Random(4),
      );
      _expectValidProductionMatch(
        state,
        wrestlerAId: 'reina',
        wrestlerBId: 'reina',
      );
    });
  });

  group('E. 4 wrestler全組み合わせ（4×4=16 ordered combinations）', () {
    for (final wrestlerAId in productionWrestlerIds) {
      for (final wrestlerBId in productionWrestlerIds) {
        test('$wrestlerAId(player-a) vs $wrestlerBId(player-b) → start成功', () {
          final state = CombatV1ProductionMatchStarter.start(
            CombatV1ProductionMatchConfig(
              wrestlerAId: wrestlerAId,
              wrestlerBId: wrestlerBId,
              playerAOwnerId: 'player-a',
              playerBOwnerId: 'player-b',
            ),
            random: Random(42),
          );
          _expectValidProductionMatch(
            state,
            wrestlerAId: wrestlerAId,
            wrestlerBId: wrestlerBId,
          );
        });
      }
    }
  });

  group('F. unknown wrestlerA → reject', () {
    test('未知のwrestlerAIdはCombatV1IllegalActionExceptionを送出する', () {
      expect(
        () => CombatV1ProductionMatchStarter.start(
          const CombatV1ProductionMatchConfig(
            wrestlerAId: 'unknown-wrestler',
            wrestlerBId: 'jack',
            playerAOwnerId: 'player-a',
            playerBOwnerId: 'player-b',
          ),
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('G. unknown wrestlerB → reject', () {
    test('未知のwrestlerBIdはCombatV1IllegalActionExceptionを送出する', () {
      expect(
        () => CombatV1ProductionMatchStarter.start(
          const CombatV1ProductionMatchConfig(
            wrestlerAId: 'misaki',
            wrestlerBId: 'unknown-wrestler',
            playerAOwnerId: 'player-a',
            playerBOwnerId: 'player-b',
          ),
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('未知のwrestlerA/wrestlerB双方の場合もCombatV1IllegalActionExceptionを送出する', () {
      expect(
        () => CombatV1ProductionMatchStarter.start(
          const CombatV1ProductionMatchConfig(
            wrestlerAId: 'unknown-a',
            wrestlerBId: 'unknown-b',
            playerAOwnerId: 'player-a',
            playerBOwnerId: 'player-b',
          ),
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('H. duplicate ownerId → reject', () {
    test('playerAOwnerId == playerBOwnerIdはCombatV1IllegalActionExceptionを送出する', () {
      expect(
        () => CombatV1ProductionMatchStarter.start(
          const CombatV1ProductionMatchConfig(
            wrestlerAId: 'misaki',
            wrestlerBId: 'jack',
            playerAOwnerId: 'same-owner',
            playerBOwnerId: 'same-owner',
          ),
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('I. empty / whitespace-only ownerId → reject', () {
    test('playerAOwnerIdが空文字はCombatV1IllegalActionExceptionを送出する', () {
      expect(
        () => CombatV1ProductionMatchStarter.start(
          const CombatV1ProductionMatchConfig(
            wrestlerAId: 'misaki',
            wrestlerBId: 'jack',
            playerAOwnerId: '',
            playerBOwnerId: 'player-b',
          ),
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('playerBOwnerIdが空白のみはCombatV1IllegalActionExceptionを送出する', () {
      expect(
        () => CombatV1ProductionMatchStarter.start(
          const CombatV1ProductionMatchConfig(
            wrestlerAId: 'misaki',
            wrestlerBId: 'jack',
            playerAOwnerId: 'player-a',
            playerBOwnerId: '   ',
          ),
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('playerAOwnerIdが空白のみはCombatV1IllegalActionExceptionを送出する', () {
      expect(
        () => CombatV1ProductionMatchStarter.start(
          const CombatV1ProductionMatchConfig(
            wrestlerAId: 'misaki',
            wrestlerBId: 'jack',
            playerAOwnerId: '  ',
            playerBOwnerId: 'player-b',
          ),
        ),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('J. wrestler/deck整合性（Production APIは必ず正しいdeckを選択する）', () {
    test('各wrestlerIdについてplayerの手持ちカードは自分のwrestler用cardIdのみで構成される', () {
      final state = CombatV1ProductionMatchStarter.start(
        const CombatV1ProductionMatchConfig(
          wrestlerAId: 'akari',
          wrestlerBId: 'reina',
          playerAOwnerId: 'player-a',
          playerBOwnerId: 'player-b',
        ),
        random: Random(7),
      );

      final aCardIds = [
        ...state.playerA.hand,
        ...state.playerA.drawPile,
        ...state.playerA.discardPile,
      ].map((e) => e.cardId);
      final bCardIds = [
        ...state.playerB.hand,
        ...state.playerB.drawPile,
        ...state.playerB.discardPile,
      ].map((e) => e.cardId);

      expect(
        aCardIds.every(
          (cardId) => cardId.startsWith('akari_') || cardId.startsWith('counter_akari_'),
        ),
        isTrue,
      );
      expect(
        bCardIds.every(
          (cardId) => cardId.startsWith('reina_') || cardId.startsWith('counter_reina_'),
        ),
        isTrue,
      );
    });
  });

  group('K. Production Data regression（wrestlerId/ENERGY Pool/Deck composition）', () {
    test('各wrestlerで、開始したmatchのwrestlerIdとENERGY Poolがカタログ定義と一致する', () {
      for (final wrestlerId in productionWrestlerIds) {
        final state = CombatV1ProductionMatchStarter.start(
          CombatV1ProductionMatchConfig(
            wrestlerAId: wrestlerId,
            wrestlerBId: 'jack',
            playerAOwnerId: 'player-a',
            playerBOwnerId: 'player-b',
          ),
          random: Random(9),
        );

        final expectedWrestler = combatV1ProductionWrestlerRegistry[wrestlerId]!
            .wrestler;
        expect(state.playerA.wrestlerId, expectedWrestler.id);
        expect(state.playerA.energyPool, expectedWrestler.energyPool);
      }
    });
  });

  group('L. rulesを明示指定した場合、そのRulesConfigがEngineへ渡る', () {
    test('startingHandSizeを変更すると初期手札枚数に反映される', () {
      const customRules = CombatV1RulesConfig(startingHandSize: 6);
      final state = CombatV1ProductionMatchStarter.start(
        const CombatV1ProductionMatchConfig(
          wrestlerAId: 'misaki',
          wrestlerBId: 'jack',
          playerAOwnerId: 'player-a',
          playerBOwnerId: 'player-b',
          rules: customRules,
        ),
        random: Random(11),
      );
      // playerAは手番プレイヤーとして開始直後に1ドローしているため+1枚。
      expect(state.playerA.hand.length, 7);
      expect(state.playerB.hand.length, 6);
    });
  });

  group('M. deterministic testability（同じseedのRandomなら同じ結果を再現する）', () {
    test('同じRandom seedを渡すと同一の初期手札構成になる', () {
      final config = const CombatV1ProductionMatchConfig(
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
        playerAOwnerId: 'player-a',
        playerBOwnerId: 'player-b',
      );
      final stateOne = CombatV1ProductionMatchStarter.start(
        config,
        random: Random(1234),
      );
      final stateTwo = CombatV1ProductionMatchStarter.start(
        config,
        random: Random(1234),
      );

      expect(
        stateOne.playerA.hand.map((e) => e.instanceId).toList(),
        stateTwo.playerA.hand.map((e) => e.instanceId).toList(),
      );
      expect(
        stateOne.playerB.hand.map((e) => e.instanceId).toList(),
        stateTwo.playerB.hand.map((e) => e.instanceId).toList(),
      );
    });
  });
}
