/// Production Wrestler定義（docs/combat_rules_v1.md 2章・18章、Phase 10A）。
///
/// Phase 10Aでは豪田ミサキのみを対象とする（黒蝶ジャック・火神アカリ・白銀レイナは
/// Phase 10B以降）。ENERGY Poolは`combat_rules_v1.md`18章の検証値を、Phase
/// 10AセッションでユーザーがProduction値として正式承認した値（
/// docs/design/combat_v1_phase10_production_data.md 2.1章参照）。
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
