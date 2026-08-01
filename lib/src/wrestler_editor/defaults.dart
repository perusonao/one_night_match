import 'models.dart';

Map<MoveAttribute, int> _cards([MoveAttribute? type, int count = 0]) => {
  for (final value in MoveAttribute.values) value: value == type ? count : 0,
};

final defaultEditorMoves = <MoveDefinition>[
  for (final item in const [
    ('dropkick', 'ドロップキック', MoveAttribute.strike, 14, 3),
    ('arm_drag', 'アームドラッグ', MoveAttribute.throwMove, 12, 2),
    ('running_knee', 'ランニングニー', MoveAttribute.strike, 18, 4),
    ('brainbuster', 'ブレーンバスター', MoveAttribute.throwMove, 22, 5),
    ('high_kick', 'ハイキック', MoveAttribute.strike, 24, 5),
    ('dragon_suplex', 'ドラゴンスープレックス', MoveAttribute.throwMove, 28, 6),
    ('lariat', '豪腕ラリアット', MoveAttribute.strike, 22, 3),
    ('powerbomb', 'パワーボム', MoveAttribute.throwMove, 26, 5),
    ('armbar', '腕ひしぎ十字固め', MoveAttribute.submission, 18, 4),
    ('figure_four', '足4の字固め', MoveAttribute.submission, 21, 5),
    ('heel_kick', 'ヒールキック', MoveAttribute.strike, 17, 4),
    ('chair_attack', 'チェアー攻撃', MoveAttribute.rough, 25, -2),
    ('moonsault', 'ムーンサルトプレス', MoveAttribute.aerial, 27, 7),
  ])
    MoveDefinition(
      id: item.$1,
      name: item.$2,
      category: MoveCategory.normal,
      attribute: item.$3,
      power: item.$4,
      heat: item.$5,
      requiredCards: _cards(item.$3, item.$4 >= 24 ? 3 : 2),
      discardAfterUse: _cards(),
      description: 'Ver.0.3エディタ用の仮技データです。',
    ),
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
  ),
  for (final item in const [
    ('high_speed_german', 'ハイスピード・ジャーマン', MoveAttribute.throwMove),
    ('gouda_driver', '豪田ドライバー', MoveAttribute.throwMove),
    ('silver_lock', '白銀式クロスロック', MoveAttribute.submission),
    ('black_butterfly', 'ブラック・バタフライ', MoveAttribute.aerial),
  ])
    MoveDefinition(
      id: item.$1,
      name: item.$2,
      category: MoveCategory.finisher,
      attribute: item.$3,
      power: 38,
      heat: 8,
      requiredCards: {..._cards(item.$3, 4), MoveAttribute.counter: 1},
      discardAfterUse: _cards(item.$3, 2),
      usageLimit: 1,
      markUsedAfterUse: true,
      additionalChecks: const [AdditionalCheckType.pinfall],
      description: 'Ver.0.3エディタ用の仮フィニッシャーです。',
    ),
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
      description: 'Ver.0.3エディタ用の仮能力データです。',
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
              value: level == 2 ? 50 : 20,
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

final defaultEditorWrestlers = <WrestlerDefinition>[
  for (final item in const [
    (
      'wrestler_akari',
      '火神アカリ',
      '紅蓮のニューヒロイン',
      EditorWrestlerType.babyface,
      '#E53935',
      'burning_spirit',
      'high_speed_german',
    ),
    (
      'wrestler_misaki',
      '豪田ミサキ',
      '鋼鉄の女帝',
      EditorWrestlerType.power,
      '#F9A825',
      'power_pressure',
      'gouda_driver',
    ),
    (
      'wrestler_reina',
      '白銀レイナ',
      'リングの魔術師',
      EditorWrestlerType.technician,
      '#8E8EAA',
      'silver_technique',
      'silver_lock',
    ),
    (
      'wrestler_jack',
      '黒蝶ジャック',
      '漆黒の悪女',
      EditorWrestlerType.heel,
      '#9C27B0',
      'heel_instinct',
      'black_butterfly',
    ),
  ])
    WrestlerDefinition(
      id: item.$1,
      name: item.$2,
      subtitle: item.$3,
      type: item.$4,
      maxHp: 100,
      description: '新ルール検討用の仮データです。既存Ver.0.2対戦には接続されません。',
      themeColor: item.$5,
      tags: [wrestlerTypeLabel(item.$4), '仮データ'],
      levels: [
        _level(item.$2, 1, const ['dropkick', 'arm_drag'], item.$6),
        _level(
          item.$2,
          2,
          const ['running_knee', 'brainbuster'],
          item.$6,
          counter: 'counter_brainbuster',
        ),
        _level(
          item.$2,
          3,
          const ['high_kick', 'dragon_suplex'],
          item.$6,
          counter: 'counter_brainbuster',
          finisher: item.$7,
        ),
      ],
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
    ),
];
