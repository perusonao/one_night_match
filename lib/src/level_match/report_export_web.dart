// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web: 指定内容をJSONファイルとしてブラウザ経由でダウンロードする。
Future<bool> downloadTextFile(String filename, String content) async {
  final blob = html.Blob(<Object>[content], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
  return true;
}
