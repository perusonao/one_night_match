import 'technique_deck_deck.dart';
import 'technique_deck_models.dart';

/// Phase 6完了後のプレイテストで判明した「防御優位・決着ゼロ」問題を受け、
/// ユーザー指示により「Phase 7へ進む前に勝ち筋が明確に異なる2人分の正式な
/// モデルデッキを用意して検証する」ために追加した、手動構築の30枚デッキ。
///
/// 対象カードは [buildProvisionalTechniqueDeckCatalog]（`technique_deck_
/// defaults.dart`）に含まれる `td_p6_*` 系カード（Phase 6モデルデッキ専用に
/// 追加）と、既存の共通カードのみを使う。**依然としてゲームバランス調整済みの
/// 正式データではない**（最初の比較基準として、ユーザー指定の構成をそのまま
/// 反映したもの）。
///
/// 「Phase 6専用暫定構成」（フィニッシャー／エスケープ／リバーサル／
/// 特殊キックアウトを除いた30枚。ユーザー指定の内訳表に準拠）:
///
/// | 種別 | 枚数 |
/// |---|---|
/// | 技エネルギー | 13 |
/// | 通常技 | 9 |
/// | 固有技 | 5 |
/// | 通常キックアウト | 1 |
/// | ロープブレイク | 1 |
/// | 調整枠 | 1 |
/// | 合計 | 30 |
///
/// 火神アカリ: 打撃・スピード型。スタンド技でダウンを奪い、フォールへつなぐ
/// （調整枠はフォール効果技）。
/// 白銀レイナ: 関節・テクニカル型。ダウン技からギブアップ技へつなぐ
/// （調整枠はギブアップ効果技）。
/// 豪田ミサキ: パワー・投げ型。低HP高火力。スタンド技でダウンを奪い、
/// パワー技のフォールへつなぐ（調整枠はフォール効果技）。
/// 黒蝶ジャック: ラフファイト・関節型。妨害技でダウンを奪い、絞め技の
/// ギブアップへつなぐ（調整枠はギブアップ効果技）。

/// Phase 7（フィニッシャー実装）向けに追加した4人分の正式モデルデッキ。
///
/// ユーザー指示（Phase 7設計仕様）に基づき、Phase 6モデルデッキの内訳から
/// 通常技を9→6枚に減らし、代わりにフィニッシャー3枚・エスケープ1枚・
/// リバーサル1枚・特殊キックアウト1枚を追加した30枚構成。
///
/// | 種別 | 枚数 |
/// |---|---|
/// | 技エネルギー | 13 |
/// | 通常技（3種×2枚） | 6 |
/// | 固有技（Phase 6の5枚から3枚を採用） | 3 |
/// | フィニッシャー（`td_p7_*_fin_*`、3枚固定） | 3 |
/// | 通常キックアウト | 1 |
/// | ロープブレイク | 1 |
/// | 特殊キックアウト（フィニッシャー脱出専用） | 1 |
/// | エスケープ | 1 |
/// | リバーサル | 1 |
/// | 合計 | 30 |
///
/// フィニッシャー3枚は、ユーザー指定のテンプレート「1枚はtargetState: any・
/// 1枚はレスラーの得意状態・1枚は条件付きの高性能技」に沿って
/// `technique_deck_defaults.dart`側で構成済み。エネルギー配分・固有技の
/// 選出はPhase 6モデルデッキと同じ方針を踏襲する。

/// 火神アカリのPhase 7モデルデッキ（30枚）。
/// エネルギー配分: 打撃7・投げ4・返し2（Phase 6と同じ）。
TechniqueDeckDefinition buildAkariPhase7ModelDeck({
  String deckId = 'model_akari_phase7',
  String deckName = '火神アカリ Phase 7モデルデッキ',
}) => TechniqueDeckBuilder(
  wrestlerId: 'wrestler_akari',
  id: deckId,
  name: deckName,
)
    // 技エネルギー13枚（打撃7・投げ4・返し2）。
    .addCard('td_energy_strike', TechniqueDeckCardType.energy, count: 7)
    .addCard('td_energy_throwMove', TechniqueDeckCardType.energy, count: 4)
    .addCard('td_energy_counter', TechniqueDeckCardType.energy, count: 2)
    // 通常技6枚（同名2枚 × 3種）。
    .addCard('td_normal_strike_1', TechniqueDeckCardType.technique, count: 2)
    .addCard('td_normal_throw_1', TechniqueDeckCardType.technique, count: 2)
    .addCard('td_normal_counter_1', TechniqueDeckCardType.technique, count: 2)
    // 固有技3枚（Phase 6の5枚から採用）。
    .addCard('td_p6_akari_sig_kneestrike', TechniqueDeckCardType.technique)
    .addCard('td_p6_akari_sig_german', TechniqueDeckCardType.technique)
    .addCard('td_p6_akari_sig_suplex', TechniqueDeckCardType.technique)
    // フィニッシャー3枚（any / スタンド得意 / 高HEAT+低HP条件）。
    .addCard(
      'td_p7_akari_fin_burningdrive',
      TechniqueDeckCardType.technique,
    )
    .addCard(
      'td_p7_akari_fin_phoenixdriver',
      TechniqueDeckCardType.technique,
    )
    .addCard('td_p7_akari_fin_finalflame', TechniqueDeckCardType.technique)
    // 通常キックアウト1枚・ロープブレイク1枚・特殊キックアウト1枚・
    // エスケープ1枚・リバーサル1枚。
    .addCard('td_kickout_normal_1', TechniqueDeckCardType.kickOut)
    .addCard('td_ropebreak_1', TechniqueDeckCardType.ropeBreak)
    .addCard('td_kickout_special_1', TechniqueDeckCardType.kickOut)
    .addCard('td_escape_1', TechniqueDeckCardType.escape)
    .addCard('td_reversal_1', TechniqueDeckCardType.reversal)
    .build();

/// 白銀レイナのPhase 7モデルデッキ（30枚）。
/// エネルギー配分: 関節7・投げ3・返し3（Phase 6と同じ）。
TechniqueDeckDefinition buildReinaPhase7ModelDeck({
  String deckId = 'model_reina_phase7',
  String deckName = '白銀レイナ Phase 7モデルデッキ',
}) => TechniqueDeckBuilder(
  wrestlerId: 'wrestler_reina',
  id: deckId,
  name: deckName,
)
    // 技エネルギー13枚（関節7・投げ3・返し3）。
    .addCard('td_energy_submission', TechniqueDeckCardType.energy, count: 7)
    .addCard('td_energy_throwMove', TechniqueDeckCardType.energy, count: 3)
    .addCard('td_energy_counter', TechniqueDeckCardType.energy, count: 3)
    // 通常技6枚（同名2枚 × 3種）。
    .addCard(
      'td_normal_submission_1',
      TechniqueDeckCardType.technique,
      count: 2,
    )
    .addCard('td_p6_normal_takedown', TechniqueDeckCardType.technique, count: 2)
    .addCard('td_normal_counter_1', TechniqueDeckCardType.technique, count: 2)
    // 固有技3枚（Phase 6の5枚から採用）。
    .addCard('td_p6_reina_sig_kneebar', TechniqueDeckCardType.technique)
    .addCard('td_p6_reina_sig_brainbuster', TechniqueDeckCardType.technique)
    .addCard('td_p6_reina_sig_camel', TechniqueDeckCardType.technique)
    // フィニッシャー3枚（any / ダウン得意 / 相手ダウン+低HP条件）。
    .addCard('td_p7_reina_fin_silverwing', TechniqueDeckCardType.technique)
    .addCard('td_p7_reina_fin_armbar_ex', TechniqueDeckCardType.technique)
    .addCard('td_p7_reina_fin_absolute', TechniqueDeckCardType.technique)
    // 通常キックアウト1枚・ロープブレイク1枚・特殊キックアウト1枚・
    // エスケープ1枚・リバーサル1枚。
    .addCard('td_kickout_normal_1', TechniqueDeckCardType.kickOut)
    .addCard('td_ropebreak_1', TechniqueDeckCardType.ropeBreak)
    .addCard('td_kickout_special_1', TechniqueDeckCardType.kickOut)
    .addCard('td_escape_1', TechniqueDeckCardType.escape)
    .addCard('td_reversal_1', TechniqueDeckCardType.reversal)
    .build();

/// 豪田ミサキのPhase 7モデルデッキ（30枚）。
/// エネルギー配分: 投げ7・打撃4・返し2（Phase 6と同じ）。
TechniqueDeckDefinition buildMisakiPhase7ModelDeck({
  String deckId = 'model_misaki_phase7',
  String deckName = '豪田ミサキ Phase 7モデルデッキ',
}) => TechniqueDeckBuilder(
  wrestlerId: 'wrestler_misaki',
  id: deckId,
  name: deckName,
)
    // 技エネルギー13枚（投げ7・打撃4・返し2）。
    .addCard('td_energy_throwMove', TechniqueDeckCardType.energy, count: 7)
    .addCard('td_energy_strike', TechniqueDeckCardType.energy, count: 4)
    .addCard('td_energy_counter', TechniqueDeckCardType.energy, count: 2)
    // 通常技6枚（同名2枚 × 3種）。
    .addCard('td_normal_throw_1', TechniqueDeckCardType.technique, count: 2)
    .addCard('td_normal_strike_1', TechniqueDeckCardType.technique, count: 2)
    .addCard('td_normal_counter_1', TechniqueDeckCardType.technique, count: 2)
    // 固有技3枚（Phase 6の5枚から採用）。
    .addCard('td_p6_misaki_sig_elbow', TechniqueDeckCardType.technique)
    .addCard('td_p6_misaki_sig_bodyslam', TechniqueDeckCardType.technique)
    .addCard('td_p6_misaki_sig_backdrop', TechniqueDeckCardType.technique)
    // フィニッシャー3枚（any / 相手低HP得意 / 相手低HP+高HEAT条件）。
    .addCard('td_p7_misaki_fin_ironpress', TechniqueDeckCardType.technique)
    .addCard('td_p7_misaki_fin_gouda', TechniqueDeckCardType.technique)
    .addCard('td_p7_misaki_fin_ultimate', TechniqueDeckCardType.technique)
    // 通常キックアウト1枚・ロープブレイク1枚・特殊キックアウト1枚・
    // エスケープ1枚・リバーサル1枚。
    .addCard('td_kickout_normal_1', TechniqueDeckCardType.kickOut)
    .addCard('td_ropebreak_1', TechniqueDeckCardType.ropeBreak)
    .addCard('td_kickout_special_1', TechniqueDeckCardType.kickOut)
    .addCard('td_escape_1', TechniqueDeckCardType.escape)
    .addCard('td_reversal_1', TechniqueDeckCardType.reversal)
    .build();

/// 黒蝶ジャックのPhase 7モデルデッキ（30枚）。
/// エネルギー配分: 関節7・ラフ4・返し2（Phase 6と同じ）。
TechniqueDeckDefinition buildJackPhase7ModelDeck({
  String deckId = 'model_jack_phase7',
  String deckName = '黒蝶ジャック Phase 7モデルデッキ',
}) => TechniqueDeckBuilder(
  wrestlerId: 'wrestler_jack',
  id: deckId,
  name: deckName,
)
    // 技エネルギー13枚（関節7・ラフ4・返し2）。
    .addCard('td_energy_submission', TechniqueDeckCardType.energy, count: 7)
    .addCard('td_energy_rough', TechniqueDeckCardType.energy, count: 4)
    .addCard('td_energy_counter', TechniqueDeckCardType.energy, count: 2)
    // 通常技6枚（同名2枚 × 3種）。
    .addCard(
      'td_normal_submission_1',
      TechniqueDeckCardType.technique,
      count: 2,
    )
    .addCard('td_normal_rough_1', TechniqueDeckCardType.technique, count: 2)
    .addCard('td_normal_counter_1', TechniqueDeckCardType.technique, count: 2)
    // 固有技3枚（Phase 6の5枚から採用）。
    .addCard('td_p6_jack_sig_lowblow', TechniqueDeckCardType.technique)
    .addCard('td_p6_jack_sig_neckbreaker', TechniqueDeckCardType.technique)
    .addCard('td_p6_jack_sig_clutch', TechniqueDeckCardType.technique)
    // フィニッシャー3枚（any / 自分低HP得意 / 自分低HP+高HEAT条件）。
    .addCard(
      'td_p7_jack_fin_blackbutterfly',
      TechniqueDeckCardType.technique,
    )
    .addCard('td_p7_jack_fin_darkfall', TechniqueDeckCardType.technique)
    .addCard('td_p7_jack_fin_judgment', TechniqueDeckCardType.technique)
    // 通常キックアウト1枚・ロープブレイク1枚・特殊キックアウト1枚・
    // エスケープ1枚・リバーサル1枚。
    .addCard('td_kickout_normal_1', TechniqueDeckCardType.kickOut)
    .addCard('td_ropebreak_1', TechniqueDeckCardType.ropeBreak)
    .addCard('td_kickout_special_1', TechniqueDeckCardType.kickOut)
    .addCard('td_escape_1', TechniqueDeckCardType.escape)
    .addCard('td_reversal_1', TechniqueDeckCardType.reversal)
    .build();

/// 火神アカリのPhase 6モデルデッキ（30枚）。
/// エネルギー配分: 打撃7・投げ4・返し2。
TechniqueDeckDefinition buildAkariPhase6ModelDeck({
  String deckId = 'model_akari_phase6',
  String deckName = '火神アカリ Phase 6モデルデッキ',
}) => TechniqueDeckBuilder(
  wrestlerId: 'wrestler_akari',
  id: deckId,
  name: deckName,
)
    // 技エネルギー13枚（打撃7・投げ4・返し2）。
    .addCard('td_energy_strike', TechniqueDeckCardType.energy, count: 7)
    .addCard('td_energy_throwMove', TechniqueDeckCardType.energy, count: 4)
    .addCard('td_energy_counter', TechniqueDeckCardType.energy, count: 2)
    // 通常技9枚（同名上限3枚 × 3種）。
    .addCard('td_normal_strike_1', TechniqueDeckCardType.technique, count: 3)
    .addCard('td_normal_throw_1', TechniqueDeckCardType.technique, count: 3)
    .addCard('td_normal_counter_1', TechniqueDeckCardType.technique, count: 3)
    // 固有技5枚（同名1枚ずつ）。
    .addCard(
      'td_p6_akari_sig_kneestrike',
      TechniqueDeckCardType.technique,
    )
    .addCard('td_p6_akari_sig_german', TechniqueDeckCardType.technique)
    .addCard('td_p6_akari_sig_suplex', TechniqueDeckCardType.technique)
    .addCard('td_p6_akari_sig_lariat', TechniqueDeckCardType.technique)
    .addCard('td_p6_akari_sig_finalkick', TechniqueDeckCardType.technique)
    // 調整枠1枚（フォール効果技）。
    .addCard('td_p6_akari_fall_extra', TechniqueDeckCardType.technique)
    // 通常キックアウト1枚・ロープブレイク1枚。
    .addCard('td_kickout_normal_1', TechniqueDeckCardType.kickOut)
    .addCard('td_ropebreak_1', TechniqueDeckCardType.ropeBreak)
    .build();

/// 白銀レイナのPhase 6モデルデッキ（30枚）。
/// エネルギー配分: 関節7・投げ3・返し3。
TechniqueDeckDefinition buildReinaPhase6ModelDeck({
  String deckId = 'model_reina_phase6',
  String deckName = '白銀レイナ Phase 6モデルデッキ',
}) => TechniqueDeckBuilder(
  wrestlerId: 'wrestler_reina',
  id: deckId,
  name: deckName,
)
    // 技エネルギー13枚（関節7・投げ3・返し3）。
    .addCard('td_energy_submission', TechniqueDeckCardType.energy, count: 7)
    .addCard('td_energy_throwMove', TechniqueDeckCardType.energy, count: 3)
    .addCard('td_energy_counter', TechniqueDeckCardType.energy, count: 3)
    // 通常技9枚（同名上限3枚 × 3種）。
    .addCard(
      'td_normal_submission_1',
      TechniqueDeckCardType.technique,
      count: 3,
    )
    .addCard('td_p6_normal_takedown', TechniqueDeckCardType.technique, count: 3)
    .addCard('td_normal_counter_1', TechniqueDeckCardType.technique, count: 3)
    // 固有技5枚（同名1枚ずつ）。
    .addCard('td_p6_reina_sig_kneebar', TechniqueDeckCardType.technique)
    .addCard('td_p6_reina_sig_brainbuster', TechniqueDeckCardType.technique)
    .addCard('td_p6_reina_sig_camel', TechniqueDeckCardType.technique)
    .addCard('td_p6_reina_sig_figurefour', TechniqueDeckCardType.technique)
    .addCard('td_p6_reina_sig_crossface', TechniqueDeckCardType.technique)
    // 調整枠1枚（ギブアップ効果技）。
    .addCard('td_p6_reina_giveup_extra', TechniqueDeckCardType.technique)
    // 通常キックアウト1枚・ロープブレイク1枚。
    .addCard('td_kickout_normal_1', TechniqueDeckCardType.kickOut)
    .addCard('td_ropebreak_1', TechniqueDeckCardType.ropeBreak)
    .build();

/// 豪田ミサキのPhase 6モデルデッキ（30枚）。
/// エネルギー配分: 投げ7・打撃4・返し2（アカリと逆の比重で、パワー型の
/// 投げ技を主力に据える）。
TechniqueDeckDefinition buildMisakiPhase6ModelDeck({
  String deckId = 'model_misaki_phase6',
  String deckName = '豪田ミサキ Phase 6モデルデッキ',
}) => TechniqueDeckBuilder(
  wrestlerId: 'wrestler_misaki',
  id: deckId,
  name: deckName,
)
    // 技エネルギー13枚（投げ7・打撃4・返し2）。
    .addCard('td_energy_throwMove', TechniqueDeckCardType.energy, count: 7)
    .addCard('td_energy_strike', TechniqueDeckCardType.energy, count: 4)
    .addCard('td_energy_counter', TechniqueDeckCardType.energy, count: 2)
    // 通常技9枚（同名上限3枚 × 3種）。
    .addCard('td_normal_throw_1', TechniqueDeckCardType.technique, count: 3)
    .addCard('td_normal_strike_1', TechniqueDeckCardType.technique, count: 3)
    .addCard('td_normal_counter_1', TechniqueDeckCardType.technique, count: 3)
    // 固有技5枚（同名1枚ずつ）。
    .addCard('td_p6_misaki_sig_elbow', TechniqueDeckCardType.technique)
    .addCard('td_p6_misaki_sig_bodyslam', TechniqueDeckCardType.technique)
    .addCard('td_p6_misaki_sig_backdrop', TechniqueDeckCardType.technique)
    .addCard('td_p6_misaki_sig_lariat', TechniqueDeckCardType.technique)
    .addCard('td_p6_misaki_sig_powerbomb', TechniqueDeckCardType.technique)
    // 調整枠1枚（フォール効果技）。
    .addCard('td_p6_misaki_fall_extra', TechniqueDeckCardType.technique)
    // 通常キックアウト1枚・ロープブレイク1枚。
    .addCard('td_kickout_normal_1', TechniqueDeckCardType.kickOut)
    .addCard('td_ropebreak_1', TechniqueDeckCardType.ropeBreak)
    .build();

/// 黒蝶ジャックのPhase 6モデルデッキ（30枚）。
/// エネルギー配分: 関節7・ラフ4・返し2（レイナと同じギブアップ寄りだが、
/// ラフ技によるダウン奪取という別経路を持つ）。
TechniqueDeckDefinition buildJackPhase6ModelDeck({
  String deckId = 'model_jack_phase6',
  String deckName = '黒蝶ジャック Phase 6モデルデッキ',
}) => TechniqueDeckBuilder(
  wrestlerId: 'wrestler_jack',
  id: deckId,
  name: deckName,
)
    // 技エネルギー13枚（関節7・ラフ4・返し2）。
    .addCard('td_energy_submission', TechniqueDeckCardType.energy, count: 7)
    .addCard('td_energy_rough', TechniqueDeckCardType.energy, count: 4)
    .addCard('td_energy_counter', TechniqueDeckCardType.energy, count: 2)
    // 通常技9枚（同名上限3枚 × 3種）。
    .addCard(
      'td_normal_submission_1',
      TechniqueDeckCardType.technique,
      count: 3,
    )
    .addCard('td_normal_rough_1', TechniqueDeckCardType.technique, count: 3)
    .addCard('td_normal_counter_1', TechniqueDeckCardType.technique, count: 3)
    // 固有技5枚（同名1枚ずつ）。
    .addCard('td_p6_jack_sig_lowblow', TechniqueDeckCardType.technique)
    .addCard('td_p6_jack_sig_neckbreaker', TechniqueDeckCardType.technique)
    .addCard('td_p6_jack_sig_clutch', TechniqueDeckCardType.technique)
    .addCard('td_p6_jack_sig_chair', TechniqueDeckCardType.technique)
    .addCard('td_p6_jack_sig_deathlock', TechniqueDeckCardType.technique)
    // 調整枠1枚（ギブアップ効果技）。
    .addCard('td_p6_jack_giveup_extra', TechniqueDeckCardType.technique)
    // 通常キックアウト1枚・ロープブレイク1枚。
    .addCard('td_kickout_normal_1', TechniqueDeckCardType.kickOut)
    .addCard('td_ropebreak_1', TechniqueDeckCardType.ropeBreak)
    .build();
