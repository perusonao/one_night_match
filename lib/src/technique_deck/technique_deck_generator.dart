import 'dart:math';

import '../wrestler_editor/models.dart' show MoveAttribute;
import 'technique_deck_deck.dart';
import 'technique_deck_models.dart';

/// Technique Deck Rules Phase 2後半: 暫定自動生成。
///
/// 強いデッキ構築AIは作らない。目的は [TechniqueDeckValidator] を通過する
/// 30枚（暫定枚数、[TechniqueDeckGenerationConfig] で変更可）を機械的に
/// 組み立てることだけ。生成比率・アルゴリズムは正式ルールではなく暫定値
/// （docs/design/technique_deck_open_questions.md参照。プレイテスト結果
/// 次第で調整する）。

/// 自動生成の枚数構成。既定値は暫定生成値（正式ルールではない）。
class TechniqueDeckGenerationConfig {
  const TechniqueDeckGenerationConfig({
    this.energyCount = 14,
    this.normalCount = 7,
    this.signatureCount = 3,
    this.finisherCount = 2,
    this.escapeCount = 1,
    this.reversalCount = 1,
    this.normalKickOutCount = 1,
    this.specialKickOutCount = 1,
    this.ropeBreakCount = 0,
    this.actionCount = 0,
    this.seed,
  });

  final int energyCount;
  final int normalCount;
  final int signatureCount;
  final int finisherCount;
  final int escapeCount;
  final int reversalCount;
  final int normalKickOutCount;
  final int specialKickOutCount;
  final int ropeBreakCount;
  final int actionCount;

  /// 指定すると候補の並べ替え・選択が再現可能になる（未指定時は毎回変わる）。
  final int? seed;

  int get totalCount =>
      energyCount +
      normalCount +
      signatureCount +
      finisherCount +
      escapeCount +
      reversalCount +
      normalKickOutCount +
      specialKickOutCount +
      ropeBreakCount +
      actionCount;
}

/// [TechniqueDeckAutoGenerator.generate] の結果。
class TechniqueDeckGenerationResult {
  const TechniqueDeckGenerationResult({
    required this.deck,
    required this.buildResult,
    required this.notes,
    required this.success,
    this.failureReasons = const [],
  });

  final TechniqueDeckDefinition deck;
  final TechniqueDeckBuildResult buildResult;

  /// 何を根拠に構成したかを人が読める文章で説明する（仕様書10章）。
  final List<String> notes;

  /// [TechniqueDeckBuildResult.isValid] と同義。エラーが1件でも残る場合は
  /// false（生成失敗）。
  final bool success;

  /// success=falseの場合の失敗理由一覧（[TechniqueDeckBuildResult.errors]の
  /// メッセージ）。
  final List<String> failureReasons;
}

class _Picked {
  _Picked(this.type, this.count);
  final TechniqueDeckCardType type;
  int count;
}

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

/// 検証を通過する暫定デッキを機械的に組み立てる。
class TechniqueDeckAutoGenerator {
  const TechniqueDeckAutoGenerator({
    this.config = const TechniqueDeckGenerationConfig(),
    this.validator = const TechniqueDeckValidator(),
  });

  final TechniqueDeckGenerationConfig config;
  final TechniqueDeckValidator validator;

  TechniqueDeckGenerationResult generate({
    required TechniqueDeckCardCatalog catalog,
    required String wrestlerId,
    String deckId = '',
    String deckName = '',
  }) {
    final random = Random(config.seed);
    final notes = <String>[];
    // cardId → 選択状況（枚数・種別）。最終的にTechniqueDeckBuilderへ渡す。
    final picked = <String, _Picked>{};
    void add(String cardId, TechniqueDeckCardType type, int count) {
      if (count <= 0) return;
      final existing = picked[cardId];
      if (existing != null) {
        existing.count += count;
      } else {
        picked[cardId] = _Picked(type, count);
      }
    }

    // 9.1 使用可能カードの絞り込み
    final usableNormal = catalog.techniques
        .where((c) => c.category == TechniqueCardCategory.normal)
        .toList();
    final usableSignature = catalog.techniques
        .where(
          (c) =>
              c.category == TechniqueCardCategory.signature &&
              c.allowedWrestlerIds.contains(wrestlerId),
        )
        .toList();
    final usableFinisher = catalog.techniques
        .where(
          (c) =>
              c.category == TechniqueCardCategory.finisher &&
              c.allowedWrestlerIds.contains(wrestlerId),
        )
        .toList();

    // 9.2 フィニッシャー（同名禁止・最大3枚）
    final finisherCap = min(config.finisherCount, validator.maxFinisherCount);
    final chosenFinishers = _pickDistinctByName(
      usableFinisher,
      finisherCap,
      random,
    );
    for (final card in chosenFinishers) {
      add(card.id, TechniqueDeckCardType.technique, 1);
    }
    if (chosenFinishers.length < config.finisherCount) {
      notes.add(
        'フィニッシャー候補は${usableFinisher.length}枚（使用可能名義ベース）のため、'
        '${chosenFinishers.length}枚のみ採用しました（目標: ${config.finisherCount}枚）。',
      );
    } else if (chosenFinishers.isNotEmpty) {
      notes.add('フィニッシャー候補が${usableFinisher.length}枚のため、${chosenFinishers.length}枚採用しました。');
    }

    // 9.3 固有技（同名1枚。不足分は通常技へ振替）
    final chosenSignature = _pickDiverseByLevel(
      usableSignature,
      config.signatureCount,
      random,
    );
    for (final card in chosenSignature) {
      add(card.id, TechniqueDeckCardType.technique, 1);
    }
    final signatureShortfall = config.signatureCount - chosenSignature.length;
    if (signatureShortfall > 0) {
      notes.add(
        '固有技候補が${usableSignature.length}枚しかないため、不足分$signatureShortfall枚を'
        '通常技で代替しました。',
      );
    }

    // 9.4 通常技（同名上限3枚、属性分散、stand/down・フォール/ギブアップ考慮）
    final normalTarget =
        config.normalCount + (signatureShortfall > 0 ? signatureShortfall : 0);
    final normalCounts = _pickNormalTechniques(
      usableNormal,
      normalTarget,
      random,
      3,
    );
    normalCounts.forEach((card, count) {
      add(card.id, TechniqueDeckCardType.technique, count);
    });
    final normalAssigned = normalCounts.values.fold<int>(0, (a, b) => a + b);
    if (normalAssigned < normalTarget) {
      notes.add(
        '通常技は候補・同名上限（3枚）の制約により、目標$normalTarget枚のうち'
        '$normalAssigned枚しか確保できませんでした。',
      );
    }

    final chosenTechniqueCards = <TechniqueDeckTechniqueCard>[
      ...chosenFinishers,
      ...chosenSignature,
      ...normalCounts.keys,
    ];
    final standCard = _firstWhereOrNull(
      chosenTechniqueCards,
      (c) => c.targetState == TechniqueTargetState.stand,
    );
    final downCard = _firstWhereOrNull(
      chosenTechniqueCards,
      (c) => c.targetState == TechniqueTargetState.down,
    );
    if (standCard != null) {
      notes.add('スタンド対象専用技を1種採用しました（${standCard.name}）。');
    }
    if (downCard != null) {
      notes.add('ダウン中専用技を1種採用しました（${downCard.name}）。');
    }
    final finishCard = _firstWhereOrNull(
      chosenTechniqueCards,
      (c) => c.hasPinEffect || c.hasSubmissionEffect,
    );
    if (finishCard != null) {
      notes.add('フォール／ギブアップ効果を持つ技を1種採用しました（${finishCard.name}）。');
    }

    // 9.5 エネルギー配分
    final energyNotes = <String>[];
    final energyCounts = _pickEnergyCards(
      catalog.energies,
      chosenTechniqueCards,
      config.energyCount,
      energyNotes,
    );
    energyCounts.forEach((card, count) {
      add(card.id, TechniqueDeckCardType.energy, count);
    });
    notes.addAll(energyNotes);
    if (energyCounts.isNotEmpty) {
      final byAttrDesc = energyCounts.entries
          .map((e) => '${e.key.attribute.name}${e.value}')
          .join('、');
      notes.add('技エネルギーの配分: $byAttrDesc（要求コストの大きい属性を優先）。');
    }

    // 9.6 防御カード
    _addDefenseCards(catalog, add, notes);

    // 端数調整: 目標合計枚数に届かない場合は通常技→技エネルギーの順で埋める。
    var currentTotal = picked.values.fold<int>(0, (a, b) => a + b.count);
    var shortfall = config.totalCount - currentTotal;
    if (shortfall > 0) {
      shortfall = _backfillWithNormalTechniques(
        usableNormal,
        picked,
        shortfall,
        3,
      );
    }
    if (shortfall > 0) {
      shortfall = _backfillWithEnergy(catalog.energies, picked, shortfall);
    }
    if (shortfall > 0) {
      notes.add(
        '技・エネルギーカードの候補が不足しているため、目標${config.totalCount}枚のうち'
        '$shortfall枚を確保できませんでした。',
      );
    }

    final builder = TechniqueDeckBuilder(
      wrestlerId: wrestlerId,
      id: deckId,
      name: deckName,
    );
    picked.forEach((cardId, info) {
      builder.addCard(cardId, info.type, count: info.count);
    });
    final deck = builder.build();
    final buildResult = validator.validate(deck, catalog);
    notes.add(
      buildResult.isValid
          ? '生成結果は検証を通過しました（${deck.entries.length}枚）。ただし最適デッキではありません。'
          : '生成結果は検証を通過しませんでした。下記のエラーを手動で修正してください。',
    );

    return TechniqueDeckGenerationResult(
      deck: deck,
      buildResult: buildResult,
      notes: notes,
      success: buildResult.isValid,
      failureReasons: buildResult.errors.map((e) => e.message).toList(),
    );
  }

  List<TechniqueDeckTechniqueCard> _pickDistinctByName(
    List<TechniqueDeckTechniqueCard> candidates,
    int count,
    Random random,
  ) {
    if (count <= 0 || candidates.isEmpty) return [];
    final uniqueByName = <String, TechniqueDeckTechniqueCard>{};
    for (final c in candidates) {
      uniqueByName.putIfAbsent(c.name, () => c);
    }
    final pool = uniqueByName.values.toList()..shuffle(random);
    return pool.take(count).toList();
  }

  List<TechniqueDeckTechniqueCard> _pickDiverseByLevel(
    List<TechniqueDeckTechniqueCard> candidates,
    int count,
    Random random,
  ) {
    if (count <= 0 || candidates.isEmpty) return [];
    final uniqueByName = <String, TechniqueDeckTechniqueCard>{};
    for (final c in candidates) {
      uniqueByName.putIfAbsent(c.name, () => c);
    }
    final byLevel = <int, List<TechniqueDeckTechniqueCard>>{};
    for (final c in uniqueByName.values) {
      byLevel.putIfAbsent(c.minimumLevel, () => []).add(c);
    }
    for (final list in byLevel.values) {
      list.shuffle(random);
    }
    final levels = byLevel.keys.toList()..sort();
    final result = <TechniqueDeckTechniqueCard>[];
    var index = 0;
    while (result.length < count) {
      var addedThisRound = false;
      for (final level in levels) {
        if (result.length >= count) break;
        final list = byLevel[level]!;
        if (index < list.length) {
          result.add(list[index]);
          addedThisRound = true;
        }
      }
      if (!addedThisRound) break;
      index++;
    }
    return result;
  }

  Map<TechniqueDeckTechniqueCard, int> _pickNormalTechniques(
    List<TechniqueDeckTechniqueCard> candidates,
    int target,
    Random random,
    int perCardLimit,
  ) {
    if (candidates.isEmpty || target <= 0) return {};
    final uniqueByName = <String, TechniqueDeckTechniqueCard>{};
    for (final c in candidates) {
      uniqueByName.putIfAbsent(c.name, () => c);
    }
    final pool = uniqueByName.values.toList()..shuffle(random);

    final priority = <TechniqueDeckTechniqueCard>[];
    for (final c in [
      _firstWhereOrNull(pool, (c) => c.targetState == TechniqueTargetState.stand),
      _firstWhereOrNull(pool, (c) => c.targetState == TechniqueTargetState.down),
      _firstWhereOrNull(pool, (c) => c.hasPinEffect || c.hasSubmissionEffect),
    ]) {
      if (c != null && !priority.contains(c)) priority.add(c);
    }

    final byAttribute = <MoveAttribute, List<TechniqueDeckTechniqueCard>>{};
    for (final c in pool) {
      byAttribute.putIfAbsent(c.attribute, () => []).add(c);
    }
    final attributesOrder = byAttribute.keys.toList()..shuffle(random);
    final roundRobinOrder = <TechniqueDeckTechniqueCard>[];
    var index = 0;
    var exhausted = false;
    while (!exhausted) {
      exhausted = true;
      for (final attr in attributesOrder) {
        final list = byAttribute[attr]!;
        if (index < list.length) {
          roundRobinOrder.add(list[index]);
          exhausted = false;
        }
      }
      index++;
    }

    final orderedCandidates = <TechniqueDeckTechniqueCard>[
      ...priority,
      for (final c in roundRobinOrder)
        if (!priority.contains(c)) c,
    ];
    if (orderedCandidates.isEmpty) return {};

    final counts = <TechniqueDeckTechniqueCard, int>{};
    var remaining = target;
    var cardIndex = 0;
    final safetyLimit = orderedCandidates.length * perCardLimit + 1;
    var iterations = 0;
    while (remaining > 0 && iterations < safetyLimit) {
      final card = orderedCandidates[cardIndex % orderedCandidates.length];
      final current = counts[card] ?? 0;
      if (current < perCardLimit) {
        counts[card] = current + 1;
        remaining--;
      }
      cardIndex++;
      iterations++;
    }
    return counts;
  }

  Map<TechniqueEnergyCard, int> _pickEnergyCards(
    List<TechniqueEnergyCard> catalogEnergies,
    List<TechniqueDeckTechniqueCard> chosenTechniques,
    int targetTotal,
    List<String> notes,
  ) {
    if (catalogEnergies.isEmpty || targetTotal <= 0) return {};
    final byAttribute = <MoveAttribute, TechniqueEnergyCard>{};
    for (final e in catalogEnergies) {
      byAttribute.putIfAbsent(e.attribute, () => e);
    }

    final attackDemand = <MoveAttribute, int>{};
    final reversalDemand = <MoveAttribute, int>{};
    final maxSingleCost = <MoveAttribute, int>{};
    for (final card in chosenTechniques) {
      for (final e in card.attackEnergyCost.entries) {
        if (e.value <= 0) continue;
        attackDemand[e.key] = (attackDemand[e.key] ?? 0) + e.value;
        maxSingleCost[e.key] = max(maxSingleCost[e.key] ?? 0, e.value);
      }
      for (final e in card.reversalEnergyCost.entries) {
        if (e.value <= 0) continue;
        reversalDemand[e.key] = (reversalDemand[e.key] ?? 0) + e.value;
        maxSingleCost[e.key] = max(maxSingleCost[e.key] ?? 0, e.value);
      }
    }

    final requiredAttributes = <MoveAttribute>{
      ...attackDemand.keys,
      ...reversalDemand.keys,
    };
    final counts = <MoveAttribute, int>{};

    // 最低保証: 攻撃・返技いずれかで要求される属性を最低1枚。
    for (final attr in requiredAttributes) {
      if (byAttribute.containsKey(attr)) {
        counts[attr] = 1;
      } else {
        notes.add('属性「${attr.name}」の技エネルギーカードがカタログにないため、確保できませんでした。');
      }
    }

    var allocated = counts.values.fold<int>(0, (a, b) => a + b);
    var remaining = targetTotal - allocated;

    // 単発最大コストを満たせるよう追加確保（可能な範囲で）。
    if (remaining > 0) {
      for (final attr in requiredAttributes) {
        if (remaining <= 0) break;
        if (!byAttribute.containsKey(attr)) continue;
        final needed = maxSingleCost[attr] ?? 0;
        final short = needed - (counts[attr] ?? 0);
        if (short > 0) {
          final addCount = min(short, remaining);
          counts[attr] = (counts[attr] ?? 0) + addCount;
          remaining -= addCount;
        }
      }
    }

    // 残り枠は要求量が大きい属性へ比例配分。要求がなければ全属性へ均等配分。
    if (remaining > 0) {
      final weights = <MoveAttribute, int>{
        for (final attr in byAttribute.keys)
          attr: (attackDemand[attr] ?? 0) + (reversalDemand[attr] ?? 0),
      };
      final totalWeight = weights.values.fold<int>(0, (a, b) => a + b);
      final attrsForFill = totalWeight > 0
          ? (weights.keys.toList()
              ..sort((a, b) => weights[b]!.compareTo(weights[a]!)))
          : byAttribute.keys.toList();
      var index = 0;
      final safetyLimit = (attrsForFill.length + 1) * (targetTotal + 1);
      var iterations = 0;
      while (remaining > 0 && attrsForFill.isNotEmpty && iterations < safetyLimit) {
        final attr = attrsForFill[index % attrsForFill.length];
        if (totalWeight <= 0 || (weights[attr] ?? 0) > 0) {
          counts[attr] = (counts[attr] ?? 0) + 1;
          remaining--;
        }
        index++;
        iterations++;
      }
    }

    return {
      for (final entry in counts.entries)
        if (entry.value > 0 && byAttribute.containsKey(entry.key))
          byAttribute[entry.key]!: entry.value,
    };
  }

  void _addDefenseCards(
    TechniqueDeckCardCatalog catalog,
    void Function(String cardId, TechniqueDeckCardType type, int count) add,
    List<String> notes,
  ) {
    void addType(
      TechniqueDeckCardType type,
      int count,
      String label, {
      KickOutCardCategory? kickOutCategory,
      int perCardLimit = 2,
    }) {
      if (count <= 0) return;
      final candidates = catalog.defenseCards
          .where(
            (c) =>
                c.type == type &&
                (kickOutCategory == null || c.kickOutCategory == kickOutCategory),
          )
          .toList();
      if (candidates.isEmpty) {
        notes.add('$labelの候補がカタログにないため採用できませんでした。');
        return;
      }
      var remaining = count;
      var index = 0;
      final counts = <TechniqueDefenseCard, int>{};
      final safetyLimit = candidates.length * perCardLimit + 1;
      var iterations = 0;
      while (remaining > 0 && iterations < safetyLimit) {
        final card = candidates[index % candidates.length];
        final current = counts[card] ?? 0;
        if (current < perCardLimit) {
          counts[card] = current + 1;
          remaining--;
        }
        index++;
        iterations++;
      }
      counts.forEach((card, c) => add(card.id, type, c));
      if (remaining > 0) {
        notes.add('$labelは候補・同名上限の制約により、目標$count枚に届きませんでした。');
      }
    }

    addType(TechniqueDeckCardType.escape, config.escapeCount, 'エスケープカード');
    addType(TechniqueDeckCardType.reversal, config.reversalCount, 'リバーサルカード');
    addType(
      TechniqueDeckCardType.kickOut,
      config.normalKickOutCount,
      '通常キックアウトカード',
      kickOutCategory: KickOutCardCategory.normal,
    );
    addType(
      TechniqueDeckCardType.kickOut,
      config.specialKickOutCount,
      '特殊キックアウトカード',
      kickOutCategory: KickOutCardCategory.finisherEscape,
      perCardLimit: 1,
    );
    addType(
      TechniqueDeckCardType.ropeBreak,
      config.ropeBreakCount,
      'ロープブレイクカード',
    );
    addType(
      TechniqueDeckCardType.action,
      config.actionCount,
      'アクションカード',
      perCardLimit: 3,
    );
  }

  int _backfillWithNormalTechniques(
    List<TechniqueDeckTechniqueCard> candidates,
    Map<String, _Picked> picked,
    int shortfall,
    int perCardLimit,
  ) {
    if (candidates.isEmpty) return shortfall;
    var remaining = shortfall;
    for (final card in candidates) {
      if (remaining <= 0) break;
      final existing = picked[card.id];
      final current = existing?.count ?? 0;
      if (current >= perCardLimit) continue;
      final addCount = min(perCardLimit - current, remaining);
      if (existing != null) {
        existing.count += addCount;
      } else {
        picked[card.id] = _Picked(TechniqueDeckCardType.technique, addCount);
      }
      remaining -= addCount;
    }
    return remaining;
  }

  int _backfillWithEnergy(
    List<TechniqueEnergyCard> candidates,
    Map<String, _Picked> picked,
    int shortfall,
  ) {
    if (candidates.isEmpty) return shortfall;
    final card = candidates.first;
    final existing = picked[card.id];
    if (existing != null) {
      existing.count += shortfall;
    } else {
      picked[card.id] = _Picked(TechniqueDeckCardType.energy, shortfall);
    }
    return 0;
  }
}
