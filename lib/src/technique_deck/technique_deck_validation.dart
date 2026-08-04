import 'technique_deck_models.dart';

/// Technique Deck Rules Phase 1: 軽量バリデーション。
///
/// Phase 2で扱うデッキ枚数・同名制限（docs/design/technique_deck_
/// open_questions.md 5番）は今回実装しない。ここでは個々のカード定義が
/// 自己矛盾していないか（負のコスト、範囲外の比率など）のみを検査する。

enum ValidationSeverity { error, warning }

class TechniqueDeckValidationIssue {
  const TechniqueDeckValidationIssue({
    required this.severity,
    required this.code,
    required this.message,
    this.cardId,
  });

  final ValidationSeverity severity;

  /// プログラムから判定しやすい短いコード（例: `emptyId`, `negativeCost`）。
  final String code;
  final String message;
  final String? cardId;

  @override
  String toString() =>
      '[${severity.name}] $code${cardId != null ? ' ($cardId)' : ''}: $message';
}

List<TechniqueDeckValidationIssue> _issuesFor({
  required String? id,
  required String? name,
}) {
  final issues = <TechniqueDeckValidationIssue>[];
  if (id == null || id.isEmpty) {
    issues.add(const TechniqueDeckValidationIssue(
      severity: ValidationSeverity.error,
      code: 'emptyId',
      message: 'IDが空です。',
    ));
  }
  if (name == null || name.isEmpty) {
    issues.add(TechniqueDeckValidationIssue(
      severity: ValidationSeverity.error,
      code: 'emptyName',
      message: '名前が空です。',
      cardId: id,
    ));
  }
  return issues;
}

/// [TechniqueDeckTechniqueCard] 単体の軽量バリデーション。
List<TechniqueDeckValidationIssue> validateTechniqueCard(
  TechniqueDeckTechniqueCard card,
) {
  final issues = _issuesFor(id: card.id, name: card.name);

  if (card.minimumLevel < 1) {
    issues.add(TechniqueDeckValidationIssue(
      severity: ValidationSeverity.error,
      code: 'invalidMinimumLevel',
      message: 'minimumLevelは1以上である必要があります（実際: ${card.minimumLevel}）。',
      cardId: card.id,
    ));
  }
  for (final entry in card.attackEnergyCost.entries) {
    if (entry.value < 0) {
      issues.add(TechniqueDeckValidationIssue(
        severity: ValidationSeverity.error,
        code: 'negativeAttackEnergyCost',
        message: 'attackEnergyCost[${entry.key.name}]が負数です（実際: ${entry.value}）。',
        cardId: card.id,
      ));
    }
  }
  for (final entry in card.reversalEnergyCost.entries) {
    if (entry.value < 0) {
      issues.add(TechniqueDeckValidationIssue(
        severity: ValidationSeverity.error,
        code: 'negativeReversalEnergyCost',
        message:
            'reversalEnergyCost[${entry.key.name}]が負数です（実際: ${entry.value}）。',
        cardId: card.id,
      ));
    }
  }
  final kickOutHpRate = card.kickOutHpRate;
  if (kickOutHpRate != null && (kickOutHpRate < 0.0 || kickOutHpRate > 1.0)) {
    issues.add(TechniqueDeckValidationIssue(
      severity: ValidationSeverity.error,
      code: 'invalidKickOutHpRate',
      message: 'kickOutHpRateは0.0〜1.0である必要があります（実際: $kickOutHpRate）。',
      cardId: card.id,
    ));
  }
  final kickOutThreshold = card.kickOutThreshold;
  if (kickOutThreshold != null && kickOutThreshold < 0) {
    issues.add(TechniqueDeckValidationIssue(
      severity: ValidationSeverity.error,
      code: 'negativeKickOutThreshold',
      message: 'kickOutThresholdは0以上である必要があります（実際: $kickOutThreshold）。',
      cardId: card.id,
    ));
  }
  final giveUpThreshold = card.giveUpThreshold;
  if (giveUpThreshold != null && giveUpThreshold < 0) {
    issues.add(TechniqueDeckValidationIssue(
      severity: ValidationSeverity.error,
      code: 'negativeGiveUpThreshold',
      message: 'giveUpThresholdは0以上である必要があります（実際: $giveUpThreshold）。',
      cardId: card.id,
    ));
  }
  final giveUpHpCost = card.giveUpHpCost;
  if (giveUpHpCost != null && giveUpHpCost < 0) {
    issues.add(TechniqueDeckValidationIssue(
      severity: ValidationSeverity.error,
      code: 'negativeGiveUpHpCost',
      message: 'giveUpHpCostは0以上である必要があります（実際: $giveUpHpCost）。',
      cardId: card.id,
    ));
  }
  // finisher以外でhasFinisherEffect==trueは警告（エラーではない —
  // Phase 1時点ではcategoryとhasFinisherEffectの関係を正式仕様として
  // 固定していないため）。
  if (card.category != TechniqueCardCategory.finisher &&
      card.hasFinisherEffect) {
    issues.add(TechniqueDeckValidationIssue(
      severity: ValidationSeverity.warning,
      code: 'finisherEffectOnNonFinisherCategory',
      message:
          'category=${card.category.name}だがhasFinisherEffect=trueです。'
          'finisherカテゴリ以外でのフィニッシャー効果は意図的か確認してください。',
      cardId: card.id,
    ));
  }
  return issues;
}

List<TechniqueDeckValidationIssue> validateEnergyCard(
  TechniqueEnergyCard card,
) => _issuesFor(id: card.id, name: card.name);

List<TechniqueDeckValidationIssue> validateDefenseCard(
  TechniqueDefenseCard card,
) => _issuesFor(id: card.id, name: card.name);

List<TechniqueDeckValidationIssue> validateWrestlerProfile(
  TechniqueDeckWrestlerProfile profile,
) {
  final issues = <TechniqueDeckValidationIssue>[];
  if (profile.wrestlerId.isEmpty) {
    issues.add(const TechniqueDeckValidationIssue(
      severity: ValidationSeverity.error,
      code: 'emptyWrestlerId',
      message: 'wrestlerIdが空です。',
    ));
  }
  if (profile.recoveryPower < 0) {
    issues.add(TechniqueDeckValidationIssue(
      severity: ValidationSeverity.error,
      code: 'negativeRecoveryPower',
      message: 'recoveryPowerは0以上である必要があります（実際: ${profile.recoveryPower}）。',
      cardId: profile.wrestlerId,
    ));
  }
  return issues;
}

/// カタログ全体のバリデーション（各カードの個別検証＋ID重複検出）。
/// デッキ枚数・同名投入枚数上限（Phase 2の対象）はここでは検査しない。
List<TechniqueDeckValidationIssue> validateCatalog(
  TechniqueDeckCardCatalog catalog,
) {
  final issues = <TechniqueDeckValidationIssue>[
    for (final card in catalog.techniques) ...validateTechniqueCard(card),
    for (final card in catalog.energies) ...validateEnergyCard(card),
    for (final card in catalog.defenseCards) ...validateDefenseCard(card),
  ];
  for (final id in catalog.findDuplicateIds()) {
    issues.add(TechniqueDeckValidationIssue(
      severity: ValidationSeverity.error,
      code: 'duplicateId',
      message: 'カタログ内でIDが重複しています。',
      cardId: id,
    ));
  }
  return issues;
}
