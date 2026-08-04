import 'dart:math';

import '../wrestler_editor/models.dart' show MoveAttribute, moveAttributeLabel;
import 'technique_deck_deck.dart';
import 'technique_deck_models.dart';

/// Technique Deck Rules Phase 3〜6: 最小限の試合状態管理＋技の応酬（ラリー）＋
/// フォール・ギブアップによる決着。
///
/// Phase 5で追加したのは「攻撃→返技判定→（成功なら）攻守交代→また攻撃」という
/// ラリー構造。読み合いの核は返技側の選択にある: 返技エネルギーが足りていても
/// 使うかどうかはプレイヤーが選ぶ（`counterAttack`で明示的に返技を選んだ場合の
/// み消費される）。返技が成立すると、攻守が入れ替わりダメージ・HEAT・ダウンは
/// 一切発生しない。返技しない（できない）場合は技が成立し、Phase 4と同じ即時
/// 適用でダメージ・HEAT・ダウンが反映されてラリーが終了する。
///
/// Phase 6で追加したのは、技が成立した際に`hasPinEffect`
/// （フォール）／`hasSubmissionEffect`（ギブアップ）が立っている場合の決着
/// 判定。防御側は「キックアウト／ロープブレイクカードを使う」「返技エネルギー
/// を払う」「HPを消費する」のいずれかで回避でき、いずれもできない（または
/// 選ばない）場合はそこで試合が終わる（`TechniqueMatchState.winnerIndex`が
/// セットされる）。優先度は仕様書どおりフォール＞ギブアップとし、
/// `hasFinisherEffect`が立っている技はPhase 6の対象外（Phase 7でフィニッシャー
/// 専用の決着処理を実装するまでは、通常のフォール／ギブアップ判定も発生しない
/// ——通常の技として扱う）。
/// キックアウト・エスケープカード・フィニッシャー決着・CPUは実装しない
/// （Phase 7以降）。既存の `LevelMatchEngine`
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
/// 制御は常に`activePlayerIndex`のプレイヤーへ戻る。フォール／ギブアップの
/// 判定はラリー終了後（`pendingEscape`）に発生し、決着すれば`winnerIndex`が
/// セットされて試合は終了する。

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

/// 技成立後の決着判定の種類。
enum TechniqueEscapeKind {
  /// フォール（`hasPinEffect`）。キックアウトカード／返技エネルギー／
  /// HP消費（`kickOutThreshold`・`kickOutHpRate`）で回避する。
  fall,

  /// ギブアップ（`hasSubmissionEffect`）。ロープブレイクカード／返技エネルギー
  /// ／HP消費（`giveUpThreshold`・`giveUpHpCost`）で回避する。
  giveUp,
}

/// フォール／ギブアップ効果を持つ技が成立し、防御側の回避判定を待っている
/// 保留状態。
class TechniquePendingEscape {
  const TechniquePendingEscape({
    required this.attackerIndex,
    required this.defenderIndex,
    required this.cardId,
    required this.kind,
  });

  final int attackerIndex;
  final int defenderIndex;
  final String cardId;
  final TechniqueEscapeKind kind;
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
    this.pendingEscape,
    this.winnerIndex,
    this.winReason,
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

  /// フォール／ギブアップ効果を持つ技が成立し、防御側の回避判定を待っている
  /// 状態（Phase 6）。nullなら待機中の決着判定は無い。
  final TechniquePendingEscape? pendingEscape;

  /// 試合の勝者（0=A, 1=B）。nullならまだ試合は継続中。
  final int? winnerIndex;

  /// 勝敗が決した理由（例:「フォール勝利」）。[winnerIndex] がnullの間はnull。
  final String? winReason;

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

  /// 試合が決着済みかどうか。
  bool get isOver => winnerIndex != null;

  TechniqueMatchState copyWith({
    TechniqueMatchPlayerState? playerA,
    TechniqueMatchPlayerState? playerB,
    int? activePlayerIndex,
    int? turnNumber,
    TechniqueMatchPhase? phase,
    Object? rallyAttackerIndex = _unset,
    int? rallyChain,
    Object? pendingAttack = _unset,
    Object? pendingEscape = _unset,
    Object? winnerIndex = _unset,
    Object? winReason = _unset,
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
    pendingEscape: identical(pendingEscape, _unset)
        ? this.pendingEscape
        : pendingEscape as TechniquePendingEscape?,
    winnerIndex: identical(winnerIndex, _unset)
        ? this.winnerIndex
        : winnerIndex as int?,
    winReason: identical(winReason, _unset)
        ? this.winReason
        : winReason as String?,
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
  /// Phase 3ではダウン状態の動作確認のみが目的）。ラリー中・決着判定待ち・
  /// 試合終了後は何もしない（Phase 6でガードを追加）。
  static TechniqueMatchState goDown(TechniqueMatchState state) {
    if (state.isOver || state.isRallyActive || state.pendingEscape != null) {
      return state;
    }
    if (state.active.posture != WrestlerPosture.stand) return state;
    final updated = state.active.copyWith(posture: WrestlerPosture.down);
    return state
        .copyWithActive(updated)
        .copyWith(
          log: [...state.log, '${state.active.wrestlerName}がダウンした'],
        );
  }

  /// 休息する（ダウン中のみ）。HPを回復力分回復し、ターンを終了する
  /// （仕様書12章）。ラリー中・決着判定待ち・試合終了後は何もしない
  /// （Phase 6でガードを追加）。
  static TechniqueMatchState rest(TechniqueMatchState state, {Random? random}) {
    if (state.isOver || state.isRallyActive || state.pendingEscape != null) {
      return state;
    }
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
  /// プレイヤーの選択は発生しない）。ラリー中・決着判定待ち・試合終了後は
  /// 何もしない（Phase 6でガードを追加）。
  static TechniqueMatchState endTurn(TechniqueMatchState state, {Random? random}) {
    if (state.isOver || state.isRallyActive || state.pendingEscape != null) {
      return state;
    }
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
    if (state.isOver) {
      return TechniqueMoveResult(
        state: state,
        success: false,
        failureReason: '試合は終了しています。',
      );
    }
    if (state.isRallyActive || state.pendingEscape != null) {
      return TechniqueMoveResult(
        state: state,
        success: false,
        failureReason: 'ラリー中・決着判定待ちの間はエネルギーをセットできません。',
      );
    }
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
    if (state.isOver) {
      return TechniqueMoveResult(
        state: state,
        success: false,
        failureReason: '試合は終了しています。',
      );
    }
    if (state.pendingEscape != null) {
      return TechniqueMoveResult(
        state: state,
        success: false,
        failureReason: '決着の判定待ちです。',
      );
    }
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
  ///
  /// Phase 6: 成立した技が`hasPinEffect`（フォール）／`hasSubmissionEffect`
  /// （ギブアップ）を持つ場合（`hasFinisherEffect`を持つ技は対象外。
  /// Phase 7でフィニッシャー専用の決着処理を実装するまでは通常の技として
  /// 扱う）、防御側の回避判定待ち（[TechniqueMatchState.pendingEscape]）へ
  /// 移行する。両方が立っている場合は仕様書どおりフォールを優先する。
  static TechniqueMatchState resolveHit(
    TechniqueMatchState state,
    TechniqueDeckCardCatalog catalog,
  ) {
    final pending = state.pendingAttack;
    if (pending == null) return state;
    final attackerIndex = pending.attackerIndex;
    final defenderIndex = 1 - attackerIndex;
    final attacker = state.playerAt(attackerIndex);
    final defender = state.playerAt(defenderIndex);
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

    final rallyEnded = state.copyWithRallyEnded(
      playerA: attackerIndex == 0 ? resolved.attacker : resolved.defender,
      playerB: attackerIndex == 1 ? resolved.attacker : resolved.defender,
      log: log,
    );

    if (!card.hasFinisherEffect &&
        (card.hasPinEffect || card.hasSubmissionEffect)) {
      final kind = card.hasPinEffect
          ? TechniqueEscapeKind.fall
          : TechniqueEscapeKind.giveUp;
      final kindLabel = kind == TechniqueEscapeKind.fall ? 'フォール' : 'ギブアップ';
      return rallyEnded.copyWith(
        pendingEscape: TechniquePendingEscape(
          attackerIndex: attackerIndex,
          defenderIndex: defenderIndex,
          cardId: card.id,
          kind: kind,
        ),
        log: [
          ...rallyEnded.log,
          '${resolved.defender.wrestlerName}は$kindLabelの危機！（回避判定待ち）',
        ],
      );
    }

    return rallyEnded;
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

  // ============================================================
  // Phase 6: フォール／ギブアップの回避判定
  // ============================================================
  //
  // 技が成立し `pendingEscape` がセットされている間、防御側は次の3種のうち
  // いずれかで回避できる（仕様書9・10章）。いずれも使わない（使えない）場合は
  // [concede] で明示的に敗北を認める。

  /// [pendingEscape] を、防御側の手札にあるキックアウト／ロープブレイクカード
  /// [entry] で回避できるかどうかを判定する（UIのボタン有効/無効判定用）。
  static ({bool canEscape, String? reason}) canEscapeWithDefenseCard(
    TechniqueMatchState state,
    TechniqueDeckEntry entry,
    TechniqueDeckCardCatalog catalog,
  ) {
    final pending = state.pendingEscape;
    if (pending == null) {
      return (canEscape: false, reason: '決着の判定待ちではありません。');
    }
    final defender = state.playerAt(pending.defenderIndex);
    if (!defender.hand.contains(entry)) {
      return (canEscape: false, reason: 'このカードは手札にありません。');
    }
    final card = catalog.findDefenseCardById(entry.cardId);
    if (card == null) {
      return (canEscape: false, reason: 'このカードは防御カードではありません。');
    }
    final requiredType = pending.kind == TechniqueEscapeKind.fall
        ? TechniqueDeckCardType.kickOut
        : TechniqueDeckCardType.ropeBreak;
    if (card.type != requiredType) {
      return (
        canEscape: false,
        reason: pending.kind == TechniqueEscapeKind.fall
            ? 'キックアウトカードが必要です。'
            : 'ロープブレイクカードが必要です。',
      );
    }
    // フォールでは通常キックアウトのみ有効（特殊キックアウトはフィニッシャー
    // 成立後専用、仕様書9.1章）。Phase 6ではフィニッシャー由来のフォールは
    // 発生しない（`hasFinisherEffect`が立つ技はPhase 6の対象外）。
    if (pending.kind == TechniqueEscapeKind.fall &&
        card.kickOutCategory != KickOutCardCategory.normal) {
      return (
        canEscape: false,
        reason: '通常のフォールには通常キックアウトカードのみ使用できます。',
      );
    }
    return (canEscape: true, reason: null);
  }

  /// キックアウト／ロープブレイクカードを使って回避する（成立後は捨て札へ）。
  /// 成功すればダメージ等の追加効果は発生せず、制御はそのまま
  /// `activePlayerIndex`のプレイヤーへ戻る。
  static TechniqueMoveResult escapeWithDefenseCard(
    TechniqueMatchState state,
    TechniqueDeckEntry entry,
    TechniqueDeckCardCatalog catalog,
  ) {
    final check = canEscapeWithDefenseCard(state, entry, catalog);
    if (!check.canEscape) {
      return TechniqueMoveResult(
        state: state,
        success: false,
        failureReason: check.reason,
      );
    }
    final pending = state.pendingEscape!;
    final defender = state.playerAt(pending.defenderIndex);
    final card = catalog.findDefenseCardById(entry.cardId)!;
    final newHand = List<TechniqueDeckEntry>.from(defender.hand)..remove(entry);
    final updatedDefender = defender.copyWith(
      hand: newHand,
      discardPile: [...defender.discardPile, entry],
    );
    final kindLabel = pending.kind == TechniqueEscapeKind.fall ? 'フォール' : 'ギブアップ';
    final log = [
      ...state.log,
      '${updatedDefender.wrestlerName}が「${card.name}」を使用し、$kindLabelを回避した',
    ];
    return TechniqueMoveResult(
      state: state.copyWith(
        playerA: pending.defenderIndex == 0 ? updatedDefender : state.playerA,
        playerB: pending.defenderIndex == 1 ? updatedDefender : state.playerB,
        pendingEscape: null,
        log: log,
      ),
      success: true,
    );
  }

  /// [pendingEscape] を、成立した技の`reversalEnergyCost`（Phase 5の返技と
  /// 同じフィールド）を消費して回避できるかどうかを判定する。
  static ({bool canEscape, String? reason}) canEscapeWithReversalEnergy(
    TechniqueMatchState state,
    TechniqueDeckCardCatalog catalog,
  ) {
    final pending = state.pendingEscape;
    if (pending == null) {
      return (canEscape: false, reason: '決着の判定待ちではありません。');
    }
    final defender = state.playerAt(pending.defenderIndex);
    final card = catalog.findTechniqueById(pending.cardId);
    if (card == null) {
      return (canEscape: false, reason: 'カードが見つかりません。');
    }
    for (final costEntry in card.reversalEnergyCost.entries) {
      if (costEntry.value <= 0) continue;
      if (defender.availableEnergyFor(costEntry.key) < costEntry.value) {
        return (
          canEscape: false,
          reason:
              '${moveAttributeLabel(costEntry.key)}の返技エネルギーが不足しています'
              '（必要${costEntry.value}、使用可能${defender.availableEnergyFor(costEntry.key)}）。',
        );
      }
    }
    return (canEscape: true, reason: null);
  }

  /// 返技エネルギーを消費して回避する。
  static TechniqueMoveResult escapeWithReversalEnergy(
    TechniqueMatchState state,
    TechniqueDeckCardCatalog catalog,
  ) {
    final check = canEscapeWithReversalEnergy(state, catalog);
    if (!check.canEscape) {
      return TechniqueMoveResult(
        state: state,
        success: false,
        failureReason: check.reason,
      );
    }
    final pending = state.pendingEscape!;
    final defender = state.playerAt(pending.defenderIndex);
    final card = catalog.findTechniqueById(pending.cardId)!;
    final spent = Map<MoveAttribute, int>.from(defender.spentEnergy);
    for (final costEntry in card.reversalEnergyCost.entries) {
      if (costEntry.value <= 0) continue;
      spent[costEntry.key] = (spent[costEntry.key] ?? 0) + costEntry.value;
    }
    final updatedDefender = defender.copyWith(spentEnergy: spent);
    final kindLabel = pending.kind == TechniqueEscapeKind.fall ? 'フォール' : 'ギブアップ';
    final log = [
      ...state.log,
      '${updatedDefender.wrestlerName}が返技エネルギーを消費し、$kindLabelを回避した',
    ];
    return TechniqueMoveResult(
      state: state.copyWith(
        playerA: pending.defenderIndex == 0 ? updatedDefender : state.playerA,
        playerB: pending.defenderIndex == 1 ? updatedDefender : state.playerB,
        pendingEscape: null,
        log: log,
      ),
      success: true,
    );
  }

  /// [pendingEscape] をHP消費で回避できるかどうかを判定する。フォールは
  /// `kickOutThreshold`／`kickOutHpRate`（現在HPに対する割合）、ギブアップは
  /// `giveUpThreshold`／`giveUpHpCost`（固定値、open questions 7番の決定）を
  /// 使う。しきい値未満のHPではこの方法は使えない（仕様書9・10章）。
  static ({bool canEscape, String? reason}) canEscapeWithHp(
    TechniqueMatchState state,
    TechniqueDeckCardCatalog catalog,
  ) {
    final pending = state.pendingEscape;
    if (pending == null) {
      return (canEscape: false, reason: '決着の判定待ちではありません。');
    }
    final defender = state.playerAt(pending.defenderIndex);
    final card = catalog.findTechniqueById(pending.cardId);
    if (card == null) {
      return (canEscape: false, reason: 'カードが見つかりません。');
    }
    if (pending.kind == TechniqueEscapeKind.fall) {
      final threshold = card.kickOutThreshold;
      final rate = card.kickOutHpRate;
      if (threshold == null || rate == null) {
        return (canEscape: false, reason: 'この技はHP消費によるキックアウトに対応していません。');
      }
      if (defender.hp < threshold) {
        return (
          canEscape: false,
          reason: 'HPが$threshold未満のため、HP消費によるキックアウトはできません（現在HP${defender.hp}）。',
        );
      }
      return (canEscape: true, reason: null);
    }
    final threshold = card.giveUpThreshold;
    final cost = card.giveUpHpCost;
    if (threshold == null || cost == null) {
      return (canEscape: false, reason: 'この技はHP消費によるギブアップ回避に対応していません。');
    }
    if (defender.hp < threshold) {
      return (
        canEscape: false,
        reason: 'HPが$threshold未満のため、HP消費によるギブアップ回避はできません（現在HP${defender.hp}）。',
      );
    }
    return (canEscape: true, reason: null);
  }

  /// HPを消費して回避する。HP0に到達しても回避自体は成功し、疲労状態へ
  /// 移行する（仕様書9章の暫定案を踏襲）。
  static TechniqueMoveResult escapeWithHp(
    TechniqueMatchState state,
    TechniqueDeckCardCatalog catalog,
  ) {
    final check = canEscapeWithHp(state, catalog);
    if (!check.canEscape) {
      return TechniqueMoveResult(
        state: state,
        success: false,
        failureReason: check.reason,
      );
    }
    final pending = state.pendingEscape!;
    final defender = state.playerAt(pending.defenderIndex);
    final card = catalog.findTechniqueById(pending.cardId)!;

    final int hpCost;
    final String kindLabel;
    if (pending.kind == TechniqueEscapeKind.fall) {
      hpCost = (defender.hp * card.kickOutHpRate!).round();
      kindLabel = 'フォール';
    } else {
      hpCost = card.giveUpHpCost!;
      kindLabel = 'ギブアップ';
    }
    final newHp = (defender.hp - hpCost).clamp(0, defender.maxHp);
    final becameFatigued =
        newHp <= 0 && defender.posture != WrestlerPosture.fatigued;
    final updatedDefender = defender.copyWith(
      hp: newHp,
      posture: becameFatigued ? WrestlerPosture.fatigued : defender.posture,
    );
    final log = [
      ...state.log,
      '${updatedDefender.wrestlerName}がHPを$hpCost消費し、$kindLabelを回避した'
          '（HP ${defender.hp} → $newHp）',
      if (becameFatigued) '${updatedDefender.wrestlerName}のHPが0になり、疲労状態になった',
    ];
    return TechniqueMoveResult(
      state: state.copyWith(
        playerA: pending.defenderIndex == 0 ? updatedDefender : state.playerA,
        playerB: pending.defenderIndex == 1 ? updatedDefender : state.playerB,
        pendingEscape: null,
        log: log,
      ),
      success: true,
    );
  }

  /// 防御側がキックアウト／ギブアップ回避を行わず（できず）、諦めて敗北を
  /// 認める。攻撃側の勝利として試合を終了させる（[TechniqueMatchState.winnerIndex]
  /// をセットする、エンジン初の勝敗確定処理）。
  static TechniqueMatchState concede(TechniqueMatchState state) {
    final pending = state.pendingEscape;
    if (pending == null) return state;
    final attacker = state.playerAt(pending.attackerIndex);
    final defender = state.playerAt(pending.defenderIndex);
    final kindLabel = pending.kind == TechniqueEscapeKind.fall ? 'フォール' : 'ギブアップ';
    final winReason = pending.kind == TechniqueEscapeKind.fall
        ? 'フォール勝利'
        : 'ギブアップ勝利';
    final log = [
      ...state.log,
      '${defender.wrestlerName}が$kindLabelを認めた。${attacker.wrestlerName}の$winReason！',
    ];
    return state.copyWith(
      pendingEscape: null,
      winnerIndex: pending.attackerIndex,
      winReason: winReason,
      log: log,
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
