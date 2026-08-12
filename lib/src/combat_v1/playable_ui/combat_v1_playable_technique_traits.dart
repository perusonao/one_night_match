/// Combat Ver.1 Playable 2A-3 — Technique / Counter Decision Readability
/// （docs/design/combat_v1_playable_match_ui.md「72章 Technique Decision
/// Traits」）。
///
/// Playable 2A-1（今できること）・2A-2（何を目指すか）に続き、「このカードを
/// 選ぶと、その目標へどう進むか」（Technique選択時点・Counter応答時点での
/// 勝敗ルート理解）を、既存`CombatV1Technique`/`CombatV1PlayablePendingAttackView`
/// /`CombatV1Counter`から安全に導出できる情報だけを使って短いbadge/文章へ
/// 変換する、pure derivationレイヤー（`combat_v1_playable_match_direction.dart`
/// と同じ方針——Combat ruleを一切再実装しない・legality判定は常に
/// `snapshot.legalActions`をそのまま参照するだけ・独自のdamage計算や
/// hidden情報の推測は行わない）。
library;

import '../combat_v1_counter.dart';
import '../combat_v1_counter_rules.dart';
import '../combat_v1_enums.dart';
import '../combat_v1_technique.dart';
import '../playable/combat_v1_playable_match_snapshot.dart';

/// [technique]成立時に自動でPINへ移行するか（docs/combat_rules_v1.md 8章
/// 「DIRECT PIN」）。
///
/// `category == finisher`の場合は、技自身の[CombatV1Technique.directPin]
/// フィールドではなく[CombatV1Technique.finisherType]が優先される
/// （`combat_v1_engine.dart` `_resolvePendingAttack`のeffectiveDirectPin
/// と同じ優先順位ルール、docs/design/combat_v1_phase1_design.md
/// 2.4章）——このfunctionはEngineの優先順位をそのまま再現するだけで、
/// 新しい判定を追加しない。
bool combatV1PlayableTechniqueHasEffectiveDirectPin(
  CombatV1Technique technique,
) => _effectiveDirectPin(
  category: technique.category,
  finisherType: technique.finisherType,
  directPin: technique.directPin,
);

/// [technique]成立時、条件を満たすとSUBMISSIONへ自動移行するか
/// （docs/combat_rules_v1.md 10.1章）。[combatV1PlayableTechniqueHasEffectiveDirectPin]
/// と同じ、FINISHER優先順位ルールを適用する。
bool combatV1PlayableTechniqueHasEffectiveSubmissionHold(
  CombatV1Technique technique,
) => _effectiveSubmissionHold(
  category: technique.category,
  finisherType: technique.finisherType,
  submissionHold: technique.submissionHold,
);

/// [pending]（宣言済みのCounter応答待ち攻撃）が成立した場合に自動でPINへ
/// 移行するか。[combatV1PlayableTechniqueHasEffectiveDirectPin]と同じ
/// FINISHER優先順位ルールを、`CombatV1PlayablePendingAttackView`側の同じ
/// フィールド（宣言時点でTechniqueから複製済みの静的metadata）に適用する。
bool combatV1PlayablePendingAttackHasEffectiveDirectPin(
  CombatV1PlayablePendingAttackView pending,
) => _effectiveDirectPin(
  category: pending.category,
  finisherType: pending.finisherType,
  directPin: pending.directPin,
);

/// [pending]成立時、条件を満たすとSUBMISSIONへ自動移行するか。
bool combatV1PlayablePendingAttackHasEffectiveSubmissionHold(
  CombatV1PlayablePendingAttackView pending,
) => _effectiveSubmissionHold(
  category: pending.category,
  finisherType: pending.finisherType,
  submissionHold: pending.submissionHold,
);

bool _effectiveDirectPin({
  required CombatV1CardCategory category,
  required CombatV1FinisherType? finisherType,
  required bool directPin,
}) {
  if (category == CombatV1CardCategory.finisher) {
    return finisherType == CombatV1FinisherType.directPin;
  }
  return directPin;
}

bool _effectiveSubmissionHold({
  required CombatV1CardCategory category,
  required CombatV1FinisherType? finisherType,
  required bool submissionHold,
}) {
  if (category == CombatV1CardCategory.finisher) {
    return finisherType == CombatV1FinisherType.submission;
  }
  return submissionHold;
}

/// [technique]がShared HEAT解禁後にプレイヤーが読める「ROUGH属性」か
/// （docs/combat_rules_v1.md 15章）。ENERGY属性の[CombatV1EnergyAttribute.rough]
/// そのものであり、COUNTER分類の`foul` group（[CombatV1TechniqueFamilyGroup.foul]）
/// とは別概念（`combat_v1_enums.dart`の既存注記どおり混同しない）。
bool combatV1PlayableTechniqueIsRough(CombatV1Technique technique) =>
    technique.attribute == CombatV1EnergyAttribute.rough;

bool combatV1PlayablePendingAttackIsRough(
  CombatV1PlayablePendingAttackView pending,
) => pending.attribute == CombatV1EnergyAttribute.rough;

/// FINISHERの決着方式（[finisherType]）を、プレイヤーが読める短いbadge
/// 文言へ変換する（docs/combat_rules_v1.md 13章）。enum名をそのままUIへ
/// 出さない——`normal`は勝敗ルートを追加しない通常のFINISHERであるため
/// 単に`FINISHER`、`directPin`/`submissionHold`はそれぞれ決着ルートを
/// 明示した合成ラベルにする。
String combatV1PlayableFinisherResolutionBadgeLabel(
  CombatV1FinisherType finisherType,
) => switch (finisherType) {
  CombatV1FinisherType.normal => 'FINISHER',
  CombatV1FinisherType.directPin => 'FINISHER · PIN',
  CombatV1FinisherType.submission => 'FINISHER · SUBMISSION',
};

/// DIRECT PIN trait badgeのTooltip/detail文言（docs/combat_rules_v1.md
/// 8章）。「今PIN actionがlegalである」こととは別概念であることを明示する
/// ——通常PINのLegalAction判定と混同しない安全な言い回しに留める。
String combatV1PlayableDirectPinTraitDetail() =>
    '成立時、自動でPINへ移行します（通常のPIN選択とは別の経路です）';

/// SUBMISSION trait badgeのTooltip/detail文言（docs/combat_rules_v1.md
/// 10.1章）。「今Submissionできる／これで勝てる」という過剰断定を避け、
/// 「成立後、条件（相手HPの閾値）を満たした場合」という限定を必ず含める。
/// [submissionHpThreshold]は`CombatV1PlayableMatchSnapshot.submissionHpThreshold`
/// （既にpublicなrule定数）をそのまま使う——magic numberをUI側で複製しない。
String combatV1PlayableSubmissionTraitDetail(int submissionHpThreshold) =>
    '成立後、相手HPが$submissionHpThreshold以下だとSubmission判定に自動移行します'
    '（Escapeされる場合があります）';

/// ROUGH trait badgeのTooltip/detail文言（docs/combat_rules_v1.md 15章）。
/// 「使用したターンはPINできない」（宣言時点基準）と「成立させて終えたターンは
/// 相手の次ターンTECHNIQUEを最大1枚に制限する」（成立時点基準）という、
/// 判定基準の異なる2つの効果を明示する（15.1章）。
String combatV1PlayableRoughTraitDetail() =>
    'このターン使用するとPINできなくなります。成立させてターンを終えると、'
    '相手の次ターンTECHNIQUEを最大1枚に制限します';

/// [CombatV1TechniqueFamilyGroup]のUI表示label（docs/combat_rules_v1.md
/// 「23.2章 Family Group」）。[CombatV1CardCategory]と同じ短い英大文字表記に
/// 揃える。
String combatV1PlayableTechniqueFamilyGroupLabel(
  CombatV1TechniqueFamilyGroup group,
) => switch (group) {
  CombatV1TechniqueFamilyGroup.strike => 'STRIKE',
  CombatV1TechniqueFamilyGroup.aerial => 'AERIAL',
  CombatV1TechniqueFamilyGroup.throwing => 'THROW',
  CombatV1TechniqueFamilyGroup.submission => 'SUBMISSION',
  CombatV1TechniqueFamilyGroup.foul => 'FOUL',
};

/// [CombatV1TechniqueFamily]のUI表示label（docs/combat_rules_v1.md
/// 「23.3章 Technique Family」）。Core enumの英語名をそのまま
/// 読みやすいTitle Caseへ整形するだけで、新しいtaxonomyは作らない。
String combatV1PlayableTechniqueFamilyLabel(CombatV1TechniqueFamily family) =>
    switch (family) {
      CombatV1TechniqueFamily.elbow => 'Elbow',
      CombatV1TechniqueFamily.chop => 'Chop',
      CombatV1TechniqueFamily.kick => 'Kick',
      CombatV1TechniqueFamily.knee => 'Knee',
      CombatV1TechniqueFamily.lariat => 'Lariat',
      CombatV1TechniqueFamily.tackle => 'Tackle',
      CombatV1TechniqueFamily.stomp => 'Stomp',
      CombatV1TechniqueFamily.guillotineDrop => 'Guillotine Drop',
      CombatV1TechniqueFamily.dropKick => 'Drop Kick',
      CombatV1TechniqueFamily.bodyPress => 'Body Press',
      CombatV1TechniqueFamily.splash => 'Splash',
      CombatV1TechniqueFamily.armDrag => 'Arm Drag',
      CombatV1TechniqueFamily.ddt => 'DDT',
      CombatV1TechniqueFamily.legTakedown => 'Leg Takedown',
      CombatV1TechniqueFamily.slam => 'Slam',
      CombatV1TechniqueFamily.backdrop => 'Backdrop',
      CombatV1TechniqueFamily.suplex => 'Suplex',
      CombatV1TechniqueFamily.powerbomb => 'Powerbomb',
      CombatV1TechniqueFamily.driver => 'Driver',
      CombatV1TechniqueFamily.armbar => 'Armbar',
      CombatV1TechniqueFamily.headlock => 'Headlock',
      CombatV1TechniqueFamily.legLock => 'Leg Lock',
      CombatV1TechniqueFamily.figureFour => 'Figure Four',
      CombatV1TechniqueFamily.crossface => 'Crossface',
      CombatV1TechniqueFamily.stretch => 'Stretch',
      CombatV1TechniqueFamily.choke => 'Choke',
      CombatV1TechniqueFamily.claw => 'Claw',
      CombatV1TechniqueFamily.neckLock => 'Neck Lock',
      CombatV1TechniqueFamily.lowBlow => 'Low Blow',
      CombatV1TechniqueFamily.weapon => 'Weapon',
    };

/// [counter]が[attackFamily]をどう受けられるか（docs/combat_rules_v1.md
/// 「23.5章 COUNTER matching」）を短いlabelへ変換する——成立条件の判定
/// 自体はCore純粋関数[techniqueFamilyMatchesCounter]をそのまま使う
/// （再実装しない）。マッチしない場合は`null`（このCounterが現在
/// `usable`として表示されている前提では通常到達しない、防御的な戻り値）。
///
/// family一致／group一致のどちらでマッチしたかは、[counter]自身が公開する
/// [CombatV1Counter.counterableFamilies]/[CombatV1Counter.counterableGroups]
/// （印刷されたカードテキストと同じ、既に公開済みの情報）をそのまま参照する
/// だけで、新しい判定ロジックを追加しない。
String? combatV1PlayableCounterFamilyMatchLabel(
  CombatV1Counter counter,
  CombatV1TechniqueFamily attackFamily,
) {
  if (!techniqueFamilyMatchesCounter(counter, attackFamily)) return null;
  if (counter.counterableFamilies.contains(attackFamily)) {
    return combatV1PlayableTechniqueFamilyLabel(attackFamily);
  }
  final group = attackFamily.group;
  return '${combatV1PlayableTechniqueFamilyGroupLabel(group)} group';
}

/// Counterが成立した場合に防げる内容（docs/combat_rules_v1.md 7.1章
/// 「攻撃効果は無効、DMG/HEAT/posture変更なし」——`combat_v1_engine.dart`
/// `playCounter`のコメントで確定している完全無効化semanticsと一致する
/// 文言）。DIRECT PIN/SUBMISSIONを持つ技の場合は、それらの自動移行も
/// 防げることを追記する——Counterが成立すれば技自体が不成立になるため、
/// 技成立を前提とする自動遷移も一切発生しない。
///
/// 新しいCombat ruleではなく、既存`playCounter`の実装コメントが確定
/// させているsemanticsをそのまま言い換えるだけ。
String combatV1PlayableCounterPreventsSummary({
  required bool directPin,
  required bool submissionHold,
}) {
  final extra = <String>[
    if (directPin) '自動PINへの移行',
    if (submissionHold) 'Submissionへの移行条件を満たすこと',
  ];
  if (extra.isEmpty) {
    return 'Counterが成立すると、この技のDMG・HEAT・状態変化を防げます';
  }
  return 'Counterが成立すると、この技のDMG・HEAT・状態変化に加えて'
      '${extra.join('・')}も防げます';
}
