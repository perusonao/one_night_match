import 'technique_deck_deck.dart';
import 'technique_deck_models.dart';

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

// ============================================================
// Phase 7Aモデルデッキの登録簿（Technique Deck BuilderのUI・Technique
// Matchのデッキ解決優先度に、レスラーIDから対応するPhase 7Aモデルデッキを
// 引けるようにするための一覧）。
// ============================================================

/// レスラーIDからPhase 7Aモデルデッキの構築関数を引くための一覧。
/// 過去のPhase 6/7/7.5世代のモデルデッキ生成関数は本番未使用だったため
/// 削除済み（Rule Cleanupラウンド。経緯はdocs/history/
/// technique_deck_rule_history.md参照）。現行は本モデルデッキ（Phase 7A）が
/// 唯一の正式データであり、Technique Match（`_resolveDeck`）はこれのみを
/// 参照する。`td_p6_*`等の旧世代カード定義自体はカタログ
/// （`buildProvisionalTechniqueDeckCatalog`）や保存済み手動デッキとの互換性
/// のため引き続き残置している（削除していない）。
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
