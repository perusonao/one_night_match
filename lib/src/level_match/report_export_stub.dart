/// 非Webプラットフォーム: ファイルダウンロードは未対応（UI 側でクリップボードにフォールバック）。
Future<bool> downloadTextFile(String filename, String content) async => false;
