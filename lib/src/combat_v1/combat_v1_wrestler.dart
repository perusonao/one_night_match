/// レスラー静的プロフィール（docs/combat_rules_v1.md 2章・18章）。
library;

import 'combat_v1_energy.dart';

/// レスラーの静的プロフィール。
///
/// Phase 1ではHPはレスラー間で差を設けない（`CombatV1RulesConfig.startingHp`
/// が全レスラー共通の初期値となる、docs/combat_rules_v1.md 2・14章）ため、
/// このモデルにはHPを持たせない。
class CombatV1Wrestler {
  const CombatV1Wrestler({
    required this.id,
    required this.name,
    required this.energyPool,
  });

  final String id;
  final String name;

  /// このレスラー固有の固定ENERGYプール（docs/combat_rules_v1.md 18章）。
  final CombatV1EnergyPool energyPool;
}
