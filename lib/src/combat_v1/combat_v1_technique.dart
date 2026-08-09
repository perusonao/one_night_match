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
    this.requiredOpponentState,
    this.resultOpponentState,
    this.familyId,
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

  /// 技系統（Phase 4のCOUNTER判定用の予約フィールド。正式taxonomyは未確定
  /// のため自由文字列とする、docs/design/combat_v1_open_questions.md 4番）。
  final String? familyId;

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

  /// 静的データvalidation（Phase 3、docs/combat_rules_v1.md 6章）:
  /// [energyCost]が有効か（負数を含まない、wildを要求していない）。
  ///
  /// [CombatV1Engine.checkTechniqueLegality]が
  /// `invalidTechniqueData`reasonCodeの判定に使う
  /// （lib/src/combat_v1/combat_v1_engine.dart）。
  bool get isStaticDataValid => energyCost.isValid;
}
