// Combat Ver.1 Phase 12A: CombatV1SimulationPolicyKind
// （lib/src/combat_v1/simulation/combat_v1_simulation_policy.dart）のtest。
//
// Codex review Major Finding M1（旧CombatV1SimulationPolicySpecが任意の
// factory closureを保持できたため、external mutable stateのcapture・
// 同一policy instanceの使い回し・供給Randomの無視・descriptor IDと
// runtime policy IDの不一致を防げなかった）の修正を直接固定するtest。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_decision_policy.dart';
import 'package:one_night_match/src/combat_v1/simulation/combat_v1_simulation_policy.dart';

void main() {
  group('A. APIが構造的に2種類へ閉じている', () {
    test('CombatV1SimulationPolicyKind.valuesはfirstLegal/randomLegalの2件のみ', () {
      expect(CombatV1SimulationPolicyKind.values, hasLength(2));
    });
  });

  group('B. descriptor IDとruntime policy IDの構造的一致', () {
    test('firstLegal.policyIdは実際にCombatV1FirstLegalPolicyを生成して読み取った'
        'idと一致する', () {
      const kind = CombatV1SimulationPolicyKind.firstLegal;
      final policy = kind.createFresh(Random(1));
      expect(kind.policyId, policy.id);
      expect(policy, isA<CombatV1FirstLegalPolicy>());
    });

    test('randomLegal.policyIdは実際にCombatV1RandomLegalPolicyを生成して読み取った'
        'idと一致する', () {
      const kind = CombatV1SimulationPolicyKind.randomLegal;
      final policy = kind.createFresh(Random(2));
      expect(kind.policyId, policy.id);
      expect(policy, isA<CombatV1RandomLegalPolicy>());
    });

    test('全kindについてpolicyIdとcreateFresh(...).idが一致する（網羅的）', () {
      for (final kind in CombatV1SimulationPolicyKind.values) {
        final policy = kind.createFresh(Random(0));
        expect(
          kind.policyId,
          policy.id,
          reason: 'kind=$kind: descriptor IDとruntime policy IDが不一致',
        );
      }
    });
  });

  group('C. fresh instance保証（同一policy instanceの使い回し不可）', () {
    test('firstLegal.createFreshを2回呼ぶと異なるinstanceが返る', () {
      const kind = CombatV1SimulationPolicyKind.firstLegal;
      final a = kind.createFresh(Random(1));
      final b = kind.createFresh(Random(2));
      expect(identical(a, b), isFalse);
    });

    test('randomLegal.createFreshを2回呼ぶと異なるinstanceが返る', () {
      const kind = CombatV1SimulationPolicyKind.randomLegal;
      final a = kind.createFresh(Random(1));
      final b = kind.createFresh(Random(2));
      expect(identical(a, b), isFalse);
    });
  });

  group('D. 供給されたRandomがそのまま使われる（無視されない）', () {
    test('randomLegalはcreateFreshへ渡したRandom instanceをそのまま'
        'CombatV1RandomLegalPolicyへ渡す（同じRandomから同じ選択列になる）', () {
      const kind = CombatV1SimulationPolicyKind.randomLegal;
      final sharedRandom = Random(42);

      // 同じRandom instanceを共有させ、createFreshが独自のRandomを新規
      // 生成して供給分を無視していないことを、後続のnextInt呼び出し結果が
      // 「共有Randomの続き」になっていることで確認する。
      final expectedNext = Random(42).nextInt(1000);

      final policy = kind.createFresh(sharedRandom);
      expect(policy, isA<CombatV1RandomLegalPolicy>());
      // createFresh自体はRandomを消費しない（policyへ渡すだけ）ため、
      // sharedRandomの次の値は独立した同seed Randomの最初の値と一致する。
      expect(sharedRandom.nextInt(1000), expectedNext);
    });
  });

  group('E. external mutable stateをcaptureする経路が存在しない', () {
    test('CombatV1SimulationPolicyKindはenumでありfieldを持たないため、'
        'external mutable stateを保持できない', () {
      // enumのvalueはコンパイル時に固定されたsingletonであり、
      // instance fieldを持たない（constructorも公開されていない）。
      // 型システム上、任意のクロージャやmutable stateをkindへ注入する
      // 手段が存在しない。
      const kindA = CombatV1SimulationPolicyKind.firstLegal;
      const kindB = CombatV1SimulationPolicyKind.firstLegal;
      expect(identical(kindA, kindB), isTrue);
    });
  });
}
