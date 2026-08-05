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

  // ============================================================
  // Technique Deck Rules Phase 7A（レスラーカード・技カード・モデルデッキ
  // 実装）: エスケープ・リバーサルを含まない30枚構成（技エネルギー13・
  // 通常技8・固有技4・フィニッシャー2・通常キックアウト1・ロープブレイク1・
  // 特殊キックアウト1）。
  // ============================================================

  group('buildAkariPhase7AModelDeck', () {
    test('30枚になる', () {
      final deck = buildAkariPhase7AModelDeck();
      expect(deck.entries.length, 30);
    });

    test('wrestler_akariのデッキとして検証を通過する（警告もなし）', () {
      final deck = buildAkariPhase7AModelDeck();
      final result = validator.validate(deck, catalog);
      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((e) => e.message).join('\n'),
      );
      expect(
        result.warnings,
        isEmpty,
        reason: result.warnings.map((e) => e.message).join('\n'),
      );
    });

    test('内訳がPhase 7A構成（エスケープ・リバーサル無し）と一致する', () {
      final deck = buildAkariPhase7AModelDeck();
      final counts = <String, int>{};
      for (final e in deck.entries) {
        counts[e.cardId] = (counts[e.cardId] ?? 0) + 1;
      }
      expect(counts['td_energy_strike'], 6);
      expect(counts['td_energy_throwMove'], 4);
      expect(counts['td_energy_aerial'], 3);
      for (final id in [
        'td_p7a_akari_normal_elbow',
        'td_p7a_akari_normal_middlekick',
        'td_p7a_akari_normal_dropkick',
        'td_p7a_akari_normal_runningknee',
        'td_p7a_akari_normal_armwhip',
        'td_p7a_akari_normal_crossbody',
        'td_p7a_akari_normal_swingddt',
        'td_p7a_akari_normal_forearm',
      ]) {
        expect(counts[id], 1, reason: id);
      }
      expect(counts['td_p7a_akari_sig_phoenixarmdrag'], 1);
      expect(counts['td_p7a_akari_sig_soulhighkick'], 1);
      expect(counts['td_p6_akari_sig_kneestrike'], 1);
      expect(counts['td_p6_akari_sig_german'], 1);
      expect(counts['td_p7a_akari_fin_phoenixsplash'], 1);
      expect(counts['td_p7a_akari_fin_redflarekick'], 1);
      expect(counts['td_kickout_normal_1'], 1);
      expect(counts['td_ropebreak_1'], 1);
      expect(counts['td_kickout_special_1'], 1);
      expect(counts.containsKey('td_escape_1'), isFalse);
      expect(counts.containsKey('td_reversal_1'), isFalse);
    });
  });

  group('buildMisakiPhase7AModelDeck', () {
    test('30枚になる', () {
      final deck = buildMisakiPhase7AModelDeck();
      expect(deck.entries.length, 30);
    });

    test('wrestler_misakiのデッキとして検証を通過する（警告もなし）', () {
      final deck = buildMisakiPhase7AModelDeck();
      final result = validator.validate(deck, catalog);
      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((e) => e.message).join('\n'),
      );
      expect(
        result.warnings,
        isEmpty,
        reason: result.warnings.map((e) => e.message).join('\n'),
      );
    });

    test('内訳がPhase 7A構成（エスケープ・リバーサル無し）と一致する', () {
      final deck = buildMisakiPhase7AModelDeck();
      final counts = <String, int>{};
      for (final e in deck.entries) {
        counts[e.cardId] = (counts[e.cardId] ?? 0) + 1;
      }
      expect(counts['td_energy_throwMove'], 9);
      expect(counts['td_energy_strike'], 4);
      for (final id in [
        'td_p7a_misaki_normal_bodyslam',
        'td_p7a_misaki_normal_shouldertackle',
        'td_p7a_misaki_normal_lariat',
        'td_p7a_misaki_normal_backdrop',
        'td_p7a_misaki_normal_brainbuster',
        'td_p7a_misaki_normal_powerslam',
        'td_p7a_misaki_normal_kneelift',
        'td_p7a_misaki_normal_spinebuster',
      ]) {
        expect(counts[id], 1, reason: id);
      }
      expect(counts['td_p7a_misaki_sig_powerbomb'], 1);
      expect(counts['td_p7a_misaki_sig_giantslam'], 1);
      expect(counts['td_p6_misaki_sig_elbow'], 1);
      expect(counts['td_p6_misaki_sig_bodyslam'], 1);
      expect(counts['td_p7a_misaki_fin_goudadriver'], 1);
      expect(counts['td_p7a_misaki_fin_lastpowerbomb'], 1);
      expect(counts['td_kickout_normal_1'], 1);
      expect(counts['td_ropebreak_1'], 1);
      expect(counts['td_kickout_special_1'], 1);
      expect(counts.containsKey('td_escape_1'), isFalse);
      expect(counts.containsKey('td_reversal_1'), isFalse);
    });
  });

  group('buildReinaPhase7AModelDeck', () {
    test('30枚になる', () {
      final deck = buildReinaPhase7AModelDeck();
      expect(deck.entries.length, 30);
    });

    test('wrestler_reinaのデッキとして検証を通過する（警告もなし）', () {
      final deck = buildReinaPhase7AModelDeck();
      final result = validator.validate(deck, catalog);
      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((e) => e.message).join('\n'),
      );
      expect(
        result.warnings,
        isEmpty,
        reason: result.warnings.map((e) => e.message).join('\n'),
      );
    });

    test('内訳がPhase 7A構成（エスケープ・リバーサル無し）と一致する', () {
      final deck = buildReinaPhase7AModelDeck();
      final counts = <String, int>{};
      for (final e in deck.entries) {
        counts[e.cardId] = (counts[e.cardId] ?? 0) + 1;
      }
      expect(counts['td_energy_submission'], 9);
      expect(counts['td_energy_throwMove'], 3);
      expect(counts['td_energy_strike'], 1);
      for (final id in [
        'td_p7a_reina_normal_elbow',
        'td_p7a_reina_normal_dragonscrew',
        'td_p7a_reina_normal_armbreaker',
        'td_p7a_reina_normal_headlock',
        'td_p7a_reina_normal_droptoehold',
        'td_p7a_reina_normal_udehishigi',
        'td_p7a_reina_normal_figurefour',
        'td_p7a_reina_normal_sideheadlock',
      ]) {
        expect(counts[id], 1, reason: id);
      }
      expect(counts['td_p7a_reina_sig_crossface'], 1);
      expect(counts['td_p7a_reina_sig_figurefour_lock'], 1);
      expect(counts['td_p6_reina_sig_kneebar'], 1);
      expect(counts['td_p6_reina_sig_brainbuster'], 1);
      expect(counts['td_p7a_reina_fin_icelock'], 1);
      expect(counts['td_p7a_reina_fin_eternalcross'], 1);
      expect(counts['td_kickout_normal_1'], 1);
      expect(counts['td_ropebreak_1'], 1);
      expect(counts['td_kickout_special_1'], 1);
      expect(counts.containsKey('td_escape_1'), isFalse);
      expect(counts.containsKey('td_reversal_1'), isFalse);
    });
  });

  group('buildJackPhase7AModelDeck', () {
    test('30枚になる', () {
      final deck = buildJackPhase7AModelDeck();
      expect(deck.entries.length, 30);
    });

    test('wrestler_jackのデッキとして検証を通過する（警告もなし）', () {
      final deck = buildJackPhase7AModelDeck();
      final result = validator.validate(deck, catalog);
      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((e) => e.message).join('\n'),
      );
      expect(
        result.warnings,
        isEmpty,
        reason: result.warnings.map((e) => e.message).join('\n'),
      );
    });

    test('内訳がPhase 7A構成（エスケープ・リバーサル無し）と一致する', () {
      final deck = buildJackPhase7AModelDeck();
      final counts = <String, int>{};
      for (final e in deck.entries) {
        counts[e.cardId] = (counts[e.cardId] ?? 0) + 1;
      }
      expect(counts['td_energy_rough'], 5);
      expect(counts['td_energy_submission'], 5);
      expect(counts['td_energy_throwMove'], 2);
      expect(counts['td_energy_strike'], 1);
      for (final id in [
        'td_p7a_jack_normal_lowblow',
        'td_p7a_jack_normal_weapon',
        'td_p7a_jack_normal_ddt',
        'td_p7a_jack_normal_choke',
        'td_p7a_jack_normal_ironclaw',
        'td_p7a_jack_normal_neckhanging',
        'td_p7a_jack_normal_facestomp',
        'td_p7a_jack_normal_elbow',
      ]) {
        expect(counts[id], 1, reason: id);
      }
      expect(counts['td_p7a_jack_sig_blackddt'], 1);
      expect(counts['td_p7a_jack_sig_darkneck'], 1);
      expect(counts['td_p6_jack_sig_lowblow'], 1);
      expect(counts['td_p6_jack_sig_neckbreaker'], 1);
      expect(counts['td_p7a_jack_fin_blackbutterfly'], 1);
      expect(counts['td_p7a_jack_fin_darkend'], 1);
      expect(counts['td_kickout_normal_1'], 1);
      expect(counts['td_ropebreak_1'], 1);
      expect(counts['td_kickout_special_1'], 1);
      expect(counts.containsKey('td_escape_1'), isFalse);
      expect(counts.containsKey('td_reversal_1'), isFalse);
    });
  });

  group('techniquePhase7AModelDeckBuilders / findTechniquePhase7AModelDeck', () {
    test('4人分すべてのレスラーIDが登録されている', () {
      expect(
        techniquePhase7AModelDeckBuilders.keys.toSet(),
        {'wrestler_akari', 'wrestler_misaki', 'wrestler_reina', 'wrestler_jack'},
      );
    });

    test('未登録のレスラーIDはnullを返す', () {
      expect(findTechniquePhase7AModelDeck('wrestler_unknown'), isNull);
    });

    test('登録済みのレスラーIDは対応するモデルデッキを返す', () {
      final deck = findTechniquePhase7AModelDeck('wrestler_akari');
      expect(deck, isNotNull);
      expect(deck!.wrestlerId, 'wrestler_akari');
      expect(deck.entries.length, 30);
    });
  });
}
