// Combat Ver.1 Phase 2: Deck/Handの正式仕様の検証
// （docs/combat_rules_v1.md 4・16章、Phase 2テスト項目【Initial hand】
// 【Hand circulation】【Reshuffle】【Card conservation】、19〜40番）。
//
// 方針:
// - 初期手札・山札再構築の枚数遷移は、実際に[CombatV1Engine.start]
//   （フィクスチャの正式30枚デッキ、固定seed）を駆動して検証する。
// - 手札循環（discard/action境界、TECHNIQUE使用後drawなど）の枚数遷移は、
//   どの具体的カードが手札にあるかに依存しない決定的なテストにするため、
//   [_buildState] でMatchStateを直接組み立ててから検証する
//   （combat_v1_engine_test.dartのbuildActionStateと同じ方針）。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_wrestler.dart';

import 'combat_v1_test_fixtures.dart';

CombatV1PlayerState _playerState({
  required CombatV1Wrestler wrestler,
  List<CombatV1DeckEntry> hand = const [],
  List<CombatV1DeckEntry> drawPile = const [],
  List<CombatV1DeckEntry> discardPile = const [],
  int hp = 150,
  int koc = 10,
}) => CombatV1PlayerState(
  wrestlerId: wrestler.id,
  wrestlerName: wrestler.name,
  maxHp: 150,
  hp: hp,
  koc: koc,
  pinCardsHeld: 2,
  energyPool: wrestler.energyPool,
  hand: hand,
  drawPile: drawPile,
  discardPile: discardPile,
);

/// `phase`・両者の手札／山札／捨て札を直接指定してMatchStateを組み立てる。
/// シャッフル結果に依存しない決定的なテスト用。
CombatV1MatchState _buildState({
  CombatV1MatchPhase phase = CombatV1MatchPhase.action,
  List<CombatV1DeckEntry> handA = const [],
  List<CombatV1DeckEntry> drawPileA = const [],
  List<CombatV1DeckEntry> discardPileA = const [],
  List<CombatV1DeckEntry> handB = const [],
  List<CombatV1DeckEntry> drawPileB = const [],
  List<CombatV1DeckEntry> discardPileB = const [],
  int activePlayerIndex = 0,
}) {
  final playerA = _playerState(
    wrestler: fixtureWrestlerA,
    hand: handA,
    drawPile: drawPileA,
    discardPile: discardPileA,
  );
  final playerB = _playerState(
    wrestler: fixtureWrestlerB,
    hand: handB,
    drawPile: drawPileB,
    discardPile: discardPileB,
  );
  return CombatV1MatchState(
    matchId: 'test-match',
    playerA: playerA,
    playerB: playerB,
    activePlayerIndex: activePlayerIndex,
    turnNumber: 1,
    phase: phase,
  );
}

/// [count]枚のダミー物理カードを生成する（カード内容そのものはこの
/// ファイルのテストの関心事ではないため、カタログに存在しないcardIdでも
/// よい。実際に使用（declareTechnique）しないカード専用）。
List<CombatV1DeckEntry> _dummyCards(String prefix, int count) => [
  for (var i = 0; i < count; i++)
    CombatV1DeckEntry(
      instanceId: '${prefix}_$i',
      cardId: 'fx_dummy_filler',
      category: CombatV1CardCategory.normal,
    ),
];

int _totalCardsFor(CombatV1PlayerState player) =>
    player.drawPile.length + player.hand.length + player.discardPile.length;

void _expectNoDuplicateInstanceIds(CombatV1PlayerState player) {
  final ids = [
    ...player.drawPile.map((e) => e.instanceId),
    ...player.hand.map((e) => e.instanceId),
    ...player.discardPile.map((e) => e.instanceId),
  ];
  expect(
    ids.toSet().length,
    ids.length,
    reason: '${player.wrestlerName}: drawPile/hand/discardPileに'
        'instanceIdの重複がある',
  );
}

void main() {
  group('初期手札（docs/combat_rules_v1.md 4章）', () {
    test('19. 開始時初期手札5枚を引く', () {
      final state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck(fixtureWrestlerA.id),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck(fixtureWrestlerB.id),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(1),
      );
      // playerBはまだ自分のターン開始処理（1ドロー）を経ていないため、
      // 配られたそのままの初期手札5枚が観測できる。
      expect(state.playerB.hand.length, 5);
    });

    test('20. 先攻turn startの1draw後に6枚', () {
      final state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck(fixtureWrestlerA.id),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck(fixtureWrestlerB.id),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(1),
      );
      expect(state.phase, CombatV1MatchPhase.discard);
      expect(state.playerA.hand.length, 6);
    });

    test('21. 1discard後に5枚', () {
      var state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck(fixtureWrestlerA.id),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck(fixtureWrestlerB.id),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(1),
      );
      state = CombatV1Engine.discardCard(state, state.active.hand.first.instanceId);
      expect(state.phase, CombatV1MatchPhase.action);
      expect(state.playerA.hand.length, 5);
    });

    test('22. 後攻も最初のturn startで5→6→5になる', () {
      var state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck(fixtureWrestlerA.id),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck(fixtureWrestlerB.id),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(1),
      );
      expect(state.playerB.hand.length, 5); // 後攻はまだ5枚のまま

      state = CombatV1Engine.discardCard(state, state.active.hand.first.instanceId);
      state = CombatV1Engine.endTurn(state, random: Random(2));

      expect(state.activePlayerIndex, 1);
      expect(state.phase, CombatV1MatchPhase.discard);
      expect(state.playerB.hand.length, 6); // 5→6（turn start 1draw）

      state = CombatV1Engine.discardCard(state, state.active.hand.first.instanceId);

      expect(state.phase, CombatV1MatchPhase.action);
      expect(state.playerB.hand.length, 5); // 6→5（discard）
    });
  });

  group('ターン開始時の手札循環（docs/combat_rules_v1.md 16.1章）', () {
    test('23. TECHNIQUE使用 5→4→draw→5', () {
      final technique = const CombatV1DeckEntry(
        instanceId: 't1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = _buildState(
        handA: [technique, ..._dummyCards('h', 4)],
        drawPileA: _dummyCards('d', 3),
      );
      expect(state.playerA.hand.length, 5);

      final next = declareAndResolveTechnique(
        state,
        't1',
        catalog: fixtureCatalog,
        random: Random(1),
      );

      expect(next.playerA.hand.any((e) => e.instanceId == 't1'), isFalse);
      expect(next.playerA.hand.length, 5); // 4枚 + draw1枚 = 5枚
    });

    test('24. 同一ターン2技使用でも各使用後に5枚へ戻る', () {
      final t1 = const CombatV1DeckEntry(
        instanceId: 't1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final t2 = const CombatV1DeckEntry(
        instanceId: 't2',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      // fixtureWrestlerAの打ENERGYは3なので、打1コスト技を2回使用できる。
      final state = _buildState(
        handA: [t1, t2, ..._dummyCards('h', 3)],
        drawPileA: _dummyCards('d', 5),
      );

      var next = declareAndResolveTechnique(
        state,
        't1',
        catalog: fixtureCatalog,
        random: Random(1),
      );
      expect(next.playerA.hand.length, 5);

      next = declareAndResolveTechnique(
        next,
        't2',
        catalog: fixtureCatalog,
        random: Random(2),
      );
      expect(next.playerA.hand.length, 5);
    });

    test('25. discard phaseではTECHNIQUEを使用できない', () {
      final technique = const CombatV1DeckEntry(
        instanceId: 't1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = _buildState(
        phase: CombatV1MatchPhase.discard,
        handA: [technique, ..._dummyCards('h', 4)],
      );

      final check = CombatV1Engine.checkTechniqueLegality(
        state,
        't1',
        catalog: fixtureCatalog,
      );
      expect(check.legal, isFalse);

      expect(
        () => declareAndResolveTechnique(state, 't1', catalog: fixtureCatalog),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('26. actionフェーズでは通常のturn-start discardは行えない', () {
      final state = _buildState(
        phase: CombatV1MatchPhase.action,
        handA: _dummyCards('h', 5),
      );

      expect(
        () => CombatV1Engine.discardCard(state, state.playerA.hand.first.instanceId),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('27. 存在しないカードをdiscardすると例外', () {
      final state = _buildState(
        phase: CombatV1MatchPhase.discard,
        handA: _dummyCards('h', 5),
      );

      expect(
        () => CombatV1Engine.discardCard(state, 'not_in_hand'),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });

    test('28. 相手手札のカードinstanceIdをdiscardすると例外', () {
      final opponentCard = const CombatV1DeckEntry(
        instanceId: 'opponent_card',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = _buildState(
        phase: CombatV1MatchPhase.discard,
        handA: _dummyCards('h', 5),
        handB: [opponentCard],
      );

      expect(
        () => CombatV1Engine.discardCard(state, 'opponent_card'),
        throwsA(isA<CombatV1IllegalActionException>()),
      );
    });
  });

  group('山札再構築（docs/combat_rules_v1.md 16章）', () {
    test('29〜33. 山札0＋捨て札ありで再構築してdrawし、reshuffleCountが+1、'
        'HP/HEAT/KOCは変化しない', () {
      final discarded = _dummyCards('a_discard', 4);
      final playerA = _playerState(
        wrestler: fixtureWrestlerA,
        hand: _dummyCards('a_hand', 1),
        drawPile: const [],
        discardPile: discarded,
      );
      final playerB = _playerState(
        wrestler: fixtureWrestlerB,
        hand: _dummyCards('b_hand', 1),
        drawPile: _dummyCards('b_draw', 3),
      );
      var state = CombatV1MatchState(
        matchId: 'test-match',
        playerA: playerA,
        playerB: playerB,
        activePlayerIndex: 0,
        sharedHeat: 20,
        turnNumber: 1,
        phase: CombatV1MatchPhase.action,
      );

      final initialHp = state.playerA.hp;
      final initialHeat = state.sharedHeat;
      final initialKoc = state.playerA.koc;

      // A→Bへターン交代（Bのturn start）。
      state = CombatV1Engine.endTurn(state, random: Random(1));
      expect(state.activePlayerIndex, 1);
      state = CombatV1Engine.discardCard(state, state.active.hand.first.instanceId);
      // B→Aへターン交代。Aのturn start 1ドローで、drawPile空・discardPileあり
      // の状態から再構築が発生する。
      state = CombatV1Engine.endTurn(state, random: Random(2));

      expect(state.activePlayerIndex, 0);
      expect(state.playerA.reshuffleCount, 1); // 29・30
      expect(state.playerA.discardPile, isEmpty);
      expect(state.playerA.drawPile, isNotEmpty);
      expect(state.playerA.hand.length, 2); // 元1枚 + 再構築後の1draw

      expect(state.playerA.hp, initialHp); // 31
      expect(state.sharedHeat, initialHeat); // 32
      expect(state.playerA.koc, initialKoc); // 33
    });

    test('34. 複数回再構築可能（reshuffleCountが2以上になる）', () {
      const smallComposition = CombatV1DeckComposition(
        normalCount: 3,
        signatureCount: 0,
        finisherCount: 0,
        counterCount: 0,
      );
      const smallRules = CombatV1RulesConfig(
        startingHandSize: 1,
        deckComposition: smallComposition,
        // 単一カードを繰り返し採用するため、同名上限を緩めておく
        // （このテストの関心事は再構築の反復であり同名上限ではないため）。
        normalSameNameLimit: 3,
      );
      CombatV1DeckDefinition smallDeck(String wrestlerId) => CombatV1DeckDefinition(
        wrestlerId: wrestlerId,
        entries: [
          for (var i = 0; i < 3; i++)
            CombatV1DeckEntry(
              instanceId: '${wrestlerId}_c$i',
              cardId: 'fx_normal_strike',
              category: CombatV1CardCategory.normal,
            ),
        ],
      );

      var state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: smallDeck(fixtureWrestlerA.id),
        wrestlerB: fixtureWrestlerB,
        deckB: smallDeck(fixtureWrestlerB.id),
        rules: smallRules,
        catalog: fixtureCatalog,
        random: Random(11),
      );

      for (var i = 0; i < 30; i++) {
        state = CombatV1Engine.discardCard(state, state.active.hand.first.instanceId);
        state = CombatV1Engine.endTurn(state, random: Random(200 + i));
      }

      expect(state.playerA.reshuffleCount, greaterThanOrEqualTo(2));
      expect(state.playerB.reshuffleCount, greaterThanOrEqualTo(2));
      // 再構築を繰り返しても総枚数は保存される。
      expect(_totalCardsFor(state.playerA), 3);
      expect(_totalCardsFor(state.playerB), 3);
    });
  });

  group('カード保存則（docs/combat_rules_v1.md 3・16章、drawPile+hand+'
      'discardPile=30）', () {
    test('35. 開始直後にカード総数30', () {
      final state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck(fixtureWrestlerA.id),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck(fixtureWrestlerB.id),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(1),
      );
      expect(_totalCardsFor(state.playerA), 30);
      expect(_totalCardsFor(state.playerB), 30);
      _expectNoDuplicateInstanceIds(state.playerA);
      _expectNoDuplicateInstanceIds(state.playerB);
    });

    test('36. turn-start draw/discard後も総数30', () {
      var state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck(fixtureWrestlerA.id),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck(fixtureWrestlerB.id),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(1),
      );

      for (var i = 0; i < 6; i++) {
        state = CombatV1Engine.discardCard(state, state.active.hand.first.instanceId);
        state = CombatV1Engine.endTurn(state, random: Random(50 + i));
        expect(_totalCardsFor(state.playerA), 30);
        expect(_totalCardsFor(state.playerB), 30);
      }
      _expectNoDuplicateInstanceIds(state.playerA);
      _expectNoDuplicateInstanceIds(state.playerB);
    });

    test('37. TECHNIQUE使用後も総数30', () {
      final technique = const CombatV1DeckEntry(
        instanceId: 't1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = _buildState(
        handA: [technique, ..._dummyCards('h', 4)],
        drawPileA: _dummyCards('d', 25), // 5(hand) + 25(draw) = 30
        handB: _dummyCards('hb', 5),
        drawPileB: _dummyCards('db', 25),
      );
      expect(_totalCardsFor(state.playerA), 30);

      final next = declareAndResolveTechnique(
        state,
        't1',
        catalog: fixtureCatalog,
        random: Random(1),
      );

      expect(_totalCardsFor(next.playerA), 30);
      _expectNoDuplicateInstanceIds(next.playerA);
    });

    test('38. 複数TECHNIQUE使用後も総数30', () {
      final t1 = const CombatV1DeckEntry(
        instanceId: 't1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final t2 = const CombatV1DeckEntry(
        instanceId: 't2',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = _buildState(
        handA: [t1, t2, ..._dummyCards('h', 3)],
        drawPileA: _dummyCards('d', 25),
      );
      expect(_totalCardsFor(state.playerA), 30);

      var next = declareAndResolveTechnique(
        state,
        't1',
        catalog: fixtureCatalog,
        random: Random(1),
      );
      expect(_totalCardsFor(next.playerA), 30);

      next = declareAndResolveTechnique(
        next,
        't2',
        catalog: fixtureCatalog,
        random: Random(2),
      );
      expect(_totalCardsFor(next.playerA), 30);
      _expectNoDuplicateInstanceIds(next.playerA);
    });

    test('39. 正式30枚デッキでreshuffleが発生しても総数30、40. 重複instanceIdなし', () {
      var state = CombatV1Engine.start(
        wrestlerA: fixtureWrestlerA,
        deckA: fixtureDeck(fixtureWrestlerA.id),
        wrestlerB: fixtureWrestlerB,
        deckB: fixtureDeck(fixtureWrestlerB.id),
        rules: fixtureRules,
        catalog: fixtureCatalog,
        random: Random(3),
      );

      // TECHNIQUEは使わずdiscard→endTurnのみを繰り返し、山札を枯渇させて
      // 再構築を発生させる（drawPile初期25枚に対し十分な反復回数）。
      for (var i = 0; i < 60; i++) {
        state = CombatV1Engine.discardCard(state, state.active.hand.first.instanceId);
        state = CombatV1Engine.endTurn(state, random: Random(300 + i));
      }

      expect(
        state.playerA.reshuffleCount + state.playerB.reshuffleCount,
        greaterThan(0),
      );
      expect(_totalCardsFor(state.playerA), 30); // 39
      expect(_totalCardsFor(state.playerB), 30); // 39
      _expectNoDuplicateInstanceIds(state.playerA); // 40
      _expectNoDuplicateInstanceIds(state.playerB); // 40
    });
  });
}
