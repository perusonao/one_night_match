/// Combat Ver.1 Playable 1C — Action Feedback pure formatting helpers
/// （docs/design/combat_v1_playable_match_ui.md Playable 1C追記「Action
/// Feedback Model」「Presentation」、Playable 2A-4「Match Flow / Result
/// Feedback Readability」追記）。
///
/// `combat_v1_playable_ui_formatters.dart`（Playable 1B）と同じ方針:
/// Flutter widget treeを一切構築しない、副作用のないpure functionのみ。
/// [CombatV1PlayableActionFeedback]（Playable 1A/1Cのcontroller/session層が
/// before/after `CombatV1MatchState`差分から構築したhidden-safe value
/// object）の値をUI表示用のHuman-readable文字列へ変換するだけで、
/// damage・PIN/SUBMISSION判定等いかなるEngineロジックも再計算・再実装
/// しない。
///
/// Playable 2A-4では、この既存formatter層へ
/// [combatV1PlayableDeriveMatchFeedback]（Match Guidance/Match
/// Directionと同じ「primary + secondary」構成のResult Feedback
/// derivation）と[combatV1PlayableFeedbackSeverity]（情報階層Tier）を
/// 追加した——「1件のfeedbackをどう文字列化するか」という責務は変わら
/// ないため、別系統のderivation fileを新設せずこのfileを拡張する。
library;

import '../combat_v1_enums.dart';
import '../playable/combat_v1_playable_action_feedback.dart';
import 'combat_v1_playable_ui_formatters.dart';

String _actorLabel(int playerIndex, {required int humanPlayerIndex}) =>
    playerIndex == humanPlayerIndex ? 'YOU' : 'CPU';

/// [feedback]の中心人物（[CombatV1PlayableActionFeedback.actorPlayerIndex]）
/// のラベル（`YOU`/`CPU`）。
String combatV1PlayableFeedbackActorLabel(
  CombatV1PlayableActionFeedback feedback, {
  required int humanPlayerIndex,
}) => _actorLabel(feedback.actorPlayerIndex, humanPlayerIndex: humanPlayerIndex);

String _pinOutcomeLabel(CombatV1PlayablePinFeedbackOutcome outcome) =>
    switch (outcome) {
      CombatV1PlayablePinFeedbackOutcome.kickOut => 'KICK OUT!',
      CombatV1PlayablePinFeedbackOutcome.matchOver => '3 COUNT — MATCH OVER',
    };

String _submissionOutcomeLabel(CombatV1PlayableSubmissionFeedbackOutcome outcome) =>
    switch (outcome) {
      CombatV1PlayableSubmissionFeedbackOutcome.escaped => 'ESCAPED',
      CombatV1PlayableSubmissionFeedbackOutcome.matchOver =>
        'GIVE UP — MATCH OVER',
    };

/// Playable 2A-4「Result Feedback Information Hierarchy」——
/// [CombatV1PlayableActionFeedback]1件がどの優先度階層に属するかを表す
/// （docs/design/combat_v1_playable_match_ui.md「Result Feedbackの情報
/// 階層」）。値そのものは表示スタイル分岐（強調度など）専用の識別子で
/// あり、優先順位判定ロジック自体は[combatV1PlayableFeedbackSeverity]へ
/// 集約する（`CombatV1PlayableMatchDirectionKind`と同じ方針）。
enum CombatV1PlayableFeedbackSeverity {
  /// Tier 1: 試合結果に直結（3-count/GIVE UPによるMatch Over・FINISHER
  /// resolution）。
  matchDecisive,

  /// Tier 2: 大きな状態変化（PIN・SUBMISSION・COUNTER成立・DOWN）。
  majorStateChange,

  /// Tier 3: 通常のTechnique結果（成功・DMG・HEAT・posture）。
  techniqueResult,

  /// Tier 4: 補助イベント（discard・turn transition・Stand Up・Rest・
  /// Technique宣言）。
  minorEvent,
}

/// [feedback]の[CombatV1PlayableFeedbackSeverity]を導出する。既に
/// [feedback]自身が保持する値（`kind`・`pinOutcome`・`submissionOutcome`・
/// `isFinisher`・posture before/after）だけから判定し、新しいCombat
/// ruleの判定は一切行わない。
CombatV1PlayableFeedbackSeverity combatV1PlayableFeedbackSeverity(
  CombatV1PlayableActionFeedback feedback,
) {
  final matchOver =
      feedback.pinOutcome == CombatV1PlayablePinFeedbackOutcome.matchOver ||
      feedback.submissionOutcome ==
          CombatV1PlayableSubmissionFeedbackOutcome.matchOver;
  if (matchOver || feedback.isFinisher) {
    return CombatV1PlayableFeedbackSeverity.matchDecisive;
  }
  switch (feedback.kind) {
    case CombatV1PlayableFeedbackKind.pinResolved:
    case CombatV1PlayableFeedbackKind.counterPlayed:
      return CombatV1PlayableFeedbackSeverity.majorStateChange;
    case CombatV1PlayableFeedbackKind.techniqueResolved:
      final becameDown =
          feedback.postureBefore != null &&
          feedback.postureBefore != CombatV1WrestlerPosture.down &&
          feedback.postureAfter == CombatV1WrestlerPosture.down;
      if (feedback.pinOutcome != null ||
          feedback.submissionOutcome != null ||
          becameDown) {
        return CombatV1PlayableFeedbackSeverity.majorStateChange;
      }
      return CombatV1PlayableFeedbackSeverity.techniqueResult;
    case CombatV1PlayableFeedbackKind.discard:
    case CombatV1PlayableFeedbackKind.techniqueDeclared:
    case CombatV1PlayableFeedbackKind.rest:
    case CombatV1PlayableFeedbackKind.standUp:
    case CombatV1PlayableFeedbackKind.endTurn:
      return CombatV1PlayableFeedbackSeverity.minorEvent;
  }
}

/// Playable 2A-4「Latest Result — Primary / Secondary」
/// （docs/design/combat_v1_playable_match_ui.md）——[feedback]から
/// 導出した、Match Guidance/Match Directionと同じ「primary 1文 +
/// 必要時のみsecondary 1文」構成のUI-oriented model。事実のみを述べ
/// （過去形）、戦術的な評価（Match Directionの責務）は含めない。
class CombatV1PlayableMatchFeedback {
  const CombatV1PlayableMatchFeedback({
    required this.severity,
    required this.primary,
    this.secondary,
  });

  final CombatV1PlayableFeedbackSeverity severity;

  /// 「何が起きたか」の中心的事実（例:「YOU — Dropkick — 20 DAMAGE」）。
  final String primary;

  /// [primary]の結果として生じた状態変化（例:「CPU HP 80 → 60 · HEAT
  /// +20」）。該当する変化が無い場合は`null`——推測で埋めない。
  final String? secondary;
}

/// [feedback]から[CombatV1PlayableMatchFeedback]を導出する。damage・HP/
/// posture/HEAT/KOC変化・PIN/SUBMISSION結果はすべて[feedback]が既に
/// 保持する実測値をそのまま文字列化するだけで、新しいCombat rule判定は
/// 一切行わない（37章「Do Not Fabricate Deltas」を維持）。
CombatV1PlayableMatchFeedback combatV1PlayableDeriveMatchFeedback(
  CombatV1PlayableActionFeedback feedback, {
  required int humanPlayerIndex,
}) {
  final actor = _actorLabel(
    feedback.actorPlayerIndex,
    humanPlayerIndex: humanPlayerIndex,
  );
  final severity = combatV1PlayableFeedbackSeverity(feedback);
  switch (feedback.kind) {
    case CombatV1PlayableFeedbackKind.discard:
      return CombatV1PlayableMatchFeedback(
        severity: severity,
        primary: '$actor discarded a card',
      );
    case CombatV1PlayableFeedbackKind.endTurn:
      return CombatV1PlayableMatchFeedback(
        severity: severity,
        primary: '$actor ended the turn',
      );
    case CombatV1PlayableFeedbackKind.standUp:
      return CombatV1PlayableMatchFeedback(
        severity: severity,
        primary: '$actor stood up',
      );
    case CombatV1PlayableFeedbackKind.rest:
      final before = feedback.hpBefore;
      final after = feedback.hpAfter;
      return CombatV1PlayableMatchFeedback(
        severity: severity,
        primary: '$actor rested',
        secondary: (before != null && after != null)
            ? '$actor HP $before → $after'
            : null,
      );
    case CombatV1PlayableFeedbackKind.techniqueDeclared:
      final name = feedback.actionDisplayName;
      return CombatV1PlayableMatchFeedback(
        severity: severity,
        primary: name == null
            ? '$actor declared a technique'
            : '$actor declared $name',
        secondary: 'Awaiting Counter response',
      );
    case CombatV1PlayableFeedbackKind.counterPlayed:
      return _deriveCounterFeedback(feedback, actor: actor, severity: severity);
    case CombatV1PlayableFeedbackKind.pinResolved:
      return _derivePinResolvedFeedback(
        feedback,
        actor: actor,
        severity: severity,
        humanPlayerIndex: humanPlayerIndex,
      );
    case CombatV1PlayableFeedbackKind.techniqueResolved:
      return _deriveTechniqueResolvedFeedback(
        feedback,
        actor: actor,
        severity: severity,
        humanPlayerIndex: humanPlayerIndex,
      );
  }
}

CombatV1PlayableMatchFeedback _derivePinResolvedFeedback(
  CombatV1PlayableActionFeedback feedback, {
  required String actor,
  required CombatV1PlayableFeedbackSeverity severity,
  required int humanPlayerIndex,
}) {
  final outcome = feedback.pinOutcome;
  final primary = outcome == null
      ? '$actor — PIN ATTEMPT'
      : '$actor — PIN ATTEMPT — ${_pinOutcomeLabel(outcome)}';

  final kocBefore = feedback.kocBefore;
  final kocAfter = feedback.kocAfter;
  final kocOwner = feedback.kocOwnerPlayerIndex;
  final secondary = (kocBefore != null && kocAfter != null && kocOwner != null)
      ? '${_actorLabel(kocOwner, humanPlayerIndex: humanPlayerIndex)} '
            'KOC $kocBefore → $kocAfter'
      : null;

  return CombatV1PlayableMatchFeedback(
    severity: severity,
    primary: primary,
    secondary: secondary,
  );
}

CombatV1PlayableMatchFeedback _deriveTechniqueResolvedFeedback(
  CombatV1PlayableActionFeedback feedback, {
  required String actor,
  required CombatV1PlayableFeedbackSeverity severity,
  required int humanPlayerIndex,
}) {
  final name = feedback.actionDisplayName;
  final label = feedback.isFinisher
      ? (name == null ? 'FINISHER' : '$name (FINISHER)')
      : (name ?? 'a technique');
  final damage = feedback.damage;
  final primaryBuffer = StringBuffer('$actor — $label');
  if (damage != null) {
    primaryBuffer.write(' — $damage DAMAGE');
  }

  final secondaryParts = <String>[];

  final hpBefore = feedback.hpBefore;
  final hpAfter = feedback.hpAfter;
  final hpOwner = feedback.hpOwnerPlayerIndex;
  if (hpBefore != null && hpAfter != null && hpOwner != null) {
    secondaryParts.add(
      '${_actorLabel(hpOwner, humanPlayerIndex: humanPlayerIndex)} '
      'HP $hpBefore → $hpAfter',
    );
  }

  final postureBefore = feedback.postureBefore;
  final postureAfter = feedback.postureAfter;
  if (postureBefore != null &&
      postureAfter != null &&
      postureBefore != postureAfter) {
    secondaryParts.add(
      '${combatV1PlayablePostureLabel(postureBefore)} → '
      '${combatV1PlayablePostureLabel(postureAfter)}',
    );
  }

  final heatBefore = feedback.heatBefore;
  final heatAfter = feedback.heatAfter;
  if (heatBefore != null && heatAfter != null && heatAfter != heatBefore) {
    final delta = heatAfter - heatBefore;
    secondaryParts.add('HEAT ${delta >= 0 ? '+' : ''}$delta');
  }

  final pinOutcome = feedback.pinOutcome;
  if (pinOutcome != null) {
    secondaryParts.add('PIN ATTEMPT — ${_pinOutcomeLabel(pinOutcome)}');
  }
  final submissionOutcome = feedback.submissionOutcome;
  if (submissionOutcome != null) {
    secondaryParts.add('SUBMISSION — ${_submissionOutcomeLabel(submissionOutcome)}');
  }

  final kocBefore = feedback.kocBefore;
  final kocAfter = feedback.kocAfter;
  final kocOwner = feedback.kocOwnerPlayerIndex;
  if ((pinOutcome != null || submissionOutcome != null) &&
      kocBefore != null &&
      kocAfter != null &&
      kocOwner != null) {
    secondaryParts.add(
      '${_actorLabel(kocOwner, humanPlayerIndex: humanPlayerIndex)} '
      'KOC $kocBefore → $kocAfter',
    );
  }

  return CombatV1PlayableMatchFeedback(
    severity: severity,
    primary: primaryBuffer.toString(),
    secondary: secondaryParts.isEmpty ? null : secondaryParts.join(' · '),
  );
}

/// Playable 2A-4「Counter Result — Prevents Summary」——design doc
/// 「76章」の`combatV1PlayableCounterPreventsSummary`（Counter Prompt
/// Sheet向け、成立"すると"防げる、という宣言前の条件文）と同じ事実を、
/// Latest Result向けの過去形（実際に防いだ）へ言い換える。Core rule・
/// 判定対象のbool値はいずれも[feedback]（`preventedDirectPin`/
/// `preventedSubmissionHold`/`preventedIsRough`）由来であり、新しい
/// 判定はここでは行わない。
CombatV1PlayableMatchFeedback _deriveCounterFeedback(
  CombatV1PlayableActionFeedback feedback, {
  required String actor,
  required CombatV1PlayableFeedbackSeverity severity,
}) {
  final name = feedback.actionDisplayName;
  final primary = name == null
      ? '$actor countered the attack'
      : '$actor countered with $name';

  final prevented = <String>[
    'DMG',
    'HEAT',
    'state changes',
    if (feedback.preventedDirectPin) 'the automatic PIN transition',
    if (feedback.preventedSubmissionHold)
      'the SUBMISSION transition condition',
  ];
  final relatedName = feedback.relatedActionDisplayName;
  final preventedSummary = relatedName == null
      ? 'Prevented ${_joinEnglishList(prevented)}'
      : '$relatedName was nullified — prevented ${_joinEnglishList(prevented)}';

  final secondaryParts = <String>[preventedSummary];
  if (feedback.preventedIsRough) {
    // Playable 2A-3「86章 ROUGH + Counter — 非対称性」と同じ2つの事実
    // （宣言時点で確定するPIN不可はCounterされても取り消されない／
    // 成立ベースの次ターンTECHNIQUE制限はCounterで防げる）を、過去形
    // のLatest Result向けに言い換えるだけで、新しいCombat ruleではない。
    secondaryParts.add(
      'Attacker still cannot PIN this turn (locked in at declaration); '
      'the next-turn TECHNIQUE limit was prevented',
    );
  }

  return CombatV1PlayableMatchFeedback(
    severity: severity,
    primary: primary,
    secondary: secondaryParts.join(' '),
  );
}

String _joinEnglishList(List<String> items) {
  if (items.length == 1) return items.single;
  return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
}

/// recent log（compact list）用の1行summary。
String combatV1PlayableFeedbackCompactLabel(
  CombatV1PlayableActionFeedback feedback, {
  required int humanPlayerIndex,
}) {
  final actor = _actorLabel(feedback.actorPlayerIndex, humanPlayerIndex: humanPlayerIndex);
  final name = feedback.actionDisplayName;
  final buffer = StringBuffer(actor)..write(': ');

  switch (feedback.kind) {
    case CombatV1PlayableFeedbackKind.discard:
      buffer.write('discarded a card');
    case CombatV1PlayableFeedbackKind.techniqueDeclared:
      buffer.write(name == null ? 'declared a technique' : 'declared $name');
    case CombatV1PlayableFeedbackKind.techniqueResolved:
      buffer.write(name ?? 'technique landed');
      if (feedback.damage != null) {
        buffer.write(' ${feedback.damage}DMG');
      }
      if (feedback.pinOutcome != null) {
        buffer.write(
          feedback.pinOutcome == CombatV1PlayablePinFeedbackOutcome.matchOver
              ? ' · PIN WIN'
              : ' · KICK OUT',
        );
      }
      if (feedback.submissionOutcome != null) {
        buffer.write(
          feedback.submissionOutcome ==
                  CombatV1PlayableSubmissionFeedbackOutcome.matchOver
              ? ' · SUBMISSION WIN'
              : ' · ESCAPED',
        );
      }
    case CombatV1PlayableFeedbackKind.counterPlayed:
      buffer.write(name == null ? 'countered' : 'countered with $name');
    case CombatV1PlayableFeedbackKind.pinResolved:
      buffer.write(
        feedback.pinOutcome == CombatV1PlayablePinFeedbackOutcome.matchOver
            ? 'PIN → MATCH OVER'
            : 'PIN → KICK OUT',
      );
    case CombatV1PlayableFeedbackKind.rest:
      final before = feedback.hpBefore;
      final after = feedback.hpAfter;
      if (before != null && after != null) {
        buffer.write('REST +${after - before} HP');
      } else {
        buffer.write('REST');
      }
    case CombatV1PlayableFeedbackKind.standUp:
      buffer.write('stood up');
    case CombatV1PlayableFeedbackKind.endTurn:
      buffer.write('ended turn');
  }

  return buffer.toString();
}
