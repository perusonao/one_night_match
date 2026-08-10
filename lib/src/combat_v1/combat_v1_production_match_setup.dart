/// Production Match Setup（docs/design/combat_v1_phase11a_production_match_setup.md、
/// Phase 11A）。
///
/// Production Wrestler（misaki/jack/akari/reina）を選択し、対応する
/// Production Deckとowner namespaceを安全に組み立てたうえで
/// `CombatV1Engine.start`（Core Engine）へ接続する、Production Data専用の
/// application/production layer entry point。
///
/// 現状はtestや将来のUI/CPU/Simulatorが、それぞれ個別に
/// 「wrestler catalogから取得→対応するdeck builderを選ぶ→ownerIdを決める→
/// productionCardCatalogを渡す→CombatV1Engine.startを呼ぶ」という手順を
/// 組み立て直していた（`combat_v1_production_wrestler_deck_integrity_test.dart`
/// 等）。本ファイルはこの手順のSSOTとなり、将来のHuman vs CPU・CPU vs
/// CPU・Simulator・UI・replay/debug toolsが同じ経路を利用できるようにする
/// （docs/design/combat_v1_phase11a_production_match_setup.md 1章）。
///
/// Core Engine（`combat_v1_engine.dart`）は変更しない。misaki/jack/akari/
/// reinaのようなProduction固有IDをCore Engineへ持ち込むこともしない——
/// [combatV1ProductionWrestlerRegistry]によるlookupはこのファイル（Production
/// layer）に閉じており、`CombatV1Engine.start`へは常に汎用的な
/// [CombatV1Wrestler]/[CombatV1DeckDefinition]として渡す（同2章）。
library;

import 'dart:math';

import 'combat_v1_deck.dart';
import 'combat_v1_decks.dart';
import 'combat_v1_engine.dart';
import 'combat_v1_match_state.dart';
import 'combat_v1_production_catalog.dart';
import 'combat_v1_rules_config.dart';
import 'combat_v1_wrestler.dart';
import 'combat_v1_wrestler_catalog.dart';

/// Production wrestlerIdから、そのwrestler専用のProduction Deckを構築する
/// 関数のシグネチャ（`buildMisakiDeck`等、`combat_v1_decks.dart`参照）。
typedef CombatV1ProductionDeckBuilder =
    CombatV1DeckDefinition Function({required String ownerId});

/// Production wrestlerIdに紐づく「静的プロフィール」と「専用Production Deck
/// builder」の組（Phase 11A）。
class CombatV1ProductionWrestlerEntry {
  const CombatV1ProductionWrestlerEntry({
    required this.wrestler,
    required this.buildDeck,
  });

  final CombatV1Wrestler wrestler;
  final CombatV1ProductionDeckBuilder buildDeck;
}

/// Production wrestlerId → [CombatV1ProductionWrestlerEntry] のレジストリ
/// （Phase 11A）。
///
/// misaki/jack/akari/reina個別のdeck builder選択をこの一箇所へ集約し、
/// call site側（本ファイル以外）が`if (wrestlerId == 'misaki') ...`のような
/// ハードコードされた分岐を書かずに済むようにする
/// （docs/design/combat_v1_phase11a_production_match_setup.md 4章）。
/// 呼び出し側からの変更を防ぐため`Map.unmodifiable`でラップする。
final Map<String, CombatV1ProductionWrestlerEntry>
combatV1ProductionWrestlerRegistry = Map.unmodifiable({
  misakiWrestler.id: CombatV1ProductionWrestlerEntry(
    wrestler: misakiWrestler,
    buildDeck: buildMisakiDeck,
  ),
  jackWrestler.id: CombatV1ProductionWrestlerEntry(
    wrestler: jackWrestler,
    buildDeck: buildJackDeck,
  ),
  akariWrestler.id: CombatV1ProductionWrestlerEntry(
    wrestler: akariWrestler,
    buildDeck: buildAkariDeck,
  ),
  reinaWrestler.id: CombatV1ProductionWrestlerEntry(
    wrestler: reinaWrestler,
    buildDeck: buildReinaDeck,
  ),
});

/// Production Match開始設定（Phase 11A）。immutable。
///
/// [wrestlerAId]/[wrestlerBId]は[combatV1ProductionWrestlerRegistry]の
/// キー（例: `"misaki"`）で、同じwrestlerId同士を指定するmirror
/// match（例: Misaki vs Misaki）も禁止しない。
///
/// [playerAOwnerId]/[playerBOwnerId]はphysical instanceId生成専用のowner
/// namespace（`combat_v1_decks.dart`の`ownerId`引数へそのまま渡す）で、
/// wrestlerId（レスラーの種類）ともcardId（カード定義identity）とも独立した
/// 概念。両者は異なる値でなければならない（同一の場合、physical instanceId
/// 衝突の原因になる）。
///
/// `matchId`はここでは扱わない——[CombatV1Engine.start]自身がmatchIdを
/// 内部生成しており（呼び出し側から受け取るパラメータを持たない）、この
/// 責務をProduction Match Setup層で肩代わりする、またはここで独自に
/// 日時・random UUIDを生成することはしない（Core Engineの変更なしにこの層
/// だけでmatchIdを差し替えることはできないため。
/// docs/design/combat_v1_phase11a_production_match_setup.md 6章）。
///
/// [rules]は既定で`const CombatV1RulesConfig()`（Core Engineの既定値と同一）
/// を使う。deterministic testabilityのため、呼び出し側が明示的に上書き
/// できるようにする。
class CombatV1ProductionMatchConfig {
  const CombatV1ProductionMatchConfig({
    required this.wrestlerAId,
    required this.wrestlerBId,
    required this.playerAOwnerId,
    required this.playerBOwnerId,
    this.rules = const CombatV1RulesConfig(),
  });

  final String wrestlerAId;
  final String wrestlerBId;
  final String playerAOwnerId;
  final String playerBOwnerId;
  final CombatV1RulesConfig rules;
}

/// Production Match開始のSSOT（Phase 11A）。
///
/// [CombatV1Engine.start]を置き換えるものではない。Core Engineは引き続き
/// 「両者のwrestler/deck/catalog/rulesを受け取り試合を開始する」汎用API
/// のままとし、本クラスはその手前でProduction Dataを安全に組み立てる
/// application/production layerとして責務を分離する
/// （docs/design/combat_v1_phase11a_production_match_setup.md 2章）。
class CombatV1ProductionMatchStarter {
  const CombatV1ProductionMatchStarter._();

  /// [config]からProduction Wrestler・Production Deckを安全に組み立て、
  /// [CombatV1Engine.start]を呼び出す。
  ///
  /// 検証はfail-fastで以下の順に行う。いずれかで
  /// [CombatV1IllegalActionException]を送出した場合、[CombatV1MatchState]は
  /// 一切構築しない（[CombatV1Engine.start]自身が持つatomicityと同じ方針）:
  ///
  /// 1. [CombatV1ProductionMatchConfig.wrestlerAId]をレジストリで解決
  ///    （unknownなら拒否）
  /// 2. [CombatV1ProductionMatchConfig.wrestlerBId]をレジストリで解決
  ///    （unknownなら拒否）
  /// 3. [CombatV1ProductionMatchConfig.playerAOwnerId]が空白のみでないことを
  ///    確認
  /// 4. [CombatV1ProductionMatchConfig.playerBOwnerId]が空白のみでないことを
  ///    確認
  /// 5. `playerAOwnerId != playerBOwnerId`を確認（physical instanceId衝突の
  ///    防止。`combat_v1_decks.dart`のownerId単体チェックとは責務が異なり、
  ///    こちらは「両player間で異なるか」をSetup時点で見る）
  ///
  /// 上記をすべて満たした場合のみ、各wrestler向けのProduction Deckを
  /// それぞれのowner namespaceで生成し、[productionCardCatalog]と
  /// [CombatV1ProductionMatchConfig.rules]を使って[CombatV1Engine.start]を
  /// 呼び出す。[random]は[CombatV1Engine.start]へそのまま渡す
  /// （deterministic testabilityのため、Production Match Setup層で独自の
  /// 乱数生成・上書きは行わない）。
  static CombatV1MatchState start(
    CombatV1ProductionMatchConfig config, {
    Random? random,
  }) {
    final entryA = combatV1ProductionWrestlerRegistry[config.wrestlerAId];
    if (entryA == null) {
      throw CombatV1IllegalActionException(
        '未知のProduction wrestlerIdです（wrestlerAId）: '
        '${config.wrestlerAId}',
      );
    }
    final entryB = combatV1ProductionWrestlerRegistry[config.wrestlerBId];
    if (entryB == null) {
      throw CombatV1IllegalActionException(
        '未知のProduction wrestlerIdです（wrestlerBId）: '
        '${config.wrestlerBId}',
      );
    }
    if (config.playerAOwnerId.trim().isEmpty) {
      throw CombatV1IllegalActionException(
        'playerAOwnerIdを空にすることはできません'
        '（player間でinstanceIdが衝突する原因になるため）',
      );
    }
    if (config.playerBOwnerId.trim().isEmpty) {
      throw CombatV1IllegalActionException(
        'playerBOwnerIdを空にすることはできません'
        '（player間でinstanceIdが衝突する原因になるため）',
      );
    }
    if (config.playerAOwnerId == config.playerBOwnerId) {
      throw CombatV1IllegalActionException(
        'playerAOwnerIdとplayerBOwnerIdは異なる値である必要があります'
        '（同一の場合、physical instanceIdがplayer間で衝突するため）: '
        '${config.playerAOwnerId}',
      );
    }

    final deckA = entryA.buildDeck(ownerId: config.playerAOwnerId);
    final deckB = entryB.buildDeck(ownerId: config.playerBOwnerId);

    return CombatV1Engine.start(
      wrestlerA: entryA.wrestler,
      deckA: deckA,
      wrestlerB: entryB.wrestler,
      deckB: deckB,
      rules: config.rules,
      catalog: productionCardCatalog,
      random: random,
    );
  }
}
