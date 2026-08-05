/// レスラーIDから立ち絵アセットパスを引くための最小限のマップ。
///
/// 【立ち絵の出典】Technique Deck Rules Phase 7Aでユーザーが添付した
/// レスラー4人分のリファレンス画像から、各レスラーの立ち絵のみを
/// 切り出して`assets/images/wrestlers/`配下へ収録した（新規イラストは
/// 作成していない。背景除去はチェッカーボード地の透過処理により実施）。
/// Ver.2時点ではアカリ・ミサキの2人分のみだったが、Phase 7Aで白銀レイナ・
/// 黒蝶ジャックの立ち絵ソースが揃ったため、4人分すべてを収録している。
///
/// 既存の`WrestlerDefinition.imagePath`とは独立した仕組み（そちらは
/// 現状どの画面でも実際には描画に使われていない自由入力欄のため、今回も
/// 流用せずTechnique Deck専用の静的マップとした）。
const Map<String, String> techniqueWrestlerPortraits = {
  'wrestler_akari': 'assets/images/wrestlers/akari.png',
  'wrestler_misaki': 'assets/images/wrestlers/misaki.png',
  'wrestler_reina': 'assets/images/wrestlers/reina.png',
  'wrestler_jack': 'assets/images/wrestlers/jack.png',
};

/// Technique Match UI/UX改善+CPU実装ラウンドで追加した、試合画面
/// （プレイヤーカードの小さな枠）専用のバストアップ（胸から上）画像。
///
/// [techniqueWrestlerPortraits] のフルボディ画像をそのまま小さな枠に
/// `BoxFit.cover`で詰め込むと顔が見切れる問題があったため、同じ
/// リファレンス画像から上半身のみを再度切り出した。フルボディ画像は
/// 引き続きリング演出パネルの背景（[technique_match_screen.dart]の
/// `_ringPanel`）で使用する。
const Map<String, String> techniqueWrestlerBustPortraits = {
  'wrestler_akari': 'assets/images/wrestlers/akari_bust.png',
  'wrestler_misaki': 'assets/images/wrestlers/misaki_bust.png',
  'wrestler_reina': 'assets/images/wrestlers/reina_bust.png',
  'wrestler_jack': 'assets/images/wrestlers/jack_bust.png',
};

/// レスラーごとの立ち絵表示調整値。
///
/// 表示は`BoxFit.contain`＋`Alignment.topCenter`を基準とし、レスラーごとに
/// 個別調整したい場合はここへ追加する（画像そのものを差し替えなくても、
/// 拡大率・水平/垂直オフセットだけで微調整できるようにする狙い）。
/// 未登録のレスラーIDは既定値（scale: 1.0, offsetX/Y: 0.0＝無調整）を使う。
class TechniquePortraitAdjustment {
  const TechniquePortraitAdjustment({
    this.scale = 1.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
  });

  /// 拡大率（1.0が等倍）。
  final double scale;

  /// 水平方向オフセット（-1.0〜1.0の`Alignment`相当。正で右へ寄る）。
  final double offsetX;

  /// 垂直方向オフセット（-1.0〜1.0の`Alignment`相当。正で下へ寄る）。
  final double offsetY;
}

const Map<String, TechniquePortraitAdjustment>
techniqueWrestlerPortraitAdjustments = {
  'wrestler_akari': TechniquePortraitAdjustment(),
  'wrestler_misaki': TechniquePortraitAdjustment(),
  'wrestler_reina': TechniquePortraitAdjustment(),
  'wrestler_jack': TechniquePortraitAdjustment(),
};

/// [wrestlerId] の調整値を取得する（未登録なら既定値）。
TechniquePortraitAdjustment techniquePortraitAdjustmentFor(String wrestlerId) =>
    techniqueWrestlerPortraitAdjustments[wrestlerId] ??
    const TechniquePortraitAdjustment();
