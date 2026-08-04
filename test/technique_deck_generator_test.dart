import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_deck.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_generator.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_models.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart' show MoveAttribute;

void main() {
  const wrestlerId = 'w1';

  TechniqueDeckTechniqueCard normalCard(
    String id,
    String name, {
    MoveAttribute attribute = MoveAttribute.strike,
    TechniqueTargetState targetState = TechniqueTargetState.any,
    bool hasPinEffect = false,
    bool hasSubmissionEffect = false,
  }) => TechniqueDeckTechniqueCard(
    id: id,
    name: name,
    category: TechniqueCardCategory.normal,
    attribute: attribute,
    attackEnergyCost: {attribute: 1},
    reversalEnergyCost: const {MoveAttribute.counter: 1},
    targetState: targetState,
    hasPinEffect: hasPinEffect,
    hasSubmissionEffect: hasSubmissionEffect,
  );

  TechniqueDeckTechniqueCard signatureCard(
    String id,
    String name, {
    List<String> allowedWrestlerIds = const [wrestlerId],
    int minimumLevel = 2,
  }) => TechniqueDeckTechniqueCard(
    id: id,
    name: name,
    category: TechniqueCardCategory.signature,
    attribute: MoveAttribute.strike,
    allowedWrestlerIds: allowedWrestlerIds,
    minimumLevel: minimumLevel,
  );

  TechniqueDeckTechniqueCard finisherCard(
    String id,
    String name, {
    List<String> allowedWrestlerIds = const [wrestlerId],
  }) => TechniqueDeckTechniqueCard(
    id: id,
    name: name,
    category: TechniqueCardCategory.finisher,
    attribute: MoveAttribute.strike,
    allowedWrestlerIds: allowedWrestlerIds,
    hasFinisherEffect: true,
    minimumLevel: 3,
  );

  TechniqueEnergyCard energyCard(MoveAttribute attribute) =>
      TechniqueEnergyCard(
        id: 'energy_${attribute.name}',
        attribute: attribute,
        name: '${attribute.name}エネルギー',
      );

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

  TechniqueDeckCardCatalog richCatalog() => TechniqueDeckCardCatalog(
    techniques: [
      normalCard(
        'normal_strike',
        '通常打1',
        targetState: TechniqueTargetState.stand,
      ),
      normalCard(
        'normal_throw',
        '通常投1',
        attribute: MoveAttribute.throwMove,
        targetState: TechniqueTargetState.down,
        hasPinEffect: true,
      ),
      normalCard('normal_submission', '通常関1', attribute: MoveAttribute.submission),
      normalCard('normal_rough', '通常凶1', attribute: MoveAttribute.rough),
      normalCard('normal_aerial', '通常飛1', attribute: MoveAttribute.aerial),
      normalCard('normal_strike_2', '通常打2'),
      signatureCard('sig_1', '固有技1', minimumLevel: 1),
      signatureCard('sig_2', '固有技2', minimumLevel: 2),
      signatureCard('sig_3', '固有技3', minimumLevel: 3),
      finisherCard('fin_1', 'フィニッシャー1'),
      finisherCard('fin_2', 'フィニッシャー2'),
      finisherCard('fin_3', 'フィニッシャー3'),
    ],
    energies: MoveAttribute.values.map(energyCard).toList(),
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
    ],
  );

  group('TechniqueDeckAutoGenerator: 豊富なカタログでの生成', () {
    TechniqueDeckGenerationResult generateOnce({int? seed}) =>
        TechniqueDeckAutoGenerator(
          config: TechniqueDeckGenerationConfig(seed: seed),
        ).generate(catalog: richCatalog(), wrestlerId: wrestlerId, deckId: 'd1');

    test('30枚になる', () {
      final result = generateOnce(seed: 1);
      expect(result.deck.entries.length, 30);
    });

    test('検証を通過する', () {
      final result = generateOnce(seed: 1);
      expect(
        result.success,
        isTrue,
        reason: result.failureReasons.join('\n'),
      );
      expect(result.buildResult.errors, isEmpty);
    });

    test('フィニッシャーは最大3枚', () {
      final result = generateOnce(seed: 1);
      final finisherCount = result.deck.entries
          .where((e) => ['fin_1', 'fin_2', 'fin_3'].contains(e.cardId))
          .length;
      expect(finisherCount, lessThanOrEqualTo(3));
    });

    test('同名フィニッシャーがない', () {
      final result = generateOnce(seed: 1);
      final finisherIds = result.deck.entries
          .where((e) => ['fin_1', 'fin_2', 'fin_3'].contains(e.cardId))
          .map((e) => e.cardId)
          .toSet();
      final finisherEntries = result.deck.entries.where(
        (e) => ['fin_1', 'fin_2', 'fin_3'].contains(e.cardId),
      );
      // 同一IDが複数投入されていない（=同名フィニッシャーが複数枚ない）。
      expect(finisherEntries.length, finisherIds.length);
    });

    test('使用可能レスラーと一致する固有技・フィニッシャーのみ採用される', () {
      final result = generateOnce(seed: 1);
      final catalog = richCatalog();
      for (final entry in result.deck.entries) {
        final technique = catalog.findTechniqueById(entry.cardId);
        if (technique == null) continue;
        if (technique.category == TechniqueCardCategory.signature ||
            technique.category == TechniqueCardCategory.finisher) {
          expect(technique.allowedWrestlerIds.contains(wrestlerId), isTrue);
        }
      }
    });

    test('固有技は同名1枚まで', () {
      final result = generateOnce(seed: 1);
      final counts = <String, int>{};
      for (final entry in result.deck.entries) {
        if (['sig_1', 'sig_2', 'sig_3'].contains(entry.cardId)) {
          counts[entry.cardId] = (counts[entry.cardId] ?? 0) + 1;
        }
      }
      expect(counts.values.every((c) => c <= 1), isTrue);
    });

    test('通常技は同名3枚以下', () {
      final result = generateOnce(seed: 1);
      final counts = <String, int>{};
      for (final entry in result.deck.entries) {
        if (entry.cardId.startsWith('normal_')) {
          counts[entry.cardId] = (counts[entry.cardId] ?? 0) + 1;
        }
      }
      expect(counts.values.every((c) => c <= 3), isTrue);
    });

    test('必要な攻撃属性のエネルギーが含まれる', () {
      final result = generateOnce(seed: 1);
      final catalog = richCatalog();
      final energyAttributes = result.deck.entries
          .map((e) => catalog.findEnergyById(e.cardId))
          .whereType<TechniqueEnergyCard>()
          .map((e) => e.attribute)
          .toSet();
      // fin/sig/normalいずれもstrike属性のattackEnergyCostを持つため
      // strikeエネルギーは必ず含まれるはず。
      expect(energyAttributes.contains(MoveAttribute.strike), isTrue);
    });

    test('Seed固定時は同じ構成が再現される', () {
      final a = generateOnce(seed: 42);
      final b = generateOnce(seed: 42);
      final aCounts = <String, int>{};
      for (final e in a.deck.entries) {
        aCounts[e.cardId] = (aCounts[e.cardId] ?? 0) + 1;
      }
      final bCounts = <String, int>{};
      for (final e in b.deck.entries) {
        bCounts[e.cardId] = (bCounts[e.cardId] ?? 0) + 1;
      }
      expect(aCounts, bCounts);
    });
  });

  group('TechniqueDeckAutoGenerator: 候補不足のフォールバック', () {
    test('固有技候補が不足すると通常技で代替し、検証を通過する', () {
      final catalog = TechniqueDeckCardCatalog(
        techniques: [
          normalCard('normal_1', '通常技1', targetState: TechniqueTargetState.stand),
          normalCard(
            'normal_2',
            '通常技2',
            attribute: MoveAttribute.throwMove,
            targetState: TechniqueTargetState.down,
            hasPinEffect: true,
          ),
          normalCard('normal_3', '通常技3', attribute: MoveAttribute.rough),
          signatureCard('sig_1', '固有技1'), // 候補1枚のみ（設定は3枚要求）
          finisherCard('fin_1', 'フィニッシャー1'),
        ],
        energies: [energyCard(MoveAttribute.strike), energyCard(MoveAttribute.counter)],
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
        ],
      );
      final result = TechniqueDeckAutoGenerator(
        config: const TechniqueDeckGenerationConfig(seed: 7),
      ).generate(catalog: catalog, wrestlerId: wrestlerId, deckId: 'd1');

      expect(result.deck.entries.length, 30);
      expect(result.success, isTrue, reason: result.failureReasons.join('\n'));
      expect(
        result.notes.any((n) => n.contains('固有技候補') && n.contains('通常技で代替')),
        isTrue,
      );
    });

    test('フィニッシャー候補が2枚しかない場合は2枚のみ採用し理由を記録する', () {
      final catalog = TechniqueDeckCardCatalog(
        techniques: [
          normalCard('normal_1', '通常技1'),
          normalCard('normal_2', '通常技2', attribute: MoveAttribute.throwMove),
          finisherCard('fin_1', 'フィニッシャー1'),
          finisherCard('fin_2', 'フィニッシャー2'),
        ],
        energies: [energyCard(MoveAttribute.strike), energyCard(MoveAttribute.counter)],
        defenseCards: const [],
      );
      final result = TechniqueDeckAutoGenerator(
        config: const TechniqueDeckGenerationConfig(seed: 3, finisherCount: 3),
      ).generate(catalog: catalog, wrestlerId: wrestlerId, deckId: 'd1');

      final finisherCount = result.deck.entries
          .where((e) => ['fin_1', 'fin_2'].contains(e.cardId))
          .length;
      expect(finisherCount, 2);
      expect(
        result.notes.any((n) => n.contains('フィニッシャー候補')),
        isTrue,
      );
    });
  });

  group('TechniqueDeckAutoGenerator: カタログ不足時の失敗', () {
    test('技エネルギーカードが1枚もないと検証エラーとなり失敗理由が返る', () {
      final catalog = TechniqueDeckCardCatalog(
        techniques: [normalCard('normal_1', '通常技1')],
        energies: const [],
        defenseCards: const [],
      );
      final result = TechniqueDeckAutoGenerator(
        config: const TechniqueDeckGenerationConfig(seed: 1),
      ).generate(catalog: catalog, wrestlerId: wrestlerId, deckId: 'd1');

      expect(result.success, isFalse);
      expect(result.failureReasons, isNotEmpty);
      expect(
        result.buildResult.errors.any(
          (i) => i.code == TechniqueDeckValidationRule.noEnergyCards.name,
        ),
        isTrue,
      );
    });

    test('カタログが完全に空だと目標枚数に届かず失敗理由が返る', () {
      const catalog = TechniqueDeckCardCatalog();
      final result = TechniqueDeckAutoGenerator(
        config: const TechniqueDeckGenerationConfig(seed: 1),
      ).generate(catalog: catalog, wrestlerId: wrestlerId, deckId: 'd1');

      expect(result.deck.entries, isEmpty);
      expect(result.success, isFalse);
      expect(result.failureReasons, isNotEmpty);
      expect(
        result.buildResult.errors.any(
          (i) => i.code == TechniqueDeckValidationRule.deckSizeMismatch.name,
        ),
        isTrue,
      );
    });
  });
}
