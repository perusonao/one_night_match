// Combat Ver.1 Phase 12B-1 — Development Result Snapshot Serializerの test。
//
// combatV1BatchResultSnapshotJson（lib/src/combat_v1/simulation/batch/
// devtools/combat_v1_batch_result_snapshot_serializer.dart）を、完成済みの
// CombatV1BatchSimulationResultのみから検証する。個別
// CombatV1MatchSimulationResultへ直接アクセスすることはない——serializer
// 自身がBatchResult以外を入力に取らないことの直接確認でもある。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_simulation_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_simulation_result.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_simulation_runner.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/devtools/combat_v1_batch_result_snapshot_serializer.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_policy.dart';

const _runner = CombatV1BatchSimulationRunner();
final _generatedAt = DateTime.utc(2026, 1, 2, 3, 4, 5);

CombatV1BatchSimulationResult _run({
  List<String> wrestlerIds = combatV1DefaultBatchWrestlerIds,
  int matchesPerMatchup = 1,
  int masterSeed = 777,
  int maxActions = 500,
}) => _runner.run(
  CombatV1BatchSimulationConfig(
    wrestlerIds: wrestlerIds,
    matchesPerMatchup: matchesPerMatchup,
    masterSeed: masterSeed,
    maxActions: maxActions,
  ),
);

void main() {
  group('combatV1BatchResultSnapshotJson — schema', () {
    late CombatV1BatchSimulationResult result;
    late Map<String, Object?> json;

    setUpAll(() {
      result = _run(matchesPerMatchup: 1, masterSeed: 2024);
      json = combatV1BatchResultSnapshotJson(result, generatedAt: _generatedAt);
    });

    test('metadata fields一式', () {
      final metadata = json['metadata']! as Map<String, Object?>;
      expect(metadata['generatedAt'], _generatedAt.toIso8601String());
      expect(metadata['game'], 'one_night_match');
      expect(metadata['simulator'], 'combat_v1_batch_simulation');
      expect(metadata['phase'], '12B-1');
      expect(metadata['masterSeed'], 2024);
      expect(metadata['matchesPerMatchup'], 1);
      expect(metadata['requestedMatchCount'], result.requestedMatchCount);
      expect(metadata['executedMatchCount'], result.executedMatchCount);
      expect(metadata['maxActions'], 500);
      expect(metadata['wrestlerIds'], ['misaki', 'jack', 'akari', 'reina']);
      expect(
        metadata['playerAPolicy'],
        CombatV1SimulationPolicyKind.randomLegal.name,
      );
      expect(
        metadata['playerBPolicy'],
        CombatV1SimulationPolicyKind.randomLegal.name,
      );
      expect(metadata['rules'], isA<Map<String, Object?>>());
    });

    test('rules: 全outcome-affecting fieldsを含む（deckComposition展開含む）', () {
      final metadata = json['metadata']! as Map<String, Object?>;
      final rules = metadata['rules']! as Map<String, Object?>;
      const expectedKeys = [
        'startingHp',
        'startingKoc',
        'startingPinCards',
        'startingHandSize',
        'deckComposition',
        'normalSameNameLimit',
        'signatureSameNameLimit',
        'finisherSameNameLimit',
        'counterSameNameLimit',
        'counterAllowsWildSubstitution',
        'totalPinCards',
        'pinCountOneKocCost',
        'pinCountTwoKocCost',
        'pinCountTwoPointNineKocCost',
        'submissionHpThreshold',
        'submissionEscapeKocCost',
        'restHpRecovery',
        'roughRestrictedTechniqueLimit',
        'finisherHeatThreshold',
      ];
      for (final key in expectedKeys) {
        expect(rules.containsKey(key), isTrue, reason: 'rules.$key');
      }
      final deckComposition = rules['deckComposition']! as Map<String, Object?>;
      expect(deckComposition.keys.toSet(), {
        'normalCount',
        'signatureCount',
        'finisherCount',
        'counterCount',
      });
      expect(rules['startingHp'], 150);
      expect(deckComposition['normalCount'], 18);
    });

    test('global fields一式', () {
      final global = json['global']! as Map<String, Object?>;
      const expectedKeys = [
        'totalMatches',
        'completedMatches',
        'safetyLimitMatches',
        'invariantViolationMatches',
        'completionRate',
        'safetyLimitRate',
        'invariantViolationRate',
        'playerAWins',
        'playerBWins',
        'playerAWinRateCompletedMatches',
        'playerBWinRateCompletedMatches',
        'terminalCauses',
      ];
      for (final key in expectedKeys) {
        expect(global.containsKey(key), isTrue, reason: 'global.$key');
      }
      expect(global['totalMatches'], result.global.totalMatches);
      final terminalCauses = global['terminalCauses']! as Map<String, Object?>;
      expect(terminalCauses.keys.toSet(), {
        'normalPin',
        'directPin',
        'submission',
        'submissionFinisher',
        'other',
      });
    });

    test('orderedMatchups: 16件・canonical order・A vs B/B vs A別・mirror含む', () {
      final matchups = json['orderedMatchups']! as List<Object?>;
      expect(matchups, hasLength(16));

      final first = matchups.first as Map<String, Object?>;
      expect(first['wrestlerAId'], 'misaki');
      expect(first['wrestlerBId'], 'misaki'); // canonical順の先頭はmirror

      const expectedKeys = [
        'wrestlerAId',
        'wrestlerBId',
        'totalMatches',
        'completedMatches',
        'safetyLimitMatches',
        'invariantViolationMatches',
        'playerAWins',
        'playerBWins',
        'playerAWinRateCompletedMatches',
        'playerBWinRateCompletedMatches',
        'terminalCauseCounts',
      ];
      for (final key in expectedKeys) {
        expect(first.containsKey(key), isTrue, reason: 'matchup.$key');
      }

      final pairs = matchups
          .cast<Map<String, Object?>>()
          .map((m) => '${m['wrestlerAId']}-${m['wrestlerBId']}')
          .toSet();
      expect(pairs, contains('akari-reina'));
      expect(pairs, contains('reina-akari'));
    });

    test('wrestlers fields一式（seat別内訳含む）', () {
      final wrestlers = json['wrestlers']! as List<Object?>;
      expect(wrestlers, hasLength(4));

      final first = wrestlers.first as Map<String, Object?>;
      const expectedKeys = [
        'wrestlerId',
        'appearances',
        'completedAppearances',
        'wins',
        'winRateCompletedMatches',
        'playerASeat',
        'playerBSeat',
      ];
      for (final key in expectedKeys) {
        expect(first.containsKey(key), isTrue, reason: 'wrestler.$key');
      }
      final seatA = first['playerASeat']! as Map<String, Object?>;
      expect(seatA.keys.toSet(), {
        'appearances',
        'completedAppearances',
        'wins',
        'winRateCompletedMatches',
      });
    });

    test('seat fields一式（currentRuleInterpretation注釈含む）', () {
      final seat = json['seat']! as Map<String, Object?>;
      const expectedKeys = [
        'playerACompletedMatches',
        'playerBCompletedMatches',
        'playerAWins',
        'playerBWins',
        'playerAWinRateCompletedMatches',
        'playerBWinRateCompletedMatches',
        'currentRuleInterpretation',
      ];
      for (final key in expectedKeys) {
        expect(seat.containsKey(key), isTrue, reason: 'seat.$key');
      }
      expect(seat['currentRuleInterpretation'], 'Player A starts first');
    });

    test('mirror fields一式', () {
      final mirror = json['mirror']! as Map<String, Object?>;
      const expectedKeys = [
        'totalMatches',
        'completedMatches',
        'safetyLimitMatches',
        'invariantViolationMatches',
        'playerAWins',
        'playerBWins',
        'playerAWinRateCompletedMatches',
        'absoluteDeviationFromFiftyPercent',
        'safetyLimitRate',
      ];
      for (final key in expectedKeys) {
        expect(mirror.containsKey(key), isTrue, reason: 'mirror.$key');
      }
    });

    test('jsonEncodeでそのままJSON文字列化できる', () {
      expect(() => jsonEncode(json), returnsNormally);
    });
  });

  group('combatV1BatchResultSnapshotJson — null semantics', () {
    test(
      'completed denominatorが0（safetyLimitのみ）ならrateはJSON nullになる（0.0にしない）',
      () {
        final result = _run(
          wrestlerIds: const ['misaki', 'jack'],
          matchesPerMatchup: 1,
          maxActions: 1, // 強制的にsafetyLimitのみにする
        );
        final json = combatV1BatchResultSnapshotJson(
          result,
          generatedAt: _generatedAt,
        );

        final global = json['global']! as Map<String, Object?>;
        expect(global['completedMatches'], 0);
        expect(global['playerAWinRateCompletedMatches'], isNull);
        expect(global['playerBWinRateCompletedMatches'], isNull);

        final matchups = (json['orderedMatchups']! as List<Object?>)
            .cast<Map<String, Object?>>();
        for (final matchup in matchups) {
          expect(matchup['playerAWinRateCompletedMatches'], isNull);
          expect(matchup['playerBWinRateCompletedMatches'], isNull);
        }

        final wrestlers = (json['wrestlers']! as List<Object?>)
            .cast<Map<String, Object?>>();
        for (final wrestler in wrestlers) {
          expect(wrestler['winRateCompletedMatches'], isNull);
        }

        // JSON文字列化してもnullのまま（0.0へ変換されない）。
        final encoded = jsonEncode(json);
        final decoded = jsonDecode(encoded) as Map<String, Object?>;
        final decodedGlobal = decoded['global']! as Map<String, Object?>;
        expect(decodedGlobal['playerAWinRateCompletedMatches'], isNull);
      },
    );
  });

  group('combatV1BatchResultSnapshotJson — deterministic content', () {
    test('同一BatchResultなら、generatedAtを除いて同一のJSON Mapになる', () {
      final result = _run(matchesPerMatchup: 3, masterSeed: 555);
      final jsonA = combatV1BatchResultSnapshotJson(
        result,
        generatedAt: DateTime.utc(2026, 1, 1),
      );
      final jsonB = combatV1BatchResultSnapshotJson(
        result,
        generatedAt: DateTime.utc(2030, 12, 31),
      );

      final metadataA = Map<String, Object?>.from(
        jsonA['metadata']! as Map<String, Object?>,
      )..remove('generatedAt');
      final metadataB = Map<String, Object?>.from(
        jsonB['metadata']! as Map<String, Object?>,
      )..remove('generatedAt');

      expect(jsonEncode(metadataA), jsonEncode(metadataB));
      expect(jsonEncode(jsonA['global']), jsonEncode(jsonB['global']));
      expect(
        jsonEncode(jsonA['orderedMatchups']),
        jsonEncode(jsonB['orderedMatchups']),
      );
      expect(jsonEncode(jsonA['wrestlers']), jsonEncode(jsonB['wrestlers']));
      expect(jsonEncode(jsonA['seat']), jsonEncode(jsonB['seat']));
      expect(jsonEncode(jsonA['mirror']), jsonEncode(jsonB['mirror']));
    });

    test('同一config・masterSeedで2回runしても同一snapshot内容になる', () {
      final resultA = _run(matchesPerMatchup: 2, masterSeed: 9090);
      final resultB = _run(matchesPerMatchup: 2, masterSeed: 9090);

      final jsonA = combatV1BatchResultSnapshotJson(
        resultA,
        generatedAt: _generatedAt,
      );
      final jsonB = combatV1BatchResultSnapshotJson(
        resultB,
        generatedAt: _generatedAt,
      );

      expect(jsonEncode(jsonA), jsonEncode(jsonB));
    });
  });
}
