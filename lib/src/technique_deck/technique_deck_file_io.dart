// プラットフォーム別の「ファイルを選んでテキストを読み込む」実装を切り替える。
// Web ではファイル選択ダイアログを起動、それ以外は常にnull
// （呼び出し側はテキスト貼り付け読込にフォールバックする）。
export 'technique_deck_file_io_stub.dart'
    if (dart.library.html) 'technique_deck_file_io_web.dart';
