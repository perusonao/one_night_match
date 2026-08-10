/// Production Technique定義（docs/combat_rules_v1.md 6章・19章・20章、Phase 10A/10B/10C）。
///
/// Phase 10Aで豪田ミサキの12技、Phase 10Bで黒蝶ジャックの12技、Phase
/// 10Cで火神アカリ・白銀レイナの12技ずつを追加した。ミサキはCOST／DMG／HEAT／
/// 状態を`combat_rules_v1.md`19章の確定値からそのまま採用した。ジャックは20章に
/// 明記された5技（チョーク攻撃・顔面かきむしり・黒蝶クラッシュ・黒蝶ドライバー・
/// ブラック・ジャック）のCOST／DMG／HEAT／デッキ枚数のみが確定値であり、
/// 状態遷移・Technique Family・finisherType・残り7技（NORMAL6+SIGNATURE1）は
/// 一次資料に記載がなかったため、Phase 10BセッションでユーザーがClaudeの草案を
/// 承認のうえ正式確定した（docs/design/combat_v1_phase10_production_data.md
/// Phase 10B節参照）。アカリ・レイナは、Phase 10C-0/10C-0.5の設計セッションで
/// Claudeが提示した完全な叩き台（Phase 10C Production Data Final
/// Specification）をユーザーが確認・承認したうえで正式確定した
/// （docs/design/combat_v1_phase10_production_data.md Phase 10C節参照）。
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

/// 火神アカリ Production Technique 12種
/// （NORMAL8・SIGNATURE2・FINISHER2、Phase 10C Production Data Final
/// Specification 2章）。ENERGY Pool（打5/関1/投2/飛2/ラフ0/＊1）を反映し、
/// 単純なStrike spam化を避けるためCost帯を分散した。関1を死に属性化させない
/// ための唯一の関節技（アームキャッチ）にsubmissionHoldを付与している
/// （docs/design/combat_v1_phase10_production_data.md Phase 10C節参照）。
const Map<String, CombatV1Technique> akariTechniques = {
  // ── NORMAL（8種） ──────────────────────────────────────────

  'akari_elbow_smash': CombatV1Technique(
    id: 'akari_elbow_smash',
    name: 'エルボースマッシュ',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
    damage: 10,
    heatGain: 10,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    family: CombatV1TechniqueFamily.elbow,
  ),

  'akari_middle_kick': CombatV1Technique(
    id: 'akari_middle_kick',
    name: 'ミドルキック',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
    damage: 10,
    heatGain: 10,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    family: CombatV1TechniqueFamily.kick,
  ),

  'akari_dropkick': CombatV1Technique(
    id: 'akari_dropkick',
    name: 'ドロップキック',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.aerial,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.aerial: 1}),
    damage: 10,
    heatGain: 20,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.dropKick,
  ),

  'akari_running_knee': CombatV1Technique(
    id: 'akari_running_knee',
    name: 'ランニングニー',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2}),
    damage: 20,
    heatGain: 20,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.knee,
  ),

  'akari_arm_whip': CombatV1Technique(
    id: 'akari_arm_whip',
    name: 'アームホイップ',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.throwing,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 1}),
    damage: 10,
    heatGain: 10,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    family: CombatV1TechniqueFamily.armDrag,
  ),

  /// requiredOpponentState==down（Phase 10C Production Data Final
  /// Specification 11章）: 「Akariのダウンを奪う→飛び技へ繋ぐ、というコンボ
  /// 構造を作るため」というゲームデザイン上の理由（プロレス実技上の理由では
  /// ない）。
  'akari_flying_crossbody': CombatV1Technique(
    id: 'akari_flying_crossbody',
    name: 'フライングクロスボディ',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.aerial,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.aerial: 2}),
    damage: 20,
    heatGain: 20,
    requiredOpponentState: CombatV1WrestlerPosture.down,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.bodyPress,
  ),

  'akari_swing_ddt': CombatV1Technique(
    id: 'akari_swing_ddt',
    name: 'スイングDDT',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.throwing,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 2}),
    damage: 20,
    heatGain: 20,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.ddt,
  ),

  /// 関1を使う唯一の関節技。submissionHold=trueにより、AkariのSUBMISSION
  /// 勝ち筋（PIN主・SUBMISSION副）を低頻度・低コストで表現する
  /// （Phase 10C Production Data Final Specification 8・10章）。
  'akari_arm_catch': CombatV1Technique(
    id: 'akari_arm_catch',
    name: 'アームキャッチ',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.joint,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 1}),
    damage: 10,
    heatGain: 10,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    submissionHold: true,
    family: CombatV1TechniqueFamily.armbar,
  ),

  // ── SIGNATURE（2種） ───────────────────────────────────────

  'akari_phoenix_armdrag': CombatV1Technique(
    id: 'akari_phoenix_armdrag',
    name: 'フェニックス・アームドラッグ',
    category: CombatV1CardCategory.signature,
    attribute: CombatV1EnergyAttribute.throwing,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 2}),
    damage: 20,
    heatGain: 30,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.armDrag,
  ),

  'akari_soul_highkick': CombatV1Technique(
    id: 'akari_soul_highkick',
    name: 'ソウルハイキック',
    category: CombatV1CardCategory.signature,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 3}),
    damage: 30,
    heatGain: 40,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.kick,
  ),

  // ── FINISHER（2種） ────────────────────────────────────────

  /// requiredOpponentState==down（Phase 10C Production Data Final
  /// Specification 11章、フライングクロスボディと同じ「ダウンを奪う→
  /// 飛び技」コンボ構造の最終段）。飛属性のCost3は保有プール（飛2）を
  /// 超えるため、宣言時に＊(wild)1で不足分を補う（`resolveEnergyPayment`の
  /// 既存ロジックがそのまま処理する、5.1章）。finisherType=directPinにより
  /// AkariのPIN主決着を表現する。
  'akari_phoenix_splash': CombatV1Technique(
    id: 'akari_phoenix_splash',
    name: 'フェニックススプラッシュ',
    category: CombatV1CardCategory.finisher,
    attribute: CombatV1EnergyAttribute.aerial,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.aerial: 3}),
    damage: 30,
    heatGain: 40,
    requiredOpponentState: CombatV1WrestlerPosture.down,
    resultOpponentState: CombatV1WrestlerPosture.down,
    finisherType: CombatV1FinisherType.directPin,
    family: CombatV1TechniqueFamily.splash,
  ),

  'akari_red_flare_kick': CombatV1Technique(
    id: 'akari_red_flare_kick',
    name: 'レッドフレアキック',
    category: CombatV1CardCategory.finisher,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 3}),
    damage: 30,
    heatGain: 50,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    resultOpponentState: CombatV1WrestlerPosture.down,
    finisherType: CombatV1FinisherType.normal,
    family: CombatV1TechniqueFamily.kick,
  ),
};

/// 白銀レイナ Production Technique 12種
/// （NORMAL8・SIGNATURE2・FINISHER2、Phase 10C Production Data Final
/// Specification 6章）。ENERGY Pool（打2/関4/投3/飛0/ラフ0/＊1）を反映し、
/// 「関節＋投げ」に明確に偏らせる方針をA7最終回答で確定した（`stretch`
/// familyの初採用を含む、docs/design/combat_v1_phase10_production_data.md
/// Phase 10C節参照）。
const Map<String, CombatV1Technique> reinaTechniques = {
  // ── NORMAL（8種） ──────────────────────────────────────────

  'reina_side_headlock': CombatV1Technique(
    id: 'reina_side_headlock',
    name: 'サイドヘッドロック',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.joint,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 1}),
    damage: 10,
    heatGain: 10,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    family: CombatV1TechniqueFamily.headlock,
  ),

  'reina_leg_figure_four': CombatV1Technique(
    id: 'reina_leg_figure_four',
    name: '足四の字',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.joint,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 1}),
    damage: 10,
    heatGain: 10,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    family: CombatV1TechniqueFamily.figureFour,
  ),

  'reina_dragon_screw': CombatV1Technique(
    id: 'reina_dragon_screw',
    name: 'ドラゴンスクリュー',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.throwing,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 1}),
    damage: 10,
    heatGain: 20,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.legTakedown,
  ),

  'reina_drop_toehold': CombatV1Technique(
    id: 'reina_drop_toehold',
    name: 'ドロップトーホールド',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.throwing,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 1}),
    damage: 10,
    heatGain: 20,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.legTakedown,
  ),

  'reina_elbow': CombatV1Technique(
    id: 'reina_elbow',
    name: 'エルボー',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
    damage: 10,
    heatGain: 10,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    family: CombatV1TechniqueFamily.elbow,
  ),

  /// A7最終回答（Phase 10C-0.5）で確定した新規技。familyはstretch
  /// （Combat Ver.1 Productionで初採用、サイドヘッドロックとのfamily重複を
  /// 避ける）。resultOpponentStateはnull（STAND→STAND、状態変化なし）。
  'reina_abdominal_stretch': CombatV1Technique(
    id: 'reina_abdominal_stretch',
    name: 'アブドミナルストレッチ',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.joint,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 1}),
    damage: 10,
    heatGain: 10,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    family: CombatV1TechniqueFamily.stretch,
  ),

  'reina_arm_breaker': CombatV1Technique(
    id: 'reina_arm_breaker',
    name: 'アームブリーカー',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.joint,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 1}),
    damage: 10,
    heatGain: 10,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    family: CombatV1TechniqueFamily.armbar,
  ),

  /// requiredOpponentState==down（Phase 10C Production Data Final
  /// Specification 11章）: ダウンした相手へ本格的な関節を極める、という
  /// ゲームデザイン上のコンボ構造。submissionHold=trueによりReinaの
  /// SUBMISSION勝ち筋①を表現する。
  'reina_ude_hishigi': CombatV1Technique(
    id: 'reina_ude_hishigi',
    name: '腕ひしぎ',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.joint,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 2}),
    damage: 20,
    heatGain: 20,
    requiredOpponentState: CombatV1WrestlerPosture.down,
    resultOpponentState: CombatV1WrestlerPosture.down,
    submissionHold: true,
    family: CombatV1TechniqueFamily.armbar,
  ),

  // ── SIGNATURE（2種） ───────────────────────────────────────

  /// submissionHold=trueによりReinaのSUBMISSION勝ち筋②を表現する
  /// （立ち技から仕掛けるSIGNATURE、Phase 10C Production Data Final
  /// Specification 10章）。
  'reina_silver_crossface': CombatV1Technique(
    id: 'reina_silver_crossface',
    name: '白銀クロスフェイス',
    category: CombatV1CardCategory.signature,
    attribute: CombatV1EnergyAttribute.joint,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 2}),
    damage: 20,
    heatGain: 30,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    resultOpponentState: CombatV1WrestlerPosture.down,
    submissionHold: true,
    family: CombatV1TechniqueFamily.crossface,
  ),

  'reina_figure_four_lock': CombatV1Technique(
    id: 'reina_figure_four_lock',
    name: 'フィギュアフォー',
    category: CombatV1CardCategory.signature,
    attribute: CombatV1EnergyAttribute.joint,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 3}),
    damage: 30,
    heatGain: 40,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.figureFour,
  ),

  // ── FINISHER（2種） ────────────────────────────────────────

  /// finisherType=submissionによりReinaのSUBMISSION主決着を表現する。
  /// familyはlegLock（足四の字/フィギュアフォーのfigureFourとの三重重複を
  /// 避けるため、Phase 10C-0.5 A7で確定）。
  'reina_ice_lock': CombatV1Technique(
    id: 'reina_ice_lock',
    name: 'アイスロック',
    category: CombatV1CardCategory.finisher,
    attribute: CombatV1EnergyAttribute.joint,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 3}),
    damage: 30,
    heatGain: 40,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    resultOpponentState: CombatV1WrestlerPosture.down,
    finisherType: CombatV1FinisherType.submission,
    family: CombatV1TechniqueFamily.legLock,
  ),

  /// 関4（保有プール全量）を使い切る最大火力技。finisherType=normalにより
  /// 成功後、攻撃側が任意でPINを選択できる（Misaki/Jackの2つ目のFINISHERと
  /// 同じ役割分担）。
  'reina_eternal_cross': CombatV1Technique(
    id: 'reina_eternal_cross',
    name: 'エターナルクロス',
    category: CombatV1CardCategory.finisher,
    attribute: CombatV1EnergyAttribute.joint,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 4}),
    damage: 40,
    heatGain: 50,
    requiredOpponentState: CombatV1WrestlerPosture.stand,
    resultOpponentState: CombatV1WrestlerPosture.down,
    finisherType: CombatV1FinisherType.normal,
    family: CombatV1TechniqueFamily.crossface,
  ),
};
