/// TECHNIQUEカード定義モデル（docs/combat_rules_v1.md 6章）。
library;

import 'combat_v1_energy.dart';
import 'combat_v1_enums.dart';

/// TECHNIQUEカード1枚の静的定義。
///
/// Effect DSLのような汎用効果システムは持たない。Phase 1で必要な最低限の
/// フィールドと、後続Phaseでモデルを壊さないための予約フィールドのみを持つ
/// （docs/design/combat_v1_phase1_design.md 2.4章）。
class CombatV1Technique {
  const CombatV1Technique({
    required this.id,
    required this.name,
    required this.category,
    required this.attribute,
    required this.energyCost,
    required this.damage,
    required this.heatGain,
    required this.family,
    this.requiredOpponentState,
    this.resultOpponentState,
    this.directPin = false,
    this.submissionHold = false,
    this.finisherType,
  }) : assert(
         attribute != CombatV1EnergyAttribute.wild,
         '技の属性にwildは指定できません',
       ),
       assert(
         category != CombatV1CardCategory.finisher || finisherType != null,
         'category==finisherの技はfinisherTypeを必ず指定してください',
       ),
       assert(
         category == CombatV1CardCategory.finisher || finisherType == null,
         'finisherTypeはcategory==finisherの技にのみ設定できます'
         '（docs/design/combat_v1_phase1_design.md 2.4章の優先順位ルール）',
       );

  final String id;
  final String name;

  /// 技の格（NORMAL/SIGNATURE/FINISHER）。COUNTERカードは
  /// [../combat_v1_counter.dart] の`CombatV1Counter`で別途表現する。
  final CombatV1CardCategory category;

  final CombatV1EnergyAttribute attribute;
  final CombatV1EnergyCost energyCost;
  final int damage;
  final int heatGain;

  /// 使用可能な相手の状態。nullは「STAND/DOWNいずれでも使用可能」を表す。
  final CombatV1WrestlerPosture? requiredOpponentState;

  /// 成立時に相手が移行する状態。nullは「状態変化なし」を表す
  /// （例: STAND→STANDは`resultOpponentState: null`、STAND→DOWN/DOWN→DOWNは
  /// `resultOpponentState: CombatV1WrestlerPosture.down`）。
  final CombatV1WrestlerPosture? resultOpponentState;

  /// 技系統（docs/combat_rules_v1.md 23章、Phase
  /// 4で正式taxonomyへ移行済み）。COUNTERの成立判定（family/group
  /// マッチング）に使う。Production向けTechniqueでは必須（Phase 1の
  /// `familyId: String?`暫定構造は廃止し、旧String ID互換レイヤーは
  /// 設けない）。
  final CombatV1TechniqueFamily family;

  /// PIN不要で成功後に自動的にPINへ移行する性質（docs/combat_rules_v1.md
  /// 8章）。FINISHER限定ではなく技全般に付与できる汎用フラグ。
  /// category==finisherの場合はこの値ではなく[finisherType]が優先される
  /// （docs/design/combat_v1_phase1_design.md 2.4章）。
  final bool directPin;

  /// この技自体がSUBMISSIONホールド技であるという汎用フラグ
  /// （例: 鳳凰固め、白銀ロック）。「FINISHERとしてSUBMISSION決着方式を
  /// 持つこと」（[finisherType]）とは別概念（docs/combat_rules_v1.md 13章）。
  /// category==finisherの場合はこの値ではなく[finisherType]が優先される。
  final bool submissionHold;

  /// FINISHERの決着方式。category==finisherの場合のみ非null
  /// （docs/combat_rules_v1.md 13章）。FINISHER決着ロジック自体はPhase 9まで
  /// 実装しない（Phase 1では値を保持するのみ）。
  final CombatV1FinisherType? finisherType;

  /// 静的データvalidation（Phase 3で導入、Phase
  /// 4でTechnique全体の責務として範囲を明確化、docs/combat_rules_v1.md
  /// 6・7章）:
  ///
  /// - [energyCost]が有効（負数を含まない、wildを要求していない）
  /// - [energyCost.total]が0より大きい（zero-cost技は禁止、
  ///   docs/combat_rules_v1.md「7.2章 CombatV1EnergyCost.total」）
  /// - [attribute]がwildではない（コンストラクタのassertと同じ不変条件を、
  ///   assertが無効化されるビルドでも検出できるようにする）
  /// - [damage]/[heatGain]が負数ではない（負のDMG/HEATはSSOT上想定されて
  ///   いないデータ不正として扱う）
  ///
  /// [CombatV1Engine.checkTechniqueLegality]が
  /// `invalidTechniqueData`reasonCodeの判定に使う（`combat_v1_engine.dart`）。
  /// [family]はenumのため型システムで常に有効（無効値を構築できない）。
  bool get isStaticDataValid =>
      energyCost.isValid &&
      energyCost.total > 0 &&
      attribute != CombatV1EnergyAttribute.wild &&
      damage >= 0 &&
      heatGain >= 0;
}
