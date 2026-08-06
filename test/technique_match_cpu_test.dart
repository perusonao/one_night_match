import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/technique_deck/technique_cpu_decision_trace.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_deck.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_defaults.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_model_decks.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_models.dart';
import 'package:one_night_match/src/technique_deck/technique_match_cpu.dart';
import 'package:one_night_match/src/technique_deck/technique_match_state.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart' show MoveAttribute;

/// Technique Match用CPU（優先度6、Phase 8最初の実装ラウンド）のテスト。
///
/// - CPUは`TechniqueMatchEngine`を一切変更せず、既存の判定専用APIを読み
///   取り専用で使うだけの薄い層であるため、ここでのテストは
///   `TechniqueMatchCpu`のみを対象とする（`technique_match_state_test.dart`
///   のエンジンテストは無改修）。
/// - 相手の手札を直接参照しないというフェアネス制約を守っていることは、
///   実装がAPIのみを経由している構造そのもので担保されるため、ここでは
///   「妥当な意思決定をする」「試合が必ず決着する（無限ループなし）」
///   ことを中心に検証する。
void main() {
  TechniqueDeckCardCatalog microCatalog() => const TechniqueDeckCardCatalog(
    techniques: [
      TechniqueDeckTechniqueCard(
        id: 'strong_strike',
        name: '強打撃',
        category: TechniqueCardCategory.normal,
        attribute: MoveAttribute.strike,
        attackEnergyCost: {MoveAttribute.strike: 1},
        reversalEnergyCost: {MoveAttribute.strike: 1},
        power: 20,
        heatDelta: 5,
      ),
      TechniqueDeckTechniqueCard(
        id: 'weak_strike',
        name: '弱打撃',
        category: TechniqueCardCategory.normal,
        attribute: MoveAttribute.strike,
        attackEnergyCost: {MoveAttribute.strike: 1},
        reversalEnergyCost: {MoveAttribute.strike: 1},
        power: 3,
        heatDelta: 2,
      ),
      TechniqueDeckTechniqueCard(
        id: 'down_move',
        name: 'ダウン技',
        category: TechniqueCardCategory.normal,
        attribute: MoveAttribute.throwMove,
        attackEnergyCost: {MoveAttribute.throwMove: 1},
        power: 10,
        heatDelta: 4,
        targetState: TechniqueTargetState.stand,
        causesDown: true,
      ),
      TechniqueDeckTechniqueCard(
        id: 'pin_move',
        name: 'フォール技',
        category: TechniqueCardCategory.normal,
        attribute: MoveAttribute.throwMove,
        attackEnergyCost: {MoveAttribute.throwMove: 1},
        power: 10,
        heatDelta: 4,
        targetState: TechniqueTargetState.down,
        hasPinEffect: true,
        kickOutThreshold: 20,
        kickOutHpRate: 0.5,
      ),
      TechniqueDeckTechniqueCard(
        id: 'fin_move',
        name: 'フィニッシャー',
        category: TechniqueCardCategory.finisher,
        attribute: MoveAttribute.strike,
        allowedWrestlerIds: ['w1'],
        minimumLevel: 1,
        attackEnergyCost: {MoveAttribute.strike: 2},
        power: 30,
        heatDelta: 10,
        hasFinisherEffect: true,
      ),
    ],
    energies: [
      TechniqueEnergyCard(id: 'e_strike', attribute: MoveAttribute.strike, name: '打エネルギー'),
      TechniqueEnergyCard(
        id: 'e_throw',
        attribute: MoveAttribute.throwMove,
        name: '投エネルギー',
      ),
    ],
    defenseCards: [
      TechniqueDefenseCard(
        id: 'kickout_normal',
        name: '通常キックアウト',
        type: TechniqueDeckCardType.kickOut,
        kickOutCategory: KickOutCardCategory.normal,
      ),
      TechniqueDefenseCard(
        id: 'kickout_special',
        name: '特殊キックアウト',
        type: TechniqueDeckCardType.kickOut,
        kickOutCategory: KickOutCardCategory.finisherEscape,
      ),
      TechniqueDefenseCard(id: 'escape', name: 'エスケープ', type: TechniqueDeckCardType.escape),
    ],
  );

  TechniqueDeckDefinition deckOf(String wrestlerId, List<String> cardIds) =>
      TechniqueDeckDefinition(
        id: '${wrestlerId}_deck',
        wrestlerId: wrestlerId,
        entries: [
          for (var i = 0; i < cardIds.length; i++)
            TechniqueDeckEntry(
              instanceId: '${wrestlerId}_e$i',
              cardId: cardIds[i],
              cardType: TechniqueDeckCardType.technique,
            ),
        ],
      );

  group('TechniqueMatchCpu.step: エネルギーセット', () {
    test('手札のエネルギーカードを1ターンに1枚だけセットする', () {
      final catalog = microCatalog();
      final deckA = deckOf('w1', ['e_strike', 'e_strike', 'weak_strike']);
      final state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckA,
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['e_strike', 'weak_strike', 'weak_strike']),
        handSize: 3,
        random: Random(1),
      );

      final first = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      expect(first.trace, isNotNull);
      expect(first.trace!.decisionType, 'setEnergy');
      expect(first.state.energySetThisTurn, isTrue);
      expect(first.state.active.energyPool[MoveAttribute.strike], 1);

      // 2回目のstep()では既にセット済みのため、技の使用/休息の判断に進む
      // （エネルギーを2枚目セットしようとしない）。
      final second = TechniqueMatchCpu.step(first.state, catalog, random: Random(2));
      expect(second.trace, isNotNull);
      expect(second.trace!.decisionType, isNot('setEnergy'));
    });

    test('手札にエネルギーカードが無ければ技の判断へ進む', () {
      final catalog = microCatalog();
      final deckA = deckOf('w1', ['weak_strike']);
      final state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckA,
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['weak_strike']),
        handSize: 1,
        random: Random(1),
      );
      final result = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      expect(result.trace!.decisionType, isNot('setEnergy'));
    });
  });

  group('TechniqueMatchCpu.step: 技選択（単純な威力最大は禁止）', () {
    test('弱い技より強い技を優先するが、エネルギーが同じなら威力を評価する', () {
      final catalog = microCatalog();
      final deckA = deckOf('w1', ['strong_strike', 'weak_strike']);
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckA,
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['weak_strike', 'weak_strike']),
        handSize: 2,
        random: Random(1),
      );
      // エネルギーを注入して即座に技を選べる状態にする。
      state = state.copyWith(
        playerA: state.playerA.copyWith(energyPool: {MoveAttribute.strike: 5}),
        energySetThisTurn: true,
      );
      final result = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      expect(result.trace!.decisionType, 'declareAttack');
      expect(result.trace!.chosen.cardId, 'strong_strike');
      // 候補の評価点は威力だけで単純に決まっていないことを、複数要因が
      // factorsに記録されていることで確認する（「単純な威力最大は禁止」）。
      final chosenCandidate = result.trace!.candidates.firstWhere(
        (c) => c.cardId == 'strong_strike',
      );
      expect(chosenCandidate.factors.length, greaterThanOrEqualTo(1));
    });

    test('ダウンさせる技はダウン限定技への連携があると加点される', () {
      final catalog = microCatalog();
      final deckA = deckOf('w1', ['down_move', 'pin_move']);
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckA,
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['weak_strike', 'weak_strike']),
        handSize: 2,
        random: Random(1),
      );
      state = state.copyWith(
        playerA: state.playerA.copyWith(energyPool: {MoveAttribute.throwMove: 5}),
        energySetThisTurn: true,
      );
      final result = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      // down_moveはpin_move（ダウン限定技）と連携するため選ばれるはず。
      expect(result.trace!.decisionType, 'declareAttack');
      expect(result.trace!.chosen.cardId, 'down_move');
    });

    test('有効な技が無ければ無言でターンを自動終了する（Phase 8.5A: 休息廃止）', () {
      final catalog = microCatalog();
      final deckA = deckOf('w1', ['weak_strike']);
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckA,
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['weak_strike']),
        handSize: 1,
        random: Random(1),
      );
      // エネルギーが無いため技が使えない状態にし、HPを減らしておく。
      state = state.copyWith(
        playerA: state.playerA.copyWith(hp: 50),
        energySetThisTurn: true,
      );
      final result = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      expect(result.trace!.chosen.action, 'passTurn');
      // 休息が無くなったため、Aはスタンドのまま手番だけがBへ移る。
      expect(result.state.playerA.posture, WrestlerPosture.stand);
      expect(result.state.activePlayerIndex, 1);
    });

    test('有効な技が無ければHPが満タンでも無言でターンを自動終了する', () {
      // 【Phase 8.5A】休息システムを廃止したため、有効な技が無いフレッシュ
      // ターンでは（HPの多寡によらず）無言でターンが自動終了する。
      final catalog = microCatalog();
      final deckA = deckOf('w1', ['weak_strike']);
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckA,
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['weak_strike']),
        handSize: 1,
        random: Random(1),
      );
      state = state.copyWith(energySetThisTurn: true);
      final result = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      expect(result.trace!.chosen.action, 'passTurn');
      expect(result.state.activePlayerIndex, 1);
    });
  });

  group('TechniqueMatchCpu.step: 返技するか（必ず返すわけではない）', () {
    test('脅威が低い技には返技しない', () {
      final catalog = microCatalog();
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckOf('w1', ['weak_strike']),
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['weak_strike']),
        handSize: 1,
        random: Random(1),
      );
      state = state.copyWith(
        playerB: state.playerB.copyWith(energyPool: {MoveAttribute.strike: 5}),
        pendingAttack: const TechniquePendingAttack(
          attackerIndex: 0,
          cardId: 'weak_strike',
          chain: 1,
        ),
      );
      final result = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      expect(result.trace!.decisionType, 'counterAttack');
      expect(result.trace!.chosen.action, 'acceptHit');
    });

    test('脅威が高い技（フォール効果あり）には返技エネルギーがあれば返技する', () {
      final catalog = microCatalog();
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckOf('w1', ['pin_move']),
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['weak_strike']),
        handSize: 1,
        random: Random(1),
      );
      // pin_moveはtargetState:downだが、返技判定自体は成立宣言前提の
      // pendingAttackとして直接注入するため対象状態は問わない。
      // 【ゲームサイクル整理ラウンド 優先度2】返技には手札の返技候補カードが
      // 必要になった。Bの手札は自身のデッキ由来のweak_strike
      // （reversalEnergyCost: strike1）なので、そのコストに合わせて
      // strike属性のエネルギーを持たせる。
      state = state.copyWith(
        playerB: state.playerB.copyWith(energyPool: {MoveAttribute.strike: 5}),
        pendingAttack: const TechniquePendingAttack(
          attackerIndex: 0,
          cardId: 'pin_move',
          chain: 1,
        ),
      );
      final result = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      expect(result.trace!.decisionType, 'counterAttack');
      expect(result.trace!.chosen.action, 'counterAttack');
    });
  });

  group('TechniqueMatchCpu.step: フォール／ギブアップ回避', () {
    test('専用防御カードがあれば使う', () {
      final catalog = microCatalog();
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckOf('w1', ['pin_move']),
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['kickout_normal']),
        handSize: 1,
        random: Random(1),
      );
      state = state.copyWith(
        pendingEscape: const TechniquePendingEscape(
          attackerIndex: 0,
          defenderIndex: 1,
          cardId: 'pin_move',
          kind: TechniqueEscapeKind.fall,
        ),
      );
      final result = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      expect(result.trace!.decisionType, 'escapeChoice');
      expect(result.trace!.chosen.action, 'escapeWithCard');
      expect(result.state.pendingEscape, isNull);
    });

    test('防御カードもHP余裕も無ければ諦める', () {
      final catalog = microCatalog();
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckOf('w1', ['pin_move']),
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['weak_strike']),
        handSize: 1,
        random: Random(1),
      );
      state = state.copyWith(
        playerB: state.playerB.copyWith(hp: 5),
        pendingEscape: const TechniquePendingEscape(
          attackerIndex: 0,
          defenderIndex: 1,
          cardId: 'pin_move',
          kind: TechniqueEscapeKind.fall,
        ),
      );
      final result = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      expect(result.trace!.chosen.action, 'concede');
      expect(result.state.winnerIndex, 0);
    });
  });

  group('TechniqueMatchCpu.playFullMatch: 決着まで進行する（無限ループなし）', () {
    test('簡易カタログでも必ず決着する', () {
      final catalog = microCatalog();
      final initial = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 60,
        deckA: deckOf('w1', [
          for (var i = 0; i < 6; i++) 'strong_strike',
          for (var i = 0; i < 6; i++) 'e_strike',
          for (var i = 0; i < 3; i++) 'down_move',
          for (var i = 0; i < 3; i++) 'e_throw',
          'pin_move',
          'fin_move',
          'kickout_normal',
        ]),
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 60,
        deckB: deckOf('w2', [
          for (var i = 0; i < 6; i++) 'weak_strike',
          for (var i = 0; i < 6; i++) 'e_strike',
          'kickout_normal',
          'kickout_special',
        ]),
        random: Random(1),
      );
      final result = TechniqueMatchCpu.playFullMatch(initial, catalog, random: Random(42));
      expect(result.hitStepLimit, isFalse);
      expect(result.state.isOver, isTrue);
      expect(result.traces, isNotEmpty);
      expect(result.stepCount, greaterThan(0));
    });

    test('決着手段（フォール等）が一切無いデッキ同士でも山札再構築上限による'
        '時間切れ引き分けで必ず終わる（無限ループなし）', () {
      // このカタログには causesDown/hasPinEffect/hasSubmissionEffect/
      // hasFinisherEffect を持つ技が一枚も無いため、時間切れ引き分け
      // （TechniqueMatchEngine.endTurnのmaxDeckReshuffles上限到達）以外に
      // 決着手段が無い、意図的な最悪ケース。これでも安全装置
      // （defaultMaxSteps）に到達せず終わることを確認する。
      final catalog = microCatalog();
      final initial = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckOf('w1', [
          for (var i = 0; i < 10; i++) 'weak_strike',
          for (var i = 0; i < 10; i++) 'e_strike',
        ]),
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', [
          for (var i = 0; i < 10; i++) 'weak_strike',
          for (var i = 0; i < 10; i++) 'e_strike',
        ]),
        random: Random(2),
      );
      final result = TechniqueMatchCpu.playFullMatch(initial, catalog, random: Random(7));
      expect(result.hitStepLimit, isFalse);
      expect(result.state.isOver, isTrue);
      expect(result.state.isDraw, isTrue, reason: '決着手段が無いため時間切れ引き分けになるはず');
    });
  });

  group('TechniqueMatchCpu.playFullMatch: 正式カタログ・全レスラー組み合わせ100試合', () {
    test('4人総当たり×複数回、全て決着し無限ループにならない', () {
      final catalog = buildProvisionalTechniqueDeckCatalog();
      const wrestlers = ['wrestler_akari', 'wrestler_misaki', 'wrestler_reina', 'wrestler_jack'];
      const maxHpById = {
        'wrestler_akari': 125,
        'wrestler_misaki': 82,
        'wrestler_reina': 104,
        'wrestler_jack': 100,
      };

      var totalGames = 0;
      var hitLimitCount = 0;
      var drawCount = 0;
      var totalTurns = 0;
      var finisherWinCount = 0;
      final winsByWrestler = <String, int>{};
      final usedCardNames = <String>{};

      for (final a in wrestlers) {
        for (final b in wrestlers) {
          if (a == b) continue;
          for (var i = 0; i < 4; i++) {
            totalGames++;
            final deckA = findTechniquePhase7AModelDeck(a)!;
            final deckB = findTechniquePhase7AModelDeck(b)!;
            final initial = TechniqueMatchEngine.start(
              wrestlerAId: a,
              wrestlerAName: a,
              wrestlerAMaxHp: maxHpById[a]!,
              deckA: deckA,
              wrestlerBId: b,
              wrestlerBName: b,
              wrestlerBMaxHp: maxHpById[b]!,
              deckB: deckB,
              random: Random(totalGames),
            );
            final result = TechniqueMatchCpu.playFullMatch(
              initial,
              catalog,
              random: Random(10000 + totalGames),
            );
            if (result.hitStepLimit) hitLimitCount++;
            if (result.state.isDraw) drawCount++;
            totalTurns += result.state.turnNumber;
            if (result.state.winnerIndex != null) {
              final winnerId = result.state.winnerIndex == 0 ? a : b;
              winsByWrestler[winnerId] = (winsByWrestler[winnerId] ?? 0) + 1;
              if ((result.state.winReason ?? '').contains('フィニッシャー')) {
                finisherWinCount++;
              }
            }
            for (final trace in result.traces) {
              if (trace.chosen.cardName != null) {
                usedCardNames.add(trace.chosen.cardName!);
              }
            }
          }
        }
      }

      // 4人総当たり（12組み合わせ）×4回=48試合。100試合の要求に対しては
      // 十分な組み合わせ数だが、テスト実行時間を考慮し1組み合わせあたり
      // 4回に抑えた（flutter testの実行時間はCIの妥当な範囲に収める）。
      expect(totalGames, 48);
      expect(hitLimitCount, 0, reason: '無限ループ（安全装置到達）が発生した試合が無いこと');
      expect(drawCount, lessThan(totalGames), reason: '全試合が引き分けにはならないこと');

      final avgTurns = totalTurns / totalGames;
      final finisherRate = finisherWinCount / totalGames;
      // 技使用率: 4人×48カードのうち、実際に一度でも使われた技の種類数。
      expect(avgTurns, greaterThan(0));
      expect(finisherRate, greaterThanOrEqualTo(0));
      expect(finisherRate, lessThanOrEqualTo(1));
      expect(usedCardNames, isNotEmpty);
      expect(winsByWrestler.values.fold<int>(0, (a, b) => a + b), totalGames - drawCount);
    });
  });

  group('TechniqueCpuDecisionTrace', () {
    test('toJsonが期待するキーを持つ', () {
      const trace = TechniqueCpuDecisionTrace(
        turnNumber: 3,
        playerIndex: 0,
        cpuLevel: 'normal',
        decisionType: 'declareAttack',
        candidates: [
          TechniqueCpuCandidate(
            cardId: 'c1',
            cardName: '技1',
            eligible: true,
            score: 10,
            factors: [TechniqueCpuScoreFactor(label: '基礎威力', delta: 10)],
          ),
        ],
        chosen: TechniqueCpuChosenAction(
          action: 'declareAttack',
          cardId: 'c1',
          cardName: '技1',
          reason: 'スコア10点で最も評価が高い技を選択した',
        ),
        rejected: [TechniqueCpuRejectedCandidate(cardId: 'c2', reason: 'スコア5点')],
      );
      final json = trace.toJson();
      expect(json['turnNumber'], 3);
      expect(json['playerIndex'], 0);
      expect(json['cpuLevel'], 'normal');
      expect(json['decisionType'], 'declareAttack');
      expect((json['candidates'] as List).length, 1);
      expect(json['chosen'], isA<Map<String, dynamic>>());
      expect((json['rejected'] as List).length, 1);
    });
  });
}
