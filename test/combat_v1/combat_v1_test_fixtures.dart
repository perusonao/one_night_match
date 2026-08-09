/// Combat Ver.1 Phase 1〜2テスト共通フィクスチャ。
///
/// 正式レスラー／技データ（Phase 10予定、docs/combat_rules_v1.md 21・22章）
/// ではなく、Core Skeleton／Deck・Handループ検証専用の最小データを提供する
/// （docs/design/combat_v1_phase1_design.md 9章の方針）。
/// `_test.dart`という命名ではないため、`flutter test`からは直接テスト
/// スイートとして実行されず、他のテストファイルから共有ヘルパーとして
/// importする。
library;

import 'package:one_night_match/src/combat_v1/combat_v1_counter.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck_validation.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_energy.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_enums.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_rules_config.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_technique.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_wrestler.dart';

const CombatV1RulesConfig fixtureRules = CombatV1RulesConfig();

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
  ),
  'fx_normal_strike_alt': CombatV1Technique(
    id: 'fx_normal_strike_alt',
    name: 'テスト打撃技2',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.strike,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.strike: 1}),
    damage: 10,
    heatGain: 10,
  ),
  'fx_normal_throw_alt': CombatV1Technique(
    id: 'fx_normal_throw_alt',
    name: 'テスト投げ技2',
    category: CombatV1CardCategory.normal,
    attribute: CombatV1EnergyAttribute.throwing,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.throwing: 1}),
    damage: 10,
    heatGain: 10,
  ),
  'fx_signature_a': CombatV1Technique(
    id: 'fx_signature_a',
    name: 'テスト固有技A',
    category: CombatV1CardCategory.signature,
    attribute: CombatV1EnergyAttribute.joint,
    energyCost: CombatV1EnergyCost({CombatV1EnergyAttribute.joint: 1}),
    damage: 20,
    heatGain: 20,
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
  ),
};

/// テスト用COUNTERカタログ（Phase 1〜2ではCOUNTERの戦闘処理は未実装。
/// デッキ構成検証・Deck/Hand/Draw/Discard/Reshuffleでの物理カードとしての
/// 取り扱いの検証にのみ使う）。3種類用意する（同名上限2枚 × 3種類 = 6枚、
/// Phase 2で1種類追加）。
const Map<String, CombatV1Counter> fixtureCounters = {
  'fx_counter_a': CombatV1Counter(
    id: 'fx_counter_a',
    name: 'テストカウンターA',
    attribute: CombatV1EnergyAttribute.strike,
  ),
  'fx_counter_b': CombatV1Counter(
    id: 'fx_counter_b',
    name: 'テストカウンターB',
    attribute: CombatV1EnergyAttribute.throwing,
  ),
  'fx_counter_c': CombatV1Counter(
    id: 'fx_counter_c',
    name: 'テストカウンターC',
    attribute: CombatV1EnergyAttribute.aerial,
  ),
};

/// [fixtureTechniques]・[fixtureCounters]を横断参照するテスト用カタログ
/// （Deck validation用、docs/combat_rules_v1.md 4章）。
const CombatV1CardCatalog fixtureCatalog = CombatV1CardCatalog(
  techniques: fixtureTechniques,
  counters: fixtureCounters,
);

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
