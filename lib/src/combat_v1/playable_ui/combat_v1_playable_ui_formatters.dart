/// Combat Ver.1 Playable 1B — pure UI formatting helpers
/// （docs/design/combat_v1_playable_match_ui.md Playable 1B追記「75章 View
/// Model」「76章 Formatters」）。
///
/// このファイルはFlutter widget treeを一切構築しない、副作用のない
/// pure functionのみを持つ——Playable 1A public API（snapshot/enum群）の
/// 値をUI表示用のHuman-readable文字列へ変換するだけで、legality・
/// damage・terminal cause等いかなるEngineロジックも再計算・再実装しない。
library;

import '../combat_v1_energy.dart';
import '../combat_v1_enums.dart';
import '../combat_v1_legal_action.dart';
import '../combat_v1_match_lifecycle.dart';
import '../combat_v1_production_match_setup.dart';
import '../playable/combat_v1_playable_match_snapshot.dart';

/// Production wrestlerId → 表示順の固定リスト（misaki → jack → akari →
/// reina）。Simulation/Batch package（`combatV1DefaultBatchWrestlerIds`）
/// へは依存させず、Playable UI専用に独立して定義する（design doc「12章
/// CPU Policy Injection」と同じ、パッケージ間の望まない依存方向を避ける
/// 設計判断）。
const List<String> combatV1PlayableWrestlerOrder = [
  'misaki',
  'jack',
  'akari',
  'reina',
];

/// [wrestlerId]の表示名を、`combatV1ProductionWrestlerRegistry`
/// （唯一のsource of truth）から解決する。UI literalでレスラー名を
/// 重複管理しない（design doc「9章 Setup Screen」）。
String combatV1PlayableWrestlerDisplayName(String wrestlerId) {
  final entry = combatV1ProductionWrestlerRegistry[wrestlerId];
  if (entry == null) {
    throw StateError(
      '未知のProduction wrestlerIdです（Playable display name lookup）: '
      '$wrestlerId',
    );
  }
  return entry.wrestler.name;
}

/// 中央に表示する「現在のactor」ラベル（design doc「21章 Current Actor
/// Display」）。`activePlayerIndex`だけでなく、
/// `currentActorPlayerIndex`/`isHumanInputRequired`/`phase`/
/// `pendingAttack`を合わせて判定する。
String combatV1PlayableActorLabel({
  required CombatV1PlayableControllerStatus status,
  required CombatV1MatchPhase phase,
  required bool isHumanInputRequired,
  required int? currentActorPlayerIndex,
  required bool hasPendingAttack,
}) {
  if (status != CombatV1PlayableControllerStatus.active) {
    return '試合終了';
  }
  final isCounterPhase = phase == CombatV1MatchPhase.counterResponsePending &&
      hasPendingAttack;
  if (isHumanInputRequired) {
    return isCounterPhase ? '返し技を選択' : 'あなたのターン';
  }
  if (currentActorPlayerIndex == null) {
    return '試合終了';
  }
  return isCounterPhase ? 'CPUが返し技を選択' : 'CPU行動中';
}

/// [CombatV1MatchTerminalCause]のUI表示label（design doc「51章 Terminal
/// Cause Label」）。勝因の判定自体はここで行わない——Engineが確定した
/// [cause]を機械的にmapするだけ。
String combatV1PlayableTerminalCauseLabel(CombatV1MatchTerminalCause cause) =>
    switch (cause) {
      CombatV1MatchTerminalCause.normalPin => 'PIN',
      CombatV1MatchTerminalCause.directPin => 'Direct PIN',
      CombatV1MatchTerminalCause.submission => 'Submission',
      CombatV1MatchTerminalCause.submissionFinisher => 'Submission Finisher',
      CombatV1MatchTerminalCause.other => 'Match Over',
    };

/// [CombatV1WrestlerPosture]のUI表示label（design doc「27章 Posture」）。
String combatV1PlayablePostureLabel(CombatV1WrestlerPosture posture) =>
    switch (posture) {
      CombatV1WrestlerPosture.stand => 'STAND',
      CombatV1WrestlerPosture.down => 'DOWN',
    };

/// [CombatV1MatchPhase]のUI表示label。
String combatV1PlayablePhaseLabel(CombatV1MatchPhase phase) => switch (phase) {
  CombatV1MatchPhase.setup => 'Setup',
  CombatV1MatchPhase.discard => 'Discard',
  CombatV1MatchPhase.action => 'Action',
  CombatV1MatchPhase.counterResponsePending => 'Counter',
  CombatV1MatchPhase.turnEnd => 'Turn End',
};

/// [CombatV1CardCategory]のUI表示label（design doc「28章 Human Hand
/// UI」）。
String combatV1PlayableCategoryLabel(CombatV1CardCategory category) =>
    switch (category) {
      CombatV1CardCategory.normal => 'NORMAL',
      CombatV1CardCategory.signature => 'SIGNATURE',
      CombatV1CardCategory.finisher => 'FINISHER',
      CombatV1CardCategory.counter => 'COUNTER',
    };

/// [CombatV1LegalActionKind]のUI表示label（primary action button文言、
/// design doc「32章 Action Groups」）。
String combatV1PlayableActionKindLabel(CombatV1LegalActionKind kind) =>
    switch (kind) {
      CombatV1LegalActionKind.discard => 'Discard',
      CombatV1LegalActionKind.technique => 'Use Technique',
      CombatV1LegalActionKind.counter => 'Play Counter',
      CombatV1LegalActionKind.declineCounter => '技を受ける',
      CombatV1LegalActionKind.pin => 'PIN',
      CombatV1LegalActionKind.rest => 'Rest',
      CombatV1LegalActionKind.standUp => 'Stand Up',
      CombatV1LegalActionKind.endTurn => 'End Turn',
    };

/// recent action 1件の要約label（design doc「45章 Action Feedback」「46章
/// Recent Log」）。damage等をCore再計算せず、actor（YOU/CPU）＋action
/// kindのみで表現する——CPUが使用したカードの表示名はhidden-safe
/// snapshotから安全に解決できないため（Human自身のhandは公開情報だが、
/// discard/使用済みcardは既にhandから抜けており、CPU側は常に非公開の
/// ため）、kind-based labelに留める（design doc追記、53章参照）。
String combatV1PlayableObservationLabel(
  CombatV1PlayableObservation observation, {
  required int humanPlayerIndex,
}) {
  final actorLabel = observation.actorPlayerIndex == humanPlayerIndex
      ? 'YOU'
      : 'CPU';
  return '$actorLabel: ${_actionSummary(observation.action)}';
}

String _actionSummary(CombatV1LegalAction action) => switch (action.kind) {
  CombatV1LegalActionKind.discard => 'カードを1枚捨てた',
  CombatV1LegalActionKind.technique => '技を使用',
  CombatV1LegalActionKind.counter => 'カウンターを使用',
  CombatV1LegalActionKind.declineCounter => '技を受けた',
  CombatV1LegalActionKind.pin => 'PINを宣言',
  CombatV1LegalActionKind.rest => 'RESTでHPを回復',
  CombatV1LegalActionKind.standUp => '起き上がった',
  CombatV1LegalActionKind.endTurn => 'ターンを終了',
};

/// [CombatV1EnergyAttribute]別costの表示文字列（例: `打1 / 関1`）。
/// [amountFor]で0の属性は表示しない。空（total 0）の場合は`-`。
String combatV1PlayableEnergyCostLabel(
  Map<CombatV1EnergyAttribute, int> amounts,
) {
  final parts = <String>[
    for (final entry in amounts.entries)
      if (entry.value > 0) '${entry.key.displayLabel}${entry.value}',
  ];
  return parts.isEmpty ? '-' : parts.join(' / ');
}

/// Playable 1C.1「Card Cost Comparison」——技のENERGY COSTと、現在Humanが
/// 使用可能なENERGY（[CombatV1PlayableHumanStatus.availableEnergy]）を
/// 属性ごとに並べた比較表示（例: `打2 / 3`＝cost2・使用可能3）。[cost]に
/// 含まれる属性のみ表示する。UI側のlegality判定ではなく、単に2つの公開
/// 数値を並べるだけの表示。
String combatV1PlayableEnergyComparisonLabel(
  CombatV1EnergyCost cost,
  Map<CombatV1EnergyAttribute, int> availableEnergy,
) {
  final parts = <String>[
    for (final entry in cost.amounts.entries)
      if (entry.value > 0)
        '${entry.key.displayLabel}${entry.value} / '
            '${availableEnergy[entry.key] ?? 0}',
  ];
  return parts.isEmpty ? '-' : parts.join(' ・ ');
}

/// Playable 1C.1「Opponent Target Label」——技成立後に相手が移行する状態
/// （`resultOpponentState`）を、対象（相手）を明示して表示する（例:
/// `相手 → DOWN`）。単独の`DOWN`/`STAND`表示はしない（呼び出し側は
/// `resultOpponentState == null`（状態変化なし）の場合、この関数を呼ばず
/// 何も表示しない）。
String combatV1PlayableOpponentResultStateLabel(
  CombatV1WrestlerPosture resultState,
) => '相手 → ${combatV1PlayablePostureLabel(resultState)}';

/// Playable 1C.1「Required Posture Label」——技を使用するための相手の
/// 必要状態（`requiredOpponentState`）を、対象（相手）を明示して表示する
/// （例: `相手がSTANDの時のみ使用可`）。`null`（STAND/DOWNいずれでも
/// 使用可能）の場合はこの関数を呼ばない。
String combatV1PlayableRequiredOpponentStateLabel(
  CombatV1WrestlerPosture requiredState,
) => '相手が${combatV1PlayablePostureLabel(requiredState)}の時のみ使用可';

/// Playable 1C.1「Opponent Target Label」——`counterResponsePending`中の
/// pending攻撃（相手の技）が成立した場合に、自分（Human＝防御側）が
/// 移行する状態を明示して表示する（例: `あなた → DOWN`）。技カード面の
/// [combatV1PlayableOpponentResultStateLabel]とは向きが逆になる——
/// pending攻撃の`resultOpponentState`は常に「攻撃した側から見た相手」を
/// 指すため、Human視点では常に自分自身を指す。
String combatV1PlayablePendingResultStateLabel(
  CombatV1WrestlerPosture? resultState,
) => resultState == null
    ? '状態変化なし'
    : 'あなた → ${combatV1PlayablePostureLabel(resultState)}';
