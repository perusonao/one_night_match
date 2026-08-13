/// Combat Ver.1 Playable 1A — Match Snapshot
/// （docs/design/combat_v1_playable_match_ui.md 16章「Hidden Information /
/// Viewer Projection」）。
///
/// `CombatV1PlayableMatchController`がWidget/呼び出し側へ公開する、
/// hidden-safeなread-only projection。raw`CombatV1MatchState`は一切
/// 含まない——CPU（対戦相手）の手札の中身（cardInstanceId/cardId/カード名/
/// draw pileの内容/利用可能なCounter）はいかなるfieldにも現れない。
library;

import '../combat_v1_counter.dart';
import '../combat_v1_energy.dart';
import '../combat_v1_enums.dart';
import '../combat_v1_legal_action.dart';
import '../combat_v1_technique.dart';
import 'combat_v1_playable_action_feedback.dart';

/// [CombatV1PlayableMatchController]の定常状態
/// （docs/design/combat_v1_playable_match_ui.md 17章）。
///
/// 同期API（[CombatV1PlayableMatchController.submitHumanAction]等）は
/// 呼び出し内で完結するため、呼び出しが返った時点で外部から観測できる
/// statusは常にこの5値のいずれかで確定する（"CPU進行中"のような中間状態は
/// 外部から観測不可能なため、専用のstatusを持たない）。
enum CombatV1PlayableControllerStatus {
  /// 試合進行中（terminal・error状態のいずれでもない）。
  active,

  /// `CombatV1Engine`でwinnerが確定した正常終了。
  matchOver,

  /// ゲームは未終了だが、controller safety guard
  /// （[CombatV1PlayableMatchConfig.maxActions]）へ到達した。
  safetyLimit,

  /// state invariant違反、または非terminal stateでlegal actionが0件など、
  /// programming/invariant上の異常により停止した。
  invariantViolation,

  /// [CombatV1ActionExecutor.execute]が予期せず例外を送出した
  /// （snapshot由来のactionのみ受理するため通常到達しない防御的ケース）。
  error,
}

/// 手札1枚の物理カードのhidden-safe projection
/// （docs/design/combat_v1_playable_match_ui.md 16章）。
///
/// [technique]/[counter]はProduction Card Catalogの静的定義そのもの
/// （secretではない、印刷されたカードテキストに相当）。[category]に応じて
/// どちらか一方のみ非nullになる。
class CombatV1PlayableHandCard {
  const CombatV1PlayableHandCard({
    required this.instanceId,
    required this.cardId,
    required this.category,
    required this.displayName,
    required this.isUsable,
    this.technique,
    this.counter,
  });

  /// 物理カードのinstanceId（`CombatV1DeckEntry.instanceId`）。同名カードを
  /// 区別するcommand identityとして使う。
  final String instanceId;

  final String cardId;
  final CombatV1CardCategory category;
  final String displayName;

  /// 現在のlegal action snapshotに、このinstanceIdを使うactionが1件以上
  /// 含まれているか。
  final bool isUsable;

  /// `category != counter`の場合のみ非null。
  final CombatV1Technique? technique;

  /// `category == counter`の場合のみ非null。
  final CombatV1Counter? counter;
}

/// Human（playerIndex 0）のhidden-safe status projection
/// （docs/design/combat_v1_playable_match_ui.md 16章）。
class CombatV1PlayableHumanStatus {
  const CombatV1PlayableHumanStatus({
    required this.wrestlerId,
    required this.wrestlerName,
    required this.hp,
    required this.maxHp,
    required this.koc,
    required this.posture,
    required this.hand,
    required this.handCount,
    required this.drawPileCount,
    required this.discardPileCount,
    required this.pinCardsHeld,
    required this.reshuffleCount,
    required this.energyPool,
    required this.availableEnergy,
  });

  final String wrestlerId;
  final String wrestlerName;
  final int hp;
  final int maxHp;
  final int koc;
  final CombatV1WrestlerPosture posture;

  /// Humanの手札全件（自分の手札なのでhidden情報ではない）。
  final List<CombatV1PlayableHandCard> hand;
  final int handCount;
  final int drawPileCount;
  final int discardPileCount;
  final int pinCardsHeld;
  final int reshuffleCount;

  /// このレスラー固有の固定ENERGYプール（`CombatV1PlayerState.energyPool`
  /// をそのまま公開する。保有量そのものであり、ターン内で変化しない
  /// ——docs/combat_rules_v1.md 5章、Playable 1C.1「Energy Semantics」）。
  /// Human自身のENERGYなのでhidden情報ではない。
  final CombatV1EnergyPool energyPool;

  /// 現在使用可能な（[energyPool]から自ターン内の使用済み分を引いた）
  /// 属性別ENERGY残量（`CombatV1PlayerState.availableEnergyFor`と同じ値。
  /// 自ターン開始時に[energyPool]と同値へ全回復する、Playable
  /// 1C.1「Energy Semantics」）。
  final Map<CombatV1EnergyAttribute, int> availableEnergy;
}

/// CPU（対戦相手、playerIndex 1）のhidden-safe status projection
/// （docs/design/combat_v1_playable_match_ui.md 16章）。
///
/// **絶対に含めない**: CPU手札のcardInstanceId・cardId・カード名・
/// draw pileの内容・現在利用可能なCPU counter。
class CombatV1PlayableOpponentStatus {
  const CombatV1PlayableOpponentStatus({
    required this.wrestlerId,
    required this.wrestlerName,
    required this.hp,
    required this.maxHp,
    required this.koc,
    required this.posture,
    required this.handCount,
    required this.drawPileCount,
    required this.discardPileCount,
    required this.pinCardsHeld,
    required this.reshuffleCount,
  });

  final String wrestlerId;
  final String wrestlerName;
  final int hp;
  final int maxHp;
  final int koc;
  final CombatV1WrestlerPosture posture;

  final int handCount;
  final int drawPileCount;
  final int discardPileCount;
  final int pinCardsHeld;
  final int reshuffleCount;
}

/// 応答待ちの攻撃（`counterResponsePending`）のhidden-safe projection
/// （docs/design/combat_v1_playable_match_ui.md 16章）。
///
/// 宣言済みの攻撃カードは既に両者へ公開された情報のため、この投影は
/// hidden information違反にならない。
class CombatV1PlayablePendingAttackView {
  const CombatV1PlayablePendingAttackView({
    required this.attackerPlayerIndex,
    required this.defenderPlayerIndex,
    required this.attackCardInstanceId,
    required this.cardId,
    required this.displayName,
    required this.category,
    required this.attribute,
    required this.family,
    required this.damage,
    required this.resultOpponentState,
    required this.energyCostTotal,
    required this.heatGain,
    required this.directPin,
    required this.submissionHold,
    this.finisherType,
  });

  final int attackerPlayerIndex;
  final int defenderPlayerIndex;
  final String attackCardInstanceId;
  final String cardId;
  final String displayName;
  final CombatV1CardCategory category;
  final CombatV1EnergyAttribute attribute;
  final CombatV1TechniqueFamily family;
  final int damage;
  final CombatV1WrestlerPosture? resultOpponentState;

  /// この攻撃のENERGY COST合計（`CombatV1EnergyCost.total`）。COUNTERの
  /// 動的必要量（docs/combat_rules_v1.md 7章「返し必要コストは、返される側の
  /// TECHNIQUEのENERGY COST『総量』と同値」）と同じ値——宣言済みの攻撃の
  /// 静的metadataなので、既に両者へ公開された情報（hidden information
  /// 違反にならない）。
  final int energyCostTotal;

  /// Playable 2A-3「Counter Response — Incoming Attack Summary」——
  /// この攻撃が成立した場合に加算されるShared HEAT（`CombatV1PendingAttack.heatGain`
  /// をそのまま公開する）。宣言済みTECHNIQUEの静的metadataであり、
  /// [energyCostTotal]と同じ理由でhidden information違反にならない。
  final int heatGain;

  /// この攻撃技自体のPIN/SUBMISSION関連フラグ（`CombatV1PendingAttack.directPin`/
  /// `submissionHold`をそのまま複製）。`category == finisher`の場合は、
  /// この値ではなく[finisherType]が実際の決着方式を決める——
  /// `CombatV1Technique.directPin`/`submissionHold`と同じ優先順位ルール
  /// （combat_v1_engine.dart `_resolvePendingAttack`のeffectiveDirectPin/
  /// effectiveSubmissionHoldと同じ、docs/design/combat_v1_phase1_design.md
  /// 2.4章）。呼び出し側は`combatV1PlayablePendingAttackHasEffectiveDirectPin`/
  /// `combatV1PlayablePendingAttackHasEffectiveSubmissionHold`
  /// （`combat_v1_playable_technique_traits.dart`）経由でこの優先順位を
  /// 安全に解決すること——[directPin]/[submissionHold]を単独で読まない。
  final bool directPin;
  final bool submissionHold;

  /// FINISHERの決着方式（`CombatV1PendingAttack.finisherType`をそのまま
  /// 公開）。`category == finisher`の場合のみ非null。
  final CombatV1FinisherType? finisherType;
}

/// 過去に成功実行された1件のpublic actionの、bounded recent
/// observation（docs/design/combat_v1_playable_match_ui.md 16章）。
///
/// raw`CombatV1MatchState`（`stateBefore`/`stateAfter`）は保持しない——
/// 実行された[action]自体（宣言・discard・counter使用）は既に「公開された
/// action」であるため、これを見せることはhidden information違反に
/// ならない。
class CombatV1PlayableObservation {
  const CombatV1PlayableObservation({
    required this.actionIndex,
    required this.turnNumber,
    required this.actorPlayerIndex,
    required this.action,
  });

  /// この試合内で0始まりの、成功したpublic actionの通し番号。
  final int actionIndex;

  /// [action]実行時点の`turnNumber`。
  final int turnNumber;

  final int actorPlayerIndex;
  final CombatV1LegalAction action;
}

/// `CombatV1PlayableMatchController`がWidget/呼び出し側へ公開する
/// hidden-safeなread-only snapshot
/// （docs/design/combat_v1_playable_match_ui.md 16章）。
class CombatV1PlayableMatchSnapshot {
  const CombatV1PlayableMatchSnapshot({
    required this.revision,
    required this.turnNumber,
    required this.phase,
    required this.status,
    required this.currentActorPlayerIndex,
    required this.isHumanInputRequired,
    required this.isMatchOver,
    required this.sharedHeat,
    required this.finisherHeatThreshold,
    required this.submissionHpThreshold,
    required this.actionCount,
    required this.maxActions,
    required this.legalActions,
    required this.human,
    required this.cpu,
    required this.pendingAttack,
    required this.recentObservations,
    this.diagnosticMessage,
    this.latestFeedback,
    this.recentFeedback = const [],
  });

  /// controller独自のmonotonic revision（stale action検出専用、
  /// docs/design/combat_v1_playable_match_ui.md 14章）。
  final int revision;

  final int turnNumber;
  final CombatV1MatchPhase phase;
  final CombatV1PlayableControllerStatus status;

  /// 現在のactor（8章参照）。terminal/error時は`null`。
  final int? currentActorPlayerIndex;

  /// `status == active && currentActorPlayerIndex == humanPlayerIndex`。
  final bool isHumanInputRequired;

  final bool isMatchOver;

  final int sharedHeat;
  final int finisherHeatThreshold;

  /// 通常SUBMISSIONへ自動移行できる相手HPの上限
  /// （[CombatV1RulesConfig.submissionHpThreshold]をそのまま公開、
  /// docs/combat_rules_v1.md 10.1章「相手HP50以下で宣言可能」）。
  ///
  /// [finisherHeatThreshold]と同じ理由（Playable 2A-2「Win Path / Match
  /// Direction」、`combat_v1_playable_match_direction.dart`）でsnapshotへ
  /// 追加した——既に`CombatV1RulesConfig`上でpublicなrule定数を、UI側で
  /// magic number（50）として複製しないための公開。Core rule・値そのものは
  /// 一切変更していない。
  final int submissionHpThreshold;

  final int actionCount;
  final int maxActions;

  /// Humanの手番の場合のみ非空（9章）。CPUの手番中は常に空リスト
  /// ——`cardInstanceId`を含むLegalActionをCPUの手番中に公開すると、
  /// CPU手札の中身が漏洩するため。
  final List<CombatV1LegalAction> legalActions;

  final CombatV1PlayableHumanStatus human;
  final CombatV1PlayableOpponentStatus cpu;

  /// `phase == counterResponsePending`の間のみ非null。
  final CombatV1PlayablePendingAttackView? pendingAttack;

  /// 直近のobservation（bounded、O(totalActions)保持にしない）。
  final List<CombatV1PlayableObservation> recentObservations;

  /// `status`が`error`/`invariantViolation`の場合のみ非null。
  final String? diagnosticMessage;

  /// 直近1件のaction feedback（Playable 1C「Action Feedback Model」）。
  /// 試合開始直後（まだ1件もactionが実行されていない）場合のみ`null`。
  final CombatV1PlayableActionFeedback? latestFeedback;

  /// 直近のaction feedback（bounded、[recentObservations]と同じ保持件数。
  /// O(totalActions)保持にしない）。末尾が最新（[latestFeedback]と同じ
  /// 値）。
  final List<CombatV1PlayableActionFeedback> recentFeedback;
}
