# Combat Ver.1 Phase 12B-1 — Deterministic Batch Matrix / Core Aggregation 設計文書

- ステータス: Phase 12B-1（Deterministic Batch Matrix / Core Aggregation）実装。
  Phase 12A（`b4e13a4aad65d26be4cd56ae90276844fc4949cc`、merge済み）のpublic APIのみを
  利用し、Core Engine・Production Data・UIは変更しない。
- 関連: [`combat_v1_phase12a_simulation_core.md`](combat_v1_phase12a_simulation_core.md)（Phase
  12A、直接の基盤） / [`combat_v1_phase11b_cpu.md`](combat_v1_phase11b_cpu.md) /
  [`combat_v1_phase11a_production_match_setup.md`](combat_v1_phase11a_production_match_setup.md)
- 実装: `lib/src/combat_v1/simulation/batch/combat_v1_batch_matchup.dart` /
  `combat_v1_batch_simulation_config.dart` / `combat_v1_batch_aggregate.dart` /
  `combat_v1_batch_aggregator.dart` / `combat_v1_batch_simulation_result.dart` /
  `combat_v1_batch_simulation_runner.dart`
- テスト: `test/combat_v1/batch/combat_v1_batch_matchup_test.dart` /
  `combat_v1_batch_simulation_config_test.dart` / `combat_v1_batch_aggregator_test.dart` /
  `combat_v1_batch_simulation_runner_test.dart`

---

## 1. Scope

Phase 12B-1は、Phase 12Aの`CombatV1SimulationRunner`（1試合実行のCPU vs CPU simulation）を
そのまま利用し、Production 4 wrestler（misaki/jack/akari/reina）について4×4=16の
ordered matchupを決定論的に実行し、balance analysis用の**pure aggregate**を生成する
「Batch層」を追加する。

含むもの:

- deterministic ordered matchup matrix生成（`combatV1GenerateMatchupMatrix`）
- batch実行設定（`CombatV1BatchSimulationConfig`）とそのfail-fast validation
- streaming batch runner（`CombatV1BatchSimulationRunner`）——全match resultを保持しない
- executionから分離したpure aggregator（`combatV1AggregateBatchResults`/
  `CombatV1BatchAggregationAccumulator`）
- immutableなresult階層（`CombatV1BatchSimulationResult`とその子aggregate群）
- termination/terminal cause/denominator semanticsの正式契約

**重要**: Phase 12B-1の目的は「balance warningを出すこと」ではない。目的は、安定した
batch execution・deterministic matrix・denominator semantics・pure aggregation・immutable
result schemaという基盤を確立することである。閾値判定・warning・有意差検定等は一切含まない。

## 2. Non-Scope（Phase 12B-2以降）

以下は明示的にPhase 12B-1のスコープ外とし、実装しない:

- action/turn mean・median・p90/p95・completed-only/all-match length分離（Descriptive
  Statistics）
- final HP/KOC/HEAT aggregation（final state summaryの統計）
- 個別match resultのretention（例外時のみの部分retentionも含む）
- batch ID
- CSV/JSON export・dashboard・UI・グラフ
- balance warning・閾値・confidence interval・有意差検定
- heuristic AI・AIチューニング
- isolate並列化・database保存
- Core Engine・Production Data・UIの変更

これらはすべてPhase 12B-2以降で扱う。Phase 12B-1のresult schemaは、Phase 12B-2が
これらを追加する際の後方互換な拡張余地（新規field追加）を前提とするが、Phase 12B-1自身は
これらのfieldを一切持たない。

## 3. Architecture

```
CombatV1BatchSimulationConfig
        |
        v
CombatV1BatchSimulationRunner
        |
        +-- combatV1GenerateMatchupMatrix（deterministic ordered matrix、pure）
        +-- CombatV1SimulationConfig（Phase 12A、matchup毎に構築）
        +-- CombatV1SimulationRunner.runSingleMatch（Phase 12A、matchup×local matchIndex毎）
        +-- 構造的invariant検証（wrestler/policy/seed/maxActions/rules/matchIndexの一致）
        +-- CombatV1BatchAggregationAccumulator.add（streaming、match result即破棄）
        |
        v
CombatV1BatchAggregateBundle（global/matchups/wrestlers/seat/mirror）
        |
        v
CombatV1BatchSimulationResult（config/requestedMatchCount/executedMatchCount + bundle）
```

`CombatV1BatchSimulationRunner`自身の責務は、(1) matrixを生成する、(2) 各matchupについて
Phase 12A `CombatV1SimulationConfig`を組み立て`runSingleMatch`をlocal matchIndex 0..N-1で
呼ぶ、(3) 返ってきた`CombatV1MatchSimulationResult`をPhase 12B自身の構造的invariantで検証
する、(4) accumulatorへ渡してすぐ参照を破棄する、(5) accumulatorが返す集約結果を
`CombatV1BatchSimulationResult`へ詰め替える、の5点のみ。CPU対戦ロジック・seed
derivation・simulation identity derivationはPhase 12Aへ完全委譲する。

## 4. Phase 12A Boundary

Batch aggregation codeが直接参照するPhase 12A public API:

- `CombatV1SimulationConfig`（1試合分の実行設定）
- `CombatV1SimulationRunner.runSingleMatch`（試合実行時のみ）
- `CombatV1SimulationPolicyKind`（policy pairing）
- `CombatV1MatchSimulationResult`（aggregation input）
- `combatV1ProductionWrestlerRegistry`（wrestlerId validation、Phase 11A）

Batch aggregation codeから直接参照しないもの（禁止）:

- `CombatV1MatchState`・Core Engine internals
- CPU action loop internals（`CombatV1ActionExecutor`等）
- deck/card internals
- `CombatV1CpuMatchRunner`（Phase 11B、Phase 12A経由でのみ間接利用）

以下はPhase 11B/12Aへ完全委譲し、Phase 12Bでは重複実装しない: LegalAction enumeration・
action loop・ActionExecutor・invariant validation・termination classification・seed
derivation・simulationMatchId derivation。

## 5. Canonical Wrestler Order

Production default order（`combatV1DefaultBatchWrestlerIds`、
`combat_v1_batch_simulation_config.dart`）:

```dart
const List<String> combatV1DefaultBatchWrestlerIds = ['misaki', 'jack', 'akari', 'reina'];
```

この順序を明示的なcanonical ordered listとして固定literalで持つ——
`combatV1ProductionWrestlerRegistry`（`Map<String, ...>`）のiteration orderには一切依存
しない。`CombatV1BatchSimulationConfig`の`wrestlerIds`既定値としてそのまま使う。

## 6. Ordered Matrix Semantics

`combatV1GenerateMatchupMatrix`（`combat_v1_batch_matchup.dart`）は、`wrestlerIds`の
順序を使ったordered Cartesian product（外側ループ=wrestlerA、内側ループ=wrestlerB）を
生成するpure function:

```dart
List<CombatV1Matchup> combatV1GenerateMatchupMatrix(List<String> wrestlerIds) => List.unmodifiable([
  for (final wrestlerAId in wrestlerIds)
    for (final wrestlerBId in wrestlerIds)
      CombatV1Matchup(wrestlerAId: wrestlerAId, wrestlerBId: wrestlerBId),
]);
```

N wrestlerならN×N matchup。default 4 wrestlersなら16。mirror（`wrestlerAId ==
wrestlerBId`）を除外しない——4 mirrorすべてを含む。A vs BとB vs Aは別matchupとして両方
生成する。戻り値は`List.unmodifiable`。

`CombatV1Matchup`（同ファイル）はimmutable value object（`wrestlerAId`/`wrestlerBId`の
組、value equality実装済み）。単なる文字列key（`"akari-vs-reina"`）は使わない——
`CombatV1MatchupAggregate.matchup`・aggregation内部のMap keyとして、value equalityを持つ
専用型を使う。

## 7. Policy Pairing

`CombatV1PolicyPairing`（`combat_v1_batch_matchup.dart`）——`playerAPolicy`/
`playerBPolicy`（両方とも`CombatV1SimulationPolicyKind`、Phase 12A）を持つimmutable
value object。1 batchにつき1 pairingのみ（`CombatV1BatchSimulationConfig.pairing`）。
対応可能な組み合わせ:

- firstLegal / firstLegal
- randomLegal / randomLegal（**default**、`CombatV1PolicyPairing.randomVsRandom`）
- firstLegal / randomLegal
- randomLegal / firstLegal

第三者factory/closure/custom policy registryは追加しない——Phase 12A
`CombatV1SimulationPolicyKind`が既に持つ「closed enumへの閉じ込め」契約をそのまま
再利用する。

## 8. Batch Config

`CombatV1BatchSimulationConfig`（`combat_v1_batch_simulation_config.dart`）:

```dart
CombatV1BatchSimulationConfig({
  List<String> wrestlerIds = combatV1DefaultBatchWrestlerIds,
  required int matchesPerMatchup,
  required int masterSeed,
  CombatV1PolicyPairing pairing = CombatV1PolicyPairing.randomVsRandom,
  int maxActions = 500,
  CombatV1RulesConfig rules = const CombatV1RulesConfig(),
})
```

`playerAPolicy`/`playerBPolicy`は`pairing.playerAPolicy`/`pairing.playerBPolicy`への
delegating getterとして公開する（`CombatV1PolicyPairing`という専用型と、フラットな
`config.playerAPolicy`アクセスの両方を提供するため）。

immutable。`wrestlerIds`はdefensive copy + `List.unmodifiable`でラップする。

## 9. Config Validation

コンストラクタでfail-fast検証する（`CombatV1IllegalActionException`、Phase 12Aと同じ
例外型を再利用）:

- `wrestlerIds`が空でないこと
- 各wrestlerIdが空白のみでないこと（`id.trim().isEmpty`を拒否）
- `wrestlerIds`内に重複がないこと
- 各wrestlerIdが`combatV1ProductionWrestlerRegistry`（Phase 11A）に存在すること
- `matchesPerMatchup > 0`
- `maxActions > 0`

検証順序: 空リストチェック → 各要素について空白/重複/unknownを順にチェック（最初の違反で
即座にthrow） → `matchesPerMatchup` → `maxActions`。

## 10. Local Match Index Strategy

各matchup内で`0 .. matchesPerMatchup - 1`のlocal matchIndexを使う。batch全体の
global sequential index（例: 「17番目に実行されたmatch」のような通し番号）は、Phase 12Aの
`CombatV1SimulationRunner.runSingleMatch`の`matchIndex`引数へは一切渡さない。

理由:

- matchup実行順序（matrix traversal order）を変更しても、各matchの結果が変化しない
- 「matchup + local matchIndex」から常にreplay可能（batch内での実行位置に依存しない）
- Phase 12Aの`simulationMatchId`が`wrestlerAId`/`wrestlerBId`/policy A・Bを含むため、
  異なるmatchup間でlocal matchIndexが重複しても`simulationMatchId`が衝突しない

概念上、各matchは`(matchup, localMatchIndex)`のペアで一意に識別される。

## 11. Master Seed Strategy

batch全体で1つの`masterSeed`（`CombatV1BatchSimulationConfig.masterSeed`）を使う。各
matchupで同じlocal matchIndexの範囲（`0..matchesPerMatchup-1`）を再利用してよい——Phase
12Aの`deriveV1SimulationSeeds`が`masterSeed` + `matchIndex` + `wrestlerAId`/`wrestlerBId`
+ `playerAPolicyId`/`playerBPolicyId`からseedを導出するため、`wrestlerAId`/`wrestlerBId`
の組み合わせが変わるだけでmatchup間のseedは自動的に分離される（同じ`masterSeed`と同じ
local matchIndexを16 matchup全てで使っても、実際のRNG seedは16通りとも異なる）。

## 12. Execution-Order Independence

Batch Runnerがmatrixをどの順序で走査しても、各`(matchup, localMatchIndex)`に対応する
Phase 12A resultは変化しない——Phase 12Aのseed derivationがbatch内の実行順序（走査順）を
一切入力に取らないため（11章）。この性質はPhase 12Aの既存契約からそのまま継承される。

Production Runnerの正式な`result ordering`自体（`CombatV1BatchSimulationResult.matchups`
の並び順等）は、`wrestlerIds`から生成したcanonical matrix order（6章）を常に維持する——
「実行順序に依存しない」ことと「出力の並び順がcanonical」であることは別の性質であり、
両方を満たす。

## 13. Denominator Semantics

Rateはすべて`double?`（zero-denominatorの場合は`null`。`0.0`や`NaN`にfabricationしない）。

- `completionRate`/`safetyLimitRate`/`invariantViolationRate`（`CombatV1TerminationDistribution`）:
  分母 = `totalMatches`
- `playerAWinRateCompletedMatches`/`playerBWinRateCompletedMatches`（Global/Matchup/
  Seat/Mirror）: 分母 = `completedMatches`
- `winRateCompletedMatches`/`playerAWinRateCompletedMatches`/`playerBWinRateCompletedMatches`
  （Wrestler）: 分母 = `completedAppearances`/`playerACompletedAppearances`/
  `playerBCompletedAppearances`
- `absoluteDeviationFromFiftyPercent`（Mirror）: `playerAWinRateCompletedMatches`が`null`
  なら`null`

`totalMatches == 0`は有効なbatch実行（`wrestlerIds`非空・`matchesPerMatchup > 0`）では
発生しない（`requestedMatchCount >= 1`）が、pure aggregator（`combatV1AggregateBatchResults`）
は空の`Iterable`からも呼べるため、この場合も同じnull-on-zero規則を適用し、統一した契約と
する。

## 14. Abnormal Termination Semantics

`CombatV1CpuMatchTermination.safetyLimit`/`invariantViolation`は、winner countへ一切
加算しない（`loss`にも`draw`にもしない）。`total = completed + safetyLimit +
invariantViolation`（`CombatV1TerminationDistribution`が保持する4フィールドの関係）。

Phase 12A/Phase 11Bからstructured `invariantViolation` resultが返った場合:

- batch実行を継続する（例外をthrowしない）
- resultをaggregateする（`invariantViolationMatches`へ加算）
- win denominator（`completedMatches`/`completedAppearances`）へは含めない

最初のinvariant violationでbatch全体をthrowすることはない。ただしPhase 12B自身の
structural/config invariant違反（15章）はfail-fastする——これは「Engineが検知した
ゲーム上のinvariant違反」とは全く別の概念である。

## 15. Internal Invariants

Batch Runnerが各match result受け取り時に検証する（`CombatV1IllegalActionException`で
fail-fast、Phase 12B自身の構造的invariantのみが対象——Engine invariantViolationは14章の
通り握りつぶさず継続する）:

- `result.wrestlerAId`/`wrestlerBId` == 対象`matchup`
- `result.playerAPolicyId`/`playerBPolicyId` == `config.pairing`から導出した`policyId`
- `result.masterSeed` == `config.masterSeed`
- `result.maxActions` == `config.maxActions`
- `result.rules`が`config.rules`とvalue equal（**object identity/hashCodeに依存しない**——
  `CombatV1RulesConfig`が`==`をoverrideしていないため、`_rulesConfigValueEquals`という
  明示的なfield-by-field比較helperを`combat_v1_batch_simulation_runner.dart`に用意する）
- `result.matchIndex` == 呼び出したlocal matchIndex
- `executedMatchCount == requestedMatchCount`（`matrix.length * matchesPerMatchup`）

Aggregator（`CombatV1BatchAggregationAccumulator`）が検証する:

- `simulationMatchId`の重複なし（`add`のたびにチェック、重複時は即fail-fast——32-bit
  identity hash衝突の理論リスクをここで検知する。Phase 12Aのhash width変更は行わない）
- `termination == matchOver`なら`winnerPlayerIndex`が0/1のいずれかであること
- `termination == matchOver`なら`terminalCause`が非null であること
- `build()`時: `total == completed + safetyLimit + invariantViolation`
- `build()`時: `completed == playerAWins + playerBWins`
- `build()`時: `terminalCause counts合計 == completedMatches`
- `build()`時: `global.totalMatches == Σ matchup.totalMatches`
- `build()`時: `Σ wrestler.appearances == 2 × global.totalMatches`

## 16. Player A/B vs First-Player Semantics

現在のCore Engine契約（Phase 1〜、`docs/combat_rules_v1.md`）: **Player A = 先手
（first player）、Player B = 後手（second player）**。この契約はCore Engineが変更されない
限りPhase 12B-1でも変わらない。

Public schemaの正本は常にA/Bとする——`firstPlayerWinRate`のような「先手/後手」を正本field
名にすることはしない。`CombatV1SeatAggregate`（24章）のdoc commentに「current engine
contract: A starts first」と明記し、A/B命名の意味（＝実質的に先手/後手バイアス分析でも
ある）を利用者が理解できるようにする。

## 17. Aggregate-Only Memory Strategy / Streaming Aggregation

Default `CombatV1BatchSimulationResult`は個別match resultを一切保持しない
（`matches: List<...>`のようなfieldを持たない）。

Production実行パス: `CombatV1SimulationRunner.runSingleMatch` → `accumulator.add(result)`
→ `result`への参照は次のloop iterationで破棄される（ローカル変数がスコープを抜ける）。
`CombatV1BatchAggregationAccumulator`は、matchup毎・wrestler毎のmutableな小さいcounter
bucket（`Map<CombatV1Matchup, _MatchupBucket>`・`Map<String, _WrestlerBucket>`、いずれも
O(distinct matchup数)・O(distinct wrestler数)のサイズ）のみを保持し、O(match数)の
メモリを消費しない。これにより160,000 matches規模のbatchでもメモリリスクを避ける。

Phase 12B-1では**aggregate-only result**を正式契約とする。all-match retention option
（個別match resultを保持する実行モード）は実装しない（Phase 12B-2以降のスコープ）。

## 18. Pure Aggregator

Aggregation logicはexecutionから完全に分離する（`combat_v1_batch_aggregator.dart`）。

- `CombatV1BatchAggregationAccumulator`: `void add(CombatV1MatchSimulationResult result)`
  （streaming入力）と`CombatV1BatchAggregateBundle build()`（最終集約）を持つmutable
  accumulator。Batch Runnerがstreaming実行で直接使う（17章）。
- `combatV1AggregateBatchResults(Iterable<CombatV1MatchSimulationResult> results)`: 上記
  accumulatorを内部で使うpure facade関数。synthetic
  （engineを一切実行していない、テストで手組みした）`CombatV1MatchSimulationResult`の
  `Iterable`を渡すだけでaggregate結果を得られる——大規模engine simulationをaggregation
  unit testの代替にしない、というテスト戦略上の要件を満たす。

両方とも入力として受け取る`CombatV1MatchSimulationResult`以外の外部stateに依存しない
（現在時刻・グローバル変数・Random等を一切使わない）。

## 19. Result Hierarchy

```
CombatV1BatchSimulationResult
├ config: CombatV1BatchSimulationConfig
├ requestedMatchCount: int         // matrix.length * matchesPerMatchup
├ executedMatchCount: int          // 実際に実行された数（正常時はrequestedと一致）
├ global: CombatV1GlobalAggregate
├ matchups: List<CombatV1MatchupAggregate>   // canonical matrix順、unmodifiable
├ wrestlers: List<CombatV1WrestlerAggregate> // wrestlerIds順（初出順）、unmodifiable
├ seat: CombatV1SeatAggregate
├ mirror: CombatV1MirrorAggregate
└ termination: CombatV1TerminationDistribution  // == global.termination（同一instance）
```

全fieldがimmutable。`List`は`List.unmodifiable`でラップ。`matchups`/`wrestlers`の並び順は
deterministic（6章のcanonical matrix順・`wrestlerIds`の初出順）。

`termination`は`global.termination`と同一instanceを指す（別途再計算しない）——
「terminationの内訳だけを見たい」利用者が`result.global.`を経由せずアクセスできる
利便性fieldであり、Global側の値と構造的に乖離しない。

### 共有value type

- `CombatV1TerminationDistribution`（`totalMatches`/`completedMatches`/
  `safetyLimitMatches`/`invariantViolationMatches` + 3 rate getter）: Global・Matchup・
  Mirror aggregateが内部でこれを保持し、フラットなdelegating getterも公開する
  （例: `CombatV1GlobalAggregate.completedMatches` は `termination.completedMatches`への
  delegating getter）。単一のstored instanceを複数のaggregateレベルで再利用する設計とし、
  同じ数値を複数箇所で独立に再計算・重複保持しない。
- `CombatV1TerminalCauseCounts`（`normalPin`/`directPin`/`submission`/
  `submissionFinisher`/`other` + `total` getter）: Global・Matchupが保持する。

## 20. Global Aggregate

`CombatV1GlobalAggregate`:

- `termination: CombatV1TerminationDistribution`（`totalMatches`/`completedMatches`/
  `safetyLimitMatches`/`invariantViolationMatches`と3 rateを、フラットなdelegating
  getterとしても公開: `totalMatches`/`completedMatches`/`safetyLimitMatches`/
  `invariantViolationMatches`/`completionRate`/`safetyLimitRate`/`invariantViolationRate`）
- `playerAWins`/`playerBWins`
- `playerAWinRateCompletedMatches`/`playerBWinRateCompletedMatches`（分母
  `completedMatches`、0なら`null`）
- `terminalCauseCounts: CombatV1TerminalCauseCounts`

## 21. Matchup Aggregate

`CombatV1MatchupAggregate`:

- `matchup: CombatV1Matchup`
- `termination: CombatV1TerminationDistribution`（+ delegating getter、20章と同型）
- `playerAWins`/`playerBWins`
- `playerAWinRateCompletedMatches`/`playerBWinRateCompletedMatches`
- `terminalCauseCounts: CombatV1TerminalCauseCounts`

**requested/executed countについて**: matchup単位のrequested/executed match countは
意図的に持たない。pure aggregator（`combatV1AggregateBatchResults`）は「実際に観測した
match result」のみからaggregateするpure boundaryであり、「この matchup に何試合
requestされていたか」という実行前の期待値を知らない（それを知っているのはBatch Runner・
Configのみ）。全matchupで`matchesPerMatchup`が均一である以上、batch全体の
`requestedMatchCount`/`executedMatchCount`（19章）で整合性確認は既に足りるため、matchup
単位の重複fieldは追加しない。

## 22. Wrestler Aggregate

`CombatV1WrestlerAggregate`:

- `wrestlerId`
- `playerAAppearances`/`playerACompletedAppearances`/`playerAWins`/
  `playerAWinRateCompletedMatches`
- `playerBAppearances`/`playerBCompletedAppearances`/`playerBWins`/
  `playerBWinRateCompletedMatches`
- 合算derived getter: `appearances`（= A+B appearances）・`completedAppearances`（=
  A+B completed）・`wins`（= A+B wins）・`winRateCompletedMatches`（分母
  `completedAppearances`）

相手別（opponent別）の詳細（例: 「misakiがjack相手にA seatで何勝したか」）は
`matchups`（`CombatV1MatchupAggregate`、21章）から取得できるため、Wrestler
Aggregateへは持たせない（データ重複回避）。

## 23. Seat Aggregate

`CombatV1SeatAggregate`（**current engine contract: Player A = first player, Player B
= second player**、16章）:

- `playerACompletedMatches`/`playerBCompletedMatches`（**常に両方とも
  `global.completedMatches`と同じ値**——batch全体の各completed matchは必ずplayerA側・
  playerB側を1つずつ持つため。両方を明示fieldとして持つのは、APIとして「A側/B側それぞれの
  分母」を対称に表現するため——値が一致することは`combat_v1_batch_aggregator_test.dart`の
  invariant testで固定する）
- `playerAWins`/`playerBWins`（= `global.playerAWins`/`playerBWins`と同じ値）
- `playerAWinRateCompletedMatches`/`playerBWinRateCompletedMatches`

Wrestlerの種類に関わらずbatch全体でのA seat/B seatバイアスを見るための集約であり、
`global`と数値的には重なるが、「wrestler固有ではなくseatに固有の集計」という意味論を
明確にするための独立したaggregateとして提供する。

## 24. Mirror Aggregate

`CombatV1MirrorAggregate`（`wrestlerAId == wrestlerBId`のmatchupのみを対象とした
first-class metric）:

- `termination: CombatV1TerminationDistribution`（+ delegating getter:
  `totalMatches`/`completedMatches`/`safetyLimitMatches`/`invariantViolationMatches`/
  `safetyLimitRate`）
- `playerAWins`/`playerBWins`/`playerAWinRateCompletedMatches`
- `absoluteDeviationFromFiftyPercent`（`(playerAWinRateCompletedMatches - 0.5).abs()`。
  `playerAWinRateCompletedMatches`が`null`なら`null`）

wrestler別mirror（例: misaki mirror限定の内訳）は持たない——public schemaを膨らませない
ため。global mirror aggregate 1つのみをMUSTとする。

## 25. Terminal Cause

`CombatV1TerminalCauseCounts`のカウント対象は`normalPin`/`directPin`/`submission`/
`submissionFinisher`/`other`の5種（Phase 11B `CombatV1CpuMatchTerminalCause`と1:1）。
分母は`completedMatches`（`termination == matchOver`の場合のみ`terminalCause`が非null）。
abnormal termination（safetyLimit/invariantViolation）はterminalCauseへ含めない。

`terminalCauseCounts.total == completedMatches`は内部invariantとして`build()`時に
検証する（15章）。

## 26. File Organization

```
lib/src/combat_v1/simulation/
├ combat_v1_simulation_*.dart          （既存、Phase 12A、変更なし）
└ batch/                               （新規、Phase 12B-1）
  ├ combat_v1_batch_matchup.dart       — CombatV1Matchup / CombatV1PolicyPairing /
  │                                       combatV1GenerateMatchupMatrix
  ├ combat_v1_batch_simulation_config.dart — CombatV1BatchSimulationConfig /
  │                                       combatV1DefaultBatchWrestlerIds
  ├ combat_v1_batch_aggregate.dart     — CombatV1TerminationDistribution /
  │                                       CombatV1TerminalCauseCounts /
  │                                       CombatV1GlobalAggregate /
  │                                       CombatV1MatchupAggregate /
  │                                       CombatV1WrestlerAggregate /
  │                                       CombatV1SeatAggregate /
  │                                       CombatV1MirrorAggregate /
  │                                       CombatV1BatchAggregateBundle
  ├ combat_v1_batch_aggregator.dart    — CombatV1BatchAggregationAccumulator /
  │                                       combatV1AggregateBatchResults
  ├ combat_v1_batch_simulation_result.dart — CombatV1BatchSimulationResult
  └ combat_v1_batch_simulation_runner.dart — CombatV1BatchSimulationRunner
```

`test/combat_v1/batch/`配下へ対応するtestを配置し、既存`test/combat_v1/`直下（Phase
12A以前のtest）とは分離する。

## 27. Test Strategy

- **Matrix**（`combat_v1_batch_matchup_test.dart`）: default 4 wrestler → 16 matchup・
  順序・4 mirror・A vs B/B vs A別・canonical順序の厳密一致・unmodifiable・custom order
  反映
- **Config**（`combat_v1_batch_simulation_config_test.dart`）: 9章の全validation
  ケース・default pairing（RandomLegal/RandomLegal）・immutability
- **Pure Aggregation**（`combat_v1_batch_aggregator_test.dart`）: synthetic
  `CombatV1MatchSimulationResult`（engine実行なし）で、total/completed/safety/
  invariant・A/B wins・completed分母・completed=0→null・matchup分類・wrestler分類・
  A/B seat帰属・mirror分類・mirror deviation・terminal cause分布・aggregate sum
  invariant・duplicate simulationMatchId拒否を検証
- **Determinism**（`combat_v1_batch_simulation_runner_test.dart`）: 同一config→同一
  aggregate（複数回run）・execution order independence（wrestlerIds順を変えてmatrix
  traversal順を変えても、matchup単位のaggregate値が不変）・異なるmasterSeedで
  identity/seedが変化すること
- **Replay**（同上）: 代表matchについて、`config` + `matchup` + `localMatchIndex`から
  `CombatV1SimulationConfig` + `CombatV1SimulationRunner.runSingleMatch`を再構築し、
  `simulationMatchId`/seed/termination/winner/summaryが一致することを確認
- **Policy Pairings**（同上）: FF/RR/FR/RFの4 built-in pairingsをsmall smokeで確認
  （defaultはRR）
- **Safety/Invariant**（同上）: 低い`maxActions`でsafetyLimitを発生させ、batch継続・
  count・win denominator除外を確認。synthetic invariantViolation resultでも同様に
  pure aggregatorレベルで確認
- **Integration Smoke**（同上）: default 4 wrestlersで16 matchup全実行・少数
  matches/matchup（例: 20/matchup = 320 matches）・executed count一致・invariant
  成立・deterministic。balance assertion（勝率の閾値判定等）は行わない

既存Phase 12A/11B testが既に検証しているCPU対戦ロジック自体の網羅的な再テストは行わない
——Batch境界として必要な確認のみを追加する。

## 28. Boundary with Phase 12B-2

Phase 12B-2（今回実装しない）が扱う項目: action/turn mean・median・p90/p95・
completed-only/all-match length分離・final HP/KOC/HEAT aggregation・optional result
retention・optional batch ID・performance refinement（並列化含む）。

Phase 12B-1の`CombatV1BatchSimulationResult`・各aggregate型は、Phase 12B-2がこれらを
追加field/追加aggregate型として拡張することを前提に設計されている
（`CombatV1MatchFinalStateSummary`・`actionCount`・`finalTurnNumber`は既にPhase 12Aの
`CombatV1MatchSimulationResult`が保持しているため、Phase 12B-2はPhase 12B-1の
streaming/aggregation基盤へ新しいaccumulator counterを追加するだけで実装できる想定）が、
Phase 12B-1自身はこれらを一切参照・集計しない。
