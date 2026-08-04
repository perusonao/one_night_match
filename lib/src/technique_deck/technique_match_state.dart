import 'dart:math';

import '../wrestler_editor/models.dart' show MoveAttribute, moveAttributeLabel;
import 'technique_deck_deck.dart';
import 'technique_deck_models.dart';

/// Technique Deck Rules Phase 3〜4: 最小限の試合状態管理＋単発技の使用。
///
/// Phase 4で追加したのは「手札から通常技・固有技を1枚使用する」基本フロー
/// （エネルギー消費・ダメージ即時適用・HEAT即時反映・ダウン付与・捨て札化）
/// のみ。返技・連続攻撃・フォール／ギブアップ／フィニッシャーの決着処理・
/// CPUは実装しない（Phase 5以降）。既存の `LevelMatchEngine`
/// （classic/energy）とは完全に独立しており、一切の変更・依存を持たない。
///
/// 【ダメージ適用方式について】仕様書7.3章・open questions 1番は本来
/// Phase 5（連続攻撃）で正式決定する論点だが、Phase 4は単発技のみを扱うため
/// 即時適用と一括適用の結果に差が出ない。ここでは即時適用（技成立ごとに
/// HP・HEAT・ダウン状態を即座に反映）を「暫定ではなく現時点の有力候補」として
/// 採用した。理由: 技Aの成立で相手がダウンし、直後にダウン限定技Bが使用可能に
/// なる、という連携（`targetState`によるダウン限定技の判定）を成立させるには
/// 即時反映が必要なため。Phase 5で連続攻撃を実装する際、この方式を維持するか
/// 改めて検証する（open questions 1番）。

/// ターンの進行段階。
enum TechniqueMatchPhase { start, draw, energySet, end }

/// 1人のプレイヤー（レスラー）の試合内状態。
class TechniqueMatchPlayerState {
  const TechniqueMatchPlayerState({
    required this.wrestlerId,
    required this.wrestlerName,
    required this.maxHp,
    required this.hp,
    this.heat = 0,
    this.posture = WrestlerPosture.stand,
    this.recoveryPower = 0,
    this.level = 1,
    this.energyPool = const {},
    this.spentEnergy = const {},
    this.drawPile = const [],
    this.hand = const [],
    this.discardPile = const [],
  });

  final String wrestlerId;
  final String wrestlerName;
  final int maxHp;
  final int hp;
  final int heat;
  final WrestlerPosture posture;

  /// 休息時のHP回復量（[TechniqueDeckWrestlerProfile.recoveryPower] 由来。
  /// プロファイルが無い場合の暫定値は呼び出し側で決める）。
  final int recoveryPower;

  /// レベル（`TechniqueDeckTechniqueCard.minimumLevel`の判定に使用）。
  /// Phase 4時点ではレベル変更アクションが未実装のため常に1で固定
  /// （open questions 12番、レベルシステムを維持するかは未決定）。
  final int level;

  /// セット済みの技エネルギー（属性別の総数、手札から出た時点で永続的に
  /// 加算される）。
  final Map<MoveAttribute, int> energyPool;

  /// 今サイクルで使用済みのエネルギー（属性別）。自分のターン開始時に
  /// 回復し0へ戻る（仕様書3.3章）。
  final Map<MoveAttribute, int> spentEnergy;

  final List<TechniqueDeckEntry> drawPile;
  final List<TechniqueDeckEntry> hand;
  final List<TechniqueDeckEntry> discardPile;

  /// 現在使用可能な（セット済みかつ未使用の）指定属性のエネルギー枚数。
  int availableEnergyFor(MoveAttribute attribute) =>
      (energyPool[attribute] ?? 0) - (spentEnergy[attribute] ?? 0);

  TechniqueMatchPlayerState copyWith({
    int? hp,
    int? heat,
    WrestlerPosture? posture,
    int? level,
    Map<MoveAttribute, int>? energyPool,
    Map<MoveAttribute, int>? spentEnergy,
    List<TechniqueDeckEntry>? drawPile,
    List<TechniqueDeckEntry>? hand,
    List<TechniqueDeckEntry>? discardPile,
  }) => TechniqueMatchPlayerState(
    wrestlerId: wrestlerId,
    wrestlerName: wrestlerName,
    maxHp: maxHp,
    hp: hp ?? this.hp,
    heat: heat ?? this.heat,
    posture: posture ?? this.posture,
    recoveryPower: recoveryPower,
    level: level ?? this.level,
    energyPool: energyPool ?? this.energyPool,
    spentEnergy: spentEnergy ?? this.spentEnergy,
    drawPile: drawPile ?? this.drawPile,
    hand: hand ?? this.hand,
    discardPile: discardPile ?? this.discardPile,
  );
}

/// 試合全体の状態（不変オブジェクト。[TechniqueMatchEngine] の各操作は
/// 新しい状態を返す）。
class TechniqueMatchState {
  const TechniqueMatchState({
    required this.playerA,
    required this.playerB,
    this.activePlayerIndex = 0,
    this.turnNumber = 1,
    this.phase = TechniqueMatchPhase.energySet,
    this.log = const [],
  });

  final TechniqueMatchPlayerState playerA;
  final TechniqueMatchPlayerState playerB;

  /// 0=A, 1=B
  final int activePlayerIndex;
  final int turnNumber;
  final TechniqueMatchPhase phase;
  final List<String> log;

  TechniqueMatchPlayerState get active =>
      activePlayerIndex == 0 ? playerA : playerB;
  TechniqueMatchPlayerState get inactive =>
      activePlayerIndex == 0 ? playerB : playerA;

  TechniqueMatchState copyWith({
    TechniqueMatchPlayerState? playerA,
    TechniqueMatchPlayerState? playerB,
    int? activePlayerIndex,
    int? turnNumber,
    TechniqueMatchPhase? phase,
    List<String>? log,
  }) => TechniqueMatchState(
    playerA: playerA ?? this.playerA,
    playerB: playerB ?? this.playerB,
    activePlayerIndex: activePlayerIndex ?? this.activePlayerIndex,
    turnNumber: turnNumber ?? this.turnNumber,
    phase: phase ?? this.phase,
    log: log ?? this.log,
  );

  /// アクティブプレイヤー側を更新した新しい状態を返す。
  TechniqueMatchState copyWithActive(TechniqueMatchPlayerState updated) =>
      activePlayerIndex == 0 ? copyWith(playerA: updated) : copyWith(playerB: updated);
}

/// 既定の休息回復力（[TechniqueDeckWrestlerProfile] が無い場合の暫定値）。
/// 正式なバランス値ではない（docs/design/technique_deck_open_questions.md参照）。
const int defaultRecoveryPower = 15;

const int _handSize = 5;

/// [TechniqueMatchState] の状態遷移を行う純粋関数群。
class TechniqueMatchEngine {
  const TechniqueMatchEngine._();

  /// 新しい試合を開始する。両者とも山札をシャッフルし、5枚ドローする。
  /// 開始直後の状態はプレイヤーA・ターン1・`energySet`フェーズ
  /// （＝両者ともドロー済みで行動可能な状態）。
  static TechniqueMatchState start({
    required String wrestlerAId,
    required String wrestlerAName,
    required int wrestlerAMaxHp,
    required TechniqueDeckDefinition deckA,
    required String wrestlerBId,
    required String wrestlerBName,
    required int wrestlerBMaxHp,
    required TechniqueDeckDefinition deckB,
    int? startingHpA,
    int? startingHpB,
    int recoveryPowerA = defaultRecoveryPower,
    int recoveryPowerB = defaultRecoveryPower,
    int handSize = _handSize,
    Random? random,
  }) {
    final rng = random ?? Random();
    final playerA = _initialPlayerState(
      wrestlerId: wrestlerAId,
      wrestlerName: wrestlerAName,
      maxHp: wrestlerAMaxHp,
      startingHp: startingHpA,
      recoveryPower: recoveryPowerA,
      deck: deckA,
      handSize: handSize,
      random: rng,
    );
    final playerB = _initialPlayerState(
      wrestlerId: wrestlerBId,
      wrestlerName: wrestlerBName,
      maxHp: wrestlerBMaxHp,
      startingHp: startingHpB,
      recoveryPower: recoveryPowerB,
      deck: deckB,
      handSize: handSize,
      random: rng,
    );
    return TechniqueMatchState(
      playerA: playerA,
      playerB: playerB,
      activePlayerIndex: 0,
      turnNumber: 1,
      phase: TechniqueMatchPhase.energySet,
      log: [
        '試合開始: ${playerA.wrestlerName} vs ${playerB.wrestlerName}',
        'ターン1: ${playerA.wrestlerName}の手番',
        '${playerA.wrestlerName}が初期手札${playerA.hand.length}枚をドローした',
      ],
    );
  }

  static TechniqueMatchPlayerState _initialPlayerState({
    required String wrestlerId,
    required String wrestlerName,
    required int maxHp,
    required int? startingHp,
    required int recoveryPower,
    required TechniqueDeckDefinition deck,
    required int handSize,
    required Random random,
  }) {
    final shuffled = List<TechniqueDeckEntry>.from(deck.entries)..shuffle(random);
    final hand = shuffled.take(handSize).toList();
    final drawPile = shuffled.skip(handSize).toList();
    return TechniqueMatchPlayerState(
      wrestlerId: wrestlerId,
      wrestlerName: wrestlerName,
      maxHp: maxHp,
      hp: (startingHp ?? maxHp).clamp(0, maxHp),
      heat: 0,
      posture: WrestlerPosture.stand,
      recoveryPower: recoveryPower,
      drawPile: drawPile,
      hand: hand,
      discardPile: const [],
    );
  }

  /// 山札から1枚引く。山札が0枚なら捨て札をシャッフルして山札にしてから引く
  /// （仕様書13章）。捨て札も0枚なら何も起きない（open questions 4番、
  /// 正式な「手詰まり」処理は未決定のため、Phase 3では単に引けないだけ）。
  static TechniqueMatchPlayerState _drawOne(
    TechniqueMatchPlayerState player,
    Random random,
  ) {
    var drawPile = player.drawPile;
    var discardPile = player.discardPile;
    if (drawPile.isEmpty) {
      if (discardPile.isEmpty) return player;
      drawPile = List<TechniqueDeckEntry>.from(discardPile)..shuffle(random);
      discardPile = const [];
    }
    final drawn = drawPile.first;
    return player.copyWith(
      drawPile: drawPile.skip(1).toList(),
      hand: [...player.hand, drawn],
      discardPile: discardPile,
    );
  }

  /// アクティブプレイヤーをスタンドからダウンさせる（技を介さない暫定操作、
  /// Phase 3ではダウン状態の動作確認のみが目的）。
  static TechniqueMatchState goDown(TechniqueMatchState state) {
    if (state.active.posture != WrestlerPosture.stand) return state;
    final updated = state.active.copyWith(posture: WrestlerPosture.down);
    return state
        .copyWithActive(updated)
        .copyWith(
          log: [...state.log, '${state.active.wrestlerName}がダウンした'],
        );
  }

  /// 休息する（ダウン中のみ）。HPを回復力分回復し、ターンを終了する
  /// （仕様書12章）。
  static TechniqueMatchState rest(TechniqueMatchState state, {Random? random}) {
    if (state.active.posture != WrestlerPosture.down) return state;
    final recovered = (state.active.hp + state.active.recoveryPower).clamp(
      0,
      state.active.maxHp,
    );
    final updated = state.active.copyWith(hp: recovered);
    final rested = state
        .copyWithActive(updated)
        .copyWith(
          log: [
            ...state.log,
            '${state.active.wrestlerName}が休息してHPを${recovered - state.active.hp}回復した'
                ' (${state.active.hp} → $recovered)',
          ],
        );
    return endTurn(rested, random: random);
  }

  /// ターンを終了し、相手プレイヤーの開始→ドロー→エネルギーセットまでを
  /// 自動的に進める（メインアクションが無いPhase 3では、これらの段階に
  /// プレイヤーの選択は発生しない）。
  static TechniqueMatchState endTurn(TechniqueMatchState state, {Random? random}) {
    final rng = random ?? Random();
    final nextIndex = state.activePlayerIndex == 0 ? 1 : 0;
    final nextTurnNumber = nextIndex == 0 ? state.turnNumber + 1 : state.turnNumber;
    var nextPlayer = nextIndex == 0 ? state.playerA : state.playerB;

    final log = [...state.log, '${state.active.wrestlerName}のターンを終了した'];

    // 仕様書11.4章: 自分のターン開始時、通常はスタンド状態へ戻す。
    // 疲労（HP0到達時）についても、Phase 4時点では他に回復手段が無いため
    // 同様にスタンドへ戻す暫定運用とする（open questions 3番、HP0時の
    // 行動制限は未決定。疲労状態の恒久化はここでは意図しない）。
    if (nextPlayer.posture == WrestlerPosture.down ||
        nextPlayer.posture == WrestlerPosture.fatigued) {
      nextPlayer = nextPlayer.copyWith(posture: WrestlerPosture.stand);
      log.add('${nextPlayer.wrestlerName}がスタンド状態に戻った');
    }

    // 仕様書3.3章: 自分のターン開始時、使用済みエネルギーを回復する。
    if (nextPlayer.spentEnergy.values.any((v) => v > 0)) {
      nextPlayer = nextPlayer.copyWith(spentEnergy: const {});
      log.add('${nextPlayer.wrestlerName}の使用済みエネルギーが回復した');
    }

    log.add('ターン$nextTurnNumber: ${nextPlayer.wrestlerName}の手番');
    nextPlayer = _drawOne(nextPlayer, rng);
    log.add('${nextPlayer.wrestlerName}がドローした（手札${nextPlayer.hand.length}枚）');
    log.add('${nextPlayer.wrestlerName}のエネルギーセット完了');

    return state.copyWith(
      playerA: nextIndex == 0 ? nextPlayer : state.playerA,
      playerB: nextIndex == 1 ? nextPlayer : state.playerB,
      activePlayerIndex: nextIndex,
      turnNumber: nextTurnNumber,
      phase: TechniqueMatchPhase.energySet,
      log: log,
    );
  }

  /// 手札のエネルギーカードをセットする（`catalog`上でエネルギーカードと
  /// 解決できるカードのみ）。セット後は永続的にそのプレイヤーの
  /// [TechniqueMatchPlayerState.energyPool] に加算される（手札からは消える。
  /// 捨て札にも入らない）。
  static TechniqueMoveResult setEnergy(
    TechniqueMatchState state,
    TechniqueDeckEntry entry,
    TechniqueDeckCardCatalog catalog,
  ) {
    final active = state.active;
    if (!active.hand.contains(entry)) {
      return TechniqueMoveResult(
        state: state,
        success: false,
        failureReason: 'このカードは手札にありません。',
      );
    }
    final card = catalog.findEnergyById(entry.cardId);
    if (card == null) {
      return TechniqueMoveResult(
        state: state,
        success: false,
        failureReason: 'このカードはエネルギーカードではありません。',
      );
    }
    final pool = Map<MoveAttribute, int>.from(active.energyPool);
    pool[card.attribute] = (pool[card.attribute] ?? 0) + 1;
    final newHand = List<TechniqueDeckEntry>.from(active.hand)..remove(entry);
    final updated = active.copyWith(energyPool: pool, hand: newHand);
    return TechniqueMoveResult(
      state: state.copyWithActive(updated).copyWith(
        log: [
          ...state.log,
          '${active.wrestlerName}が「${card.name}」をエネルギーとしてセットした'
              '（${moveAttributeLabel(card.attribute)} ${pool[card.attribute]}枚）',
        ],
      ),
      success: true,
    );
  }

  /// [entry] が示す技カードを、現在の状態でアクティブプレイヤーが使用できるかを
  /// 判定する。UIのボタン有効/無効判定にも使う。
  static ({bool canUse, String? reason}) canUseMove(
    TechniqueMatchState state,
    TechniqueDeckEntry entry,
    TechniqueDeckCardCatalog catalog,
  ) {
    final active = state.active;
    if (!active.hand.contains(entry)) {
      return (canUse: false, reason: 'このカードは手札にありません。');
    }
    final card = catalog.findTechniqueById(entry.cardId);
    if (card == null) {
      return (canUse: false, reason: 'このカードは技カードではありません。');
    }
    final isRestricted =
        card.category == TechniqueCardCategory.signature ||
        card.category == TechniqueCardCategory.finisher;
    if (isRestricted && !card.allowedWrestlerIds.contains(active.wrestlerId)) {
      return (canUse: false, reason: '${active.wrestlerName}は使用できません。');
    }
    if (card.minimumLevel > active.level) {
      return (
        canUse: false,
        reason: '必要レベルLv.${card.minimumLevel}に達していません（現在Lv.${active.level}）。',
      );
    }
    final opponent = state.inactive;
    final opponentDownLike =
        opponent.posture == WrestlerPosture.down ||
        opponent.posture == WrestlerPosture.fatigued;
    if (card.targetState == TechniqueTargetState.stand &&
        opponent.posture != WrestlerPosture.stand) {
      return (canUse: false, reason: '相手がスタンド状態でないと使用できません。');
    }
    if (card.targetState == TechniqueTargetState.down && !opponentDownLike) {
      return (canUse: false, reason: '相手がダウン状態でないと使用できません。');
    }
    for (final costEntry in card.attackEnergyCost.entries) {
      if (costEntry.value <= 0) continue;
      if (active.availableEnergyFor(costEntry.key) < costEntry.value) {
        return (
          canUse: false,
          reason:
              '${moveAttributeLabel(costEntry.key)}エネルギーが不足しています'
              '（必要${costEntry.value}、使用可能${active.availableEnergyFor(costEntry.key)}）。',
        );
      }
    }
    return (canUse: true, reason: null);
  }

  /// 手札の技カードを1枚使用する（Phase 4: 単発技のみ、返技は無い）。
  ///
  /// 即時に以下を反映する: 攻撃エネルギー消費、技カードの捨て札化、
  /// ダメージ（HPは0未満にしない）、HEAT、ダウン付与。HP0到達時は疲労状態へ
  /// 移行する。フォール／ギブアップ／フィニッシャー効果（`hasPinEffect` /
  /// `hasSubmissionEffect` / `hasFinisherEffect`）はまだ決着処理へ接続しない
  /// （Phase 6・7）。
  static TechniqueMoveResult useMove(
    TechniqueMatchState state,
    TechniqueDeckEntry entry,
    TechniqueDeckCardCatalog catalog,
  ) {
    final check = canUseMove(state, entry, catalog);
    if (!check.canUse) {
      return TechniqueMoveResult(
        state: state,
        success: false,
        failureReason: check.reason,
      );
    }
    final card = catalog.findTechniqueById(entry.cardId)!;

    // エネルギー消費（即時）。
    final spent = Map<MoveAttribute, int>.from(state.active.spentEnergy);
    for (final costEntry in card.attackEnergyCost.entries) {
      if (costEntry.value <= 0) continue;
      spent[costEntry.key] = (spent[costEntry.key] ?? 0) + costEntry.value;
    }
    // 技カードを手札から捨て札へ（成立・不成立を問わない仕様書6章の原則。
    // Phase 4には防御が無いため常に成立する）。
    final newHand = List<TechniqueDeckEntry>.from(state.active.hand)
      ..remove(entry);
    final active = state.active.copyWith(
      spentEnergy: spent,
      hand: newHand,
      discardPile: [...state.active.discardPile, entry],
      heat: state.active.heat + card.heatDelta,
    );

    // ダメージ即時適用（HPは0未満にしない）。
    final originalOpponent = state.inactive;
    final damage = card.power < 0 ? 0 : card.power;
    final newHp = (originalOpponent.hp - damage).clamp(0, originalOpponent.maxHp);
    final becameFatigued =
        newHp <= 0 && originalOpponent.posture != WrestlerPosture.fatigued;
    final becameDown =
        !becameFatigued &&
        card.causesDown &&
        originalOpponent.posture == WrestlerPosture.stand;
    final newPosture = newHp <= 0
        ? WrestlerPosture.fatigued
        : (becameDown ? WrestlerPosture.down : originalOpponent.posture);
    final opponent = originalOpponent.copyWith(hp: newHp, posture: newPosture);

    final log = [
      ...state.log,
      '${active.wrestlerName}が「${card.name}」を使用した（威力${card.power}）',
      if (damage > 0)
        '${opponent.wrestlerName}に$damageダメージ（HP ${originalOpponent.hp} → $newHp）',
      if (card.heatDelta != 0)
        '${active.wrestlerName}のHEATが${card.heatDelta}上昇した（HEAT ${active.heat}）',
      if (becameFatigued) '${opponent.wrestlerName}のHPが0になり、疲労状態になった',
      if (becameDown) '${opponent.wrestlerName}がダウンした',
    ];

    final newPlayerA = state.activePlayerIndex == 0 ? active : opponent;
    final newPlayerB = state.activePlayerIndex == 0 ? opponent : active;

    return TechniqueMoveResult(
      state: state.copyWith(playerA: newPlayerA, playerB: newPlayerB, log: log),
      success: true,
    );
  }
}

/// [TechniqueMatchEngine.useMove] / [TechniqueMatchEngine.setEnergy] の結果。
/// 失敗時は[state]は入力のまま変化しない。
class TechniqueMoveResult {
  const TechniqueMoveResult({
    required this.state,
    required this.success,
    this.failureReason,
  });

  final TechniqueMatchState state;
  final bool success;
  final String? failureReason;
}
