import 'models.dart';

class WrestlerValidationResult {
  const WrestlerValidationResult(this.errors, this.warnings);
  final List<String> errors;
  final List<String> warnings;
  bool get isValid => errors.isEmpty;
}

class WrestlerValidator {
  const WrestlerValidator();

  WrestlerValidationResult validate(
    WrestlerDefinition wrestler, {
    required Map<String, MoveDefinition> moves,
    required Map<String, AbilityDefinition> abilities,
    bool allowEarlyFinisher = false,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    if (wrestler.id.trim().isEmpty) errors.add('レスラーIDは必須です');
    if (wrestler.name.trim().isEmpty) errors.add('リングネームは必須です');
    if (wrestler.maxHp < 1) errors.add('最大HPは1以上にしてください');
    if (!wrestler.levels.any((item) => item.level == 1)) {
      errors.add('Level 1が必要です');
    }
    final levelNumbers = wrestler.levels.map((item) => item.level).toList();
    if (levelNumbers.toSet().length != levelNumbers.length) {
      errors.add('レベル番号が重複しています');
    }
    for (final level in wrestler.levels) {
      final prefix = 'Level ${level.level}: ';
      if (level.level < 1 || level.level > 6) {
        errors.add('$prefixレベル番号は1〜6です');
      }
      if (level.level == 1 && level.unlockCondition != null) {
        errors.add('$prefix解放条件は設定できません');
      }
      if (level.level > 1 &&
          level.unlockCondition != null &&
          level.unlockCondition!.conditions.isEmpty) {
        errors.add('$prefix解放条件が空です');
      }
      if (level.resistances.values.any((value) => value < 0)) {
        errors.add('$prefix耐性は0以上です');
      }
      if (level.moveIds.length > 2) errors.add('$prefix通常技は最大2種類です');
      if (level.moveIds.toSet().length != level.moveIds.length) {
        errors.add('$prefix同じ通常技を重複設定できません');
      }
      for (final id in [
        ...level.moveIds,
        if (level.counterMoveId != null) level.counterMoveId!,
        if (level.finisherId != null) level.finisherId!,
      ]) {
        if (!moves.containsKey(id)) errors.add('$prefix存在しない技ID: $id');
      }
      if (level.abilityId != null && !abilities.containsKey(level.abilityId)) {
        errors.add('$prefix存在しない能力ID: ${level.abilityId}');
      }
      if (level.finisherId != null && level.level < 3 && !allowEarlyFinisher) {
        errors.add('$prefixフィニッシャーはLevel 3以降に設定してください');
      }
      final finisher = moves[level.finisherId];
      if (finisher != null && finisher.usageLimit == null) {
        errors.add('$prefixフィニッシャーの使用回数制限が必要です');
      }
    }
    for (final move in moves.values) {
      if (move.power < 0) errors.add('${move.name}: 攻撃力は0以上です');
      if (move.requiredCards.values.any((value) => value < 0) ||
          move.discardAfterUse.values.any((value) => value < 0)) {
        errors.add('${move.name}: カード枚数は0以上です');
      }
      if (move.successRate != null &&
          (move.successRate! < 0 || move.successRate! > 100)) {
        errors.add('${move.name}: 成功率は0〜100です');
      }
      if (move.usageLimit != null && move.usageLimit! < 1) {
        errors.add('${move.name}: 使用回数制限は1以上です');
      }
    }
    for (final ability in abilities.values) {
      if (ability.successRate != null &&
          (ability.successRate! < 0 || ability.successRate! > 100)) {
        errors.add('${ability.name}: 成功率は0〜100です');
      }
      if (ability.usageLimit != null && ability.usageLimit! < 1) {
        errors.add('${ability.name}: 使用回数制限は1以上です');
      }
    }
    return WrestlerValidationResult(errors, warnings);
  }
}
