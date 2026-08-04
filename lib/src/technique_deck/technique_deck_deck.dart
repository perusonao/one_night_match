import '../wrestler_editor/models.dart' show MoveAttribute;
import 'technique_deck_models.dart';
import 'technique_deck_validation.dart';

/// Technique Deck Rules Phase 2: デッキ定義・組み立て・検証。
///
/// Phase 2で実装するのは「手動で定義したデッキの検証」と「JSON保存・読込」まで。
/// デッキプレビューUI・自動生成AI・構成不足時の理由表示（推奨実装順の3〜5番目）は
/// 本ファイルの対象外（将来のPhaseで追加する）。実戦エンジンへの接続もまだ行わない。

// ============================================================
// モデル: デッキの1枚（物理カード）とデッキ全体
// ============================================================

/// デッキ内の1枚の物理カードを表す。同じ [cardId]（カード定義）が複数枚
/// 投入されても [instanceId] で個々を区別できる。
class TechniqueDeckEntry {
  const TechniqueDeckEntry({
    required this.instanceId,
    required this.cardId,
    required this.cardType,
  });

  final String instanceId;

  /// [TechniqueDeckTechniqueCard.id] / [TechniqueEnergyCard.id] /
  /// [TechniqueDefenseCard.id] のいずれかを参照する。
  final String cardId;

  /// カタログのどのリストを見るべきかを示す申告値。実際にカタログ上の
  /// カードと一致するかは [TechniqueDeckValidator] が検証する
  /// （`cardTypeMismatch`）。
  final TechniqueDeckCardType cardType;

  TechniqueDeckEntry copyWith({
    String? instanceId,
    String? cardId,
    TechniqueDeckCardType? cardType,
  }) => TechniqueDeckEntry(
    instanceId: instanceId ?? this.instanceId,
    cardId: cardId ?? this.cardId,
    cardType: cardType ?? this.cardType,
  );

  Map<String, dynamic> toJson() => {
    'instanceId': instanceId,
    'cardId': cardId,
    'cardType': cardType.name,
  };

  factory TechniqueDeckEntry.fromJson(Map<String, dynamic> json) {
    final instanceId = json['instanceId'];
    final cardId = json['cardId'];
    return TechniqueDeckEntry(
      instanceId: instanceId is String && instanceId.isNotEmpty
          ? instanceId
          : '',
      cardId: cardId is String && cardId.isNotEmpty ? cardId : '',
      cardType: enumOrDefault(
        TechniqueDeckCardType.values,
        json['cardType'],
        TechniqueDeckCardType.technique,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TechniqueDeckEntry &&
      instanceId == other.instanceId &&
      cardId == other.cardId &&
      cardType == other.cardType;

  @override
  int get hashCode => Object.hash(instanceId, cardId, cardType);

  @override
  String toString() =>
      'TechniqueDeckEntry(instanceId: $instanceId, cardId: $cardId, cardType: $cardType)';
}

bool _entryListEquals(List<TechniqueDeckEntry> a, List<TechniqueDeckEntry> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 特定レスラー向けのTechnique Deck一式（30枚、暫定）。
class TechniqueDeckDefinition {
  const TechniqueDeckDefinition({
    required this.id,
    required this.wrestlerId,
    this.name = '',
    this.entries = const [],
  });

  final String id;
  final String wrestlerId;
  final String name;
  final List<TechniqueDeckEntry> entries;

  int get cardCount => entries.length;

  TechniqueDeckDefinition copyWith({
    String? id,
    String? wrestlerId,
    String? name,
    List<TechniqueDeckEntry>? entries,
  }) => TechniqueDeckDefinition(
    id: id ?? this.id,
    wrestlerId: wrestlerId ?? this.wrestlerId,
    name: name ?? this.name,
    entries: entries ?? this.entries,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'wrestlerId': wrestlerId,
    'name': name,
    'entries': entries.map((e) => e.toJson()).toList(),
  };

  factory TechniqueDeckDefinition.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final wrestlerId = json['wrestlerId'];
    final name = json['name'];
    return TechniqueDeckDefinition(
      id: id is String && id.isNotEmpty ? id : '',
      wrestlerId: wrestlerId is String ? wrestlerId : '',
      name: name is String ? name : '',
      entries: (json['entries'] as List? ?? const [])
          .map(
            (item) =>
                TechniqueDeckEntry.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TechniqueDeckDefinition &&
      id == other.id &&
      wrestlerId == other.wrestlerId &&
      name == other.name &&
      _entryListEquals(entries, other.entries);

  @override
  int get hashCode => Object.hash(id, wrestlerId, name, entries.length);

  @override
  String toString() =>
      'TechniqueDeckDefinition(id: $id, wrestlerId: $wrestlerId, cardCount: $cardCount)';
}

// ============================================================
// デッキ組み立て（手動定義の補助のみ。自動生成AIはPhase 2後続で扱う）
// ============================================================

/// 手動で定義するデッキの組み立てを補助する。カードIDと枚数を指定すると
/// インスタンスIDを自動採番する。強いデッキ自動生成AIはPhase 2の後続
/// ステップ（推奨実装順4番目）で扱うため、ここには含めない。
class TechniqueDeckBuilder {
  TechniqueDeckBuilder({required this.wrestlerId, this.id = '', this.name = ''});

  final String wrestlerId;
  final String id;
  final String name;
  final List<TechniqueDeckEntry> _entries = [];
  int _autoInstanceCounter = 0;

  /// [cardId] のカードを [count] 枚追加する。インスタンスIDは
  /// `<cardId>#<連番>` を自動採番する。
  TechniqueDeckBuilder addCard(
    String cardId,
    TechniqueDeckCardType cardType, {
    int count = 1,
  }) {
    for (var i = 0; i < count; i++) {
      _autoInstanceCounter++;
      _entries.add(
        TechniqueDeckEntry(
          instanceId: '${cardId}_#$_autoInstanceCounter',
          cardId: cardId,
          cardType: cardType,
        ),
      );
    }
    return this;
  }

  /// インスタンスIDを自分で指定したい場合はこちらを使う。
  TechniqueDeckBuilder addEntry(TechniqueDeckEntry entry) {
    _entries.add(entry);
    return this;
  }

  TechniqueDeckDefinition build() => TechniqueDeckDefinition(
    id: id,
    wrestlerId: wrestlerId,
    name: name,
    entries: List.unmodifiable(_entries),
  );
}

// ============================================================
// デッキ検証
// ============================================================

/// デッキ検証ルールの識別子。[TechniqueDeckValidationIssue.code] へ
/// `.name` として渡す。
enum TechniqueDeckValidationRule {
  deckSizeMismatch,
  unknownCardId,
  duplicateInstanceId,
  sameNameLimitExceeded,
  finisherCountExceeded,
  duplicateFinisherName,
  wrestlerMismatch,
  emptyAllowedWrestlerIds,
  cardTypeMismatch,
  noEnergyCards,
  noFinisherCards,
  noSpecialKickOutCards,
  missingAttackEnergyCoverage,
  missingReversalEnergyCoverage,
  tooFewTechniqueCards,
  extremeEnergyRatio,
  allTechniquesUnusableLevel,
}

/// 各ルールのデフォルト重要度（エラー/警告）。
extension TechniqueDeckValidationRuleSeverity on TechniqueDeckValidationRule {
  ValidationSeverity get severity => switch (this) {
    TechniqueDeckValidationRule.deckSizeMismatch => ValidationSeverity.error,
    TechniqueDeckValidationRule.unknownCardId => ValidationSeverity.error,
    TechniqueDeckValidationRule.duplicateInstanceId => ValidationSeverity.error,
    TechniqueDeckValidationRule.sameNameLimitExceeded => ValidationSeverity.error,
    TechniqueDeckValidationRule.finisherCountExceeded => ValidationSeverity.error,
    TechniqueDeckValidationRule.duplicateFinisherName => ValidationSeverity.error,
    TechniqueDeckValidationRule.wrestlerMismatch => ValidationSeverity.error,
    TechniqueDeckValidationRule.emptyAllowedWrestlerIds =>
      ValidationSeverity.error,
    TechniqueDeckValidationRule.cardTypeMismatch => ValidationSeverity.error,
    TechniqueDeckValidationRule.noEnergyCards => ValidationSeverity.error,
    TechniqueDeckValidationRule.noFinisherCards => ValidationSeverity.warning,
    TechniqueDeckValidationRule.noSpecialKickOutCards =>
      ValidationSeverity.warning,
    TechniqueDeckValidationRule.missingAttackEnergyCoverage =>
      ValidationSeverity.warning,
    TechniqueDeckValidationRule.missingReversalEnergyCoverage =>
      ValidationSeverity.warning,
    TechniqueDeckValidationRule.tooFewTechniqueCards =>
      ValidationSeverity.warning,
    TechniqueDeckValidationRule.extremeEnergyRatio => ValidationSeverity.warning,
    TechniqueDeckValidationRule.allTechniquesUnusableLevel =>
      ValidationSeverity.warning,
  };
}

/// [TechniqueDeckValidator.validate] の結果。
class TechniqueDeckBuildResult {
  const TechniqueDeckBuildResult({required this.deck, required this.issues});

  final TechniqueDeckDefinition deck;
  final List<TechniqueDeckValidationIssue> issues;

  bool get isValid =>
      !issues.any((issue) => issue.severity == ValidationSeverity.error);

  List<TechniqueDeckValidationIssue> get errors =>
      issues.where((i) => i.severity == ValidationSeverity.error).toList();

  List<TechniqueDeckValidationIssue> get warnings =>
      issues.where((i) => i.severity == ValidationSeverity.warning).toList();
}

class _ResolvedEntry {
  const _ResolvedEntry({
    required this.entry,
    this.technique,
    this.energy,
    this.defense,
  });

  final TechniqueDeckEntry entry;
  final TechniqueDeckTechniqueCard? technique;
  final TechniqueEnergyCard? energy;
  final TechniqueDefenseCard? defense;

  String? get displayName => technique?.name ?? energy?.name ?? defense?.name;
}

/// デッキ枚数・カードID解決・同名上限・使用可能レスラー・属性カバレッジ等を
/// 検証する。数値パラメータ（枚数上限・比率閾値など）は暫定値であり、
/// コンストラクタで上書き可能にしてある
/// （[docs/rules/technique_deck_rules.md] 4.2章・[docs/design/
/// technique_deck_open_questions.md] 参照。プレイテスト結果次第で調整する）。
class TechniqueDeckValidator {
  const TechniqueDeckValidator({
    this.deckSize = 30,
    this.maxFinisherCount = 3,
    this.maxSpecialKickOutCount = 3,
    this.minTechniqueCardCount = 8,
    this.minEnergyRatio = 0.3,
    this.maxEnergyRatio = 0.7,
  });

  final int deckSize;
  final int maxFinisherCount;
  final int maxSpecialKickOutCount;
  final int minTechniqueCardCount;
  final double minEnergyRatio;
  final double maxEnergyRatio;

  TechniqueDeckBuildResult validate(
    TechniqueDeckDefinition deck,
    TechniqueDeckCardCatalog catalog,
  ) {
    final issues = <TechniqueDeckValidationIssue>[];
    void addIssue(
      TechniqueDeckValidationRule rule,
      String message, {
      String? cardId,
    }) {
      issues.add(
        TechniqueDeckValidationIssue(
          severity: rule.severity,
          code: rule.name,
          message: message,
          cardId: cardId,
        ),
      );
    }

    if (deck.entries.length != deckSize) {
      addIssue(
        TechniqueDeckValidationRule.deckSizeMismatch,
        'デッキ枚数は$deckSize枚である必要があります（実際: ${deck.entries.length}枚）。',
      );
    }

    final seenInstanceIds = <String>{};
    for (final entry in deck.entries) {
      if (!seenInstanceIds.add(entry.instanceId)) {
        addIssue(
          TechniqueDeckValidationRule.duplicateInstanceId,
          'インスタンスIDが重複しています。',
          cardId: entry.instanceId,
        );
      }
    }

    final resolved = <_ResolvedEntry>[];
    for (final entry in deck.entries) {
      final technique = catalog.findTechniqueById(entry.cardId);
      final energy = catalog.findEnergyById(entry.cardId);
      final defense = catalog.findDefenseCardById(entry.cardId);
      if (technique == null && energy == null && defense == null) {
        addIssue(
          TechniqueDeckValidationRule.unknownCardId,
          'カタログに存在しないカードIDです。',
          cardId: entry.cardId,
        );
        continue;
      }
      final actualType = technique != null
          ? TechniqueDeckCardType.technique
          : energy != null
          ? TechniqueDeckCardType.energy
          : defense!.type;
      if (entry.cardType != actualType) {
        addIssue(
          TechniqueDeckValidationRule.cardTypeMismatch,
          '宣言されたcardType（${entry.cardType.name}）がカタログ上の実際の種別'
          '（${actualType.name}）と一致しません。',
          cardId: entry.cardId,
        );
      }
      resolved.add(
        _ResolvedEntry(
          entry: entry,
          technique: technique,
          energy: energy,
          defense: defense,
        ),
      );
    }

    // 同名上限（フィニッシャーは合計枚数・同名不可を別途検証するため除外）
    final nameGroups = <String, List<_ResolvedEntry>>{};
    for (final r in resolved) {
      if (r.technique?.category == TechniqueCardCategory.finisher) continue;
      final name = r.displayName;
      if (name == null || name.isEmpty) continue;
      nameGroups.putIfAbsent(name, () => []).add(r);
    }
    for (final group in nameGroups.entries) {
      final limit = _sameNameLimitFor(group.value.first);
      if (limit > 0 && group.value.length > limit) {
        addIssue(
          TechniqueDeckValidationRule.sameNameLimitExceeded,
          '「${group.key}」は同名$limit枚までですが、${group.value.length}枚投入されています。',
          cardId: group.value.first.entry.cardId,
        );
      }
    }

    // フィニッシャー: 合計上限・同名禁止
    final finisherEntries = resolved
        .where((r) => r.technique?.category == TechniqueCardCategory.finisher)
        .toList();
    if (finisherEntries.length > maxFinisherCount) {
      addIssue(
        TechniqueDeckValidationRule.finisherCountExceeded,
        'フィニッシャーはデッキ全体で最大$maxFinisherCount枚までですが、'
        '${finisherEntries.length}枚投入されています。',
      );
    }
    final finisherNameCounts = <String, int>{};
    for (final r in finisherEntries) {
      final name = r.technique!.name;
      finisherNameCounts[name] = (finisherNameCounts[name] ?? 0) + 1;
    }
    for (final entry in finisherNameCounts.entries) {
      if (entry.value > 1) {
        addIssue(
          TechniqueDeckValidationRule.duplicateFinisherName,
          '同名フィニッシャー「${entry.key}」が${entry.value}枚投入されています'
          '（フィニッシャーは同名不可）。',
        );
      }
    }

    // 使用可能レスラー（固有技・フィニッシャーのみ対象）
    for (final r in resolved) {
      final technique = r.technique;
      if (technique == null) continue;
      final isRestricted =
          technique.category == TechniqueCardCategory.signature ||
          technique.category == TechniqueCardCategory.finisher;
      if (!isRestricted) continue;
      if (technique.allowedWrestlerIds.isEmpty) {
        addIssue(
          TechniqueDeckValidationRule.emptyAllowedWrestlerIds,
          '固有技・フィニッシャー「${technique.name}」はallowedWrestlerIdsの指定が必須です。',
          cardId: technique.id,
        );
      } else if (!technique.allowedWrestlerIds.contains(deck.wrestlerId)) {
        addIssue(
          TechniqueDeckValidationRule.wrestlerMismatch,
          '「${technique.name}」はこのデッキのレスラー（${deck.wrestlerId}）を'
          '使用可能レスラーに含みません。',
          cardId: technique.id,
        );
      }
    }

    final energyEntries = resolved.where((r) => r.energy != null).toList();
    if (energyEntries.isEmpty) {
      addIssue(
        TechniqueDeckValidationRule.noEnergyCards,
        '技エネルギーカードが1枚もありません。',
      );
    }

    if (finisherEntries.isEmpty) {
      addIssue(
        TechniqueDeckValidationRule.noFinisherCards,
        'フィニッシャーが1枚もありません。',
      );
    }

    final specialKickOutEntries = resolved
        .where(
          (r) =>
              r.defense?.type == TechniqueDeckCardType.kickOut &&
              r.defense?.kickOutCategory == KickOutCardCategory.finisherEscape,
        )
        .toList();
    if (specialKickOutEntries.isEmpty) {
      addIssue(
        TechniqueDeckValidationRule.noSpecialKickOutCards,
        '特殊キックアウトカードが1枚もありません。',
      );
    } else if (specialKickOutEntries.length > maxSpecialKickOutCount) {
      addIssue(
        TechniqueDeckValidationRule.sameNameLimitExceeded,
        '特殊キックアウトカードはデッキ全体で最大$maxSpecialKickOutCount枚までですが、'
        '${specialKickOutEntries.length}枚投入されています。',
      );
    }

    final availableAttributes = energyEntries
        .map((r) => r.energy!.attribute)
        .toSet();
    final requiredAttack = <MoveAttribute>{};
    final requiredReversal = <MoveAttribute>{};
    for (final r in resolved) {
      final technique = r.technique;
      if (technique == null) continue;
      for (final e in technique.attackEnergyCost.entries) {
        if (e.value > 0) requiredAttack.add(e.key);
      }
      for (final e in technique.reversalEnergyCost.entries) {
        if (e.value > 0) requiredReversal.add(e.key);
      }
    }
    for (final attribute in requiredAttack.difference(availableAttributes)) {
      addIssue(
        TechniqueDeckValidationRule.missingAttackEnergyCoverage,
        '属性「${attribute.name}」の攻撃エネルギーを要求する技がありますが、'
        '対応する技エネルギーカードがデッキにありません。',
      );
    }
    for (final attribute in requiredReversal.difference(availableAttributes)) {
      addIssue(
        TechniqueDeckValidationRule.missingReversalEnergyCoverage,
        '属性「${attribute.name}」の返技エネルギーを要求する技がありますが、'
        '対応する技エネルギーカードがデッキにありません。',
      );
    }

    final techniqueEntries = resolved.where((r) => r.technique != null).toList();
    if (techniqueEntries.length < minTechniqueCardCount) {
      addIssue(
        TechniqueDeckValidationRule.tooFewTechniqueCards,
        '技カード（通常技・固有技・フィニッシャー合計）が${techniqueEntries.length}枚しか'
        'ありません（目安: $minTechniqueCardCount枚以上）。',
      );
    }

    if (deck.entries.isNotEmpty) {
      final ratio = energyEntries.length / deck.entries.length;
      if (ratio < minEnergyRatio || ratio > maxEnergyRatio) {
        addIssue(
          TechniqueDeckValidationRule.extremeEnergyRatio,
          '技エネルギーカードの比率が${(ratio * 100).toStringAsFixed(1)}%です'
          '（目安: ${(minEnergyRatio * 100).toStringAsFixed(0)}%〜'
          '${(maxEnergyRatio * 100).toStringAsFixed(0)}%）。',
        );
      }
    }

    if (techniqueEntries.isNotEmpty &&
        techniqueEntries.every((r) => r.technique!.minimumLevel > 1)) {
      addIssue(
        TechniqueDeckValidationRule.allTechniquesUnusableLevel,
        'minimumLevelが1以下の技が1枚もありません（試合開始直後に使える技がありません）。',
      );
    }

    return TechniqueDeckBuildResult(deck: deck, issues: issues);
  }

  int _sameNameLimitFor(_ResolvedEntry r) {
    final technique = r.technique;
    if (technique != null) {
      return switch (technique.category) {
        TechniqueCardCategory.normal => 3,
        TechniqueCardCategory.signature => 1,
        TechniqueCardCategory.finisher => 1,
      };
    }
    final defense = r.defense;
    if (defense != null) {
      return switch (defense.type) {
        TechniqueDeckCardType.escape => 2,
        TechniqueDeckCardType.reversal => 2,
        TechniqueDeckCardType.kickOut =>
          defense.kickOutCategory == KickOutCardCategory.finisherEscape
              ? 1
              : 2,
        TechniqueDeckCardType.ropeBreak => 2,
        TechniqueDeckCardType.action => 3,
        TechniqueDeckCardType.technique || TechniqueDeckCardType.energy => 0,
      };
    }
    return 0; // 技エネルギーカード: 制限なし
  }
}
