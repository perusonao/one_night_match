import '../wrestler_editor/models.dart';

/// Ver.0.5: 技カードセット画面向けの「全Level技コスト」評価モデル。
///
/// セット判定ロジックをここへ集約し、UI は表示のみ担当する。純粋関数群。

/// 技1つ分のコスト表示情報。
class MoveCostView {
  const MoveCostView({
    required this.moveId,
    required this.name,
    required this.category,
    required this.attribute,
    required this.requiredCards,
    required this.discardAfterUse,
    required this.currentCounts,
    required this.shortages,
    required this.levelUnlocked,
    required this.isCurrentLevel,
    required this.usableNow,
    required this.symbol,
    required this.offersPin,
    required this.offersSubmission,
    required this.additionalChecks,
  });

  final String moveId;
  final String name;
  final MoveCategory category;
  final MoveAttribute attribute;
  final Map<MoveAttribute, int> requiredCards;
  final Map<MoveAttribute, int> discardAfterUse;
  final Map<MoveAttribute, int> currentCounts;
  final Map<MoveAttribute, int> shortages;
  final bool levelUnlocked;
  final bool isCurrentLevel;
  final bool usableNow;

  /// '✓' 使用可能 / '△' カード不足 / '×' レベル未解放・使用不可。
  final String symbol;
  final bool offersPin;
  final bool offersSubmission;
  final List<AdditionalCheckType> additionalChecks;

  bool get isFinisher => category == MoveCategory.finisher;
  bool get hasShortage => shortages.values.any((value) => value > 0);
}

/// Level1つ分のコスト表示情報。
class LevelCostView {
  const LevelCostView({
    required this.level,
    required this.displayName,
    required this.unlocked,
    required this.isCurrentLevel,
    required this.normalMoves,
    required this.counterMoves,
    required this.finisherMoves,
  });

  final int level;
  final String displayName;
  final bool unlocked;
  final bool isCurrentLevel;
  final List<MoveCostView> normalMoves;
  final List<MoveCostView> counterMoves;
  final List<MoveCostView> finisherMoves;

  List<MoveCostView> get allMoves => [
    ...normalMoves,
    ...counterMoves,
    ...finisherMoves,
  ];
}

/// あるカードをセットした場合の1技分の変化。
class MovePredictionChange {
  const MovePredictionChange({
    required this.moveName,
    required this.attribute,
    required this.requiredForAttribute,
    required this.beforeCount,
    required this.afterCount,
    required this.remainingAfter,
    required this.usableBefore,
    required this.usableAfter,
  });

  final String moveName;
  final MoveAttribute attribute;
  final int requiredForAttribute;
  final int beforeCount;
  final int afterCount;
  final int remainingAfter;
  final bool usableBefore;
  final bool usableAfter;

  bool get becameUsable => !usableBefore && usableAfter;
}

/// セット後予測の結果。
class SetPrediction {
  const SetPrediction({required this.attribute, required this.changes});
  final MoveAttribute attribute;
  final List<MovePredictionChange> changes;
}

class LevelMatchCostPreview {
  const LevelMatchCostPreview({
    required this.wrestler,
    required this.moves,
  });

  final WrestlerDefinition wrestler;
  final Map<String, MoveDefinition> moves;

  Map<MoveAttribute, int> _shortages(
    MoveDefinition move,
    Map<MoveAttribute, int> counts,
  ) {
    final result = <MoveAttribute, int>{
      for (final attribute in MoveAttribute.values) attribute: 0,
    };
    for (final attribute in MoveAttribute.values) {
      final need =
          (move.requiredCards[attribute] ?? 0) +
          (move.discardAfterUse[attribute] ?? 0);
      final have = counts[attribute] ?? 0;
      final shortage = need - have;
      result[attribute] = shortage > 0 ? shortage : 0;
    }
    return result;
  }

  MoveCostView _moveView(
    MoveDefinition move,
    int level, {
    required Map<MoveAttribute, int> counts,
    required Set<int> unlockedLevels,
    required int currentLevel,
    required bool finisherUsed,
  }) {
    final shortages = _shortages(move, counts);
    final hasShortage = shortages.values.any((value) => value > 0);
    final unlocked = unlockedLevels.contains(level);
    final finisherBlocked =
        move.category == MoveCategory.finisher && finisherUsed;
    final String symbol;
    if (!unlocked || finisherBlocked) {
      symbol = '×';
    } else if (hasShortage) {
      symbol = '△';
    } else {
      symbol = '✓';
    }
    return MoveCostView(
      moveId: move.id,
      name: move.name,
      category: move.category,
      attribute: move.attribute,
      requiredCards: move.requiredCards,
      discardAfterUse: move.discardAfterUse,
      currentCounts: counts,
      shortages: shortages,
      levelUnlocked: unlocked,
      isCurrentLevel: level == currentLevel,
      usableNow: symbol == '✓' && level == currentLevel,
      symbol: symbol,
      offersPin: move.offersPin,
      offersSubmission: move.offersSubmission,
      additionalChecks: move.additionalChecks,
    );
  }

  /// Level1〜登録済み最上位までの全技コストビュー。
  List<LevelCostView> allLevelViews({
    required Map<MoveAttribute, int> counts,
    required Set<int> unlockedLevels,
    required int currentLevel,
    required bool finisherUsed,
  }) {
    final levels = [...wrestler.levels]
      ..sort((a, b) => a.level.compareTo(b.level));
    return [
      for (final level in levels)
        LevelCostView(
          level: level.level,
          displayName: level.displayName,
          unlocked: unlockedLevels.contains(level.level),
          isCurrentLevel: level.level == currentLevel,
          normalMoves: [
            for (final id in level.moveIds)
              if (moves[id] != null)
                _moveView(
                  moves[id]!,
                  level.level,
                  counts: counts,
                  unlockedLevels: unlockedLevels,
                  currentLevel: currentLevel,
                  finisherUsed: finisherUsed,
                ),
          ],
          counterMoves: [
            if (level.counterMoveId != null && moves[level.counterMoveId] != null)
              _moveView(
                moves[level.counterMoveId]!,
                level.level,
                counts: counts,
                unlockedLevels: unlockedLevels,
                currentLevel: currentLevel,
                finisherUsed: finisherUsed,
              ),
          ],
          finisherMoves: [
            if (level.finisherId != null && moves[level.finisherId] != null)
              _moveView(
                moves[level.finisherId]!,
                level.level,
                counts: counts,
                unlockedLevels: unlockedLevels,
                currentLevel: currentLevel,
                finisherUsed: finisherUsed,
              ),
          ],
        ),
    ];
  }

  bool _usable(
    MoveDefinition move,
    int level,
    Map<MoveAttribute, int> counts,
    Set<int> unlockedLevels,
    bool finisherUsed,
  ) {
    if (!unlockedLevels.contains(level)) return false;
    if (move.category == MoveCategory.finisher && finisherUsed) return false;
    return !_shortages(move, counts).values.any((value) => value > 0);
  }

  /// 指定属性のカードを1枚セットした場合の変化を予測する。
  SetPrediction predictSet({
    required MoveAttribute attribute,
    required Map<MoveAttribute, int> counts,
    required Set<int> unlockedLevels,
    required bool finisherUsed,
  }) {
    final after = <MoveAttribute, int>{
      for (final key in MoveAttribute.values) key: counts[key] ?? 0,
    };
    after[attribute] = (after[attribute] ?? 0) + 1;
    final changes = <MovePredictionChange>[];
    for (final level in wrestler.levels) {
      final ids = <String>[
        ...level.moveIds,
        if (level.counterMoveId != null) level.counterMoveId!,
        if (level.finisherId != null) level.finisherId!,
      ];
      for (final id in ids) {
        final move = moves[id];
        if (move == null) continue;
        final need =
            (move.requiredCards[attribute] ?? 0) +
            (move.discardAfterUse[attribute] ?? 0);
        if (need <= 0) continue; // この属性を必要としない技は無関係。
        final beforeCount = counts[attribute] ?? 0;
        final afterCount = after[attribute] ?? 0;
        final usableBefore = _usable(
          move,
          level.level,
          counts,
          unlockedLevels,
          finisherUsed,
        );
        final usableAfter = _usable(
          move,
          level.level,
          after,
          unlockedLevels,
          finisherUsed,
        );
        changes.add(
          MovePredictionChange(
            moveName: move.name,
            attribute: attribute,
            requiredForAttribute: need,
            beforeCount: beforeCount,
            afterCount: afterCount,
            remainingAfter: (need - afterCount) > 0 ? need - afterCount : 0,
            usableBefore: usableBefore,
            usableAfter: usableAfter,
          ),
        );
      }
    }
    // 使用可能になった技を優先表示。
    changes.sort((a, b) {
      if (a.becameUsable != b.becameUsable) return a.becameUsable ? -1 : 1;
      return a.remainingAfter.compareTo(b.remainingAfter);
    });
    return SetPrediction(attribute: attribute, changes: changes);
  }
}
