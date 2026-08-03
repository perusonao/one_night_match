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

enum MoveCategory { normal, counter, finisher, basic }

enum AdditionalCheckType {
  none,
  knockout,
  submission,
  pinfall,
  bleeding,
  counterSuccess,
  down,
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
  // Ver.0.5: level-flexible unlock conditions (allow "飛び級" progression).
  specificLevelUsedAtLeast,
  specificLevelMoveSuccessAtLeast,
  currentLevelIs,
  levelChangeCountAtLeast,
  pinKickOutCountAtLeast,
  submissionEscapeCountAtLeast,
  finisherKickOutCountAtLeast,
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
    this.level,
  });
  final UnlockConditionType type;
  final int? value;
  final MoveAttribute? attribute;
  final String? eventKey;

  /// Ver.0.5: target level referenced by specificLevel* conditions.
  final int? level;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    if (value != null) 'value': value,
    if (attribute != null) 'attribute': attribute!.name,
    if (eventKey != null) 'eventKey': eventKey,
    if (level != null) 'level': level,
  };

  factory UnlockCondition.fromJson(Map<String, dynamic> json) =>
      UnlockCondition(
        type: enumValue(UnlockConditionType.values, json['type'], 'type'),
        value: (json['value'] as num?)?.toInt(),
        attribute: json['attribute'] == null
            ? null
            : enumValue(MoveAttribute.values, json['attribute'], 'attribute'),
        eventKey: json['eventKey'] as String?,
        level: (json['level'] as num?)?.toInt(),
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
    this.canAttemptPin = false,
    this.pinPower = 0,
    this.autoPin = false,
    this.pinAttemptLimit,
    this.pinBonusOnFinisher = 0,
    this.canAttemptSubmission = false,
    this.submissionPower = 0,
    this.autoSubmissionCheck = false,
    this.submissionBonusOnFinisher = 0,
    this.speed = 5,
    this.canPin = false,
    this.canSubmit = false,
    this.canKO = false,
    this.counterTypes = const [],
    this.cannotCounterTypes = const [],
    this.specialAbilities = const [],
    this.causesDownFlag = false,
    this.causesCorner = false,
    this.causesOutside = false,
    this.requiredPreviousState,
    this.consumesSetCards = true,
    this.canUseAsNormalMove = false,
    this.ignoreNormalSpeed = false,
    this.allowedResponses = const [],
    this.extra = const {},
    this.heatCost = 0,
    this.rank = 1,
    this.deckPoints = 0,
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

  // Ver.0.5: フォール（3カウント）用パラメータ。
  final bool canAttemptPin;
  final int pinPower;
  final bool autoPin;
  final int? pinAttemptLimit;
  final int pinBonusOnFinisher;

  // Ver.0.5: ギブアップ（サブミッション）用パラメータ。
  final bool canAttemptSubmission;
  final int submissionPower;
  final bool autoSubmissionCheck;
  final int submissionBonusOnFinisher;

  // Ver.0.7: 技速度・返し・決着可否・状態変化・特殊能力（改修10）。
  final int speed; // 大きいほど速い（先に命中）
  final bool canPin; // フォール可能（固有技のみ想定）
  final bool canSubmit; // ギブアップ可能
  final bool canKO; // KO可能（ダウンへ）
  final List<MoveAttribute> counterTypes; // 返せる相手属性
  final List<MoveAttribute> cannotCounterTypes; // この技を返せない属性
  final List<String> specialAbilities; // 例: cannotRopeBreak, cannotCounter
  final bool causesDownFlag; // 明示的なダウン付与
  final bool causesCorner;
  final bool causesOutside;
  final String? requiredPreviousState; // 使用に必要な直前状態（例: down, topRope）
  final bool consumesSetCards; // 使用時にセットカードを消費するか
  final bool canUseAsNormalMove; // 返し技を通常攻撃としても宣言できるか

  // Ver.0.7.2: フィニッシャーは通常技のSpeedクラッシュで割り込めない切り札。
  final bool ignoreNormalSpeed; // 通常技のSpeed勝ちを無効化
  final List<String>
  allowedResponses; // 許可レスポンス: dedicatedCounter/escape/ability/take 等

  /// Ver.0.8.0: 将来拡張用の任意メタデータ（AI優先度・発動率・レアリティ・
  /// エフェクト/SE/モーションID・コンボ条件・部位ダメージ・ロープブレイク等）。
  /// 現行エンジンは未使用。増やしてもモデル改変不要。
  final Map<String, dynamic> extra;

  /// Ver.0.8.0: HEATマナ制での消費HEAT（0=カテゴリから自動推定）。
  final int heatCost;

  /// Ver.0.8.0: 技の格（★1〜★5）。ダメージではなく“格”を表す。
  final int rank;

  /// Ver.0.8.0: デッキ構築ポイント（0=ランクから自動＝ランク値）。
  final int deckPoints;

  /// デッキ構築で使う実効ポイント（未設定ならランク＝ポイント）。
  int get displayDeckPoints => deckPoints > 0 ? deckPoints : rank.clamp(1, 5);

  /// 必要エネルギー（属性→枚数）。現行の requiredCards をそのまま用いる。
  Map<MoveAttribute, int> get energyCost => {
    for (final e in requiredCards.entries)
      if (e.value > 0) e.key: e.value,
  };

  /// Ver.0.8.0 energyモードでの実効コスト。requiredCards が全て0（＝通常技等、
  /// classicモードでは無料だった技）の場合のみ、自属性1枚を既定コストとする。
  /// 数値バランスの再調整ではなく、「無料技を廃止する」という土台の仕組み。
  Map<MoveAttribute, int> get energyModeRequiredCards {
    // Ver.0.8.0: energyOverrides.energyCost があれば最優先（classicのrequiredCards
    // ＝セットコストとは独立にenergyモード専用のコストを設定できる）。
    final overrides = extra['energyOverrides'];
    if (overrides is Map && overrides['energyCost'] is Map) {
      final raw = overrides['energyCost'] as Map;
      return {
        for (final a in MoveAttribute.values)
          a: (raw[a.name] as num?)?.toInt() ?? 0,
      };
    }
    final total = requiredCards.values.fold<int>(0, (a, b) => a + b);
    if (total > 0) return requiredCards;
    return {attribute: 1};
  }

  /// Ver.0.8.0: energyモード専用のバランス上書き（technique-master modelを
  /// 複製せず extra を使う）。classicの数値・技マスタ本体には一切影響しない。
  /// 例: extra['energyOverrides'] = {'canPin': false, 'pinPower': 0}
  MoveDefinition get resolvedForEnergyMode {
    final overrides = extra['energyOverrides'];
    if (overrides is! Map) return this;
    return copyWith(
      power: (overrides['power'] as num?)?.toInt(),
      heat: (overrides['heat'] as num?)?.toInt(),
      pinPower: (overrides['pinPower'] as num?)?.toInt(),
      submissionPower: (overrides['submissionPower'] as num?)?.toInt(),
      canPin: overrides['canPin'] as bool?,
      canSubmit: overrides['canSubmit'] as bool?,
    );
  }

  /// 表示・HEATマナ制で使う消費HEAT。未設定(0)ならカテゴリから推定。
  int get displayHeatCost {
    if (heatCost > 0) return heatCost;
    final cardCost = requiredCards.values.fold<int>(0, (a, b) => a + b);
    return switch (category) {
      MoveCategory.basic => 1,
      MoveCategory.finisher => 8,
      _ => (cardCost + 2).clamp(3, 6),
    };
  }

  /// 技編集時に、UI未対応のフィールドを失わないためのコピー生成。
  MoveDefinition copyWith({
    String? id,
    String? name,
    MoveCategory? category,
    MoveAttribute? attribute,
    int? power,
    int? heat,
    Map<MoveAttribute, int>? requiredCards,
    Map<MoveAttribute, int>? discardAfterUse,
    List<AdditionalCheckType>? additionalChecks,
    int? successRate,
    int? usageLimit,
    List<String>? successEffects,
    List<String>? failureEffects,
    String? description,
    String? imagePath,
    bool? markUsedAfterUse,
    bool? canResetUsedState,
    int? speed,
    int? pinPower,
    int? submissionPower,
    bool? canPin,
    bool? canSubmit,
    bool? canKO,
    bool? canAttemptPin,
    bool? canAttemptSubmission,
    int? heatCost,
    int? rank,
    int? deckPoints,
  }) => MoveDefinition(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    attribute: attribute ?? this.attribute,
    power: power ?? this.power,
    heat: heat ?? this.heat,
    requiredCards: requiredCards ?? this.requiredCards,
    conditions: conditions,
    successEffects: successEffects ?? this.successEffects,
    failureEffects: failureEffects ?? this.failureEffects,
    additionalChecks: additionalChecks ?? this.additionalChecks,
    successRate: successRate ?? this.successRate,
    usageLimit: usageLimit ?? this.usageLimit,
    discardAfterUse: discardAfterUse ?? this.discardAfterUse,
    description: description ?? this.description,
    imagePath: imagePath ?? this.imagePath,
    markUsedAfterUse: markUsedAfterUse ?? this.markUsedAfterUse,
    canResetUsedState: canResetUsedState ?? this.canResetUsedState,
    canAttemptPin: canAttemptPin ?? this.canAttemptPin,
    pinPower: pinPower ?? this.pinPower,
    autoPin: autoPin,
    pinAttemptLimit: pinAttemptLimit,
    pinBonusOnFinisher: pinBonusOnFinisher,
    canAttemptSubmission: canAttemptSubmission ?? this.canAttemptSubmission,
    submissionPower: submissionPower ?? this.submissionPower,
    autoSubmissionCheck: autoSubmissionCheck,
    submissionBonusOnFinisher: submissionBonusOnFinisher,
    speed: speed ?? this.speed,
    canPin: canPin ?? this.canPin,
    canSubmit: canSubmit ?? this.canSubmit,
    canKO: canKO ?? this.canKO,
    counterTypes: counterTypes,
    cannotCounterTypes: cannotCounterTypes,
    specialAbilities: specialAbilities,
    causesDownFlag: causesDownFlag,
    causesCorner: causesCorner,
    causesOutside: causesOutside,
    requiredPreviousState: requiredPreviousState,
    consumesSetCards: consumesSetCards,
    canUseAsNormalMove: canUseAsNormalMove,
    ignoreNormalSpeed: ignoreNormalSpeed,
    allowedResponses: allowedResponses,
    extra: extra,
    heatCost: heatCost ?? this.heatCost,
    rank: rank ?? this.rank,
    deckPoints: deckPoints ?? this.deckPoints,
  );

  /// この技は「返し」として相手技に対応する性質を持つか。
  bool get isCounterMove =>
      category == MoveCategory.counter || counterTypes.isNotEmpty;

  /// 単体技（コスト不要・決着不可）か。
  bool get isBasic => category == MoveCategory.basic;

  /// この技が成功後にフォール判定へ移行できるか（単体技は不可）。
  bool get offersPin =>
      !isBasic &&
      (canPin ||
          canAttemptPin ||
          additionalChecks.contains(AdditionalCheckType.pinfall));

  /// この技が成功後にギブアップ判定へ移行できるか（単体技は不可）。
  bool get offersSubmission =>
      !isBasic &&
      (canSubmit ||
          canAttemptSubmission ||
          additionalChecks.contains(AdditionalCheckType.submission));

  /// この技が相手をダウンさせるか（単体技は不可。旧knockoutはdown扱い）。
  bool get causesDown =>
      !isBasic &&
      (causesDownFlag ||
          canKO ||
          additionalChecks.contains(AdditionalCheckType.down) ||
          additionalChecks.contains(AdditionalCheckType.knockout));

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
    'canAttemptPin': canAttemptPin,
    'pinPower': pinPower,
    'autoPin': autoPin,
    'pinAttemptLimit': pinAttemptLimit,
    'pinBonusOnFinisher': pinBonusOnFinisher,
    'canAttemptSubmission': canAttemptSubmission,
    'submissionPower': submissionPower,
    'autoSubmissionCheck': autoSubmissionCheck,
    'submissionBonusOnFinisher': submissionBonusOnFinisher,
    'speed': speed,
    'canPin': canPin,
    'canSubmit': canSubmit,
    'canKO': canKO,
    'counterTypes': counterTypes.map((item) => item.name).toList(),
    'cannotCounterTypes': cannotCounterTypes.map((item) => item.name).toList(),
    'specialAbilities': specialAbilities,
    'causesDown': causesDownFlag,
    'causesCorner': causesCorner,
    'causesOutside': causesOutside,
    'requiredPreviousState': requiredPreviousState,
    'consumesSetCards': consumesSetCards,
    'canUseAsNormalMove': canUseAsNormalMove,
    'ignoreNormalSpeed': ignoreNormalSpeed,
    'allowedResponses': allowedResponses,
    if (extra.isNotEmpty) 'extra': extra,
    if (heatCost > 0) 'heatCost': heatCost,
    if (rank != 1) 'rank': rank,
    if (deckPoints > 0) 'deckPoints': deckPoints,
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
    canAttemptPin: json['canAttemptPin'] as bool? ?? false,
    pinPower: (json['pinPower'] as num?)?.toInt() ?? 0,
    autoPin: json['autoPin'] as bool? ?? false,
    pinAttemptLimit: (json['pinAttemptLimit'] as num?)?.toInt(),
    pinBonusOnFinisher: (json['pinBonusOnFinisher'] as num?)?.toInt() ?? 0,
    canAttemptSubmission: json['canAttemptSubmission'] as bool? ?? false,
    submissionPower: (json['submissionPower'] as num?)?.toInt() ?? 0,
    autoSubmissionCheck: json['autoSubmissionCheck'] as bool? ?? false,
    submissionBonusOnFinisher:
        (json['submissionBonusOnFinisher'] as num?)?.toInt() ?? 0,
    speed: (json['speed'] as num?)?.toInt() ?? 5,
    canPin: json['canPin'] as bool? ?? false,
    canSubmit: json['canSubmit'] as bool? ?? false,
    canKO: json['canKO'] as bool? ?? false,
    counterTypes: [
      for (final item in (json['counterTypes'] as List? ?? const []))
        enumValue(MoveAttribute.values, item, 'counterTypes'),
    ],
    cannotCounterTypes: [
      for (final item in (json['cannotCounterTypes'] as List? ?? const []))
        enumValue(MoveAttribute.values, item, 'cannotCounterTypes'),
    ],
    specialAbilities: List<String>.from(
      json['specialAbilities'] as List? ?? const [],
    ),
    causesDownFlag: json['causesDown'] as bool? ?? false,
    causesCorner: json['causesCorner'] as bool? ?? false,
    causesOutside: json['causesOutside'] as bool? ?? false,
    requiredPreviousState: json['requiredPreviousState'] as String?,
    consumesSetCards: json['consumesSetCards'] as bool? ?? true,
    canUseAsNormalMove: json['canUseAsNormalMove'] as bool? ?? false,
    ignoreNormalSpeed: json['ignoreNormalSpeed'] as bool? ?? false,
    allowedResponses: List<String>.from(
      json['allowedResponses'] as List? ?? const [],
    ),
    extra: Map<String, dynamic>.from(json['extra'] as Map? ?? const {}),
    heatCost: (json['heatCost'] as num?)?.toInt() ?? 0,
    rank: (json['rank'] as num?)?.toInt() ?? 1,
    deckPoints: (json['deckPoints'] as num?)?.toInt() ?? 0,
  );
}

/// Ver.0.5 で追加された追加判定・属性のラベル。
String additionalCheckLabel(AdditionalCheckType value) => switch (value) {
  AdditionalCheckType.none => 'なし',
  AdditionalCheckType.knockout => 'KO(ダウン)',
  AdditionalCheckType.submission => 'ギブアップ',
  AdditionalCheckType.pinfall => 'フォール',
  AdditionalCheckType.bleeding => '流血',
  AdditionalCheckType.counterSuccess => '返し成功',
  AdditionalCheckType.down => 'ダウン',
};

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
    this.basicMoveIds = const {},
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

  /// Ver.0.7.7: レスラー固有の通常技（属性→技ID）。空なら共通の通常技を使う。
  final Map<MoveAttribute, String> basicMoveIds;

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
    Map<MoveAttribute, String>? basicMoveIds,
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
    basicMoveIds: basicMoveIds ?? this.basicMoveIds,
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
    if (basicMoveIds.isNotEmpty)
      'basicMoveIds': {
        for (final e in basicMoveIds.entries) e.key.name: e.value,
      },
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
        basicMoveIds: {
          for (final e in (json['basicMoveIds'] as Map? ?? const {}).entries)
            enumValue(MoveAttribute.values, e.key, 'basicMoveIds'):
                e.value as String,
        },
      );
}

/// Ver.0.8.0: デッキ構築の総ポイント上限（設定で変更可能）。
const int kDefaultDeckPointCap = 60;

/// 技リストの合計デッキポイント（デッキエディタのカウンタ用）。
int deckTotalPoints(Iterable<MoveDefinition> moves) =>
    moves.fold<int>(0, (sum, m) => sum + m.displayDeckPoints);

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
