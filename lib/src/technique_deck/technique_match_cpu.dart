import 'dart:math';

import '../wrestler_editor/models.dart' show MoveAttribute, moveAttributeLabel;
import 'technique_cpu_decision_trace.dart';
import 'technique_deck_deck.dart' show TechniqueDeckEntry;
import 'technique_deck_models.dart';
import 'technique_match_state.dart';

/// Technique Match用CPU（優先度6、Phase 8の最初の実装ラウンド）。
///
/// docs/design/technique_deck_cpu_design.md の設計方針に沿って実装した。
/// - `TechniqueMatchEngine`は一切変更しない。CPUはエンジンの外側から、
///   既存の判定のみを行う公開API（`canDeclareAttack`等）を読み取り専用で
///   使い、最終的にどのエンジンメソッドを呼ぶかを選ぶだけの薄い層とする。
/// - **相手の手札を直接参照しない**（フェアネス。プレイヤーと同じ情報
///   [自分の手札・双方の公開情報（HP/HEAT/状態/山札残数/捨て札/除外札）]
///   のみで判断する）。
/// - 各意思決定ポイントで[TechniqueCpuDecisionTrace]を生成する。
///
/// 【本ラウンドの実装レベル】ユーザー指示により、まずは単一レベル
/// （[TechniqueCpuLevel.normal]）のみを実装する。docs/design/
/// technique_deck_cpu_design.mdのLevel1〜3の3段階構成はPhase 8の将来
/// ラウンドで扱う（本ファイルはその土台として、レベルをenumで持たせる
/// 構造にはしてある）。
enum TechniqueCpuLevel { normal }

/// [TechniqueMatchCpu.step]の戻り値。1回の意思決定の結果、新しい状態と
/// その思考ログを返す。`trace`は試合が既に終了している等、何も判断する
/// 必要が無かった場合はnull。
class TechniqueCpuStepResult {
  const TechniqueCpuStepResult({required this.state, this.trace});

  final TechniqueMatchState state;
  final TechniqueCpuDecisionTrace? trace;
}

/// [TechniqueMatchCpu.playFullMatch]の戻り値。
class TechniqueCpuMatchResult {
  const TechniqueCpuMatchResult({
    required this.state,
    required this.traces,
    required this.stepCount,
    required this.hitStepLimit,
  });

  final TechniqueMatchState state;
  final List<TechniqueCpuDecisionTrace> traces;
  final int stepCount;

  /// 安全装置（[TechniqueMatchCpu.defaultMaxSteps]）に達して強制終了した
  /// 場合はtrue。CPU対CPUシミュレーションの「無限ループなし」の検証に使う。
  final bool hitStepLimit;
}

class TechniqueMatchCpu {
  const TechniqueMatchCpu._();

  /// 1試合が異常に長引いた場合の安全装置（無限ループ防止）。
  /// 通常の試合は数十〜百数十ステップ程度で決着する想定。
  static const int defaultMaxSteps = 2000;

  // ============================================================
  // 1手分の意思決定
  // ============================================================

  /// 現在の状態を見て、CPUとして次に取るべき行動を1つ決定し、適用した
  /// 新しい状態を返す。試合が終了している場合は何もしない
  /// （`trace: null`）。
  static TechniqueCpuStepResult step(
    TechniqueMatchState state,
    TechniqueDeckCardCatalog catalog, {
    TechniqueCpuLevel level = TechniqueCpuLevel.normal,
    Random? random,
  }) {
    if (state.isOver) {
      return TechniqueCpuStepResult(state: state);
    }
    final rng = random ?? Random();

    final pendingFinisher = state.pendingFinisher;
    if (pendingFinisher != null) {
      return _settled(
        pendingFinisher.stage == TechniqueFinisherStage.responsePending
            ? _decideCancelFinisher(state, catalog, level, rng)
            : _decideFinisherEscape(state, catalog, level, rng),
        rng,
      );
    }
    if (state.pendingEscape != null) {
      return _settled(_decideEscape(state, catalog, level, rng), rng);
    }
    if (state.pendingAttack != null) {
      return _settled(_decideCounter(state, catalog, level, rng), rng);
    }
    if (state.isRallyActive) {
      // _decideRallyAction自身が「有効技なし」の枝で既にautoAdvanceTurn
      // IfSettledまで完了させる場合があるため、二重にターンを進めてしまわ
      // ないよう、settle処理は_decideRallyAction内部で枝ごとに個別に行う
      // （ここではラップしない）。
      return _decideRallyAction(state, catalog, level, rng, isFreshTurn: false);
    }
    if (!state.energySetThisTurn) {
      final energyDecision = _decideEnergy(state, catalog, level, rng);
      // 【ゲームサイクル整理ラウンド 優先度1】エネルギーセット直後は
      // 絶対にターンを進めてはならない（技の使用はこの後に続く別ステップ）。
      // そのためここだけは_settled()を経由させない。
      if (energyDecision != null) return energyDecision;
    }
    return _decideRallyAction(state, catalog, level, rng, isFreshTurn: true);
  }

  /// 【Phase 8.5A】技の使用（ラリー・返技・決着判定を含む）が完全に完結する
  /// か、使用可能な技が尽きるまでは、CPUの意思決定にもターンを進めない
  /// 方針を一律で適用する。[TechniqueMatchEngine.autoAdvanceTurnIfSettled]は
  /// ラリー継続中・判定待ちの間は何もしない（内部でガードする）ため安全に
  /// 呼べるが、**既にそのものが`endTurn`を実行済みの結果には絶対に二重適用
  /// してはならない**（ターンが2回分進んでしまう）。そのため呼び出し側は、
  /// まだターンを終える処理を行っていない結果に対してのみこれを呼ぶこと。
  static TechniqueCpuStepResult _settled(TechniqueCpuStepResult result, Random rng) =>
      TechniqueCpuStepResult(
        state: TechniqueMatchEngine.autoAdvanceTurnIfSettled(result.state, random: rng),
        trace: result.trace,
      );

  /// 決着（[TechniqueMatchState.isOver]）まで[step]を繰り返す。
  /// CPU対CPUシミュレーション用。[defaultMaxSteps]に達した場合は打ち切り、
  /// [TechniqueCpuMatchResult.hitStepLimit]をtrueにして返す（無限ループの
  /// 検出・防止）。
  static TechniqueCpuMatchResult playFullMatch(
    TechniqueMatchState initialState,
    TechniqueDeckCardCatalog catalog, {
    TechniqueCpuLevel levelA = TechniqueCpuLevel.normal,
    TechniqueCpuLevel levelB = TechniqueCpuLevel.normal,
    Random? random,
    int maxSteps = defaultMaxSteps,
  }) {
    final rng = random ?? Random();
    var state = initialState;
    final traces = <TechniqueCpuDecisionTrace>[];
    var steps = 0;
    while (!state.isOver && steps < maxSteps) {
      final actingIndex = actingPlayerIndex(state);
      final level = actingIndex == 0 ? levelA : levelB;
      final result = step(state, catalog, level: level, random: rng);
      state = result.state;
      if (result.trace != null) traces.add(result.trace!);
      steps++;
      if (identical(result.state, state) && result.trace == null && !state.isOver) {
        // 意思決定が何も行われず状態も変化しなかった場合、無限ループを
        // 避けるためここで打ち切る（本来到達しない防御的分岐）。
        break;
      }
    }
    return TechniqueCpuMatchResult(
      state: state,
      traces: traces,
      stepCount: steps,
      hitStepLimit: !state.isOver && steps >= maxSteps,
    );
  }

  /// 現在、行動する必要があるプレイヤーのインデックス（0=A, 1=B）。
  /// 保留中の判定がある場合はその防御側、ラリー中はラリー攻撃側、
  /// それ以外は`activePlayerIndex`。
  ///
  /// 【ゲームサイクル整理ラウンド 優先度7】`TechniqueMatchScreen`がCPU対戦
  /// 統合のため、「次に行動すべきなのは人間かCPUか」を判定する目的で公開
  /// メソッドへ変更した（元は`playFullMatch`専用の内部ヘルパーだった）。
  static int actingPlayerIndex(TechniqueMatchState state) {
    final pendingFinisher = state.pendingFinisher;
    if (pendingFinisher != null) return pendingFinisher.defenderIndex;
    final pendingEscape = state.pendingEscape;
    if (pendingEscape != null) return pendingEscape.defenderIndex;
    final pendingAttack = state.pendingAttack;
    if (pendingAttack != null) return 1 - pendingAttack.attackerIndex;
    if (state.isRallyActive) return state.rallyAttackerIndex!;
    return state.activePlayerIndex;
  }

  // ============================================================
  // ① エネルギーセット
  // ============================================================

  static TechniqueCpuStepResult? _decideEnergy(
    TechniqueMatchState state,
    TechniqueDeckCardCatalog catalog,
    TechniqueCpuLevel level,
    Random rng,
  ) {
    final playerIndex = state.activePlayerIndex;
    final self = state.active;
    final energyEntries = self.hand
        .where((e) => catalog.findEnergyById(e.cardId) != null)
        .toList();
    if (energyEntries.isEmpty) return null;

    // 手札の技カードが要求する属性ごとの不足量（要求-既存保有）を集計し、
    // 最も不足している属性のエネルギーを優先してセットする。
    final demand = <MoveAttribute, int>{};
    for (final e in self.hand) {
      final technique = catalog.findTechniqueById(e.cardId);
      if (technique == null) continue;
      for (final cost in technique.attackEnergyCost.entries) {
        if (cost.value <= 0) continue;
        demand[cost.key] = (demand[cost.key] ?? 0) + cost.value;
      }
    }
    for (final attribute in MoveAttribute.values) {
      final have = self.availableEnergyFor(attribute);
      if (demand.containsKey(attribute)) {
        demand[attribute] = ((demand[attribute] ?? 0) - have).clamp(0, 999);
      }
    }

    TechniqueDeckEntry? chosen;
    var bestDemand = -1;
    final candidates = <TechniqueCpuCandidate>[];
    for (final entry in energyEntries) {
      final energy = catalog.findEnergyById(entry.cardId)!;
      final d = demand[energy.attribute] ?? 0;
      candidates.add(
        TechniqueCpuCandidate(
          cardId: entry.cardId,
          cardName: energy.name,
          eligible: true,
          score: d,
          factors: [
            TechniqueCpuScoreFactor(
              label: '${moveAttributeLabel(energy.attribute)}の技カード不足量',
              delta: d,
            ),
          ],
        ),
      );
      if (d > bestDemand) {
        bestDemand = d;
        chosen = entry;
      }
    }
    chosen ??= energyEntries.first;
    final chosenCard = catalog.findEnergyById(chosen.cardId)!;

    final result = TechniqueMatchEngine.setEnergy(state, chosen, catalog);
    final trace = TechniqueCpuDecisionTrace(
      turnNumber: state.turnNumber,
      playerIndex: playerIndex,
      cpuLevel: level.name,
      decisionType: 'setEnergy',
      candidates: candidates,
      chosen: TechniqueCpuChosenAction(
        action: 'setEnergy',
        cardId: chosen.cardId,
        cardName: chosenCard.name,
        reason: bestDemand > 0
            ? '手札の技が最も必要としている属性（${moveAttributeLabel(chosenCard.attribute)}）を優先してセットした'
            : '手札の技の不足属性が無いため、最初のエネルギーカードをセットした',
      ),
    );
    return TechniqueCpuStepResult(state: result.state, trace: trace);
  }

  // ============================================================
  // ② 技を使用する／③ 休息する／ターン終了する（＋ラリー継続判断）
  // ============================================================

  /// 手札の技カード（フィニッシャー含む）を評価し、最良のものを宣言する。
  /// 十分なスコアの技が無ければ、フレッシュターンなら休息／ターン終了、
  /// ラリー中ならラリーを終了する。
  static TechniqueCpuStepResult _decideRallyAction(
    TechniqueMatchState state,
    TechniqueDeckCardCatalog catalog,
    TechniqueCpuLevel level,
    Random rng, {
    required bool isFreshTurn,
  }) {
    final attackerIndex = state.rallyAttackerIndex ?? state.activePlayerIndex;
    final attacker = state.playerAt(attackerIndex);
    final defender = state.playerAt(1 - attackerIndex);
    final recentNames = _recentOwnMoveNames(state, attackerIndex);

    final candidates = <TechniqueCpuCandidate>[];
    TechniqueDeckEntry? bestEntry;
    TechniqueDeckTechniqueCard? bestCard;
    var bestScore = -1 << 30;

    for (final entry in attacker.hand) {
      final card = catalog.findTechniqueById(entry.cardId);
      if (card == null) continue; // エネルギー・防御カードは対象外
      bool eligible;
      String? reason;
      if (card.hasFinisherEffect) {
        final check = TechniqueMatchEngine.canDeclareFinisher(state, entry, catalog);
        eligible = check.canDeclare;
        reason = check.reason;
      } else {
        final check = TechniqueMatchEngine.canDeclareAttack(state, entry, catalog);
        eligible = check.canUse;
        reason = check.reason;
      }
      if (!eligible) {
        candidates.add(
          TechniqueCpuCandidate(
            cardId: entry.cardId,
            cardName: card.name,
            eligible: false,
            score: 0,
            ineligibleReason: reason,
          ),
        );
        continue;
      }
      final (score, factors) = _scoreTechnique(
        card: card,
        self: attacker,
        opponent: defender,
        catalog: catalog,
        recentOwnMoveNames: recentNames,
      );
      candidates.add(
        TechniqueCpuCandidate(
          cardId: entry.cardId,
          cardName: card.name,
          eligible: true,
          score: score,
          factors: factors,
        ),
      );
      if (score > bestScore) {
        bestScore = score;
        bestEntry = entry;
        bestCard = card;
      }
    }

    // 攻撃するかどうかは「スコアが正か」ではなく「有効な技が他に無いか」
    // で決める。同じ技しか手札に無い場合など、多様性ペナルティ等の
    // ソフトな減点だけでスコアが0以下になることがあり、絶対しきい値で
    // 判定すると「唯一の選択肢なのに何もしない」まま手番を空費し続ける
    // （山札・捨て札が両方尽きて手番だけが進む）不具合になるため。
    // 低HP時の撤退（休息優先）だけは例外的に扱う。
    final hpRatio = attacker.maxHp == 0 ? 1.0 : attacker.hp / attacker.maxHp;
    const decisiveScoreThreshold = 15;
    final shouldRetreat = isFreshTurn &&
        attacker.posture == WrestlerPosture.stand &&
        attacker.hp < attacker.maxHp &&
        hpRatio <= 0.4 &&
        (bestEntry == null || bestScore < decisiveScoreThreshold);

    if (bestEntry != null && bestCard != null && !shouldRetreat) {
      final rejected = candidates
          .where((c) => c.eligible && c.cardId != bestEntry!.cardId)
          .map(
            (c) => TechniqueCpuRejectedCandidate(
              cardId: c.cardId,
              reason: 'スコア${c.score}点（採用技より低い）',
            ),
          )
          .toList();
      final isFinisher = bestCard.hasFinisherEffect;
      final result = isFinisher
          ? TechniqueMatchEngine.declareFinisher(state, bestEntry, catalog)
          : TechniqueMatchEngine.declareAttack(state, bestEntry, catalog);
      final trace = TechniqueCpuDecisionTrace(
        turnNumber: state.turnNumber,
        playerIndex: attackerIndex,
        cpuLevel: level.name,
        decisionType: isFinisher ? 'declareFinisher' : 'declareAttack',
        candidates: candidates,
        chosen: TechniqueCpuChosenAction(
          action: isFinisher ? 'declareFinisher' : 'declareAttack',
          cardId: bestEntry.cardId,
          cardName: bestCard.name,
          reason: 'スコア$bestScore点で最も評価が高い技を選択した',
        ),
        rejected: rejected,
      );
      return TechniqueCpuStepResult(state: result.state, trace: trace);
    }

    // 十分なスコアの技が無い。
    if (!isFreshTurn) {
      // ラリー中: 追撃せずラリーを終了する。【優先度1】返技によってラリーが
      // 終了した場合もそのターンを終了する仕様のため、endRally自体は
      // ターンを終えないので、ここでautoAdvanceTurnIfSettledを適用する。
      final newState = TechniqueMatchEngine.autoAdvanceTurnIfSettled(
        TechniqueMatchEngine.endRally(state),
        random: rng,
      );
      final trace = TechniqueCpuDecisionTrace(
        turnNumber: state.turnNumber,
        playerIndex: attackerIndex,
        cpuLevel: level.name,
        decisionType: 'endRally',
        candidates: candidates,
        chosen: const TechniqueCpuChosenAction(
          action: 'endRally',
          reason: '追撃に値するスコアの技が無いためラリーを終了した',
        ),
      );
      return TechniqueCpuStepResult(state: newState, trace: trace);
    }

    // 【Phase 8.5A】休息システムの廃止に伴い、フレッシュターン開始時に
    // 使用可能な技が1枚も無い場合は、無言でターンを自動終了する
    // （Phase 8.2以前に存在した独立の「ターン終了」ボタンの復活ではなく、
    // 他に取れる行動が無い場合限定の自動処理。ユーザー確認済み）。
    final passed = TechniqueMatchEngine.autoAdvanceTurnIfSettled(
      state,
      random: rng,
    );
    final trace = TechniqueCpuDecisionTrace(
      turnNumber: state.turnNumber,
      playerIndex: attackerIndex,
      cpuLevel: level.name,
      decisionType: 'passTurn',
      candidates: candidates,
      chosen: const TechniqueCpuChosenAction(
        action: 'passTurn',
        reason: '使用可能な技が無いためターンを自動終了した',
      ),
    );
    return TechniqueCpuStepResult(state: passed, trace: trace);
  }

  /// 技カード1枚のスコアを算出する。単純な威力最大は禁止（ユーザー指示）で、
  /// ダメージ・エネルギー効率・ダウン付与・ダウン限定技への連携・
  /// フォール／ギブアップ／フィニッシャーへの寄与・技の多様性・返技用
  /// エネルギーの温存を総合評価する。
  static (int, List<TechniqueCpuScoreFactor>) _scoreTechnique({
    required TechniqueDeckTechniqueCard card,
    required TechniqueMatchPlayerState self,
    required TechniqueMatchPlayerState opponent,
    required TechniqueDeckCardCatalog catalog,
    required List<String> recentOwnMoveNames,
  }) {
    final factors = <TechniqueCpuScoreFactor>[];
    var score = 0;

    void add(String label, int delta) {
      if (delta == 0) return;
      factors.add(TechniqueCpuScoreFactor(label: label, delta: delta));
      score += delta;
    }

    // ダメージ（基礎威力）。
    add('基礎威力', card.power);

    // ダウン中ボーナス威力（既存フィールドdownBonusPowerも加味）。
    final opponentDownLike = opponent.posture != WrestlerPosture.stand;
    if (card.downBonusPower != null && opponentDownLike) {
      add('ダウン中ボーナス威力', card.downBonusPower!);
    }

    // エネルギー効率: コストが高いほど減点（同威力ならコストが低い技を優先）。
    final totalCost = card.attackEnergyCost.values.fold<int>(0, (a, b) => a + b);
    if (totalCost > 0) add('エネルギーコスト', -(totalCost * 2));

    // ダウンさせられる。
    final causesNewDown = card.causesDown && !opponentDownLike;
    if (causesNewDown) {
      add('相手をダウンさせられる', 8);
      // ダウン限定技へ繋がる: ダウンを取った後に使えるダウン限定技が
      // 手札にあれば、連携としてさらに加点する。
      final hasDownFollowUp = self.hand.any((e) {
        final t = catalog.findTechniqueById(e.cardId);
        return t != null &&
            t.id != card.id &&
            t.targetState == TechniqueTargetState.down;
      });
      if (hasDownFollowUp) add('ダウン限定技への連携', 6);
    }

    // フォール／ギブアップへ繋がる。
    if (card.hasPinEffect) add('フォール効果', 10);
    if (card.hasSubmissionEffect) add('ギブアップ効果', 10);

    // フィニッシャー。
    if (card.hasFinisherEffect) {
      add('フィニッシャー', 25);
    } else {
      // フィニッシャー条件へ近づく: 手札にHEAT条件付きフィニッシャーが
      // あり、現在HEATが不足しているなら、HEAT獲得量に応じて加点する。
      final needsMoreHeat = self.hand.any((e) {
        final t = catalog.findTechniqueById(e.cardId);
        if (t == null || !t.hasFinisherEffect) return false;
        final minimumHeat = t.finisherRequirements['minimumHeat'];
        return minimumHeat is num && minimumHeat > self.heat;
      });
      if (needsMoreHeat && card.heatDelta > 0) {
        add('フィニッシャーHEAT条件へ接近', (card.heatDelta / 2).round());
      }
    }

    // 同じ技ばかり使わない。
    if (recentOwnMoveNames.contains(card.name)) {
      add('連続使用ペナルティ', -12);
    }

    // 返技用エネルギーを残す: このカードの使用で該当属性のエネルギーが
    // 枯渇するなら減点（返技の余地を残すことを優先する）。
    for (final entry in card.attackEnergyCost.entries) {
      if (entry.value <= 0) continue;
      final remainingAfter = self.availableEnergyFor(entry.key) - entry.value;
      if (remainingAfter <= 0) {
        add('${moveAttributeLabel(entry.key)}返技エネルギーの枯渇', -6);
      }
    }

    return (score, factors);
  }

  /// 直近、このプレイヤーが使用／宣言した技名を新しい順に返す（試合ログを
  /// 走査するのみで、自前の状態を持たない。ログはエンジンが常に生成する
  /// 公開情報のため、フェアネス上の問題は無い）。
  static List<String> _recentOwnMoveNames(
    TechniqueMatchState state,
    int playerIndex, {
    int count = 2,
  }) {
    final name = state.playerAt(playerIndex).wrestlerName;
    final pattern = RegExp('${RegExp.escape(name)}が「(.+?)」を(?:使用した|宣言した)');
    final names = <String>[];
    for (final line in state.log.reversed) {
      final match = pattern.firstMatch(line);
      if (match == null) continue;
      final cardName = match.group(1)!;
      if (!names.contains(cardName)) names.add(cardName);
      if (names.length >= count) break;
    }
    return names;
  }

  // ============================================================
  // ④ 返技するか（防御側）
  // ============================================================

  static TechniqueCpuStepResult _decideCounter(
    TechniqueMatchState state,
    TechniqueDeckCardCatalog catalog,
    TechniqueCpuLevel level,
    Random rng,
  ) {
    final pending = state.pendingAttack!;
    final defenderIndex = 1 - pending.attackerIndex;
    final defender = state.playerAt(defenderIndex);
    final card = catalog.findTechniqueById(pending.cardId);
    final check = TechniqueMatchEngine.checkCounterEligibility(state, catalog);

    var threat = 0;
    final factors = <TechniqueCpuScoreFactor>[];
    void add(String label, int delta) {
      factors.add(TechniqueCpuScoreFactor(label: label, delta: delta));
      threat += delta;
    }

    if (card != null) {
      add('相手の技の威力', card.power);
      if (card.causesDown) add('成立するとダウンさせられる', 10);
      if (card.hasPinEffect) add('フォール効果あり', 15);
      if (card.hasSubmissionEffect) add('ギブアップ効果あり', 15);
    }

    // 【ゲームサイクル整理ラウンド 優先度2】返技には手札の返技候補カードが
    // 必要になった。候補の中から「返技すると自分のエネルギーが枯渇しない
    // カード」を優先して選ぶ（返技用エネルギーを残す、という既存方針の延長）。
    final candidates = TechniqueMatchEngine.counterCandidates(state, catalog);
    TechniqueDeckEntry? chosenEntry;
    if (candidates.isNotEmpty) {
      chosenEntry = candidates.reduce((a, b) {
        final cardA = catalog.findTechniqueById(a.cardId)!;
        final cardB = catalog.findTechniqueById(b.cardId)!;
        final depleteA = cardA.reversalEnergyCost.entries.any(
          (e) => e.value > 0 && defender.availableEnergyFor(e.key) - e.value <= 0,
        );
        final depleteB = cardB.reversalEnergyCost.entries.any(
          (e) => e.value > 0 && defender.availableEnergyFor(e.key) - e.value <= 0,
        );
        if (depleteA == depleteB) return a;
        return depleteA ? b : a;
      });
      final chosenCard = catalog.findTechniqueById(chosenEntry.cardId)!;
      final willDeplete = chosenCard.reversalEnergyCost.entries.any(
        (e) => e.value > 0 && defender.availableEnergyFor(e.key) - e.value <= 0,
      );
      if (willDeplete) add('返技すると当該エネルギーが枯渇する', -8);
    }

    const threshold = 15;
    final counterEntry = chosenEntry;

    if (check.canCounter && counterEntry != null && threat >= threshold) {
      final result = TechniqueMatchEngine.counterAttack(state, counterEntry, catalog);
      final counterCardName =
          catalog.findTechniqueById(counterEntry.cardId)?.name ?? counterEntry.cardId;
      final trace = TechniqueCpuDecisionTrace(
        turnNumber: state.turnNumber,
        playerIndex: defenderIndex,
        cpuLevel: level.name,
        decisionType: 'counterAttack',
        candidates: [
          TechniqueCpuCandidate(
            cardId: pending.cardId,
            cardName: card?.name ?? pending.cardId,
            eligible: true,
            score: threat,
            factors: factors,
          ),
        ],
        chosen: TechniqueCpuChosenAction(
          action: 'counterAttack',
          cardId: counterEntry.cardId,
          cardName: counterCardName,
          reason: '脅威スコア$threat点（閾値$threshold）が高いため'
              '「$counterCardName」で返技した',
        ),
      );
      return TechniqueCpuStepResult(state: result.state, trace: trace);
    }

    // 返技しない（受ける）。resolveHitの結果、pendingEscapeが発生する
    // 場合があるが、その判断は次のstep()呼び出しで行う。
    final resolved = TechniqueMatchEngine.resolveHit(state, catalog);
    final trace = TechniqueCpuDecisionTrace(
      turnNumber: state.turnNumber,
      playerIndex: defenderIndex,
      cpuLevel: level.name,
      decisionType: 'counterAttack',
      candidates: [
        if (card != null)
          TechniqueCpuCandidate(
            cardId: pending.cardId,
            cardName: card.name,
            eligible: check.canCounter,
            score: threat,
            factors: factors,
            ineligibleReason: check.canCounter ? null : check.reason,
          ),
      ],
      chosen: TechniqueCpuChosenAction(
        action: 'acceptHit',
        reason: !check.canCounter
            ? (check.reason ?? '返技できないため受けた')
            : '脅威スコア$threat点（閾値$threshold未満）のため返技せず受けた',
      ),
    );
    return TechniqueCpuStepResult(state: resolved, trace: trace);
  }

  // ============================================================
  // ⑤⑥ フォール／ギブアップ回避
  // ============================================================

  static TechniqueCpuStepResult _decideEscape(
    TechniqueMatchState state,
    TechniqueDeckCardCatalog catalog,
    TechniqueCpuLevel level,
    Random rng,
  ) {
    final pending = state.pendingEscape!;
    final defender = state.playerAt(pending.defenderIndex);
    final kindLabel = pending.kind == TechniqueEscapeKind.fall ? 'フォール' : 'ギブアップ';

    final defenseEntries = defender.hand
        .where(
          (e) => TechniqueMatchEngine.canEscapeWithDefenseCard(state, e, catalog).canEscape,
        )
        .toList();
    final hpCheck = TechniqueMatchEngine.canEscapeWithHp(state, catalog);

    final candidates = [
      for (final e in defenseEntries)
        TechniqueCpuCandidate(
          cardId: e.cardId,
          cardName: catalog.findDefenseCardById(e.cardId)?.name ?? e.cardId,
          eligible: true,
          score: 10,
          factors: const [TechniqueCpuScoreFactor(label: '専用防御カード', delta: 10)],
        ),
      TechniqueCpuCandidate(
        cardId: 'hp',
        cardName: 'HPを消費して耐える',
        eligible: hpCheck.canEscape,
        score: 5,
        ineligibleReason: hpCheck.canEscape ? null : hpCheck.reason,
      ),
    ];

    if (defenseEntries.isNotEmpty) {
      final chosen = defenseEntries.first;
      final result = TechniqueMatchEngine.escapeWithDefenseCard(state, chosen, catalog);
      final cardName = catalog.findDefenseCardById(chosen.cardId)?.name ?? chosen.cardId;
      return TechniqueCpuStepResult(
        state: result.state,
        trace: TechniqueCpuDecisionTrace(
          turnNumber: state.turnNumber,
          playerIndex: pending.defenderIndex,
          cpuLevel: level.name,
          decisionType: 'escapeChoice',
          candidates: candidates,
          chosen: TechniqueCpuChosenAction(
            action: 'escapeWithCard',
            cardId: chosen.cardId,
            cardName: cardName,
            reason: '$kindLabel回避用カードを保持していたため使用した',
          ),
        ),
      );
    }
    if (hpCheck.canEscape) {
      final result = TechniqueMatchEngine.escapeWithHp(state, catalog);
      return TechniqueCpuStepResult(
        state: result.state,
        trace: TechniqueCpuDecisionTrace(
          turnNumber: state.turnNumber,
          playerIndex: pending.defenderIndex,
          cpuLevel: level.name,
          decisionType: 'escapeChoice',
          candidates: candidates,
          chosen: const TechniqueCpuChosenAction(
            action: 'escapeWithHp',
            reason: '専用防御カードが無いためHPを消費して耐えた',
          ),
        ),
      );
    }
    final newState = TechniqueMatchEngine.concede(state);
    return TechniqueCpuStepResult(
      state: newState,
      trace: TechniqueCpuDecisionTrace(
        turnNumber: state.turnNumber,
        playerIndex: pending.defenderIndex,
        cpuLevel: level.name,
        decisionType: 'escapeChoice',
        candidates: candidates,
        chosen: const TechniqueCpuChosenAction(
          action: 'concede',
          reason: 'いずれの回避手段も使えないため諦めた',
        ),
      ),
    );
  }

  // ============================================================
  // ⑥ フィニッシャーのキャンセル（防御側）
  // ============================================================

  static TechniqueCpuStepResult _decideCancelFinisher(
    TechniqueMatchState state,
    TechniqueDeckCardCatalog catalog,
    TechniqueCpuLevel level,
    Random rng,
  ) {
    final pending = state.pendingFinisher!;
    final defender = state.playerAt(pending.defenderIndex);
    final cancelEntries = defender.hand
        .where(
          (e) => TechniqueMatchEngine.canCancelFinisher(state, e, catalog).canCancel,
        )
        .toList();

    final candidates = [
      for (final e in cancelEntries)
        TechniqueCpuCandidate(
          cardId: e.cardId,
          cardName: catalog.findDefenseCardById(e.cardId)?.name ?? e.cardId,
          eligible: true,
          score: 20,
          factors: const [
            TechniqueCpuScoreFactor(label: 'フィニッシャーは危険度が高い', delta: 20),
          ],
        ),
    ];

    if (cancelEntries.isNotEmpty) {
      final chosen = cancelEntries.first;
      final result = TechniqueMatchEngine.cancelFinisher(state, chosen, catalog);
      final cardName = catalog.findDefenseCardById(chosen.cardId)?.name ?? chosen.cardId;
      return TechniqueCpuStepResult(
        state: result.state,
        trace: TechniqueCpuDecisionTrace(
          turnNumber: state.turnNumber,
          playerIndex: pending.defenderIndex,
          cpuLevel: level.name,
          decisionType: 'cancelFinisher',
          candidates: candidates,
          chosen: TechniqueCpuChosenAction(
            action: 'cancelFinisher',
            cardId: chosen.cardId,
            cardName: cardName,
            reason: 'エスケープ／リバーサルカードでフィニッシャーの発動をキャンセルした',
          ),
        ),
      );
    }
    final resolved = TechniqueMatchEngine.resolveFinisher(state, catalog);
    return TechniqueCpuStepResult(
      state: resolved,
      trace: TechniqueCpuDecisionTrace(
        turnNumber: state.turnNumber,
        playerIndex: pending.defenderIndex,
        cpuLevel: level.name,
        decisionType: 'cancelFinisher',
        candidates: candidates,
        chosen: const TechniqueCpuChosenAction(
          action: 'acceptFinisher',
          reason: 'キャンセル可能なカードが無いため成立させた',
        ),
      ),
    );
  }

  // ============================================================
  // ⑦ フィニッシャーからの脱出（防御側）
  // ============================================================

  static TechniqueCpuStepResult _decideFinisherEscape(
    TechniqueMatchState state,
    TechniqueDeckCardCatalog catalog,
    TechniqueCpuLevel level,
    Random rng,
  ) {
    final pending = state.pendingFinisher!;
    final defender = state.playerAt(pending.defenderIndex);
    final escapeEntries = defender.hand
        .where(
          (e) => TechniqueMatchEngine.canEscapeFinisher(state, e, catalog).canEscape,
        )
        .toList();

    final candidates = [
      for (final e in escapeEntries)
        TechniqueCpuCandidate(
          cardId: e.cardId,
          cardName: catalog.findDefenseCardById(e.cardId)?.name ?? e.cardId,
          eligible: true,
          score: 30,
          factors: const [
            TechniqueCpuScoreFactor(label: '脱出できなければ即敗北', delta: 30),
          ],
        ),
    ];

    if (escapeEntries.isNotEmpty) {
      final chosen = escapeEntries.first;
      final result = TechniqueMatchEngine.escapeFinisher(state, chosen, catalog);
      final cardName = catalog.findDefenseCardById(chosen.cardId)?.name ?? chosen.cardId;
      return TechniqueCpuStepResult(
        state: result.state,
        trace: TechniqueCpuDecisionTrace(
          turnNumber: state.turnNumber,
          playerIndex: pending.defenderIndex,
          cpuLevel: level.name,
          decisionType: 'finisherEscapeChoice',
          candidates: candidates,
          chosen: TechniqueCpuChosenAction(
            action: 'escapeFinisherWithCard',
            cardId: chosen.cardId,
            cardName: cardName,
            reason: '特殊キックアウトカードで脱出した',
          ),
        ),
      );
    }
    final newState = TechniqueMatchEngine.concedeFinisher(state);
    return TechniqueCpuStepResult(
      state: newState,
      trace: TechniqueCpuDecisionTrace(
        turnNumber: state.turnNumber,
        playerIndex: pending.defenderIndex,
        cpuLevel: level.name,
        decisionType: 'finisherEscapeChoice',
        candidates: candidates,
        chosen: const TechniqueCpuChosenAction(
          action: 'concedeFinisher',
          reason: '特殊キックアウトカードが無く脱出できないため諦めた',
        ),
      ),
    );
  }
}
