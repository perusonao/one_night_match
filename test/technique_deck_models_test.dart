import 'package:flutter_test/flutter_test.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_models.dart';
import 'package:one_night_match/src/technique_deck/technique_deck_validation.dart';
import 'package:one_night_match/src/wrestler_editor/models.dart' show MoveAttribute;

void main() {
  group('enum: 文字列変換', () {
    test('正常な文字列は対応する値へ変換される', () {
      expect(
        enumOrDefault(TechniqueCardCategory.values, 'signature', TechniqueCardCategory.normal),
        TechniqueCardCategory.signature,
      );
      expect(
        enumOrDefault(TechniqueDeckCardType.values, 'reversal', TechniqueDeckCardType.technique),
        TechniqueDeckCardType.reversal,
      );
      expect(
        enumOrDefault(WrestlerPosture.values, 'down', WrestlerPosture.stand),
        WrestlerPosture.down,
      );
      expect(
        enumOrDefault(TechniqueTargetState.values, 'stand', TechniqueTargetState.any),
        TechniqueTargetState.stand,
      );
    });

    test('未知の文字列はフォールバック値へ安全に変換される', () {
      expect(
        enumOrDefault(TechniqueCardCategory.values, 'unknown_value', TechniqueCardCategory.normal),
        TechniqueCardCategory.normal,
      );
      expect(
        enumOrDefault(TechniqueCardCategory.values, null, TechniqueCardCategory.normal),
        TechniqueCardCategory.normal,
      );
      expect(
        enumOrDefault(TechniqueCardCategory.values, 42, TechniqueCardCategory.normal),
        TechniqueCardCategory.normal,
      );
    });

    test('WrestlerPostureの表示ラベル', () {
      expect(WrestlerPosture.stand.displayLabel, 'スタンド');
      expect(WrestlerPosture.down.displayLabel, 'ダウン');
      expect(WrestlerPosture.fatigued.displayLabel, '疲労');
    });
  });

  group('TechniqueDeckResourceMode', () {
    test('既定値は現行モードのまま自動選択されない想定のdisabled', () {
      // enumの宣言順で最初の値がdisabledであることを確認
      // （既定値として使われる想定の値）。
      expect(TechniqueDeckResourceMode.values.first, TechniqueDeckResourceMode.disabled);
    });
  });

  group('TechniqueDeckTechniqueCard', () {
    TechniqueDeckTechniqueCard fullCard() => const TechniqueDeckTechniqueCard(
      id: 'td_akari_dropkick',
      name: '紅蓮ドロップキック',
      category: TechniqueCardCategory.signature,
      attribute: MoveAttribute.strike,
      allowedWrestlerIds: ['wrestler_akari'],
      minimumLevel: 2,
      attackEnergyCost: {MoveAttribute.strike: 2},
      reversalEnergyCost: {MoveAttribute.counter: 1},
      power: 14,
      heatDelta: 4,
      targetState: TechniqueTargetState.stand,
      causesDown: true,
      hasPinEffect: true,
      hasSubmissionEffect: false,
      hasFinisherEffect: false,
      kickOutThreshold: 20,
      kickOutHpRate: 0.5,
      giveUpThreshold: 15,
      giveUpHpCost: 10,
      downBonusPower: 6,
      finisherRequirements: {'minimumHeat': 40},
      description: 'テスト用固有技',
      sourceMoveId: 'akari_dropkick',
    );

    test('全項目のJSON往復', () {
      final card = fullCard();
      final round = TechniqueDeckTechniqueCard.fromJson(card.toJson());
      expect(round, card);
    });

    test('最小JSONの読み込み（欠落項目は既定値で補完）', () {
      final card = TechniqueDeckTechniqueCard.fromJson(const {
        'id': 'td_min',
        'name': '最小技',
      });
      expect(card.id, 'td_min');
      expect(card.name, '最小技');
      expect(card.category, TechniqueCardCategory.normal);
      expect(card.attribute, MoveAttribute.strike);
      expect(card.allowedWrestlerIds, isEmpty);
      expect(card.minimumLevel, 1);
      expect(card.attackEnergyCost, {for (final a in MoveAttribute.values) a: 0});
      expect(card.reversalEnergyCost, {for (final a in MoveAttribute.values) a: 0});
      expect(card.power, 0);
      expect(card.heatDelta, 0);
      expect(card.targetState, TechniqueTargetState.any);
      expect(card.causesDown, isFalse);
      expect(card.hasPinEffect, isFalse);
      expect(card.hasSubmissionEffect, isFalse);
      expect(card.hasFinisherEffect, isFalse);
      expect(card.kickOutThreshold, isNull);
      expect(card.kickOutHpRate, isNull);
      expect(card.giveUpThreshold, isNull);
      expect(card.giveUpHpCost, isNull);
      expect(card.downBonusPower, isNull);
      expect(card.finisherRequirements, isEmpty);
      expect(card.description, '');
      expect(card.sourceMoveId, isNull);
    });

    test('デフォルトコンストラクタの既定値（7章の指定通り）', () {
      const card = TechniqueDeckTechniqueCard(
        id: 'x',
        name: 'x',
        attribute: MoveAttribute.strike,
      );
      expect(card.category, TechniqueCardCategory.normal);
      expect(card.allowedWrestlerIds, const []);
      expect(card.minimumLevel, 1);
      expect(card.attackEnergyCost, const {});
      expect(card.reversalEnergyCost, const {});
      expect(card.power, 0);
      expect(card.heatDelta, 0);
      expect(card.targetState, TechniqueTargetState.any);
      expect(card.causesDown, isFalse);
      expect(card.hasPinEffect, isFalse);
      expect(card.hasSubmissionEffect, isFalse);
      expect(card.hasFinisherEffect, isFalse);
      expect(card.kickOutThreshold, isNull);
      expect(card.kickOutHpRate, isNull);
      expect(card.giveUpThreshold, isNull);
      expect(card.giveUpHpCost, isNull);
      expect(card.downBonusPower, isNull);
      expect(card.finisherRequirements, const {});
      expect(card.description, '');
      expect(card.sourceMoveId, isNull);
    });

    test('不正なエネルギー値（負数）は0へ正規化される', () {
      final card = TechniqueDeckTechniqueCard.fromJson({
        'id': 'td_neg',
        'name': '不正コスト技',
        'attackEnergyCost': {'strike': -3, 'throwMove': 2},
        'reversalEnergyCost': {'counter': -1},
      });
      expect(card.attackEnergyCost[MoveAttribute.strike], 0);
      expect(card.attackEnergyCost[MoveAttribute.throwMove], 2);
      expect(card.reversalEnergyCost[MoveAttribute.counter], 0);
    });

    test('未知の属性キーはJSON読み込み時に無視される', () {
      final card = TechniqueDeckTechniqueCard.fromJson({
        'id': 'td_unknown_attr',
        'name': '未知属性技',
        'attackEnergyCost': {'strike': 1, 'unknownAttr': 5},
      });
      expect(card.attackEnergyCost[MoveAttribute.strike], 1);
      // 未知キーはMoveAttribute.valuesに存在しないため無視される
      // （_costMapFromJsonはMoveAttribute.valuesを基準に走査するため安全）。
    });

    test('数値型の不整合（文字列が入る等）でもクラッシュせず既定値になる', () {
      expect(
        () => TechniqueDeckTechniqueCard.fromJson({
          'id': 'td_bad_type',
          'name': '型不正技',
          'minimumLevel': 'not_a_number',
          'power': 'also_not_a_number',
        }),
        returnsNormally,
      );
      final card = TechniqueDeckTechniqueCard.fromJson({
        'id': 'td_bad_type',
        'name': '型不正技',
        'minimumLevel': 'not_a_number',
        'power': 'also_not_a_number',
      });
      expect(card.minimumLevel, 1);
      expect(card.power, 0);
    });

    test('nullable項目（kickOutThreshold等）は未設定時にnull', () {
      final card = TechniqueDeckTechniqueCard.fromJson(const {
        'id': 'td_nullable',
        'name': 'nullableテスト',
      });
      expect(card.kickOutThreshold, isNull);
      expect(card.kickOutHpRate, isNull);
      expect(card.giveUpThreshold, isNull);
      expect(card.giveUpHpCost, isNull);
      expect(card.downBonusPower, isNull);
      expect(card.sourceMoveId, isNull);
    });

    test('copyWith: 通常のフィールド更新', () {
      final card = fullCard();
      final updated = card.copyWith(power: 30, name: '改名後');
      expect(updated.power, 30);
      expect(updated.name, '改名後');
      expect(updated.id, card.id);
    });

    test('copyWith: nullable項目へ明示的にnullをセットできる', () {
      final card = fullCard();
      final updated = card.copyWith(kickOutThreshold: null, sourceMoveId: null);
      expect(updated.kickOutThreshold, isNull);
      expect(updated.sourceMoveId, isNull);
      // 未指定の場合は既存値を保持する。
      final untouched = card.copyWith(power: 99);
      expect(untouched.kickOutThreshold, card.kickOutThreshold);
      expect(untouched.sourceMoveId, card.sourceMoveId);
    });

    test('equality: 同じ内容なら等しい、異なれば等しくない', () {
      final a = fullCard();
      final b = fullCard();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      final c = fullCard().copyWith(power: 999);
      expect(a == c, isFalse);
    });
  });

  group('TechniqueEnergyCard', () {
    test('JSON往復', () {
      const card = TechniqueEnergyCard(
        id: 'energy_strike_1',
        attribute: MoveAttribute.strike,
        name: '打エネルギー',
      );
      final round = TechniqueEnergyCard.fromJson(card.toJson());
      expect(round, card);
    });

    test('属性の復元', () {
      final card = TechniqueEnergyCard.fromJson(const {
        'id': 'e1',
        'attribute': 'rough',
        'name': 'ラフエネルギー',
      });
      expect(card.attribute, MoveAttribute.rough);
    });

    test('未知の属性文字列は安全にフォールバックする', () {
      final card = TechniqueEnergyCard.fromJson(const {
        'id': 'e1',
        'attribute': 'not_a_real_attribute',
        'name': '不正属性',
      });
      expect(card.attribute, MoveAttribute.strike);
    });

    test('copyWith', () {
      const card = TechniqueEnergyCard(
        id: 'e1',
        attribute: MoveAttribute.strike,
        name: '打',
      );
      final updated = card.copyWith(name: '投');
      expect(updated.name, '投');
      expect(updated.id, 'e1');
    });
  });

  group('TechniqueDefenseCard', () {
    test('type別のJSON往復', () {
      for (final type in TechniqueDeckCardType.values) {
        final card = TechniqueDefenseCard(
          id: 'defense_${type.name}',
          name: type.name,
          type: type,
          description: 'desc',
          requirements: const {'minLevel': 2},
          effects: const {'note': 'unresolved'},
        );
        final round = TechniqueDefenseCard.fromJson(card.toJson());
        expect(round, card, reason: 'type=$type');
      }
    });

    test('未知のtypeは安全にescapeへフォールバックする', () {
      final card = TechniqueDefenseCard.fromJson(const {
        'id': 'd1',
        'name': '不明カード',
        'type': 'totally_unknown_type',
      });
      expect(card.type, TechniqueDeckCardType.escape);
    });
  });

  group('TechniqueDeckCardCatalog', () {
    final catalog = TechniqueDeckCardCatalog(
      techniques: [
        const TechniqueDeckTechniqueCard(
          id: 't1',
          name: '技1',
          category: TechniqueCardCategory.normal,
          attribute: MoveAttribute.strike,
        ),
        const TechniqueDeckTechniqueCard(
          id: 't2',
          name: '技2',
          category: TechniqueCardCategory.signature,
          attribute: MoveAttribute.throwMove,
        ),
      ],
      energies: const [
        TechniqueEnergyCard(id: 'e1', attribute: MoveAttribute.strike, name: '打'),
      ],
      defenseCards: const [
        TechniqueDefenseCard(id: 'd1', name: 'エスケープ', type: TechniqueDeckCardType.escape),
      ],
    );

    test('ID検索', () {
      expect(catalog.findTechniqueById('t1')?.name, '技1');
      expect(catalog.findTechniqueById('nope'), isNull);
      expect(catalog.findEnergyById('e1')?.name, '打');
      expect(catalog.findDefenseCardById('d1')?.name, 'エスケープ');
    });

    test('種別検索', () {
      expect(catalog.techniquesByCategory(TechniqueCardCategory.signature).map((c) => c.id), ['t2']);
      expect(catalog.defenseCardsByType(TechniqueDeckCardType.escape).map((c) => c.id), ['d1']);
    });

    test('重複ID検出', () {
      final dup = TechniqueDeckCardCatalog(
        techniques: [
          const TechniqueDeckTechniqueCard(id: 'dup', name: 'A', attribute: MoveAttribute.strike),
        ],
        energies: const [
          TechniqueEnergyCard(id: 'dup', attribute: MoveAttribute.strike, name: 'B'),
        ],
      );
      expect(dup.findDuplicateIds(), ['dup']);
      expect(catalog.findDuplicateIds(), isEmpty);
    });

    test('カタログのJSON往復', () {
      final round = TechniqueDeckCardCatalog.fromJson(catalog.toJson());
      expect(round.techniques.length, catalog.techniques.length);
      expect(round.energies.length, catalog.energies.length);
      expect(round.defenseCards.length, catalog.defenseCards.length);
    });
  });

  group('TechniqueDeckWrestlerProfile', () {
    test('JSON往復', () {
      const profile = TechniqueDeckWrestlerProfile(
        wrestlerId: 'wrestler_akari',
        recoveryPower: 8,
        allowedSignatureCardIds: ['td_akari_dropkick'],
        allowedFinisherCardIds: ['td_akari_german'],
      );
      final round = TechniqueDeckWrestlerProfile.fromJson(profile.toJson());
      expect(round, profile);
    });

    test('既定値', () {
      const profile = TechniqueDeckWrestlerProfile(wrestlerId: 'w1');
      expect(profile.recoveryPower, 0);
      expect(profile.allowedSignatureCardIds, const []);
      expect(profile.allowedFinisherCardIds, const []);
    });

    test('回復力の保持', () {
      final profile = TechniqueDeckWrestlerProfile.fromJson(const {
        'wrestlerId': 'w1',
        'recoveryPower': 12,
      });
      expect(profile.recoveryPower, 12);
    });
  });

  group('Validation', () {
    test('負数コストはエラーとして検出される', () {
      const card = TechniqueDeckTechniqueCard(
        id: 't1',
        name: '不正技',
        attribute: MoveAttribute.strike,
        attackEnergyCost: {MoveAttribute.strike: -1},
      );
      final issues = validateTechniqueCard(card);
      expect(
        issues.any((i) => i.code == 'negativeAttackEnergyCost' && i.severity == ValidationSeverity.error),
        isTrue,
      );
    });

    test('不正なHP割合(kickOutHpRate)はエラーとして検出される', () {
      const card = TechniqueDeckTechniqueCard(
        id: 't1',
        name: '不正技',
        attribute: MoveAttribute.strike,
        kickOutHpRate: 1.5,
      );
      final issues = validateTechniqueCard(card);
      expect(issues.any((i) => i.code == 'invalidKickOutHpRate'), isTrue);
    });

    test('kickOutHpRateが0.0〜1.0なら問題なし', () {
      const card = TechniqueDeckTechniqueCard(
        id: 't1',
        name: '正常技',
        attribute: MoveAttribute.strike,
        kickOutHpRate: 0.5,
      );
      expect(validateTechniqueCard(card), isEmpty);
    });

    test('重複IDはカタログ検証でエラーとして検出される', () {
      final catalog = TechniqueDeckCardCatalog(
        techniques: [
          const TechniqueDeckTechniqueCard(id: 'dup', name: 'A', attribute: MoveAttribute.strike),
        ],
        energies: const [
          TechniqueEnergyCard(id: 'dup', attribute: MoveAttribute.strike, name: 'B'),
        ],
      );
      final issues = validateCatalog(catalog);
      expect(issues.any((i) => i.code == 'duplicateId' && i.cardId == 'dup'), isTrue);
    });

    test('finisher以外でhasFinisherEffect==trueは警告', () {
      const card = TechniqueDeckTechniqueCard(
        id: 't1',
        name: '矛盾技',
        category: TechniqueCardCategory.normal,
        attribute: MoveAttribute.strike,
        hasFinisherEffect: true,
      );
      final issues = validateTechniqueCard(card);
      expect(
        issues.any((i) =>
            i.code == 'finisherEffectOnNonFinisherCategory' &&
            i.severity == ValidationSeverity.warning),
        isTrue,
      );
    });

    test('finisherカテゴリでhasFinisherEffect==trueは警告なし', () {
      const card = TechniqueDeckTechniqueCard(
        id: 't1',
        name: '正しいフィニッシャー',
        category: TechniqueCardCategory.finisher,
        attribute: MoveAttribute.strike,
        hasFinisherEffect: true,
      );
      final issues = validateTechniqueCard(card);
      expect(issues.any((i) => i.code == 'finisherEffectOnNonFinisherCategory'), isFalse);
    });

    test('IDや名前が空ならエラー', () {
      const card = TechniqueDeckTechniqueCard(id: '', name: '', attribute: MoveAttribute.strike);
      final issues = validateTechniqueCard(card);
      expect(issues.any((i) => i.code == 'emptyId'), isTrue);
      expect(issues.any((i) => i.code == 'emptyName'), isTrue);
    });

    test('レスラープロファイルの回復力負数はエラー', () {
      const profile = TechniqueDeckWrestlerProfile(wrestlerId: 'w1', recoveryPower: -5);
      final issues = validateWrestlerProfile(profile);
      expect(issues.any((i) => i.code == 'negativeRecoveryPower'), isTrue);
    });

    test('妥当なカードはバリデーションエラーなし', () {
      const card = TechniqueDeckTechniqueCard(
        id: 't1',
        name: '正常技',
        attribute: MoveAttribute.strike,
        minimumLevel: 2,
        attackEnergyCost: {MoveAttribute.strike: 2},
        kickOutThreshold: 20,
        kickOutHpRate: 0.5,
        giveUpThreshold: 15,
        giveUpHpCost: 10,
      );
      expect(validateTechniqueCard(card), isEmpty);
    });
  });
}
