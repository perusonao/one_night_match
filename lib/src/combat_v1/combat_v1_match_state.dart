/// 試合状態モデル（docs/combat_rules_v1.md 2章、
/// docs/design/combat_v1_phase1_design.md 2.2章）。
library;

import 'combat_v1_deck.dart';
import 'combat_v1_energy.dart';
import 'combat_v1_enums.dart';
import 'combat_v1_pending_attack.dart';
import 'combat_v1_successful_technique_snapshot.dart';

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
    this.roughTechniqueUsedThisTurn = false,
    this.roughTechniqueLimitActive = false,
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

  /// このターン、attribute==roughのTECHNIQUEを1枚でも宣言したか
  /// （docs/combat_rules_v1.md 15章「ROUGH属性TECHNIQUEを1枚でも使用した
  /// ターンはPINできない」、Phase 8）。COUNTERされても値は変化しない
  /// （宣言＝`techniquesUsedThisTurn`と同じ「使用」基準、Phase
  /// 8セッションでユーザーが確定した方針）。`checkPinLegality`
  /// （通常PINのみ）が参照する。DIRECT PINはこの値を参照しない（Phase
  /// 8で確定：DIRECT PINはROUGH-PIN不可ルールの対象外）。ターン開始時に
  /// falseへ戻る。
  final bool roughTechniqueUsedThisTurn;

  /// このターン、ROUGHによる「TECHNIQUE最大1枚」制限を受けているか
  /// （docs/combat_rules_v1.md 15章、Phase
  /// 8）。相手が直前の自ターンをROUGH技の成功（`lastSuccessfulTechnique`）
  /// で終えた場合にtrueとなる。COUNTER・REST・起き上がりはこの上限に
  /// 含めない。そのターンの終了とともに（消費の有無に関わらず）falseへ
  /// 戻る（Phase 8セッションでユーザーが確定した方針。持ち越しは行わない）。
  final bool roughTechniqueLimitActive;

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
    bool? roughTechniqueUsedThisTurn,
    bool? roughTechniqueLimitActive,
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
    roughTechniqueUsedThisTurn:
        roughTechniqueUsedThisTurn ?? this.roughTechniqueUsedThisTurn,
    roughTechniqueLimitActive:
        roughTechniqueLimitActive ?? this.roughTechniqueLimitActive,
  );
}

/// 試合全体の不変状態。
///
/// `winner`/`isOver`はPhase 1〜4では持たなかった（決着条件が一切
/// 存在しなかったため。docs/design/combat_v1_phase1_design.md
/// 2.6章）。Phase 5でPINによる決着（KOC不足による3カウント、
/// docs/combat_rules_v1.md 8.2章）が初めて発生しうるため、[winnerPlayerIndex]
/// を正式に追加した。
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
    this.lastSuccessfulTechnique,
    this.winnerPlayerIndex,
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

  /// 直近で成立した（COUNTERされずにdeclineで解決した）TECHNIQUEの
  /// snapshot（Phase 4 Codexレビュー指摘H2/H3対応）。試合開始時null、
  /// declineによる攻撃成立ごとに更新される。COUNTER成立時は更新しない
  /// （既存値も上書きしない）。ターン開始時にもclearしない
  /// （match-level情報として保持し、Phase 5/6/9等が解決直後に参照できる
  /// ようにするため。`combat_v1_successful_technique_snapshot.dart`
  /// 参照）。
  final CombatV1SuccessfulTechniqueSnapshot? lastSuccessfulTechnique;

  /// 試合の勝者（`0`=playerA、`1`=playerB）。試合が決着していなければ
  /// `null`（Phase 5で新規追加。docs/combat_rules_v1.md 8.2章「必要なKOCを
  /// 支払えなければ3カウントとなり、PIN決着」）。[lastSuccessfulTechnique]と
  /// 同じく一方向（null→非null）にのみ更新する（勝者が決まった試合が
  /// 再びnullへ戻ることはない）。
  final int? winnerPlayerIndex;

  /// 試合が決着しているか（[winnerPlayerIndex]から導出、勝者名stringの
  /// 重複保存はしない）。
  bool get isOver => winnerPlayerIndex != null;

  CombatV1PlayerState get active =>
      activePlayerIndex == 0 ? playerA : playerB;

  CombatV1PlayerState get opponent =>
      activePlayerIndex == 0 ? playerB : playerA;

  /// [pendingAttack]は明示的に渡した値だけを反映する（省略時は既存値を
  /// 維持）。`counterResponsePending`を抜けてpendingを消す場合は
  /// [clearPendingAttack]を使う（`null`を「省略」と区別できないため）。
  /// [lastSuccessfulTechnique]・[winnerPlayerIndex]は一方向（null→非null）
  /// にのみ更新するため（13章、および本ファイル冒頭コメント）、同じ`??`
  /// パターンで問題ない（クリア用の別メソッドは不要）。
  CombatV1MatchState copyWith({
    CombatV1PlayerState? playerA,
    CombatV1PlayerState? playerB,
    int? activePlayerIndex,
    int? sharedHeat,
    int? turnNumber,
    CombatV1MatchPhase? phase,
    List<String>? log,
    CombatV1PendingAttack? pendingAttack,
    CombatV1SuccessfulTechniqueSnapshot? lastSuccessfulTechnique,
    int? winnerPlayerIndex,
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
    lastSuccessfulTechnique:
        lastSuccessfulTechnique ?? this.lastSuccessfulTechnique,
    winnerPlayerIndex: winnerPlayerIndex ?? this.winnerPlayerIndex,
  );

  /// [pendingAttack]を`null`へ戻した新しいstateを返す（COUNTER成功/decline
  /// でpendingを解消する際に使う）。[lastSuccessfulTechnique]など他の
  /// fieldはすべて維持する。
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
    lastSuccessfulTechnique: lastSuccessfulTechnique,
    winnerPlayerIndex: winnerPlayerIndex,
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
