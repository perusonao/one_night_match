import 'dart:math';

import '../wrestler_editor/models.dart' show MoveAttribute, moveAttributeLabel;
import 'technique_deck_deck.dart';
import 'technique_deck_models.dart';

/// Technique Deck Rules Phase 3〜5: 最小限の試合状態管理＋技の応酬（ラリー）。
///
/// Phase 5で追加したのは「攻撃→返技判定→（成功なら）攻守交代→また攻撃」という
/// ラリー構造。読み合いの核は返技側の選択にある: 返技エネルギーが足りていても
/// 使うかどうかはプレイヤーが選ぶ（`counterAttack`で明示的に返技を選んだ場合の
/// み消費される）。返技が成立すると、攻守が入れ替わりダメージ・HEAT・ダウンは
/// 一切発生しない。返技しない（できない）場合は技が成立し、Phase 4と同じ即時
/// 適用でダメージ・HEAT・ダウンが反映されてラリーが終了する。
/// フォール・ギブアップ・フィニッシャーの決着処理・キックアウト・エスケープ・
/// CPUは実装しない（Phase 6以降）。既存の `LevelMatchEngine`
/// （classic/energy）とは完全に独立しており、一切の変更・依存を持たない。
///
/// 【ダメージ適用方式について】open questions 1番。Phase 4に続きPhase 5でも
/// 技ごとの即時適用を維持した（ユーザー指示）。技Aの成立で相手がダウンし、
/// 直後にダウン限定技Bが使用可能になる連携（`targetState`判定）を成立させる
/// には即時反映が必要なため。
///
/// 【ラリーと「ターン」の関係】ラリー中に攻守（`rallyAttackerIndex`）が
/// 入れ替わっても、公式な「ターン」の所有者（`activePlayerIndex`。ターン開始
/// 処理・ドロー・ターン終了操作の主体）は変化しない。ラリーが終了すると
/// （技が成立する／Chain Limit／使用可能技なし／プレイヤーが終了を選択）、
/// 制御は常に`activePlayerIndex`のプレイヤーへ戻る。

/// ターンの進行段階。
enum TechniqueMatchPhase { start, draw, energySet, end }

/// ラリー中、攻撃が宣言されてから防御側の返技判定が済むまでの保留状態。
class TechniquePendingAttack {
  const TechniquePendingAttack({
    required this.attackerIndex,
    required this.cardId,
    required this.chain,
  });

  /// 0=A, 1=B。この攻撃を宣言した側。
  final int attackerIndex;
  final String cardId;

  /// このラリーの何回目の攻撃か（1始まり）。
  final int chain;
}

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

/// `copyWith` で「nullを明示的にセットする」と「未指定」を区別するための
/// 番兵値（`lib/src/technique_deck/technique_deck_models.dart`と同じ慣習）。
const Object _unset = Object();

/// 試合全体の状態（不変オブジェクト。[TechniqueMatchEngine] の各操作は
/// 新しい状態を返す）。
class TechniqueMatchState {
  const TechniqueMatchState({
    required this.playerA,
    required this.playerB,
    this.activePlayerIndex = 0,
    this.turnNumber = 1,
    this.phase = TechniqueMatchPhase.energySet,
    this.rallyAttackerIndex,
    this.rallyChain = 0,
    this.pendingAttack,
    this.log = const [],
  });

  final TechniqueMatchPlayerState playerA;
  final TechniqueMatchPlayerState playerB;

  /// 0=A, 1=B。「公式なターン」の所有者（ラリー中の攻守交代では変化しない）。
  final int activePlayerIndex;
  final int turnNumber;
  final TechniqueMatchPhase phase;

  /// ラリー中の攻撃側（0=A, 1=B）。ラリーが進行していなければnull
  /// （この場合、次に技を宣言できるのは`activePlayerIndex`のプレイヤー）。
  final int? rallyAttackerIndex;

  /// 現在のラリーの通算攻撃回数（ラリー終了時に0へ戻る）。
  final int rallyChain;

  /// 攻撃が宣言され、防御側の返技判定を待っている状態。nullなら待機中の
  /// 攻撃は無い。
  final TechniquePendingAttack? pendingAttack;

  final List<String> log;

  TechniqueMatchPlayerState get active =>
      activePlayerIndex == 0 ? playerA : playerB;
  TechniqueMatchPlayerState get inactive =>
      activePlayerIndex == 0 ? playerB : playerA;

  TechniqueMatchPlayerState playerAt(int index) => index == 0 ? playerA : playerB;

  /// ラリーが進行中かどうか（攻守が`activePlayerIndex`から入れ替わっている、
  /// または攻撃の判定待ちがある状態）。
  bool get isRallyActive => rallyAttackerIndex != null;

  /// 防御側の返技判定を待っているかどうか。
  bool get isAwaitingDefense => pendingAttack != null;

  TechniqueMatchState copyWith({
    TechniqueMatchPlayerState? playerA,
    TechniqueMatchPlayerState? playerB,
    int? activePlayerIndex,
    int? turnNumber,
    TechniqueMatchPhase? phase,
    Object? rallyAttackerIndex = _unset,
    int? rallyChain,
    Object? pendingAttack = _unset,
    List<String>? log,
  }) => TechniqueMatchState(
    playerA: playerA ?? this.playerA,
    playerB: playerB ?? this.playerB,
    activePlayerIndex: activePlayerIndex ?? this.activePlayerIndex,
    turnNumber: turnNumber ?? this.turnNumber,
    phase: phase ?? this.phase,
    rallyAttackerIndex: identical(rallyAttackerIndex, _unset)
        ? this.rallyAttackerIndex
        : rallyAttackerIndex as int?,
    rallyChain: rallyChain ?? this.rallyChain,
    pendingAttack: identical(pendingAttack, _unset)
        ? this.pendingAttack
        : pendingAttack as TechniquePendingAttack?,
    log: log ?? this.log,
  );

  /// アクティブプレイヤー側を更新した新しい状態を返す。
  TechniqueMatchState copyWithActive(TechniqueMatchPlayerState updated) =>
      activePlayerIndex == 0 ? copyWith(playerA: updated) : copyWith(playerB: updated);

  /// ラリー・保留攻撃をリセットした新しい状態を返す（ラリー終了時に使う）。
  TechniqueMatchState copyWithRallyEnded({
    TechniqueMatchPlayerState? playerA,
    TechniqueMatchPlayerState? playerB,
    List<String>? log,
  }) => copyWith(
    playerA: playerA,
    playerB: playerB,
    rallyAttackerIndex: null,
    rallyChain: 0,
    pendingAttack: null,
    log: log,
  );
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
  ) => _checkEligibility(state.active, state.inactive, entry, catalog);

  static ({bool canUse, String? reason}) _checkEligibility(
    TechniqueMatchPlayerState attacker,
    TechniqueMatchPlayerState defender,
    TechniqueDeckEntry entry,
    TechniqueDeckCardCatalog catalog,
  ) {
    if (!attacker.hand.contains(entry)) {
      return (canUse: false, reason: 'このカードは手札にありません。');
    }
    final card = catalog.findTechniqueById(entry.cardId);
    if (card == null) {
      return (canUse: false, reason: 'このカードは技カードではありません。');
    }
    final isRestricted =
        card.category == TechniqueCardCategory.signature ||
        card.category == TechniqueCardCategory.finisher;
    if (isRestricted && !card.allowedWrestlerIds.contains(attacker.wrestlerId)) {
      return (canUse: false, reason: '${attacker.wrestlerName}は使用できません。');
    }
    if (card.minimumLevel > attacker.level) {
      return (
        canUse: false,
        reason: '必要レベルLv.${card.minimumLevel}に達していません（現在Lv.${attacker.level}）。',
      );
    }
    final defenderDownLike =
        defender.posture == WrestlerPosture.down ||
        defender.posture == WrestlerPosture.fatigued;
    if (card.targetState == TechniqueTargetState.stand &&
        defender.posture != WrestlerPosture.stand) {
      return (canUse: false, reason: '相手がスタンド状態でないと使用できません。');
    }
    if (card.targetState == TechniqueTargetState.down && !defenderDownLike) {
      return (canUse: false, reason: '相手がダウン状態でないと使用できません。');
    }
    for (final costEntry in card.attackEnergyCost.entries) {
      if (costEntry.value <= 0) continue;
      if (attacker.availableEnergyFor(costEntry.key) < costEntry.value) {
        return (
          canUse: false,
          reason:
              '${moveAttributeLabel(costEntry.key)}エネルギーが不足しています'
              '（必要${costEntry.value}、使用可能${attacker.availableEnergyFor(costEntry.key)}）。',
        );
      }
    }
    return (canUse: true, reason: null);
  }

  /// 攻撃エネルギー消費・技カードの捨て札化・ダメージ即時適用（HPは0未満に
  /// しない）・HEAT・ダウン付与を行う。[useMove] と [resolveHit] の共通処理。
  static ({
    TechniqueMatchPlayerState attacker,
    TechniqueMatchPlayerState defender,
    List<String> log,
  })
  _resolveAttack(
    TechniqueMatchPlayerState attacker,
    TechniqueMatchPlayerState defender,
    TechniqueDeckTechniqueCard card, {
    /// nullでない場合のみ、攻撃エネルギー消費・手札→捨て札を行う
    /// （宣言時点で既に消費済みのラリー経由の攻撃ではnullを渡す）。
    TechniqueDeckEntry? entryToConsume,
  }) {
    var updatedAttacker = attacker;
    if (entryToConsume != null) {
      final spent = Map<MoveAttribute, int>.from(attacker.spentEnergy);
      for (final costEntry in card.attackEnergyCost.entries) {
        if (costEntry.value <= 0) continue;
        spent[costEntry.key] = (spent[costEntry.key] ?? 0) + costEntry.value;
      }
      final newHand = List<TechniqueDeckEntry>.from(attacker.hand)
        ..remove(entryToConsume);
      updatedAttacker = attacker.copyWith(
        spentEnergy: spent,
        hand: newHand,
        discardPile: [...attacker.discardPile, entryToConsume],
      );
    }
    updatedAttacker = updatedAttacker.copyWith(
      heat: updatedAttacker.heat + card.heatDelta,
    );

    final damage = card.power < 0 ? 0 : card.power;
    final newHp = (defender.hp - damage).clamp(0, defender.maxHp);
    final becameFatigued =
        newHp <= 0 && defender.posture != WrestlerPosture.fatigued;
    final becameDown =
        !becameFatigued &&
        card.causesDown &&
        defender.posture == WrestlerPosture.stand;
    final newPosture = newHp <= 0
        ? WrestlerPosture.fatigued
        : (becameDown ? WrestlerPosture.down : defender.posture);
    final updatedDefender = defender.copyWith(hp: newHp, posture: newPosture);

    final log = [
      if (damage > 0)
        '${updatedDefender.wrestlerName}に$damageダメージ（HP ${defender.hp} → $newHp）',
      if (card.heatDelta != 0)
        '${updatedAttacker.wrestlerName}のHEATが${card.heatDelta}上昇した'
            '（HEAT ${updatedAttacker.heat}）',
      if (becameFatigued) '${updatedDefender.wrestlerName}のHPが0になり、疲労状態になった',
      if (becameDown) '${updatedDefender.wrestlerName}がダウンした',
    ];

    return (attacker: updatedAttacker, defender: updatedDefender, log: log);
  }

  /// 手札の技カードを1枚使用する（Phase 4互換API: 単発技のみ、返技は無い。
  /// ラリー機構を経由せず即座に成立させたい場合はこちらを使う）。
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
    final resolved = _resolveAttack(
      state.active,
      state.inactive,
      card,
      entryToConsume: entry,
    );
    final log = [
      ...state.log,
      '${resolved.attacker.wrestlerName}が「${card.name}」を使用した（威力${card.power}）',
      ...resolved.log,
    ];

    final newPlayerA = state.activePlayerIndex == 0
        ? resolved.attacker
        : resolved.defender;
    final newPlayerB = state.activePlayerIndex == 0
        ? resolved.defender
        : resolved.attacker;

    return TechniqueMoveResult(
      state: state.copyWith(playerA: newPlayerA, playerB: newPlayerB, log: log),
      success: true,
    );
  }

  // ============================================================
  // Phase 5: ラリー（攻撃 → 返技判定 → 攻守交代 → また攻撃）
  // ============================================================

  /// 1ラリーで許容する最大攻撃回数（無限ループ防止の安全弁）。
  /// 到達した場合はラリーを強制終了する（Chain Limit）。
  static const int maxRallyChain = 20;

  /// 現在攻撃側になり得るプレイヤー（ラリー中ならその攻撃側、ラリー外なら
  /// `activePlayerIndex`）が、手札の中に使用可能な技を1枚でも持っているか。
  /// UIが「使用可能技がない」による自動終了を判定するのに使う。
  static bool hasUsableMove(
    TechniqueMatchState state,
    TechniqueDeckCardCatalog catalog,
  ) {
    final attackerIndex = state.rallyAttackerIndex ?? state.activePlayerIndex;
    final attacker = state.playerAt(attackerIndex);
    final defender = state.playerAt(1 - attackerIndex);
    return attacker.hand.any(
      (entry) =>
          _checkEligibility(attacker, defender, entry, catalog).canUse,
    );
  }

  /// [entry] を現在の実質的な攻撃側（`rallyAttackerIndex ?? activePlayerIndex`）
  /// が宣言できるかどうかを判定する。UIのボタン有効/無効判定に使う。
  static ({bool canUse, String? reason}) canDeclareAttack(
    TechniqueMatchState state,
    TechniqueDeckEntry entry,
    TechniqueDeckCardCatalog catalog,
  ) {
    if (state.pendingAttack != null) {
      return (canUse: false, reason: '返技の判定待ちです。');
    }
    final attackerIndex = state.rallyAttackerIndex ?? state.activePlayerIndex;
    return _checkEligibility(
      state.playerAt(attackerIndex),
      state.playerAt(1 - attackerIndex),
      entry,
      catalog,
    );
  }

  /// 現在保留中の攻撃に対して、防御側が返技可能かどうかを判定する
  /// （UIのボタン有効/無効判定用。実際に返技エネルギーを消費するには
  /// [counterAttack] を呼ぶ）。
  static ({bool canCounter, String? reason}) checkCounterEligibility(
    TechniqueMatchState state,
    TechniqueDeckCardCatalog catalog,
  ) {
    final pending = state.pendingAttack;
    if (pending == null) {
      return (canCounter: false, reason: '返技可能な攻撃がありません。');
    }
    final defenderIndex = 1 - pending.attackerIndex;
    final defender = state.playerAt(defenderIndex);
    final card = catalog.findTechniqueById(pending.cardId);
    if (card == null) {
      return (canCounter: false, reason: 'カードが見つかりません。');
    }
    for (final costEntry in card.reversalEnergyCost.entries) {
      if (costEntry.value <= 0) continue;
      if (defender.availableEnergyFor(costEntry.key) < costEntry.value) {
        return (
          canCounter: false,
          reason:
              '${moveAttributeLabel(costEntry.key)}の返技エネルギーが不足しています'
              '（必要${costEntry.value}、使用可能${defender.availableEnergyFor(costEntry.key)}）。',
        );
      }
    }
    return (canCounter: true, reason: null);
  }

  /// 技を宣言する（攻撃側）。ラリーが未開始なら`activePlayerIndex`のプレイヤー
  /// が新しいラリーを開始する。ラリー中なら現在の攻撃側（返技で攻守交代した
  /// 側を含む）が追加の技を宣言する。宣言のみを行い、成立可否（返技判定）は
  /// [counterAttack] / [resolveHit] で決める。
  static TechniqueMoveResult declareAttack(
    TechniqueMatchState state,
    TechniqueDeckEntry entry,
    TechniqueDeckCardCatalog catalog,
  ) {
    if (state.pendingAttack != null) {
      return TechniqueMoveResult(
        state: state,
        success: false,
        failureReason: '返技の判定待ちです。',
      );
    }
    if (state.rallyChain >= maxRallyChain) {
      final log = [
        ...state.log,
        '[Chain ${state.rallyChain}] Chain Limitに達したためラリーを終了した',
      ];
      return TechniqueMoveResult(
        state: state.copyWithRallyEnded(log: log),
        success: false,
        failureReason: 'Chain Limit（$maxRallyChain）に達しています。',
      );
    }

    final attackerIndex = state.rallyAttackerIndex ?? state.activePlayerIndex;
    final attacker = state.playerAt(attackerIndex);
    final defender = state.playerAt(1 - attackerIndex);
    final check = _checkEligibility(attacker, defender, entry, catalog);
    if (!check.canUse) {
      return TechniqueMoveResult(
        state: state,
        success: false,
        failureReason: check.reason,
      );
    }
    final card = catalog.findTechniqueById(entry.cardId)!;

    // 攻撃エネルギー消費・手札→捨て札は宣言時点で行う（仕様書6章: 成立・
    // 不成立を問わず技カードは使用後に捨て札）。
    final spent = Map<MoveAttribute, int>.from(attacker.spentEnergy);
    for (final costEntry in card.attackEnergyCost.entries) {
      if (costEntry.value <= 0) continue;
      spent[costEntry.key] = (spent[costEntry.key] ?? 0) + costEntry.value;
    }
    final newHand = List<TechniqueDeckEntry>.from(attacker.hand)
      ..remove(entry);
    final updatedAttacker = attacker.copyWith(
      spentEnergy: spent,
      hand: newHand,
      discardPile: [...attacker.discardPile, entry],
    );

    final chain = state.rallyChain + 1;
    final pending = TechniquePendingAttack(
      attackerIndex: attackerIndex,
      cardId: card.id,
      chain: chain,
    );
    final log = [
      ...state.log,
      '[Chain $chain] ${updatedAttacker.wrestlerName}が「${card.name}」を宣言した',
    ];

    return TechniqueMoveResult(
      state: state.copyWith(
        playerA: attackerIndex == 0 ? updatedAttacker : state.playerA,
        playerB: attackerIndex == 1 ? updatedAttacker : state.playerB,
        rallyAttackerIndex: attackerIndex,
        rallyChain: chain,
        pendingAttack: pending,
        log: log,
      ),
      success: true,
    );
  }

  /// 防御側が返技する。返技エネルギー（`reversalEnergyCost`）が足りない
  /// 場合は失敗する（プレイヤーは返技するかどうかを任意に選べる。エネルギーが
  /// 足りていても返技しない、という選択が読み合いの核になる。その場合は
  /// [resolveHit] を呼ぶ）。
  ///
  /// 成功時: ダメージ無効・HEAT加算なし・ダウンなし。攻守が即座に交代し、
  /// 新しい攻撃側（元の防御側）が次の技を宣言できる状態になる。
  static TechniqueMoveResult counterAttack(
    TechniqueMatchState state,
    TechniqueDeckCardCatalog catalog,
  ) {
    final pending = state.pendingAttack;
    if (pending == null) {
      return TechniqueMoveResult(
        state: state,
        success: false,
        failureReason: '返技可能な攻撃がありません。',
      );
    }
    final defenderIndex = 1 - pending.attackerIndex;
    final defender = state.playerAt(defenderIndex);
    final card = catalog.findTechniqueById(pending.cardId)!;

    for (final costEntry in card.reversalEnergyCost.entries) {
      if (costEntry.value <= 0) continue;
      if (defender.availableEnergyFor(costEntry.key) < costEntry.value) {
        return TechniqueMoveResult(
          state: state,
          success: false,
          failureReason:
              '${moveAttributeLabel(costEntry.key)}の返技エネルギーが不足しています'
              '（必要${costEntry.value}、使用可能${defender.availableEnergyFor(costEntry.key)}）。',
        );
      }
    }

    final spent = Map<MoveAttribute, int>.from(defender.spentEnergy);
    for (final costEntry in card.reversalEnergyCost.entries) {
      if (costEntry.value <= 0) continue;
      spent[costEntry.key] = (spent[costEntry.key] ?? 0) + costEntry.value;
    }
    final updatedDefender = defender.copyWith(spentEnergy: spent);

    final log = [
      ...state.log,
      '[Chain ${pending.chain}] ${updatedDefender.wrestlerName}が'
          '「${card.name}」を返技した（ダメージ無効・攻守交代）',
    ];

    return TechniqueMoveResult(
      state: state.copyWith(
        playerA: defenderIndex == 0 ? updatedDefender : state.playerA,
        playerB: defenderIndex == 1 ? updatedDefender : state.playerB,
        rallyAttackerIndex: defenderIndex,
        pendingAttack: null,
        log: log,
      ),
      success: true,
    );
  }

  /// 防御側が返技しない（できない、または選ばない）。技が成立し、ダメージ・
  /// HEAT・ダウンが即時反映される。ラリーはここで終了し、制御は
  /// `activePlayerIndex`のプレイヤーへ戻る。
  static TechniqueMatchState resolveHit(
    TechniqueMatchState state,
    TechniqueDeckCardCatalog catalog,
  ) {
    final pending = state.pendingAttack;
    if (pending == null) return state;
    final attackerIndex = pending.attackerIndex;
    final attacker = state.playerAt(attackerIndex);
    final defender = state.playerAt(1 - attackerIndex);
    final card = catalog.findTechniqueById(pending.cardId)!;

    // 手札・エネルギーは宣言（declareAttack）時点で既に消費済みのため、
    // entryToConsumeは渡さない。
    final resolved = _resolveAttack(attacker, defender, card);

    final log = [
      ...state.log,
      '[Chain ${pending.chain}] Hit! ${resolved.attacker.wrestlerName}の'
          '「${card.name}」が成立した',
      ...resolved.log,
      'ラリー終了（Chain ${pending.chain}）',
    ];

    return state.copyWithRallyEnded(
      playerA: attackerIndex == 0 ? resolved.attacker : resolved.defender,
      playerB: attackerIndex == 1 ? resolved.attacker : resolved.defender,
      log: log,
    );
  }

  /// ラリーを（技を成立させずに）終了する。返技で攻守を得た側が、あえて
  /// 追撃しない場合などに使う（仕様書のラリー終了条件「プレイヤーが終了を
  /// 選択」に相当）。保留中の攻撃（[TechniqueMatchState.pendingAttack]）が
  /// ある状態では使えない（先に [counterAttack] / [resolveHit] で解決する）。
  static TechniqueMatchState endRally(TechniqueMatchState state) {
    if (!state.isRallyActive || state.pendingAttack != null) return state;
    final log = [...state.log, 'ラリーを終了した（Chain ${state.rallyChain}）'];
    return state.copyWithRallyEnded(log: log);
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
