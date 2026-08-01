import 'dart:convert';

enum EditorWrestlerType {
  babyface,
  power,
  technician,
  striker,
  highSpeed,
  heel,
  allRounder,
  other,
}

enum MoveAttribute { strike, throwMove, submission, counter, rough, aerial }

enum MoveCategory { normal, counter, finisher }

enum AdditionalCheckType {
  none,
  knockout,
  submission,
  pinfall,
  bleeding,
  counterSuccess,
}

enum ConditionOperator { and, or }

enum UnlockConditionType {
  hpAtMost,
  hpAtLeast,
  heatAtLeast,
  turnAtLeast,
  damageGivenAtLeast,
  damageReceivedAtLeast,
  attributeSuccessAtLeast,
  kickOutCountAtLeast,
  bleeding,
  eventOccurred,
  previousLevelUnlocked,
}

enum MoveConditionType {
  levelAtLeast,
  levelEquals,
  heatAtLeast,
  selfHpAtMost,
  opponentHpAtMost,
  selfBleeding,
  opponentBleeding,
  selfInRing,
  selfOutside,
  opponentInRing,
  opponentOutside,
  selfCorner,
  opponentCorner,
  opponentDown,
  afterAttributeMove,
  duringPin,
  duringSubmission,
  unusedThisMatch,
  ropeBreakAvailable,
  ropeRunning,
  cheering,
}

enum AbilityTiming {
  turnStart,
  cardSet,
  beforeMove,
  afterMoveSuccess,
  beforeDamage,
  afterDamage,
  checkStart,
  kickOut,
  levelChange,
  turnEnd,
}

T enumValue<T extends Enum>(List<T> values, Object? raw, String field) {
  if (raw is! String) throw FormatException('$field は文字列で指定してください');
  return values.firstWhere(
    (value) => value.name == raw,
    orElse: () => throw FormatException('$field の値「$raw」は未対応です'),
  );
}

String requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('必須フィールド「$key」がありません');
  }
  return value;
}

int requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num) throw FormatException('必須フィールド「$key」がありません');
  return value.toInt();
}

Map<MoveAttribute, int> attributeMap(Object? raw) {
  final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  return {
    for (final attribute in MoveAttribute.values)
      attribute: (map[attribute.name] as num?)?.toInt() ?? 0,
  };
}

Map<String, int> attributeMapToJson(Map<MoveAttribute, int> map) => {
  for (final attribute in MoveAttribute.values)
    attribute.name: map[attribute] ?? 0,
};

class RuleCondition {
  const RuleCondition({
    required this.type,
    this.value,
    this.attribute,
    this.key,
  });
  final String type;
  final int? value;
  final MoveAttribute? attribute;
  final String? key;

  Map<String, dynamic> toJson() => {
    'type': type,
    if (value != null) 'value': value,
    if (attribute != null) 'attribute': attribute!.name,
    if (key != null) 'key': key,
  };

  factory RuleCondition.fromJson(Map<String, dynamic> json) => RuleCondition(
    type: requiredString(json, 'type'),
    value: (json['value'] as num?)?.toInt(),
    attribute: json['attribute'] == null
        ? null
        : enumValue(MoveAttribute.values, json['attribute'], 'attribute'),
    key: json['key'] as String?,
  );
}

class UnlockCondition {
  const UnlockCondition({
    required this.type,
    this.value,
    this.attribute,
    this.eventKey,
  });
  final UnlockConditionType type;
  final int? value;
  final MoveAttribute? attribute;
  final String? eventKey;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    if (value != null) 'value': value,
    if (attribute != null) 'attribute': attribute!.name,
    if (eventKey != null) 'eventKey': eventKey,
  };

  factory UnlockCondition.fromJson(Map<String, dynamic> json) =>
      UnlockCondition(
        type: enumValue(UnlockConditionType.values, json['type'], 'type'),
        value: (json['value'] as num?)?.toInt(),
        attribute: json['attribute'] == null
            ? null
            : enumValue(MoveAttribute.values, json['attribute'], 'attribute'),
        eventKey: json['eventKey'] as String?,
      );
}

class UnlockConditionGroup {
  const UnlockConditionGroup({
    required this.operator,
    required this.conditions,
  });
  final ConditionOperator operator;
  final List<UnlockCondition> conditions;

  Map<String, dynamic> toJson() => {
    'operator': operator.name,
    'conditions': conditions.map((item) => item.toJson()).toList(),
  };

  factory UnlockConditionGroup.fromJson(Map<String, dynamic> json) =>
      UnlockConditionGroup(
        operator: enumValue(
          ConditionOperator.values,
          json['operator'],
          'operator',
        ),
        conditions: (json['conditions'] as List? ?? const [])
            .map(
              (item) =>
                  UnlockCondition.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(),
      );
}

class MoveDefinition {
  const MoveDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.attribute,
    required this.power,
    required this.heat,
    required this.requiredCards,
    this.conditions = const [],
    this.successEffects = const [],
    this.failureEffects = const [],
    this.additionalChecks = const [AdditionalCheckType.none],
    this.successRate,
    this.usageLimit,
    required this.discardAfterUse,
    this.description = '',
    this.imagePath,
    this.markUsedAfterUse = false,
    this.canResetUsedState = false,
  });

  final String id;
  final String name;
  final MoveCategory category;
  final MoveAttribute attribute;
  final int power;
  final int heat;
  final Map<MoveAttribute, int> requiredCards;
  final List<RuleCondition> conditions;
  final List<String> successEffects;
  final List<String> failureEffects;
  final List<AdditionalCheckType> additionalChecks;
  final int? successRate;
  final int? usageLimit;
  final Map<MoveAttribute, int> discardAfterUse;
  final String description;
  final String? imagePath;
  final bool markUsedAfterUse;
  final bool canResetUsedState;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category.name,
    'attribute': attribute.name,
    'power': power,
    'heat': heat,
    'requiredCards': attributeMapToJson(requiredCards),
    'conditions': conditions.map((item) => item.toJson()).toList(),
    'successEffects': successEffects,
    'failureEffects': failureEffects,
    'additionalChecks': additionalChecks.map((item) => item.name).toList(),
    'successRate': successRate,
    'usageLimit': usageLimit,
    'discardAfterUse': attributeMapToJson(discardAfterUse),
    'description': description,
    'imagePath': imagePath,
    'markUsedAfterUse': markUsedAfterUse,
    'canResetUsedState': canResetUsedState,
  };

  factory MoveDefinition.fromJson(Map<String, dynamic> json) => MoveDefinition(
    id: requiredString(json, 'id'),
    name: requiredString(json, 'name'),
    category: enumValue(MoveCategory.values, json['category'], 'category'),
    attribute: enumValue(MoveAttribute.values, json['attribute'], 'attribute'),
    power: requiredInt(json, 'power'),
    heat: requiredInt(json, 'heat'),
    requiredCards: attributeMap(json['requiredCards']),
    conditions: (json['conditions'] as List? ?? const [])
        .map((item) => RuleCondition.fromJson(Map<String, dynamic>.from(item)))
        .toList(),
    successEffects: List<String>.from(
      json['successEffects'] as List? ?? const [],
    ),
    failureEffects: List<String>.from(
      json['failureEffects'] as List? ?? const [],
    ),
    additionalChecks: (json['additionalChecks'] as List? ?? const ['none'])
        .map(
          (item) =>
              enumValue(AdditionalCheckType.values, item, 'additionalChecks'),
        )
        .toList(),
    successRate: (json['successRate'] as num?)?.toInt(),
    usageLimit: (json['usageLimit'] as num?)?.toInt(),
    discardAfterUse: attributeMap(json['discardAfterUse']),
    description: json['description'] as String? ?? '',
    imagePath: json['imagePath'] as String?,
    markUsedAfterUse: json['markUsedAfterUse'] as bool? ?? false,
    canResetUsedState: json['canResetUsedState'] as bool? ?? false,
  );
}

class AbilityDefinition {
  const AbilityDefinition({
    required this.id,
    required this.name,
    this.description = '',
    required this.timing,
    this.conditions = const [],
    this.cost = const {},
    this.successEffects = const [],
    this.failureEffects = const [],
    this.successRate,
    this.usageLimit,
    this.isAutomatic = true,
  });
  final String id;
  final String name;
  final String description;
  final AbilityTiming timing;
  final List<RuleCondition> conditions;
  final Map<MoveAttribute, int> cost;
  final List<String> successEffects;
  final List<String> failureEffects;
  final int? successRate;
  final int? usageLimit;
  final bool isAutomatic;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'timing': timing.name,
    'conditions': conditions.map((item) => item.toJson()).toList(),
    'cost': attributeMapToJson(cost),
    'successEffects': successEffects,
    'failureEffects': failureEffects,
    'successRate': successRate,
    'usageLimit': usageLimit,
    'isAutomatic': isAutomatic,
  };

  factory AbilityDefinition.fromJson(Map<String, dynamic> json) =>
      AbilityDefinition(
        id: requiredString(json, 'id'),
        name: requiredString(json, 'name'),
        description: json['description'] as String? ?? '',
        timing: enumValue(AbilityTiming.values, json['timing'], 'timing'),
        conditions: (json['conditions'] as List? ?? const [])
            .map(
              (item) => RuleCondition.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(),
        cost: attributeMap(json['cost']),
        successEffects: List<String>.from(
          json['successEffects'] as List? ?? const [],
        ),
        failureEffects: List<String>.from(
          json['failureEffects'] as List? ?? const [],
        ),
        successRate: (json['successRate'] as num?)?.toInt(),
        usageLimit: (json['usageLimit'] as num?)?.toInt(),
        isAutomatic: json['isAutomatic'] as bool? ?? true,
      );
}

class WrestlerLevelDefinition {
  const WrestlerLevelDefinition({
    required this.level,
    required this.displayName,
    this.unlockCondition,
    required this.resistances,
    this.moveIds = const [],
    this.counterMoveId,
    this.abilityId,
    this.finisherId,
    this.imagePath,
    this.flavorText = '',
  });
  final int level;
  final String displayName;
  final UnlockConditionGroup? unlockCondition;
  final Map<MoveAttribute, int> resistances;
  final List<String> moveIds;
  final String? counterMoveId;
  final String? abilityId;
  final String? finisherId;
  final String? imagePath;
  final String flavorText;

  Map<String, dynamic> toJson() => {
    'level': level,
    'displayName': displayName,
    'unlockCondition': unlockCondition?.toJson(),
    'resistances': attributeMapToJson(resistances),
    'moveIds': moveIds,
    'counterMoveId': counterMoveId,
    'abilityId': abilityId,
    'finisherId': finisherId,
    'imagePath': imagePath,
    'flavorText': flavorText,
  };

  factory WrestlerLevelDefinition.fromJson(Map<String, dynamic> json) =>
      WrestlerLevelDefinition(
        level: requiredInt(json, 'level'),
        displayName: requiredString(json, 'displayName'),
        unlockCondition: json['unlockCondition'] == null
            ? null
            : UnlockConditionGroup.fromJson(
                Map<String, dynamic>.from(json['unlockCondition']),
              ),
        resistances: attributeMap(json['resistances']),
        moveIds: List<String>.from(json['moveIds'] as List? ?? const []),
        counterMoveId: json['counterMoveId'] as String?,
        abilityId: json['abilityId'] as String?,
        finisherId: json['finisherId'] as String?,
        imagePath: json['imagePath'] as String?,
        flavorText: json['flavorText'] as String? ?? '',
      );
}

class WrestlerDefinition {
  const WrestlerDefinition({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.type,
    required this.maxHp,
    this.description = '',
    required this.themeColor,
    this.imagePath,
    this.tags = const [],
    required this.levels,
    required this.createdAt,
    required this.updatedAt,
    this.dataVersion = 1,
  });
  final String id;
  final String name;
  final String subtitle;
  final EditorWrestlerType type;
  final int maxHp;
  final String description;
  final String themeColor;
  final String? imagePath;
  final List<String> tags;
  final List<WrestlerLevelDefinition> levels;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int dataVersion;

  WrestlerDefinition copyWith({
    String? id,
    String? name,
    String? subtitle,
    EditorWrestlerType? type,
    int? maxHp,
    String? description,
    String? themeColor,
    String? imagePath,
    List<String>? tags,
    List<WrestlerLevelDefinition>? levels,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => WrestlerDefinition(
    id: id ?? this.id,
    name: name ?? this.name,
    subtitle: subtitle ?? this.subtitle,
    type: type ?? this.type,
    maxHp: maxHp ?? this.maxHp,
    description: description ?? this.description,
    themeColor: themeColor ?? this.themeColor,
    imagePath: imagePath ?? this.imagePath,
    tags: tags ?? this.tags,
    levels: levels ?? this.levels,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    dataVersion: dataVersion,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'subtitle': subtitle,
    'type': type.name,
    'maxHp': maxHp,
    'description': description,
    'themeColor': themeColor,
    'imagePath': imagePath,
    'tags': tags,
    'levels': levels.map((item) => item.toJson()).toList(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'dataVersion': dataVersion,
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory WrestlerDefinition.fromJson(Map<String, dynamic> json) =>
      WrestlerDefinition(
        id: requiredString(json, 'id'),
        name: requiredString(json, 'name'),
        subtitle: json['subtitle'] as String? ?? '',
        type: enumValue(EditorWrestlerType.values, json['type'], 'type'),
        maxHp: requiredInt(json, 'maxHp'),
        description: json['description'] as String? ?? '',
        themeColor: requiredString(json, 'themeColor'),
        imagePath: json['imagePath'] as String?,
        tags: List<String>.from(json['tags'] as List? ?? const []),
        levels:
            (json['levels'] as List? ??
                    (throw const FormatException('必須フィールド「levels」がありません')))
                .map(
                  (item) => WrestlerLevelDefinition.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        dataVersion: (json['dataVersion'] as num?)?.toInt() ?? 1,
      );
}

String moveAttributeLabel(MoveAttribute value) => switch (value) {
  MoveAttribute.strike => '打',
  MoveAttribute.throwMove => '投',
  MoveAttribute.submission => '関',
  MoveAttribute.counter => '返',
  MoveAttribute.rough => '凶',
  MoveAttribute.aerial => '飛',
};

String wrestlerTypeLabel(EditorWrestlerType value) => switch (value) {
  EditorWrestlerType.babyface => '正統派',
  EditorWrestlerType.power => 'パワー',
  EditorWrestlerType.technician => 'テクニシャン',
  EditorWrestlerType.striker => 'ストライカー',
  EditorWrestlerType.highSpeed => 'ハイスピード',
  EditorWrestlerType.heel => 'ヒール',
  EditorWrestlerType.allRounder => 'オールラウンダー',
  EditorWrestlerType.other => 'その他',
};
