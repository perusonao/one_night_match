/// Production 30枚Deck定義（docs/combat_rules_v1.md 3・21章、Phase 10A）。
///
/// Phase 10Aでは豪田ミサキの正式30枚デッキのみを対象とする（黒蝶ジャック・火神アカリ・
/// 白銀レイナは今回実装しない）。配分は`combat_rules_v1.md`21章の方針
/// （基本NORMAL×3・その他NORMAL×2、SIGNATURE各×2、FINISHER各×1、COUNTER各×2）を
/// そのまま正式採用した（docs/design/combat_v1_phase10_production_data.md 5章）。
library;

import 'combat_v1_deck.dart';
import 'combat_v1_enums.dart';
import 'combat_v1_wrestler_catalog.dart';

/// [wrestlerId]・[spec]（cardId／category／枚数）から物理カード
/// （[CombatV1DeckEntry]）のリストを組み立てる。instanceIdは
/// `<wrestlerId>_<cardId>_#<連番>`で一意にする。
List<CombatV1DeckEntry> _buildEntries(
  String wrestlerId,
  List<(String cardId, CombatV1CardCategory category, int count)> spec,
) {
  final entries = <CombatV1DeckEntry>[];
  var seq = 0;
  for (final (cardId, category, count) in spec) {
    for (var i = 0; i < count; i++) {
      entries.add(
        CombatV1DeckEntry(
          instanceId: '${wrestlerId}_${cardId}_#${seq++}',
          cardId: cardId,
          category: category,
        ),
      );
    }
  }
  return entries;
}

/// 豪田ミサキ Production Deck 30枚の内訳
/// （NORMAL18・SIGNATURE4・FINISHER2・COUNTER6、
/// docs/design/combat_v1_phase10_production_data.md 5章）。
const List<(String, CombatV1CardCategory, int)> misakiDeckSpec = [
  // NORMAL 18枚: 基本技（逆水平チョップ・ボディスラム）×3、その他×2。
  ('misaki_reverse_chop', CombatV1CardCategory.normal, 3),
  ('misaki_body_slam', CombatV1CardCategory.normal, 3),
  ('misaki_shoulder_tackle', CombatV1CardCategory.normal, 2),
  ('misaki_brainbuster', CombatV1CardCategory.normal, 2),
  ('misaki_backdrop', CombatV1CardCategory.normal, 2),
  ('misaki_power_slam', CombatV1CardCategory.normal, 2),
  ('misaki_lariat', CombatV1CardCategory.normal, 2),
  ('misaki_guillotine_drop', CombatV1CardCategory.normal, 2),

  // SIGNATURE 4枚: 2種×2枚。
  ('misaki_mighty_backdrop', CombatV1CardCategory.signature, 2),
  ('misaki_strong_arm_lariat', CombatV1CardCategory.signature, 2),

  // FINISHER 2枚: 2種×1枚。
  ('misaki_goda_bomb', CombatV1CardCategory.finisher, 1),
  ('misaki_goda_driver', CombatV1CardCategory.finisher, 1),

  // COUNTER 6枚: 3種×2枚。
  ('counter_strike_guard', CombatV1CardCategory.counter, 2),
  ('counter_suplex_reversal', CombatV1CardCategory.counter, 2),
  ('counter_powerbomb_escape', CombatV1CardCategory.counter, 2),
];

/// 豪田ミサキ Production Deck（30枚）。
CombatV1DeckDefinition buildMisakiDeck() => CombatV1DeckDefinition(
  wrestlerId: misakiWrestler.id,
  entries: _buildEntries(misakiWrestler.id, misakiDeckSpec),
);
