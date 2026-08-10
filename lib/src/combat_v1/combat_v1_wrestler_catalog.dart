/// Production Wrestler定義（docs/combat_rules_v1.md 2章・18章、Phase 10A/10B/10C）。
///
/// Phase 10Aで豪田ミサキ、Phase 10Bで黒蝶ジャック、Phase 10Cで火神アカリ・
/// 白銀レイナを追加した。ENERGY Poolは`combat_rules_v1.md`18章の検証値を、
/// 各Phaseセッションでユーザーが確認のうえProduction値として正式承認した値（
/// docs/design/combat_v1_phase10_production_data.md 2.1章・Phase 10B/10C節参照）。
library;

import 'combat_v1_energy.dart';
import 'combat_v1_enums.dart';
import 'combat_v1_wrestler.dart';

/// 豪田ミサキ（Production Wrestler、docs/design/combat_v1_phase10_production_data.md 2章）。
const CombatV1Wrestler misakiWrestler = CombatV1Wrestler(
  id: 'misaki',
  name: '豪田ミサキ',
  energyPool: CombatV1EnergyPool({
    CombatV1EnergyAttribute.strike: 3,
    CombatV1EnergyAttribute.joint: 0,
    CombatV1EnergyAttribute.throwing: 4,
    CombatV1EnergyAttribute.aerial: 0,
    CombatV1EnergyAttribute.rough: 1,
    CombatV1EnergyAttribute.wild: 1,
  }),
);

/// 黒蝶ジャック（Production Wrestler、docs/design/combat_v1_phase10_production_data.md
/// Phase 10B節）。ENERGY Poolは`combat_rules_v1.md`18章の検証値をそのまま採用した。
const CombatV1Wrestler jackWrestler = CombatV1Wrestler(
  id: 'jack',
  name: '黒蝶ジャック',
  energyPool: CombatV1EnergyPool({
    CombatV1EnergyAttribute.strike: 3,
    CombatV1EnergyAttribute.joint: 1,
    CombatV1EnergyAttribute.throwing: 1,
    CombatV1EnergyAttribute.aerial: 0,
    CombatV1EnergyAttribute.rough: 4,
    CombatV1EnergyAttribute.wild: 1,
  }),
);

/// 火神アカリ（Production Wrestler、Phase 10C Production Data Final
/// Specification 1章）。ENERGY Poolは`combat_rules_v1.md`18章の検証値をそのまま
/// 採用した。
const CombatV1Wrestler akariWrestler = CombatV1Wrestler(
  id: 'akari',
  name: '火神アカリ',
  energyPool: CombatV1EnergyPool({
    CombatV1EnergyAttribute.strike: 5,
    CombatV1EnergyAttribute.joint: 1,
    CombatV1EnergyAttribute.throwing: 2,
    CombatV1EnergyAttribute.aerial: 2,
    CombatV1EnergyAttribute.rough: 0,
    CombatV1EnergyAttribute.wild: 1,
  }),
);

/// 白銀レイナ（Production Wrestler、Phase 10C Production Data Final
/// Specification 5章）。ENERGY Poolは`combat_rules_v1.md`18章の検証値をそのまま
/// 採用した。
const CombatV1Wrestler reinaWrestler = CombatV1Wrestler(
  id: 'reina',
  name: '白銀レイナ',
  energyPool: CombatV1EnergyPool({
    CombatV1EnergyAttribute.strike: 2,
    CombatV1EnergyAttribute.joint: 4,
    CombatV1EnergyAttribute.throwing: 3,
    CombatV1EnergyAttribute.aerial: 0,
    CombatV1EnergyAttribute.rough: 0,
    CombatV1EnergyAttribute.wild: 1,
  }),
);
