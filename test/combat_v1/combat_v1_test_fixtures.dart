/// Combat Ver.1 Phase 1テスト共通フィクスチャ。
///
/// 正式レスラー／技データ（Phase 10予定、docs/combat_rules_v1.md 21・22章）
/// ではなく、Core Skeletonのループ検証専用の最小データを提供する
/// （docs/design/combat_v1_phase1_design.md 9章の方針）。
/// `_test.dart`という命名ではないため、`flutter test`からは直接テスト
/// スイートとして実行されず、他の3ファイルから共有ヘルパーとしてimportする。
library;

import 'package:one_night_match/src/combat_v1/combat_v1_counter.dart';
import 'package:one_night_match/src/combat_v1/combat_v1_deck.dart';
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

/// テスト用COUNTERカタログ（Phase 1では未使用、デッキ構成検証のみに使う）。
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
};

/// 30枚のテスト用デッキ（NORMAL18/SIGNATURE4/FINISHER2/COUNTER6）を生成する。
CombatV1DeckDefinition fixtureDeck(String wrestlerId) {
  final entries = <CombatV1DeckEntry>[];
  var seq = 0;

  void add(String cardId, CombatV1CardCategory category, int count) {
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

  add('fx_normal_strike', CombatV1CardCategory.normal, 6);
  add('fx_normal_throw_down', CombatV1CardCategory.normal, 6);
  add('fx_normal_ground', CombatV1CardCategory.normal, 3);
  add('fx_normal_combo_cost', CombatV1CardCategory.normal, 3);
  add('fx_signature_a', CombatV1CardCategory.signature, 2);
  add('fx_signature_b', CombatV1CardCategory.signature, 2);
  add('fx_finisher_a', CombatV1CardCategory.finisher, 1);
  add('fx_finisher_b', CombatV1CardCategory.finisher, 1);
  add('fx_counter_a', CombatV1CardCategory.counter, 3);
  add('fx_counter_b', CombatV1CardCategory.counter, 3);

  return CombatV1DeckDefinition(wrestlerId: wrestlerId, entries: entries);
}
