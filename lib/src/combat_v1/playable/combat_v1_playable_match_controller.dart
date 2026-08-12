/// Combat Ver.1 Playable 1A — Match Controller / Session
/// （docs/design/combat_v1_playable_match_ui.md）。
///
/// Human（Player A / index 0）vs CPU（Player B / index 1）の1試合を、
/// 既存Combat Ver.1 Engineの境界（`CombatV1ProductionMatchStarter`・
/// `CombatV1LegalActionEnumerator`・`CombatV1ActionExecutor`・
/// `CombatV1DecisionPolicy`）だけを使ってstep-wiseに進行させる、UI非依存の
/// plain Dart class。Flutter importなし・`ChangeNotifier`等を継承しない・
/// Timer/Streamを内部に持たない（`dispose`不要）。
library;

import 'dart:math';

import '../combat_v1_action_executor.dart';
import '../combat_v1_decision_policy.dart';
import '../combat_v1_deck.dart';
import '../combat_v1_deck_validation.dart';
import '../combat_v1_engine.dart';
import '../combat_v1_enums.dart';
import '../combat_v1_legal_action.dart';
import '../combat_v1_legal_action_enumerator.dart';
import '../combat_v1_match_lifecycle.dart';
import '../combat_v1_match_state.dart';
import '../combat_v1_production_catalog.dart';
import '../combat_v1_production_match_setup.dart';
import '../combat_v1_rules_config.dart';
import 'combat_v1_playable_action_feedback.dart';
import 'combat_v1_playable_match_config.dart';
import 'combat_v1_playable_match_result.dart';
import 'combat_v1_playable_match_snapshot.dart';

/// [CombatV1PlayableMatchController.submitHumanAction]の結果種別
/// （docs/design/combat_v1_playable_match_ui.md 14〜15章）。
///
/// stale revision・不正action送信はcontroller stateを変更せず、例外も
/// 送出しない——UIが再描画可能なrecoverable caseとして`outcome`で
/// 区別する。
enum CombatV1PlayableSubmitOutcome {
  /// 受理・実行された。
  accepted,

  /// `status != active`（試合終了・error等）のため受理できない。
  rejectedNotReady,

  /// 現在のactorがHumanではない、または`action.actorPlayerIndex`が
  /// Humanのplayer indexと一致しない。
  rejectedWrongActor,

  /// `expectedRevision`が現在のrevisionと一致しない（stale action）。
  rejectedStaleRevision,

  /// `action`が現在のlegal action snapshotに含まれない。
  rejectedIllegalAction,
}

/// [CombatV1PlayableMatchController.submitHumanAction]の戻り値。
class CombatV1PlayableSubmitResult {
  const CombatV1PlayableSubmitResult({
    required this.outcome,
    required this.snapshot,
    this.message,
  });

  final CombatV1PlayableSubmitOutcome outcome;

  /// 受理・拒否いずれの場合も、呼び出し直後の最新snapshot
  /// （拒否時はstate変更なしのため、送信前と同じ内容）。
  final CombatV1PlayableMatchSnapshot snapshot;

  /// 拒否理由の人間可読説明（`outcome != accepted`の場合のみ非null）。
  final String? message;

  bool get isAccepted => outcome == CombatV1PlayableSubmitOutcome.accepted;
}

/// [CombatV1PlayableMatchController.advanceCpuOneAction]/
/// [CombatV1PlayableMatchController.advanceCpuUntilHumanInput]の戻り値
/// （docs/design/combat_v1_playable_match_ui.md 20章「CPU one-step API +
/// convenience loop」）。
class CombatV1PlayableAdvanceResult {
  const CombatV1PlayableAdvanceResult({
    required this.snapshot,
    required this.actionsExecuted,
  });

  final CombatV1PlayableMatchSnapshot snapshot;

  /// この呼び出しで実際に実行されたCPU actionの数（0件の場合は
  /// 「CPUの手番ではなかった」または「既にterminal/error」を意味する、
  /// no-op）。
  final int actionsExecuted;
}

/// Human vs CPUの1試合をstep-wiseに進行させるcontroller/session
/// （docs/design/combat_v1_playable_match_ui.md）。
class CombatV1PlayableMatchController {
  /// [config]からHuman（playerA / index 0）vs CPU（playerB / index 1）の
  /// 試合を開始する。
  ///
  /// [config]自体が不正な場合（未知wrestlerId・`maxActions <= 0`）は
  /// [CombatV1PlayableMatchConfig]のコンストラクタが既にfail-fastして
  /// いる。`CombatV1ProductionMatchStarter.start`が失敗する場合
  /// （catalog/deck不正等、通常到達しない）も同様にfail-fastで例外を
  /// 伝播する——programming errorとして扱い、recoverableなcontroller
  /// stateにはしない。
  CombatV1PlayableMatchController(CombatV1PlayableMatchConfig config)
    : _config = config,
      _catalog = productionCardCatalog,
      _rules = config.rules,
      _engineRandom = Random(config.engineSeed) {
    _cpuPolicy = config.cpuPolicyKind.createFresh(Random(config.cpuPolicySeed));

    final humanOwnerId = combatV1PlayableOwnerId(
      engineSeed: config.engineSeed,
      playerSuffix: 'human',
    );
    final cpuOwnerId = combatV1PlayableOwnerId(
      engineSeed: config.engineSeed,
      playerSuffix: 'cpu',
    );

    _state = CombatV1ProductionMatchStarter.start(
      CombatV1ProductionMatchConfig(
        wrestlerAId: config.humanWrestlerId,
        wrestlerBId: config.cpuWrestlerId,
        playerAOwnerId: humanOwnerId,
        playerBOwnerId: cpuOwnerId,
        rules: config.rules,
      ),
      random: _engineRandom,
    );

    // Invariant checkpoint 1: match start直後
    // （docs/design/combat_v1_playable_match_ui.md 「Invariant
    // Checkpoints」）。
    final startViolation = CombatV1MatchLifecycle.validateIntegratedInvariants(
      _state,
      rules: _rules,
    );
    if (startViolation != null) {
      _enterInvariantViolation(startViolation);
    } else {
      _settle();
      // CPU-start耐性（現行Engineは常にplayerA=Humanから開始するため
      // 通常到達しないが、controller自体は将来のstarting player変更にも
      // 耐えられる設計にする、20章）: 開始直後にCPUのactorになった場合も
      // ここで自動進行はしない——[submitHumanAction]と同じ方針で、CPU
      // 進行は必ず呼び出し側が[advanceCpuOneAction]/
      // [advanceCpuUntilHumanInput]を明示的に呼ぶことで行う（下記参照）。
    }
  }

  /// Human（Player A）のplayerIndex。
  static const int humanPlayerIndex = 0;

  /// CPU（Player B）のplayerIndex。
  static const int cpuPlayerIndex = 1;

  static const int _maxRecentObservations = 8;

  /// Playable 1C「Feedback Data Model」——[_recentObservations]と同じ
  /// 保持件数（O(totalActions)保持にしない）。
  static const int _maxRecentFeedback = 8;

  final CombatV1PlayableMatchConfig _config;
  final CombatV1CardCatalog _catalog;
  final CombatV1RulesConfig _rules;
  final Random _engineRandom;
  late final CombatV1DecisionPolicy _cpuPolicy;

  late CombatV1MatchState _state;
  int _revision = 0;
  int _actionCount = 0;

  List<CombatV1LegalAction> _legalActions = const [];
  int? _currentActor;

  CombatV1PlayableControllerStatus _status =
      CombatV1PlayableControllerStatus.active;
  String? _diagnosticMessage;
  CombatV1MatchTerminalCause? _terminalCause;
  CombatV1PlayableMatchResult? _result;

  CombatV1LegalAction? _lastAction;
  CombatV1MatchState? _stateBeforeLastAction;

  final List<CombatV1PlayableObservation> _recentObservations = [];

  /// Playable 1C「Action Feedback Model」——[_recentObservations]と1:1で
  /// 対応する、before/after diffから構築したhidden-safe feedback。
  final List<CombatV1PlayableActionFeedback> _recentFeedback = [];

  /// 現在のhidden-safe snapshot（呼び出しのたびに`_state`から再構築する。
  /// cacheしない——staleなcacheを持ち越すリスクを構造的に排除する）。
  CombatV1PlayableMatchSnapshot get snapshot => CombatV1PlayableMatchSnapshot(
    revision: _revision,
    turnNumber: _state.turnNumber,
    phase: _state.phase,
    status: _status,
    currentActorPlayerIndex: _currentActor,
    isHumanInputRequired:
        _status == CombatV1PlayableControllerStatus.active &&
        _currentActor == humanPlayerIndex,
    isMatchOver: _state.isOver,
    sharedHeat: _state.sharedHeat,
    finisherHeatThreshold: _rules.finisherHeatThreshold,
    actionCount: _actionCount,
    maxActions: _config.maxActions,
    legalActions:
        (_status == CombatV1PlayableControllerStatus.active &&
            _currentActor == humanPlayerIndex)
        ? List.unmodifiable(_legalActions)
        : const [],
    human: _buildHumanStatus(),
    cpu: _buildOpponentStatus(),
    pendingAttack: _buildPendingAttackView(),
    recentObservations: List.unmodifiable(_recentObservations),
    diagnosticMessage: _diagnosticMessage,
    latestFeedback: _recentFeedback.isEmpty ? null : _recentFeedback.last,
    recentFeedback: List.unmodifiable(_recentFeedback),
  );

  /// `status`が`matchOver`/`safetyLimit`/`invariantViolation`のいずれかに
  /// なった時点で非null（18章）。
  CombatV1PlayableMatchResult? get result => _result;

  /// 現在のcontroller status（利便性getter、`snapshot.status`と同じ値）。
  CombatV1PlayableControllerStatus get status => _status;

  /// [expectedRevision]・[action]をHumanのactionとして送信する
  /// （docs/design/combat_v1_playable_match_ui.md 15章）。
  ///
  /// 受理された場合でも、CPU actionへの自動連鎖は行わない——実行後の
  /// `snapshot.isHumanInputRequired`が`false`（CPUの手番）になった場合、
  /// 呼び出し側が[advanceCpuOneAction]または[advanceCpuUntilHumanInput]を
  /// 明示的に呼んでCPUを進行させる（20章「CPU one-step API + convenience
  /// loop」。Playable 1BがCPU 1手ごとにpresentation delayを挟めるよう、
  /// このmethod自身はCPU進行を隠蔽・自動化しない）。
  CombatV1PlayableSubmitResult submitHumanAction({
    required int expectedRevision,
    required CombatV1LegalAction action,
  }) {
    if (_status != CombatV1PlayableControllerStatus.active) {
      return CombatV1PlayableSubmitResult(
        outcome: CombatV1PlayableSubmitOutcome.rejectedNotReady,
        snapshot: snapshot,
        message: 'controllerはactive状態ではありません（status: $_status）',
      );
    }
    if (_currentActor != humanPlayerIndex ||
        action.actorPlayerIndex != humanPlayerIndex) {
      return CombatV1PlayableSubmitResult(
        outcome: CombatV1PlayableSubmitOutcome.rejectedWrongActor,
        snapshot: snapshot,
        message: '現在のactorはHumanではありません'
            '（currentActor: $_currentActor, action.actorPlayerIndex: '
            '${action.actorPlayerIndex}）',
      );
    }
    if (expectedRevision != _revision) {
      return CombatV1PlayableSubmitResult(
        outcome: CombatV1PlayableSubmitOutcome.rejectedStaleRevision,
        snapshot: snapshot,
        message: 'stale revisionです（expected: $expectedRevision, '
            'current: $_revision）',
      );
    }
    if (!_legalActions.contains(action)) {
      return CombatV1PlayableSubmitResult(
        outcome: CombatV1PlayableSubmitOutcome.rejectedIllegalAction,
        snapshot: snapshot,
        message: '現在のlegal action snapshotに含まれないactionです: $action',
      );
    }

    _applyAction(action);

    return CombatV1PlayableSubmitResult(
      outcome: CombatV1PlayableSubmitOutcome.accepted,
      snapshot: snapshot,
    );
  }

  /// CPUの手番であれば、ちょうど1件のCPU actionを実行する
  /// （docs/design/combat_v1_playable_match_ui.md 20章、Playable 1Bの
  /// per-action presentation delay向け）。CPUの手番でない場合、または
  /// `status != active`の場合はno-op（`actionsExecuted == 0`）。
  CombatV1PlayableAdvanceResult advanceCpuOneAction() {
    if (_status != CombatV1PlayableControllerStatus.active ||
        _currentActor != cpuPlayerIndex) {
      return CombatV1PlayableAdvanceResult(
        snapshot: snapshot,
        actionsExecuted: 0,
      );
    }
    final countBefore = _actionCount;
    _executeOneCpuStep();
    return CombatV1PlayableAdvanceResult(
      snapshot: snapshot,
      actionsExecuted: _actionCount - countBefore,
    );
  }

  /// Humanの手番（またはterminal/error）になるまでCPU actionを連続して
  /// 実行するconvenience API（20章）。
  CombatV1PlayableAdvanceResult advanceCpuUntilHumanInput() {
    final executed = _runCpuUntilHumanInput();
    return CombatV1PlayableAdvanceResult(
      snapshot: snapshot,
      actionsExecuted: executed,
    );
  }

  int _runCpuUntilHumanInput() {
    final countBefore = _actionCount;
    while (_status == CombatV1PlayableControllerStatus.active &&
        _currentActor == cpuPlayerIndex) {
      _executeOneCpuStep();
    }
    return _actionCount - countBefore;
  }

  /// enumerate → policy.choose → execute、の1 CPU stepを実行する。
  /// `_legalActions`/`_currentActor`は直前の[_settle]で既に
  /// `cpuPlayerIndex`として確定している前提。
  void _executeOneCpuStep() {
    final chosen = _cpuPolicy.choose(_state, _legalActions);
    _applyAction(chosen);
  }

  /// [action]を実行し、invariant validate → observation記録 →
  /// revision/actionCount更新 → 再enumerateまでを行う
  /// （docs/design/combat_v1_playable_match_ui.md 15章「Human Action
  /// Execution」、Human/CPU双方のactionから共通で呼ばれる）。
  void _applyAction(CombatV1LegalAction action) {
    final stateBefore = _state;
    final turnBefore = _state.turnNumber;

    late final CombatV1MatchState next;
    try {
      next = CombatV1ActionExecutor.execute(
        _state,
        action,
        catalog: _catalog,
        rules: _rules,
        random: _engineRandom,
      );
    } on Object catch (error) {
      _enterError(
        'action実行に失敗しました（action: $action, revision: $_revision, '
        'actionCount: $_actionCount, engineSeed: ${_config.engineSeed}）: '
        '$error',
      );
      return;
    }

    _state = next;
    _actionCount += 1;
    _revision += 1;
    _lastAction = action;
    _stateBeforeLastAction = stateBefore;
    _recordObservation(
      actionIndex: _actionCount - 1,
      turnNumber: turnBefore,
      action: action,
    );
    _recordFeedback(
      action: action,
      stateBefore: stateBefore,
      stateAfter: _state,
      actionIndex: _actionCount - 1,
      turnNumber: turnBefore,
    );

    // Invariant checkpoint 2: 各action後。
    final violation = CombatV1MatchLifecycle.validateIntegratedInvariants(
      _state,
      rules: _rules,
    );
    if (violation != null) {
      _enterInvariantViolation(violation);
      return;
    }

    _settle();
  }

  /// terminal判定 → safety limit判定 → 非terminalならlegal actionの
  /// 再enumerate・actor解決を行う（docs/design/combat_v1_playable_match_ui.md
  /// 8章「Actor Semantics」、14章）。
  void _settle() {
    if (_state.isOver) {
      _terminalCause = CombatV1MatchLifecycle.classifyTerminalCause(
        action: _lastAction,
        stateBefore: _stateBeforeLastAction,
        stateAfter: _state,
      );
      _legalActions = const [];
      _currentActor = null;
      _status = CombatV1PlayableControllerStatus.matchOver;
      _buildResult();
      return;
    }

    if (_actionCount >= _config.maxActions) {
      _legalActions = const [];
      _currentActor = null;
      _status = CombatV1PlayableControllerStatus.safetyLimit;
      _buildResult();
      return;
    }

    final legal = CombatV1LegalActionEnumerator.enumerate(
      _state,
      catalog: _catalog,
      rules: _rules,
    );
    if (legal.isEmpty) {
      _enterInvariantViolation(
        '試合未終了のstate（phase:${_state.phase.name}, '
        'activePlayerIndex:${_state.activePlayerIndex}）でlegal actionが'
        '0件でした。正常な非terminal stateでは発生しないはずの'
        'programming/invariant errorです。',
      );
      return;
    }

    final actor = legal.first.actorPlayerIndex;
    final consistentActor = legal.every((a) => a.actorPlayerIndex == actor);
    if (!consistentActor || (actor != 0 && actor != 1)) {
      _enterInvariantViolation(
        '列挙されたlegal action群のactorPlayerIndexが一致しない、または'
        '0/1の範囲外です（actor:$actor）。',
      );
      return;
    }

    _legalActions = legal;
    _currentActor = actor;
    _status = CombatV1PlayableControllerStatus.active;
  }

  void _recordObservation({
    required int actionIndex,
    required int turnNumber,
    required CombatV1LegalAction action,
  }) {
    _recentObservations.add(
      CombatV1PlayableObservation(
        actionIndex: actionIndex,
        turnNumber: turnNumber,
        actorPlayerIndex: action.actorPlayerIndex,
        action: action,
      ),
    );
    if (_recentObservations.length > _maxRecentObservations) {
      _recentObservations.removeAt(0);
    }
  }

  /// Playable 1C「Action Feedback Model」——[action]実行前後の
  /// `CombatV1MatchState`差分から[CombatV1PlayableActionFeedback]を構築し、
  /// bounded historyへ追加する。damage/PIN/SUBMISSION結果はいずれも
  /// Technique metadataの宣言値を鵜呑みにせず、実際に観測された
  /// before/after差分から導出する（design doc「Do Not Fabricate
  /// Deltas」）。
  void _recordFeedback({
    required CombatV1LegalAction action,
    required CombatV1MatchState stateBefore,
    required CombatV1MatchState stateAfter,
    required int actionIndex,
    required int turnNumber,
  }) {
    final feedback = _buildFeedback(
      action: action,
      stateBefore: stateBefore,
      stateAfter: stateAfter,
      actionIndex: actionIndex,
      turnNumber: turnNumber,
    );
    if (feedback == null) return;
    _recentFeedback.add(feedback);
    if (_recentFeedback.length > _maxRecentFeedback) {
      _recentFeedback.removeAt(0);
    }
  }

  static CombatV1PlayerState _playerAt(CombatV1MatchState state, int index) =>
      index == 0 ? state.playerA : state.playerB;

  String _techniqueName(String cardId) {
    final technique = _catalog.techniques[cardId];
    if (technique == null) {
      throw CombatV1IllegalActionException(
        'action feedback用のtechnique cardIdがcatalogに存在しません: $cardId',
      );
    }
    return technique.name;
  }

  /// [instanceId]のCounterカードを[playerIndex]のdiscardPileから逆引きし、
  /// 表示名を解決する（`playCounter`実行直後は必ず末尾付近に存在する
  /// ——既にHuman/CPU双方へ公開されたaction結果のため、hidden information
  /// 違反にならない）。見つからない場合は`null`（防御的、通常到達しない）。
  String? _resolveCounterName(
    CombatV1MatchState state,
    int playerIndex,
    String? instanceId,
  ) {
    if (instanceId == null) return null;
    final discardPile = _playerAt(state, playerIndex).discardPile;
    for (final entry in discardPile.reversed) {
      if (entry.instanceId == instanceId) {
        return _catalog.counters[entry.cardId]?.name;
      }
    }
    return null;
  }

  CombatV1PlayableActionFeedback? _buildFeedback({
    required CombatV1LegalAction action,
    required CombatV1MatchState stateBefore,
    required CombatV1MatchState stateAfter,
    required int actionIndex,
    required int turnNumber,
  }) {
    switch (action.kind) {
      case CombatV1LegalActionKind.discard:
        return CombatV1PlayableActionFeedback(
          actionIndex: actionIndex,
          turnNumber: turnNumber,
          kind: CombatV1PlayableFeedbackKind.discard,
          actorPlayerIndex: action.actorPlayerIndex,
        );

      case CombatV1LegalActionKind.endTurn:
        return CombatV1PlayableActionFeedback(
          actionIndex: actionIndex,
          turnNumber: turnNumber,
          kind: CombatV1PlayableFeedbackKind.endTurn,
          actorPlayerIndex: action.actorPlayerIndex,
        );

      case CombatV1LegalActionKind.standUp:
        final owner = action.actorPlayerIndex;
        final before = _playerAt(stateBefore, owner);
        final after = _playerAt(stateAfter, owner);
        return CombatV1PlayableActionFeedback(
          actionIndex: actionIndex,
          turnNumber: turnNumber,
          kind: CombatV1PlayableFeedbackKind.standUp,
          actorPlayerIndex: owner,
          postureOwnerPlayerIndex: owner,
          postureBefore: before.posture,
          postureAfter: after.posture,
        );

      case CombatV1LegalActionKind.rest:
        final owner = action.actorPlayerIndex;
        final before = _playerAt(stateBefore, owner);
        final after = _playerAt(stateAfter, owner);
        return CombatV1PlayableActionFeedback(
          actionIndex: actionIndex,
          turnNumber: turnNumber,
          kind: CombatV1PlayableFeedbackKind.rest,
          actorPlayerIndex: owner,
          hpOwnerPlayerIndex: owner,
          hpBefore: before.hp,
          hpAfter: after.hp,
        );

      case CombatV1LegalActionKind.pin:
        final attacker = action.actorPlayerIndex;
        final defender = attacker == 0 ? 1 : 0;
        final defenderBefore = _playerAt(stateBefore, defender);
        final defenderAfter = _playerAt(stateAfter, defender);
        final matchEndedByAttacker =
            !stateBefore.isOver &&
            stateAfter.isOver &&
            stateAfter.winnerPlayerIndex == attacker;
        return CombatV1PlayableActionFeedback(
          actionIndex: actionIndex,
          turnNumber: turnNumber,
          kind: CombatV1PlayableFeedbackKind.pinResolved,
          actorPlayerIndex: attacker,
          opponentPlayerIndex: defender,
          kocOwnerPlayerIndex: defender,
          kocBefore: defenderBefore.koc,
          kocAfter: defenderAfter.koc,
          pinOutcome: matchEndedByAttacker
              ? CombatV1PlayablePinFeedbackOutcome.matchOver
              : CombatV1PlayablePinFeedbackOutcome.kickOut,
        );

      case CombatV1LegalActionKind.technique:
        // 宣言のみ——`counterResponsePending`へ移行するだけで、
        // damage/HP/posture/HEATはまだ確定しない（Core Engineが
        // 効果を適用するのは`declineCounter`/`playCounter`実行時）。
        final pendingAfter = stateAfter.pendingAttack;
        return CombatV1PlayableActionFeedback(
          actionIndex: actionIndex,
          turnNumber: turnNumber,
          kind: CombatV1PlayableFeedbackKind.techniqueDeclared,
          actorPlayerIndex: action.actorPlayerIndex,
          opponentPlayerIndex: pendingAfter?.defenderPlayerIndex,
          actionDisplayName: pendingAfter == null
              ? null
              : _techniqueName(pendingAfter.attackCardId),
        );

      case CombatV1LegalActionKind.counter:
        final defender = action.actorPlayerIndex;
        final pendingBefore = stateBefore.pendingAttack;
        final attacker =
            pendingBefore?.attackerPlayerIndex ?? (defender == 0 ? 1 : 0);
        return CombatV1PlayableActionFeedback(
          actionIndex: actionIndex,
          turnNumber: turnNumber,
          kind: CombatV1PlayableFeedbackKind.counterPlayed,
          actorPlayerIndex: defender,
          opponentPlayerIndex: attacker,
          actionDisplayName: _resolveCounterName(
            stateAfter,
            defender,
            action.cardInstanceId,
          ),
          relatedActionDisplayName: pendingBefore == null
              ? null
              : _techniqueName(pendingBefore.attackCardId),
        );

      case CombatV1LegalActionKind.declineCounter:
        return _buildTechniqueResolvedFeedback(
          stateBefore: stateBefore,
          stateAfter: stateAfter,
          actionIndex: actionIndex,
          turnNumber: turnNumber,
        );
    }
  }

  /// [CombatV1LegalActionKind.declineCounter]専用: 宣言済みTECHNIQUEが
  /// COUNTERされず成立した際のfeedbackを構築する。同一action内で
  /// DIRECT PIN/SUBMISSIONへ自動移行した場合（Core Engine
  /// `_resolvePendingAttack`、docs/combat_rules_v1.md 8・10章）は
  /// [pinOutcome]/[submissionOutcome]も併せて設定する。
  ///
  /// PIN/SUBMISSIONが実際に発生したかどうかは、TECHNIQUEの静的
  /// metadata（`directPin`/`submissionHold`/`finisherType`——宣言済みの
  /// カードなので公開情報）と、防御側KOCの実測差分・試合終了の有無から
  /// 判定する。KOCは`_resolvePin`/`_resolveSubmission`以外では変化しない
  /// （Core Engine全体の不変条件）ため、この判定はEngineの実際の遷移結果
  /// を観測しているだけであり、legality/damage計算の再実装ではない。
  CombatV1PlayableActionFeedback? _buildTechniqueResolvedFeedback({
    required CombatV1MatchState stateBefore,
    required CombatV1MatchState stateAfter,
    required int actionIndex,
    required int turnNumber,
  }) {
    final pending = stateBefore.pendingAttack;
    if (pending == null) return null;

    final attacker = pending.attackerPlayerIndex;
    final defender = pending.defenderPlayerIndex;

    final defenderBefore = _playerAt(stateBefore, defender);
    final defenderAfter = _playerAt(stateAfter, defender);
    final actualDamage = defenderBefore.hp - defenderAfter.hp;

    final isFinisher = pending.category == CombatV1CardCategory.finisher;
    final likelyDirectPin = isFinisher
        ? pending.finisherType == CombatV1FinisherType.directPin
        : pending.directPin;
    final likelySubmissionHold = isFinisher
        ? pending.finisherType == CombatV1FinisherType.submission
        : pending.submissionHold;

    final kocDelta = defenderAfter.koc - defenderBefore.koc;
    final matchEndedByAttacker =
        !stateBefore.isOver &&
        stateAfter.isOver &&
        stateAfter.winnerPlayerIndex == attacker;
    final secondaryResolved = kocDelta != 0 || matchEndedByAttacker;

    CombatV1PlayablePinFeedbackOutcome? pinOutcome;
    CombatV1PlayableSubmissionFeedbackOutcome? submissionOutcome;
    if (secondaryResolved && likelyDirectPin) {
      pinOutcome = matchEndedByAttacker
          ? CombatV1PlayablePinFeedbackOutcome.matchOver
          : CombatV1PlayablePinFeedbackOutcome.kickOut;
    } else if (secondaryResolved && likelySubmissionHold) {
      submissionOutcome = matchEndedByAttacker
          ? CombatV1PlayableSubmissionFeedbackOutcome.matchOver
          : CombatV1PlayableSubmissionFeedbackOutcome.escaped;
    }

    return CombatV1PlayableActionFeedback(
      actionIndex: actionIndex,
      turnNumber: turnNumber,
      kind: CombatV1PlayableFeedbackKind.techniqueResolved,
      actorPlayerIndex: attacker,
      opponentPlayerIndex: defender,
      actionDisplayName: _techniqueName(pending.attackCardId),
      damage: actualDamage > 0 ? actualDamage : 0,
      hpOwnerPlayerIndex: defender,
      hpBefore: defenderBefore.hp,
      hpAfter: defenderAfter.hp,
      postureOwnerPlayerIndex: defender,
      postureBefore: defenderBefore.posture,
      postureAfter: defenderAfter.posture,
      heatBefore: stateBefore.sharedHeat,
      heatAfter: stateAfter.sharedHeat,
      kocOwnerPlayerIndex: secondaryResolved ? defender : null,
      kocBefore: secondaryResolved ? defenderBefore.koc : null,
      kocAfter: secondaryResolved ? defenderAfter.koc : null,
      pinOutcome: pinOutcome,
      submissionOutcome: submissionOutcome,
    );
  }

  void _enterInvariantViolation(String message) {
    _diagnosticMessage = message;
    _legalActions = const [];
    _currentActor = null;
    _status = CombatV1PlayableControllerStatus.invariantViolation;
    _buildResult();
  }

  void _enterError(String message) {
    _diagnosticMessage = message;
    _legalActions = const [];
    _currentActor = null;
    _status = CombatV1PlayableControllerStatus.error;
  }

  void _buildResult() {
    final winnerPlayerIndex = _state.winnerPlayerIndex;
    // 注意: switch式のcase patternへ`humanPlayerIndex`/`cpuPlayerIndex`を
    // bareのままでは書かない——Dartのpattern matchingでは、bareな識別子は
    // （それがconstであっても）常にvariable pattern（新規binding、無条件
    // match）として扱われるため、意図せず常にhumanPlayerIndex側のarmが
    // 一致してしまう。`==`比較のif/elseで明示的に書く。
    final String? winnerWrestlerId;
    if (winnerPlayerIndex == humanPlayerIndex) {
      winnerWrestlerId = _config.humanWrestlerId;
    } else if (winnerPlayerIndex == cpuPlayerIndex) {
      winnerWrestlerId = _config.cpuWrestlerId;
    } else {
      winnerWrestlerId = null;
    }

    _result = CombatV1PlayableMatchResult(
      status: _status,
      terminalCause:
          _status == CombatV1PlayableControllerStatus.matchOver
          ? _terminalCause
          : null,
      winnerPlayerIndex: winnerPlayerIndex,
      winnerWrestlerId: winnerWrestlerId,
      actionCount: _actionCount,
      finalTurnNumber: _state.turnNumber,
      safetyLimitReached:
          _status == CombatV1PlayableControllerStatus.safetyLimit,
      invariantViolationMessage:
          _status == CombatV1PlayableControllerStatus.invariantViolation
          ? _diagnosticMessage
          : null,
      finalHumanStatus: _buildHumanStatus(),
      finalCpuStatus: _buildOpponentStatus(),
      finalSharedHeat: _state.sharedHeat,
      finalPhase: _state.phase,
      finalActivePlayerIndex: _state.activePlayerIndex,
      humanWrestlerId: _config.humanWrestlerId,
      cpuWrestlerId: _config.cpuWrestlerId,
      engineSeed: _config.engineSeed,
      cpuPolicySeed: _config.cpuPolicySeed,
      maxActions: _config.maxActions,
      rules: _rules,
    );
  }

  CombatV1PlayerState get _humanPlayerState =>
      humanPlayerIndex == 0 ? _state.playerA : _state.playerB;

  CombatV1PlayerState get _cpuPlayerState =>
      cpuPlayerIndex == 0 ? _state.playerA : _state.playerB;

  CombatV1PlayableHumanStatus _buildHumanStatus() {
    final player = _humanPlayerState;
    final usableInstanceIds =
        (_status == CombatV1PlayableControllerStatus.active &&
            _currentActor == humanPlayerIndex)
        ? _legalActions
              .map((a) => a.cardInstanceId)
              .whereType<String>()
              .toSet()
        : const <String>{};

    return CombatV1PlayableHumanStatus(
      wrestlerId: player.wrestlerId,
      wrestlerName: player.wrestlerName,
      hp: player.hp,
      maxHp: player.maxHp,
      koc: player.koc,
      posture: player.posture,
      hand: [
        for (final entry in player.hand) _buildHandCard(entry, usableInstanceIds),
      ],
      handCount: player.hand.length,
      drawPileCount: player.drawPile.length,
      discardPileCount: player.discardPile.length,
      pinCardsHeld: player.pinCardsHeld,
      reshuffleCount: player.reshuffleCount,
      // Playable 1C.1「Energy Semantics」——`energyPool`（保有量そのもの、
      // 自ターン内で変化しない）と、そこから使用済み分を引いた現在の
      // 使用可能量を別々に公開する。どちらも`CombatV1PlayerState`が既に
      // 持つ値をそのまま読むだけで、新しいlegality/計算ロジックは
      // 追加しない。
      energyPool: player.energyPool,
      availableEnergy: {
        for (final attribute in CombatV1EnergyAttribute.values)
          attribute: player.availableEnergyFor(attribute),
      },
    );
  }

  CombatV1PlayableOpponentStatus _buildOpponentStatus() {
    final player = _cpuPlayerState;
    return CombatV1PlayableOpponentStatus(
      wrestlerId: player.wrestlerId,
      wrestlerName: player.wrestlerName,
      hp: player.hp,
      maxHp: player.maxHp,
      koc: player.koc,
      posture: player.posture,
      handCount: player.hand.length,
      drawPileCount: player.drawPile.length,
      discardPileCount: player.discardPile.length,
      pinCardsHeld: player.pinCardsHeld,
      reshuffleCount: player.reshuffleCount,
    );
  }

  CombatV1PlayableHandCard _buildHandCard(
    CombatV1DeckEntry entry,
    Set<String> usableInstanceIds,
  ) {
    final technique = _catalog.techniques[entry.cardId];
    final counter = _catalog.counters[entry.cardId];
    if (technique == null && counter == null) {
      throw CombatV1IllegalActionException(
        '手札のcardIdがcatalogに存在しません: ${entry.cardId} '
        '(instance: ${entry.instanceId})',
      );
    }
    return CombatV1PlayableHandCard(
      instanceId: entry.instanceId,
      cardId: entry.cardId,
      category: entry.category,
      displayName: technique?.name ?? counter!.name,
      technique: technique,
      counter: counter,
      isUsable: usableInstanceIds.contains(entry.instanceId),
    );
  }

  CombatV1PlayablePendingAttackView? _buildPendingAttackView() {
    final pending = _state.pendingAttack;
    if (pending == null) return null;

    final technique = _catalog.techniques[pending.attackCardId];
    if (technique == null) {
      throw CombatV1IllegalActionException(
        'pendingAttackのcardIdがcatalogに存在しません: ${pending.attackCardId}',
      );
    }

    return CombatV1PlayablePendingAttackView(
      attackerPlayerIndex: pending.attackerPlayerIndex,
      defenderPlayerIndex: pending.defenderPlayerIndex,
      attackCardInstanceId: pending.attackCardInstance.instanceId,
      cardId: pending.attackCardId,
      displayName: technique.name,
      category: pending.category,
      attribute: pending.attribute,
      family: pending.family,
      damage: pending.damage,
      resultOpponentState: pending.resultOpponentState,
      energyCostTotal: pending.energyCost.total,
    );
  }
}
