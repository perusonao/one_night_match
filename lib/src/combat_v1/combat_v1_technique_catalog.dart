/// Production Technique定義（docs/combat_rules_v1.md 6章・19章・20章、Phase 10A/10B）。
///
/// Phase 10Aで豪田ミサキの12技、Phase 10Bで黒蝶ジャックの12技を追加した
/// （火神アカリ・白銀レイナはPhase 10C以降、実装しない）。ミサキはCOST／DMG／HEAT／
/// 状態を`combat_rules_v1.md`19章の確定値からそのまま採用した。ジャックは20章に
/// 明記された5技（チョーク攻撃・顔面かきむしり・黒蝶クラッシュ・黒蝶ドライバー・
/// ブラック・ジャック）のCOST／DMG／HEAT／デッキ枚数のみが確定値であり、
/// 状態遷移・Technique Family・finisherType・残り7技（NORMAL6+SIGNATURE1）は
/// 一次資料に記載がなかったため、Phase 10BセッションでユーザーがClaudeの草案を
/// 承認のうえ正式確定した（docs/design/combat_v1_phase10_production_data.md
/// Phase 10B節参照）。
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
    requiredOpponentState: CombatV1WrestlerPosture.stand,
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
    requiredOpponentState: CombatV1WrestlerPosture.stand,
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
    requiredOpponentState: CombatV1WrestlerPosture.stand,
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
    requiredOpponentState: CombatV1WrestlerPosture.stand,
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
    requiredOpponentState: CombatV1WrestlerPosture.stand,
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
    requiredOpponentState: CombatV1WrestlerPosture.stand,
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
    requiredOpponentState: CombatV1WrestlerPosture.stand,
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
    requiredOpponentState: CombatV1WrestlerPosture.stand,
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
    requiredOpponentState: CombatV1WrestlerPosture.stand,
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
    requiredOpponentState: CombatV1WrestlerPosture.stand,
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
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    resultOpponentState: CombatV1WrestlerPosture.down,
    finisherType: CombatV1FinisherType.normal,
    family: CombatV1TechniqueFamily.driver,
  ),
};

/// 黒蝶ジャック Production Technique 12種
/// （NORMAL8・SIGNATURE2・FINISHER2、docs/design/combat_v1_phase10_production_data.md
/// Phase 10B節）。ROUGH属性技は`combat_rules_v1.md`20章の基準どおり5枚
/// （チョーク攻撃・顔面かきむしり・黒蝶クラッシュ×2・黒蝶ドライバー）で打ち止め、
/// 残りはSTRIKE中心＋JOINT/THROWを各1種で構成する。
const Map<String, CombatV1Technique> jackTechniques = {
  // ── NORMAL（8種） ──────────────────────────────────────────

  /// docs/combat_rules_v1.md 23.4章がCHOKE family × attribute=roughの例として
  /// 明示的に挙げている技そのもの。
  'jack_choke_attack': CombatV1Technique(
    id: 'jack_choke_attack',
    name: 'チョーク攻撃',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.rough,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.rough: 1}),
    damage: 10,
    heatGain: 20,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    family: CombatV1TechniqueFamily.choke,
  ),

  'jack_face_claw': CombatV1Technique(
    id: 'jack_face_claw',
    name: '顔面かきむしり',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.rough,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.rough: 1}),
    damage: 10,
    heatGain: 20,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    family: CombatV1TechniqueFamily.claw,
  ),

  'jack_sneak_kick': CombatV1Technique(
    id: 'jack_sneak_kick',
    name: '闇討ちキック',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
    damage: 10,
    heatGain: 10,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    family: CombatV1TechniqueFamily.kick,
  ),

  'jack_elbow': CombatV1Technique(
    id: 'jack_elbow',
    name: '黒蝶エルボー',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
    damage: 10,
    heatGain: 10,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    family: CombatV1TechniqueFamily.elbow,
  ),

  'jack_sneak_lariat': CombatV1Technique(
    id: 'jack_sneak_lariat',
    name: '闇討ちラリアット',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2}),
    damage: 20,
    heatGain: 20,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.lariat,
  ),

  'jack_suplex': CombatV1Technique(
    id: 'jack_suplex',
    name: '黒蝶スープレックス',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.throwing,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 1}),
    damage: 10,
    heatGain: 10,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    family: CombatV1TechniqueFamily.suplex,
  ),

  'jack_armlock': CombatV1Technique(
    id: 'jack_armlock',
    name: 'アームロック',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.joint,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 1}),
    damage: 10,
    heatGain: 10,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    family: CombatV1TechniqueFamily.armbar,
  ),

  /// docs/combat_rules_v1.md 20章「踏みつけはROUGHではなく通常技として扱う」・
  /// 23.3章「STOMPはSTRIKE group（踏みつけは通常技として扱う、20章の踏みつけ
  /// 方針と整合）」に対応する技。DOWN相手専用（misaki_guillotine_dropと同型）。
  'jack_finishing_stomp': CombatV1Technique(
    id: 'jack_finishing_stomp',
    name: 'とどめの踏みつけ',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
    damage: 10,
    heatGain: 20,
    requiredOpponentState: CombatV1WrestlerPosture.down,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.stomp,
  ),

  // ── SIGNATURE（2種） ───────────────────────────────────────

  'jack_kurocho_crash': CombatV1Technique(
    id: 'jack_kurocho_crash',
    name: '黒蝶クラッシュ',
    category: CombatV1CardCategory.signature,
    attribute: CombatV1EnergyAttribute.rough,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.rough: 2}),
    damage: 20,
    heatGain: 40,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.tackle,
  ),

  'jack_knee_drop': CombatV1Technique(
    id: 'jack_knee_drop',
    name: '黒蝶ニードロップ',
    category: CombatV1CardCategory.signature,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2}),
    damage: 20,
    heatGain: 30,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.knee,
  ),

  // ── FINISHER（2種） ────────────────────────────────────────

  /// finisherType確定経緯: docs/combat_rules_v1.md 20章は「妨害型FINISHER」
  /// とのみ記載し、決着方式は未確定だった。Phase
  /// 10Bセッションでユーザーへ確認のうえdirectPinとして確定した
  /// （成功後すぐPINへ移行し主導権を握る「妨害」の役割）。
  'jack_kurocho_driver': CombatV1Technique(
    id: 'jack_kurocho_driver',
    name: '黒蝶ドライバー',
    category: CombatV1CardCategory.finisher,
    attribute: CombatV1EnergyAttribute.rough,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.rough: 3}),
    damage: 30,
    heatGain: 50,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    resultOpponentState: CombatV1WrestlerPosture.down,
    finisherType: CombatV1FinisherType.directPin,
    family: CombatV1TechniqueFamily.driver,
  ),

  /// finisherType確定経緯: docs/combat_rules_v1.md 20章は「決着型FINISHER」
  /// とのみ記載し、決着方式は未確定だった。Phase
  /// 10Bセッションでユーザーへ確認のうえnormalとして確定した
  /// （成功後、攻撃側が任意でPINを選択する強力な通常技として扱う）。
  'jack_black_jack': CombatV1Technique(
    id: 'jack_black_jack',
    name: 'ブラック・ジャック',
    category: CombatV1CardCategory.finisher,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 3}),
    damage: 30,
    heatGain: 50,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    resultOpponentState: CombatV1WrestlerPosture.down,
    finisherType: CombatV1FinisherType.normal,
    family: CombatV1TechniqueFamily.lariat,
  ),
};
