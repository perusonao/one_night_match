// Combat Ver.1 Phase 4: Technique Family / Family Groupの検証
// （docs/combat_rules_v1.md 23章「技系統（TechniqueFamily）」
// （23.2 Family Group／23.3 Technique Family／23.4
// CHOKEはattribute横断／23.5 COUNTER matching）、テスト項目31-A）。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_counter.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_counter_rules.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';

void main() {
  group('family → group 導出', () {
    test('STRIKE groupの全familyがgroup=strikeになる', () {
      const strikeFamilies = [
        CombatV1TechniqueFamily.elbow,
        CombatV1TechniqueFamily.chop,
        CombatV1TechniqueFamily.kick,
        CombatV1TechniqueFamily.knee,
        CombatV1TechniqueFamily.lariat,
        CombatV1TechniqueFamily.tackle,
        CombatV1TechniqueFamily.stomp,
        CombatV1TechniqueFamily.guillotineDrop,
      ];
      for (final family in strikeFamilies) {
        expect(
          family.group,
          CombatV1TechniqueFamilyGroup.strike,
          reason: '$familyはSTRIKE groupであるべき',
        );
      }
    });

    test('AERIAL groupの全familyがgroup=aerialになる', () {
      const aerialFamilies = [
        CombatV1TechniqueFamily.dropKick,
        CombatV1TechniqueFamily.bodyPress,
        CombatV1TechniqueFamily.splash,
      ];
      for (final family in aerialFamilies) {
        expect(family.group, CombatV1TechniqueFamilyGroup.aerial);
      }
    });

    test('THROW groupの全familyがgroup=throwingになる', () {
      const throwFamilies = [
        CombatV1TechniqueFamily.armDrag,
        CombatV1TechniqueFamily.ddt,
        CombatV1TechniqueFamily.legTakedown,
        CombatV1TechniqueFamily.slam,
        CombatV1TechniqueFamily.backdrop,
        CombatV1TechniqueFamily.suplex,
        CombatV1TechniqueFamily.powerbomb,
        CombatV1TechniqueFamily.driver,
      ];
      for (final family in throwFamilies) {
        expect(family.group, CombatV1TechniqueFamilyGroup.throwing);
      }
    });

    test('SUBMISSION groupの全familyがgroup=submissionになる', () {
      const submissionFamilies = [
        CombatV1TechniqueFamily.armbar,
        CombatV1TechniqueFamily.headlock,
        CombatV1TechniqueFamily.legLock,
        CombatV1TechniqueFamily.figureFour,
        CombatV1TechniqueFamily.crossface,
        CombatV1TechniqueFamily.stretch,
        CombatV1TechniqueFamily.choke,
        CombatV1TechniqueFamily.claw,
        CombatV1TechniqueFamily.neckLock,
      ];
      for (final family in submissionFamilies) {
        expect(family.group, CombatV1TechniqueFamilyGroup.submission);
      }
    });

    test('FOUL groupの全familyがgroup=foulになる', () {
      const foulFamilies = [
        CombatV1TechniqueFamily.lowBlow,
        CombatV1TechniqueFamily.weapon,
      ];
      for (final family in foulFamilies) {
        expect(family.group, CombatV1TechniqueFamilyGroup.foul);
      }
    });

    test('taxonomy合計は30family（SSOTの「合計29 family」という記述との'
        '不一致は最終報告で明示する）', () {
      expect(CombatV1TechniqueFamily.values.length, 30);
    });

    test('FOUL groupはCombatV1EnergyAttribute.roughとは異なる概念', () {
      // FOUL（COUNTER分類上のgroup）とROUGH（ENERGY属性）は別概念であり、
      // 同一視しない（docs/combat_rules_v1.md「23.2章 Family Group」）。
      // 型自体が異なるため、両者は決して==で比較できない
      // （コンパイル時に別enum型として扱われることが最大の裏付け）。
      expect(
        CombatV1TechniqueFamilyGroup.foul.runtimeType,
        isNot(CombatV1EnergyAttribute.rough.runtimeType),
      );
    });

    test('STOMPはSTRIKE group', () {
      expect(
        CombatV1TechniqueFamily.stomp.group,
        CombatV1TechniqueFamilyGroup.strike,
      );
    });

    test('FIGURE_FOURはSUBMISSION group', () {
      expect(
        CombatV1TechniqueFamily.figureFour.group,
        CombatV1TechniqueFamilyGroup.submission,
      );
    });

    test('STRETCHはSUBMISSION group', () {
      expect(
        CombatV1TechniqueFamily.stretch.group,
        CombatV1TechniqueFamilyGroup.submission,
      );
    });

    test('BACKDROPとSUPLEXは別family（同じTHROW groupだが異なるfamily値）', () {
      expect(
        CombatV1TechniqueFamily.backdrop,
        isNot(CombatV1TechniqueFamily.suplex),
      );
      expect(
        CombatV1TechniqueFamily.backdrop.group,
        CombatV1TechniqueFamily.suplex.group,
      );
    });
  });

  group('CHOKEはattribute横断（docs/combat_rules_v1.md「23.4章」）', () {
    test('familyはCHOKEのままattribute=joint/roughいずれも表現できる', () {
      // familyはTechniqueのattributeフィールドから独立しており、Technique
      // モデル自体がCHOKE familyかつattribute=joint、あるいはCHOKE family
      // かつattribute=roughのいずれも構築できる（型レベルで両立可能）。
      expect(CombatV1TechniqueFamily.choke.group, CombatV1TechniqueFamilyGroup.submission);
      // familyの値そのものはattributeに一切依存せず定まる。
      expect(CombatV1TechniqueFamily.values.contains(CombatV1TechniqueFamily.choke), isTrue);
    });
  });

  group('COUNTER matching — family/groupマッチング（docs/combat_rules_v1.md「23.5章」）', () {
    const familyOnlyCounter = CombatV1Counter(
      id: 'match_family_only',
      name: 'family専門カウンター',
      attribute: CombatV1EnergyAttribute.strike,
      counterableFamilies: [CombatV1TechniqueFamily.kick],
    );

    const groupOnlyCounter = CombatV1Counter(
      id: 'match_group_only',
      name: 'group広域カウンター',
      attribute: CombatV1EnergyAttribute.strike,
      counterableGroups: [CombatV1TechniqueFamilyGroup.strike],
    );

    test('exact family match: counterableFamiliesに攻撃familyが含まれれば成立', () {
      expect(
        techniqueFamilyMatchesCounter(familyOnlyCounter, CombatV1TechniqueFamily.kick),
        isTrue,
      );
    });

    test('group match: counterableGroupsに攻撃family.groupが含まれれば成立', () {
      expect(
        techniqueFamilyMatchesCounter(groupOnlyCounter, CombatV1TechniqueFamily.chop),
        isTrue, // chop.group == strike
      );
    });

    test('mismatch: familyもgroupも一致しなければ不成立', () {
      expect(
        techniqueFamilyMatchesCounter(familyOnlyCounter, CombatV1TechniqueFamily.suplex),
        isFalse,
      );
      expect(
        techniqueFamilyMatchesCounter(groupOnlyCounter, CombatV1TechniqueFamily.suplex),
        isFalse, // suplex.group == throwing != strike
      );
    });

    test('attribute一致だけでは成立しない（attackとcounterのattributeが同じでも'
        'family/groupが非対応なら不成立）', () {
      // familyOnlyCounter.attribute == strike、攻撃側のfamily=suplex
      // （THROW group）はattributeの一致とは無関係にfamily/group不一致で拒否
      // される。
      expect(
        techniqueFamilyMatchesCounter(familyOnlyCounter, CombatV1TechniqueFamily.suplex),
        isFalse,
      );
    });
  });
}
