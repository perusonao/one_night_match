/// CombatV1MatchLifecycle（Playable 1A、
/// docs/design/combat_v1_playable_match_ui.md）。
///
/// [CombatV1CpuMatchRunner]（Phase 11B）が個別に持っていた「統合invariant
/// 検証」「terminal cause分類」の2つのロジックを、CPU vs CPU runnerと
/// Human vs CPU Playable controllerの両方から共通で利用できる場所へ
/// 抽出したもの。ロジック自体は一切変更しない（Phase 11B
/// docs/design/combat_v1_phase11b_cpu.md・Codexレビュー指摘で確定済みの
/// 契約をそのまま移設するのみ）——CPU runnerの既存挙動・既存testはこの
/// 抽出の前後で完全に同一でなければならない。
///
/// Core Engine（`combat_v1_engine.dart`）・legality判定・damage計算・
/// PIN/SUBMISSION resolutionはこのファイルへ一切持ち込まない。責務は
/// 「読み取り専用の診断」の2つに限定する。
library;

import 'combat_v1_enums.dart';
import 'combat_v1_legal_action.dart';
import 'combat_v1_match_state.dart';
import 'combat_v1_rules_config.dart';
import 'combat_v1_state_invariants.dart';

/// [CombatV1MatchState.isOver]になった直接の原因（Phase 11B addendum
/// 「Terminal Metadata」、Playable 1Aで`combat_v1_cpu_match_runner.dart`
/// から本ファイルへ移設）。
///
/// [CombatV1PendingAttack]の公開field（`category`/`finisherType`/
/// `directPin`/`submissionHold`）のみから導出する——`CombatV1Engine`の
/// private実装（`_resolvePendingAttack`のeffectiveDirectPin/
/// effectiveSubmissionHold導出と同じ公開情報ベースの判定）を再現するのみで、
/// private stateへのアクセスやCore Engine変更は必要としない。
///
/// `combat_v1_cpu_match_runner.dart`の`CombatV1CpuMatchTerminalCause`は、
/// この型への`typedef`（完全なalias）として引き続き公開される——既存の
/// import・型参照（Simulation/Batch層・既存test）は一切変更不要。
enum CombatV1MatchTerminalCause {
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

/// [CombatV1CpuMatchRunner]・Playable
/// [CombatV1PlayableMatchController]が共通で利用する、読み取り専用の
/// lifecycle診断utility（Playable 1A）。
class CombatV1MatchLifecycle {
  const CombatV1MatchLifecycle._();

  /// [state]が統合invariantを満たしているかを検証する。
  /// [validateMatchStateInvariants]（`CombatV1MatchState`全体の構造的
  /// 整合性）に加え、[validatePlayerStateInvariants]を`state.playerA`/
  /// `state.playerB`の両方へ適用する——`validateMatchStateInvariants`単体
  /// では`spentEnergy`が`energyPool`を超えている・`spentEnergy`が負数・
  /// `energyPool`自体が不正・`koc`が負数・`pinCardsHeld`が1未満、といった
  /// player-level invariant違反を検出できないため。
  ///
  /// さらに`state.activePlayerIndex`が0/1のいずれかであることも検証する。
  /// `validateMatchStateInvariants`は`pendingAttack`が存在する場合の
  /// `attackerPlayerIndex`/`defenderPlayerIndex`・`winnerPlayerIndex`の
  /// 範囲は検証するが、`pendingAttack`が`null`の場合（match開始直後・
  /// `action`/`discard`フェーズ中等）は`activePlayerIndex`自体の範囲を
  /// 検証しない。`CombatV1MatchState.active`/`opponent`は`activePlayerIndex
  /// == 0`以外を無条件にplayerB側として扱うため、この検証が無いまま
  /// 呼び出し側がactor選択・[CombatV1LegalActionEnumerator]・
  /// [CombatV1ActionExecutor]まで進んでしまうと、範囲外の
  /// activePlayerIndex（例: `-1`・`2`）がpolicy/human dispatchへsilentに
  /// 渡ってしまう。ここで検出することで、actor解決・action実行へ進む前に
  /// 必ず違反として停止できる。
  ///
  /// 満たしていれば`null`、そうでなければ結合した人間可読メッセージを
  /// 返す。Core Engine側のvalidator（`combat_v1_state_invariants.dart`）
  /// 自体は変更しない——既存の2つのAPIをここで組み合わせ、
  /// 呼び出し側共通の追加チェックを1件加えるだけの薄いhelper（Phase 11B
  /// `CombatV1CpuMatchRunner._validateRunnerInvariants`と完全に同じ
  /// ロジック・同じメッセージ文言）。
  static String? validateIntegratedInvariants(
    CombatV1MatchState state, {
    required CombatV1RulesConfig rules,
  }) {
    final messages = <String>[
      if (state.activePlayerIndex != 0 && state.activePlayerIndex != 1)
        'activePlayerIndexが0/1のいずれでもありません'
            '（activePlayerIndex:${state.activePlayerIndex}）。'
            'policy dispatch・action実行より前にrunner invariant違反として'
            '検出しました。',
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
  /// （決着済み）へ遷移した場合の[CombatV1MatchTerminalCause]を返す。
  /// 決着していない、またはpublicなAction/state情報だけでは分類できない
  /// 場合は`null`または[CombatV1MatchTerminalCause.other]を返す。
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
  static CombatV1MatchTerminalCause? classifyTerminalCause({
    required CombatV1LegalAction? action,
    required CombatV1MatchState? stateBefore,
    required CombatV1MatchState stateAfter,
  }) {
    if (action == null || stateBefore == null) return null;
    if (stateBefore.isOver || !stateAfter.isOver) return null;

    if (action is CombatV1PinAction) {
      return CombatV1MatchTerminalCause.normalPin;
    }

    if (action is CombatV1DeclineCounterAction) {
      final pending = stateBefore.pendingAttack;
      if (pending == null) return CombatV1MatchTerminalCause.other;

      final isFinisher = pending.category == CombatV1CardCategory.finisher;
      final effectiveDirectPin = isFinisher
          ? pending.finisherType == CombatV1FinisherType.directPin
          : pending.directPin;
      final effectiveSubmissionHold = isFinisher
          ? pending.finisherType == CombatV1FinisherType.submission
          : pending.submissionHold;

      if (effectiveDirectPin) return CombatV1MatchTerminalCause.directPin;
      if (effectiveSubmissionHold) {
        return isFinisher
            ? CombatV1MatchTerminalCause.submissionFinisher
            : CombatV1MatchTerminalCause.submission;
      }
      return CombatV1MatchTerminalCause.other;
    }

    return CombatV1MatchTerminalCause.other;
  }
}
