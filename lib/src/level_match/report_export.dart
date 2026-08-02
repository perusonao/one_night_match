// プラットフォーム別の「テキストをファイルとして出力」実装を切り替える。
// Web ではブラウザのダウンロードを起動、それ以外は false（UI 側でクリップボードにフォールバック）。
export 'report_export_stub.dart'
    if (dart.library.html) 'report_export_web.dart';
