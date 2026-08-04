import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_deck.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_models.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart' show MoveAttribute;

void main() {
  group('TechniqueDeckEntry', () {
    test('JSON往復', () {
      const entry = TechniqueDeckEntry(
        instanceId: 'e1',
        cardId: 'card_normal_1',
        cardType: TechniqueDeckCardType.technique,
      );
      final round = TechniqueDeckEntry.fromJson(entry.toJson());
      expect(round, entry);
    });

    test('未知のcardTypeはtechniqueへ安全にフォールバックする', () {
      final entry = TechniqueDeckEntry.fromJson(const {
        'instanceId': 'e1',
        'cardId': 'x',
        'cardType': 'not_a_real_type',
      });
      expect(entry.cardType, TechniqueDeckCardType.technique);
    });
  });

  group('TechniqueDeckDefinition', () {
    test('JSON往復', () {
      final deck = TechniqueDeckDefinition(
        id: 'deck_1',
        wrestlerId: 'wrestler_akari',
        name: 'テストデッキ',
        entries: const [
          TechniqueDeckEntry(
            instanceId: 'e1',
            cardId: 'c1',
            cardType: TechniqueDeckCardType.technique,
          ),
          TechniqueDeckEntry(
            instanceId: 'e2',
            cardId: 'c2',
            cardType: TechniqueDeckCardType.energy,
          ),
        ],
      );
      final round = TechniqueDeckDefinition.fromJson(deck.toJson());
      expect(round, deck);
      expect(round.cardCount, 2);
    });

    test('欠落フィールドは既定値で補完される', () {
      final deck = TechniqueDeckDefinition.fromJson(const {'id': 'd1'});
      expect(deck.id, 'd1');
      expect(deck.wrestlerId, '');
      expect(deck.name, '');
      expect(deck.entries, isEmpty);
    });
  });

  group('TechniqueDeckBuilder', () {
    test('addCardでインスタンスIDが自動採番される', () {
      final deck = TechniqueDeckBuilder(wrestlerId: 'w1', id: 'd1')
          .addCard('normal_1', TechniqueDeckCardType.technique, count: 3)
          .build();
      expect(deck.entries.length, 3);
      final instanceIds = deck.entries.map((e) => e.instanceId).toSet();
      expect(instanceIds.length, 3); // すべて一意
      expect(deck.entries.every((e) => e.cardId == 'normal_1'), isTrue);
    });
  });

  group('TechniqueDeckValidator', () {
    TechniqueDeckTechniqueCard normalCard(String id, String name) =>
        TechniqueDeckTechniqueCard(
          id: id,
          name: name,
          category: TechniqueCardCategory.normal,
          attribute: MoveAttribute.strike,
          attackEnergyCost: const {MoveAttribute.strike: 1},
          reversalEnergyCost: const {MoveAttribute.counter: 1},
          minimumLevel: 1,
        );

    TechniqueDeckTechniqueCard signatureCard(
      String id,
      String name, {
      List<String> allowedWrestlerIds = const ['w1'],
    }) => TechniqueDeckTechniqueCard(
      id: id,
      name: name,
      category: TechniqueCardCategory.signature,
      attribute: MoveAttribute.strike,
      allowedWrestlerIds: allowedWrestlerIds,
      minimumLevel: 2,
    );

    TechniqueDeckTechniqueCard finisherCard(
      String id,
      String name, {
      List<String> allowedWrestlerIds = const ['w1'],
    }) => TechniqueDeckTechniqueCard(
      id: id,
      name: name,
      category: TechniqueCardCategory.finisher,
      attribute: MoveAttribute.strike,
      allowedWrestlerIds: allowedWrestlerIds,
      hasFinisherEffect: true,
      minimumLevel: 3,
    );

    TechniqueEnergyCard energyCard(String id, MoveAttribute attribute) =>
        TechniqueEnergyCard(id: id, attribute: attribute, name: '$id-name');

    TechniqueDefenseCard defenseCard(
      String id,
      TechniqueDeckCardType type, {
      KickOutCardCategory? kickOutCategory,
    }) => TechniqueDefenseCard(
      id: id,
      name: '$id-name',
      type: type,
      kickOutCategory: kickOutCategory,
    );

    // 30枚のバランスの取れた有効デッキを組み立てるヘルパー。
    ({TechniqueDeckDefinition deck, TechniqueDeckCardCatalog catalog})
    buildValidDeckAndCatalog() {
      final catalog = TechniqueDeckCardCatalog(
        techniques: [
          normalCard('normal_1', '通常技1'),
          normalCard('normal_2', '通常技2'),
          signatureCard('sig_1', '固有技1'),
          signatureCard('sig_2', '固有技2'),
          finisherCard('fin_1', 'フィニッシャー1'),
        ],
        energies: [
          energyCard('energy_strike', MoveAttribute.strike),
          energyCard('energy_counter', MoveAttribute.counter),
        ],
        defenseCards: [
          defenseCard('escape_1', TechniqueDeckCardType.escape),
          defenseCard('reversal_1', TechniqueDeckCardType.reversal),
          defenseCard(
            'kickout_normal_1',
            TechniqueDeckCardType.kickOut,
            kickOutCategory: KickOutCardCategory.normal,
          ),
          defenseCard(
            'kickout_special_1',
            TechniqueDeckCardType.kickOut,
            kickOutCategory: KickOutCardCategory.finisherEscape,
          ),
          defenseCard('ropebreak_1', TechniqueDeckCardType.ropeBreak),
        ],
      );

      final builder = TechniqueDeckBuilder(wrestlerId: 'w1', id: 'd1')
        ..addCard('normal_1', TechniqueDeckCardType.technique, count: 3)
        ..addCard('normal_2', TechniqueDeckCardType.technique, count: 3)
        ..addCard('sig_1', TechniqueDeckCardType.technique)
        ..addCard('sig_2', TechniqueDeckCardType.technique)
        ..addCard('fin_1', TechniqueDeckCardType.technique)
        ..addCard('energy_strike', TechniqueDeckCardType.energy, count: 6)
        ..addCard('energy_counter', TechniqueDeckCardType.energy, count: 6)
        ..addCard('escape_1', TechniqueDeckCardType.escape, count: 2)
        ..addCard('reversal_1', TechniqueDeckCardType.reversal, count: 2)
        ..addCard('kickout_normal_1', TechniqueDeckCardType.kickOut, count: 2)
        ..addCard(
          'kickout_special_1',
          TechniqueDeckCardType.kickOut,
          count: 1,
        )
        ..addCard('ropebreak_1', TechniqueDeckCardType.ropeBreak, count: 2);

      final deck = builder.build();
      // 3+3+1+1+1 + 6+6 + 2+2+2+1+2 = 9 + 12 + 9 = 30
      expect(deck.entries.length, 30);
      return (deck: deck, catalog: catalog);
    }

    test('バランスの取れたデッキはエラー・警告なし', () {
      final fixture = buildValidDeckAndCatalog();
      final result = const TechniqueDeckValidator().validate(
        fixture.deck,
        fixture.catalog,
      );
      expect(result.isValid, isTrue, reason: result.errors.join('\n'));
      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    });

    test('デッキ枚数が30枚でない場合はエラー', () {
      final fixture = buildValidDeckAndCatalog();
      final shortDeck = fixture.deck.copyWith(
        entries: fixture.deck.entries.take(29).toList(),
      );
      final result = const TechniqueDeckValidator().validate(
        shortDeck,
        fixture.catalog,
      );
      expect(
        result.errors.any(
          (i) => i.code == TechniqueDeckValidationRule.deckSizeMismatch.name,
        ),
        isTrue,
      );
    });

    test('存在しないカードIDはエラー', () {
      final fixture = buildValidDeckAndCatalog();
      final entries = List<TechniqueDeckEntry>.from(fixture.deck.entries);
      entries[0] = entries[0].copyWith(cardId: 'unknown_card');
      final result = const TechniqueDeckValidator().validate(
        fixture.deck.copyWith(entries: entries),
        fixture.catalog,
      );
      expect(
        result.errors.any(
          (i) => i.code == TechniqueDeckValidationRule.unknownCardId.name,
        ),
        isTrue,
      );
    });

    test('重複インスタンスIDはエラー', () {
      final fixture = buildValidDeckAndCatalog();
      final entries = List<TechniqueDeckEntry>.from(fixture.deck.entries);
      entries[1] = entries[1].copyWith(instanceId: entries[0].instanceId);
      final result = const TechniqueDeckValidator().validate(
        fixture.deck.copyWith(entries: entries),
        fixture.catalog,
      );
      expect(
        result.errors.any(
          (i) => i.code == TechniqueDeckValidationRule.duplicateInstanceId.name,
        ),
        isTrue,
      );
    });

    test('宣言cardTypeとカタログ実態の不一致はエラー', () {
      final fixture = buildValidDeckAndCatalog();
      final entries = List<TechniqueDeckEntry>.from(fixture.deck.entries);
      entries[0] = entries[0].copyWith(cardType: TechniqueDeckCardType.energy);
      final result = const TechniqueDeckValidator().validate(
        fixture.deck.copyWith(entries: entries),
        fixture.catalog,
      );
      expect(
        result.errors.any(
          (i) => i.code == TechniqueDeckValidationRule.cardTypeMismatch.name,
        ),
        isTrue,
      );
    });

    test('通常技の同名上限（3枚）超過はエラー', () {
      final fixture = buildValidDeckAndCatalog();
      final builder = TechniqueDeckBuilder(wrestlerId: 'w1', id: 'd1')
        ..addCard('normal_1', TechniqueDeckCardType.technique, count: 4)
        ..addCard('normal_2', TechniqueDeckCardType.technique, count: 2)
        ..addCard('sig_1', TechniqueDeckCardType.technique)
        ..addCard('sig_2', TechniqueDeckCardType.technique)
        ..addCard('fin_1', TechniqueDeckCardType.technique)
        ..addCard('energy_strike', TechniqueDeckCardType.energy, count: 6)
        ..addCard('energy_counter', TechniqueDeckCardType.energy, count: 6)
        ..addCard('escape_1', TechniqueDeckCardType.escape, count: 2)
        ..addCard('reversal_1', TechniqueDeckCardType.reversal, count: 2)
        ..addCard('kickout_normal_1', TechniqueDeckCardType.kickOut, count: 2)
        ..addCard(
          'kickout_special_1',
          TechniqueDeckCardType.kickOut,
          count: 1,
        )
        ..addCard('ropebreak_1', TechniqueDeckCardType.ropeBreak, count: 2);
      final result = const TechniqueDeckValidator().validate(
        builder.build(),
        fixture.catalog,
      );
      expect(
        result.errors.any(
          (i) =>
              i.code == TechniqueDeckValidationRule.sameNameLimitExceeded.name,
        ),
        isTrue,
      );
    });

    test('固有技の同名上限（1枚）超過はエラー', () {
      final fixture = buildValidDeckAndCatalog();
      // 30枚を維持したまま、ropebreak_1の1枚をsig_1（既に1枚投入済み）へ
      // 差し替えることで、sig_1の同名枚数を2枚にする。
      final entries = List<TechniqueDeckEntry>.from(fixture.deck.entries);
      final ropeBreakIndex = entries.indexWhere(
        (e) => e.cardId == 'ropebreak_1',
      );
      entries[ropeBreakIndex] = entries[ropeBreakIndex].copyWith(
        cardId: 'sig_1',
        cardType: TechniqueDeckCardType.technique,
      );
      final result = const TechniqueDeckValidator().validate(
        fixture.deck.copyWith(entries: entries),
        fixture.catalog,
      );
      expect(
        result.errors.any(
          (i) =>
              i.code == TechniqueDeckValidationRule.sameNameLimitExceeded.name,
        ),
        isTrue,
      );
    });

    test('フィニッシャーが3枚を超えるとエラー', () {
      final catalog = TechniqueDeckCardCatalog(
        techniques: [
          finisherCard('fin_1', 'フィニッシャー1'),
          finisherCard('fin_2', 'フィニッシャー2'),
          finisherCard('fin_3', 'フィニッシャー3'),
          finisherCard('fin_4', 'フィニッシャー4'),
          normalCard('normal_1', '通常技1'),
        ],
        energies: [energyCard('energy_strike', MoveAttribute.strike)],
        defenseCards: const [],
      );
      final builder = TechniqueDeckBuilder(wrestlerId: 'w1', id: 'd1')
        ..addCard('fin_1', TechniqueDeckCardType.technique)
        ..addCard('fin_2', TechniqueDeckCardType.technique)
        ..addCard('fin_3', TechniqueDeckCardType.technique)
        ..addCard('fin_4', TechniqueDeckCardType.technique)
        ..addCard('normal_1', TechniqueDeckCardType.technique, count: 3)
        ..addCard('energy_strike', TechniqueDeckCardType.energy, count: 23);
      final result = const TechniqueDeckValidator().validate(
        builder.build(),
        catalog,
      );
      expect(
        result.errors.any(
          (i) =>
              i.code == TechniqueDeckValidationRule.finisherCountExceeded.name,
        ),
        isTrue,
      );
    });

    test('同名フィニッシャーが複数あるとエラー', () {
      final catalog = TechniqueDeckCardCatalog(
        techniques: [
          finisherCard('fin_1', '同じ名前'),
          finisherCard('fin_2', '同じ名前'),
          normalCard('normal_1', '通常技1'),
        ],
        energies: [energyCard('energy_strike', MoveAttribute.strike)],
        defenseCards: const [],
      );
      final builder = TechniqueDeckBuilder(wrestlerId: 'w1', id: 'd1')
        ..addCard('fin_1', TechniqueDeckCardType.technique)
        ..addCard('fin_2', TechniqueDeckCardType.technique)
        ..addCard('normal_1', TechniqueDeckCardType.technique, count: 3)
        ..addCard('energy_strike', TechniqueDeckCardType.energy, count: 25);
      final result = const TechniqueDeckValidator().validate(
        builder.build(),
        catalog,
      );
      expect(
        result.errors.any(
          (i) =>
              i.code == TechniqueDeckValidationRule.duplicateFinisherName.name,
        ),
        isTrue,
      );
    });

    test('固有技・フィニッシャーのallowedWrestlerIdsが空だとエラー', () {
      final catalog = TechniqueDeckCardCatalog(
        techniques: [
          signatureCard('sig_1', '固有技1', allowedWrestlerIds: const []),
          normalCard('normal_1', '通常技1'),
        ],
        energies: [energyCard('energy_strike', MoveAttribute.strike)],
        defenseCards: const [],
      );
      final builder = TechniqueDeckBuilder(wrestlerId: 'w1', id: 'd1')
        ..addCard('sig_1', TechniqueDeckCardType.technique)
        ..addCard('normal_1', TechniqueDeckCardType.technique, count: 3)
        ..addCard('energy_strike', TechniqueDeckCardType.energy, count: 26);
      final result = const TechniqueDeckValidator().validate(
        builder.build(),
        catalog,
      );
      expect(
        result.errors.any(
          (i) =>
              i.code ==
              TechniqueDeckValidationRule.emptyAllowedWrestlerIds.name,
        ),
        isTrue,
      );
    });

    test('固有技のallowedWrestlerIdsがデッキのレスラーを含まないとエラー', () {
      final catalog = TechniqueDeckCardCatalog(
        techniques: [
          signatureCard(
            'sig_1',
            '固有技1',
            allowedWrestlerIds: const ['someone_else'],
          ),
          normalCard('normal_1', '通常技1'),
        ],
        energies: [energyCard('energy_strike', MoveAttribute.strike)],
        defenseCards: const [],
      );
      final builder = TechniqueDeckBuilder(wrestlerId: 'w1', id: 'd1')
        ..addCard('sig_1', TechniqueDeckCardType.technique)
        ..addCard('normal_1', TechniqueDeckCardType.technique, count: 3)
        ..addCard('energy_strike', TechniqueDeckCardType.energy, count: 26);
      final result = const TechniqueDeckValidator().validate(
        builder.build(),
        catalog,
      );
      expect(
        result.errors.any(
          (i) => i.code == TechniqueDeckValidationRule.wrestlerMismatch.name,
        ),
        isTrue,
      );
    });

    test('通常技のallowedWrestlerIdsが空でもエラーにならない', () {
      final catalog = TechniqueDeckCardCatalog(
        techniques: [normalCard('normal_1', '通常技1')],
        energies: [energyCard('energy_strike', MoveAttribute.strike)],
        defenseCards: const [],
      );
      final builder = TechniqueDeckBuilder(wrestlerId: 'w1', id: 'd1')
        ..addCard('normal_1', TechniqueDeckCardType.technique, count: 3)
        ..addCard('energy_strike', TechniqueDeckCardType.energy, count: 27);
      final result = const TechniqueDeckValidator().validate(
        builder.build(),
        catalog,
      );
      expect(
        result.errors.any(
          (i) =>
              i.code ==
                  TechniqueDeckValidationRule.emptyAllowedWrestlerIds.name ||
              i.code == TechniqueDeckValidationRule.wrestlerMismatch.name,
        ),
        isFalse,
      );
    });

    test('エネルギーカードが0枚だとエラー', () {
      final catalog = TechniqueDeckCardCatalog(
        techniques: [normalCard('normal_1', '通常技1')],
        energies: const [],
        defenseCards: const [],
      );
      final builder = TechniqueDeckBuilder(wrestlerId: 'w1', id: 'd1')
        ..addCard('normal_1', TechniqueDeckCardType.technique, count: 3);
      final result = const TechniqueDeckValidator().validate(
        builder.build(),
        catalog,
      );
      expect(
        result.errors.any(
          (i) => i.code == TechniqueDeckValidationRule.noEnergyCards.name,
        ),
        isTrue,
      );
    });

    test('フィニッシャー0枚は警告', () {
      final fixture = buildValidDeckAndCatalog();
      final entries = List<TechniqueDeckEntry>.from(fixture.deck.entries);
      final finIndex = entries.indexWhere((e) => e.cardId == 'fin_1');
      entries[finIndex] = entries[finIndex].copyWith(cardId: 'normal_1');
      final result = const TechniqueDeckValidator().validate(
        fixture.deck.copyWith(entries: entries),
        fixture.catalog,
      );
      expect(
        result.warnings.any(
          (i) => i.code == TechniqueDeckValidationRule.noFinisherCards.name,
        ),
        isTrue,
      );
    });

    test('特殊キックアウト0枚は警告', () {
      final fixture = buildValidDeckAndCatalog();
      final entries = List<TechniqueDeckEntry>.from(fixture.deck.entries);
      final index = entries.indexWhere((e) => e.cardId == 'kickout_special_1');
      entries[index] = entries[index].copyWith(cardId: 'kickout_normal_1');
      final result = const TechniqueDeckValidator().validate(
        fixture.deck.copyWith(entries: entries),
        fixture.catalog,
      );
      expect(
        result.warnings.any(
          (i) =>
              i.code == TechniqueDeckValidationRule.noSpecialKickOutCards.name,
        ),
        isTrue,
      );
    });

    test('必要な攻撃属性のエネルギーカードがないと警告', () {
      final catalog = TechniqueDeckCardCatalog(
        techniques: [
          TechniqueDeckTechniqueCard(
            id: 'normal_aerial',
            name: '飛技',
            category: TechniqueCardCategory.normal,
            attribute: MoveAttribute.aerial,
            attackEnergyCost: const {MoveAttribute.aerial: 1},
          ),
        ],
        energies: [energyCard('energy_strike', MoveAttribute.strike)],
        defenseCards: const [],
      );
      final builder = TechniqueDeckBuilder(wrestlerId: 'w1', id: 'd1')
        ..addCard('normal_aerial', TechniqueDeckCardType.technique, count: 3)
        ..addCard('energy_strike', TechniqueDeckCardType.energy, count: 27);
      final result = const TechniqueDeckValidator().validate(
        builder.build(),
        catalog,
      );
      expect(
        result.warnings.any(
          (i) =>
              i.code ==
              TechniqueDeckValidationRule.missingAttackEnergyCoverage.name,
        ),
        isTrue,
      );
    });

    test('技カードが極端に少ないと警告', () {
      final catalog = TechniqueDeckCardCatalog(
        techniques: [normalCard('normal_1', '通常技1')],
        energies: [energyCard('energy_strike', MoveAttribute.strike)],
        defenseCards: const [],
      );
      final builder = TechniqueDeckBuilder(wrestlerId: 'w1', id: 'd1')
        ..addCard('normal_1', TechniqueDeckCardType.technique, count: 3)
        ..addCard('energy_strike', TechniqueDeckCardType.energy, count: 27);
      final result = const TechniqueDeckValidator().validate(
        builder.build(),
        catalog,
      );
      expect(
        result.warnings.any(
          (i) =>
              i.code == TechniqueDeckValidationRule.tooFewTechniqueCards.name,
        ),
        isTrue,
      );
    });

    test('エネルギーカード比率が極端だと警告', () {
      final catalog = TechniqueDeckCardCatalog(
        techniques: [normalCard('normal_1', '通常技1')],
        energies: [energyCard('energy_strike', MoveAttribute.strike)],
        defenseCards: const [],
      );
      final builder = TechniqueDeckBuilder(wrestlerId: 'w1', id: 'd1')
        ..addCard('normal_1', TechniqueDeckCardType.technique, count: 3)
        ..addCard('energy_strike', TechniqueDeckCardType.energy, count: 27);
      final result = const TechniqueDeckValidator().validate(
        builder.build(),
        catalog,
      );
      expect(
        result.warnings.any(
          (i) => i.code == TechniqueDeckValidationRule.extremeEnergyRatio.name,
        ),
        isTrue,
      );
    });

    test('minimumLevelが1以下の技が皆無だと警告', () {
      final catalog = TechniqueDeckCardCatalog(
        techniques: [
          TechniqueDeckTechniqueCard(
            id: 'normal_lv2',
            name: 'レベル2技',
            category: TechniqueCardCategory.normal,
            attribute: MoveAttribute.strike,
            minimumLevel: 2,
          ),
        ],
        energies: [energyCard('energy_strike', MoveAttribute.strike)],
        defenseCards: const [],
      );
      final builder = TechniqueDeckBuilder(wrestlerId: 'w1', id: 'd1')
        ..addCard('normal_lv2', TechniqueDeckCardType.technique, count: 3)
        ..addCard('energy_strike', TechniqueDeckCardType.energy, count: 27);
      final result = const TechniqueDeckValidator().validate(
        builder.build(),
        catalog,
      );
      expect(
        result.warnings.any(
          (i) =>
              i.code ==
              TechniqueDeckValidationRule.allTechniquesUnusableLevel.name,
        ),
        isTrue,
      );
    });
  });
}
