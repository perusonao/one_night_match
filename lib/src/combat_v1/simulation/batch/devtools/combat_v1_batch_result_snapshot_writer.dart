/// Combat Ver.1 Phase 12B-1 — Development Result Snapshot Writer
/// （development/verification専用。正式なCSV/JSON Export APIではない）。
///
/// [combatV1BatchResultSnapshotJsonString]/[writeCombatV1BatchResultSnapshot]は、
/// `combat_v1_batch_result_snapshot_serializer.dart`が組み立てたpureな
/// `Map<String, Object?>`を実際にJSON文字列化・ファイル書き出しする薄い
/// `dart:io` wrapper。`CombatV1BatchSimulationResult`自体にはfile write
/// メソッドを持たせない——domain modelとfile I/Oを分離する（11章相当）。
///
/// このfileはPhase 12B-1のdomain API（`CombatV1BatchSimulationRunner`等）
/// からは一切参照されない——`tool/combat_v1_batch_result_snapshot.dart`
/// （開発者が手動実行するscript）と、このfile自身のtestからのみ使う。
library;

import 'dart:convert';
import 'dart:io';

import '../combat_v1_batch_simulation_result.dart';
import 'combat_v1_batch_result_snapshot_serializer.dart';

/// development snapshot JSONのdefault出力directory。
///
/// `/build/`はリポジトリの`.gitignore`で既にignore対象になっている
/// （Flutter標準のbuild artifact directory）ため、ここへ書き出す限り
/// snapshotを個別にGit管理対象から除外する追加設定は不要。
const String combatV1BatchResultSnapshotDefaultDirectory =
    'build/combat_v1_simulation';

/// [result]のsnapshot JSONを、pretty-printされたJSON文字列として返す
/// （`dart:io`を使わない部分——fileへの書き出しは
/// [writeCombatV1BatchResultSnapshot]が行う）。
String combatV1BatchResultSnapshotJsonString(
  CombatV1BatchSimulationResult result, {
  required DateTime generatedAt,
}) {
  final json = combatV1BatchResultSnapshotJson(
    result,
    generatedAt: generatedAt,
  );
  return const JsonEncoder.withIndent('  ').convert(json);
}

/// 人間が識別しやすいsnapshot file名を生成する（13章相当）。
///
/// [generatedAt]はfile名の一意性・識別のためだけに使う——simulation
/// determinism（seed derivation・simulationMatchId等）には一切使わない。
String combatV1BatchResultSnapshotFileName(DateTime generatedAt) {
  String pad2(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${generatedAt.year}${pad2(generatedAt.month)}${pad2(generatedAt.day)}'
      '_${pad2(generatedAt.hour)}${pad2(generatedAt.minute)}'
      '${pad2(generatedAt.second)}';
  return 'combat_v1_batch_result_$stamp.json';
}

/// [result]のsnapshot JSONを[outputDirectory]（省略時は
/// [combatV1BatchResultSnapshotDefaultDirectory]）へファイルとして書き出す。
///
/// [result]は既に完成した[CombatV1BatchSimulationResult]（aggregate-only）
/// のみを入力とする——このwriter自身がbatchを実行したり、個別match
/// resultを保持したりすることはない（M1 memory契約に一切影響しない）。
Future<File> writeCombatV1BatchResultSnapshot(
  CombatV1BatchSimulationResult result, {
  String outputDirectory = combatV1BatchResultSnapshotDefaultDirectory,
  DateTime? generatedAt,
}) async {
  final effectiveGeneratedAt = generatedAt ?? DateTime.now();
  final jsonString = combatV1BatchResultSnapshotJsonString(
    result,
    generatedAt: effectiveGeneratedAt,
  );

  final directory = Directory(outputDirectory);
  await directory.create(recursive: true);

  final filePath =
      '$outputDirectory/${combatV1BatchResultSnapshotFileName(effectiveGeneratedAt)}';
  final file = File(filePath);
  await file.writeAsString(jsonString);
  return file;
}
