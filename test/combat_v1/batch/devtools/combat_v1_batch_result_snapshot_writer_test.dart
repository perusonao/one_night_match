// Combat Ver.1 Phase 12B-1 — Development Result Snapshot Writerの test。
//
// writeCombatV1BatchResultSnapshot（lib/src/combat_v1/simulation/batch/
// devtools/combat_v1_batch_result_snapshot_writer.dart）が、実際にJSON
// fileを書き出せること・fileの内容がpure serializerの出力と一致すること
// を確認する。テスト自体はrepositoryを汚さないよう、一時directoryへ書く。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_simulation_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_simulation_runner.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/devtools/combat_v1_batch_result_snapshot_serializer.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/devtools/combat_v1_batch_result_snapshot_writer.dart';

void main() {
  group('combatV1BatchResultSnapshotFileName', () {
    test('generatedAtから人間可読なfile名を組み立てる', () {
      final name = combatV1BatchResultSnapshotFileName(
        DateTime.utc(2026, 1, 2, 3, 4, 5),
      );
      expect(name, 'combat_v1_batch_result_20260102_030405.json');
    });
  });

  group('writeCombatV1BatchResultSnapshot', () {
    test('指定directoryへJSON fileを書き出し、内容がserializerの出力と一致する', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'combat_v1_batch_snapshot_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      const runner = CombatV1BatchSimulationRunner();
      final config = CombatV1BatchSimulationConfig(
        wrestlerIds: const ['misaki', 'jack'],
        matchesPerMatchup: 1,
        masterSeed: 321,
      );
      final result = runner.run(config);
      final generatedAt = DateTime.utc(2026, 5, 6, 7, 8, 9);

      final file = await writeCombatV1BatchResultSnapshot(
        result,
        outputDirectory: tempDir.path,
        generatedAt: generatedAt,
      );

      expect(await file.exists(), isTrue);
      expect(
        file.path,
        endsWith('combat_v1_batch_result_20260506_070809.json'),
      );

      final written = jsonDecode(await file.readAsString());
      final expected = combatV1BatchResultSnapshotJson(
        result,
        generatedAt: generatedAt,
      );
      expect(jsonEncode(written), jsonEncode(expected));
    });

    test('outputDirectoryが存在しない場合は作成する', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'combat_v1_batch_snapshot_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final nestedDir = '${tempDir.path}/nested/output';

      const runner = CombatV1BatchSimulationRunner();
      final result = runner.run(
        CombatV1BatchSimulationConfig(
          wrestlerIds: const ['misaki', 'jack'],
          matchesPerMatchup: 1,
          masterSeed: 654,
        ),
      );

      final file = await writeCombatV1BatchResultSnapshot(
        result,
        outputDirectory: nestedDir,
        generatedAt: DateTime.utc(2026, 1, 1),
      );

      expect(await file.exists(), isTrue);
      expect(await Directory(nestedDir).exists(), isTrue);
    });
  });
}
