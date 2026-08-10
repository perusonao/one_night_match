/// Catalog Definition validation（docs/combat_rules_v1.md「23.6.
/// Catalog validation」、Phase 4）。
///
/// `combat_v1_deck_validation.dart`の`validateDeck`はデッキ（30枚構成・
/// category・cardId等）の妥当性を検証するのに対し、本ファイルの
/// [validateCatalog]は`CombatV1CardCatalog`が保持するTechnique/Counter
/// **Definitionそのもの**の整合性を検証する（責務を分離する、
/// docs/combat_rules_v1.md「23.6章」）。
///
/// [CombatV1Technique.family]/[CombatV1TechniqueFamilyGroup]はいずれも
/// 閉じたenumであるため、「unknown family」「unknown group」は型システムが
/// 構築自体を防ぐ（無効な値を持つインスタンスを作れない）。Phase
/// 1〜3の`String? familyId`のような自由文字列と異なり、この種の
/// エラーコードは構造的に到達不能になるため、あえて定義しない
/// （`checkTechniqueLegality`から`notTechnique`reasonCodeを削除したのと
/// 同じ「形骸化したreasonCode／エラーコードを残さない」方針を
/// Catalog validationにも適用する、`combat_v1_engine.dart`参照）。
library;

import 'combat_v1_counter.dart';
import 'combat_v1_deck_validation.dart';
import 'combat_v1_enums.dart';
import 'combat_v1_technique.dart';

/// [validateCatalog]のエラー種別。
enum CombatV1CatalogValidationErrorCode {
  /// [CombatV1Technique.energyCost]が[CombatV1EnergyCost.isValid]でない
  /// （負数のCost、またはwildをCostとして要求している）。
  techniqueInvalidEnergyCost,

  /// [CombatV1Technique.energyCost]の合計が0以下（zero-cost技は禁止、
  /// docs/combat_rules_v1.md「7.2章 CombatV1EnergyCost.total」）。
  techniqueZeroEnergyCost,

  /// [CombatV1Technique.attribute]がwild（技属性にwildは指定できない）。
  techniqueWildAttribute,

  /// [CombatV1Technique.damage]が負数。
  techniqueNegativeDamage,

  /// [CombatV1Technique.heatGain]が負数。
  techniqueNegativeHeatGain,

  /// [CombatV1Counter.attribute]がwild（docs/combat_rules_v1.md「5.2章
  /// COUNTERでの＊(ワイルド)ENERGYの扱い」とは別概念。COUNTERの支払い属性
  /// そのものにwildは指定できない）。
  counterWildAttribute,

  /// [CombatV1Counter.counterableFamilies]・[CombatV1Counter.counterableGroups]
  /// がどちらも空。
  counterEmptyTargets,

  /// [CombatV1Counter.counterableFamilies]内に重複がある。
  counterDuplicateFamily,

  /// [CombatV1Counter.counterableGroups]内に重複がある。
  counterDuplicateGroup,

  /// あるgroupと、そのgroupに完全包含されるfamilyを同時指定している
  /// （例: `counterableGroups: [strike]`かつ`counterableFamilies: [kick]`。
  /// kickはstrikeに含まれるため冗長）。
  counterRedundantGroupAndFamily,

  /// 同一cardIdがTechnique/Counter両方のカタログに定義されている。
  cardIdCollision,

  /// カタログMapのキーと、値である定義の`id`が一致しない。
  catalogKeyIdMismatch,
}

/// [validateCatalog]の1件のエラー。
class CombatV1CatalogValidationError {
  const CombatV1CatalogValidationError({
    required this.code,
    required this.cardId,
    required this.message,
  });

  final CombatV1CatalogValidationErrorCode code;

  /// エラーの原因となったcardId（Map key側で発生した場合はそのkey）。
  final String cardId;

  /// 人間可読な説明（ログ・簡易UI用）。
  final String message;

  @override
  String toString() => message;
}

/// [validateCatalog]の結果。複数のエラーをまとめて返せる。
class CombatV1CatalogValidationResult {
  const CombatV1CatalogValidationResult(this.errors);

  final List<CombatV1CatalogValidationError> errors;

  bool get isValid => errors.isEmpty;
}

/// [catalog]が保持するTechnique/Counter Definitionそのものの整合性を検証
/// する（docs/combat_rules_v1.md「23.6章 Catalog validation」）。
///
/// UI／Deck Builder／[CombatV1Engine.start]のいずれからも呼べる読み取り
/// 専用APIとする（`validateDeck`と同じ設計方針）。
CombatV1CatalogValidationResult validateCatalog(CombatV1CardCatalog catalog) {
  final errors = <CombatV1CatalogValidationError>[];

  for (final entry in catalog.techniques.entries) {
    final key = entry.key;
    final technique = entry.value;

    if (key != technique.id) {
      errors.add(
        CombatV1CatalogValidationError(
          code: CombatV1CatalogValidationErrorCode.catalogKeyIdMismatch,
          cardId: key,
          message: 'techniquesのキー($key)と定義のid(${technique.id})が'
              '一致しません',
        ),
      );
    }

    if (!technique.energyCost.isValid) {
      errors.add(
        CombatV1CatalogValidationError(
          code: CombatV1CatalogValidationErrorCode.techniqueInvalidEnergyCost,
          cardId: key,
          message: '$keyのENERGY COSTが不正です（負数、またはwildを'
              '要求しています）',
        ),
      );
    } else if (technique.energyCost.total <= 0) {
      errors.add(
        CombatV1CatalogValidationError(
          code: CombatV1CatalogValidationErrorCode.techniqueZeroEnergyCost,
          cardId: key,
          message: '$keyのENERGY COST合計が0以下です（zero-cost技は禁止）',
        ),
      );
    }

    if (technique.attribute == CombatV1EnergyAttribute.wild) {
      errors.add(
        CombatV1CatalogValidationError(
          code: CombatV1CatalogValidationErrorCode.techniqueWildAttribute,
          cardId: key,
          message: '$keyのattributeにwildは指定できません',
        ),
      );
    }

    if (technique.damage < 0) {
      errors.add(
        CombatV1CatalogValidationError(
          code: CombatV1CatalogValidationErrorCode.techniqueNegativeDamage,
          cardId: key,
          message: '$keyのdamageが負数です',
        ),
      );
    }

    if (technique.heatGain < 0) {
      errors.add(
        CombatV1CatalogValidationError(
          code: CombatV1CatalogValidationErrorCode.techniqueNegativeHeatGain,
          cardId: key,
          message: '$keyのheatGainが負数です',
        ),
      );
    }

    if (catalog.counters.containsKey(key)) {
      errors.add(
        CombatV1CatalogValidationError(
          code: CombatV1CatalogValidationErrorCode.cardIdCollision,
          cardId: key,
          message: '$keyがTechnique/Counter両方のカタログに定義されています',
        ),
      );
    }
  }

  for (final entry in catalog.counters.entries) {
    final key = entry.key;
    final counter = entry.value;

    if (key != counter.id) {
      errors.add(
        CombatV1CatalogValidationError(
          code: CombatV1CatalogValidationErrorCode.catalogKeyIdMismatch,
          cardId: key,
          message: 'countersのキー($key)と定義のid(${counter.id})が'
              '一致しません',
        ),
      );
    }

    if (counter.attribute == CombatV1EnergyAttribute.wild) {
      errors.add(
        CombatV1CatalogValidationError(
          code: CombatV1CatalogValidationErrorCode.counterWildAttribute,
          cardId: key,
          message: '$keyのattributeにwildは指定できません',
        ),
      );
    }

    if (counter.counterableFamilies.isEmpty &&
        counter.counterableGroups.isEmpty) {
      errors.add(
        CombatV1CatalogValidationError(
          code: CombatV1CatalogValidationErrorCode.counterEmptyTargets,
          cardId: key,
          message: '$keyはcounterableFamilies/counterableGroupsが'
              'どちらも空です',
        ),
      );
    }

    if (counter.counterableFamilies.length !=
        counter.counterableFamilies.toSet().length) {
      errors.add(
        CombatV1CatalogValidationError(
          code: CombatV1CatalogValidationErrorCode.counterDuplicateFamily,
          cardId: key,
          message: '$keyのcounterableFamiliesに重複があります',
        ),
      );
    }

    if (counter.counterableGroups.length !=
        counter.counterableGroups.toSet().length) {
      errors.add(
        CombatV1CatalogValidationError(
          code: CombatV1CatalogValidationErrorCode.counterDuplicateGroup,
          cardId: key,
          message: '$keyのcounterableGroupsに重複があります',
        ),
      );
    }

    final groupSet = counter.counterableGroups.toSet();
    for (final family in counter.counterableFamilies.toSet()) {
      if (groupSet.contains(family.group)) {
        errors.add(
          CombatV1CatalogValidationError(
            code: CombatV1CatalogValidationErrorCode
                .counterRedundantGroupAndFamily,
            cardId: key,
            message: '$keyは${family.group.name}groupと、それに包含される'
                '${family.name}familyを同時指定しています（冗長）',
          ),
        );
      }
    }

    // cardIdCollision（techniques側にも同じcardIdがある場合）はtechniques
    // 側のループで検出済みのため、ここでは重複して追加しない。
  }

  return CombatV1CatalogValidationResult(errors);
}
