import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_defaults.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_deck.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_model_decks.dart';

void main() {
  final catalog = buildProvisionalTechniqueDeckCatalog();
  const validator = TechniqueDeckValidator();

  group('buildAkariPhase6ModelDeck', () {
    test('30枚になる', () {
      final deck = buildAkariPhase6ModelDeck();
      expect(deck.entries.length, 30);
    });

    test('wrestler_akariのデッキとして検証を通過する', () {
      final deck = buildAkariPhase6ModelDeck();
      final result = validator.validate(deck, catalog);
      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((e) => e.message).join('\n'),
      );
    });

    test('内訳がユーザー指定の構成と一致する', () {
      final deck = buildAkariPhase6ModelDeck();
      final counts = <String, int>{};
      for (final e in deck.entries) {
        counts[e.cardId] = (counts[e.cardId] ?? 0) + 1;
      }
      expect(counts['td_energy_strike'], 7);
      expect(counts['td_energy_throwMove'], 4);
      expect(counts['td_energy_counter'], 2);
      expect(counts['td_normal_strike_1'], 3);
      expect(counts['td_normal_throw_1'], 3);
      expect(counts['td_normal_counter_1'], 3);
      expect(counts['td_p6_akari_sig_kneestrike'], 1);
      expect(counts['td_p6_akari_sig_german'], 1);
      expect(counts['td_p6_akari_sig_suplex'], 1);
      expect(counts['td_p6_akari_sig_lariat'], 1);
      expect(counts['td_p6_akari_sig_finalkick'], 1);
      expect(counts['td_p6_akari_fall_extra'], 1);
      expect(counts['td_kickout_normal_1'], 1);
      expect(counts['td_ropebreak_1'], 1);
    });
  });

  group('buildReinaPhase6ModelDeck', () {
    test('30枚になる', () {
      final deck = buildReinaPhase6ModelDeck();
      expect(deck.entries.length, 30);
    });

    test('wrestler_reinaのデッキとして検証を通過する', () {
      final deck = buildReinaPhase6ModelDeck();
      final result = validator.validate(deck, catalog);
      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((e) => e.message).join('\n'),
      );
    });

    test('内訳がユーザー指定の構成と一致する', () {
      final deck = buildReinaPhase6ModelDeck();
      final counts = <String, int>{};
      for (final e in deck.entries) {
        counts[e.cardId] = (counts[e.cardId] ?? 0) + 1;
      }
      expect(counts['td_energy_submission'], 7);
      expect(counts['td_energy_throwMove'], 3);
      expect(counts['td_energy_counter'], 3);
      expect(counts['td_normal_submission_1'], 3);
      expect(counts['td_p6_normal_takedown'], 3);
      expect(counts['td_normal_counter_1'], 3);
      expect(counts['td_p6_reina_sig_kneebar'], 1);
      expect(counts['td_p6_reina_sig_brainbuster'], 1);
      expect(counts['td_p6_reina_sig_camel'], 1);
      expect(counts['td_p6_reina_sig_figurefour'], 1);
      expect(counts['td_p6_reina_sig_crossface'], 1);
      expect(counts['td_p6_reina_giveup_extra'], 1);
      expect(counts['td_kickout_normal_1'], 1);
      expect(counts['td_ropebreak_1'], 1);
    });
  });
}
