// Combat Ver.1 Playable 1B widget test共通fixture。
//
// `_test.dart`という命名ではないため、`flutter test`から直接テスト
// スイートとして実行されない（Playable 1Aの
// `combat_v1_playable_test_helpers.dart`と同じ方針）。実Engineを一切
// 経由せず、`CombatV1PlayableMatchSnapshot`等のpublic constructor（値
// object）だけを使ってsynthetic snapshotを組み立てる——widget test側で
// legality等を再実装しない（design doc「79〜86章」の"Synthetic/fake
// snapshot"方針）。

import 'package:one_night_match/src/combat_v1/combat_v1_counter.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_legal_action.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_lifecycle.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_action_feedback.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_controller.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_result.dart';
import 'package:one_night_match/src/combat_v1/playable/combat_v1_playable_match_snapshot.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_match_session.dart';

const CombatV1Technique testNormalTechnique = CombatV1Technique(
  id: 'test_normal_strike',
  name: 'テストストライク',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.strike,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
  damage: 20,
  heatGain: 10,
  family: CombatV1TechniqueFamily.elbow,
);

const CombatV1Technique testFinisherTechnique = CombatV1Technique(
  id: 'test_finisher',
  name: 'テストフィニッシャー',
  category: CombatV1CardCategory.finisher,
  attribute: CombatV1EnergyAttribute.throwing,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 2}),
  damage: 60,
  heatGain: 0,
  family: CombatV1TechniqueFamily.powerbomb,
  finisherType: CombatV1FinisherType.normal,
);

final CombatV1Counter testCounter = CombatV1Counter(
  id: 'test_counter',
  name: 'テストカウンター',
  attribute: CombatV1EnergyAttribute.strike,
  counterableFamilies: const [CombatV1TechniqueFamily.elbow],
);

CombatV1PlayableHandCard testTechniqueCard({
  String instanceId = 'human-technique-1',
  bool isUsable = true,
  CombatV1Technique technique = testNormalTechnique,
}) => CombatV1PlayableHandCard(
  instanceId: instanceId,
  cardId: technique.id,
  category: technique.category,
  displayName: technique.name,
  isUsable: isUsable,
  technique: technique,
);

CombatV1PlayableHandCard testCounterCard({
  String instanceId = 'human-counter-1',
  bool isUsable = true,
}) => CombatV1PlayableHandCard(
  instanceId: instanceId,
  cardId: testCounter.id,
  category: CombatV1CardCategory.counter,
  displayName: testCounter.name,
  isUsable: isUsable,
  counter: testCounter,
);

/// docs/combat_rules_v1.md 5章のアカリEnergy配分例（打5／関1／投2／飛2／
/// ラフ0／＊1）をそのままtest既定値に使う——テスト側で新しい配分を発明
/// しない。
const CombatV1EnergyPool testEnergyPool = CombatV1EnergyPool({
  CombatV1EnergyAttribute.strike: 5,
  CombatV1EnergyAttribute.joint: 1,
  CombatV1EnergyAttribute.throwing: 2,
  CombatV1EnergyAttribute.aerial: 2,
  CombatV1EnergyAttribute.rough: 0,
  CombatV1EnergyAttribute.wild: 1,
});

CombatV1PlayableHumanStatus testHumanStatus({
  String wrestlerId = 'akari',
  String wrestlerName = 'テストあかり',
  int hp = 120,
  int maxHp = 150,
  int koc = 10,
  CombatV1WrestlerPosture posture = CombatV1WrestlerPosture.stand,
  List<CombatV1PlayableHandCard>? hand,
  int drawPileCount = 10,
  int discardPileCount = 2,
  int pinCardsHeld = 2,
  int reshuffleCount = 0,
  CombatV1EnergyPool energyPool = testEnergyPool,
  Map<CombatV1EnergyAttribute, int>? availableEnergy,
}) {
  final resolvedHand = hand ?? [testTechniqueCard()];
  return CombatV1PlayableHumanStatus(
    wrestlerId: wrestlerId,
    wrestlerName: wrestlerName,
    hp: hp,
    maxHp: maxHp,
    koc: koc,
    posture: posture,
    hand: resolvedHand,
    handCount: resolvedHand.length,
    drawPileCount: drawPileCount,
    discardPileCount: discardPileCount,
    pinCardsHeld: pinCardsHeld,
    reshuffleCount: reshuffleCount,
    energyPool: energyPool,
    // 既定では未使用（pool全量が利用可能）——自ターン開始直後の状態と
    // 同じにする。呼び出し側が個別に消費済み量を渡したい場合のみ
    // `availableEnergy`を明示する。
    availableEnergy:
        availableEnergy ??
        {
          for (final attribute in CombatV1EnergyAttribute.values)
            attribute: energyPool.amountFor(attribute),
        },
  );
}

CombatV1PlayableOpponentStatus testCpuStatus({
  String wrestlerId = 'reina',
  String wrestlerName = 'テストレイナ',
  int hp = 100,
  int maxHp = 150,
  int koc = 9,
  CombatV1WrestlerPosture posture = CombatV1WrestlerPosture.stand,
  int handCount = 5,
  int drawPileCount = 8,
  int discardPileCount = 3,
  int pinCardsHeld = 2,
  int reshuffleCount = 0,
}) => CombatV1PlayableOpponentStatus(
  wrestlerId: wrestlerId,
  wrestlerName: wrestlerName,
  hp: hp,
  maxHp: maxHp,
  koc: koc,
  posture: posture,
  handCount: handCount,
  drawPileCount: drawPileCount,
  discardPileCount: discardPileCount,
  pinCardsHeld: pinCardsHeld,
  reshuffleCount: reshuffleCount,
);

CombatV1PlayablePendingAttackView testPendingAttack({
  int attackerPlayerIndex = 1,
  int defenderPlayerIndex = 0,
  String attackCardInstanceId = 'cpu-attack-1',
  CombatV1Technique technique = testNormalTechnique,
  CombatV1WrestlerPosture? resultOpponentState,
  int? energyCostTotal,
}) => CombatV1PlayablePendingAttackView(
  attackerPlayerIndex: attackerPlayerIndex,
  defenderPlayerIndex: defenderPlayerIndex,
  attackCardInstanceId: attackCardInstanceId,
  cardId: technique.id,
  displayName: technique.name,
  category: technique.category,
  attribute: technique.attribute,
  family: technique.family,
  damage: technique.damage,
  resultOpponentState: resultOpponentState,
  energyCostTotal: energyCostTotal ?? technique.energyCost.total,
);

CombatV1PlayableObservation testObservation({
  int actionIndex = 0,
  int turnNumber = 1,
  int actorPlayerIndex = 0,
  CombatV1LegalAction? action,
}) => CombatV1PlayableObservation(
  actionIndex: actionIndex,
  turnNumber: turnNumber,
  actorPlayerIndex: actorPlayerIndex,
  action: action ?? const CombatV1EndTurnAction(actorPlayerIndex: 0),
);

CombatV1PlayableActionFeedback testActionFeedback({
  int actionIndex = 0,
  int turnNumber = 1,
  CombatV1PlayableFeedbackKind kind = CombatV1PlayableFeedbackKind.techniqueResolved,
  int actorPlayerIndex = 0,
  int? opponentPlayerIndex = 1,
  String? actionDisplayName = 'テストストライク',
  String? relatedActionDisplayName,
  int? damage,
  int? hpOwnerPlayerIndex,
  int? hpBefore,
  int? hpAfter,
  int? postureOwnerPlayerIndex,
  CombatV1WrestlerPosture? postureBefore,
  CombatV1WrestlerPosture? postureAfter,
  int? heatBefore,
  int? heatAfter,
  int? kocOwnerPlayerIndex,
  int? kocBefore,
  int? kocAfter,
  CombatV1PlayablePinFeedbackOutcome? pinOutcome,
  CombatV1PlayableSubmissionFeedbackOutcome? submissionOutcome,
}) => CombatV1PlayableActionFeedback(
  actionIndex: actionIndex,
  turnNumber: turnNumber,
  kind: kind,
  actorPlayerIndex: actorPlayerIndex,
  opponentPlayerIndex: opponentPlayerIndex,
  actionDisplayName: actionDisplayName,
  relatedActionDisplayName: relatedActionDisplayName,
  damage: damage,
  hpOwnerPlayerIndex: hpOwnerPlayerIndex,
  hpBefore: hpBefore,
  hpAfter: hpAfter,
  postureOwnerPlayerIndex: postureOwnerPlayerIndex,
  postureBefore: postureBefore,
  postureAfter: postureAfter,
  heatBefore: heatBefore,
  heatAfter: heatAfter,
  kocOwnerPlayerIndex: kocOwnerPlayerIndex,
  kocBefore: kocBefore,
  kocAfter: kocAfter,
  pinOutcome: pinOutcome,
  submissionOutcome: submissionOutcome,
);

CombatV1PlayableMatchSnapshot testSnapshot({
  int revision = 0,
  int turnNumber = 1,
  CombatV1MatchPhase phase = CombatV1MatchPhase.action,
  CombatV1PlayableControllerStatus status =
      CombatV1PlayableControllerStatus.active,
  int? currentActorPlayerIndex = CombatV1PlayableMatchController.humanPlayerIndex,
  bool isHumanInputRequired = true,
  bool isMatchOver = false,
  int sharedHeat = 0,
  int finisherHeatThreshold = 200,
  int submissionHpThreshold = 50,
  int actionCount = 0,
  int maxActions = 500,
  List<CombatV1LegalAction> legalActions = const [],
  CombatV1PlayableHumanStatus? human,
  CombatV1PlayableOpponentStatus? cpu,
  CombatV1PlayablePendingAttackView? pendingAttack,
  List<CombatV1PlayableObservation> recentObservations = const [],
  String? diagnosticMessage,
  CombatV1PlayableActionFeedback? latestFeedback,
  List<CombatV1PlayableActionFeedback> recentFeedback = const [],
}) => CombatV1PlayableMatchSnapshot(
  revision: revision,
  turnNumber: turnNumber,
  phase: phase,
  status: status,
  currentActorPlayerIndex: currentActorPlayerIndex,
  isHumanInputRequired: isHumanInputRequired,
  isMatchOver: isMatchOver,
  sharedHeat: sharedHeat,
  finisherHeatThreshold: finisherHeatThreshold,
  submissionHpThreshold: submissionHpThreshold,
  actionCount: actionCount,
  maxActions: maxActions,
  legalActions: legalActions,
  human: human ?? testHumanStatus(),
  cpu: cpu ?? testCpuStatus(),
  pendingAttack: pendingAttack,
  recentObservations: recentObservations,
  diagnosticMessage: diagnosticMessage,
  latestFeedback: latestFeedback,
  recentFeedback: recentFeedback,
);

CombatV1PlayableMatchResult testResult({
  CombatV1PlayableControllerStatus status =
      CombatV1PlayableControllerStatus.matchOver,
  CombatV1MatchTerminalCause? terminalCause = CombatV1MatchTerminalCause.normalPin,
  int? winnerPlayerIndex = CombatV1PlayableMatchController.humanPlayerIndex,
  String? winnerWrestlerId = 'akari',
  int actionCount = 12,
  int finalTurnNumber = 3,
  bool safetyLimitReached = false,
  String? invariantViolationMessage,
  CombatV1PlayableHumanStatus? finalHumanStatus,
  CombatV1PlayableOpponentStatus? finalCpuStatus,
  int finalSharedHeat = 50,
  CombatV1MatchPhase finalPhase = CombatV1MatchPhase.turnEnd,
  int finalActivePlayerIndex = 0,
  String humanWrestlerId = 'akari',
  String cpuWrestlerId = 'reina',
  int engineSeed = 1,
  int cpuPolicySeed = 2,
  int maxActions = 500,
  CombatV1RulesConfig rules = const CombatV1RulesConfig(),
}) => CombatV1PlayableMatchResult(
  status: status,
  terminalCause: terminalCause,
  winnerPlayerIndex: winnerPlayerIndex,
  winnerWrestlerId: winnerWrestlerId,
  actionCount: actionCount,
  finalTurnNumber: finalTurnNumber,
  safetyLimitReached: safetyLimitReached,
  invariantViolationMessage: invariantViolationMessage,
  finalHumanStatus: finalHumanStatus ?? testHumanStatus(),
  finalCpuStatus: finalCpuStatus ?? testCpuStatus(),
  finalSharedHeat: finalSharedHeat,
  finalPhase: finalPhase,
  finalActivePlayerIndex: finalActivePlayerIndex,
  humanWrestlerId: humanWrestlerId,
  cpuWrestlerId: cpuWrestlerId,
  engineSeed: engineSeed,
  cpuPolicySeed: cpuPolicySeed,
  maxActions: maxActions,
  rules: rules,
);

/// scripted [CombatV1PlayableMatchSession] fake（design doc「74・84章」）。
/// 実Engineを一切経由せず、事前に用意したsnapshotをそのまま返す。
class FakePlayableMatchSession implements CombatV1PlayableMatchSession {
  FakePlayableMatchSession(CombatV1PlayableMatchSnapshot initialSnapshot, {this.result})
    : _snapshot = initialSnapshot;

  CombatV1PlayableMatchSnapshot _snapshot;

  @override
  CombatV1PlayableMatchResult? result;

  /// `submitHumanAction`が呼ばれた際に返すoutcome（既定は受理）。
  CombatV1PlayableSubmitOutcome nextSubmitOutcome =
      CombatV1PlayableSubmitOutcome.accepted;

  /// 次の`submitHumanAction`で返すsnapshot（未指定なら現在のsnapshotを
  /// そのまま返す＝実質no-op）。
  CombatV1PlayableMatchSnapshot? nextSubmitSnapshot;

  /// `advanceCpuOneAction`が呼ばれるたびに1つずつ消費されるscripted
  /// snapshot列（design doc「84章 CPU loop widget tests」）。
  List<CombatV1PlayableMatchSnapshot> cpuScript = [];
  int cpuScriptCallCount = 0;

  final List<({int expectedRevision, CombatV1LegalAction action})> submitCalls = [];

  @override
  CombatV1PlayableMatchSnapshot get snapshot => _snapshot;

  @override
  CombatV1PlayableSubmitResult submitHumanAction({
    required int expectedRevision,
    required CombatV1LegalAction action,
  }) {
    submitCalls.add((expectedRevision: expectedRevision, action: action));
    final resultSnapshot = nextSubmitSnapshot ?? _snapshot;
    _snapshot = resultSnapshot;
    return CombatV1PlayableSubmitResult(
      outcome: nextSubmitOutcome,
      snapshot: resultSnapshot,
    );
  }

  @override
  CombatV1PlayableAdvanceResult advanceCpuOneAction() {
    if (cpuScriptCallCount >= cpuScript.length) {
      return CombatV1PlayableAdvanceResult(snapshot: _snapshot, actionsExecuted: 0);
    }
    _snapshot = cpuScript[cpuScriptCallCount];
    cpuScriptCallCount += 1;
    return CombatV1PlayableAdvanceResult(snapshot: _snapshot, actionsExecuted: 1);
  }
}
