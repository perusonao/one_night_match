/// Production Counter定義（docs/combat_rules_v1.md 7章・23章、Phase 10A）。
///
/// COUNTERは原則共有definitionとして扱う（同一name／payment attribute／
/// counterableFamilies・counterableGroupsであれば複数レスラーが同一定義を参照でき、
/// レスラー別に同じCounterを複製しない、docs/design/combat_v1_phase10_production_data.md
/// 1.3章）。そのためIDはwrestler-stable-keyを含まない`counter_<counter-stable-key>`とする。
///
/// Phase 10Aでは、豪田ミサキ用に広範囲/中範囲/専門の3種を正式採用した
/// （docs/design/combat_v1_phase10_production_data.md 4章）。attribute（支払い属性）は
/// ミサキが実際に保有するENERGY属性（打／投／ラフ、`combat_v1_wrestler_catalog.dart`）の
/// 範囲内から選定している。
///
/// Phase 10Bでは、黒蝶ジャック用に同じ広範囲/中範囲/専門テンプレートで3種を追加した
/// （docs/design/combat_v1_phase10_production_data.md Phase 10B節）。attributeは
/// ジャックが保有量の多いENERGY属性（打3／ラフ4、`combat_v1_wrestler_catalog.dart`）の
/// 範囲内から選定している。COUNTERは返すTECHNIQUEのENERGY Cost合計をCounter側の
/// 単一属性で支払う（docs/combat_rules_v1.md 7章）ため、関1／投1でもCost
/// 1のTECHNIQUEになら支払える。ただしCost2以上には対応できず、対象family/groupの
/// Cost分布次第では実用性が低いため、より保有量の多い打／ラフを選定した
/// （関・飛の保有量が0のためCounter属性に選ぶと常に支払い不能になるミサキ4章の
/// ケースとは異なる）。
///
/// Phase 10Cでは、火神アカリ・白銀レイナ用に同じテンプレートで3種ずつ追加した
/// （docs/design/combat_v1_phase10_production_data.md Phase 10C節）。Reinaの
/// `stretch` family（アブドミナルストレッチ）を専門target するCounterは現状
/// 存在しない——Phase 10C-0.5 A7最終回答でユーザーが明示的に許容した仕様であり、
/// Counter coverageを補うための新規Counter追加は行っていない。
library;

import 'combat_v1_counter.dart';
import 'combat_v1_enums.dart';

/// 豪田ミサキ Production Counter 3種。
final Map<String, CombatV1Counter> misakiCounters = {
  /// 広範囲型: STRIKE group全体を打属性で返す。
  'counter_strike_guard': CombatV1Counter(
    id: 'counter_strike_guard',
    name: 'ガード＆エルボー',
    attribute: CombatV1EnergyAttribute.strike,
    counterableGroups: [CombatV1TechniqueFamilyGroup.strike],
  ),

  /// 中範囲型: バックドロップ系・スープレックス系を投属性で返す。
  'counter_suplex_reversal': CombatV1Counter(
    id: 'counter_suplex_reversal',
    name: 'スープレックス切り返し',
    attribute: CombatV1EnergyAttribute.throwing,
    counterableFamilies: [
      CombatV1TechniqueFamily.backdrop,
      CombatV1TechniqueFamily.suplex,
    ],
  ),

  /// 専門型: パワーボム系のみを投属性で返す。
  'counter_powerbomb_escape': CombatV1Counter(
    id: 'counter_powerbomb_escape',
    name: 'フランケンシュタイナー返し',
    attribute: CombatV1EnergyAttribute.throwing,
    counterableFamilies: [CombatV1TechniqueFamily.powerbomb],
  ),
};

/// 黒蝶ジャック Production Counter 3種
/// （docs/design/combat_v1_phase10_production_data.md Phase 10B節）。
final Map<String, CombatV1Counter> jackCounters = {
  /// 広範囲型: STRIKE group全体を打属性で返す。
  'counter_jack_sneak_guard': CombatV1Counter(
    id: 'counter_jack_sneak_guard',
    name: '闇討ちガード',
    attribute: CombatV1EnergyAttribute.strike,
    counterableGroups: [CombatV1TechniqueFamilyGroup.strike],
  ),

  /// 中範囲型: 投げ系フィニッシュ級の技（SUPLEX/BACKDROP/POWERBOMB/DRIVER）を
  /// ラフ属性で返す。
  'counter_jack_reversal': CombatV1Counter(
    id: 'counter_jack_reversal',
    name: '黒蝶リバーサル',
    attribute: CombatV1EnergyAttribute.rough,
    counterableFamilies: [
      CombatV1TechniqueFamily.suplex,
      CombatV1TechniqueFamily.backdrop,
      CombatV1TechniqueFamily.powerbomb,
      CombatV1TechniqueFamily.driver,
    ],
  ),

  /// 専門型: 首絞め・クロー系の関節/ラフ技のみを打属性で返す。
  'counter_jack_choke_break': CombatV1Counter(
    id: 'counter_jack_choke_break',
    name: 'チョークブレイク',
    attribute: CombatV1EnergyAttribute.strike,
    counterableFamilies: [
      CombatV1TechniqueFamily.choke,
      CombatV1TechniqueFamily.claw,
    ],
  ),
};

/// 火神アカリ Production Counter 3種
/// （Phase 10C Production Data Final Specification 3章）。attribute（支払い
/// 属性）は、Akariが実際に保有するENERGY属性（打5/投2/飛2）の範囲内から選定
/// している（関1・ラフ0は、Misaki 4章と同じ理由で除外した）。②は既存
/// `counter_suplex_reversal`（Misaki）と機械的に同一のtargetを持つが、Phase
/// 10C-0.5 A5でユーザーが「レスラー固有のカードとして扱う」方針を明示的に
/// 選択したため、新規flavor名・新規definitionとして採用した。
final Map<String, CombatV1Counter> akariCounters = {
  /// 広範囲型: STRIKE group全体を打属性で返す。
  'counter_akari_crimson_guard': CombatV1Counter(
    id: 'counter_akari_crimson_guard',
    name: '紅蓮ガード',
    attribute: CombatV1EnergyAttribute.strike,
    counterableGroups: [CombatV1TechniqueFamilyGroup.strike],
  ),

  /// 中範囲型: バックドロップ系・スープレックス系を投属性で返す。
  'counter_akari_phoenix_throw_reversal': CombatV1Counter(
    id: 'counter_akari_phoenix_throw_reversal',
    name: 'フェニックス投げ返し',
    attribute: CombatV1EnergyAttribute.throwing,
    counterableFamilies: [
      CombatV1TechniqueFamily.backdrop,
      CombatV1TechniqueFamily.suplex,
    ],
  ),

  /// 専門型: スプラッシュ系のみを飛属性で返す。
  'counter_akari_sky_intercept': CombatV1Counter(
    id: 'counter_akari_sky_intercept',
    name: 'スカイインターセプト',
    attribute: CombatV1EnergyAttribute.aerial,
    counterableFamilies: [CombatV1TechniqueFamily.splash],
  ),
};

/// 白銀レイナ Production Counter 3種
/// （Phase 10C Production Data Final Specification 7章）。attribute（支払い
/// 属性）は、Reinaが実際に保有するENERGY属性（投3/関4/打2）の範囲内から選定
/// している（飛0・ラフ0は除外した）。専門型は打2の少ないプールでも支払える
/// Cost2級（LARIAT）に限定し、関4を使う中範囲型は本格的な関節技
/// （CROSSFACE/FIGURE_FOUR）まで対応できるようにした。
final Map<String, CombatV1Counter> reinaCounters = {
  /// 広範囲型: THROW group全体を投属性で返す。
  'counter_reina_leg_catch_guard': CombatV1Counter(
    id: 'counter_reina_leg_catch_guard',
    name: '足取りガード',
    attribute: CombatV1EnergyAttribute.throwing,
    counterableGroups: [CombatV1TechniqueFamilyGroup.throwing],
  ),

  /// 中範囲型: クロスフェイス系・フィギュアフォー系を関属性で返す。
  'counter_reina_silver_lock_reversal': CombatV1Counter(
    id: 'counter_reina_silver_lock_reversal',
    name: '白銀ロックリバーサル',
    attribute: CombatV1EnergyAttribute.joint,
    counterableFamilies: [
      CombatV1TechniqueFamily.crossface,
      CombatV1TechniqueFamily.figureFour,
    ],
  ),

  /// 専門型: ラリアット系のみを打属性で返す。
  'counter_reina_silver_flash_counter': CombatV1Counter(
    id: 'counter_reina_silver_flash_counter',
    name: '銀閃カウンター',
    attribute: CombatV1EnergyAttribute.strike,
    counterableFamilies: [CombatV1TechniqueFamily.lariat],
  ),
};
