import 'models.dart';

Map<MoveAttribute, int> _cards([MoveAttribute? type, int count = 0]) => {
  for (final value in MoveAttribute.values) value: value == type ? count : 0,
};

/// Ver.0.5 用の技ビルダー。フォール／ギブアップ／ダウンのパラメータを持たせる。
MoveDefinition _move(
  String id,
  String name,
  MoveAttribute attribute,
  int power,
  int heat, {
  int cost = 1,
  MoveCategory category = MoveCategory.normal,
  bool pin = false,
  int pinPower = 0,
  bool submission = false,
  int submissionPower = 0,
  bool down = false,
  int? speed,
  List<MoveAttribute> cannotCounterTypes = const [],
  List<String> specialAbilities = const [],
  String description = 'Ver.0.5 検討用の仮技データです。',
}) {
  final checks = <AdditionalCheckType>[
    if (pin) AdditionalCheckType.pinfall,
    if (submission) AdditionalCheckType.submission,
    if (down) AdditionalCheckType.down,
  ];
  // 速度は威力から自動決定（重い技ほど遅い）。5刻みの目安。
  final autoSpeed = power >= 26
      ? 3
      : power >= 20
      ? 4
      : power >= 15
      ? 6
      : 8;
  return MoveDefinition(
    id: id,
    name: name,
    category: category,
    attribute: attribute,
    power: power,
    heat: heat,
    requiredCards: _cards(attribute, cost),
    discardAfterUse: _cards(),
    additionalChecks: checks.isEmpty ? const [AdditionalCheckType.none] : checks,
    canAttemptPin: pin,
    pinPower: pinPower,
    canAttemptSubmission: submission,
    submissionPower: submissionPower,
    speed: speed ?? autoSpeed,
    canPin: pin,
    canSubmit: submission,
    canKO: down,
    cannotCounterTypes: cannotCounterTypes,
    specialAbilities: specialAbilities,
    description: description,
  );
}

/// Ver.0.7 単体技（基本技）。コスト不要・決着不可・速い。
MoveDefinition _basic(
  String id,
  String name,
  MoveAttribute attribute,
  int power,
  int heat,
  int speed,
) => MoveDefinition(
  id: id,
  name: name,
  category: MoveCategory.basic,
  attribute: attribute,
  power: power,
  heat: heat,
  requiredCards: _cards(),
  discardAfterUse: _cards(),
  speed: speed,
  consumesSetCards: false,
  description: 'Ver.0.7 単体技。手札から直接使用（コスト不要・決着不可）。',
);

MoveDefinition _finisher(
  String id,
  String name,
  MoveAttribute attribute, {
  required bool pinfall,
  int strength = 12,
}) => MoveDefinition(
  id: id,
  name: name,
  category: MoveCategory.finisher,
  attribute: attribute,
  power: pinfall ? 38 : 36,
  heat: 8,
  // Ver.0.7.2: フィニッシャーを到達可能なコストに（4+返1 → 3）。切り札を実戦投入可能に。
  requiredCards: _cards(attribute, 3),
  discardAfterUse: _cards(attribute, 2),
  usageLimit: 1,
  markUsedAfterUse: true,
  additionalChecks: [
    pinfall ? AdditionalCheckType.pinfall : AdditionalCheckType.submission,
  ],
  canAttemptPin: pinfall,
  pinPower: pinfall ? strength : 0,
  pinBonusOnFinisher: pinfall ? 15 : 0,
  canAttemptSubmission: !pinfall,
  submissionPower: pinfall ? 0 : strength,
  submissionBonusOnFinisher: pinfall ? 0 : 15,
  speed: 2, // 表示用（Ver.0.7.2 以降フィニッシャーはSpeedクラッシュ対象外）
  canPin: pinfall,
  canSubmit: !pinfall,
  // Ver.0.7.2: フィニッシャーは通常技で割り込めない切り札。専用返し／受けのみ。
  ignoreNormalSpeed: true,
  allowedResponses: const ['dedicatedCounter', 'take'],
  description: 'Ver.0.7.2 のフィニッシャー。通常技では割り込めない切り札。',
);

/// Ver.0.9 技カードカタログ（属性→技）。
/// クラシックルール廃止に伴い、この一覧の唯一の用途はenergyモードの
/// 「技カード」（手札から使用・使用後は捨て札）の技実体。
/// 技エネルギーカード（場にセットする燃料。属性名のみを名乗る＝
/// moveAttributeLabel）や、レスラー固有のド派手な固有技名とは重ならない、
/// 汎用的だが実在感のある技名にする（3段階の役割を名前で見分けられる）。
final defaultBasicMoves = <MoveDefinition>[
  _basic('basic_strike', 'ジャブ', MoveAttribute.strike, 5, 5, 9),
  _basic('basic_throw', 'テイクダウン', MoveAttribute.throwMove, 10, 5, 6),
  _basic('basic_aerial', 'クロスボディ', MoveAttribute.aerial, 10, 10, 9),
  _basic('basic_submission', 'アームロック', MoveAttribute.submission, 5, 5, 6),
  _basic('basic_rough', 'ラフブロー', MoveAttribute.rough, 8, 3, 7),
  _basic('basic_counter', 'カウンター構え', MoveAttribute.counter, 4, 5, 10),
];

/// 属性→単体技ID の対応。
final basicMoveIdByAttribute = <MoveAttribute, String>{
  for (final move in defaultBasicMoves) move.attribute: move.id,
};

final defaultEditorMoves = <MoveDefinition>[
  // 打撃（KO=ダウン）。
  _move('dropkick', 'ドロップキック', MoveAttribute.strike, 14, 3, cost: 1),
  _move('elbow', 'エルボー', MoveAttribute.strike, 12, 2, cost: 1),
  _move('running_knee', 'ランニングニー', MoveAttribute.strike, 18, 4, cost: 2, down: true),
  _move('high_kick', 'ハイキック', MoveAttribute.strike, 24, 5, cost: 3, down: true, speed: 8),
  _move('lariat', '豪腕ラリアット', MoveAttribute.strike, 18, 3,
      cost: 2, down: true, cannotCounterTypes: [MoveAttribute.strike]),
  // 投げ（フォール可能）。
  _move('arm_drag', 'アームドラッグ', MoveAttribute.throwMove, 12, 2,
      cost: 1, pin: true, pinPower: 4),
  _move('body_slam', 'ボディスラム', MoveAttribute.throwMove, 15, 3,
      cost: 1, pin: true, pinPower: 2),
  _move('neckbreaker', 'ネックブリーカー', MoveAttribute.throwMove, 20, 4,
      cost: 2, pin: true, pinPower: 5),
  _move('brainbuster', 'ブレーンバスター', MoveAttribute.throwMove, 22, 5,
      cost: 2, pin: true, pinPower: 6, speed: 7),
  _move('backdrop', 'バックドロップ', MoveAttribute.throwMove, 18, 5,
      cost: 2, pin: true, pinPower: 3),
  _move('dragon_suplex', 'ドラゴンスープレックス', MoveAttribute.throwMove, 28, 6,
      cost: 3, pin: true, pinPower: 9, speed: 7),
  // Ver.0.7.2/0.7.3: 豪田ミサキ弱体化（フォール性能を抑制）。
  _move('powerbomb', 'パワーボム', MoveAttribute.throwMove, 20, 6,
      cost: 3, pin: true, pinPower: 3),
  // 関節（ギブアップ可能）。
  _move('armbar', '腕ひしぎ十字固め', MoveAttribute.submission, 18, 4,
      cost: 2, submission: true, submissionPower: 5),
  _move('figure_four', '足4の字固め', MoveAttribute.submission, 21, 5,
      cost: 2, submission: true, submissionPower: 6),
  _move('camel_clutch', 'キャメルクラッチ', MoveAttribute.submission, 19, 4,
      cost: 2, submission: true, submissionPower: 5),
  _move('cross_face', 'クロスフェイス', MoveAttribute.submission, 24, 5,
      cost: 3, submission: true, submissionPower: 8),
  // 凶（ヒール）。Ver.0.7.2: ジャックの“嫌らしさ” = 返しにくく高威力の妨害技。
  // Ver.0.7.3: ジャックの妨害技を高速化。cannotCounterに加えSpeedでも潰されにくくし、
  // “嫌らしく主導権を握る”個性を機能させる（速い単体技に一方的に負けない）。
  _move('rough_slam', 'ラフ投げ', MoveAttribute.rough, 22, 2,
      cost: 2, pin: true, pinPower: 8, speed: 9,
      specialAbilities: ['cannotCounter']),
  _move('low_blow', '急所攻撃', MoveAttribute.rough, 16, -1,
      cost: 1, down: true, speed: 9, specialAbilities: ['cannotCounter']),
  _move('chair_attack', 'チェアー攻撃', MoveAttribute.rough, 22, -2,
      cost: 2, pin: true, pinPower: 7, speed: 9,
      specialAbilities: ['cannotCounter']),
  _move('neckbreaker_heel', '毒霧ネックブリーカー', MoveAttribute.rough, 22, 1,
      cost: 2, pin: true, pinPower: 7, speed: 8,
      specialAbilities: ['cannotCounter']),
  // 飛（フォール可能）。
  _move('moonsault', 'ムーンサルトプレス', MoveAttribute.aerial, 27, 7,
      cost: 3, pin: true, pinPower: 7),
  // 返し技（Ver.0.5でも本格実装は見送り）。
  MoveDefinition(
    id: 'counter_brainbuster',
    name: '切り返しブレーンバスター',
    category: MoveCategory.counter,
    attribute: MoveAttribute.counter,
    power: 20,
    heat: 4,
    requiredCards: _cards(MoveAttribute.counter, 1),
    discardAfterUse: _cards(),
    successRate: 65,
    additionalChecks: const [AdditionalCheckType.counterSuccess],
    speed: 10, // 返し技は最速
    counterTypes: const [MoveAttribute.throwMove], // 投げ技を切り返す
  ),
  // フィニッシャー（各レスラー固有・決着直結）。
  // Ver.0.7.3: アカリのフィニッシャーを strike に。彼女のデッキ傾向（打撃/空中）と
  // 属性を一致させ、切り札を組み立て可能にする（決着ルートを機能させる）。
  _finisher('high_speed_german', 'ハイスピード・ジャーマン', MoveAttribute.strike,
      pinfall: true, strength: 15),
  _finisher('gouda_driver', '豪田ドライバー', MoveAttribute.throwMove,
      pinfall: true, strength: 7),
  _finisher('silver_lock', '白銀式クロスロック', MoveAttribute.submission,
      pinfall: false, strength: 13),
  _finisher('black_butterfly', 'ブラック・バタフライ', MoveAttribute.rough,
      pinfall: true, strength: 11),

  // ===== Ver.0.7.7：レスラー別に整理した固有技（重複・名前衝突を解消） =====
  // 性能は従来と同一。IDと技名だけをレスラー固有にして個性を明確化。
  // 火神アカリ（正統派・打撃/投げ）
  _move('akari_dropkick', '紅蓮ドロップキック', MoveAttribute.strike, 14, 3, cost: 1),
  _move('akari_armdrag', 'フェニックス・アームドラッグ', MoveAttribute.throwMove, 12, 2,
      cost: 1, pin: true, pinPower: 4),
  _move('akari_knee', 'ライジングニー', MoveAttribute.strike, 18, 4,
      cost: 2, down: true),
  _move('akari_brainbuster', '紅蓮ブレーンバスター', MoveAttribute.throwMove, 22, 5,
      cost: 2, pin: true, pinPower: 6, speed: 7),
  _move('akari_highkick', 'ソウルハイキック', MoveAttribute.strike, 24, 5,
      cost: 3, down: true, speed: 8),
  _move('akari_dragon', '紅蓮ドラゴンスープレックス', MoveAttribute.throwMove, 28, 6,
      cost: 3, pin: true, pinPower: 9, speed: 7),
  // 豪田ミサキ（パワー・打撃/投げ）
  _move('misaki_elbow', '鉄拳エルボー', MoveAttribute.strike, 12, 2, cost: 1),
  _move('misaki_bodyslam', 'ゴウダ・スラム', MoveAttribute.throwMove, 15, 3,
      cost: 1, pin: true, pinPower: 2),
  _move('misaki_lariat', '豪腕ラリアット', MoveAttribute.strike, 18, 3,
      cost: 2, down: true, cannotCounterTypes: [MoveAttribute.strike]),
  _move('misaki_powerbomb', 'アイアン・パワーボム', MoveAttribute.throwMove, 20, 6,
      cost: 3, pin: true, pinPower: 3),
  _move('misaki_knee', '圧殺ニー', MoveAttribute.strike, 18, 4,
      cost: 2, down: true),
  _move('misaki_backdrop', '鋼鉄バックドロップ', MoveAttribute.throwMove, 18, 5,
      cost: 2, pin: true, pinPower: 3),
  // 白銀レイナ（テクニシャン・関節主体）
  _move('reina_dropkick', '銀閃ドロップキック', MoveAttribute.strike, 14, 3, cost: 1),
  _move('reina_armbar', '銀の腕ひしぎ十字固め', MoveAttribute.submission, 18, 4,
      cost: 2, submission: true, submissionPower: 5),
  _move('reina_brainbuster', '白銀ブレーンバスター', MoveAttribute.throwMove, 22, 5,
      cost: 2, pin: true, pinPower: 6, speed: 7),
  _move('reina_figurefour', '銀糸の足4の字固め', MoveAttribute.submission, 21, 5,
      cost: 2, submission: true, submissionPower: 6),
  _move('reina_camel', '氷結キャメルクラッチ', MoveAttribute.submission, 19, 4,
      cost: 2, submission: true, submissionPower: 5),
  _move('reina_crossface', '白銀クロスフェイス', MoveAttribute.submission, 24, 5,
      cost: 3, submission: true, submissionPower: 8),
  // 黒蝶ジャック（ヒール・凶技主体／返しにくく速い）
  _move('jack_elbow', '闇討ちエルボー', MoveAttribute.strike, 12, 2, cost: 1),
  _move('jack_roughslam', 'ラフスラム', MoveAttribute.rough, 22, 2,
      cost: 2, pin: true, pinPower: 8, speed: 9,
      specialAbilities: ['cannotCounter']),
  _move('jack_lowblow', '急所ロー', MoveAttribute.rough, 16, -1,
      cost: 1, down: true, speed: 9, specialAbilities: ['cannotCounter']),
  _move('jack_neckbreaker', '毒霧ネックブリーカー', MoveAttribute.rough, 22, 1,
      cost: 2, pin: true, pinPower: 7, speed: 8,
      specialAbilities: ['cannotCounter']),
  _move('jack_chair', '凶器チェアーショット', MoveAttribute.rough, 22, -2,
      cost: 2, pin: true, pinPower: 7, speed: 9,
      specialAbilities: ['cannotCounter']),
  _move('jack_ddt', 'ブラッディDDT', MoveAttribute.rough, 22, 2,
      cost: 2, pin: true, pinPower: 8, speed: 9,
      specialAbilities: ['cannotCounter']),

  // ===== Ver.0.9：レスラー固有の技カード（性能のみ個性化） =====
  // 技エネルギーカード（属性名のみ）でも固有技（ド派手な固有名）でもない、
  // 「実在する技名」の技カードとしてレスラーごとに軽く個性を付ける。
  _basic('akari_nt_strike', '速射ジャブ', MoveAttribute.strike, 5, 5, 9),
  _basic('akari_nt_throw', 'スイングテイクダウン', MoveAttribute.throwMove, 10, 5, 6),
  _basic('misaki_nt_strike', '重量ジャブ', MoveAttribute.strike, 5, 5, 9),
  _basic('misaki_nt_throw', 'パワーテイクダウン', MoveAttribute.throwMove, 10, 5, 6),
  _basic('reina_nt_sub', 'テクニカルアームロック', MoveAttribute.submission, 5, 5, 6),
  _basic('reina_nt_strike', '精密ジャブ', MoveAttribute.strike, 5, 5, 9),
  _basic('jack_nt_rough', '闇討ちラフブロー', MoveAttribute.rough, 8, 3, 7),
  _basic('jack_nt_strike', '不意打ちジャブ', MoveAttribute.strike, 5, 5, 9),

  // Ver.0.7 単体技（全レスラー共通・手札から直接使用）。
  ...defaultBasicMoves,
];

final defaultEditorAbilities = <AbilityDefinition>[
  for (final item in const [
    ('burning_spirit', '燃える闘志'),
    ('power_pressure', '圧倒的パワー'),
    ('silver_technique', '白銀の技巧'),
    ('heel_instinct', 'ヒールの本能'),
  ])
    AbilityDefinition(
      id: item.$1,
      name: item.$2,
      description: 'Ver.0.5 用の仮能力データです。',
      timing: AbilityTiming.afterDamage,
      successEffects: const ['HEATを+1する'],
    ),
];

WrestlerLevelDefinition _level(
  String name,
  int level,
  List<String> moves,
  String ability, {
  String? counter,
  String? finisher,
}) => WrestlerLevelDefinition(
  level: level,
  displayName: '$name Level $level',
  unlockCondition: level == 1
      ? null
      : UnlockConditionGroup(
          operator: level == 2 ? ConditionOperator.or : ConditionOperator.and,
          conditions: [
            if (level == 3)
              const UnlockCondition(
                type: UnlockConditionType.previousLevelUnlocked,
              ),
            UnlockCondition(
              type: level == 2
                  ? UnlockConditionType.hpAtMost
                  : UnlockConditionType.heatAtLeast,
              value: level == 2 ? 70 : 20,
            ),
          ],
        ),
  resistances: {
    for (final attribute in MoveAttribute.values)
      attribute: (level - 1) * 5 + (attribute == MoveAttribute.strike ? 5 : 0),
  },
  moveIds: moves,
  counterMoveId: counter,
  abilityId: ability,
  finisherId: finisher,
  flavorText: level == 3 ? 'この一撃で、夜を終わらせる。' : 'ここからが私の試合！',
);

/// レスラーごとの技構成（個性を反映）。
class _WrestlerBlueprint {
  const _WrestlerBlueprint({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.type,
    required this.color,
    required this.ability,
    required this.finisher,
    required this.level1,
    required this.level2,
    required this.level3,
    this.basics = const {},
  });
  final String id;
  final String name;
  final String subtitle;
  final EditorWrestlerType type;
  final String color;
  final String ability;
  final String finisher;
  final List<String> level1;
  final List<String> level2;
  final List<String> level3;

  /// レスラー固有の通常技（属性→技ID）。未指定の属性は共通の通常技を使う。
  final Map<MoveAttribute, String> basics;
}

const _blueprints = <_WrestlerBlueprint>[
  _WrestlerBlueprint(
    id: 'wrestler_akari',
    name: '火神アカリ',
    subtitle: '紅蓮のニューヒロイン',
    type: EditorWrestlerType.babyface,
    color: '#E53935',
    ability: 'burning_spirit',
    finisher: 'high_speed_german',
    level1: ['akari_dropkick', 'akari_armdrag'],
    level2: ['akari_knee', 'akari_brainbuster'],
    level3: ['akari_highkick', 'akari_dragon'],
    basics: {
      MoveAttribute.strike: 'akari_nt_strike',
      MoveAttribute.throwMove: 'akari_nt_throw',
    },
  ),
  _WrestlerBlueprint(
    id: 'wrestler_misaki',
    name: '豪田ミサキ',
    subtitle: '鋼鉄の女帝',
    type: EditorWrestlerType.power,
    color: '#F9A825',
    ability: 'power_pressure',
    finisher: 'gouda_driver',
    level1: ['misaki_elbow', 'misaki_bodyslam'],
    level2: ['misaki_lariat', 'misaki_powerbomb'],
    level3: ['misaki_knee', 'misaki_backdrop'],
    basics: {
      MoveAttribute.strike: 'misaki_nt_strike',
      MoveAttribute.throwMove: 'misaki_nt_throw',
    },
  ),
  _WrestlerBlueprint(
    id: 'wrestler_reina',
    name: '白銀レイナ',
    subtitle: 'リングの魔術師',
    type: EditorWrestlerType.technician,
    color: '#8E8EAA',
    ability: 'silver_technique',
    finisher: 'silver_lock',
    level1: ['reina_dropkick', 'reina_armbar'],
    level2: ['reina_brainbuster', 'reina_figurefour'],
    level3: ['reina_camel', 'reina_crossface'],
    basics: {
      MoveAttribute.submission: 'reina_nt_sub',
      MoveAttribute.strike: 'reina_nt_strike',
    },
  ),
  _WrestlerBlueprint(
    id: 'wrestler_jack',
    name: '黒蝶ジャック',
    subtitle: '漆黒の悪女',
    type: EditorWrestlerType.heel,
    color: '#9C27B0',
    ability: 'heel_instinct',
    finisher: 'black_butterfly',
    // Ver.0.7.2/0.7.7: 返しにくい妨害技で主導権を握る“嫌らしい”構成。L3の重複を解消。
    level1: ['jack_elbow', 'jack_roughslam'],
    level2: ['jack_lowblow', 'jack_neckbreaker'],
    level3: ['jack_chair', 'jack_ddt'],
    basics: {
      MoveAttribute.rough: 'jack_nt_rough',
      MoveAttribute.strike: 'jack_nt_strike',
    },
  ),
];

/// Ver.0.7.3: レスラー別の最大HP（キックアウト耐久＝フォール応酬の強さ）。
const _maxHpById = <String, int>{
  'wrestler_akari': 125, // 打たれ強い主人公
  'wrestler_misaki': 82, // 一撃は重いが打たれ弱い女帝
  'wrestler_reina': 104, // 粘って関節で仕留めるテクニシャン
};

final defaultEditorWrestlers = <WrestlerDefinition>[
  for (final item in _blueprints)
    WrestlerDefinition(
      id: item.id,
      name: item.name,
      subtitle: item.subtitle,
      type: item.type,
      // Ver.0.7.3: 体力を個性化。HPはキックアウト耐久（フォール応酬）に効くため、
      // 打たれ強いアカリを厚く、一撃屋ミサキを薄くしてバランスを取る。
      maxHp: _maxHpById[item.id] ?? 100,
      description: 'Ver.0.5 フォール・ギブアップ試作版の仮データです。既存Ver.0.2対戦には接続されません。',
      themeColor: item.color,
      tags: [wrestlerTypeLabel(item.type), '仮データ'],
      levels: [
        _level(item.name, 1, item.level1, item.ability),
        _level(
          item.name,
          2,
          item.level2,
          item.ability,
          counter: 'counter_brainbuster',
        ),
        _level(
          item.name,
          3,
          item.level3,
          item.ability,
          counter: 'counter_brainbuster',
          finisher: item.finisher,
        ),
      ],
      basicMoveIds: item.basics,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
    ),
];
