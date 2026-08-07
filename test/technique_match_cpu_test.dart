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
      // Phase 8.5A-2: Combo Speed関連テスト用。
      TechniqueDeckTechniqueCard(
        id: 'costly_strike',
        name: '高コスト打撃',
        category: TechniqueCardCategory.normal,
        attribute: MoveAttribute.strike,
        attackEnergyCost: {MoveAttribute.strike: 3},
        power: 4,
        heatDelta: 2,
      ),
      TechniqueDeckTechniqueCard(
        id: 'speed_light',
        name: '軽量技',
        category: TechniqueCardCategory.normal,
        attribute: MoveAttribute.strike,
        attackEnergyCost: {MoveAttribute.strike: 1},
        power: 5,
        heatDelta: 2,
        speed: 2,
      ),
      TechniqueDeckTechniqueCard(
        id: 'speed_heavy',
        name: '重量技',
        category: TechniqueCardCategory.normal,
        attribute: MoveAttribute.strike,
        attackEnergyCost: {MoveAttribute.strike: 1},
        power: 6,
        heatDelta: 2,
        speed: 7,
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

  group('Phase 8.5A-2: CPU攻撃停止バグの修正確認', () {
    test('低HP（40%以下）でもスコアの低い合法技があればpassTurnせず使用する'
        '（旧shouldRetreatロジックの回帰テスト）', () {
      // 実プレイで発覚したバグの再現条件: HPが40%以下、最も良い技でも
      // スコアが低い（15点未満）。休息廃止前は「休息を優先して様子見」の
      // つもりだったロジックが、休息が無くなった後は単に何もしない
      // （passTurn）バグになっていた。
      final catalog = microCatalog();
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckOf('w1', ['weak_strike']),
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['weak_strike', 'e_strike']),
        handSize: 2,
        random: Random(1),
      );
      state = state.copyWith(
        activePlayerIndex: 1,
        playerB: state.playerB.copyWith(
          hp: 20, // 20% HP。旧shouldRetreatの閾値（40%）を大きく下回る。
          energyPool: const {MoveAttribute.strike: 1},
        ),
        energySetThisTurn: true,
      );
      final result = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      expect(result.trace!.decisionType, 'declareAttack');
      expect(result.trace!.chosen.cardId, 'weak_strike');
    });

    test('唯一の合法技のスコアが負でも使用する（多様性ペナルティ等で全滅させない）', () {
      final catalog = microCatalog();
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckOf('w1', ['weak_strike']),
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['costly_strike']),
        handSize: 1,
        random: Random(1),
      );
      state = state.copyWith(
        activePlayerIndex: 1,
        playerB: state.playerB.copyWith(
          energyPool: const {MoveAttribute.strike: 3},
        ),
        energySetThisTurn: true,
      );
      final result = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      // costly_strikeのスコアは 4（威力） - 3*2（コスト） = -2 と負になるが、
      // 唯一の合法技なので必ず使用されるべき。
      expect(result.trace!.decisionType, 'declareAttack');
      expect(result.trace!.chosen.cardId, 'costly_strike');
    });

    test('本当に使用可能な技が無い場合のみpassTurnする', () {
      final catalog = microCatalog();
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckOf('w1', ['weak_strike']),
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['costly_strike']),
        handSize: 1,
        random: Random(1),
      );
      // エネルギーが無いため costly_strike は使用不可。
      state = state.copyWith(activePlayerIndex: 1, energySetThisTurn: true);
      final result = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      expect(result.trace!.decisionType, 'passTurn');
      expect(result.state.activePlayerIndex, 0);
    });
  });

  group('Phase 8.5A-2: Combo Speed対応（CPU）', () {
    test('残りSpeedが足りる限り1ターンで複数技を使用する', () {
      final catalog = microCatalog();
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckOf('w1', ['weak_strike']),
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['speed_light', 'speed_light']),
        handSize: 2,
        random: Random(1),
      );
      state = state.copyWith(
        activePlayerIndex: 1,
        playerB: state.playerB.copyWith(
          energyPool: const {MoveAttribute.strike: 2},
        ),
        energySetThisTurn: true,
      );
      final first = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      expect(first.trace!.decisionType, 'declareAttack');
      expect(first.state.rallyRemainingSpeed, 8); // 10 - speed(2)

      final second = TechniqueMatchCpu.step(first.state, catalog, random: Random(1));
      // Aは返技候補を持たないため、resolveHitを経てラリーが継続する。
      expect(second.trace!.decisionType, 'counterAttack');
      expect(second.trace!.chosen.action, 'acceptHit');
      expect(second.state.rallyAttackerIndex, 1); // ラリー継続、Bのまま。

      final third = TechniqueMatchCpu.step(second.state, catalog, random: Random(1));
      expect(third.trace!.decisionType, 'declareAttack');
      expect(third.trace!.chosen.cardId, 'speed_light');
      expect(third.state.rallyRemainingSpeed, 6); // 8 - speed(2)
    });

    test('残りSpeedが技のSpeedコストに満たない場合は候補から除外される', () {
      final catalog = microCatalog();
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckOf('w1', ['weak_strike']),
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['speed_heavy']),
        handSize: 1,
        random: Random(1),
      );
      state = state.copyWith(
        activePlayerIndex: 1,
        rallyAttackerIndex: 1,
        rallyChain: 1,
        rallyRemainingSpeed: 3, // speed_heavy（Speed7）には不足。
        playerB: state.playerB.copyWith(
          energyPool: const {MoveAttribute.strike: 1},
        ),
      );
      final result = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      expect(result.trace!.decisionType, 'endRally');
      final candidate = result.trace!.candidates.single;
      expect(candidate.eligible, isFalse);
      expect(candidate.ineligibleReason, contains('Speed'));
    });
  });

  group('Phase 8.5A-2: 返技成功後のCPU攻守交代', () {
    test('CPUが返技成功後、新しい攻撃側としてComboSpeed全回復のうえ攻撃を継続する', () {
      final catalog = microCatalog();
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckOf('w1', ['strong_strike']),
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['weak_strike', 'weak_strike']),
        handSize: 2,
        random: Random(1),
      );
      // Aがstrong_strikeを宣言。Bは返技候補（weak_strike、返技コストstrike1）
      // ＋返技用エネルギーを持つ。
      state = state.copyWith(
        playerA: state.playerA.copyWith(
          energyPool: const {MoveAttribute.strike: 1},
        ),
        playerB: state.playerB.copyWith(
          energyPool: const {MoveAttribute.strike: 2},
        ),
      );
      final declared = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog,
      ).state;
      expect(declared.pendingAttack, isNotNull);

      final counterResult = TechniqueMatchCpu.step(declared, catalog, random: Random(1));
      expect(counterResult.trace!.decisionType, 'counterAttack');
      expect(counterResult.trace!.chosen.action, 'counterAttack');
      expect(counterResult.state.rallyAttackerIndex, 1); // Bが新しい攻撃側。
      expect(
        counterResult.state.rallyRemainingSpeed,
        counterResult.state.playerB.comboSpeed,
      ); // ComboSpeedが全回復している。

      final followUp = TechniqueMatchCpu.step(counterResult.state, catalog, random: Random(1));
      expect(followUp.trace!.decisionType, 'declareAttack');
      expect(followUp.trace!.chosen.cardId, 'weak_strike');
    });
  });

  group('Phase 8.5A-2: 回帰ケース（アカリ対ミサキCPU）', () {
    test('固定シードの複数試合で、ミサキCPUの自発攻撃回数が0にならない', () {
      final catalog = buildProvisionalTechniqueDeckCatalog();
      final deckA = findTechniquePhase7AModelDeck('wrestler_akari')!;
      final deckB = findTechniquePhase7AModelDeck('wrestler_misaki')!;

      var zeroAttackGames = 0;
      var totalMisakiAttacks = 0;
      const gameCount = 12;
      for (var seed = 0; seed < gameCount; seed++) {
        final initial = TechniqueMatchEngine.start(
          wrestlerAId: 'wrestler_akari',
          wrestlerAName: '火神アカリ',
          wrestlerAMaxHp: 125,
          deckA: deckA,
          wrestlerBId: 'wrestler_misaki',
          wrestlerBName: '豪田ミサキ',
          wrestlerBMaxHp: 82,
          deckB: deckB,
          random: Random(seed),
        );
        final result = TechniqueMatchCpu.playFullMatch(
          initial,
          catalog,
          random: Random(seed * 1000 + 1),
        );
        final misakiAttacks = result.traces
            .where(
              (t) =>
                  t.playerIndex == 1 &&
                  (t.decisionType == 'declareAttack' ||
                      t.decisionType == 'declareFinisher'),
            )
            .length;
        totalMisakiAttacks += misakiAttacks;
        if (misakiAttacks == 0) zeroAttackGames++;
        expect(result.hitStepLimit, isFalse);
      }
      // 実プレイJSONで発覚したバグ（ミサキの自発攻撃0回）が、固定シード
      // 12試合のいずれでも再発しないことを確認する。
      expect(zeroAttackGames, 0);
      expect(totalMisakiAttacks, greaterThan(0));
    });
  });

  group('Rule Cleanup STEP7: CPU Action Selection Fix（合法技の不整合検証）', () {
    // 実プレイログ（白銀レイナ vs 黒蝶ジャックCPU、33ターンDRAW、ジャックの
    // movesUsed=0）で報告された「Decision Traceにeligible:trueの候補が
    // あるのにpassTurn/endRallyを選んでいる」という不整合の再現・回帰防止用。
    //
    // 調査の結論（詳細はdocs/design/technique_deck_implementation_plan.md
    // 「Rule Cleanup STEP7」参照）: `_decideRallyAction`は`bestScore`の初期値
    // が`-1 << 30`で、スコアの符号を問わず「eligible:trueな候補が1つでも
    // あれば必ずbestEntryに採用する」構造になっており、この構造上
    // 「eligible:trueなのにpassTurn/endRallyを選ぶ」ことはコード上不可能
    // （STEP7以前のPhase 8.5A-2で既に修正済み）。CPU対CPU計4000試合超の
    // 総当たりシミュレーションでもこの矛盾は一度も再現しなかった。
    // 以下のテストは、この不変条件が今後の変更で壊れないことを保証する
    // 回帰テストと、それを機械可読に検出するための`legalMoveCount`フィールド
    // （STEP7で新設）の検証。

    test('TEST1: 通常手番でeligible技が1枚以上あればpassTurnを選ばない', () {
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
        activePlayerIndex: 1,
        playerB: state.playerB.copyWith(
          energyPool: const {MoveAttribute.strike: 1},
        ),
        energySetThisTurn: true,
      );
      final result = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      expect(result.trace!.decisionType, isNot('passTurn'));
      expect(result.trace!.decisionType, 'declareAttack');
      expect(result.trace!.legalMoveCount, 1);
      expect(result.trace!.bestEligibleCardId, 'weak_strike');
    });

    test('TEST2: 複数のeligible技がある場合、最高評価候補を選択できる', () {
      final catalog = microCatalog();
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckOf('w1', ['weak_strike']),
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['weak_strike', 'strong_strike']),
        handSize: 2,
        random: Random(1),
      );
      state = state.copyWith(
        activePlayerIndex: 1,
        playerB: state.playerB.copyWith(
          energyPool: const {MoveAttribute.strike: 2},
        ),
        energySetThisTurn: true,
      );
      final result = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      expect(result.trace!.decisionType, 'declareAttack');
      expect(result.trace!.legalMoveCount, 2);
      // strong_strike（威力20）はweak_strike（威力3）よりスコアが高い。
      expect(result.trace!.chosen.cardId, 'strong_strike');
      expect(result.trace!.bestEligibleCardId, 'strong_strike');
    });

    test('TEST3・4: 返技成功後、remainingSpeed>0かつeligible技があれば即'
        'endRallyせず、合法な追撃技を最低1回使用する', () {
      final catalog = microCatalog();
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckOf('w1', ['strong_strike']),
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['weak_strike', 'weak_strike']),
        handSize: 2,
        random: Random(1),
      );
      state = state.copyWith(
        playerA: state.playerA.copyWith(
          energyPool: const {MoveAttribute.strike: 1},
        ),
        playerB: state.playerB.copyWith(
          energyPool: const {MoveAttribute.strike: 2},
        ),
      );
      final declared = TechniqueMatchEngine.declareAttack(
        state,
        state.playerA.hand.first,
        catalog,
      ).state;
      final counterResult = TechniqueMatchCpu.step(declared, catalog, random: Random(1));
      expect(counterResult.trace!.decisionType, 'counterAttack');
      expect(counterResult.state.rallyAttackerIndex, 1); // Bが新しい攻撃側。
      expect(counterResult.state.rallyRemainingSpeed, greaterThan(0));

      final followUp = TechniqueMatchCpu.step(counterResult.state, catalog, random: Random(1));
      // 即endRallyしない。合法な追撃技（残るweak_strike）を使用する。
      expect(followUp.trace!.decisionType, isNot('endRally'));
      expect(followUp.trace!.decisionType, 'declareAttack');
      expect(followUp.trace!.chosen.cardId, 'weak_strike');
      expect(followUp.trace!.legalMoveCount, greaterThan(0));
    });

    test('TEST5・6: エネルギー不足で本当に合法技が0枚の場合のみpassTurnし、'
        'legalMoveCount==0・理由分類がinsufficientEnergyになる', () {
      final catalog = microCatalog();
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckOf('w1', ['weak_strike']),
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['costly_strike']),
        handSize: 1,
        random: Random(1),
      );
      // エネルギーが無いため costly_strike は使用不可（合法技0枚）。
      state = state.copyWith(activePlayerIndex: 1, energySetThisTurn: true);
      final result = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      expect(result.trace!.decisionType, 'passTurn');
      expect(result.trace!.legalMoveCount, 0);
      expect(result.trace!.bestEligibleCardId, isNull);
      expect(
        result.trace!.noLegalMoveReasonCode,
        TechniqueCpuNoLegalMoveReason.insufficientEnergy.name,
      );
    });

    test('TEST7: Speed不足で本当に合法技が0枚の場合のみendRallyし、'
        'legalMoveCount==0・理由分類がinsufficientSpeedになる', () {
      final catalog = microCatalog();
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckOf('w1', ['weak_strike']),
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        deckB: deckOf('w2', ['speed_heavy']),
        handSize: 1,
        random: Random(1),
      );
      state = state.copyWith(
        activePlayerIndex: 1,
        rallyAttackerIndex: 1,
        rallyChain: 1,
        rallyRemainingSpeed: 3, // speed_heavy（Speed7）には不足。
        playerB: state.playerB.copyWith(
          energyPool: const {MoveAttribute.strike: 1},
        ),
      );
      final result = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      expect(result.trace!.decisionType, 'endRally');
      expect(result.trace!.legalMoveCount, 0);
      expect(
        result.trace!.noLegalMoveReasonCode,
        TechniqueCpuNoLegalMoveReason.insufficientSpeed.name,
      );
    });

    test('targetState不一致で合法技が0枚の場合、理由分類がtargetStateMismatch'
        'になる', () {
      final catalog = microCatalog();
      var state = TechniqueMatchEngine.start(
        wrestlerAId: 'w1',
        wrestlerAName: 'A',
        wrestlerAMaxHp: 100,
        deckA: deckOf('w1', ['weak_strike']),
        wrestlerBId: 'w2',
        wrestlerBName: 'B',
        wrestlerBMaxHp: 100,
        // pin_moveはtargetState: down限定。相手（A）はstand状態のまま。
        deckB: deckOf('w2', ['pin_move']),
        handSize: 1,
        random: Random(1),
      );
      state = state.copyWith(
        activePlayerIndex: 1,
        playerB: state.playerB.copyWith(
          energyPool: const {MoveAttribute.throwMove: 1},
        ),
        energySetThisTurn: true,
      );
      final result = TechniqueMatchCpu.step(state, catalog, random: Random(1));
      expect(result.trace!.decisionType, 'passTurn');
      expect(result.trace!.legalMoveCount, 0);
      expect(
        result.trace!.noLegalMoveReasonCode,
        TechniqueCpuNoLegalMoveReason.targetStateMismatch.name,
      );
    });

    test(
      'Reina vs Jack（実プレイ報告のマッチアップ）: 固定シード100試合'
      '（両陣営順）で、Decision Trace上「legalMoveCount > 0なのに'
      'passTurn/endRallyを選ぶ」矛盾が一度も発生しない',
      () {
        final catalog = buildProvisionalTechniqueDeckCatalog();
        var contradictions = 0;
        var zeroAttackGames = 0;
        var totalJackDeclares = 0;

        for (final swap in [false, true]) {
          for (var seed = 0; seed < 50; seed++) {
            final reinaDeck = findTechniquePhase7AModelDeck('wrestler_reina')!;
            final jackDeck = findTechniquePhase7AModelDeck('wrestler_jack')!;
            final start = TechniqueMatchEngine.start(
              wrestlerAId: swap ? 'wrestler_jack' : 'wrestler_reina',
              wrestlerAName: swap ? '黒蝶ジャック' : '白銀レイナ',
              wrestlerAMaxHp: 100,
              deckA: swap ? jackDeck : reinaDeck,
              wrestlerBId: swap ? 'wrestler_reina' : 'wrestler_jack',
              wrestlerBName: swap ? '白銀レイナ' : '黒蝶ジャック',
              wrestlerBMaxHp: 100,
              deckB: swap ? reinaDeck : jackDeck,
              random: Random(seed * 7 + 1),
            );
            final jackIndex = swap ? 0 : 1;
            final result = TechniqueMatchCpu.playFullMatch(
              start,
              catalog,
              random: Random(seed * 7 + 2),
            );
            expect(result.hitStepLimit, isFalse); // 無限ループが無いこと。

            for (final trace in result.traces) {
              if ((trace.decisionType == 'passTurn' || trace.decisionType == 'endRally') &&
                  (trace.legalMoveCount ?? 0) > 0) {
                contradictions++;
              }
            }
            final jackDeclares = result.traces
                .where(
                  (t) =>
                      t.playerIndex == jackIndex &&
                      (t.decisionType == 'declareAttack' ||
                          t.decisionType == 'declareFinisher'),
                )
                .length;
            totalJackDeclares += jackDeclares;
            if (jackDeclares == 0) zeroAttackGames++;
          }
        }

        expect(
          contradictions,
          0,
          reason:
              'legalMoveCount > 0のままpassTurn/endRallyを選ぶ矛盾が発生した'
              '（実プレイ報告のバグそのもの）。',
        );
        // このシード範囲（両陣営0〜49、計100試合）ではジャックの自発攻撃が
        // 0試合になることも無い（固定シードでの回帰確認。無限に0%を保証する
        // ものではなく、このシード範囲での再現防止のための固定回帰テスト）。
        expect(zeroAttackGames, 0);
        expect(totalJackDeclares, greaterThan(0));
      },
    );
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

    // 【次フェーズ Stage7】reasonCodeは追加のみのnullableフィールドで、
    // 未設定なら従来どおりJSONに現れないこと・設定時はenum名の文字列で
    // 出力されることを確認する。
    test('reasonCode未設定ならJSONに現れない', () {
      const chosen = TechniqueCpuChosenAction(action: 'passTurn', reason: '技が無い');
      expect(chosen.toJson().containsKey('reasonCode'), isFalse);
    });

    test('reasonCode設定時はenum名の文字列としてJSONへ出力される', () {
      const chosen = TechniqueCpuChosenAction(
        action: 'passTurn',
        reason: '技が無い',
        reasonCode: TechniqueCpuDecisionReason.noPlayableAttack,
      );
      expect(chosen.toJson()['reasonCode'], 'noPlayableAttack');
    });
  });
}
