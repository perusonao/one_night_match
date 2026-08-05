/// Technique Match Ver.2 UI改修（リング演出・立ち絵表示）で追加した、
/// レスラーIDから立ち絵アセットパスを引くための最小限のマップ。
///
/// 【立ち絵の出典】ユーザー添付のUIモックアップ画像（Technique Match UI
/// 新デザインイメージ）に描かれていた火神アカリ・豪田ミサキの2人分の
/// イラストのみを、`assets/images/wrestlers/`配下へ切り出して収録した
/// （新規イラストは作成していない。切り出し手順はPRの説明を参照）。
/// 白銀レイナ・黒蝶ジャックの立ち絵ソースは存在しないため、このマップには
/// 意図的に含めていない（ユーザー承認済み）。該当エントリが無いレスラーは
/// `technique_match_screen.dart`側でアイコンベースの代替表示にフォール
/// バックする。
///
/// 既存の`WrestlerDefinition.imagePath`とは独立した仕組み（そちらは
/// 現状どの画面でも実際には描画に使われていない自由入力欄のため、今回は
/// 流用せずTechnique Match専用の静的マップとした）。
const Map<String, String> techniqueWrestlerPortraits = {
  'wrestler_akari': 'assets/images/wrestlers/akari.png',
  'wrestler_misaki': 'assets/images/wrestlers/misaki.png',
};
