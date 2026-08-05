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

/// Phase 7.5（モデルデッキ最適化＋フィニッシャー条件分散）向けに追加した
/// 4人分のモデルデッキ。
///
/// Phase 7の1000試合検証で、フィニッシャー宣言率76.5%・決着率47.2%・
/// 通常決着率52.8%・技を使えないターン率59.4%と、いずれもユーザーの目標
/// レンジから逸脱していることが判明した。ユーザー指示により、フィニッシャー
/// 側の数値調整（HEAT閾値・威力・宣言確率）は行わず、代わりに以下の2点を
/// 見直して再検証する。
///
/// 1. **通常技を6枚→8枚に戻し、フィニッシャーを3枚→2枚へ**（「3枚は
///    投入できる上限であって、全員必ず3積みする必要はない」というユーザー
///    指示に基づく）。固有技も3枚→2枚に減らし、合計30枚に収めた。
/// 2. **フィニッシャー3枚の発動条件をレスラーごとに分散**（既存の
///    `td_p7_*`カード側で対応、`technique_deck_defaults.dart`参照）。
///
/// | 種別 | Phase 7 | Phase 7.5 |
/// |---|---|---|
/// | 技エネルギー | 13 | 13 |
/// | 通常技 | 6（3種×2枚） | 8（3種×3+3+2枚） |
/// | 固有技 | 3 | 2 |
/// | フィニッシャー | 3 | 2 |
/// | 通常キックアウト | 1 | 1 |
/// | ロープブレイク | 1 | 1 |
/// | 特殊キックアウト | 1 | 1 |
/// | エスケープ | 1 | 1 |
/// | リバーサル | 1 | 1 |
/// | 合計 | 30 | 30 |
///
/// フィニッシャー2枚の選定は、各レスラーの3枚のうち「targetState: any」枠と
/// 「得意状態限定（Phase 7.5で条件を撤去済み）」枠を採用し、最も条件が厳しい
/// 「条件付き高性能技」枠はカタログには残しつつ本デッキからは外した
/// （3枚同時投入前提を崩す、というユーザー指示の趣旨に沿った選定）。
/// 固有技2枚は各レスラーのPhase 7モデルデッキで採用していた3枚のうち先頭
/// 2枚を継続採用する。

/// 火神アカリのPhase 7.5モデルデッキ（30枚）。
/// エネルギー配分: 打撃7・投げ4・返し2（Phase 6・7と同じ）。
TechniqueDeckDefinition buildAkariPhase75ModelDeck({
  String deckId = 'model_akari_phase75',
  String deckName = '火神アカリ Phase 7.5モデルデッキ',
}) => TechniqueDeckBuilder(
  wrestlerId: 'wrestler_akari',
  id: deckId,
  name: deckName,
)
    // 技エネルギー13枚（打撃7・投げ4・返し2）。
    .addCard('td_energy_strike', TechniqueDeckCardType.energy, count: 7)
    .addCard('td_energy_throwMove', TechniqueDeckCardType.energy, count: 4)
    .addCard('td_energy_counter', TechniqueDeckCardType.energy, count: 2)
    // 通常技8枚（3種、同名上限3枚以内で3+3+2）。
    .addCard('td_normal_strike_1', TechniqueDeckCardType.technique, count: 3)
    .addCard('td_normal_throw_1', TechniqueDeckCardType.technique, count: 3)
    .addCard('td_normal_counter_1', TechniqueDeckCardType.technique, count: 2)
    // 固有技2枚（Phase 7の3枚から先頭2枚を継続採用）。
    .addCard('td_p6_akari_sig_kneestrike', TechniqueDeckCardType.technique)
    .addCard('td_p6_akari_sig_german', TechniqueDeckCardType.technique)
    // フィニッシャー2枚（any / スタンド得意。条件付き高性能技は本デッキ
    // からは除外）。
    .addCard(
      'td_p7_akari_fin_burningdrive',
      TechniqueDeckCardType.technique,
    )
    .addCard(
      'td_p7_akari_fin_phoenixdriver',
      TechniqueDeckCardType.technique,
    )
    // 通常キックアウト1枚・ロープブレイク1枚・特殊キックアウト1枚・
    // エスケープ1枚・リバーサル1枚。
    .addCard('td_kickout_normal_1', TechniqueDeckCardType.kickOut)
    .addCard('td_ropebreak_1', TechniqueDeckCardType.ropeBreak)
    .addCard('td_kickout_special_1', TechniqueDeckCardType.kickOut)
    .addCard('td_escape_1', TechniqueDeckCardType.escape)
    .addCard('td_reversal_1', TechniqueDeckCardType.reversal)
    .build();

/// 白銀レイナのPhase 7.5モデルデッキ（30枚）。
/// エネルギー配分: 関節7・投げ3・返し3（Phase 6・7と同じ）。
TechniqueDeckDefinition buildReinaPhase75ModelDeck({
  String deckId = 'model_reina_phase75',
  String deckName = '白銀レイナ Phase 7.5モデルデッキ',
}) => TechniqueDeckBuilder(
  wrestlerId: 'wrestler_reina',
  id: deckId,
  name: deckName,
)
    // 技エネルギー13枚（関節7・投げ3・返し3）。
    .addCard('td_energy_submission', TechniqueDeckCardType.energy, count: 7)
    .addCard('td_energy_throwMove', TechniqueDeckCardType.energy, count: 3)
    .addCard('td_energy_counter', TechniqueDeckCardType.energy, count: 3)
    // 通常技8枚（3種、同名上限3枚以内で3+3+2）。
    .addCard(
      'td_normal_submission_1',
      TechniqueDeckCardType.technique,
      count: 3,
    )
    .addCard('td_p6_normal_takedown', TechniqueDeckCardType.technique, count: 3)
    .addCard('td_normal_counter_1', TechniqueDeckCardType.technique, count: 2)
    // 固有技2枚（Phase 7の3枚から先頭2枚を継続採用）。
    .addCard('td_p6_reina_sig_kneebar', TechniqueDeckCardType.technique)
    .addCard('td_p6_reina_sig_brainbuster', TechniqueDeckCardType.technique)
    // フィニッシャー2枚（any / ダウン得意。条件付き高性能技は本デッキ
    // からは除外）。
    .addCard('td_p7_reina_fin_silverwing', TechniqueDeckCardType.technique)
    .addCard('td_p7_reina_fin_armbar_ex', TechniqueDeckCardType.technique)
    // 通常キックアウト1枚・ロープブレイク1枚・特殊キックアウト1枚・
    // エスケープ1枚・リバーサル1枚。
    .addCard('td_kickout_normal_1', TechniqueDeckCardType.kickOut)
    .addCard('td_ropebreak_1', TechniqueDeckCardType.ropeBreak)
    .addCard('td_kickout_special_1', TechniqueDeckCardType.kickOut)
    .addCard('td_escape_1', TechniqueDeckCardType.escape)
    .addCard('td_reversal_1', TechniqueDeckCardType.reversal)
    .build();

/// 豪田ミサキのPhase 7.5モデルデッキ（30枚）。
/// エネルギー配分: 投げ7・打撃4・返し2（Phase 6・7と同じ）。
TechniqueDeckDefinition buildMisakiPhase75ModelDeck({
  String deckId = 'model_misaki_phase75',
  String deckName = '豪田ミサキ Phase 7.5モデルデッキ',
}) => TechniqueDeckBuilder(
  wrestlerId: 'wrestler_misaki',
  id: deckId,
  name: deckName,
)
    // 技エネルギー13枚（投げ7・打撃4・返し2）。
    .addCard('td_energy_throwMove', TechniqueDeckCardType.energy, count: 7)
    .addCard('td_energy_strike', TechniqueDeckCardType.energy, count: 4)
    .addCard('td_energy_counter', TechniqueDeckCardType.energy, count: 2)
    // 通常技8枚（3種、同名上限3枚以内で3+3+2）。
    .addCard('td_normal_throw_1', TechniqueDeckCardType.technique, count: 3)
    .addCard('td_normal_strike_1', TechniqueDeckCardType.technique, count: 3)
    .addCard('td_normal_counter_1', TechniqueDeckCardType.technique, count: 2)
    // 固有技2枚（Phase 7の3枚から先頭2枚を継続採用）。
    .addCard('td_p6_misaki_sig_elbow', TechniqueDeckCardType.technique)
    .addCard('td_p6_misaki_sig_bodyslam', TechniqueDeckCardType.technique)
    // フィニッシャー2枚（any / ダウン得意。条件付き高性能技は本デッキ
    // からは除外）。
    .addCard('td_p7_misaki_fin_ironpress', TechniqueDeckCardType.technique)
    .addCard('td_p7_misaki_fin_gouda', TechniqueDeckCardType.technique)
    // 通常キックアウト1枚・ロープブレイク1枚・特殊キックアウト1枚・
    // エスケープ1枚・リバーサル1枚。
    .addCard('td_kickout_normal_1', TechniqueDeckCardType.kickOut)
    .addCard('td_ropebreak_1', TechniqueDeckCardType.ropeBreak)
    .addCard('td_kickout_special_1', TechniqueDeckCardType.kickOut)
    .addCard('td_escape_1', TechniqueDeckCardType.escape)
    .addCard('td_reversal_1', TechniqueDeckCardType.reversal)
    .build();

/// 黒蝶ジャックのPhase 7.5モデルデッキ（30枚）。
/// エネルギー配分: 関節7・ラフ4・返し2（Phase 6・7と同じ）。
TechniqueDeckDefinition buildJackPhase75ModelDeck({
  String deckId = 'model_jack_phase75',
  String deckName = '黒蝶ジャック Phase 7.5モデルデッキ',
}) => TechniqueDeckBuilder(
  wrestlerId: 'wrestler_jack',
  id: deckId,
  name: deckName,
)
    // 技エネルギー13枚（関節7・ラフ4・返し2）。
    .addCard('td_energy_submission', TechniqueDeckCardType.energy, count: 7)
    .addCard('td_energy_rough', TechniqueDeckCardType.energy, count: 4)
    .addCard('td_energy_counter', TechniqueDeckCardType.energy, count: 2)
    // 通常技8枚（3種、同名上限3枚以内で3+3+2）。
    .addCard(
      'td_normal_submission_1',
      TechniqueDeckCardType.technique,
      count: 3,
    )
    .addCard('td_normal_rough_1', TechniqueDeckCardType.technique, count: 3)
    .addCard('td_normal_counter_1', TechniqueDeckCardType.technique, count: 2)
    // 固有技2枚（Phase 7の3枚から先頭2枚を継続採用）。
    .addCard('td_p6_jack_sig_lowblow', TechniqueDeckCardType.technique)
    .addCard('td_p6_jack_sig_neckbreaker', TechniqueDeckCardType.technique)
    // フィニッシャー2枚（any / ダウン得意。条件付き高性能技は本デッキ
    // からは除外）。
    .addCard(
      'td_p7_jack_fin_blackbutterfly',
      TechniqueDeckCardType.technique,
    )
    .addCard('td_p7_jack_fin_darkfall', TechniqueDeckCardType.technique)
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

/// Technique Deck Rules Phase 7A（レスラーカード・技カード・モデルデッキ
/// 実装）向けに追加した4人分の正式モデルデッキ。
///
/// ユーザー指示の構成（エスケープ・リバーサルを含まない30枚）:
///
/// | 種別 | 枚数 |
/// |---|---|
/// | 技エネルギー | 13 |
/// | 通常技（`td_p7a_*_normal_*`、8種×1枚） | 8 |
/// | 固有技（新規2種×1枚 + 既存`td_p6_*_sig_*`から2種×1枚） | 4 |
/// | フィニッシャー（`td_p7a_*_fin_*`、2種×1枚） | 2 |
/// | 通常キックアウト | 1 |
/// | ロープブレイク | 1 |
/// | 特殊キックアウト | 1 |
/// | 合計 | 30 |
///
/// 固有技はバリデータの同名上限（固有技は同名1枚まで、`technique_deck_
/// deck.dart`の`_sameNameLimitFor`）があるため、ユーザー指定の新規2種
/// （各1枚）だけでは4枚に届かない。既存のPhase 6固有技（`td_p6_*_sig_*`、
/// 各レスラー5種保有）から2種を1枚ずつ追加採用することで、同名上限に
/// 抵触せず4枚構成を満たした。
TechniqueDeckDefinition buildAkariPhase7AModelDeck({
  String deckId = 'model_akari_phase7a',
  String deckName = '火神アカリ Phase 7Aモデルデッキ',
}) => TechniqueDeckBuilder(
  wrestlerId: 'wrestler_akari',
  id: deckId,
  name: deckName,
)
    // 技エネルギー13枚（打撃6・投げ4・飛び3）。
    .addCard('td_energy_strike', TechniqueDeckCardType.energy, count: 6)
    .addCard('td_energy_throwMove', TechniqueDeckCardType.energy, count: 4)
    .addCard('td_energy_aerial', TechniqueDeckCardType.energy, count: 3)
    // 通常技8枚（8種×1枚）。
    .addCard('td_p7a_akari_normal_elbow', TechniqueDeckCardType.technique)
    .addCard(
      'td_p7a_akari_normal_middlekick',
      TechniqueDeckCardType.technique,
    )
    .addCard('td_p7a_akari_normal_dropkick', TechniqueDeckCardType.technique)
    .addCard(
      'td_p7a_akari_normal_runningknee',
      TechniqueDeckCardType.technique,
    )
    .addCard('td_p7a_akari_normal_armwhip', TechniqueDeckCardType.technique)
    .addCard(
      'td_p7a_akari_normal_crossbody',
      TechniqueDeckCardType.technique,
    )
    .addCard('td_p7a_akari_normal_swingddt', TechniqueDeckCardType.technique)
    .addCard('td_p7a_akari_normal_forearm', TechniqueDeckCardType.technique)
    // 固有技4枚（新規2種 + 既存Phase 6固有技2種）。
    .addCard(
      'td_p7a_akari_sig_phoenixarmdrag',
      TechniqueDeckCardType.technique,
    )
    .addCard(
      'td_p7a_akari_sig_soulhighkick',
      TechniqueDeckCardType.technique,
    )
    .addCard('td_p6_akari_sig_kneestrike', TechniqueDeckCardType.technique)
    .addCard('td_p6_akari_sig_german', TechniqueDeckCardType.technique)
    // フィニッシャー2枚（any / スタンド得意）。
    .addCard(
      'td_p7a_akari_fin_phoenixsplash',
      TechniqueDeckCardType.technique,
    )
    .addCard(
      'td_p7a_akari_fin_redflarekick',
      TechniqueDeckCardType.technique,
    )
    // 通常キックアウト1枚・ロープブレイク1枚・特殊キックアウト1枚。
    .addCard('td_kickout_normal_1', TechniqueDeckCardType.kickOut)
    .addCard('td_ropebreak_1', TechniqueDeckCardType.ropeBreak)
    .addCard('td_kickout_special_1', TechniqueDeckCardType.kickOut)
    .build();

/// 豪田ミサキのPhase 7Aモデルデッキ（30枚）。
TechniqueDeckDefinition buildMisakiPhase7AModelDeck({
  String deckId = 'model_misaki_phase7a',
  String deckName = '豪田ミサキ Phase 7Aモデルデッキ',
}) => TechniqueDeckBuilder(
  wrestlerId: 'wrestler_misaki',
  id: deckId,
  name: deckName,
)
    // 技エネルギー13枚（投げ9・打撃4）。
    .addCard('td_energy_throwMove', TechniqueDeckCardType.energy, count: 9)
    .addCard('td_energy_strike', TechniqueDeckCardType.energy, count: 4)
    // 通常技8枚（8種×1枚）。
    .addCard('td_p7a_misaki_normal_bodyslam', TechniqueDeckCardType.technique)
    .addCard(
      'td_p7a_misaki_normal_shouldertackle',
      TechniqueDeckCardType.technique,
    )
    .addCard('td_p7a_misaki_normal_lariat', TechniqueDeckCardType.technique)
    .addCard('td_p7a_misaki_normal_backdrop', TechniqueDeckCardType.technique)
    .addCard(
      'td_p7a_misaki_normal_brainbuster',
      TechniqueDeckCardType.technique,
    )
    .addCard(
      'td_p7a_misaki_normal_powerslam',
      TechniqueDeckCardType.technique,
    )
    .addCard('td_p7a_misaki_normal_kneelift', TechniqueDeckCardType.technique)
    .addCard(
      'td_p7a_misaki_normal_spinebuster',
      TechniqueDeckCardType.technique,
    )
    // 固有技4枚（新規2種 + 既存Phase 6固有技2種）。
    .addCard('td_p7a_misaki_sig_powerbomb', TechniqueDeckCardType.technique)
    .addCard('td_p7a_misaki_sig_giantslam', TechniqueDeckCardType.technique)
    .addCard('td_p6_misaki_sig_elbow', TechniqueDeckCardType.technique)
    .addCard('td_p6_misaki_sig_bodyslam', TechniqueDeckCardType.technique)
    // フィニッシャー2枚（any / ダウン得意）。
    .addCard('td_p7a_misaki_fin_goudadriver', TechniqueDeckCardType.technique)
    .addCard(
      'td_p7a_misaki_fin_lastpowerbomb',
      TechniqueDeckCardType.technique,
    )
    // 通常キックアウト1枚・ロープブレイク1枚・特殊キックアウト1枚。
    .addCard('td_kickout_normal_1', TechniqueDeckCardType.kickOut)
    .addCard('td_ropebreak_1', TechniqueDeckCardType.ropeBreak)
    .addCard('td_kickout_special_1', TechniqueDeckCardType.kickOut)
    .build();

/// 白銀レイナのPhase 7Aモデルデッキ（30枚）。
TechniqueDeckDefinition buildReinaPhase7AModelDeck({
  String deckId = 'model_reina_phase7a',
  String deckName = '白銀レイナ Phase 7Aモデルデッキ',
}) => TechniqueDeckBuilder(
  wrestlerId: 'wrestler_reina',
  id: deckId,
  name: deckName,
)
    // 技エネルギー13枚（関節9・投げ3・打撃1）。
    .addCard('td_energy_submission', TechniqueDeckCardType.energy, count: 9)
    .addCard('td_energy_throwMove', TechniqueDeckCardType.energy, count: 3)
    .addCard('td_energy_strike', TechniqueDeckCardType.energy, count: 1)
    // 通常技8枚（8種×1枚）。
    .addCard('td_p7a_reina_normal_elbow', TechniqueDeckCardType.technique)
    .addCard(
      'td_p7a_reina_normal_dragonscrew',
      TechniqueDeckCardType.technique,
    )
    .addCard(
      'td_p7a_reina_normal_armbreaker',
      TechniqueDeckCardType.technique,
    )
    .addCard('td_p7a_reina_normal_headlock', TechniqueDeckCardType.technique)
    .addCard(
      'td_p7a_reina_normal_droptoehold',
      TechniqueDeckCardType.technique,
    )
    .addCard('td_p7a_reina_normal_udehishigi', TechniqueDeckCardType.technique)
    .addCard(
      'td_p7a_reina_normal_figurefour',
      TechniqueDeckCardType.technique,
    )
    .addCard(
      'td_p7a_reina_normal_sideheadlock',
      TechniqueDeckCardType.technique,
    )
    // 固有技4枚（新規2種 + 既存Phase 6固有技2種）。
    .addCard('td_p7a_reina_sig_crossface', TechniqueDeckCardType.technique)
    .addCard(
      'td_p7a_reina_sig_figurefour_lock',
      TechniqueDeckCardType.technique,
    )
    .addCard('td_p6_reina_sig_kneebar', TechniqueDeckCardType.technique)
    .addCard('td_p6_reina_sig_brainbuster', TechniqueDeckCardType.technique)
    // フィニッシャー2枚（any / ダウン得意）。
    .addCard('td_p7a_reina_fin_icelock', TechniqueDeckCardType.technique)
    .addCard(
      'td_p7a_reina_fin_eternalcross',
      TechniqueDeckCardType.technique,
    )
    // 通常キックアウト1枚・ロープブレイク1枚・特殊キックアウト1枚。
    .addCard('td_kickout_normal_1', TechniqueDeckCardType.kickOut)
    .addCard('td_ropebreak_1', TechniqueDeckCardType.ropeBreak)
    .addCard('td_kickout_special_1', TechniqueDeckCardType.kickOut)
    .build();

/// 黒蝶ジャックのPhase 7Aモデルデッキ（30枚）。
TechniqueDeckDefinition buildJackPhase7AModelDeck({
  String deckId = 'model_jack_phase7a',
  String deckName = '黒蝶ジャック Phase 7Aモデルデッキ',
}) => TechniqueDeckBuilder(
  wrestlerId: 'wrestler_jack',
  id: deckId,
  name: deckName,
)
    // 技エネルギー13枚（ラフ5・関節5・投げ2・打撃1）。
    .addCard('td_energy_rough', TechniqueDeckCardType.energy, count: 5)
    .addCard('td_energy_submission', TechniqueDeckCardType.energy, count: 5)
    .addCard('td_energy_throwMove', TechniqueDeckCardType.energy, count: 2)
    .addCard('td_energy_strike', TechniqueDeckCardType.energy, count: 1)
    // 通常技8枚（8種×1枚）。
    .addCard('td_p7a_jack_normal_lowblow', TechniqueDeckCardType.technique)
    .addCard('td_p7a_jack_normal_weapon', TechniqueDeckCardType.technique)
    .addCard('td_p7a_jack_normal_ddt', TechniqueDeckCardType.technique)
    .addCard('td_p7a_jack_normal_choke', TechniqueDeckCardType.technique)
    .addCard('td_p7a_jack_normal_ironclaw', TechniqueDeckCardType.technique)
    .addCard(
      'td_p7a_jack_normal_neckhanging',
      TechniqueDeckCardType.technique,
    )
    .addCard('td_p7a_jack_normal_facestomp', TechniqueDeckCardType.technique)
    .addCard('td_p7a_jack_normal_elbow', TechniqueDeckCardType.technique)
    // 固有技4枚（新規2種 + 既存Phase 6固有技2種）。
    .addCard('td_p7a_jack_sig_blackddt', TechniqueDeckCardType.technique)
    .addCard('td_p7a_jack_sig_darkneck', TechniqueDeckCardType.technique)
    .addCard('td_p6_jack_sig_lowblow', TechniqueDeckCardType.technique)
    .addCard('td_p6_jack_sig_neckbreaker', TechniqueDeckCardType.technique)
    // フィニッシャー2枚（any / ダウン得意）。
    .addCard(
      'td_p7a_jack_fin_blackbutterfly',
      TechniqueDeckCardType.technique,
    )
    .addCard('td_p7a_jack_fin_darkend', TechniqueDeckCardType.technique)
    // 通常キックアウト1枚・ロープブレイク1枚・特殊キックアウト1枚。
    .addCard('td_kickout_normal_1', TechniqueDeckCardType.kickOut)
    .addCard('td_ropebreak_1', TechniqueDeckCardType.ropeBreak)
    .addCard('td_kickout_special_1', TechniqueDeckCardType.kickOut)
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

// ============================================================
// Phase 7Aモデルデッキの登録簿（Technique Deck BuilderのUI・Technique
// Matchのデッキ解決優先度に、レスラーIDから対応するPhase 7Aモデルデッキを
// 引けるようにするための一覧）。
// ============================================================

/// レスラーIDからPhase 7Aモデルデッキの構築関数を引くための一覧。
/// Phase 6/7/7.5のモデルデッキは（UIへ未接続のまま）ここには含めない
/// （ユーザー指示は「Phase 7Aモデルデッキを優先的に使う」ため）。
final Map<String, TechniqueDeckDefinition Function()>
techniquePhase7AModelDeckBuilders = {
  'wrestler_akari': buildAkariPhase7AModelDeck,
  'wrestler_misaki': buildMisakiPhase7AModelDeck,
  'wrestler_reina': buildReinaPhase7AModelDeck,
  'wrestler_jack': buildJackPhase7AModelDeck,
};

/// [wrestlerId] に対応するPhase 7Aモデルデッキを返す。存在しない場合はnull。
TechniqueDeckDefinition? findTechniquePhase7AModelDeck(String wrestlerId) =>
    techniquePhase7AModelDeckBuilders[wrestlerId]?.call();
