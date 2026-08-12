// Combat Ver.1 Playable 2A-3 — Technique / Counter Decision Readability
// pure derivation test（lib/src/combat_v1/playable_ui/combat_v1_playable_technique_traits.dart）。
//
// Widgetを一切構築しない、pure functionのみを対象とするtest。実際の
// Production Catalogに存在する組み合わせ（jack_choke_attack・
// akari_arm_catch・misaki_goda_bomb/driver・reina_ice_lock等）を
// 参考に、代表的なTechnique構成を検証する（無理に存在しない組み合わせは
// 作らない）。

import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_counter.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';
import 'package:one_night_match/src/combat_v1/playable_ui/combat_v1_playable_technique_traits.dart';

import 'combat_v1_playable_ui_test_fixtures.dart';

// ── 代表Technique（Production Catalogの実在組み合わせを参考にした
//    self-contained fixture、combat_v1_playable_1c1_clarity_test.dartと
//    同じ方針） ──────────────────────────────────────────────

/// normal Technique（例: akari_elbow_smash）。
const CombatV1Technique _normalTechnique = CombatV1Technique(
  id: 'test_trait_normal',
  name: 'テストエルボー',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.strike,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
  damage: 10,
  heatGain: 10,
  family: CombatV1TechniqueFamily.elbow,
);

/// Direct PIN技（技全般に付与できる汎用フラグ、`CombatV1Technique.directPin`
/// のdocコメントどおり——Production CatalogにはFINISHER以外での使用例は
/// 無いが、モデル上明示的にサポートされている構成）。
const CombatV1Technique _directPinTechnique = CombatV1Technique(
  id: 'test_trait_direct_pin',
  name: 'テストダイレクトピン技',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.throwing,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 2}),
  damage: 20,
  heatGain: 20,
  family: CombatV1TechniqueFamily.slam,
  directPin: true,
);

/// Submission Hold技（例: akari_arm_catch）。
const CombatV1Technique _submissionHoldTechnique = CombatV1Technique(
  id: 'test_trait_submission_hold',
  name: 'テストアームキャッチ',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.joint,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 1}),
  damage: 10,
  heatGain: 10,
  family: CombatV1TechniqueFamily.armbar,
  submissionHold: true,
);

/// ROUGH Technique（例: jack_choke_attack）。
const CombatV1Technique _roughTechnique = CombatV1Technique(
  id: 'test_trait_rough',
  name: 'テストチョーク攻撃',
  category: CombatV1CardCategory.normal,
  attribute: CombatV1EnergyAttribute.rough,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.rough: 1}),
  damage: 10,
  heatGain: 20,
  family: CombatV1TechniqueFamily.choke,
);

/// normal FINISHER（例: misaki_goda_driver）。
const CombatV1Technique _normalFinisher = CombatV1Technique(
  id: 'test_trait_finisher_normal',
  name: 'テスト通常フィニッシャー',
  category: CombatV1CardCategory.finisher,
  attribute: CombatV1EnergyAttribute.throwing,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 4}),
  damage: 40,
  heatGain: 50,
  family: CombatV1TechniqueFamily.driver,
  finisherType: CombatV1FinisherType.normal,
);

/// Direct PIN FINISHER（例: misaki_goda_bomb）。FINISHERのcategoryでは
/// technique自身の`directPin`は無視され、`finisherType`が優先される
/// ——[_directPinFinisherWithConflictingFlag]で優先順位そのものを検証する
/// ため、ここでは`directPin: false`のまま構築する。
const CombatV1Technique _directPinFinisher = CombatV1Technique(
  id: 'test_trait_finisher_direct_pin',
  name: 'テストダイレクトピンフィニッシャー',
  category: CombatV1CardCategory.finisher,
  attribute: CombatV1EnergyAttribute.throwing,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 3}),
  damage: 30,
  heatGain: 40,
  family: CombatV1TechniqueFamily.powerbomb,
  finisherType: CombatV1FinisherType.directPin,
);

/// Submission FINISHER（例: reina_ice_lock）。
const CombatV1Technique _submissionFinisher = CombatV1Technique(
  id: 'test_trait_finisher_submission',
  name: 'テストサブミッションフィニッシャー',
  category: CombatV1CardCategory.finisher,
  attribute: CombatV1EnergyAttribute.joint,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 3}),
  damage: 30,
  heatGain: 40,
  family: CombatV1TechniqueFamily.legLock,
  finisherType: CombatV1FinisherType.submission,
);

/// jack_kurocho_driver相当（ROUGH属性 かつ Direct PIN FINISHER）——
/// ROUGHとFINISHER resolutionが同時に成立する実在の組み合わせ。
const CombatV1Technique _roughDirectPinFinisher = CombatV1Technique(
  id: 'test_trait_rough_finisher',
  name: 'テストラフフィニッシャー',
  category: CombatV1CardCategory.finisher,
  attribute: CombatV1EnergyAttribute.rough,
  energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.rough: 3}),
  damage: 30,
  heatGain: 50,
  family: CombatV1TechniqueFamily.driver,
  finisherType: CombatV1FinisherType.directPin,
);

void main() {
  group('Effective DIRECT PIN / SUBMISSION（優先順位ルール）', () {
    test('normal Techniqueはどちらもfalse', () {
      expect(
        combatV1PlayableTechniqueHasEffectiveDirectPin(_normalTechnique),
        isFalse,
      );
      expect(
        combatV1PlayableTechniqueHasEffectiveSubmissionHold(_normalTechnique),
        isFalse,
      );
    });

    test('directPin: trueの非FINISHER技はtrue', () {
      expect(
        combatV1PlayableTechniqueHasEffectiveDirectPin(_directPinTechnique),
        isTrue,
      );
      expect(
        combatV1PlayableTechniqueHasEffectiveSubmissionHold(
          _directPinTechnique,
        ),
        isFalse,
      );
    });

    test('submissionHold: trueの非FINISHER技はtrue', () {
      expect(
        combatV1PlayableTechniqueHasEffectiveSubmissionHold(
          _submissionHoldTechnique,
        ),
        isTrue,
      );
      expect(
        combatV1PlayableTechniqueHasEffectiveDirectPin(
          _submissionHoldTechnique,
        ),
        isFalse,
      );
    });

    test('normal FINISHERはどちらもfalse', () {
      expect(
        combatV1PlayableTechniqueHasEffectiveDirectPin(_normalFinisher),
        isFalse,
      );
      expect(
        combatV1PlayableTechniqueHasEffectiveSubmissionHold(_normalFinisher),
        isFalse,
      );
    });

    test('Direct PIN FINISHERはfinisherType経由でtrueになる', () {
      expect(
        combatV1PlayableTechniqueHasEffectiveDirectPin(_directPinFinisher),
        isTrue,
      );
      expect(
        combatV1PlayableTechniqueHasEffectiveSubmissionHold(
          _directPinFinisher,
        ),
        isFalse,
      );
    });

    test('Submission FINISHERはfinisherType経由でtrueになる', () {
      expect(
        combatV1PlayableTechniqueHasEffectiveSubmissionHold(
          _submissionFinisher,
        ),
        isTrue,
      );
      expect(
        combatV1PlayableTechniqueHasEffectiveDirectPin(_submissionFinisher),
        isFalse,
      );
    });

    test(
      'FINISHERはtechnique自身のdirectPin/submissionHoldフィールドより'
      'finisherTypeが優先される（combat_v1_engine.dart effectiveDirectPin '
      'と同じ優先順位）',
      () {
        // category==finisherかつdirectPin: true・finisherType: submissionの
        // ような矛盾した構成でも、finisherTypeが常に優先されることを
        // 明示的に確認する。
        const conflicting = CombatV1Technique(
          id: 'test_trait_conflicting_finisher',
          name: 'テスト矛盾フィニッシャー',
          category: CombatV1CardCategory.finisher,
          attribute: CombatV1EnergyAttribute.strike,
          energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 3}),
          damage: 30,
          heatGain: 40,
          family: CombatV1TechniqueFamily.lariat,
          directPin: true,
          submissionHold: false,
          finisherType: CombatV1FinisherType.submission,
        );
        expect(
          combatV1PlayableTechniqueHasEffectiveDirectPin(conflicting),
          isFalse,
        );
        expect(
          combatV1PlayableTechniqueHasEffectiveSubmissionHold(conflicting),
          isTrue,
        );
      },
    );
  });

  group('ROUGH', () {
    test('attribute==roughのTechniqueはtrue', () {
      expect(combatV1PlayableTechniqueIsRough(_roughTechnique), isTrue);
    });

    test('attribute!=roughのTechniqueはfalse', () {
      expect(combatV1PlayableTechniqueIsRough(_normalTechnique), isFalse);
    });

    test(
      'ROUGH属性のFINISHER（jack_kurocho_driver相当）はROUGHとFINISHER '
      'resolutionが両方成立する',
      () {
        expect(
          combatV1PlayableTechniqueIsRough(_roughDirectPinFinisher),
          isTrue,
        );
        expect(
          combatV1PlayableTechniqueHasEffectiveDirectPin(
            _roughDirectPinFinisher,
          ),
          isTrue,
        );
      },
    );
  });

  group('Finisher resolution badge label', () {
    test('normalは"FINISHER"のみ', () {
      expect(
        combatV1PlayableFinisherResolutionBadgeLabel(
          CombatV1FinisherType.normal,
        ),
        'FINISHER',
      );
    });

    test('directPinは"FINISHER · PIN"', () {
      expect(
        combatV1PlayableFinisherResolutionBadgeLabel(
          CombatV1FinisherType.directPin,
        ),
        'FINISHER · PIN',
      );
    });

    test('submissionは"FINISHER · SUBMISSION"', () {
      expect(
        combatV1PlayableFinisherResolutionBadgeLabel(
          CombatV1FinisherType.submission,
        ),
        'FINISHER · SUBMISSION',
      );
    });
  });

  group('Pending Attack（Counter応答時）の同じ優先順位ルール', () {
    test('Direct PIN FINISHERの宣言済み攻撃はeffectiveDirectPin==true', () {
      final pending = testPendingAttack(technique: _directPinFinisher);
      expect(
        combatV1PlayablePendingAttackHasEffectiveDirectPin(pending),
        isTrue,
      );
      expect(
        combatV1PlayablePendingAttackHasEffectiveSubmissionHold(pending),
        isFalse,
      );
    });

    test('Submission Holdの宣言済み攻撃（非FINISHER）はeffectiveSubmissionHold==true', () {
      final pending = testPendingAttack(technique: _submissionHoldTechnique);
      expect(
        combatV1PlayablePendingAttackHasEffectiveSubmissionHold(pending),
        isTrue,
      );
    });

    test('ROUGH技の宣言済み攻撃はcombatV1PlayablePendingAttackIsRough==true', () {
      final pending = testPendingAttack(technique: _roughTechnique);
      expect(combatV1PlayablePendingAttackIsRough(pending), isTrue);
    });

    test('通常技の宣言済み攻撃はどのtraitもfalse', () {
      final pending = testPendingAttack(technique: _normalTechnique);
      expect(
        combatV1PlayablePendingAttackHasEffectiveDirectPin(pending),
        isFalse,
      );
      expect(
        combatV1PlayablePendingAttackHasEffectiveSubmissionHold(pending),
        isFalse,
      );
      expect(combatV1PlayablePendingAttackIsRough(pending), isFalse);
    });
  });

  group('SUBMISSION Wording（過剰断定しない、8章）', () {
    test('「今Submissionできる」「これでギブアップ」「この技で勝てる」を含まない', () {
      final detail = combatV1PlayableSubmissionTraitDetail(50);
      expect(detail, isNot(contains('今Submissionできる')));
      expect(detail, isNot(contains('ギブアップ')));
      expect(detail, isNot(contains('この技で勝てる')));
      // 条件（HP閾値）付きの限定表現であることを確認する。
      expect(detail, contains('50'));
      expect(detail, contains('成立後'));
    });
  });

  group('DIRECT PIN Wording（通常PIN legalityと混同しない、9章）', () {
    test('「自動でPINへ」と説明し、通常PIN選択とは別経路であることを明示する', () {
      final detail = combatV1PlayableDirectPinTraitDetail();
      expect(detail, contains('自動でPIN'));
    });
  });

  group('ROUGH Wording（15章の2つの判定基準を区別する）', () {
    test('「使用したターンはPINできない」「成立後は次ターン1枚制限」を両方含む', () {
      final detail = combatV1PlayableRoughTraitDetail();
      expect(detail, contains('PINできなくなります'));
      expect(detail, contains('最大1枚'));
    });
  });

  group('Counter Family Match Label', () {
    final strikeCounter = CombatV1Counter(
      id: 'test_counter_strike',
      name: 'テストストライクカウンター',
      attribute: CombatV1EnergyAttribute.strike,
      counterableFamilies: const [CombatV1TechniqueFamily.elbow],
    );
    final groupCounter = CombatV1Counter(
      id: 'test_counter_group',
      name: 'テストグループカウンター',
      attribute: CombatV1EnergyAttribute.throwing,
      counterableGroups: const [CombatV1TechniqueFamilyGroup.throwing],
    );

    test('family一致の場合はfamily labelを返す', () {
      expect(
        combatV1PlayableCounterFamilyMatchLabel(
          strikeCounter,
          CombatV1TechniqueFamily.elbow,
        ),
        'Elbow',
      );
    });

    test('group一致（family不一致）の場合はgroup labelを返す', () {
      expect(
        combatV1PlayableCounterFamilyMatchLabel(
          groupCounter,
          CombatV1TechniqueFamily.suplex,
        ),
        'THROW group',
      );
    });

    test('一致しない場合はnullを返す', () {
      expect(
        combatV1PlayableCounterFamilyMatchLabel(
          strikeCounter,
          CombatV1TechniqueFamily.suplex,
        ),
        isNull,
      );
    });
  });

  group('Counter Success Meaning（7章「完全無効」semanticsと一致）', () {
    test('trait無しの技はDMG・HEAT・状態変化のみ言及する', () {
      final summary = combatV1PlayableCounterPreventsSummary(
        directPin: false,
        submissionHold: false,
      );
      expect(summary, contains('DMG'));
      expect(summary, contains('HEAT'));
      expect(summary, contains('状態変化'));
      expect(summary, isNot(contains('PIN')));
      expect(summary, isNot(contains('Submission')));
    });

    test('Direct PIN技は自動PINへの移行も防げることを言及する', () {
      final summary = combatV1PlayableCounterPreventsSummary(
        directPin: true,
        submissionHold: false,
      );
      expect(summary, contains('自動PINへの移行'));
    });

    test('Submission Hold技はSubmission移行条件を防げることを言及する', () {
      final summary = combatV1PlayableCounterPreventsSummary(
        directPin: false,
        submissionHold: true,
      );
      expect(summary, contains('Submission'));
    });
  });

  group('Family / Group Display Label', () {
    test('主要familyのlabelがCore enum名と対応する', () {
      expect(
        combatV1PlayableTechniqueFamilyLabel(CombatV1TechniqueFamily.ddt),
        'DDT',
      );
      expect(
        combatV1PlayableTechniqueFamilyLabel(
          CombatV1TechniqueFamily.figureFour,
        ),
        'Figure Four',
      );
    });

    test('全familyグループのlabelが定義されている', () {
      for (final group in CombatV1TechniqueFamilyGroup.values) {
        expect(
          combatV1PlayableTechniqueFamilyGroupLabel(group),
          isNotEmpty,
        );
      }
    });
  });
}
