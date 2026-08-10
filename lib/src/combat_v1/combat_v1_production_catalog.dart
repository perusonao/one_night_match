/// Production Card Catalog横断lookup view（docs/combat_rules_v1.md 23.6章、Phase 10A）。
///
/// `combat_v1_technique_catalog.dart`／`combat_v1_counter_catalog.dart`が持つ個々の
/// Technique/Counter定義を、`CombatV1CardCatalog`（`combat_v1_deck_validation.dart`）として
/// 横断参照できるようにまとめる。UI／CPU／Simulator／Testのいずれからも共通で参照できる
/// Domain構造とし、責務はlookupに留める（本ファイル自身は戦闘resolutionや検証ロジックを
/// 持たない）。
///
/// Phase 10Aで豪田ミサキ、Phase 10Bで黒蝶ジャック、Phase 10Cで火神アカリ・
/// 白銀レイナを追加した（4人構成完成）。
library;

import 'combat_v1_counter_catalog.dart';
import 'combat_v1_deck_validation.dart';
import 'combat_v1_technique_catalog.dart';

/// 現時点のProduction Card Catalog
/// （Phase 10C: 豪田ミサキ＋黒蝶ジャック＋火神アカリ＋白銀レイナ、4人構成）。
final CombatV1CardCatalog productionCardCatalog = CombatV1CardCatalog(
  techniques: {
    ...misakiTechniques,
    ...jackTechniques,
    ...akariTechniques,
    ...reinaTechniques,
  },
  counters: {
    ...misakiCounters,
    ...jackCounters,
    ...akariCounters,
    ...reinaCounters,
  },
);
