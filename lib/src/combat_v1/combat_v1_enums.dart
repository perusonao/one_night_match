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
/// （docs/design/combat_v1_phase1_design.md 3章）。
///
/// `setup`/`turnEnd`は概念上のフェーズであり、Phase 1のCommand APIが返す
/// [CombatV1MatchState.phase] には現れない（`start`/`endTurn`が内部で
/// ターン開始処理まで完了させ、常に`discard`または`action`の状態を返すため）。
enum CombatV1MatchPhase { setup, discard, action, turnEnd }

/// FINISHERの決着方式（docs/combat_rules_v1.md 13章）。
///
/// 技モデル上の `submissionHold` 等の汎用フラグからは導出しない、独立enum
/// （`combat_v1_open_questions.md` G番で優先順位ルールを確定済み）。
enum CombatV1FinisherType { normal, directPin, submission }
