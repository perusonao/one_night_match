/// Combat Ver.1 Playable 1C — Action Feedback pure formatting helpers
/// （docs/design/combat_v1_playable_match_ui.md Playable 1C追記「Action
/// Feedback Model」「Presentation」）。
///
/// `combat_v1_playable_ui_formatters.dart`（Playable 1B）と同じ方針:
/// Flutter widget treeを一切構築しない、副作用のないpure functionのみ。
/// [CombatV1PlayableActionFeedback]（Playable 1A/1Cのcontroller/session層が
/// before/after `CombatV1MatchState`差分から構築したhidden-safe value
/// object）の値をUI表示用のHuman-readable文字列へ変換するだけで、
/// damage・PIN/SUBMISSION判定等いかなるEngineロジックも再計算・再実装
/// しない。
library;

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

/// 大きめbanner用のtitle行（design doc「Action Result Feedback」例:
/// 「YOU — ドロップキック」）。
String combatV1PlayableFeedbackTitle(
  CombatV1PlayableActionFeedback feedback, {
  required int humanPlayerIndex,
}) {
  final actor = _actorLabel(feedback.actorPlayerIndex, humanPlayerIndex: humanPlayerIndex);
  final name = feedback.actionDisplayName;
  return switch (feedback.kind) {
    CombatV1PlayableFeedbackKind.discard => '$actor discarded a card',
    CombatV1PlayableFeedbackKind.techniqueDeclared =>
      name == null ? '$actor declared a technique' : '$actor declared $name',
    CombatV1PlayableFeedbackKind.techniqueResolved =>
      name == null ? actor : '$actor — $name',
    CombatV1PlayableFeedbackKind.counterPlayed =>
      name == null ? '$actor countered the attack' : '$actor countered with $name',
    CombatV1PlayableFeedbackKind.pinResolved => '$actor — PIN ATTEMPT',
    CombatV1PlayableFeedbackKind.rest => '$actor — REST',
    CombatV1PlayableFeedbackKind.standUp => '$actor stood up',
    CombatV1PlayableFeedbackKind.endTurn => '$actor ended the turn',
  };
}

/// banner本体の詳細行（damage・HP変化・posture変化・HEAT変化・KOC変化・
/// PIN/SUBMISSION結果）。値が無い（該当しない）行は含めない——推測で
/// 埋めない（design doc「Do Not Fabricate Deltas」）。
List<String> combatV1PlayableFeedbackDetailLines(
  CombatV1PlayableActionFeedback feedback, {
  required int humanPlayerIndex,
}) {
  final lines = <String>[];

  if (feedback.kind == CombatV1PlayableFeedbackKind.counterPlayed &&
      feedback.relatedActionDisplayName != null) {
    lines.add('${feedback.relatedActionDisplayName} was nullified — no damage');
  }

  if (feedback.damage != null) {
    lines.add('${feedback.damage} DAMAGE');
  }

  final hpBefore = feedback.hpBefore;
  final hpAfter = feedback.hpAfter;
  final hpOwner = feedback.hpOwnerPlayerIndex;
  if (hpBefore != null && hpAfter != null && hpOwner != null) {
    final owner = _actorLabel(hpOwner, humanPlayerIndex: humanPlayerIndex);
    lines.add('$owner HP $hpBefore → $hpAfter');
  }

  final postureBefore = feedback.postureBefore;
  final postureAfter = feedback.postureAfter;
  if (postureBefore != null && postureAfter != null && postureBefore != postureAfter) {
    lines.add(
      '${combatV1PlayablePostureLabel(postureBefore)} → '
      '${combatV1PlayablePostureLabel(postureAfter)}',
    );
  }

  final heatBefore = feedback.heatBefore;
  final heatAfter = feedback.heatAfter;
  if (heatBefore != null && heatAfter != null && heatAfter != heatBefore) {
    final delta = heatAfter - heatBefore;
    lines.add('HEAT ${delta >= 0 ? '+' : ''}$delta');
  }

  final kocBefore = feedback.kocBefore;
  final kocAfter = feedback.kocAfter;
  final kocOwner = feedback.kocOwnerPlayerIndex;
  if (kocBefore != null && kocAfter != null && kocOwner != null) {
    final owner = _actorLabel(kocOwner, humanPlayerIndex: humanPlayerIndex);
    lines.add('$owner KOC $kocBefore → $kocAfter');
  }

  if (feedback.kind != CombatV1PlayableFeedbackKind.pinResolved &&
      feedback.pinOutcome != null) {
    lines.add('PIN ATTEMPT');
  }
  if (feedback.pinOutcome != null) {
    lines.add(_pinOutcomeLabel(feedback.pinOutcome!));
  }

  if (feedback.submissionOutcome != null) {
    lines.add('SUBMISSION');
    lines.add(_submissionOutcomeLabel(feedback.submissionOutcome!));
  }

  return lines;
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
