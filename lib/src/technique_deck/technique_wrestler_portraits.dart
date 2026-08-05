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
