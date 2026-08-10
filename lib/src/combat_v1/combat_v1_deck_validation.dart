/// Deck Definition validation（docs/combat_rules_v1.md 3・4章、Phase 2）。
///
/// UI／将来のDeck Builder／Engine.startのいずれからも呼べる読み取り専用API
/// として設計する。エラーは`code`（enum）で機械判定でき、`message`は
/// ログ・簡易UI用の付随情報に留める（UI用日本語文字列とDomainルールを
/// 強く結合しすぎないため、docs/combat_rules_v1.md 13章）。
library;

import 'combat_v1_counter.dart';
import 'combat_v1_deck.dart';
import 'combat_v1_enums.dart';
import 'combat_v1_rules_config.dart';
import 'combat_v1_technique.dart';

/// TECHNIQUE／COUNTER両方のカード定義を横断参照するための薄いラッパー
/// （Phase 4でコメントを更新。Catalog validationとの責務分離は
/// docs/combat_rules_v1.md「23.6章」参照）。
///
/// `CombatV1Engine`（`combat_v1_engine.dart`）・`validateDeck`
/// （Deck validation）・`validateCatalog`（Catalog validation、
/// `combat_v1_catalog_validation.dart`）が共通して使う、cardId存在確認・
/// category一致確認・Technique/Counter定義lookupのための横断ビュー。
/// 責務はlookupに留め、戦闘resolutionや検証ロジックそのものは持たせない
/// （巨大なRepositoryへ肥大化させない、docs/combat_rules_v1.md
/// 「10-5」）。
class CombatV1CardCatalog {
  const CombatV1CardCatalog({required this.techniques, required this.counters});

  final Map<String, CombatV1Technique> techniques;
  final Map<String, CombatV1Counter> counters;

  bool containsCardId(String cardId) =>
      techniques.containsKey(cardId) || counters.containsKey(cardId);

  /// [cardId] のカード定義上の正しいカテゴリ。存在しない場合はnull。
  CombatV1CardCategory? categoryOf(String cardId) {
    final technique = techniques[cardId];
    if (technique != null) return technique.category;
    if (counters.containsKey(cardId)) return CombatV1CardCategory.counter;
    return null;
  }
}

/// Deck validationのエラー種別。UIやログでの機械判定に使う。
enum CombatV1DeckValidationErrorCode {
  /// デッキ合計枚数が規定と異なる。
  totalCountMismatch,

  /// カテゴリ別枚数が規定と異なる。
  categoryCountMismatch,

  /// instanceIdが重複している。
  duplicateInstanceId,

  /// 参照しているcardIdがカタログに存在しない。
  unknownCardId,

  /// DeckEntry.categoryと参照先カード定義のcategoryが一致しない
  /// （COUNTERとTECHNIQUEの誤分類もこれに含まれる）。
  categoryMismatch,

  /// 同名カード枚数が上限を超えている。
  sameNameLimitExceeded,

  /// [validateDeck]の`wrestlerId`引数が非nullで、かつ
  /// [CombatV1DeckDefinition.wrestlerId]と一致しない（そのデッキが
  /// 渡された`wrestlerId`のwrestler向けに作られたものではない）。
  wrestlerMismatch,
}

/// Deck validationの1件のエラー。
class CombatV1DeckValidationError {
  const CombatV1DeckValidationError({required this.code, required this.message});

  final CombatV1DeckValidationErrorCode code;

  /// 人間可読な説明（ログ・簡易UI用）。
  final String message;

  @override
  String toString() => message;
}

/// [validateDeck] の結果。複数のエラーをまとめて返せる（docs/combat_rules_v1.md
/// 4章）。
class CombatV1DeckValidationResult {
  const CombatV1DeckValidationResult(this.errors);

  final List<CombatV1DeckValidationError> errors;

  bool get isValid => errors.isEmpty;
}

/// [deck] が正式なCombat Ver.1のデッキルールに一致するか検証する
/// （docs/combat_rules_v1.md 3章「30枚デッキ構成」・4章「Deck Definition
/// validation」）。
///
/// 検証項目:
/// - 合計枚数（[CombatV1RulesConfig.deckComposition]の`total`）
/// - カテゴリ別枚数（NORMAL/SIGNATURE/FINISHER/COUNTER）
/// - instanceIdの重複なし
/// - 存在しないcardIdを参照していないこと
/// - DeckEntry.categoryと参照先カード定義のcategoryが一致すること
///   （COUNTERとTECHNIQUEの誤分類の防止を含む）
/// - 同名カード枚数がカテゴリ別上限（[CombatV1RulesConfig.sameNameLimitFor]）
///   以内であること
/// - [wrestlerId]が非nullの場合、[CombatV1DeckDefinition.wrestlerId]と
///   一致すること（Phase 10B Codexレビュー指摘対応。あるwrestler向けの
///   デッキが別のwrestlerへ渡される取り違えを検出する。デフォルトは`null`
///   ＝チェックをスキップし、wrestlerとの対応を検証する必要がない既存の
///   呼び出し元・fixtureベースのテストは無変更で動作し続ける）
///
/// UI／Deck Builder／[CombatV1Engine.start] のいずれからも呼べる読み取り
/// 専用APIとする。
CombatV1DeckValidationResult validateDeck(
  CombatV1DeckDefinition deck, {
  required CombatV1CardCatalog catalog,
  required CombatV1RulesConfig rules,
  String? wrestlerId,
}) {
  final errors = <CombatV1DeckValidationError>[];
  final composition = rules.deckComposition;

  if (wrestlerId != null && deck.wrestlerId != wrestlerId) {
    errors.add(
      CombatV1DeckValidationError(
        code: CombatV1DeckValidationErrorCode.wrestlerMismatch,
        message: 'このデッキは wrestlerId=$wrestlerId 向けではありません'
            '（デッキが宣言するwrestlerId: ${deck.wrestlerId}）',
      ),
    );
  }

  if (deck.size != composition.total) {
    errors.add(
      CombatV1DeckValidationError(
        code: CombatV1DeckValidationErrorCode.totalCountMismatch,
        message: 'デッキ合計枚数は${composition.total}枚である必要があります'
            '（現在${deck.size}枚）',
      ),
    );
  }

  for (final category in CombatV1CardCategory.values) {
    final expected = composition.countFor(category);
    final actual = deck.countOf(category);
    if (actual != expected) {
      errors.add(
        CombatV1DeckValidationError(
          code: CombatV1DeckValidationErrorCode.categoryCountMismatch,
          message: '${category.name}は$expected枚である必要があります'
              '（現在$actual枚）',
        ),
      );
    }
  }

  final seenInstanceIds = <String>{};
  for (final entry in deck.entries) {
    if (!seenInstanceIds.add(entry.instanceId)) {
      errors.add(
        CombatV1DeckValidationError(
          code: CombatV1DeckValidationErrorCode.duplicateInstanceId,
          message: 'instanceIdが重複しています: ${entry.instanceId}',
        ),
      );
    }
  }

  for (final entry in deck.entries) {
    final definedCategory = catalog.categoryOf(entry.cardId);
    if (definedCategory == null) {
      errors.add(
        CombatV1DeckValidationError(
          code: CombatV1DeckValidationErrorCode.unknownCardId,
          message: '存在しないcardIdを参照しています: ${entry.cardId}',
        ),
      );
      continue;
    }
    if (definedCategory != entry.category) {
      errors.add(
        CombatV1DeckValidationError(
          code: CombatV1DeckValidationErrorCode.categoryMismatch,
          message: '${entry.cardId}のカテゴリが一致しません'
              '（DeckEntry: ${entry.category.name}、カード定義: '
              '${definedCategory.name}）',
        ),
      );
    }
  }

  final countsByCardId = <String, int>{};
  for (final entry in deck.entries) {
    countsByCardId[entry.cardId] = (countsByCardId[entry.cardId] ?? 0) + 1;
  }
  for (final cardEntry in countsByCardId.entries) {
    final cardId = cardEntry.key;
    final count = cardEntry.value;
    final category = catalog.categoryOf(cardId);
    if (category == null) continue; // 既にunknownCardIdとして報告済み。
    final limit = rules.sameNameLimitFor(category);
    if (count > limit) {
      errors.add(
        CombatV1DeckValidationError(
          code: CombatV1DeckValidationErrorCode.sameNameLimitExceeded,
          message: '$cardIdは同名最大$limit枚までです（現在$count枚）',
        ),
      );
    }
  }

  return CombatV1DeckValidationResult(errors);
}
