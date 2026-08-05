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
