// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;

/// Web: ファイル選択ダイアログを開き、選択されたテキストファイルの内容を返す。
/// キャンセルされた場合はnull。
Future<String?> pickAndReadTextFile() {
  final completer = Completer<String?>();
  final input = html.FileUploadInputElement()..accept = '.json,application/json';
  input.click();
  input.onChange.listen((event) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      return;
    }
    final reader = html.FileReader();
    reader.readAsText(files[0]);
    reader.onLoadEnd.listen((event) {
      final result = reader.result;
      completer.complete(result is String ? result : null);
    });
  });
  return completer.future;
}
