/// Combat Ver.1 Phase 1〜2テスト共通フィクスチャ。
///
/// 正式レスラー／技データ（Phase 10予定、docs/combat_rules_v1.md 21・22章）
/// ではなく、Core Skeleton／Deck・Handループ検証専用の最小データを提供する
/// （docs/design/combat_v1_phase1_design.md 9章の方針）。
/// `_test.dart`という命名ではないため、`flutter test`からは直接テスト
/// スイートとして実行されず、他のテストファイルから共有ヘルパーとして
/// importする。
library;

import 'dart:math';

import 'package:one_night_match/src/combat_v1/combat_v1_counter.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_engine.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_match_state.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_wrestler.dart';

const CombatV1RulesConfig fixtureRules = CombatV1RulesConfig();

/// Phase 1〜3時代の`playTechnique`（宣言と同時に即時成功解決していた）と
/// 同じ結果を得るためのテスト専用ヘルパー（Phase 4、docs/combat_rules_v1.md
/// 「31-J Regression」）。
///
/// Phase 4では`declareTechnique`は宣言のみを行い、実際の解決は
/// `playCounter`／`declineCounter`が別途行う（`counterResponsePending`）。
/// COUNTERを一切使わないテストで「宣言→即解決」という旧来の挙動を再現する
/// ために、宣言直後に`declineCounter`を呼ぶだけの薄いラッパーとして提供する
/// （ゲーム結果としてdecline経路はPhase 3の即時成功解決と同じになる）。
CombatV1MatchState declareAndResolveTechnique(
  CombatV1MatchState state,
  String instanceId, {
  required CombatV1CardCatalog catalog,
  Random? random,
}) {
  final declared = CombatV1Engine.declareTechnique(
    state,
    instanceId,
    catalog: catalog,
  );
  return CombatV1Engine.declineCounter(declared, random: random);
}

const CombatV1Wrestler fixtureWrestlerA = CombatV1Wrestler(
  id: 'fx_wrestler_a',
  name: 'テストファイターA',
  energyPool: CombatV1EnergyPool({
    CombatV1EnergyAttribute.strike: 3,
    CombatV1EnergyAttribute.joint: 1,
    CombatV1EnergyAttribute.throwing: 2,
    CombatV1EnergyAttribute.aerial: 1,
    CombatV1EnergyAttribute.rough: 1,
    CombatV1EnergyAttribute.wild: 2,
  }),
);

const CombatV1Wrestler fixtureWrestlerB = CombatV1Wrestler(
  id: 'fx_wrestler_b',
  name: 'テストファイターB',
  energyPool: CombatV1EnergyPool({
    CombatV1EnergyAttribute.strike: 2,
    CombatV1EnergyAttribute.joint: 2,
    CombatV1EnergyAttribute.throwing: 1,
    CombatV1EnergyAttribute.aerial: 1,
    CombatV1EnergyAttribute.rough: 0,
    CombatV1EnergyAttribute.wild: 2,
  }),
);

/// テスト用技カタログ（NORMAL/SIGNATURE/FINISHERを一通りカバー）。
///
/// NORMALは6種類（同名上限3枚 × 6種類 = 18枚）用意する。フィクスチャデッキ
/// （[fixtureDeck]）が同名カード上限（docs/combat_rules_v1.md 3章）ちょうど
/// で30枚構成を満たせるようにするための種類数（Phase 2で追加）。
const Map<String, CombatV1Technique> fixtureTechniques = {
  'fx_normal_strike': CombatV1Technique(
    id: 'fx_normal_strike',
    name: 'テスト打撃技',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
    damage: 10,
    heatGain: 10,
    family: CombatV1TechniqueFamily.elbow,
  ),
  'fx_normal_throw_down': CombatV1Technique(
    id: 'fx_normal_throw_down',
    name: 'テストダウン投げ技',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.throwing,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 1}),
    damage: 20,
    heatGain: 20,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.slam,
  ),
  'fx_normal_ground': CombatV1Technique(
    id: 'fx_normal_ground',
    name: 'テストダウン限定技',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
    damage: 10,
    heatGain: 20,
    requiredOpponentState: CombatV1WrestlerPosture.down,
    resultOpponentState: CombatV1WrestlerPosture.down,
    family: CombatV1TechniqueFamily.stomp,
  ),
  'fx_normal_combo_cost': CombatV1Technique(
    id: 'fx_normal_combo_cost',
    name: 'テスト複合コスト技',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.aerial,
    energyCost: CombatV1EnergyCost({
      CombatV1EnergyAttribute.strike: 2,
      CombatV1EnergyAttribute.throwing: 1,
    }),
    damage: 15,
    heatGain: 15,
    family: CombatV1TechniqueFamily.dropKick,
  ),
  'fx_normal_strike_alt': CombatV1Technique(
    id: 'fx_normal_strike_alt',
    name: 'テスト打撃技2',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
    damage: 10,
    heatGain: 10,
    family: CombatV1TechniqueFamily.chop,
  ),
  'fx_normal_throw_alt': CombatV1Technique(
    id: 'fx_normal_throw_alt',
    name: 'テスト投げ技2',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.throwing,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 1}),
    damage: 10,
    heatGain: 10,
    family: CombatV1TechniqueFamily.backdrop,
  ),
  'fx_signature_a': CombatV1Technique(
    id: 'fx_signature_a',
    name: 'テスト固有技A',
    category: CombatV1CardCategory.signature,
    attribute: CombatV1EnergyAttribute.joint,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 1}),
    damage: 20,
    heatGain: 20,
    family: CombatV1TechniqueFamily.armbar,
  ),
  'fx_signature_b': CombatV1Technique(
    id: 'fx_signature_b',
    name: 'テスト固有技B',
    category: CombatV1CardCategory.signature,
    attribute: CombatV1EnergyAttribute.aerial,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.aerial: 1}),
    damage: 20,
    heatGain: 20,
    submissionHold: true,
    family: CombatV1TechniqueFamily.bodyPress,
  ),
  'fx_finisher_a': CombatV1Technique(
    id: 'fx_finisher_a',
    name: 'テストフィニッシャーA',
    category: CombatV1CardCategory.finisher,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 2}),
    damage: 30,
    heatGain: 30,
    finisherType: CombatV1FinisherType.normal,
    family: CombatV1TechniqueFamily.lariat,
  ),
  'fx_finisher_b': CombatV1Technique(
    id: 'fx_finisher_b',
    name: 'テストフィニッシャーB',
    category: CombatV1CardCategory.finisher,
    attribute: CombatV1EnergyAttribute.throwing,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 2}),
    damage: 30,
    heatGain: 30,
    directPin: true,
    finisherType: CombatV1FinisherType.directPin,
    family: CombatV1TechniqueFamily.powerbomb,
  ),
};

/// テスト用COUNTERカタログ（3種類、同名上限2枚 × 3種類 = 6枚）。
/// Phase 4でfamily/groupの成立判定に使う対象を設定する。
/// docs/combat_rules_v1.md 3・7章（COUNTERカードのテスト用fixture方針）の広範囲/中範囲/専門の
/// 方針に沿って3段階の範囲を用意する。
const Map<String, CombatV1Counter> fixtureCounters = {
  /// 広範囲: STRIKE group全体を返せる（打属性で支払う）。
  'fx_counter_a': CombatV1Counter(
    id: 'fx_counter_a',
    name: 'テストカウンターA',
    attribute: CombatV1EnergyAttribute.strike,
    counterableGroups: [CombatV1TechniqueFamilyGroup.strike],
  ),

  /// 中範囲: backdrop/suplex系統のみ返せる（投属性で支払う）。
  'fx_counter_b': CombatV1Counter(
    id: 'fx_counter_b',
    name: 'テストカウンターB',
    attribute: CombatV1EnergyAttribute.throwing,
    counterableFamilies: [
      CombatV1TechniqueFamily.backdrop,
      CombatV1TechniqueFamily.suplex,
    ],
  ),

  /// 専門: dropKickのみ返せる（飛属性で支払う）。
  'fx_counter_c': CombatV1Counter(
    id: 'fx_counter_c',
    name: 'テストカウンターC',
    attribute: CombatV1EnergyAttribute.aerial,
    counterableFamilies: [CombatV1TechniqueFamily.dropKick],
  ),
};

/// [fixtureTechniques]・[fixtureCounters]を横断参照するテスト用カタログ
/// （Deck validation用、docs/combat_rules_v1.md 4章）。
const CombatV1CardCatalog fixtureCatalog = CombatV1CardCatalog(
  techniques: fixtureTechniques,
  counters: fixtureCounters,
);

/// Phase 4テスト共通: 任意のフィールドを指定してMatchStateを直接組み立てる
/// 汎用ヘルパー（`combat_v1_engine_test.dart`の`buildActionState`／
/// `combat_v1_technique_legality_test.dart`の`_buildState`と同じ方針を、
/// pendingAttack関連のテスト（Phase 4の新規テストファイル群）向けに
/// playerB側のフィールドも直接指定できるよう拡張したもの）。
CombatV1MatchState buildMatchState({
  CombatV1MatchPhase phase = CombatV1MatchPhase.action,
  List<CombatV1DeckEntry> handA = const [],
  List<CombatV1DeckEntry> drawPileA = const [],
  List<CombatV1DeckEntry> discardPileA = const [],
  List<CombatV1DeckEntry> handB = const [],
  List<CombatV1DeckEntry> drawPileB = const [],
  List<CombatV1DeckEntry> discardPileB = const [],
  int hpA = 150,
  int hpB = 150,
  Map<CombatV1EnergyAttribute, int> spentA = const {},
  Map<CombatV1EnergyAttribute, int> spentB = const {},
  CombatV1WrestlerPosture postureA = CombatV1WrestlerPosture.stand,
  CombatV1WrestlerPosture postureB = CombatV1WrestlerPosture.stand,
  int sharedHeat = 0,
  int techniquesUsedA = 0,
  int techniquesUsedB = 0,
  int activePlayerIndex = 0,
}) {
  final playerA = CombatV1PlayerState(
    wrestlerId: fixtureWrestlerA.id,
    wrestlerName: fixtureWrestlerA.name,
    maxHp: 150,
    hp: hpA,
    koc: 10,
    pinCardsHeld: 2,
    posture: postureA,
    energyPool: fixtureWrestlerA.energyPool,
    spentEnergy: spentA,
    hand: handA,
    drawPile: drawPileA,
    discardPile: discardPileA,
    techniquesUsedThisTurn: techniquesUsedA,
  );
  final playerB = CombatV1PlayerState(
    wrestlerId: fixtureWrestlerB.id,
    wrestlerName: fixtureWrestlerB.name,
    maxHp: 150,
    hp: hpB,
    koc: 10,
    pinCardsHeld: 2,
    posture: postureB,
    energyPool: fixtureWrestlerB.energyPool,
    spentEnergy: spentB,
    hand: handB,
    drawPile: drawPileB,
    discardPile: discardPileB,
    techniquesUsedThisTurn: techniquesUsedB,
  );
  return CombatV1MatchState(
    matchId: 'phase4-test-match',
    playerA: playerA,
    playerB: playerB,
    activePlayerIndex: activePlayerIndex,
    sharedHeat: sharedHeat,
    turnNumber: 1,
    phase: phase,
  );
}

/// カード内訳の指定から物理カード（[CombatV1DeckEntry]）のリストを生成する
/// （instanceIdはユニーク）。テストで様々な（正しい／不正な）デッキを
/// 組み立てるための共通ヘルパー（docs/combat_rules_v1.md 3・4章）。
List<CombatV1DeckEntry> buildDeckEntries(
  String wrestlerId,
  List<(String cardId, CombatV1CardCategory category, int count)> spec,
) {
  final entries = <CombatV1DeckEntry>[];
  var seq = 0;
  for (final (cardId, category, count) in spec) {
    for (var i = 0; i < count; i++) {
      entries.add(
        CombatV1DeckEntry(
          instanceId: '${wrestlerId}_${cardId}_#${seq++}',
          cardId: cardId,
          category: category,
        ),
      );
    }
  }
  return entries;
}

/// フィクスチャデッキの標準カード内訳（NORMAL18/SIGNATURE4/FINISHER2/
/// COUNTER6、同名カード上限ちょうどに収まる構成、docs/combat_rules_v1.md
/// 3章）。
const List<(String, CombatV1CardCategory, int)> fixtureDeckSpec = [
  ('fx_normal_strike', CombatV1CardCategory.normal, 3),
  ('fx_normal_throw_down', CombatV1CardCategory.normal, 3),
  ('fx_normal_ground', CombatV1CardCategory.normal, 3),
  ('fx_normal_combo_cost', CombatV1CardCategory.normal, 3),
  ('fx_normal_strike_alt', CombatV1CardCategory.normal, 3),
  ('fx_normal_throw_alt', CombatV1CardCategory.normal, 3),
  ('fx_signature_a', CombatV1CardCategory.signature, 2),
  ('fx_signature_b', CombatV1CardCategory.signature, 2),
  ('fx_finisher_a', CombatV1CardCategory.finisher, 1),
  ('fx_finisher_b', CombatV1CardCategory.finisher, 1),
  ('fx_counter_a', CombatV1CardCategory.counter, 2),
  ('fx_counter_b', CombatV1CardCategory.counter, 2),
  ('fx_counter_c', CombatV1CardCategory.counter, 2),
];

/// 30枚の正式なテスト用デッキ（NORMAL18/SIGNATURE4/FINISHER2/COUNTER6）を
/// 生成する。[validateDeck]・[fixtureRules]に対して常にvalidである。
CombatV1DeckDefinition fixtureDeck(String wrestlerId) => CombatV1DeckDefinition(
  wrestlerId: wrestlerId,
  entries: buildDeckEntries(wrestlerId, fixtureDeckSpec),
);
