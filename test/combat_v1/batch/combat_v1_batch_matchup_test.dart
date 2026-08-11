// Combat Ver.1 Phase 12B-1: CombatV1Matchup / CombatV1PolicyPairing /
// combatV1GenerateMatchupMatrix
// （lib/src/combat_v1/simulation/batch/combat_v1_batch_matchup.dart）のtest。
//
// docs/design/combat_v1_phase12b1_batch_core_aggregation.md 6・7章、および
// 35章「TESTS — MATRIX」を検証する。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_matchup.dart';
import 'package:one_night_match/src/combat_v1/simulation/batch/combat_v1_batch_simulation_config.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_policy.dart';

void main() {
  group('CombatV1Matchup', () {
    test('value equality: 同じwrestlerA/Bなら等しい', () {
      const a = CombatV1Matchup(wrestlerAId: 'misaki', wrestlerBId: 'jack');
      const b = CombatV1Matchup(wrestlerAId: 'misaki', wrestlerBId: 'jack');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('A/Bが逆なら別のmatchup（非対称）', () {
      const a = CombatV1Matchup(wrestlerAId: 'misaki', wrestlerBId: 'jack');
      const b = CombatV1Matchup(wrestlerAId: 'jack', wrestlerBId: 'misaki');
      expect(a, isNot(equals(b)));
    });

    test('isMirror: wrestlerAId == wrestlerBIdの場合のみtrue', () {
      const mirror = CombatV1Matchup(
        wrestlerAId: 'misaki',
        wrestlerBId: 'misaki',
      );
      const nonMirror = CombatV1Matchup(
        wrestlerAId: 'misaki',
        wrestlerBId: 'jack',
      );
      expect(mirror.isMirror, isTrue);
      expect(nonMirror.isMirror, isFalse);
    });

    test('Mapのkeyとして使える（value equalityベースのlookup）', () {
      final map = <CombatV1Matchup, int>{
        const CombatV1Matchup(wrestlerAId: 'misaki', wrestlerBId: 'jack'): 1,
      };
      expect(
        map[const CombatV1Matchup(wrestlerAId: 'misaki', wrestlerBId: 'jack')],
        1,
      );
    });
  });

  group('CombatV1PolicyPairing', () {
    test('default（randomVsRandom）はrandomLegal/randomLegal', () {
      expect(
        CombatV1PolicyPairing.randomVsRandom.playerAPolicy,
        CombatV1SimulationPolicyKind.randomLegal,
      );
      expect(
        CombatV1PolicyPairing.randomVsRandom.playerBPolicy,
        CombatV1SimulationPolicyKind.randomLegal,
      );
    });

    test('value equality', () {
      const a = CombatV1PolicyPairing(
        playerAPolicy: CombatV1SimulationPolicyKind.firstLegal,
        playerBPolicy: CombatV1SimulationPolicyKind.randomLegal,
      );
      const b = CombatV1PolicyPairing(
        playerAPolicy: CombatV1SimulationPolicyKind.firstLegal,
        playerBPolicy: CombatV1SimulationPolicyKind.randomLegal,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('4通りの組み合わせすべてが構築できる', () {
      for (final a in CombatV1SimulationPolicyKind.values) {
        for (final b in CombatV1SimulationPolicyKind.values) {
          final pairing = CombatV1PolicyPairing(
            playerAPolicy: a,
            playerBPolicy: b,
          );
          expect(pairing.playerAPolicy, a);
          expect(pairing.playerBPolicy, b);
        }
      }
    });
  });

  group('combatV1GenerateMatchupMatrix', () {
    test('default 4 wrestlersなら16 matchup', () {
      final matrix = combatV1GenerateMatchupMatrix(
        combatV1DefaultBatchWrestlerIds,
      );
      expect(matrix, hasLength(16));
    });

    test('canonical order（misaki/jack/akari/reina）と厳密一致', () {
      final matrix = combatV1GenerateMatchupMatrix(
        combatV1DefaultBatchWrestlerIds,
      );
      const expected = [
        CombatV1Matchup(wrestlerAId: 'misaki', wrestlerBId: 'misaki'),
        CombatV1Matchup(wrestlerAId: 'misaki', wrestlerBId: 'jack'),
        CombatV1Matchup(wrestlerAId: 'misaki', wrestlerBId: 'akari'),
        CombatV1Matchup(wrestlerAId: 'misaki', wrestlerBId: 'reina'),
        CombatV1Matchup(wrestlerAId: 'jack', wrestlerBId: 'misaki'),
        CombatV1Matchup(wrestlerAId: 'jack', wrestlerBId: 'jack'),
        CombatV1Matchup(wrestlerAId: 'jack', wrestlerBId: 'akari'),
        CombatV1Matchup(wrestlerAId: 'jack', wrestlerBId: 'reina'),
        CombatV1Matchup(wrestlerAId: 'akari', wrestlerBId: 'misaki'),
        CombatV1Matchup(wrestlerAId: 'akari', wrestlerBId: 'jack'),
        CombatV1Matchup(wrestlerAId: 'akari', wrestlerBId: 'akari'),
        CombatV1Matchup(wrestlerAId: 'akari', wrestlerBId: 'reina'),
        CombatV1Matchup(wrestlerAId: 'reina', wrestlerBId: 'misaki'),
        CombatV1Matchup(wrestlerAId: 'reina', wrestlerBId: 'jack'),
        CombatV1Matchup(wrestlerAId: 'reina', wrestlerBId: 'akari'),
        CombatV1Matchup(wrestlerAId: 'reina', wrestlerBId: 'reina'),
      ];
      for (var i = 0; i < expected.length; i++) {
        expect(matrix[i], equals(expected[i]), reason: 'index $i');
      }
    });

    test('4 mirrorすべてを含む', () {
      final matrix = combatV1GenerateMatchupMatrix(
        combatV1DefaultBatchWrestlerIds,
      );
      final mirrors = matrix.where((m) => m.isMirror).toList();
      expect(mirrors, hasLength(4));
      expect(
        mirrors.map((m) => m.wrestlerAId).toSet(),
        combatV1DefaultBatchWrestlerIds.toSet(),
      );
    });

    test('A vs BとB vs Aは別要素として両方存在する', () {
      final matrix = combatV1GenerateMatchupMatrix(
        combatV1DefaultBatchWrestlerIds,
      );
      expect(
        matrix,
        contains(
          const CombatV1Matchup(wrestlerAId: 'akari', wrestlerBId: 'reina'),
        ),
      );
      expect(
        matrix,
        contains(
          const CombatV1Matchup(wrestlerAId: 'reina', wrestlerBId: 'akari'),
        ),
      );
    });

    test('戻り値はunmodifiable', () {
      final matrix = combatV1GenerateMatchupMatrix(
        combatV1DefaultBatchWrestlerIds,
      );
      expect(
        () => matrix.add(
          const CombatV1Matchup(wrestlerAId: 'x', wrestlerBId: 'y'),
        ),
        throwsUnsupportedError,
      );
    });

    test('カスタムのwrestlerId順序がmatrixへ反映される', () {
      final matrix = combatV1GenerateMatchupMatrix(['reina', 'misaki']);
      expect(matrix, hasLength(4));
      expect(
        matrix,
        equals(const [
          CombatV1Matchup(wrestlerAId: 'reina', wrestlerBId: 'reina'),
          CombatV1Matchup(wrestlerAId: 'reina', wrestlerBId: 'misaki'),
          CombatV1Matchup(wrestlerAId: 'misaki', wrestlerBId: 'reina'),
          CombatV1Matchup(wrestlerAId: 'misaki', wrestlerBId: 'misaki'),
        ]),
      );
    });

    test('N wrestlerならN×N matchup（3 wrestlerで9件）', () {
      final matrix = combatV1GenerateMatchupMatrix(['misaki', 'jack', 'akari']);
      expect(matrix, hasLength(9));
    });
  });
}
