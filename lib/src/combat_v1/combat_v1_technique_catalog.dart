/// Production Technique定義（docs/combat_rules_v1.md 6章・19章、Phase 10A）。
///
/// Phase 10Aでは豪田ミサキの12技のみを対象とする（黒蝶ジャック・火神アカリ・白銀レイナは
/// Phase 10B以降、実装しない）。COST／DMG／HEAT／状態は`combat_rules_v1.md`19章の
/// 確定値をそのまま採用し、Technique
/// Family割当・豪田ドライバーのfinisherTypeはPhase
/// 10Aセッションでユーザーが確認のうえ正式確定した
/// （docs/design/combat_v1_phase10_production_data.md 3章参照）。
library;

import 'combat_v1_energy.dart';
import 'combat_v1_enums.dart';
import 'combat_v1_technique.dart';

/// 豪田ミサキ Production Technique 12種
/// （NORMAL8・SIGNATURE2・FINISHER2、docs/design/combat_v1_phase10_production_data.md 3章）。
const Map<String, CombatV1Technique> misakiTechniques = {
  // ── NORMAL（8種） ──────────────────────────────────────────

  'misaki_reverse_chop': CombatV1Technique(
    id: 'misaki_reverse_chop',
    name: '逆水平チョップ',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
    damage: 10,
    heatGain: 10,
    family: CombatV1TechniqueFamily.chop,
  ),

  'misaki_shoulder_tackle': CombatV1Technique(
    id: 'misaki_shoulder_tackle',
    name: 'ショルダータックル',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
    damage: 10,
    heatGain: 20,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.tackle,
  ),

  'misaki_body_slam': CombatV1Technique(
    id: 'misaki_body_slam',
    name: 'ボディスラム',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.throwing,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 1}),
    damage: 10,
    heatGain: 10,
    family: CombatV1TechniqueFamily.slam,
  ),

  'misaki_brainbuster': CombatV1Technique(
    id: 'misaki_brainbuster',
    name: 'ブレーンバスター',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.throwing,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 2}),
    damage: 20,
    heatGain: 20,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.suplex,
  ),

  'misaki_backdrop': CombatV1Technique(
    id: 'misaki_backdrop',
    name: 'バックドロップ',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.throwing,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 2}),
    damage: 20,
    heatGain: 20,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.backdrop,
  ),

  'misaki_power_slam': CombatV1Technique(
    id: 'misaki_power_slam',
    name: 'パワースラム',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.throwing,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 3}),
    damage: 30,
    heatGain: 30,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.slam,
  ),

  'misaki_lariat': CombatV1Technique(
    id: 'misaki_lariat',
    name: 'ラリアット',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2}),
    damage: 20,
    heatGain: 20,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.lariat,
  ),

  'misaki_guillotine_drop': CombatV1Technique(
    id: 'misaki_guillotine_drop',
    name: 'ギロチンドロップ',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
    damage: 10,
    heatGain: 20,
    requiredOpponentState: CombatV1WrestlerPosture.down,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.guillotineDrop,
  ),

  // ── SIGNATURE（2種） ───────────────────────────────────────

  'misaki_mighty_backdrop': CombatV1Technique(
    id: 'misaki_mighty_backdrop',
    name: '豪快バックドロップ',
    category: CombatV1CardCategory.signature,
    attribute: CombatV1EnergyAttribute.throwing,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 3}),
    damage: 30,
    heatGain: 40,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.backdrop,
  ),

  'misaki_strong_arm_lariat': CombatV1Technique(
    id: 'misaki_strong_arm_lariat',
    name: '剛腕ラリアット',
    category: CombatV1CardCategory.signature,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2}),
    damage: 20,
    heatGain: 30,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.lariat,
  ),

  // ── FINISHER（2種） ────────────────────────────────────────

  /// finisherType確定経緯: docs/combat_rules_v1.md 19章の表が「特性」列に
  /// 「DIRECT PIN」と明記しているため、Phase
  /// 10Aセッションでの追加確認なしにdirectPinとして確定した
  /// （docs/design/combat_v1_phase10_production_data.md 3.1章）。
  'misaki_goda_bomb': CombatV1Technique(
    id: 'misaki_goda_bomb',
    name: '豪田ボム',
    category: CombatV1CardCategory.finisher,
    attribute: CombatV1EnergyAttribute.throwing,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 3}),
    damage: 30,
    heatGain: 40,
    resultOpponentState: CombatV1WrestlerPosture.down,
    finisherType: CombatV1FinisherType.directPin,
    family: CombatV1TechniqueFamily.powerbomb,
  ),

  /// finisherType確定経緯: docs/combat_rules_v1.md 19章には「最大火力
  /// （検証対象）」としか記載がなく未確定だったため、Phase
  /// 10Aセッションでユーザーへ確認のうえnormalとして確定した
  /// （docs/design/combat_v1_phase10_production_data.md 3.1章）。
  'misaki_goda_driver': CombatV1Technique(
    id: 'misaki_goda_driver',
    name: '豪田ドライバー',
    category: CombatV1CardCategory.finisher,
    attribute: CombatV1EnergyAttribute.throwing,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 4}),
    damage: 40,
    heatGain: 50,
    resultOpponentState: CombatV1WrestlerPosture.down,
    finisherType: CombatV1FinisherType.normal,
    family: CombatV1TechniqueFamily.driver,
  ),
};
