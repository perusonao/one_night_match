// Combat Ver.1 Phase 2: Deck validationの単体テスト
// （docs/combat_rules_v1.md 3・4章、Phase 2テスト項目【Deck】1〜18）。
//
// [validateDeck] を直接呼び出し、UI/Engineから独立した読み取り専用APIとして
// 正しく機能することを検証する。[fixtureDeckSpec] のカード内訳を
// 部分的に組み替えて、様々な（正しい／不正な）デッキを構築する。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';

import 'combat_v1_test_fixtures.dart';

CombatV1DeckDefinition deckFromSpec(
  String wrestlerId,
  List<(String, CombatV1CardCategory, int)> spec,
) => CombatV1DeckDefinition(
  wrestlerId: wrestlerId,
  entries: buildDeckEntries(wrestlerId, spec),
);

void main() {
  group('validateDeck — 正しい30枚デッキ', () {
    test('1. 正しい30枚デッキはvalid', () {
      final result = validateDeck(
        fixtureDeck('w'),
        catalog: fixtureCatalog,
        rules: fixtureRules,
      );
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });
  });

  group('validateDeck — 合計枚数', () {
    test('2. 29枚はinvalid', () {
      final deck = CombatV1DeckDefinition(
        wrestlerId: 'w',
        entries: fixtureDeck('w').entries.take(29).toList(),
      );
      final result = validateDeck(deck, catalog: fixtureCatalog, rules: fixtureRules);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1DeckValidationErrorCode.totalCountMismatch),
      );
    });

    test('3. 31枚はinvalid', () {
      final extra = CombatV1DeckEntry(
        instanceId: 'w_extra_normal',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final deck = CombatV1DeckDefinition(
        wrestlerId: 'w',
        entries: [...fixtureDeck('w').entries, extra],
      );
      final result = validateDeck(deck, catalog: fixtureCatalog, rules: fixtureRules);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1DeckValidationErrorCode.totalCountMismatch),
      );
    });

    test('4. 合計30でもNORMALが18枚でなければinvalid', () {
      final deck = deckFromSpec('w', const [
        ('fx_normal_strike', CombatV1CardCategory.normal, 3),
        ('fx_normal_throw_down', CombatV1CardCategory.normal, 3),
        ('fx_normal_ground', CombatV1CardCategory.normal, 3),
        ('fx_normal_combo_cost', CombatV1CardCategory.normal, 3),
        ('fx_normal_strike_alt', CombatV1CardCategory.normal, 3),
        // NORMALはここまでで15枚（本来18枚必要）。
        ('fx_signature_a', CombatV1CardCategory.signature, 2),
        ('fx_signature_b', CombatV1CardCategory.signature, 2),
        ('fx_finisher_a', CombatV1CardCategory.finisher, 1),
        ('fx_finisher_b', CombatV1CardCategory.finisher, 1),
        ('fx_counter_a', CombatV1CardCategory.counter, 2),
        ('fx_counter_b', CombatV1CardCategory.counter, 2),
        ('fx_counter_c', CombatV1CardCategory.counter, 5),
        // COUNTERを9枚にして合計30に帳尻を合わせる。
      ]);
      expect(deck.size, 30);
      final result = validateDeck(deck, catalog: fixtureCatalog, rules: fixtureRules);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1DeckValidationErrorCode.categoryCountMismatch),
      );
    });
  });

  group('validateDeck — カテゴリ枚数違反', () {
    test('5. SIGNATURE 4枚違反', () {
      final deck = deckFromSpec('w', const [
        ('fx_normal_strike', CombatV1CardCategory.normal, 3),
        ('fx_normal_throw_down', CombatV1CardCategory.normal, 3),
        ('fx_normal_ground', CombatV1CardCategory.normal, 3),
        ('fx_normal_combo_cost', CombatV1CardCategory.normal, 3),
        ('fx_normal_strike_alt', CombatV1CardCategory.normal, 3),
        ('fx_normal_throw_alt', CombatV1CardCategory.normal, 3),
        ('fx_signature_a', CombatV1CardCategory.signature, 2),
        // SIGNATUREはここまでで2枚（本来4枚必要）。
        ('fx_finisher_a', CombatV1CardCategory.finisher, 1),
        ('fx_finisher_b', CombatV1CardCategory.finisher, 1),
        ('fx_counter_a', CombatV1CardCategory.counter, 2),
        ('fx_counter_b', CombatV1CardCategory.counter, 2),
        ('fx_counter_c', CombatV1CardCategory.counter, 2),
        // 合計は28枚なので余った2枚をCOUNTER以外に足すとcounter上限に抵触する
        // ため、ここでは合計不一致とカテゴリ不一致が同時に出ることを許容する。
      ]);
      final result = validateDeck(deck, catalog: fixtureCatalog, rules: fixtureRules);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1DeckValidationErrorCode.categoryCountMismatch),
      );
    });

    test('6. FINISHER 2枚違反', () {
      final deck = deckFromSpec('w', const [
        ('fx_normal_strike', CombatV1CardCategory.normal, 3),
        ('fx_normal_throw_down', CombatV1CardCategory.normal, 3),
        ('fx_normal_ground', CombatV1CardCategory.normal, 3),
        ('fx_normal_combo_cost', CombatV1CardCategory.normal, 3),
        ('fx_normal_strike_alt', CombatV1CardCategory.normal, 3),
        ('fx_normal_throw_alt', CombatV1CardCategory.normal, 3),
        ('fx_signature_a', CombatV1CardCategory.signature, 2),
        ('fx_signature_b', CombatV1CardCategory.signature, 2),
        ('fx_finisher_a', CombatV1CardCategory.finisher, 1),
        // FINISHERはここまでで1枚（本来2枚必要）。
        ('fx_counter_a', CombatV1CardCategory.counter, 2),
        ('fx_counter_b', CombatV1CardCategory.counter, 2),
        ('fx_counter_c', CombatV1CardCategory.counter, 2),
      ]);
      expect(deck.size, 29);
      final result = validateDeck(deck, catalog: fixtureCatalog, rules: fixtureRules);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1DeckValidationErrorCode.categoryCountMismatch),
      );
    });

    test('7. COUNTER 6枚違反', () {
      final deck = deckFromSpec('w', const [
        ('fx_normal_strike', CombatV1CardCategory.normal, 3),
        ('fx_normal_throw_down', CombatV1CardCategory.normal, 3),
        ('fx_normal_ground', CombatV1CardCategory.normal, 3),
        ('fx_normal_combo_cost', CombatV1CardCategory.normal, 3),
        ('fx_normal_strike_alt', CombatV1CardCategory.normal, 3),
        ('fx_normal_throw_alt', CombatV1CardCategory.normal, 3),
        ('fx_signature_a', CombatV1CardCategory.signature, 2),
        ('fx_signature_b', CombatV1CardCategory.signature, 2),
        ('fx_finisher_a', CombatV1CardCategory.finisher, 1),
        ('fx_finisher_b', CombatV1CardCategory.finisher, 1),
        ('fx_counter_a', CombatV1CardCategory.counter, 2),
        ('fx_counter_b', CombatV1CardCategory.counter, 2),
        // COUNTERはここまでで4枚（本来6枚必要）。
      ]);
      expect(deck.size, 28);
      final result = validateDeck(deck, catalog: fixtureCatalog, rules: fixtureRules);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1DeckValidationErrorCode.categoryCountMismatch),
      );
    });
  });

  group('validateDeck — 同名カード枚数上限（NORMAL）', () {
    test('8. NORMAL同名4枚→invalid', () {
      // strikeを4枚、throw_altを2枚にしてNORMAL合計18枚は維持したまま
      // 同名上限（3枚）だけを違反させる。
      final deck = deckFromSpec('w', const [
        ('fx_normal_strike', CombatV1CardCategory.normal, 4),
        ('fx_normal_throw_down', CombatV1CardCategory.normal, 3),
        ('fx_normal_ground', CombatV1CardCategory.normal, 3),
        ('fx_normal_combo_cost', CombatV1CardCategory.normal, 3),
        ('fx_normal_strike_alt', CombatV1CardCategory.normal, 3),
        ('fx_normal_throw_alt', CombatV1CardCategory.normal, 2),
        ('fx_signature_a', CombatV1CardCategory.signature, 2),
        ('fx_signature_b', CombatV1CardCategory.signature, 2),
        ('fx_finisher_a', CombatV1CardCategory.finisher, 1),
        ('fx_finisher_b', CombatV1CardCategory.finisher, 1),
        ('fx_counter_a', CombatV1CardCategory.counter, 2),
        ('fx_counter_b', CombatV1CardCategory.counter, 2),
        ('fx_counter_c', CombatV1CardCategory.counter, 2),
      ]);
      expect(deck.size, 30);
      expect(deck.countOf(CombatV1CardCategory.normal), 18);
      final result = validateDeck(deck, catalog: fixtureCatalog, rules: fixtureRules);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1DeckValidationErrorCode.sameNameLimitExceeded),
      );
      // カテゴリ別枚数自体は規定通りなので、他のエラー種別は出ない。
      expect(
        result.errors.map((e) => e.code),
        isNot(contains(CombatV1DeckValidationErrorCode.categoryCountMismatch)),
      );
    });

    test('9. NORMAL同名3枚→valid', () {
      final result = validateDeck(
        fixtureDeck('w'), // 全NORMALが同名3枚ちょうど
        catalog: fixtureCatalog,
        rules: fixtureRules,
      );
      expect(result.isValid, isTrue);
    });
  });

  group('validateDeck — 同名カード枚数上限（SIGNATURE）', () {
    test('10. SIGNATURE同名3枚→invalid', () {
      final deck = deckFromSpec('w', const [
        ('fx_normal_strike', CombatV1CardCategory.normal, 3),
        ('fx_normal_throw_down', CombatV1CardCategory.normal, 3),
        ('fx_normal_ground', CombatV1CardCategory.normal, 3),
        ('fx_normal_combo_cost', CombatV1CardCategory.normal, 3),
        ('fx_normal_strike_alt', CombatV1CardCategory.normal, 3),
        ('fx_normal_throw_alt', CombatV1CardCategory.normal, 3),
        ('fx_signature_a', CombatV1CardCategory.signature, 3),
        ('fx_signature_b', CombatV1CardCategory.signature, 1),
        ('fx_finisher_a', CombatV1CardCategory.finisher, 1),
        ('fx_finisher_b', CombatV1CardCategory.finisher, 1),
        ('fx_counter_a', CombatV1CardCategory.counter, 2),
        ('fx_counter_b', CombatV1CardCategory.counter, 2),
        ('fx_counter_c', CombatV1CardCategory.counter, 2),
      ]);
      expect(deck.size, 30);
      expect(deck.countOf(CombatV1CardCategory.signature), 4);
      final result = validateDeck(deck, catalog: fixtureCatalog, rules: fixtureRules);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1DeckValidationErrorCode.sameNameLimitExceeded),
      );
    });

    test('11. SIGNATURE同名2枚→valid', () {
      final result = validateDeck(
        fixtureDeck('w'),
        catalog: fixtureCatalog,
        rules: fixtureRules,
      );
      expect(result.isValid, isTrue);
    });
  });

  group('validateDeck — 同名カード枚数上限（FINISHER）', () {
    test('12. FINISHER同名2枚→invalid', () {
      final deck = deckFromSpec('w', const [
        ('fx_normal_strike', CombatV1CardCategory.normal, 3),
        ('fx_normal_throw_down', CombatV1CardCategory.normal, 3),
        ('fx_normal_ground', CombatV1CardCategory.normal, 3),
        ('fx_normal_combo_cost', CombatV1CardCategory.normal, 3),
        ('fx_normal_strike_alt', CombatV1CardCategory.normal, 3),
        ('fx_normal_throw_alt', CombatV1CardCategory.normal, 3),
        ('fx_signature_a', CombatV1CardCategory.signature, 2),
        ('fx_signature_b', CombatV1CardCategory.signature, 2),
        ('fx_finisher_a', CombatV1CardCategory.finisher, 2),
        ('fx_counter_a', CombatV1CardCategory.counter, 2),
        ('fx_counter_b', CombatV1CardCategory.counter, 2),
        ('fx_counter_c', CombatV1CardCategory.counter, 2),
      ]);
      expect(deck.size, 30);
      expect(deck.countOf(CombatV1CardCategory.finisher), 2);
      final result = validateDeck(deck, catalog: fixtureCatalog, rules: fixtureRules);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1DeckValidationErrorCode.sameNameLimitExceeded),
      );
    });

    test('13. FINISHER同名1枚→valid', () {
      final result = validateDeck(
        fixtureDeck('w'),
        catalog: fixtureCatalog,
        rules: fixtureRules,
      );
      expect(result.isValid, isTrue);
    });
  });

  group('validateDeck — 同名カード枚数上限（COUNTER）', () {
    test('14. COUNTER同名3枚→invalid', () {
      final deck = deckFromSpec('w', const [
        ('fx_normal_strike', CombatV1CardCategory.normal, 3),
        ('fx_normal_throw_down', CombatV1CardCategory.normal, 3),
        ('fx_normal_ground', CombatV1CardCategory.normal, 3),
        ('fx_normal_combo_cost', CombatV1CardCategory.normal, 3),
        ('fx_normal_strike_alt', CombatV1CardCategory.normal, 3),
        ('fx_normal_throw_alt', CombatV1CardCategory.normal, 3),
        ('fx_signature_a', CombatV1CardCategory.signature, 2),
        ('fx_signature_b', CombatV1CardCategory.signature, 2),
        ('fx_finisher_a', CombatV1CardCategory.finisher, 1),
        ('fx_finisher_b', CombatV1CardCategory.finisher, 1),
        ('fx_counter_a', CombatV1CardCategory.counter, 3),
        ('fx_counter_b', CombatV1CardCategory.counter, 2),
        ('fx_counter_c', CombatV1CardCategory.counter, 1),
      ]);
      expect(deck.size, 30);
      expect(deck.countOf(CombatV1CardCategory.counter), 6);
      final result = validateDeck(deck, catalog: fixtureCatalog, rules: fixtureRules);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1DeckValidationErrorCode.sameNameLimitExceeded),
      );
    });

    test('15. COUNTER同名2枚→valid', () {
      final result = validateDeck(
        fixtureDeck('w'),
        catalog: fixtureCatalog,
        rules: fixtureRules,
      );
      expect(result.isValid, isTrue);
    });
  });

  group('validateDeck — instanceId / cardId / category整合性', () {
    test('16. instanceId重複→invalid', () {
      final entries = fixtureDeck('w').entries.toList();
      // 2枚目のinstanceIdを1枚目と同じ値に書き換えて重複させる
      // （枚数・カテゴリ内訳・同名枚数はそのまま維持する）。
      entries[1] = CombatV1DeckEntry(
        instanceId: entries[0].instanceId,
        cardId: entries[1].cardId,
        category: entries[1].category,
      );
      final deck = CombatV1DeckDefinition(wrestlerId: 'w', entries: entries);

      final result = validateDeck(deck, catalog: fixtureCatalog, rules: fixtureRules);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1DeckValidationErrorCode.duplicateInstanceId),
      );
    });

    test('17. 存在しないcardIdを参照→invalid', () {
      final entries = fixtureDeck('w').entries.toList();
      entries[0] = CombatV1DeckEntry(
        instanceId: entries[0].instanceId,
        cardId: 'fx_does_not_exist',
        category: entries[0].category,
      );
      final deck = CombatV1DeckDefinition(wrestlerId: 'w', entries: entries);

      final result = validateDeck(deck, catalog: fixtureCatalog, rules: fixtureRules);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1DeckValidationErrorCode.unknownCardId),
      );
    });

    test('18. DeckEntry.categoryとcard definition不一致→invalid', () {
      final entries = fixtureDeck('w').entries.toList();
      // fx_normal_strike（本来category==normal）をDeckEntry上ではsignature
      // と偽って登録する。
      final target = entries.firstWhere((e) => e.cardId == 'fx_normal_strike');
      final index = entries.indexOf(target);
      entries[index] = CombatV1DeckEntry(
        instanceId: target.instanceId,
        cardId: target.cardId,
        category: CombatV1CardCategory.signature,
      );
      final deck = CombatV1DeckDefinition(wrestlerId: 'w', entries: entries);

      final result = validateDeck(deck, catalog: fixtureCatalog, rules: fixtureRules);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1DeckValidationErrorCode.categoryMismatch),
      );
    });

    test('COUNTERカードをNORMALとして誤登録→categoryMismatchでinvalid', () {
      final entries = fixtureDeck('w').entries.toList();
      final target = entries.firstWhere((e) => e.cardId == 'fx_counter_a');
      final index = entries.indexOf(target);
      entries[index] = CombatV1DeckEntry(
        instanceId: target.instanceId,
        cardId: target.cardId,
        category: CombatV1CardCategory.normal,
      );
      final deck = CombatV1DeckDefinition(wrestlerId: 'w', entries: entries);

      final result = validateDeck(deck, catalog: fixtureCatalog, rules: fixtureRules);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1DeckValidationErrorCode.categoryMismatch),
      );
    });
  });

  group('validateDeck — wrestlerId（Phase 10B Codexレビュー指摘対応）', () {
    test('wrestlerId省略（null）時は既存挙動を維持し、有効なデッキはvalidのまま', () {
      final result = validateDeck(
        fixtureDeck('w'),
        catalog: fixtureCatalog,
        rules: fixtureRules,
      );
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('wrestlerIdがdeck.wrestlerIdと一致すればvalid', () {
      final result = validateDeck(
        fixtureDeck('w'),
        catalog: fixtureCatalog,
        rules: fixtureRules,
        wrestlerId: 'w',
      );
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('wrestlerIdがdeck.wrestlerIdと不一致ならwrestlerMismatchでinvalid', () {
      final result = validateDeck(
        fixtureDeck('w'),
        catalog: fixtureCatalog,
        rules: fixtureRules,
        wrestlerId: 'other-wrestler',
      );
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1DeckValidationErrorCode.wrestlerMismatch),
      );
    });

    test('wrestlerMismatchは他の検証項目（枚数・category等）とは独立して報告される', () {
      // 合計枚数も壊れたデッキに対してwrestlerIdも不一致にすると、
      // totalCountMismatchとwrestlerMismatchの両方が報告される。
      final deck = CombatV1DeckDefinition(
        wrestlerId: 'w',
        entries: fixtureDeck('w').entries.take(29).toList(),
      );
      final result = validateDeck(
        deck,
        catalog: fixtureCatalog,
        rules: fixtureRules,
        wrestlerId: 'other-wrestler',
      );
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        containsAll([
          CombatV1DeckValidationErrorCode.totalCountMismatch,
          CombatV1DeckValidationErrorCode.wrestlerMismatch,
        ]),
      );
    });
  });
}
