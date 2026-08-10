// Combat Ver.1 Phase 4 Codexレビュー指摘M3: CombatV1Counterの
// counterableFamilies/counterableGroupsの防御的コピー、および
// CombatV1PendingAttackが宣言時点のスナップショットを保持し、元の
// Catalog/Technique定義の変更・mutationの影響を受けないことの検証。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_counter.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';

import 'combat_v1_test_fixtures.dart';

void main() {
  group('CombatV1Counter — target list defensive copy（M3）', () {
    test('外部で渡したmutableなListをコンストラクタ後に変更しても、'
        'Counter定義のcounterableFamiliesは変化しない', () {
      final source = <CombatV1TechniqueFamily>[CombatV1TechniqueFamily.kick];
      final counter = CombatV1Counter(
        id: 'mut_test',
        name: 'テスト',
        attribute: CombatV1EnergyAttribute.strike,
        counterableFamilies: source,
      );
      source.add(CombatV1TechniqueFamily.chop); // 構築後に外部で変更
      expect(counter.counterableFamilies, [CombatV1TechniqueFamily.kick]);
    });

    test('外部で渡したmutableなListをコンストラクタ後に変更しても、'
        'Counter定義のcounterableGroupsは変化しない', () {
      final source = <CombatV1TechniqueFamilyGroup>[CombatV1TechniqueFamilyGroup.strike];
      final counter = CombatV1Counter(
        id: 'mut_test2',
        name: 'テスト2',
        attribute: CombatV1EnergyAttribute.strike,
        counterableGroups: source,
      );
      source.add(CombatV1TechniqueFamilyGroup.aerial);
      expect(counter.counterableGroups, [CombatV1TechniqueFamilyGroup.strike]);
    });

    test('Counter.counterableFamilies自体への外部からの変更（要素追加）は失敗する'
        '（unmodifiable）', () {
      final counter = CombatV1Counter(
        id: 'unmod_test',
        name: 'テスト',
        attribute: CombatV1EnergyAttribute.strike,
        counterableFamilies: [CombatV1TechniqueFamily.kick],
      );
      expect(
        () => counter.counterableFamilies.add(CombatV1TechniqueFamily.chop),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('重複を含むListも防御的コピー後に重複を保持する（Catalog validationの'
        '重複検出が引き続き機能することの裏付け）', () {
      final counter = CombatV1Counter(
        id: 'dup_test',
        name: 'テスト',
        attribute: CombatV1EnergyAttribute.strike,
        counterableFamilies: [
          CombatV1TechniqueFamily.kick,
          CombatV1TechniqueFamily.kick,
        ],
      );
      expect(counter.counterableFamilies.length, 2);
    });
  });

  group('CombatV1PendingAttack — snapshot immutability', () {
    test('宣言後にCatalogのTechnique定義を差し替えても、既存pendingの内容は'
        '変化しない（宣言時点でスナップショットしているため）', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'atk1',
        cardId: 'fx_normal_strike', // damage10, family=elbow
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry]);

      final declared = CombatV1Engine.declareTechnique(
        state,
        'atk1',
        catalog: fixtureCatalog,
      );
      final pendingBefore = declared.pendingAttack!;
      expect(pendingBefore.damage, 10);
      expect(pendingBefore.family, CombatV1TechniqueFamily.elbow);

      // 差し替えた別カタログを後から使っても（同じstateには影響しない）、
      // 既存のpendingAttackインスタンス自体は元の値のまま。
      final alteredCatalog = CombatV1CardCatalog(
        techniques: {
          ...fixtureTechniques,
          'fx_normal_strike': const CombatV1Technique(
            id: 'fx_normal_strike',
            name: '差し替え後の技',
            category: CombatV1CardCategory.normal,
            attribute: CombatV1EnergyAttribute.strike,
            energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
            damage: 999, // 大きく変えてみる
            heatGain: 999,
            family: CombatV1TechniqueFamily.driver,
          ),
        },
        counters: fixtureCounters,
      );
      // alteredCatalogは新しいオブジェクトであり、既存pendingには影響しない
      // ことを確認する（declared.pendingAttackの値がalteredCatalog構築後も
      // 変化しないことそのものが検証）。
      expect(alteredCatalog.techniques['fx_normal_strike']!.damage, 999);
      expect(declared.pendingAttack!.damage, 10);
      expect(declared.pendingAttack!.family, CombatV1TechniqueFamily.elbow);
    });

    test('energyCostの防御的コピー: 宣言後にTechnique側のenergyCost.amounts'
        '（Mapリテラル）を書き換えてもpendingの値は変化しない', () {
      final mutableAmounts = <CombatV1EnergyAttribute, int>{
        CombatV1EnergyAttribute.strike: 1,
      };
      final technique = CombatV1Technique(
        id: 'mut_energy_test',
        name: 'テスト',
        category: CombatV1CardCategory.normal,
        attribute: CombatV1EnergyAttribute.strike,
        energyCost: CombatV1EnergyCost(mutableAmounts),
        damage: 10,
        heatGain: 10,
        family: CombatV1TechniqueFamily.kick,
      );
      final catalog = CombatV1CardCatalog(
        techniques: {...fixtureTechniques, technique.id: technique},
        counters: fixtureCounters,
      );
      final entry = const CombatV1DeckEntry(
        instanceId: 'atk1',
        cardId: 'mut_energy_test',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry]);
      final declared = CombatV1Engine.declareTechnique(state, 'atk1', catalog: catalog);

      // 宣言後に元のmutable Mapを書き換える。
      mutableAmounts[CombatV1EnergyAttribute.strike] = 99;

      expect(
        declared.pendingAttack!.energyCost.amountFor(CombatV1EnergyAttribute.strike),
        1, // 99ではなく、宣言時点の値のまま
      );
    });

    test('pendingAttack.energyCost.amountsへの外部からの変更は失敗する（unmodifiable）', () {
      final entry = const CombatV1DeckEntry(
        instanceId: 'atk1',
        cardId: 'fx_normal_strike',
        category: CombatV1CardCategory.normal,
      );
      final state = buildMatchState(handA: [entry]);
      final declared = CombatV1Engine.declareTechnique(state, 'atk1', catalog: fixtureCatalog);

      expect(
        () => declared.pendingAttack!.energyCost.amounts[CombatV1EnergyAttribute.wild] = 5,
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
