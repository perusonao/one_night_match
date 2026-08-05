import '../wrestler_editor/models.dart' show MoveAttribute;
import 'technique_deck_models.dart';

/// Technique Deck Rules Phase 7A（レスラーカード・技カード・モデルデッキ
/// 実装）で追加した、4人分の正式な「レスラーカード」データ。
///
/// 【方針】ゲームバランス調整ではなく、正式なモデルデータを実装することが
/// 目的（ユーザー指示）。`TechniqueMatchEngine`・ダメージ計算等の実戦
/// ロジックには一切接続しない、データ追加のみ。
///
/// - `hp`・`themeColor`は既存の`WrestlerDefinition`（`lib/src/
///   wrestler_editor/defaults.dart`、classic/energyモード）の値をそのまま
///   踏襲した（新規に数値を作らず、確立済みの個性付けを流用）。
/// - `imagePath`は`technique_wrestler_portraits.dart`の
///   `techniqueWrestlerPortraits`と同じ、添付リファレンス画像から切り出した
///   立ち絵を指す。
/// - `attributeBonus`・`initialHeat`・`passiveAbility`は本Phaseで新規に
///   定義した値であり、エンジンには未接続のフレーバー・将来のバランス調整
///   用データ（今後の調整候補として完了報告にも明記する）。
List<TechniqueDeckWrestlerProfile> buildTechniqueDeckWrestlerCatalog() => [
  const TechniqueDeckWrestlerProfile(
    wrestlerId: 'wrestler_akari',
    name: '火神アカリ',
    hp: 125,
    recoveryPower: 12,
    initialHeat: 0,
    attributeBonus: {
      MoveAttribute.strike: 3,
      MoveAttribute.aerial: 2,
      MoveAttribute.throwMove: 0,
      MoveAttribute.submission: -1,
      MoveAttribute.rough: 0,
    },
    passiveAbility:
        'バーニングスピリット：劣勢でも闘志を絶やさない、と伝えられる不屈の精神'
        '（フレーバーテキスト。効果としては未実装）。',
    description: '紅蓮のニューヒロイン。打たれ強さとスピードを武器に、格上にも臆せず'
        '挑みかかる次世代エース。',
    imagePath: 'assets/images/wrestlers/akari.png',
    themeColor: '#E53935',
  ),
  const TechniqueDeckWrestlerProfile(
    wrestlerId: 'wrestler_misaki',
    name: '豪田ミサキ',
    hp: 82,
    recoveryPower: 10,
    initialHeat: 0,
    attributeBonus: {
      MoveAttribute.throwMove: 3,
      MoveAttribute.rough: 1,
      MoveAttribute.strike: 1,
      MoveAttribute.submission: 0,
      MoveAttribute.aerial: -1,
    },
    passiveAbility:
        'パワープレッシャー：一撃の重さで相手の勢いを押し返す、と伝えられる'
        '圧力（フレーバーテキスト。効果としては未実装）。',
    description: '鋼鉄の女帝。一撃の重さと投げ技の完成度は随一だが、打たれ強さでは'
        '見劣りするハイリスク・ハイリターン型。',
    imagePath: 'assets/images/wrestlers/misaki.png',
    themeColor: '#F9A825',
  ),
  const TechniqueDeckWrestlerProfile(
    wrestlerId: 'wrestler_reina',
    name: '白銀レイナ',
    hp: 104,
    recoveryPower: 11,
    initialHeat: 0,
    attributeBonus: {
      MoveAttribute.submission: 3,
      MoveAttribute.throwMove: 1,
      MoveAttribute.strike: 0,
      MoveAttribute.aerial: 0,
      MoveAttribute.rough: -2,
    },
    passiveAbility:
        'シルバーテクニック：極めた関節は逃さない、と伝えられる精緻な技巧'
        '（フレーバーテキスト。効果としては未実装）。',
    description: 'リングの魔術師。関節技の完成度と粘り強さで格上を仕留めるテクニ'
        'シャン。ラフファイトは苦手。',
    imagePath: 'assets/images/wrestlers/reina.png',
    themeColor: '#8E8EAA',
  ),
  const TechniqueDeckWrestlerProfile(
    wrestlerId: 'wrestler_jack',
    name: '黒蝶ジャック',
    hp: 100,
    recoveryPower: 10,
    initialHeat: 0,
    attributeBonus: {
      MoveAttribute.rough: 3,
      MoveAttribute.submission: 2,
      MoveAttribute.strike: 1,
      MoveAttribute.throwMove: 0,
      MoveAttribute.aerial: -2,
    },
    passiveAbility:
        'ヒールインスティンクト：反則すれすれの一撃で主導権を握る、と伝え'
        'られる嫌らしさ（フレーバーテキスト。効果としては未実装）。',
    description: '漆黒の悪女。ラフファイトで主導権を奪い、絞め技・関節技へつなぐ'
        '嫌らしい戦い方を得意とする。',
    imagePath: 'assets/images/wrestlers/jack.png',
    themeColor: '#9C27B0',
  ),
];
