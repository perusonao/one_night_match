/// Combat Ver.1 Playable 1C — Action Result Feedback
/// （docs/design/combat_v1_playable_match_ui.md Playable 1C追記「Action
/// Feedback Model」）。
///
/// `CombatV1PlayableMatchController`が各actionの実行直後（before/after
/// `CombatV1MatchState`の比較）に構築する、pure presentation-only value
/// object。damage・PIN/SUBMISSION結果等はいずれもEngine側の実際の
/// state遷移から導出した“実際に起きた事実”のみを保持し、Technique
/// metadataの宣言値（`CombatV1Technique.damage`等）をそのまま「実際の
/// 結果」として扱わない（Playable 1C「Do Not Fabricate Deltas」方針）。
///
/// UI/Widget層はこのオブジェクトの値をそのまま表示するだけで、legality・
/// damage・PIN/SUBMISSION判定を一切再計算しない——それらは全て
/// controller（`combat_v1_playable_match_controller.dart`）が、既存Core
/// Engineが返した before/after state と、Technique/Counter Catalogの
/// **公開されている**静的カードテキスト（宣言済みのカードは両者に公開済み
/// のため、hidden information違反にならない）だけを使って構築する。
library;

import '../combat_v1_enums.dart';

/// [CombatV1PlayableActionFeedback]の8 variant（Playable
/// 1A/1Bの`CombatV1LegalActionKind`とは異なる、UI表示用の粒度）。
///
/// `technique`宣言（`CombatV1LegalActionKind.technique`）と
/// TECHNIQUE成立解決（`declineCounter`）は別のfeedback kindとして扱う
/// ——宣言時点ではdamage/HP/posture/HEATはまだ確定していないため
/// （Core Engineは`counterResponsePending`を経由するまでTECHNIQUEの効果を
/// 適用しない）。
enum CombatV1PlayableFeedbackKind {
  /// 手札から1枚捨てた（discard phase）。
  discard,

  /// TECHNIQUEを宣言した（まだCOUNTER応答待ち、効果未確定）。
  techniqueDeclared,

  /// 宣言済みTECHNIQUEがCOUNTERされず成立した（`declineCounter`。DIRECT
  /// PIN/SUBMISSIONへの自動移行が同一actionで起きた場合、[pinOutcome]/
  /// [submissionOutcome]も併せて非nullになる）。
  techniqueResolved,

  /// COUNTERで応答し、攻撃を無効化した。
  counterPlayed,

  /// 通常PIN（`declarePin`）を宣言し、同一action内で解決した。
  pinResolved,

  /// RESTでHPを回復した。
  rest,

  /// DOWNから起き上がった。
  standUp,

  /// ターンを終了した。
  endTurn,
}

/// PIN解決の結果（通常PIN宣言、またはTECHNIQUE成立に伴うDIRECT PIN自動
/// 移行のいずれか）。
enum CombatV1PlayablePinFeedbackOutcome {
  /// 防御側がKOCを支払いキックアウトした（試合continue）。
  kickOut,

  /// 防御側がKOCを支払えず、3カウントで試合が決着した。
  matchOver,
}

/// SUBMISSION解決の結果（TECHNIQUE成立に伴う自動移行）。
enum CombatV1PlayableSubmissionFeedbackOutcome {
  /// 防御側がKOCを支払いESCAPEした（試合continue）。
  escaped,

  /// 防御側がESCAPEできず（KOC不足、またはFINISHER SUBMISSIONのHP0）、
  /// GIVE UPで試合が決着した。
  matchOver,
}

/// 1件のactionから導出した、hidden-safeなfeedback（Playable 1C）。
///
/// 全fieldは「そのactionのbefore/after `CombatV1MatchState`から実際に
/// 観測された事実」または「既に公開された（宣言済み・使用済みの）
/// カードの静的テキスト」のみを保持する。値の意味は[kind]によって決まり、
/// 該当しないfieldは`null`のままにする（推測でデフォルト値を埋めない）。
class CombatV1PlayableActionFeedback {
  const CombatV1PlayableActionFeedback({
    required this.actionIndex,
    required this.turnNumber,
    required this.kind,
    required this.actorPlayerIndex,
    this.opponentPlayerIndex,
    this.actionDisplayName,
    this.relatedActionDisplayName,
    this.damage,
    this.hpOwnerPlayerIndex,
    this.hpBefore,
    this.hpAfter,
    this.postureOwnerPlayerIndex,
    this.postureBefore,
    this.postureAfter,
    this.heatBefore,
    this.heatAfter,
    this.kocOwnerPlayerIndex,
    this.kocBefore,
    this.kocAfter,
    this.pinOutcome,
    this.submissionOutcome,
  });

  /// [CombatV1PlayableObservation.actionIndex]と同じ通し番号（1:1で対応）。
  final int actionIndex;

  final int turnNumber;

  final CombatV1PlayableFeedbackKind kind;

  /// このfeedbackの中心人物（TECHNIQUE成立解決では攻撃側、COUNTERでは
  /// 防御側など、`kind`によって「actionを実行したplayerIndex」とは
  /// 異なる場合がある——例えば`declineCounter`の`actorPlayerIndex`
  /// （`CombatV1LegalAction.actorPlayerIndex`）は防御側だが、
  /// feedback上の主役は攻撃した技なので攻撃側を[actorPlayerIndex]とする）。
  final int actorPlayerIndex;

  final int? opponentPlayerIndex;

  /// TECHNIQUE/COUNTERの表示名（Production Card Catalogの静的定義）。
  /// 宣言・使用済みの（＝既に両者へ公開された）カードのみを対象とする。
  final String? actionDisplayName;

  /// `counterPlayed`のみ非null: COUNTERで無効化された攻撃側TECHNIQUEの
  /// 表示名。
  final String? relatedActionDisplayName;

  /// 実際に適用されたdamage（before/after HP差分から導出。Technique
  /// metadataの宣言値をそのまま使わない）。
  final int? damage;

  final int? hpOwnerPlayerIndex;
  final int? hpBefore;
  final int? hpAfter;

  final int? postureOwnerPlayerIndex;
  final CombatV1WrestlerPosture? postureBefore;
  final CombatV1WrestlerPosture? postureAfter;

  /// 共有HEAT（`CombatV1MatchState.sharedHeat`）のbefore/after。
  final int? heatBefore;
  final int? heatAfter;

  final int? kocOwnerPlayerIndex;
  final int? kocBefore;
  final int? kocAfter;

  final CombatV1PlayablePinFeedbackOutcome? pinOutcome;
  final CombatV1PlayableSubmissionFeedbackOutcome? submissionOutcome;
}
