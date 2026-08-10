/// CombatV1CpuMatchRunner（Phase 11B、docs/design/combat_v1_phase11b_cpu.md）。
///
/// 「現在のstateから合法手を列挙し、CPU Policyが1手を選択し、Engine
/// Commandとして安全に実行する」サイクルを、bounded single-matchとして
/// 進行させるrunner。batch simulation・statistics・analytics・exportは
/// Phase 12へ回す（このファイルへは含めない）。
library;

import 'dart:math';

import 'combat_v1_action_executor.dart';
import 'combat_v1_action_observer.dart';
import 'combat_v1_decision_policy.dart';
import 'combat_v1_deck_validation.dart';
import 'combat_v1_enums.dart';
import 'combat_v1_legal_action.dart';
import 'combat_v1_legal_action_enumerator.dart';
import 'combat_v1_match_state.dart';
import 'combat_v1_pending_attack.dart';
import 'combat_v1_rules_config.dart';
import 'combat_v1_state_invariants.dart';

/// [CombatV1CpuMatchRunner.run]の終了理由（Phase 11B）。
enum CombatV1CpuMatchTermination {
  /// `CombatV1Engine`でwinnerが確定した正常終了
  /// （[CombatV1MatchState.isOver]）。
  matchOver,

  /// ゲームは未終了だが、runner safety guard（[CombatV1CpuMatchRunner.maxActions]）
  /// へ到達した。ゲームルールではなくrunner側の安全装置であり、winnerを
  /// 捏造しない・draw扱いにもしない・Engine stateも書き換えない
  /// （到達した時点のstateをそのまま返すのみ）。
  safetyLimit,

  /// state invariant違反（[validateMatchStateInvariants]または
  /// 両playerの[validatePlayerStateInvariants]のいずれかが失敗）、または
  /// 非terminal stateでlegal actionが0件など、programming/invariant上の
  /// 異常により停止した。
  invariantViolation,
}

/// [CombatV1MatchState.isOver]になった直接の原因（Phase 11B addendum
/// 「Terminal Metadata」）。
///
/// [CombatV1PendingAttack]の公開field（`category`/`finisherType`/
/// `directPin`/`submissionHold`）のみから導出する——`CombatV1Engine`の
/// private実装（`_resolvePendingAttack`のeffectiveDirectPin/
/// effectiveSubmissionHold導出と同じ公開情報ベースの判定）を再現するのみで、
/// private stateへのアクセスやCore Engine変更は必要としない。
enum CombatV1CpuMatchTerminalCause {
  /// 通常PIN（[CombatV1PinAction]、`declarePin`）の3カウントで決着。
  normalPin,

  /// DIRECT PIN（NORMAL/SIGNATUREの`directPin`、またはFINISHERの
  /// `finisherType == directPin`）の自動PINで決着。
  directPin,

  /// 通常SUBMISSION（`submissionHold`）のGIVE UPで決着。
  submission,

  /// FINISHER SUBMISSION（`finisherType == submission`）のGIVE UPで決着。
  submissionFinisher,

  /// 上記のいずれにも分類できない決着経路。
  other,
}

/// [CombatV1CpuMatchRunner.run]の結果（Phase 11B）。
///
/// Phase 12（Simulator）で再利用しやすい最小限の形にする——analytics項目は
/// 増やしすぎない。
class CombatV1CpuMatchResult {
  const CombatV1CpuMatchResult({
    required this.finalState,
    required this.actionCount,
    required this.finalTurnNumber,
    required this.termination,
    required this.maxActions,
    required this.policyAId,
    required this.policyBId,
    this.lastAction,
    this.terminalCause,
    this.invariantViolationMessage,
  });

  final CombatV1MatchState finalState;

  /// [CombatV1ActionExecutor.execute]が成功したpublic CPU actionの数
  /// （discard/declareTechnique/playCounter/declineCounter/declarePin/
  /// rest/standUp/endTurnの8種のみを数える。direct PIN resolution・
  /// submission resolution・draw・shuffle・posture update・turn
  /// transition等、Engine内部で自動的に行われる処理は追加でカウントしない）。
  final int actionCount;

  /// [finalState.turnNumber]。
  final int finalTurnNumber;

  final CombatV1CpuMatchTermination termination;

  /// このrunで使用したrunner safety guardの上限値
  /// （[CombatV1CpuMatchRunner.maxActions]と同じ値）。
  final int maxActions;

  final String policyAId;
  final String policyBId;

  /// 最後に成功実行された[CombatV1LegalAction]。1件もactionが成功しなかった
  /// 場合（開始直後に[CombatV1MatchState.isOver]、または開始直後の
  /// invariant違反）は`null`。
  final CombatV1LegalAction? lastAction;

  /// [termination] == [CombatV1CpuMatchTermination.matchOver]の場合のみ
  /// 非null。
  final CombatV1CpuMatchTerminalCause? terminalCause;

  /// [termination] == [CombatV1CpuMatchTermination.invariantViolation]の
  /// 場合のみ非null。
  final String? invariantViolationMessage;

  bool get hasWinner => finalState.winnerPlayerIndex != null;

  CombatV1MatchPhase get lastPhase => finalState.phase;

  int get lastActivePlayerIndex => finalState.activePlayerIndex;

  bool get hasPendingAttack => finalState.pendingAttack != null;
}

/// bounded single CPU vs CPU matchを進行させるrunner（Phase 11B）。
///
/// [initialState]・[catalog]・[rules]・engine用[Random]・両playerの
/// [CombatV1DecisionPolicy]を受け取って動作する——`CombatV1ProductionMatchStarter`
/// 等の特定の初期化経路へ強結合しない。
class CombatV1CpuMatchRunner {
  const CombatV1CpuMatchRunner({
    required this.catalog,
    required this.rules,
    this.maxActions = 500,
  });

  final CombatV1CardCatalog catalog;
  final CombatV1RulesConfig rules;

  /// runner safety guard（既定500）。ゲームルールのturn limit/draw条件では
  /// ない。[CombatV1ActionExecutor.execute]成功後にカウントする。
  final int maxActions;

  /// [initialState]から試合を進行させる。
  ///
  /// [policyA]は`playerIndex == 0`のactor（playerA、およびplayerAが防御側の
  /// COUNTER応答）を、[policyB]は`playerIndex == 1`のactorを担当する
  /// （counterResponsePending中も[CombatV1LegalAction.actorPlayerIndex]から
  /// 導出した防御側のplayerIndexで判定するため、defenderのpolicyが正しく
  /// 使われる）。
  ///
  /// [engineRandom]は`CombatV1Engine` Command（shuffle/draw/PIN/COUNTER
  /// 解決）専用のRandom。[policyA]/[policyB]（例:
  /// [CombatV1RandomLegalPolicy]）がコンストラクタで受け取るdecision用
  /// Randomとは常に分離する——このrunner自身はpolicy用のRandomを一切生成・
  /// 共有しない（Phase 11B addendum「RNG Separation」。呼び出し側が
  /// playerAPolicyRandom/playerBPolicyRandom/engineRandomをそれぞれ独立に
  /// 生成して注入する）。
  ///
  /// [observer]は省略可能。渡された場合、成功した各public actionについて
  /// [CombatV1ActionObserver.onActionResolved]を呼び出す（Phase 11B
  /// addendum「Structured Action Observation」）。Phase 11B自身は
  /// observationを蓄積・分析しない。
  ///
  /// [_validateRunnerInvariants]（[validateMatchStateInvariants] + 両
  /// playerの[validatePlayerStateInvariants]の統合チェック）を(1)開始直後、
  /// (2)各Action Executor成功後、(3)result返却直前、の3箇所で実行する
  /// （性能より正しさを優先するPhase 11Bの方針。[validateMatchStateInvariants]
  /// 単体は`spentEnergy`/`energyPool`/`koc`/`pinCardsHeld`等のplayer-level
  /// invariantを検証しないため、これらもrunnerが確実に検出できるようにする）。
  CombatV1CpuMatchResult run(
    CombatV1MatchState initialState, {
    required CombatV1DecisionPolicy policyA,
    required CombatV1DecisionPolicy policyB,
    Random? engineRandom,
    CombatV1ActionObserver? observer,
  }) {
    final rng = engineRandom ?? Random();

    final startViolation = _validateRunnerInvariants(initialState);
    if (startViolation != null) {
      return _buildResult(
        state: initialState,
        actionCount: 0,
        termination: CombatV1CpuMatchTermination.invariantViolation,
        policyAId: policyA.id,
        policyBId: policyB.id,
        violationMessage: startViolation,
      );
    }

    var state = initialState;
    var actionCount = 0;
    CombatV1LegalAction? lastAction;
    CombatV1MatchState? stateBeforeLastAction;

    while (true) {
      if (state.isOver) {
        return _buildResult(
          state: state,
          actionCount: actionCount,
          termination: CombatV1CpuMatchTermination.matchOver,
          policyAId: policyA.id,
          policyBId: policyB.id,
          lastAction: lastAction,
          terminalCause: _classifyTerminalCause(
            action: lastAction,
            stateBefore: stateBeforeLastAction,
            stateAfter: state,
          ),
        );
      }

      if (actionCount >= maxActions) {
        return _buildResult(
          state: state,
          actionCount: actionCount,
          termination: CombatV1CpuMatchTermination.safetyLimit,
          policyAId: policyA.id,
          policyBId: policyB.id,
          lastAction: lastAction,
        );
      }

      final legalActions = CombatV1LegalActionEnumerator.enumerate(
        state,
        catalog: catalog,
        rules: rules,
      );
      if (legalActions.isEmpty) {
        return _buildResult(
          state: state,
          actionCount: actionCount,
          termination: CombatV1CpuMatchTermination.invariantViolation,
          policyAId: policyA.id,
          policyBId: policyB.id,
          lastAction: lastAction,
          violationMessage: '試合未終了のstate（phase:${state.phase.name}, '
              'activePlayerIndex:${state.activePlayerIndex}）でlegal actionが'
              '0件でした。正常な非terminal stateでは発生しないはずの'
              'programming/invariant errorです。',
        );
      }

      final actor = legalActions.first.actorPlayerIndex;
      final policy = actor == 0 ? policyA : policyB;
      final chosen = policy.choose(state, legalActions);

      final stateBefore = state;
      state = CombatV1ActionExecutor.execute(
        state,
        chosen,
        catalog: catalog,
        rules: rules,
        random: rng,
      );
      final resolvedIndex = actionCount;
      actionCount += 1;
      lastAction = chosen;
      stateBeforeLastAction = stateBefore;

      observer?.onActionResolved(
        CombatV1ActionObservation(
          actionIndex: resolvedIndex,
          turnNumber: stateBefore.turnNumber,
          actorPlayerIndex: chosen.actorPlayerIndex,
          action: chosen,
          stateBefore: stateBefore,
          stateAfter: state,
        ),
      );

      final postActionViolation = _validateRunnerInvariants(state);
      if (postActionViolation != null) {
        return _buildResult(
          state: state,
          actionCount: actionCount,
          termination: CombatV1CpuMatchTermination.invariantViolation,
          policyAId: policyA.id,
          policyBId: policyB.id,
          lastAction: lastAction,
          violationMessage: postActionViolation,
        );
      }
    }
  }

  /// [state]がPhase 11Bで求める統合invariantを満たしているかを検証する。
  /// [validateMatchStateInvariants]（`CombatV1MatchState`全体の構造的
  /// 整合性）に加え、[validatePlayerStateInvariants]を`state.playerA`/
  /// `state.playerB`の両方へ適用する——`validateMatchStateInvariants`単体
  /// では`spentEnergy`が`energyPool`を超えている・`spentEnergy`が負数・
  /// `energyPool`自体が不正・`koc`が負数・`pinCardsHeld`が1未満、といった
  /// player-level invariant違反を検出できないため（Codexレビュー指摘、
  /// docs/design/combat_v1_phase11b_cpu.md参照）。
  ///
  /// 満たしていれば`null`、そうでなければ結合した人間可読メッセージ
  /// （[CombatV1CpuMatchResult.invariantViolationMessage]）を返す。
  /// Core Engine側のvalidator（`combat_v1_state_invariants.dart`）自体は
  /// 変更しない——既存の2つのAPIをrunner側で組み合わせるだけの薄いhelper。
  String? _validateRunnerInvariants(CombatV1MatchState state) {
    final messages = <String>[
      ...validateMatchStateInvariants(state, rules: rules).errors.map(
        (e) => e.message,
      ),
      ...validatePlayerStateInvariants(state.playerA).errors.map(
        (e) => e.message,
      ),
      ...validatePlayerStateInvariants(state.playerB).errors.map(
        (e) => e.message,
      ),
    ];
    return messages.isEmpty ? null : messages.join(' / ');
  }

  /// [action]の実行によって[stateBefore]（未決着）から[stateAfter]
  /// （決着済み）へ遷移した場合の[CombatV1CpuMatchTerminalCause]を返す。
  /// 決着していない、またはpublicなAction/state情報だけでは分類できない
  /// 場合は`null`または[CombatV1CpuMatchTerminalCause.other]を返す。
  ///
  /// PIN/SUBMISSIONの自動解決はいずれも[CombatV1DeclineCounterAction]（技
  /// 成功の確定Command）1回のCommand呼び出し内で完結するため
  /// （docs/combat_rules_v1.md 8・10・13章）、[CombatV1PendingAttack]が
  /// 保持する宣言時点の`category`/`finisherType`/`directPin`/
  /// `submissionHold`（いずれも公開field）だけで分類できる。通常PINは
  /// [CombatV1PinAction]（`declarePin`）以外の経路では決着しない。
  ///
  /// `CombatV1Engine._resolvePendingAttack`のeffectiveDirectPin/
  /// effectiveSubmissionHold導出（Codexレビューで確認済みの現行Engine仕様）
  /// と完全に一致する、以下の網羅的なmappingに従う
  /// （`combat_v1_cpu_terminal_cause_test.dart`で10パターンを直接検証）:
  ///
  /// - NORMAL/SIGNATURE（`category != finisher`）:
  ///   - `directPin==false && submissionHold==false` → 自動決着なし（`null`）
  ///   - `directPin==true && submissionHold==false` → [directPin]
  ///   - `directPin==false && submissionHold==true` → [submission]
  ///   - `directPin==true && submissionHold==true` → Catalog validation
  ///     （`techniqueDirectPinSubmissionHoldConflict`）で拒否されるため
  ///     到達しない
  /// - FINISHER（`category == finisher`）: `directPin`/`submissionHold`
  ///   フィールドは一切参照しない（`finisherType`のみが決着方式を決定する。
  ///   docs/design/combat_v1_phase1_design.md 2.4章）
  ///   - `finisherType == normal` → 自動決着なし（`null`）。技定義に
  ///     `directPin`/`submissionHold`が誤って`true`設定されていても無視する
  ///   - `finisherType == directPin` → [directPin]
  ///   - `finisherType == submission` → [submissionFinisher]
  static CombatV1CpuMatchTerminalCause? _classifyTerminalCause({
    required CombatV1LegalAction? action,
    required CombatV1MatchState? stateBefore,
    required CombatV1MatchState stateAfter,
  }) {
    if (action == null || stateBefore == null) return null;
    if (stateBefore.isOver || !stateAfter.isOver) return null;

    if (action is CombatV1PinAction) {
      return CombatV1CpuMatchTerminalCause.normalPin;
    }

    if (action is CombatV1DeclineCounterAction) {
      final pending = stateBefore.pendingAttack;
      if (pending == null) return CombatV1CpuMatchTerminalCause.other;

      final isFinisher = pending.category == CombatV1CardCategory.finisher;
      final effectiveDirectPin = isFinisher
          ? pending.finisherType == CombatV1FinisherType.directPin
          : pending.directPin;
      final effectiveSubmissionHold = isFinisher
          ? pending.finisherType == CombatV1FinisherType.submission
          : pending.submissionHold;

      if (effectiveDirectPin) return CombatV1CpuMatchTerminalCause.directPin;
      if (effectiveSubmissionHold) {
        return isFinisher
            ? CombatV1CpuMatchTerminalCause.submissionFinisher
            : CombatV1CpuMatchTerminalCause.submission;
      }
      return CombatV1CpuMatchTerminalCause.other;
    }

    return CombatV1CpuMatchTerminalCause.other;
  }

  /// result返却直前にもう一度invariantを検証し、[CombatV1CpuMatchResult]を
  /// 構築する（checkpoint 3）。既に[termination] ==
  /// [CombatV1CpuMatchTermination.invariantViolation]の場合は二重検証しない。
  CombatV1CpuMatchResult _buildResult({
    required CombatV1MatchState state,
    required int actionCount,
    required CombatV1CpuMatchTermination termination,
    required String policyAId,
    required String policyBId,
    CombatV1LegalAction? lastAction,
    CombatV1CpuMatchTerminalCause? terminalCause,
    String? violationMessage,
  }) {
    var finalTermination = termination;
    var message = violationMessage;
    var cause = terminalCause;

    if (finalTermination != CombatV1CpuMatchTermination.invariantViolation) {
      final finalViolation = _validateRunnerInvariants(state);
      if (finalViolation != null) {
        finalTermination = CombatV1CpuMatchTermination.invariantViolation;
        message = finalViolation;
        cause = null;
      }
    }

    return CombatV1CpuMatchResult(
      finalState: state,
      actionCount: actionCount,
      finalTurnNumber: state.turnNumber,
      termination: finalTermination,
      maxActions: maxActions,
      policyAId: policyAId,
      policyBId: policyBId,
      lastAction: lastAction,
      terminalCause: cause,
      invariantViolationMessage: message,
    );
  }
}
