/// 試合状態モデル（docs/combat_rules_v1.md 2章、
/// docs/design/combat_v1_phase1_design.md 2.2章）。
library;

import 'combat_v1_deck.dart';
import 'combat_v1_energy.dart';
import 'combat_v1_enums.dart';
import 'combat_v1_pending_attack.dart';

/// 1人のプレイヤー（レスラー）の試合内状態。不変オブジェクト。
class CombatV1PlayerState {
  const CombatV1PlayerState({
    required this.wrestlerId,
    required this.wrestlerName,
    required this.maxHp,
    required this.hp,
    required this.koc,
    required this.pinCardsHeld,
    this.posture = CombatV1WrestlerPosture.stand,
    this.energyPool = const CombatV1EnergyPool({}),
    this.spentEnergy = const {},
    this.drawPile = const [],
    this.hand = const [],
    this.discardPile = const [],
    this.reshuffleCount = 0,
    this.techniquesUsedThisTurn = 0,
  });

  final String wrestlerId;
  final String wrestlerName;
  final int maxHp;
  final int hp;

  /// KOC（初期値10、docs/combat_rules_v1.md 9章）。Phase 1では消費ロジックを
  /// 実装せず、初期化のみを対象とする。
  final int koc;

  /// 保有PINカード枚数（初期値2、docs/combat_rules_v1.md 8.1章）。Phase 1
  /// では移動ロジックを実装せず、初期化のみを対象とする。
  final int pinCardsHeld;

  final CombatV1WrestlerPosture posture;

  /// このプレイヤー固有の固定ENERGYプール。
  final CombatV1EnergyPool energyPool;

  /// 今サイクルで使用済みのENERGY（属性別）。自ターン開始時に空へ戻る。
  final Map<CombatV1EnergyAttribute, int> spentEnergy;

  final List<CombatV1DeckEntry> drawPile;
  final List<CombatV1DeckEntry> hand;
  final List<CombatV1DeckEntry> discardPile;

  /// 山札切れ→捨て札再構築を行った回数（ログ／解析用、
  /// docs/combat_rules_v1.md 16章）。
  final int reshuffleCount;

  /// このターンで使用したTECHNIQUEの枚数。ROUGH実装（Phase 8）で、次ターン
  /// の相手のTECHNIQUE使用枚数制限判定に使う想定（COUNTER/REST/起き上がりは
  /// 含めない、docs/combat_rules_v1.md 15章）。ターン開始時に0へ戻る。
  final int techniquesUsedThisTurn;

  /// 現在使用可能な（保有量から使用済みを引いた）指定属性のENERGY残量。
  int availableEnergyFor(CombatV1EnergyAttribute attribute) =>
      energyPool.amountFor(attribute) - (spentEnergy[attribute] ?? 0);

  CombatV1PlayerState copyWith({
    int? hp,
    int? koc,
    int? pinCardsHeld,
    CombatV1WrestlerPosture? posture,
    Map<CombatV1EnergyAttribute, int>? spentEnergy,
    List<CombatV1DeckEntry>? drawPile,
    List<CombatV1DeckEntry>? hand,
    List<CombatV1DeckEntry>? discardPile,
    int? reshuffleCount,
    int? techniquesUsedThisTurn,
  }) => CombatV1PlayerState(
    wrestlerId: wrestlerId,
    wrestlerName: wrestlerName,
    maxHp: maxHp,
    hp: hp ?? this.hp,
    koc: koc ?? this.koc,
    pinCardsHeld: pinCardsHeld ?? this.pinCardsHeld,
    posture: posture ?? this.posture,
    energyPool: energyPool,
    spentEnergy: spentEnergy ?? this.spentEnergy,
    drawPile: drawPile ?? this.drawPile,
    hand: hand ?? this.hand,
    discardPile: discardPile ?? this.discardPile,
    reshuffleCount: reshuffleCount ?? this.reshuffleCount,
    techniquesUsedThisTurn:
        techniquesUsedThisTurn ?? this.techniquesUsedThisTurn,
  );
}

/// 試合全体の不変状態。
///
/// `winner`/`isOver`はPhase 1では持たない（Phase 1には決着条件が一切
/// 存在しないため。docs/design/combat_v1_phase1_design.md 2.6章）。
class CombatV1MatchState {
  const CombatV1MatchState({
    required this.matchId,
    required this.playerA,
    required this.playerB,
    this.activePlayerIndex = 0,
    this.sharedHeat = 0,
    this.turnNumber = 1,
    this.phase = CombatV1MatchPhase.setup,
    this.log = const [],
    this.pendingAttack,
  });

  final String matchId;
  final CombatV1PlayerState playerA;
  final CombatV1PlayerState playerB;

  /// 0=playerA、1=playerBが手番プレイヤー。COUNTER成立/decline問わず、
  /// `phase == counterResponsePending`の間も含めて宣言した攻撃側のまま
  /// 変化しない（docs/combat_rules_v1.md 7.1章）。
  final int activePlayerIndex;

  /// 両者共有のHEAT（docs/combat_rules_v1.md 12章）。消費されない。
  final int sharedHeat;

  final int turnNumber;
  final CombatV1MatchPhase phase;

  /// 人間可読なログ（既存①②③と同じ慣習）。
  final List<String> log;

  /// 宣言済みだが未解決の攻撃TECHNIQUE（`phase ==
  /// counterResponsePending`の間のみ非null、docs/combat_rules_v1.md
  /// 7.1章「PendingAttack・counterResponsePending」）。
  final CombatV1PendingAttack? pendingAttack;

  CombatV1PlayerState get active =>
      activePlayerIndex == 0 ? playerA : playerB;

  CombatV1PlayerState get opponent =>
      activePlayerIndex == 0 ? playerB : playerA;

  /// [pendingAttack]は明示的に渡した値だけを反映する（省略時は既存値を
  /// 維持）。`counterResponsePending`を抜けてpendingを消す場合は
  /// [clearPendingAttack]を使う（`null`を「省略」と区別できないため）。
  CombatV1MatchState copyWith({
    CombatV1PlayerState? playerA,
    CombatV1PlayerState? playerB,
    int? activePlayerIndex,
    int? sharedHeat,
    int? turnNumber,
    CombatV1MatchPhase? phase,
    List<String>? log,
    CombatV1PendingAttack? pendingAttack,
  }) => CombatV1MatchState(
    matchId: matchId,
    playerA: playerA ?? this.playerA,
    playerB: playerB ?? this.playerB,
    activePlayerIndex: activePlayerIndex ?? this.activePlayerIndex,
    sharedHeat: sharedHeat ?? this.sharedHeat,
    turnNumber: turnNumber ?? this.turnNumber,
    phase: phase ?? this.phase,
    log: log ?? this.log,
    pendingAttack: pendingAttack ?? this.pendingAttack,
  );

  /// [pendingAttack]を`null`へ戻した新しいstateを返す（COUNTER成功/decline
  /// でpendingを解消する際に使う）。
  CombatV1MatchState clearPendingAttack() => CombatV1MatchState(
    matchId: matchId,
    playerA: playerA,
    playerB: playerB,
    activePlayerIndex: activePlayerIndex,
    sharedHeat: sharedHeat,
    turnNumber: turnNumber,
    phase: phase,
    log: log,
    pendingAttack: null,
  );

  /// 手番プレイヤー（[active]）を更新した新しいstateを返す。
  CombatV1MatchState withActive(CombatV1PlayerState updated) =>
      activePlayerIndex == 0
      ? copyWith(playerA: updated)
      : copyWith(playerB: updated);

  /// 非手番プレイヤー（[opponent]）を更新した新しいstateを返す。
  CombatV1MatchState withOpponent(CombatV1PlayerState updated) =>
      activePlayerIndex == 0
      ? copyWith(playerB: updated)
      : copyWith(playerA: updated);
}
