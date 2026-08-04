/// 非Web環境ではファイル選択に対応しないため、常にnull（呼び出し側は
/// テキスト貼り付け読込へフォールバックする）。
Future<String?> pickAndReadTextFile() async => null;
