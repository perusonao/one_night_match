/// Match State不変条件の検証（Phase 3、docs/combat_rules_v1.md 5章）。
///
/// [CombatV1EnergyPool]/[CombatV1EnergyCost]/[CombatV1Technique]の静的データ
/// validation（`isValid`/`isStaticDataValid`）とは別に、試合が進行した後の
/// `CombatV1PlayerState`スナップショットが不変条件を満たしているかを検証する
/// 読み取り専用ヘルパー。
///
/// immutableモデルのコンストラクタに重いruntime validationを持たせる方針は
/// 取らない（`combat_v1_energy.dart`のコンストラクタコメント参照）。この
/// ファイルの関数は、CPU/Simulator/テストなど必要な箇所からオプトインで
/// 呼び出す想定で、Engine本体のCommand APIには自動配線しない。
library;

import 'combat_v1_enums.dart';
import 'combat_v1_match_state.dart';

/// [validatePlayerStateInvariants]のエラー種別。
enum CombatV1PlayerStateInvariantErrorCode {
  /// spentEnergy（今サイクルの使用済みENERGY）が、対応する属性の
  /// energyPool（保有ENERGY）を超えている。
  spentExceedsPool,

  /// spentEnergyの値が負数（Phase 4、Phase 3 Codexレビュー指摘「10-1」）。
  /// defenderが自ターン外にCOUNTER ENERGYを消費するようになるため、
  /// spentEnergyの不正な負値を検出できることがPhase 4以降より重要になる。
  negativeSpentEnergy,

  /// [CombatV1PlayerState.energyPool]自体が[CombatV1EnergyPool.isValid]
  /// でない（負数のENERGY量を含む、Phase 4、Phase 3 Codexレビュー指摘
  /// 「10-1」）。
  invalidEnergyPool,
}

/// [validatePlayerStateInvariants]の1件のエラー。
class CombatV1PlayerStateInvariantError {
  const CombatV1PlayerStateInvariantError({
    required this.code,
    required this.message,
  });

  final CombatV1PlayerStateInvariantErrorCode code;

  /// 人間可読な説明（ログ・簡易UI用）。
  final String message;

  @override
  String toString() => message;
}

/// [validatePlayerStateInvariants]の結果。
class CombatV1PlayerStateInvariantResult {
  const CombatV1PlayerStateInvariantResult(this.errors);

  final List<CombatV1PlayerStateInvariantError> errors;

  bool get isValid => errors.isEmpty;
}

/// [player]の`spentEnergy`/`energyPool`が不変条件を満たしているか検証する
/// （docs/combat_rules_v1.md 5章、Phase 4でnegativeSpentEnergy/
/// invalidEnergyPoolを追加）。
CombatV1PlayerStateInvariantResult validatePlayerStateInvariants(
  CombatV1PlayerState player,
) {
  final errors = <CombatV1PlayerStateInvariantError>[];

  if (!player.energyPool.isValid) {
    errors.add(
      CombatV1PlayerStateInvariantError(
        code: CombatV1PlayerStateInvariantErrorCode.invalidEnergyPool,
        message: '${player.wrestlerName}のenergyPoolに負数のENERGY量が'
            '含まれています',
      ),
    );
  }

  for (final attribute in CombatV1EnergyAttribute.values) {
    final spent = player.spentEnergy[attribute] ?? 0;

    if (spent < 0) {
      errors.add(
        CombatV1PlayerStateInvariantError(
          code: CombatV1PlayerStateInvariantErrorCode.negativeSpentEnergy,
          message:
              '${player.wrestlerName}の${attribute.displayLabel}ENERGYの'
              'spentEnergyが負数です（spent:$spent）',
        ),
      );
      continue;
    }

    final pool = player.energyPool.amountFor(attribute);
    if (spent > pool) {
      errors.add(
        CombatV1PlayerStateInvariantError(
          code: CombatV1PlayerStateInvariantErrorCode.spentExceedsPool,
          message:
              '${player.wrestlerName}の${attribute.displayLabel}ENERGYが'
              'Poolを超えて使用されています（spent:$spent, pool:$pool）',
        ),
      );
    }
  }

  return CombatV1PlayerStateInvariantResult(errors);
}
