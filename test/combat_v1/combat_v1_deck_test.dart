// Combat Ver.1 Phase 1: デッキ構成の単体テスト（docs/combat_rules_v1.md 3章）。
//
// 山札再構築（山札切れ時の捨て札シャッフル）はEngineの内部処理
// （CombatV1Engine._drawOne、非公開）を通じてのみ発生するため、
// combat_v1_engine_test.dart側でCommand APIを駆動して検証する。
// このファイルは静的なデッキ構成の検証のみを対象とする。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';

import 'combat_v1_test_fixtures.dart';

void main() {
  group('CombatV1DeckDefinition / CombatV1DeckComposition', () {
    test('フィクスチャデッキは30枚である', () {
      final deck = fixtureDeck('fx_wrestler_a');
      expect(deck.size, 30);
    });

    test('フィクスチャデッキの内訳はNORMAL18/SIGNATURE4/FINISHER2/COUNTER6である', () {
      final deck = fixtureDeck('fx_wrestler_a');
      expect(deck.countOf(CombatV1CardCategory.normal), 18);
      expect(deck.countOf(CombatV1CardCategory.signature), 4);
      expect(deck.countOf(CombatV1CardCategory.finisher), 2);
      expect(deck.countOf(CombatV1CardCategory.counter), 6);
    });

    test('既定のCombatV1DeckCompositionはNORMAL18/SIGNATURE4/FINISHER2/COUNTER6/合計30である', () {
      const composition = CombatV1DeckComposition();
      expect(composition.normalCount, 18);
      expect(composition.signatureCount, 4);
      expect(composition.finisherCount, 2);
      expect(composition.counterCount, 6);
      expect(composition.total, 30);
    });

    test('フィクスチャデッキは既定のデッキ構成に一致する', () {
      const composition = CombatV1DeckComposition();
      final deck = fixtureDeck('fx_wrestler_a');
      expect(composition.matches(deck), isTrue);
    });

    test('カテゴリ内訳が既定構成と異なるデッキは一致しない', () {
      const composition = CombatV1DeckComposition();
      final deck = fixtureDeck('fx_wrestler_a');
      final tooManyNormal = CombatV1DeckDefinition(
        wrestlerId: deck.wrestlerId,
        entries: [
          ...deck.entries,
          const CombatV1DeckEntry(
            instanceId: 'extra_normal',
            cardId: 'fx_normal_strike',
            category: CombatV1CardCategory.normal,
          ),
        ],
      );
      expect(composition.matches(tooManyNormal), isFalse);
    });

    test('枚数が30枚に満たないデッキは一致しない', () {
      const composition = CombatV1DeckComposition();
      final deck = fixtureDeck('fx_wrestler_a');
      final shortDeck = CombatV1DeckDefinition(
        wrestlerId: deck.wrestlerId,
        entries: deck.entries.take(29).toList(),
      );
      expect(composition.matches(shortDeck), isFalse);
    });
  });
}
