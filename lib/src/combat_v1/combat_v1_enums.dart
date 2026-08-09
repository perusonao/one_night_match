/// Combat Ver.1 共有enum定義。
///
/// 既存の `MoveAttribute`（lib/src/wrestler_editor/models.dart）・
/// `TechniqueCardCategory`（lib/src/technique_deck/technique_deck_models.dart）
/// 等とは意味が異なるため、依存せず独立して定義する
/// （docs/combat_rules_v1.md 1章「Engine方針」）。
library;

/// ENERGY属性（docs/combat_rules_v1.md 5章）。
///
/// `wild`（＊）はワイルドENERGYで、技のコストとしては現れず、支払い時の
/// 不足分の補完にのみ使われる（5.1章、[../combat_v1_energy.dart]参照）。
enum CombatV1EnergyAttribute { strike, joint, throwing, aerial, rough, wild }

extension CombatV1EnergyAttributeLabel on CombatV1EnergyAttribute {
  /// 打／関／投／飛／ラフ／＊ の表示名。
  String get displayLabel => switch (this) {
    CombatV1EnergyAttribute.strike => '打',
    CombatV1EnergyAttribute.joint => '関',
    CombatV1EnergyAttribute.throwing => '投',
    CombatV1EnergyAttribute.aerial => '飛',
    CombatV1EnergyAttribute.rough => 'ラフ',
    CombatV1EnergyAttribute.wild => '＊',
  };
}

/// レスラーの状態（docs/combat_rules_v1.md 2章・11章）。
///
/// Ver.1は `fatigued` 相当の第3状態を持たない（HP0は自動DOWNではない、14章）。
enum CombatV1WrestlerPosture { stand, down }

/// デッキ内カードのカテゴリ（docs/combat_rules_v1.md 3章）。
enum CombatV1CardCategory { normal, signature, finisher, counter }

/// 試合の外部から観測可能なフェーズ
/// （docs/design/combat_v1_phase1_design.md 3章、Phase 4で`counterResponsePending`
/// を追加）。
///
/// `setup`/`turnEnd`は概念上のフェーズであり、Command APIが返す
/// [CombatV1MatchState.phase] には現れない（`start`/`endTurn`が内部で
/// ターン開始処理まで完了させ、常に`discard`/`action`/`counterResponsePending`
/// のいずれかの状態を返すため）。
enum CombatV1MatchPhase {
  setup,
  discard,
  action,

  /// TECHNIQUE宣言（`declareTechnique`）直後、防御側がCOUNTERするか
  /// declineするかを選択する応答待ちフェーズ（docs/combat_rules_v1.md 7章、
  /// Phase 4）。このフェーズ中は`activePlayerIndex`は宣言した攻撃側のまま
  /// 変化しない（COUNTER成立でも攻守交代しない）。
  counterResponsePending,

  turnEnd,
}

/// FINISHERの決着方式（docs/combat_rules_v1.md 13章）。
///
/// 技モデル上の `submissionHold` 等の汎用フラグからは導出しない、独立enum
/// （`combat_v1_open_questions.md` G番で優先順位ルールを確定済み）。
enum CombatV1FinisherType { normal, directPin, submission }

/// COUNTERの成立判定に使う技系統の上位分類（docs/combat_rules_v1.md 23章、
/// Phase 4で正式化）。
///
/// 閉じた型（enum）とする。[CombatV1EnergyAttribute.rough]（ENERGY属性の
/// 「ラフ」）とは別概念であり、混同しないこと——`foul`はCOUNTER分類上の
/// groupであり、ENERGY属性のroughとは対応しない
/// （SSOT「23.2章 Family Group」参照）。
enum CombatV1TechniqueFamilyGroup { strike, aerial, throwing, submission, foul }

/// TECHNIQUEの技系統（docs/combat_rules_v1.md 23章、Phase 4で正式taxonomyを
/// 確定）。COUNTERが「何系の技を返せるか」を判定する具体分類。
///
/// [CombatV1EnergyAttribute]（ENERGY支払い・技属性）とは別概念（同じ技でも
/// familyとattributeは独立に決まる。例: CHOKEはjoint/rough両方のattributeで
/// 存在しうる）。Technique自身はgroupを保持せず、[group]で
/// [CombatV1TechniqueFamilyGroup]を導出する。
enum CombatV1TechniqueFamily {
  // STRIKE group
  elbow,
  chop,
  kick,
  knee,
  lariat,
  tackle,
  stomp,
  guillotineDrop,

  // AERIAL group
  dropKick,
  bodyPress,
  splash,

  // THROW group
  armDrag,
  ddt,
  legTakedown,
  slam,
  backdrop,
  suplex,
  powerbomb,
  driver,

  // SUBMISSION group
  armbar,
  headlock,
  legLock,
  figureFour,
  crossface,
  stretch,
  choke,
  claw,
  neckLock,

  // FOUL group
  lowBlow,
  weapon,
}

extension CombatV1TechniqueFamilyGrouping on CombatV1TechniqueFamily {
  /// この技系統が属する上位分類（docs/combat_rules_v1.md「23.3章 Technique
  /// Family」）。Technique自身はgroupを保持せず、常にfamilyから導出する。
  CombatV1TechniqueFamilyGroup get group => switch (this) {
    CombatV1TechniqueFamily.elbow ||
    CombatV1TechniqueFamily.chop ||
    CombatV1TechniqueFamily.kick ||
    CombatV1TechniqueFamily.knee ||
    CombatV1TechniqueFamily.lariat ||
    CombatV1TechniqueFamily.tackle ||
    CombatV1TechniqueFamily.stomp ||
    CombatV1TechniqueFamily.guillotineDrop =>
      CombatV1TechniqueFamilyGroup.strike,
    CombatV1TechniqueFamily.dropKick ||
    CombatV1TechniqueFamily.bodyPress ||
    CombatV1TechniqueFamily.splash =>
      CombatV1TechniqueFamilyGroup.aerial,
    CombatV1TechniqueFamily.armDrag ||
    CombatV1TechniqueFamily.ddt ||
    CombatV1TechniqueFamily.legTakedown ||
    CombatV1TechniqueFamily.slam ||
    CombatV1TechniqueFamily.backdrop ||
    CombatV1TechniqueFamily.suplex ||
    CombatV1TechniqueFamily.powerbomb ||
    CombatV1TechniqueFamily.driver =>
      CombatV1TechniqueFamilyGroup.throwing,
    CombatV1TechniqueFamily.armbar ||
    CombatV1TechniqueFamily.headlock ||
    CombatV1TechniqueFamily.legLock ||
    CombatV1TechniqueFamily.figureFour ||
    CombatV1TechniqueFamily.crossface ||
    CombatV1TechniqueFamily.stretch ||
    CombatV1TechniqueFamily.choke ||
    CombatV1TechniqueFamily.claw ||
    CombatV1TechniqueFamily.neckLock =>
      CombatV1TechniqueFamilyGroup.submission,
    CombatV1TechniqueFamily.lowBlow ||
    CombatV1TechniqueFamily.weapon =>
      CombatV1TechniqueFamilyGroup.foul,
  };
}
