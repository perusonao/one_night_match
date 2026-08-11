// Combat Ver.1 Phase 12B-1 — Development Batch Result Snapshot script.
//
// 開発・検証用のBatch Simulationを1回実行し、集計結果
// （CombatV1BatchSimulationResult、aggregate-only）を
// build/combat_v1_simulation/ 配下へJSON snapshotとして書き出す。
//
// これは正式なCSV/JSON Export機能・Dashboard・CIツールではない——
// 「Phase 12B-1で実際にどのような結果が出たかを人間が確認・共有できる」
// ための開発時ツール。実行方法:
//
//   dart run tool/combat_v1_batch_result_snapshot.dart
//
// 実行するbatchのdefault設定（16 matchup × 100 matches = 1,600 matches、
// RandomLegal vs RandomLegal、masterSeed固定・maxActions 500・default
// rules）は、必要ならこのファイル内の定数を変更して調整できる。

import 'dart:io';

import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_simulation_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_simulation_result.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_simulation_runner.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/devtools/combat_v1_batch_result_snapshot_writer.dart';

const int _matchesPerMatchup = 100;
const int _masterSeed = 12345;
const int _maxActions = 500;

Future<void> main() async {
  final config = CombatV1BatchSimulationConfig(
    matchesPerMatchup: _matchesPerMatchup,
    masterSeed: _masterSeed,
    maxActions: _maxActions,
  );

  stdout.writeln(
    'Combat V1 batch simulation: '
    '${config.wrestlerIds.length}x${config.wrestlerIds.length} matrix, '
    '${config.matchesPerMatchup} matches/matchup, masterSeed=$_masterSeed …',
  );

  const runner = CombatV1BatchSimulationRunner();
  final stopwatch = Stopwatch()..start();
  final result = runner.run(config);
  stopwatch.stop();

  stdout.writeln(
    'Executed ${result.executedMatchCount} matches in '
    '${stopwatch.elapsedMilliseconds}ms.',
  );

  final generatedAt = DateTime.now();
  final file = await writeCombatV1BatchResultSnapshot(
    result,
    generatedAt: generatedAt,
  );

  stdout.writeln('Snapshot written to: ${file.path}');
  _printSummary(result);
}

void _printSummary(CombatV1BatchSimulationResult result) {
  final global = result.global;
  String rate(double? r) => r == null ? 'null' : (r * 100).toStringAsFixed(1);

  stdout
    ..writeln('')
    ..writeln('--- Global ---')
    ..writeln('totalMatches: ${global.totalMatches}')
    ..writeln(
      'completedMatches: ${global.completedMatches} '
      '(${rate(global.completionRate)}%)',
    )
    ..writeln(
      'safetyLimitMatches: ${global.safetyLimitMatches} '
      '(${rate(global.safetyLimitRate)}%)',
    )
    ..writeln(
      'invariantViolationMatches: ${global.invariantViolationMatches} '
      '(${rate(global.invariantViolationRate)}%)',
    )
    ..writeln(
      'playerAWins: ${global.playerAWins} '
      '(${rate(global.playerAWinRateCompletedMatches)}%), '
      'playerBWins: ${global.playerBWins} '
      '(${rate(global.playerBWinRateCompletedMatches)}%)',
    )
    ..writeln('')
    ..writeln('--- Wrestlers ---');

  for (final wrestler in result.wrestlers) {
    stdout.writeln(
      '${wrestler.wrestlerId}: wins ${wrestler.wins}/'
      '${wrestler.completedAppearances} (${rate(wrestler.winRateCompletedMatches)}%)',
    );
  }

  stdout
    ..writeln('')
    ..writeln('--- Seat ---')
    ..writeln(
      'playerA: ${result.seat.playerAWins}/'
      '${result.seat.playerACompletedMatches} '
      '(${rate(result.seat.playerAWinRateCompletedMatches)}%)',
    )
    ..writeln(
      'playerB: ${result.seat.playerBWins}/'
      '${result.seat.playerBCompletedMatches} '
      '(${rate(result.seat.playerBWinRateCompletedMatches)}%)',
    )
    ..writeln('')
    ..writeln('--- Mirror ---')
    ..writeln(
      'totalMatches: ${result.mirror.totalMatches}, '
      'playerAWinRate: ${rate(result.mirror.playerAWinRateCompletedMatches)}%, '
      'deviationFrom50%: ${result.mirror.absoluteDeviationFromFiftyPercent}',
    )
    ..writeln('')
    ..writeln('--- Match Length (completed, Phase 12B-2A) ---');

  final length = result.statistics.global.length;
  stdout
    ..writeln(
      'actionCount: sampleCount=${length.actionCount.sampleCount} '
      'mean=${length.actionCount.mean} median=${length.actionCount.median} '
      'p90=${length.actionCount.p90} p95=${length.actionCount.p95} '
      'min=${length.actionCount.min} max=${length.actionCount.max}',
    )
    ..writeln(
      'finalTurnNumber: sampleCount=${length.finalTurnNumber.sampleCount} '
      'mean=${length.finalTurnNumber.mean} '
      'median=${length.finalTurnNumber.median} '
      'p90=${length.finalTurnNumber.p90} p95=${length.finalTurnNumber.p95} '
      'min=${length.finalTurnNumber.min} max=${length.finalTurnNumber.max}',
    );
}
