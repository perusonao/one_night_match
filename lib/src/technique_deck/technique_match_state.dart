import 'dart:math';

import 'technique_deck_deck.dart';
import 'technique_deck_models.dart';

/// Technique Deck Rules Phase 3: 最小限の試合状態管理。
///
/// 技の使用・ダメージ・返技・連続攻撃・フォール／ギブアップ・フィニッシャー・
/// CPUは一切実装しない（Phase 4以降）。ここで扱うのは、スタンド／ダウン／
/// 疲労・休息・ターン進行（開始→ドロー→エネルギーセット→終了）・HP／HEAT
/// の表示・手札5枚・山札／捨て札のみ。既存の `LevelMatchEngine`
/// （classic/energy）とは完全に独立しており、一切の変更・依存を持たない。

/// ターンの進行段階。技の使用（メインアクション）はPhase 4以降のため、
/// ここには含めない。
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

  final List<TechniqueDeckEntry> drawPile;
  final List<TechniqueDeckEntry> hand;
  final List<TechniqueDeckEntry> discardPile;

  TechniqueMatchPlayerState copyWith({
    int? hp,
    int? heat,
    WrestlerPosture? posture,
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
    if (nextPlayer.posture == WrestlerPosture.down) {
      nextPlayer = nextPlayer.copyWith(posture: WrestlerPosture.stand);
      log.add('${nextPlayer.wrestlerName}がスタンド状態に戻った');
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
}
