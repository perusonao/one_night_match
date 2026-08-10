# Combat Ver.1 Phase 11A — Production Match Setup 設計文書

- ステータス: Phase 11A（Production Match Setup 基盤実装）完了時点。
- 関連: [`../combat_rules_v1.md`](../combat_rules_v1.md)（SSOT） /
  [`combat_v1_phase1_design.md`](combat_v1_phase1_design.md) /
  [`combat_v1_phase10_production_data.md`](combat_v1_phase10_production_data.md)
- 実装: `lib/src/combat_v1/combat_v1_production_match_setup.dart`
- テスト: `test/combat_v1/combat_v1_production_match_setup_test.dart`

---

## 1. 目的

Phase 10Cまでで4人のProduction Wrestler（豪田ミサキ／黒蝶ジャック／火神アカリ／白銀レイナ）と
それぞれの正式30枚Deck、4人構成のProduction Catalogが揃った。しかし「Production Wrestlerを
選び、対応するProduction Deckを作り、owner namespaceを割り当て、`CombatV1Engine.start`を呼ぶ」
という一連の手順は、テストごと（`combat_v1_production_wrestler_deck_integrity_test.dart`
・`combat_v1_production_akari_vs_reina_command_test.dart`等）に個別で組み立てられており、
将来のCPU・Simulator・UI・replay/debug toolsが同じ手順を再実装する前提のままだった。

Phase 11Aは、この組み立て処理のSSOTとなる安全なapplication/production layer API
（`CombatV1ProductionMatchStarter.start`）を導入する。これにより将来のHuman vs CPU・CPU vs
CPU・Simulator・UI・Browser play・replay/debug toolsが、全て同じProduction Match開始経路を
利用できるようになる。

## 2. Core Engineとの責務分離

- `CombatV1Engine.start`（`combat_v1_engine.dart`）: 汎用Core entry point。`CombatV1Wrestler`・
  `CombatV1DeckDefinition`・`CombatV1RulesConfig`・`CombatV1CardCatalog`という汎用的な型のみを
  受け取り、Production固有の概念（wrestlerId文字列が`"misaki"`かどうか等）を一切知らない。
- `CombatV1ProductionMatchStarter.start`（Phase 11A、`combat_v1_production_match_setup.dart`）:
  Production Data専用のapplication/production entry point。`CombatV1ProductionMatchConfig`
  （wrestlerId 2つ・owner namespace 2つ・rules）を受け取り、Production Wrestler Registry経由で
  wrestler本体とDeck builderを解決し、`productionCardCatalog`と併せて`CombatV1Engine.start`を
  呼び出す。

Phase 11Aでは`combat_v1_engine.dart`を一切変更していない。Production固有のID
（`"misaki"`/`"jack"`/`"akari"`/`"reina"`）はProduction layer（本ファイル）に閉じており、Core
Engineへは持ち込まない——Core Engine側は引き続き`CombatV1Wrestler.id`と
`CombatV1DeckDefinition.wrestlerId`という汎用フィールド同士の文字列比較のみで整合性を検証する
（Phase 10B Codexレビュー指摘対応がそのまま活きている）。

## 3. wrestler ID / player slot / owner namespace / cardId / instanceId

Production Match Setupで混同してはならない5つの概念（既存のPhase 10設計方針をそのまま踏襲）:

| 概念 | 例 | 役割 |
|---|---|---|
| wrestler ID | `misaki` / `jack` / `akari` / `reina` | どのレスラーか（`CombatV1ProductionMatchConfig.wrestlerAId`/`wrestlerBId`） |
| player slot | A / B | `CombatV1MatchState.playerA`/`playerB`のいずれか |
| owner namespace | `player-a` / `player-b` 等 | physical instanceId生成専用の識別子（`CombatV1ProductionMatchConfig.playerAOwnerId`/`playerBOwnerId`） |
| cardId | `misaki_backdrop` 等 | カード定義identity（wrestlerを跨いでも安定） |
| instanceId | `player-a_misaki_backdrop_#0` 等 | 物理カードidentity（match内でplayerを跨いで一意） |

wrestler IDとowner namespaceは独立した概念であり、同じwrestler ID同士（mirror match、例:
Misaki vs Misaki）でも異なるowner namespaceを渡す限り安全にmatchを開始できる。

## 4. Production Deck builder registry

`combat_v1_production_match_setup.dart`が公開する
`combatV1ProductionWrestlerRegistry`（`Map<String, CombatV1ProductionWrestlerEntry>`）に、
wrestler ID→（`CombatV1Wrestler`本体・専用Production Deck builder）の対応を一箇所へ集約した。

```dart
final Map<String, CombatV1ProductionWrestlerEntry>
combatV1ProductionWrestlerRegistry = Map.unmodifiable({
  misakiWrestler.id: CombatV1ProductionWrestlerEntry(
    wrestler: misakiWrestler,
    buildDeck: buildMisakiDeck,
  ),
  // jack / akari / reina も同様
});
```

これにより、call site側（本ファイル以外）は`if (wrestlerId == 'misaki') ...`のような
Production固有IDのハードコード分岐を書く必要がない。新しいProduction Wrestlerを追加する際は、
このレジストリへ1エントリ追加するだけでよい（Phase 12以降・4人以外のwrestler追加時の
拡張ポイント）。

呼び出し側からの書き換えを防ぐため、レジストリ自体は`Map.unmodifiable`でラップしている。

## 5. Production Catalog

`CombatV1ProductionMatchStarter.start`は常に`combat_v1_production_catalog.dart`の
`productionCardCatalog`（4人構成のProduction Catalog）を使う。`CombatV1ProductionMatchConfig`
にcatalogを差し替えるフィールドは設けていない——「Production」Match Setupという責務上、
使用するカタログは常にProduction Catalogに固定するのが最小・自然なAPIであり、任意のカタログを
注入できるようにするのはCore Engine（`CombatV1Engine.start`）側の責務のまま残す。

## 6. matchId

`CombatV1Engine.start`は`matchId`を呼び出し側から受け取らず、内部で
`'combat-v1-${DateTime.now().microsecondsSinceEpoch}'`として生成している
（`combat_v1_engine.dart`参照）。Production Match Setup層にも`matchId`を受け取る・生成する
フィールドは設けていない。理由:

- `CombatV1Engine.start`のシグネチャを変更する（`matchId`パラメータを追加する）ことは
  Core Engine変更にあたり、Phase 11Aのスコープ外（19章「Core変更ルール」）。
- Production Match Setup層だけで独自に日時・random UUIDを生成し、後から`matchId`を上書きする
  ような仕組みをDomain内へ追加すると、deterministic testabilityを損なう余地を新たに作ってしまう。

そのため、matchIdの扱いはCore Engineの既存挙動（非decisiveなtimestampベースの内部生成）を
そのまま維持する。将来的にmatchIdを外部から指定可能にする必要が生じた場合は、Core Engine側の
シグネチャ変更として別途検討する。

## 7. setup flow

`CombatV1ProductionMatchStarter.start(config, {random})`は以下の順でfail-fast検証を行う。
いずれかで`CombatV1IllegalActionException`を送出した場合、`CombatV1MatchState`は一切構築しない
（`CombatV1Engine.start`自身が持つatomicityと同じ方針）。

1. `config.wrestlerAId`を`combatV1ProductionWrestlerRegistry`で解決（unknownなら拒否）
2. `config.wrestlerBId`を`combatV1ProductionWrestlerRegistry`で解決（unknownなら拒否）
3. `config.playerAOwnerId`が空白のみでないことを確認
4. `config.playerBOwnerId`が空白のみでないことを確認
5. `config.playerAOwnerId != config.playerBOwnerId`を確認（physical instanceId衝突の防止）
6. 解決したwrestlerごとに、それぞれのowner namespaceでProduction Deckを生成
7. `productionCardCatalog`・`config.rules`・（あれば）呼び出し元の`random`を使って
   `CombatV1Engine.start`を呼び出す

## 8. validation（API責務まとめ）

| 検証項目 | 結果 |
|---|---|
| 未知のwrestlerAId | `CombatV1IllegalActionException` |
| 未知のwrestlerBId | `CombatV1IllegalActionException` |
| 同じwrestlerId同士（mirror match、例: Misaki vs Misaki） | 許可（禁止しない） |
| playerAOwnerId／playerBOwnerIdが空文字・空白のみ | `CombatV1IllegalActionException` |
| playerAOwnerId == playerBOwnerId | `CombatV1IllegalActionException` |
| wrestler/deckの組み合わせ | レジストリが常に対応する組を選ぶため、Production Match Setup
  経由では取り違えが構造的に起こらない（`CombatV1Engine.start`側のwrestlerId整合性チェックも
  防御的に効き続ける） |

Setup自体の検証に加えて、`CombatV1Engine.start`が内部で行う`validateCatalog`／`validateDeck`
（wrestlerId整合性込み）もそのまま経由するため、二重の安全網になっている。

## 9. config immutability

`CombatV1ProductionMatchConfig`はimmutableな値オブジェクトで、`wrestlerAId`／`wrestlerBId`／
`playerAOwnerId`／`playerBOwnerId`／`rules`はすべて`String`または`CombatV1RulesConfig`という
scalar/immutableな型のみを持つ（public mutable collectionを持たない）。既存の`CombatV1Wrestler`
／`CombatV1RulesConfig`と同じく、モデル自体はvalidationを行わない「plain data」として設計し、
validationは`CombatV1ProductionMatchStarter.start`（呼び出し時）へ分離した——これは
`CombatV1MatchState`が`validateMatchStateInvariants`という別関数でinvariantを検証するのと同じ
設計方針である。

## 10. deterministic testability

`CombatV1ProductionMatchStarter.start`は`Random? random`を`CombatV1Engine.start`へそのまま
渡す。Production Match Setup層自身が乱数を生成・上書きすることはない。そのため、同じ`config`と
同じseedの`Random`を渡せば、既存のCore Engineテストと同様に決定的な再現が可能
（`combat_v1_production_match_setup_test.dart`の「deterministic testability」グループ参照）。

## 11. Phase 11B（CPU）との接続点

Phase 11Aで実装したのはMatch Setupのみであり、CPU意思決定・CPU action selection・自動対戦
loopは対象外（Phase boundary、本タスクの依頼文0〜1章）。将来のPhase 11B（CPU実装）は、以下の
形でPhase 11Aの成果を利用できる想定:

- CPU vs CPU・Human vs CPUいずれの場合も、対戦開始は
  `CombatV1ProductionMatchStarter.start(CombatV1ProductionMatchConfig(...))`を呼ぶだけでよい。
  CPU側がwrestler選択後にDeck builderやProduction Catalogを個別に組み立てる必要はない。
- CPUの思考ロジックは、Setupが返す`CombatV1MatchState`と`CombatV1Engine`の既存Command
  （`declareTechnique`／`playCounter`／`declineCounter`／`declarePin`等）のみを使う——Phase
  11AはCPUの意思決定ロジックには一切踏み込んでいない。
- `combatV1ProductionWrestlerRegistry`のキー一覧（`misaki`/`jack`/`akari`/`reina`）は、CPU側が
  「有効なwrestler ID」を機械的に列挙する際にも再利用できる。

## 12. 今回のスコープ外

以下はPhase 11Aでは実装していない（Phase 11B以降・別Phaseの対象）:

- CPU意思決定・CPU action selection
- Simulator・自動対戦loop
- UI・Browser integration
- balance tuning・Production Data変更
- Combat Core rule変更
