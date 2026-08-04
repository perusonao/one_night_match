import '../wrestler_editor/models.dart' show MoveAttribute;

/// Technique Deck Rules（Phase 0仕様書 docs/rules/technique_deck_rules.md）の
/// データモデル基盤（Phase 1）。
///
/// このファイルは「保持・JSON入出力・軽量バリデーション」のみを目的とし、
/// 実戦エンジン（LevelMatchEngine相当）へは一切接続しない（Phase 4以降）。
/// classic/energyモード（lib/src/level_match/level_match_engine.dart）の
/// ロジック・データには一切変更を加えていない。

// ============================================================
// enum: 新モード識別子
// ============================================================

/// Technique Deck Rulesの有効/無効を識別する。
///
/// 【設計メモ】既存の `MatchResourceMode`（lib/src/level_match/
/// level_match_engine.dart、classic/energy）へ値を追加する案（候補:
/// `ResourceMode.techniqueDeck`）ではなく、独立した新enumとした。
///
/// 理由: `MatchResourceMode` は `LevelMatchEngine`/`LevelMatchState` 内の
/// 数十箇所の分岐（`evaluateMove`・`_consumeEnergy`・`_autoChooseMove`・
/// `_declareAttack` 等）で使われている。ここへ第3の値を追加すると、
/// Dartの `switch` が既存モードの分岐に対しても網羅性チェックで新しい
/// caseへの対応を要求する可能性があり、「既存のclassicモード・energy
/// モードのゲーム進行に影響を与えない」というPhase 1の方針に反する
/// リスクを持つ。Technique Deck専用のenumとして独立させることで、
/// 既存コードへの影響をゼロに保てる。
///
/// 実戦エンジンへ接続する段階（Phase 4以降）で、`MatchResourceMode`へ
/// 正式統合するか、独立エンジンのまま扱うかを改めて設計判断する
/// （docs/design/technique_deck_open_questions.md に追記）。
///
/// 既定値は `disabled`（現行モードのまま、Technique Deck Rulesは
/// 自動選択されない）。
enum TechniqueDeckResourceMode {
  /// Technique Deck Rulesが無効（既定値）。
  disabled,

  /// Technique Deck Rulesが有効。
  techniqueDeck,
}

// ============================================================
// enum: Technique Deck専用カード分類
// ============================================================

/// Technique Deck Rules専用の技カード分類。
///
/// 既存の `MoveCategory`（lib/src/wrestler_editor/models.dart:
/// normal/counter/finisher/basic）とは **別概念** であり、
/// 意図的に拡張していない。既存 `MoveCategory` は classic/energy
/// モードの実装・大量のテスト資産と強く結び付いているため、ここへ
/// Technique Deck専用の分類を混在させると、将来的にモード間の分岐が
/// 増えて混乱を招く（Phase 0のレビューで確認された方針）。
enum TechniqueCardCategory {
  /// 汎用通常技。
  normal,

  /// 特定レスラー専用の固有技。
  signature,

  /// 発動条件を持つ決着技。
  finisher,
}

// ============================================================
// enum: カード種別
// ============================================================

/// Technique Deck Rulesで扱うカードの種別。
/// 今回（Phase 1）は分類の保持のみを行い、各カードの実戦効果は実装しない。
enum TechniqueDeckCardType {
  technique,
  energy,
  escape,
  reversal,
  kickOut,
  ropeBreak,
  action,
}

// ============================================================
// enum: レスラー状態（表示用ラベル付き）
// ============================================================

/// Technique Deck Rules専用のレスラー状態。
/// Phase 1では状態遷移ロジックは実装しない（保持のみ）。
enum WrestlerPosture {
  /// スタンド。
  stand,

  /// ダウン。
  down,

  /// 疲労（ダウン表示に疲労マーカーを追加、仕様書11.1章）。
  fatigued,
}

/// 表示用ラベル（仕様書11.1章）。
extension WrestlerPostureLabel on WrestlerPosture {
  String get displayLabel => switch (this) {
    WrestlerPosture.stand => 'スタンド',
    WrestlerPosture.down => 'ダウン',
    WrestlerPosture.fatigued => '疲労',
  };
}

// ============================================================
// enum: 技の対象状態
// ============================================================

/// 技カードが使用可能な相手状態（仕様書11.3章）。
///
/// 【設計メモ】自分側の状態条件（例: 自分がダウン中のみ使用可能）も
/// 将来必要になる可能性があるが、Phase 0の仕様書に明記がないため
/// 今回は追加しない。必要性が生じた場合は
/// docs/design/technique_deck_open_questions.md へ未決定事項として
/// 追記すること（勝手に先行実装しない）。
enum TechniqueTargetState {
  /// 相手の状態を問わない。
  any,

  /// 相手がスタンド状態のときのみ使用可能。
  stand,

  /// 相手がダウン状態のときのみ使用可能。
  down,
}

// ============================================================
// JSON補助関数（未知値へのフォールバックを持つ、安全側の実装）
// ============================================================

/// 未知のenum文字列に遭遇しても例外を投げず、`fallback` へフォールバックする。
/// （既存 `enumValue()` は未知値で例外を投げる仕様のため、Technique Deckの
/// 「後方互換・安全な既定値」要件には使わず、専用の実装を用意する。）
T enumOrDefault<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return fallback;
}

/// 属性別コストマップをJSONから復元する。負数は0へ正規化し、
/// 未知の属性キーは無視する。
Map<MoveAttribute, int> _costMapFromJson(Object? raw) {
  final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  final result = <MoveAttribute, int>{};
  for (final attribute in MoveAttribute.values) {
    final value = map[attribute.name];
    final parsed = value is num ? value.toInt() : 0;
    result[attribute] = parsed < 0 ? 0 : parsed;
  }
  return result;
}

Map<String, int> _costMapToJson(Map<MoveAttribute, int> map) => {
  for (final attribute in MoveAttribute.values)
    attribute.name: (map[attribute] ?? 0) < 0 ? 0 : (map[attribute] ?? 0),
};

/// 属性別コストマップの正規化（負数除去）。モデル生成時にも適用し、
/// JSON経由でなくても不正値が混入しないようにする。
Map<MoveAttribute, int> normalizeCostMap(Map<MoveAttribute, int> raw) => {
  for (final entry in raw.entries)
    if (entry.value > 0) entry.key: entry.value,
};

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

int _mapHash(Map<Object?, Object?> map) =>
    Object.hashAllUnordered(map.entries.map((e) => Object.hash(e.key, e.value)));

/// 属性別コストマップ専用の等価判定。コストは「未指定の属性は0」という
/// 前提のtotal mapとして扱う（JSON往復では [_costMapFromJson] が全属性
/// キーを補完するため、直接構築時の部分マップと比較しても一致するように
/// する）。
bool _costMapEquals(Map<MoveAttribute, int> a, Map<MoveAttribute, int> b) {
  for (final attribute in MoveAttribute.values) {
    if ((a[attribute] ?? 0) != (b[attribute] ?? 0)) return false;
  }
  return true;
}

int _costMapHash(Map<MoveAttribute, int> map) => Object.hashAll([
  for (final attribute in MoveAttribute.values) map[attribute] ?? 0,
]);

/// 数値型の不整合（文字列等）でもクラッシュしないための安全なキャスト。
int? _intOrNull(Object? raw) => raw is num ? raw.toInt() : null;
double? _doubleOrNull(Object? raw) => raw is num ? raw.toDouble() : null;
bool _boolOrDefault(Object? raw, bool fallback) => raw is bool ? raw : fallback;
String? _stringOrNull(Object? raw) => raw is String ? raw : null;
String _stringOrDefault(Object? raw, String fallback) =>
    raw is String ? raw : fallback;

// ============================================================
// モデル: Technique Card
// ============================================================

/// Technique Deck Rules専用の技カードモデル（仕様書6章）。
///
/// 既存 `MoveDefinition`（lib/src/wrestler_editor/models.dart）を直接
/// 大幅拡張するのではなく、新規モデルとして独立させた。既存の技マスターと
/// 関連付けたい場合は [sourceMoveId] を使う（Phase 1では参照のみ保持し、
/// 解決・検証はしない）。
class TechniqueDeckTechniqueCard {
  const TechniqueDeckTechniqueCard({
    required this.id,
    required this.name,
    this.category = TechniqueCardCategory.normal,
    required this.attribute,
    this.allowedWrestlerIds = const [],
    this.minimumLevel = 1,
    this.attackEnergyCost = const {},
    this.reversalEnergyCost = const {},
    this.power = 0,
    this.heatDelta = 0,
    this.targetState = TechniqueTargetState.any,
    this.causesDown = false,
    this.hasPinEffect = false,
    this.hasSubmissionEffect = false,
    this.hasFinisherEffect = false,
    this.kickOutThreshold,
    this.kickOutHpRate,
    this.giveUpThreshold,
    this.giveUpHpCost,
    this.finisherRequirements = const {},
    this.description = '',
    this.sourceMoveId,
  });

  final String id;
  final String name;
  final TechniqueCardCategory category;
  final MoveAttribute attribute;
  final List<String> allowedWrestlerIds;
  final int minimumLevel;
  final Map<MoveAttribute, int> attackEnergyCost;
  final Map<MoveAttribute, int> reversalEnergyCost;
  final int power;
  final int heatDelta;
  final TechniqueTargetState targetState;
  final bool causesDown;
  final bool hasPinEffect;
  final bool hasSubmissionEffect;
  final bool hasFinisherEffect;
  final int? kickOutThreshold;
  final double? kickOutHpRate;
  final int? giveUpThreshold;
  final int? giveUpHpCost;

  /// フィニッシャー発動条件（仕様書10章）。Phase 0時点で条件の種類が
  /// 未確定のため型を固定しない。想定キー（正式仕様ではない、例示のみ）:
  /// - `minimumHeat`: 必要HEAT（int）
  /// - `maximumOpponentHp`: 相手HPがこの値以下（int）
  /// - `requiredOpponentState`: 相手の状態（`TechniqueTargetState.name`相当の文字列）
  /// - `requiredLevel`: 必要レベル（int）
  /// - `requiredUsedMoveIds`: 使用済み技IDの履歴条件（`List<String>`）
  /// - `requiresKickOutHistory`: キックアウト経験の有無（bool）
  /// これらはあくまで例示であり、Phase 1時点では正式仕様として固定しない。
  final Map<String, dynamic> finisherRequirements;
  final String description;

  /// 既存の技マスター（`MoveDefinition.id`）との関連付け（任意）。
  /// Phase 1では保持のみ。解決・整合性検証は行わない。
  final String? sourceMoveId;

  TechniqueDeckTechniqueCard copyWith({
    String? id,
    String? name,
    TechniqueCardCategory? category,
    MoveAttribute? attribute,
    List<String>? allowedWrestlerIds,
    int? minimumLevel,
    Map<MoveAttribute, int>? attackEnergyCost,
    Map<MoveAttribute, int>? reversalEnergyCost,
    int? power,
    int? heatDelta,
    TechniqueTargetState? targetState,
    bool? causesDown,
    bool? hasPinEffect,
    bool? hasSubmissionEffect,
    bool? hasFinisherEffect,
    Object? kickOutThreshold = _unset,
    Object? kickOutHpRate = _unset,
    Object? giveUpThreshold = _unset,
    Object? giveUpHpCost = _unset,
    Map<String, dynamic>? finisherRequirements,
    String? description,
    Object? sourceMoveId = _unset,
  }) => TechniqueDeckTechniqueCard(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    attribute: attribute ?? this.attribute,
    allowedWrestlerIds: allowedWrestlerIds ?? this.allowedWrestlerIds,
    minimumLevel: minimumLevel ?? this.minimumLevel,
    attackEnergyCost: attackEnergyCost ?? this.attackEnergyCost,
    reversalEnergyCost: reversalEnergyCost ?? this.reversalEnergyCost,
    power: power ?? this.power,
    heatDelta: heatDelta ?? this.heatDelta,
    targetState: targetState ?? this.targetState,
    causesDown: causesDown ?? this.causesDown,
    hasPinEffect: hasPinEffect ?? this.hasPinEffect,
    hasSubmissionEffect: hasSubmissionEffect ?? this.hasSubmissionEffect,
    hasFinisherEffect: hasFinisherEffect ?? this.hasFinisherEffect,
    kickOutThreshold: identical(kickOutThreshold, _unset)
        ? this.kickOutThreshold
        : kickOutThreshold as int?,
    kickOutHpRate: identical(kickOutHpRate, _unset)
        ? this.kickOutHpRate
        : kickOutHpRate as double?,
    giveUpThreshold: identical(giveUpThreshold, _unset)
        ? this.giveUpThreshold
        : giveUpThreshold as int?,
    giveUpHpCost: identical(giveUpHpCost, _unset)
        ? this.giveUpHpCost
        : giveUpHpCost as int?,
    finisherRequirements: finisherRequirements ?? this.finisherRequirements,
    description: description ?? this.description,
    sourceMoveId: identical(sourceMoveId, _unset)
        ? this.sourceMoveId
        : sourceMoveId as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category.name,
    'attribute': attribute.name,
    'allowedWrestlerIds': allowedWrestlerIds,
    'minimumLevel': minimumLevel,
    'attackEnergyCost': _costMapToJson(attackEnergyCost),
    'reversalEnergyCost': _costMapToJson(reversalEnergyCost),
    'power': power,
    'heatDelta': heatDelta,
    'targetState': targetState.name,
    'causesDown': causesDown,
    'hasPinEffect': hasPinEffect,
    'hasSubmissionEffect': hasSubmissionEffect,
    'hasFinisherEffect': hasFinisherEffect,
    if (kickOutThreshold != null) 'kickOutThreshold': kickOutThreshold,
    if (kickOutHpRate != null) 'kickOutHpRate': kickOutHpRate,
    if (giveUpThreshold != null) 'giveUpThreshold': giveUpThreshold,
    if (giveUpHpCost != null) 'giveUpHpCost': giveUpHpCost,
    'finisherRequirements': finisherRequirements,
    'description': description,
    if (sourceMoveId != null) 'sourceMoveId': sourceMoveId,
  };

  /// 欠落フィールドは既定値で補完し、不正な値でクラッシュしない。
  factory TechniqueDeckTechniqueCard.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final attributeRaw = json['attribute'];
    return TechniqueDeckTechniqueCard(
      id: id is String && id.isNotEmpty ? id : '',
      name: name is String ? name : '',
      category: enumOrDefault(
        TechniqueCardCategory.values,
        json['category'],
        TechniqueCardCategory.normal,
      ),
      attribute: enumOrDefault(
        MoveAttribute.values,
        attributeRaw,
        MoveAttribute.strike,
      ),
      allowedWrestlerIds: (json['allowedWrestlerIds'] as List?)
              ?.whereType<String>()
              .toList() ??
          const [],
      minimumLevel: _intOrNull(json['minimumLevel']) ?? 1,
      attackEnergyCost: _costMapFromJson(json['attackEnergyCost']),
      reversalEnergyCost: _costMapFromJson(json['reversalEnergyCost']),
      power: _intOrNull(json['power']) ?? 0,
      heatDelta: _intOrNull(json['heatDelta']) ?? 0,
      targetState: enumOrDefault(
        TechniqueTargetState.values,
        json['targetState'],
        TechniqueTargetState.any,
      ),
      causesDown: _boolOrDefault(json['causesDown'], false),
      hasPinEffect: _boolOrDefault(json['hasPinEffect'], false),
      hasSubmissionEffect: _boolOrDefault(json['hasSubmissionEffect'], false),
      hasFinisherEffect: _boolOrDefault(json['hasFinisherEffect'], false),
      kickOutThreshold: _intOrNull(json['kickOutThreshold']),
      kickOutHpRate: _doubleOrNull(json['kickOutHpRate']),
      giveUpThreshold: _intOrNull(json['giveUpThreshold']),
      giveUpHpCost: _intOrNull(json['giveUpHpCost']),
      finisherRequirements: json['finisherRequirements'] is Map
          ? Map<String, dynamic>.from(json['finisherRequirements'] as Map)
          : const {},
      description: _stringOrDefault(json['description'], ''),
      sourceMoveId: _stringOrNull(json['sourceMoveId']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TechniqueDeckTechniqueCard &&
      id == other.id &&
      name == other.name &&
      category == other.category &&
      attribute == other.attribute &&
      _listEquals(allowedWrestlerIds, other.allowedWrestlerIds) &&
      minimumLevel == other.minimumLevel &&
      _costMapEquals(attackEnergyCost, other.attackEnergyCost) &&
      _costMapEquals(reversalEnergyCost, other.reversalEnergyCost) &&
      power == other.power &&
      heatDelta == other.heatDelta &&
      targetState == other.targetState &&
      causesDown == other.causesDown &&
      hasPinEffect == other.hasPinEffect &&
      hasSubmissionEffect == other.hasSubmissionEffect &&
      hasFinisherEffect == other.hasFinisherEffect &&
      kickOutThreshold == other.kickOutThreshold &&
      kickOutHpRate == other.kickOutHpRate &&
      giveUpThreshold == other.giveUpThreshold &&
      giveUpHpCost == other.giveUpHpCost &&
      _mapEquals(finisherRequirements, other.finisherRequirements) &&
      description == other.description &&
      sourceMoveId == other.sourceMoveId;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    category,
    attribute,
    _listEquals(allowedWrestlerIds, const []) ? 0 : allowedWrestlerIds.length,
    minimumLevel,
    _costMapHash(attackEnergyCost),
    _costMapHash(reversalEnergyCost),
    power,
    heatDelta,
    targetState,
    Object.hash(
      causesDown,
      hasPinEffect,
      hasSubmissionEffect,
      hasFinisherEffect,
      kickOutThreshold,
      kickOutHpRate,
      giveUpThreshold,
      giveUpHpCost,
    ),
  );

  @override
  String toString() =>
      'TechniqueDeckTechniqueCard(id: $id, name: $name, category: $category)';
}

/// `copyWith` で「nullを明示的にセットする」と「未指定」を区別するための
/// 番兵値。
const Object _unset = Object();

// ============================================================
// モデル: Technique Energy Card
// ============================================================

/// Technique Deck Rules専用の技エネルギーカードの定義（仕様書3.3章）。
/// ready/used状態は試合中インスタンスの状態であり、定義モデルには含めない。
class TechniqueEnergyCard {
  const TechniqueEnergyCard({
    required this.id,
    required this.attribute,
    required this.name,
  });

  final String id;
  final MoveAttribute attribute;
  final String name;

  TechniqueEnergyCard copyWith({
    String? id,
    MoveAttribute? attribute,
    String? name,
  }) => TechniqueEnergyCard(
    id: id ?? this.id,
    attribute: attribute ?? this.attribute,
    name: name ?? this.name,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'attribute': attribute.name,
    'name': name,
  };

  factory TechniqueEnergyCard.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    return TechniqueEnergyCard(
      id: id is String && id.isNotEmpty ? id : '',
      attribute: enumOrDefault(
        MoveAttribute.values,
        json['attribute'],
        MoveAttribute.strike,
      ),
      name: name is String ? name : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TechniqueEnergyCard &&
      id == other.id &&
      attribute == other.attribute &&
      name == other.name;

  @override
  int get hashCode => Object.hash(id, attribute, name);

  @override
  String toString() => 'TechniqueEnergyCard(id: $id, attribute: $attribute)';
}

// ============================================================
// モデル: 特殊防御カード（Escape/Reversal/KickOut/RopeBreak共通）
// ============================================================

/// Escape／Reversal／KickOut／RopeBreakの最小共通モデル（仕様書9章）。
/// Phase 1では効果実装を行わず、JSONで保持・復元できることのみを対象とする。
/// [effects] の具体的なキーは未決定（docs/design/technique_deck_open_questions.md）
/// のため、エンジン側から参照しないこと。
class TechniqueDefenseCard {
  const TechniqueDefenseCard({
    required this.id,
    required this.name,
    required this.type,
    this.description = '',
    this.requirements = const {},
    this.effects = const {},
  });

  final String id;
  final String name;

  /// escape / reversal / kickOut / ropeBreak のいずれかを想定するが、
  /// Phase 1では [TechniqueDeckCardType] の値をそのまま保持するのみで
  /// 型レベルの制約は課さない。
  final TechniqueDeckCardType type;
  final String description;
  final Map<String, dynamic> requirements;
  final Map<String, dynamic> effects;

  TechniqueDefenseCard copyWith({
    String? id,
    String? name,
    TechniqueDeckCardType? type,
    String? description,
    Map<String, dynamic>? requirements,
    Map<String, dynamic>? effects,
  }) => TechniqueDefenseCard(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    description: description ?? this.description,
    requirements: requirements ?? this.requirements,
    effects: effects ?? this.effects,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'description': description,
    'requirements': requirements,
    'effects': effects,
  };

  factory TechniqueDefenseCard.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    return TechniqueDefenseCard(
      id: id is String && id.isNotEmpty ? id : '',
      name: name is String ? name : '',
      // 未知typeは安全側でescapeへフォールバック。
      type: enumOrDefault(
        TechniqueDeckCardType.values,
        json['type'],
        TechniqueDeckCardType.escape,
      ),
      description: _stringOrDefault(json['description'], ''),
      requirements: json['requirements'] is Map
          ? Map<String, dynamic>.from(json['requirements'] as Map)
          : const {},
      effects: json['effects'] is Map
          ? Map<String, dynamic>.from(json['effects'] as Map)
          : const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TechniqueDefenseCard &&
      id == other.id &&
      name == other.name &&
      type == other.type &&
      description == other.description &&
      _mapEquals(requirements, other.requirements) &&
      _mapEquals(effects, other.effects);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    type,
    description,
    _mapHash(requirements),
    _mapHash(effects),
  );

  @override
  String toString() => 'TechniqueDefenseCard(id: $id, type: $type)';
}

// ============================================================
// モデル: レスラー別Technique Deck設定
// ============================================================

/// 既存レスラーモデル（`WrestlerDefinition`）を変更せず、Technique Deck
/// Rules用の設定を専用profileとして分離する（仕様書13章の`recoveryPower`等）。
/// Phase 1では休息処理や使用可否判定へ接続しない（保持のみ）。
class TechniqueDeckWrestlerProfile {
  const TechniqueDeckWrestlerProfile({
    required this.wrestlerId,
    this.recoveryPower = 0,
    this.allowedSignatureCardIds = const [],
    this.allowedFinisherCardIds = const [],
  });

  final String wrestlerId;
  final int recoveryPower;
  final List<String> allowedSignatureCardIds;
  final List<String> allowedFinisherCardIds;

  TechniqueDeckWrestlerProfile copyWith({
    String? wrestlerId,
    int? recoveryPower,
    List<String>? allowedSignatureCardIds,
    List<String>? allowedFinisherCardIds,
  }) => TechniqueDeckWrestlerProfile(
    wrestlerId: wrestlerId ?? this.wrestlerId,
    recoveryPower: recoveryPower ?? this.recoveryPower,
    allowedSignatureCardIds:
        allowedSignatureCardIds ?? this.allowedSignatureCardIds,
    allowedFinisherCardIds:
        allowedFinisherCardIds ?? this.allowedFinisherCardIds,
  );

  Map<String, dynamic> toJson() => {
    'wrestlerId': wrestlerId,
    'recoveryPower': recoveryPower,
    'allowedSignatureCardIds': allowedSignatureCardIds,
    'allowedFinisherCardIds': allowedFinisherCardIds,
  };

  factory TechniqueDeckWrestlerProfile.fromJson(Map<String, dynamic> json) {
    final wrestlerId = json['wrestlerId'];
    return TechniqueDeckWrestlerProfile(
      wrestlerId: wrestlerId is String && wrestlerId.isNotEmpty
          ? wrestlerId
          : '',
      recoveryPower: _intOrNull(json['recoveryPower']) ?? 0,
      allowedSignatureCardIds: (json['allowedSignatureCardIds'] as List?)
              ?.whereType<String>()
              .toList() ??
          const [],
      allowedFinisherCardIds: (json['allowedFinisherCardIds'] as List?)
              ?.whereType<String>()
              .toList() ??
          const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TechniqueDeckWrestlerProfile &&
      wrestlerId == other.wrestlerId &&
      recoveryPower == other.recoveryPower &&
      _listEquals(allowedSignatureCardIds, other.allowedSignatureCardIds) &&
      _listEquals(allowedFinisherCardIds, other.allowedFinisherCardIds);

  @override
  int get hashCode => Object.hash(
    wrestlerId,
    recoveryPower,
    allowedSignatureCardIds.length,
    allowedFinisherCardIds.length,
  );

  @override
  String toString() =>
      'TechniqueDeckWrestlerProfile(wrestlerId: $wrestlerId, recoveryPower: $recoveryPower)';
}

// ============================================================
// コンテナ: Technique Deckカード定義カタログ
// ============================================================

/// Phase 2のデッキ生成で利用するためのカード定義コンテナ。
/// 今回（Phase 1）は保持・ID検索・種別検索・JSON入出力・重複ID検出のみ。
/// 実際のデッキ生成・30枚検証はPhase 2で実装する。
class TechniqueDeckCardCatalog {
  const TechniqueDeckCardCatalog({
    this.techniques = const [],
    this.energies = const [],
    this.defenseCards = const [],
  });

  final List<TechniqueDeckTechniqueCard> techniques;
  final List<TechniqueEnergyCard> energies;
  final List<TechniqueDefenseCard> defenseCards;

  TechniqueDeckTechniqueCard? findTechniqueById(String id) {
    for (final card in techniques) {
      if (card.id == id) return card;
    }
    return null;
  }

  TechniqueEnergyCard? findEnergyById(String id) {
    for (final card in energies) {
      if (card.id == id) return card;
    }
    return null;
  }

  TechniqueDefenseCard? findDefenseCardById(String id) {
    for (final card in defenseCards) {
      if (card.id == id) return card;
    }
    return null;
  }

  List<TechniqueDeckTechniqueCard> techniquesByCategory(
    TechniqueCardCategory category,
  ) => techniques.where((card) => card.category == category).toList();

  List<TechniqueDefenseCard> defenseCardsByType(TechniqueDeckCardType type) =>
      defenseCards.where((card) => card.type == type).toList();

  /// カタログ全体（technique/energy/defense）を横断して重複しているIDを返す。
  /// カード種別が異なっても、IDは一意である前提のヘルパー。
  List<String> findDuplicateIds() {
    final seen = <String>{};
    final duplicates = <String>{};
    for (final id in [
      ...techniques.map((c) => c.id),
      ...energies.map((c) => c.id),
      ...defenseCards.map((c) => c.id),
    ]) {
      if (!seen.add(id)) duplicates.add(id);
    }
    return duplicates.toList();
  }

  Map<String, dynamic> toJson() => {
    'techniques': techniques.map((c) => c.toJson()).toList(),
    'energies': energies.map((c) => c.toJson()).toList(),
    'defenseCards': defenseCards.map((c) => c.toJson()).toList(),
  };

  factory TechniqueDeckCardCatalog.fromJson(Map<String, dynamic> json) =>
      TechniqueDeckCardCatalog(
        techniques: (json['techniques'] as List? ?? const [])
            .map((item) => TechniqueDeckTechniqueCard.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(),
        energies: (json['energies'] as List? ?? const [])
            .map((item) => TechniqueEnergyCard.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(),
        defenseCards: (json['defenseCards'] as List? ?? const [])
            .map((item) => TechniqueDefenseCard.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(),
      );
}
