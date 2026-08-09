// Combat Ver.1 Phase 1: ENERGY支払いロジックの単体テスト
// （docs/combat_rules_v1.md 5・5.1章）。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';

void main() {
  group('resolveEnergyPayment', () {
    test('具体属性ENERGYのみで足りる場合は支払い成立する', () {
      const pool = CombatV1EnergyPool({
        CombatV1EnergyAttribute.strike: 3,
      });
      const cost = CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2});

      final result = resolveEnergyPayment(
        pool: pool,
        spent: const {},
        cost: cost,
        allowWildSubstitution: true,
      );

      expect(result.isSuccess, isTrue);
      expect(result.updatedSpent![CombatV1EnergyAttribute.strike], 2);
      expect(result.updatedSpent!.containsKey(CombatV1EnergyAttribute.wild), isFalse);
    });

    test('ENERGYが不足していれば使用不可（ワイルドも無い場合）', () {
      const pool = CombatV1EnergyPool({CombatV1EnergyAttribute.strike: 1});
      const cost = CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2});

      final result = resolveEnergyPayment(
        pool: pool,
        spent: const {},
        cost: cost,
        allowWildSubstitution: true,
      );

      expect(result.isSuccess, isFalse);
      expect(result.failureReason, isNotNull);
    });

    test('単一属性の不足分をワイルド(＊)で補完できる', () {
      // 残り 打1 / ＊2、COST 打2 → 不足1を＊で補い成立。
      const pool = CombatV1EnergyPool({
        CombatV1EnergyAttribute.strike: 1,
        CombatV1EnergyAttribute.wild: 2,
      });
      const cost = CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2});

      final result = resolveEnergyPayment(
        pool: pool,
        spent: const {},
        cost: cost,
        allowWildSubstitution: true,
      );

      expect(result.isSuccess, isTrue);
      expect(result.updatedSpent![CombatV1EnergyAttribute.strike], 1);
      expect(result.updatedSpent![CombatV1EnergyAttribute.wild], 1);
    });

    test('複数属性の不足分を合算してワイルド(＊)で補完できる（docs/combat_rules_v1.md 5.1章の例）', () {
      // 残り 打1 / 投0 / ＊2、COST 打2 / 投1 → 不足合計2を＊2で補い成立。
      const pool = CombatV1EnergyPool({
        CombatV1EnergyAttribute.strike: 1,
        CombatV1EnergyAttribute.throwing: 0,
        CombatV1EnergyAttribute.wild: 2,
      });
      const cost = CombatV1EnergyCost({
        CombatV1EnergyAttribute.strike: 2,
        CombatV1EnergyAttribute.throwing: 1,
      });

      final result = resolveEnergyPayment(
        pool: pool,
        spent: const {},
        cost: cost,
        allowWildSubstitution: true,
      );

      expect(result.isSuccess, isTrue);
      expect(result.updatedSpent![CombatV1EnergyAttribute.strike], 1);
      expect(result.updatedSpent![CombatV1EnergyAttribute.throwing], 0);
      expect(result.updatedSpent![CombatV1EnergyAttribute.wild], 2);
    });

    test('合算不足分がワイルド残量を上回れば使用不可', () {
      const pool = CombatV1EnergyPool({
        CombatV1EnergyAttribute.strike: 0,
        CombatV1EnergyAttribute.throwing: 0,
        CombatV1EnergyAttribute.wild: 1,
      });
      const cost = CombatV1EnergyCost({
        CombatV1EnergyAttribute.strike: 2,
        CombatV1EnergyAttribute.throwing: 1,
      });

      final result = resolveEnergyPayment(
        pool: pool,
        spent: const {},
        cost: cost,
        allowWildSubstitution: true,
      );

      expect(result.isSuccess, isFalse);
    });

    test('allowWildSubstitution=falseの場合はワイルドで補完できない'
        '（Phase 4でCOUNTER用ポリシーとして利用予定）', () {
      const pool = CombatV1EnergyPool({
        CombatV1EnergyAttribute.strike: 1,
        CombatV1EnergyAttribute.wild: 5,
      });
      const cost = CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2});

      final result = resolveEnergyPayment(
        pool: pool,
        spent: const {},
        cost: cost,
        allowWildSubstitution: false,
      );

      expect(result.isSuccess, isFalse);
    });

    test('既に使用済みのENERGYは残量計算から差し引かれる', () {
      const pool = CombatV1EnergyPool({CombatV1EnergyAttribute.strike: 3});
      const cost = CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2});

      final result = resolveEnergyPayment(
        pool: pool,
        spent: const {CombatV1EnergyAttribute.strike: 2},
        cost: cost,
        allowWildSubstitution: true,
      );

      // 残り1しかないため、COST2は支払えない。
      expect(result.isSuccess, isFalse);
    });
  });

  group('CombatV1EnergyPool / CombatV1EnergyCost', () {
    test('amountForは未定義の属性に対して0を返す', () {
      const pool = CombatV1EnergyPool({CombatV1EnergyAttribute.strike: 3});
      expect(pool.amountFor(CombatV1EnergyAttribute.aerial), 0);

      const cost = CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1});
      expect(cost.amountFor(CombatV1EnergyAttribute.aerial), 0);
    });
  });
}
