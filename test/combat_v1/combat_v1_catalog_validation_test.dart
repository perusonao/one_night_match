// Combat Ver.1 Phase 4: Catalog Definition validationの検証
// （docs/combat_rules_v1.md「23.6章 Catalog validation」、テスト項目31-B）。
//
// combat_v1_deck_validation_test.dartがデッキ（30枚構成）の検証を担当
// するのに対し、このファイルはTechnique/Counter Definitionそのものの
// 整合性（validateCatalog）を検証する。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_catalog_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_counter.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';

import 'combat_v1_test_fixtures.dart';

const _validTechnique = CombatV1Technique(
  id: 'cv_technique',
  name: '検証用技',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.strike,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
  damage: 10,
  heatGain: 10,
  family: CombatV1TechniqueFamily.kick,
);

final _validCounter = CombatV1Counter(
  id: 'cv_counter',
  name: '検証用カウンター',
  attribute: CombatV1EnergyAttribute.strike,
  counterableFamilies: [CombatV1TechniqueFamily.kick],
);

void main() {
  group('validateCatalog — 正しいカタログ', () {
    test('フィクスチャカタログはvalid', () {
      final result = validateCatalog(fixtureCatalog);
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });
  });

  group('validateCatalog — Technique', () {
    test('Technique familyが必須（型で強制されるため、familyを持たないTechniqueは'
        'そもそも構築できない）', () {
      // CombatV1Technique.familyはrequiredな非nullable enumのため、
      // 「familyが無いTechnique」は型システムが構築自体を許さない
      // （コンパイルエラーになる）。この事実そのものが「family必須」要件の
      // 充足を裏付ける。
      expect(_validTechnique.family, isNotNull);
    });

    test('invalid Energy Cost（wildを要求）はtechniqueInvalidEnergyCost', () {
      final catalog = CombatV1CardCatalog(
        techniques: {
          'bad': const CombatV1Technique(
            id: 'bad',
            name: '不正技',
            category: CombatV1CardCategory.normal,
            attribute: CombatV1EnergyAttribute.strike,
            energyCost: CombatV1EnergyCost({
              CombatV1EnergyAttribute.strike: 1,
              CombatV1EnergyAttribute.wild: 1,
            }),
            damage: 10,
            heatGain: 10,
            family: CombatV1TechniqueFamily.kick,
          ),
        },
        counters: const {},
      );
      final result = validateCatalog(catalog);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1CatalogValidationErrorCode.techniqueInvalidEnergyCost),
      );
    });

    test('zero Costは拒否される（techniqueZeroEnergyCost）', () {
      final catalog = CombatV1CardCatalog(
        techniques: {
          'zero': const CombatV1Technique(
            id: 'zero',
            name: 'zero cost技',
            category: CombatV1CardCategory.normal,
            attribute: CombatV1EnergyAttribute.strike,
            energyCost: CombatV1EnergyCost.zero,
            damage: 10,
            heatGain: 10,
            family: CombatV1TechniqueFamily.kick,
          ),
        },
        counters: const {},
      );
      final result = validateCatalog(catalog);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1CatalogValidationErrorCode.techniqueZeroEnergyCost),
      );
    });

    test('負数のdamage/heatGainは拒否される', () {
      final catalog = CombatV1CardCatalog(
        techniques: {
          'neg': const CombatV1Technique(
            id: 'neg',
            name: '負数技',
            category: CombatV1CardCategory.normal,
            attribute: CombatV1EnergyAttribute.strike,
            energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
            damage: -1,
            heatGain: -1,
            family: CombatV1TechniqueFamily.kick,
          ),
        },
        counters: const {},
      );
      final result = validateCatalog(catalog);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        containsAll([
          CombatV1CatalogValidationErrorCode.techniqueNegativeDamage,
          CombatV1CatalogValidationErrorCode.techniqueNegativeHeatGain,
        ]),
      );
    });

    test('key/id不一致はcatalogKeyIdMismatch', () {
      final catalog = CombatV1CardCatalog(
        techniques: {'wrong_key': _validTechnique},
        counters: const {},
      );
      final result = validateCatalog(catalog);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1CatalogValidationErrorCode.catalogKeyIdMismatch),
      );
    });

    test(
      'directPin=trueかつsubmissionHold=true（category!=finisher）は排他違反'
      '（docs/combat_rules_v1.md 10章、Phase 6）',
      () {
        final catalog = CombatV1CardCatalog(
          techniques: {
            'both': const CombatV1Technique(
              id: 'both',
              name: '排他違反技',
              category: CombatV1CardCategory.normal,
              attribute: CombatV1EnergyAttribute.throwing,
              energyCost: CombatV1EnergyCost({
                CombatV1EnergyAttribute.throwing: 1,
              }),
              damage: 20,
              heatGain: 20,
              directPin: true,
              submissionHold: true,
              family: CombatV1TechniqueFamily.backdrop,
            ),
          },
          counters: const {},
        );
        final result = validateCatalog(catalog);
        expect(result.isValid, isFalse);
        expect(
          result.errors.map((e) => e.code),
          contains(
            CombatV1CatalogValidationErrorCode
                .techniqueDirectPinSubmissionHoldConflict,
          ),
        );
      },
    );

    test('directPinのみ、submissionHoldのみはそれぞれ単独で許可される', () {
      final catalog = CombatV1CardCatalog(
        techniques: {
          'direct_pin_only': const CombatV1Technique(
            id: 'direct_pin_only',
            name: 'DIRECT PINのみ',
            category: CombatV1CardCategory.normal,
            attribute: CombatV1EnergyAttribute.throwing,
            energyCost: CombatV1EnergyCost({
              CombatV1EnergyAttribute.throwing: 1,
            }),
            damage: 20,
            heatGain: 20,
            directPin: true,
            family: CombatV1TechniqueFamily.backdrop,
          ),
          'submission_hold_only': const CombatV1Technique(
            id: 'submission_hold_only',
            name: 'submissionHoldのみ',
            category: CombatV1CardCategory.normal,
            attribute: CombatV1EnergyAttribute.joint,
            energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 1}),
            damage: 20,
            heatGain: 20,
            submissionHold: true,
            family: CombatV1TechniqueFamily.crossface,
          ),
        },
        counters: const {},
      );
      final result = validateCatalog(catalog);
      expect(
        result.errors.map((e) => e.code),
        isNot(
          contains(
            CombatV1CatalogValidationErrorCode
                .techniqueDirectPinSubmissionHoldConflict,
          ),
        ),
      );
    });
  });

  group('validateCatalog — Counter', () {
    test('Counter.attribute==wildは拒否される（counterWildAttribute）', () {
      final catalog = CombatV1CardCatalog(
        techniques: const {},
        counters: {
          'wild_counter': CombatV1Counter(
            id: 'wild_counter',
            name: '不正カウンター',
            attribute: CombatV1EnergyAttribute.wild,
            counterableFamilies: [CombatV1TechniqueFamily.kick],
          ),
        },
      );
      final result = validateCatalog(catalog);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1CatalogValidationErrorCode.counterWildAttribute),
      );
    });

    test('counterableFamilies/counterableGroupsが両方空はcounterEmptyTargets', () {
      final catalog = CombatV1CardCatalog(
        techniques: const {},
        counters: {
          'empty_counter': CombatV1Counter(
            id: 'empty_counter',
            name: '空カウンター',
            attribute: CombatV1EnergyAttribute.strike,
          ),
        },
      );
      final result = validateCatalog(catalog);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1CatalogValidationErrorCode.counterEmptyTargets),
      );
    });

    test('counterableFamiliesの重複はcounterDuplicateFamily', () {
      final catalog = CombatV1CardCatalog(
        techniques: const {},
        counters: {
          'dup_family': CombatV1Counter(
            id: 'dup_family',
            name: '重複family',
            attribute: CombatV1EnergyAttribute.strike,
            counterableFamilies: [
              CombatV1TechniqueFamily.kick,
              CombatV1TechniqueFamily.kick,
            ],
          ),
        },
      );
      final result = validateCatalog(catalog);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1CatalogValidationErrorCode.counterDuplicateFamily),
      );
    });

    test('counterableGroupsの重複はcounterDuplicateGroup', () {
      final catalog = CombatV1CardCatalog(
        techniques: const {},
        counters: {
          'dup_group': CombatV1Counter(
            id: 'dup_group',
            name: '重複group',
            attribute: CombatV1EnergyAttribute.strike,
            counterableGroups: [
              CombatV1TechniqueFamilyGroup.strike,
              CombatV1TechniqueFamilyGroup.strike,
            ],
          ),
        },
      );
      final result = validateCatalog(catalog);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1CatalogValidationErrorCode.counterDuplicateGroup),
      );
    });

    test('groupと、それに包含されるfamilyの冗長同時指定はcounterRedundantGroupAndFamily'
        '（例: STRIKE groupとKICK familyの同時指定）', () {
      final catalog = CombatV1CardCatalog(
        techniques: const {},
        counters: {
          'redundant': CombatV1Counter(
            id: 'redundant',
            name: '冗長カウンター',
            attribute: CombatV1EnergyAttribute.strike,
            counterableGroups: [CombatV1TechniqueFamilyGroup.strike],
            counterableFamilies: [CombatV1TechniqueFamily.kick],
          ),
        },
      );
      final result = validateCatalog(catalog);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1CatalogValidationErrorCode.counterRedundantGroupAndFamily),
      );
    });

    test('groupに包含されないfamilyの併用は冗長ではない（例: STRIKE group + SUPLEX family）', () {
      final catalog = CombatV1CardCatalog(
        techniques: const {},
        counters: {
          'ok': CombatV1Counter(
            id: 'ok',
            name: '非冗長カウンター',
            attribute: CombatV1EnergyAttribute.strike,
            counterableGroups: [CombatV1TechniqueFamilyGroup.strike],
            counterableFamilies: [CombatV1TechniqueFamily.suplex],
          ),
        },
      );
      final result = validateCatalog(catalog);
      expect(result.isValid, isTrue);
    });
  });

  group('validateCatalog — Cross catalog', () {
    test('Technique/Counter ID collisionはcardIdCollision', () {
      final catalog = CombatV1CardCatalog(
        techniques: {'shared_id': _validTechnique.copyWithId('shared_id')},
        counters: {'shared_id': _validCounter.copyWithId('shared_id')},
      );
      final result = validateCatalog(catalog);
      expect(result.isValid, isFalse);
      expect(
        result.errors.map((e) => e.code),
        contains(CombatV1CatalogValidationErrorCode.cardIdCollision),
      );
    });
  });
}

extension on CombatV1Technique {
  CombatV1Technique copyWithId(String id) => CombatV1Technique(
    id: id,
    name: name,
    category: category,
    attribute: attribute,
    energyCost: energyCost,
    damage: damage,
    heatGain: heatGain,
    family: family,
  );
}

extension on CombatV1Counter {
  CombatV1Counter copyWithId(String id) => CombatV1Counter(
    id: id,
    name: name,
    attribute: attribute,
    counterableFamilies: counterableFamilies,
    counterableGroups: counterableGroups,
  );
}
