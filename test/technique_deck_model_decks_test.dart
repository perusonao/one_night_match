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

  group('buildMisakiPhase6ModelDeck', () {
    test('30枚になる', () {
      final deck = buildMisakiPhase6ModelDeck();
      expect(deck.entries.length, 30);
    });

    test('wrestler_misakiのデッキとして検証を通過する', () {
      final deck = buildMisakiPhase6ModelDeck();
      final result = validator.validate(deck, catalog);
      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((e) => e.message).join('\n'),
      );
    });

    test('内訳がユーザー指定の構成と一致する', () {
      final deck = buildMisakiPhase6ModelDeck();
      final counts = <String, int>{};
      for (final e in deck.entries) {
        counts[e.cardId] = (counts[e.cardId] ?? 0) + 1;
      }
      expect(counts['td_energy_throwMove'], 7);
      expect(counts['td_energy_strike'], 4);
      expect(counts['td_energy_counter'], 2);
      expect(counts['td_normal_throw_1'], 3);
      expect(counts['td_normal_strike_1'], 3);
      expect(counts['td_normal_counter_1'], 3);
      expect(counts['td_p6_misaki_sig_elbow'], 1);
      expect(counts['td_p6_misaki_sig_bodyslam'], 1);
      expect(counts['td_p6_misaki_sig_backdrop'], 1);
      expect(counts['td_p6_misaki_sig_lariat'], 1);
      expect(counts['td_p6_misaki_sig_powerbomb'], 1);
      expect(counts['td_p6_misaki_fall_extra'], 1);
      expect(counts['td_kickout_normal_1'], 1);
      expect(counts['td_ropebreak_1'], 1);
    });
  });

  group('buildJackPhase6ModelDeck', () {
    test('30枚になる', () {
      final deck = buildJackPhase6ModelDeck();
      expect(deck.entries.length, 30);
    });

    test('wrestler_jackのデッキとして検証を通過する', () {
      final deck = buildJackPhase6ModelDeck();
      final result = validator.validate(deck, catalog);
      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((e) => e.message).join('\n'),
      );
    });

    test('内訳がユーザー指定の構成と一致する', () {
      final deck = buildJackPhase6ModelDeck();
      final counts = <String, int>{};
      for (final e in deck.entries) {
        counts[e.cardId] = (counts[e.cardId] ?? 0) + 1;
      }
      expect(counts['td_energy_submission'], 7);
      expect(counts['td_energy_rough'], 4);
      expect(counts['td_energy_counter'], 2);
      expect(counts['td_normal_submission_1'], 3);
      expect(counts['td_normal_rough_1'], 3);
      expect(counts['td_normal_counter_1'], 3);
      expect(counts['td_p6_jack_sig_lowblow'], 1);
      expect(counts['td_p6_jack_sig_neckbreaker'], 1);
      expect(counts['td_p6_jack_sig_clutch'], 1);
      expect(counts['td_p6_jack_sig_chair'], 1);
      expect(counts['td_p6_jack_sig_deathlock'], 1);
      expect(counts['td_p6_jack_giveup_extra'], 1);
      expect(counts['td_kickout_normal_1'], 1);
      expect(counts['td_ropebreak_1'], 1);
    });
  });

  group('buildAkariPhase7ModelDeck', () {
    test('30枚になる', () {
      final deck = buildAkariPhase7ModelDeck();
      expect(deck.entries.length, 30);
    });

    test('wrestler_akariのデッキとして検証を通過する', () {
      final deck = buildAkariPhase7ModelDeck();
      final result = validator.validate(deck, catalog);
      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((e) => e.message).join('\n'),
      );
    });

    test('内訳がPhase 7構成と一致する', () {
      final deck = buildAkariPhase7ModelDeck();
      final counts = <String, int>{};
      for (final e in deck.entries) {
        counts[e.cardId] = (counts[e.cardId] ?? 0) + 1;
      }
      expect(counts['td_energy_strike'], 7);
      expect(counts['td_energy_throwMove'], 4);
      expect(counts['td_energy_counter'], 2);
      expect(counts['td_normal_strike_1'], 2);
      expect(counts['td_normal_throw_1'], 2);
      expect(counts['td_normal_counter_1'], 2);
      expect(counts['td_p6_akari_sig_kneestrike'], 1);
      expect(counts['td_p6_akari_sig_german'], 1);
      expect(counts['td_p6_akari_sig_suplex'], 1);
      expect(counts['td_p7_akari_fin_burningdrive'], 1);
      expect(counts['td_p7_akari_fin_phoenixdriver'], 1);
      expect(counts['td_p7_akari_fin_finalflame'], 1);
      expect(counts['td_kickout_normal_1'], 1);
      expect(counts['td_ropebreak_1'], 1);
      expect(counts['td_kickout_special_1'], 1);
      expect(counts['td_escape_1'], 1);
      expect(counts['td_reversal_1'], 1);
    });
  });

  group('buildReinaPhase7ModelDeck', () {
    test('30枚になる', () {
      final deck = buildReinaPhase7ModelDeck();
      expect(deck.entries.length, 30);
    });

    test('wrestler_reinaのデッキとして検証を通過する', () {
      final deck = buildReinaPhase7ModelDeck();
      final result = validator.validate(deck, catalog);
      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((e) => e.message).join('\n'),
      );
    });

    test('内訳がPhase 7構成と一致する', () {
      final deck = buildReinaPhase7ModelDeck();
      final counts = <String, int>{};
      for (final e in deck.entries) {
        counts[e.cardId] = (counts[e.cardId] ?? 0) + 1;
      }
      expect(counts['td_energy_submission'], 7);
      expect(counts['td_energy_throwMove'], 3);
      expect(counts['td_energy_counter'], 3);
      expect(counts['td_normal_submission_1'], 2);
      expect(counts['td_p6_normal_takedown'], 2);
      expect(counts['td_normal_counter_1'], 2);
      expect(counts['td_p6_reina_sig_kneebar'], 1);
      expect(counts['td_p6_reina_sig_brainbuster'], 1);
      expect(counts['td_p6_reina_sig_camel'], 1);
      expect(counts['td_p7_reina_fin_silverwing'], 1);
      expect(counts['td_p7_reina_fin_armbar_ex'], 1);
      expect(counts['td_p7_reina_fin_absolute'], 1);
      expect(counts['td_kickout_normal_1'], 1);
      expect(counts['td_ropebreak_1'], 1);
      expect(counts['td_kickout_special_1'], 1);
      expect(counts['td_escape_1'], 1);
      expect(counts['td_reversal_1'], 1);
    });
  });

  group('buildMisakiPhase7ModelDeck', () {
    test('30枚になる', () {
      final deck = buildMisakiPhase7ModelDeck();
      expect(deck.entries.length, 30);
    });

    test('wrestler_misakiのデッキとして検証を通過する', () {
      final deck = buildMisakiPhase7ModelDeck();
      final result = validator.validate(deck, catalog);
      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((e) => e.message).join('\n'),
      );
    });

    test('内訳がPhase 7構成と一致する', () {
      final deck = buildMisakiPhase7ModelDeck();
      final counts = <String, int>{};
      for (final e in deck.entries) {
        counts[e.cardId] = (counts[e.cardId] ?? 0) + 1;
      }
      expect(counts['td_energy_throwMove'], 7);
      expect(counts['td_energy_strike'], 4);
      expect(counts['td_energy_counter'], 2);
      expect(counts['td_normal_throw_1'], 2);
      expect(counts['td_normal_strike_1'], 2);
      expect(counts['td_normal_counter_1'], 2);
      expect(counts['td_p6_misaki_sig_elbow'], 1);
      expect(counts['td_p6_misaki_sig_bodyslam'], 1);
      expect(counts['td_p6_misaki_sig_backdrop'], 1);
      expect(counts['td_p7_misaki_fin_ironpress'], 1);
      expect(counts['td_p7_misaki_fin_gouda'], 1);
      expect(counts['td_p7_misaki_fin_ultimate'], 1);
      expect(counts['td_kickout_normal_1'], 1);
      expect(counts['td_ropebreak_1'], 1);
      expect(counts['td_kickout_special_1'], 1);
      expect(counts['td_escape_1'], 1);
      expect(counts['td_reversal_1'], 1);
    });
  });

  group('buildJackPhase7ModelDeck', () {
    test('30枚になる', () {
      final deck = buildJackPhase7ModelDeck();
      expect(deck.entries.length, 30);
    });

    test('wrestler_jackのデッキとして検証を通過する', () {
      final deck = buildJackPhase7ModelDeck();
      final result = validator.validate(deck, catalog);
      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((e) => e.message).join('\n'),
      );
    });

    test('内訳がPhase 7構成と一致する', () {
      final deck = buildJackPhase7ModelDeck();
      final counts = <String, int>{};
      for (final e in deck.entries) {
        counts[e.cardId] = (counts[e.cardId] ?? 0) + 1;
      }
      expect(counts['td_energy_submission'], 7);
      expect(counts['td_energy_rough'], 4);
      expect(counts['td_energy_counter'], 2);
      expect(counts['td_normal_submission_1'], 2);
      expect(counts['td_normal_rough_1'], 2);
      expect(counts['td_normal_counter_1'], 2);
      expect(counts['td_p6_jack_sig_lowblow'], 1);
      expect(counts['td_p6_jack_sig_neckbreaker'], 1);
      expect(counts['td_p6_jack_sig_clutch'], 1);
      expect(counts['td_p7_jack_fin_blackbutterfly'], 1);
      expect(counts['td_p7_jack_fin_darkfall'], 1);
      expect(counts['td_p7_jack_fin_judgment'], 1);
      expect(counts['td_kickout_normal_1'], 1);
      expect(counts['td_ropebreak_1'], 1);
      expect(counts['td_kickout_special_1'], 1);
      expect(counts['td_escape_1'], 1);
      expect(counts['td_reversal_1'], 1);
    });
  });

  group('buildAkariPhase75ModelDeck', () {
    test('30枚になる', () {
      final deck = buildAkariPhase75ModelDeck();
      expect(deck.entries.length, 30);
    });

    test('wrestler_akariのデッキとして検証を通過する', () {
      final deck = buildAkariPhase75ModelDeck();
      final result = validator.validate(deck, catalog);
      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((e) => e.message).join('\n'),
      );
    });

    test('内訳がPhase 7.5構成と一致する', () {
      final deck = buildAkariPhase75ModelDeck();
      final counts = <String, int>{};
      for (final e in deck.entries) {
        counts[e.cardId] = (counts[e.cardId] ?? 0) + 1;
      }
      expect(counts['td_energy_strike'], 7);
      expect(counts['td_energy_throwMove'], 4);
      expect(counts['td_energy_counter'], 2);
      expect(counts['td_normal_strike_1'], 3);
      expect(counts['td_normal_throw_1'], 3);
      expect(counts['td_normal_counter_1'], 2);
      expect(counts['td_p6_akari_sig_kneestrike'], 1);
      expect(counts['td_p6_akari_sig_german'], 1);
      expect(counts['td_p7_akari_fin_burningdrive'], 1);
      expect(counts['td_p7_akari_fin_phoenixdriver'], 1);
      expect(counts.containsKey('td_p7_akari_fin_finalflame'), isFalse);
      expect(counts['td_kickout_normal_1'], 1);
      expect(counts['td_ropebreak_1'], 1);
      expect(counts['td_kickout_special_1'], 1);
      expect(counts['td_escape_1'], 1);
      expect(counts['td_reversal_1'], 1);
    });
  });

  group('buildReinaPhase75ModelDeck', () {
    test('30枚になる', () {
      final deck = buildReinaPhase75ModelDeck();
      expect(deck.entries.length, 30);
    });

    test('wrestler_reinaのデッキとして検証を通過する', () {
      final deck = buildReinaPhase75ModelDeck();
      final result = validator.validate(deck, catalog);
      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((e) => e.message).join('\n'),
      );
    });

    test('内訳がPhase 7.5構成と一致する', () {
      final deck = buildReinaPhase75ModelDeck();
      final counts = <String, int>{};
      for (final e in deck.entries) {
        counts[e.cardId] = (counts[e.cardId] ?? 0) + 1;
      }
      expect(counts['td_energy_submission'], 7);
      expect(counts['td_energy_throwMove'], 3);
      expect(counts['td_energy_counter'], 3);
      expect(counts['td_normal_submission_1'], 3);
      expect(counts['td_p6_normal_takedown'], 3);
      expect(counts['td_normal_counter_1'], 2);
      expect(counts['td_p6_reina_sig_kneebar'], 1);
      expect(counts['td_p6_reina_sig_brainbuster'], 1);
      expect(counts['td_p7_reina_fin_silverwing'], 1);
      expect(counts['td_p7_reina_fin_armbar_ex'], 1);
      expect(counts.containsKey('td_p7_reina_fin_absolute'), isFalse);
      expect(counts['td_kickout_normal_1'], 1);
      expect(counts['td_ropebreak_1'], 1);
      expect(counts['td_kickout_special_1'], 1);
      expect(counts['td_escape_1'], 1);
      expect(counts['td_reversal_1'], 1);
    });
  });

  group('buildMisakiPhase75ModelDeck', () {
    test('30枚になる', () {
      final deck = buildMisakiPhase75ModelDeck();
      expect(deck.entries.length, 30);
    });

    test('wrestler_misakiのデッキとして検証を通過する', () {
      final deck = buildMisakiPhase75ModelDeck();
      final result = validator.validate(deck, catalog);
      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((e) => e.message).join('\n'),
      );
    });

    test('内訳がPhase 7.5構成と一致する', () {
      final deck = buildMisakiPhase75ModelDeck();
      final counts = <String, int>{};
      for (final e in deck.entries) {
        counts[e.cardId] = (counts[e.cardId] ?? 0) + 1;
      }
      expect(counts['td_energy_throwMove'], 7);
      expect(counts['td_energy_strike'], 4);
      expect(counts['td_energy_counter'], 2);
      expect(counts['td_normal_throw_1'], 3);
      expect(counts['td_normal_strike_1'], 3);
      expect(counts['td_normal_counter_1'], 2);
      expect(counts['td_p6_misaki_sig_elbow'], 1);
      expect(counts['td_p6_misaki_sig_bodyslam'], 1);
      expect(counts['td_p7_misaki_fin_ironpress'], 1);
      expect(counts['td_p7_misaki_fin_gouda'], 1);
      expect(counts.containsKey('td_p7_misaki_fin_ultimate'), isFalse);
      expect(counts['td_kickout_normal_1'], 1);
      expect(counts['td_ropebreak_1'], 1);
      expect(counts['td_kickout_special_1'], 1);
      expect(counts['td_escape_1'], 1);
      expect(counts['td_reversal_1'], 1);
    });
  });

  group('buildJackPhase75ModelDeck', () {
    test('30枚になる', () {
      final deck = buildJackPhase75ModelDeck();
      expect(deck.entries.length, 30);
    });

    test('wrestler_jackのデッキとして検証を通過する', () {
      final deck = buildJackPhase75ModelDeck();
      final result = validator.validate(deck, catalog);
      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((e) => e.message).join('\n'),
      );
    });

    test('内訳がPhase 7.5構成と一致する', () {
      final deck = buildJackPhase75ModelDeck();
      final counts = <String, int>{};
      for (final e in deck.entries) {
        counts[e.cardId] = (counts[e.cardId] ?? 0) + 1;
      }
      expect(counts['td_energy_submission'], 7);
      expect(counts['td_energy_rough'], 4);
      expect(counts['td_energy_counter'], 2);
      expect(counts['td_normal_submission_1'], 3);
      expect(counts['td_normal_rough_1'], 3);
      expect(counts['td_normal_counter_1'], 2);
      expect(counts['td_p6_jack_sig_lowblow'], 1);
      expect(counts['td_p6_jack_sig_neckbreaker'], 1);
      expect(counts['td_p7_jack_fin_blackbutterfly'], 1);
      expect(counts['td_p7_jack_fin_darkfall'], 1);
      expect(counts.containsKey('td_p7_jack_fin_judgment'), isFalse);
      expect(counts['td_kickout_normal_1'], 1);
      expect(counts['td_ropebreak_1'], 1);
      expect(counts['td_kickout_special_1'], 1);
      expect(counts['td_escape_1'], 1);
      expect(counts['td_reversal_1'], 1);
    });
  });
}
