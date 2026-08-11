# Combat Ver.1 Phase 12B-2A — Match Length Descriptive Statistics 設計文書

- ステータス: Phase 12B-2A（Match Length Descriptive Statistics）実装。Phase 12B-1
  （`21502817eb332dc93236f54d16dc410912b8d6e3`、merge済み）のpublic APIのみを利用し、
  Core Engine・Phase 12A（Simulation Core）・Production Data・UIは変更しない。
- 関連: [`combat_v1_phase12b1_batch_core_aggregation.md`](combat_v1_phase12b1_batch_core_aggregation.md)
  （Phase 12B-1、直接の基盤） /
  [`combat_v1_phase12a_simulation_core.md`](combat_v1_phase12a_simulation_core.md) /
  [`combat_v1_phase11b_cpu.md`](combat_v1_phase11b_cpu.md)
- 実装: `lib/src/combat_v1/simulation/batch/combat_v1_batch_length_statistics.dart`
  （public value types）/
  `combat_v1_batch_length_statistics_accumulator.dart`（internal histogram +
  streaming accumulator、public facade）/ `combat_v1_batch_simulation_result.dart`
  （`statistics` field追加）/ `combat_v1_batch_simulation_runner.dart`（accumulator
  接続 + 構造的invariant検証）/
  `devtools/combat_v1_batch_result_snapshot_serializer.dart`（`statistics`
  top-level field追加）
- テスト: `test/combat_v1/batch/combat_v1_batch_length_statistics_test.dart`
  （pure histogram/distribution logic）/
  `combat_v1_batch_length_statistics_accumulator_test.dart`（completed-only /
  Global・Matchup対応 / matchup独立性 / determinism / immutability）/
  `combat_v1_batch_simulation_runner_test.dart`（integration追加分）/
  `devtools/combat_v1_batch_result_snapshot_serializer_test.dart`（schema追加分）

---

## 1. Scope

Phase 12B-2Aは、Dashboard v1（未着手）が「平均試合長・median・p90・p95」を表示できる
ようにするための、**match length descriptive statistics**基盤を追加する。対象は
以下の2指標のみ:

- `actionCount`（Phase 11B/12A由来、CPU runnerが実際にexecuteしたpublic action数）
- `finalTurnNumber`（Phase 11B/12A由来、決着時点のturn番号）

いずれも**completed match（`termination == matchOver`）のみ**を対象とし、
Global（batch全体）単位・Ordered Matchup（`CombatV1Matchup`単位）単位の両方で
以下7つのdescriptive statisticsを提供する:

- `sampleCount`
- `mean`
- `median`
- `p90`
- `p95`
- `min`
- `max`

含むもの:

- exact bounded histogram（sparse `Map<int, int>`、raw value list非保持）
- streaming/incremental accumulation（`CombatV1BatchAggregationAccumulator`と同型の
  streaming pattern）
- immutableなresult階層（`CombatV1BatchDescriptiveStatistics`とその子value type群）
- deterministic percentile semantics（nearest-rank、整数演算）
- Development Snapshotへの`statistics` top-level additive field
- pure synthetic test（engineを起動しない、histogram/statistics logic直接test）
- lightweight manual benchmark（320 / 1,600 / 16,000 matchesの実行時間測定）

**重要**: Phase 12B-2Aの目的も、Phase 12B-1同様「balance warningを出すこと」では
ない。目的は、Dashboard v1が必要とする最小限のmatch length分布情報を、
streaming・immutable・deterministicな形で提供する基盤を確立することである。

## 2. Non-Scope（Phase 12B-2B/12B-2C/Dashboard）

以下は明示的にPhase 12B-2Aのスコープ外とし、実装しない:

- final HP/KOC/shared HEAT/differentialのdescriptive statistics（Phase 12B-2Bへ）
- wrestler別・mirror別・seat別のlength分布（今回はGlobal/Matchupのみ）
- exceptional retention（safety/invariant match metadataのlist保持、failure replay
  index、reservoir sampling等、Phase 12B-2C以降）
- batch ID
- 正式なCSV/JSON Export schema
- Dashboard/UI（Phase 12B-2A merge後、別Phaseとして開始）
- warning・閾値判定・confidence interval・有意差検定
- heuristic AI・AIチューニング
- isolate/Web Worker並列化
- full action trace・raw value list retention
- `allExecuted`（safetyLimit/invariantViolationを含む全実行試合の統計）——今回は
  completed-onlyのみをMUSTとする（11章参照）

Phase 12B-1のresult schema（`CombatV1BatchSimulationResult`とその既存field群）は
一切変更しない——`statistics`は既存treeの外側に追加する、後方互換なadditive
extensionである（19章「Statistics Tree」参照）。

## 3. Phase 12B-1 Contract（維持）

以下はPhase 12B-1で確立された契約であり、Phase 12B-2Aでも維持する:

- aggregate-only（個別`CombatV1MatchSimulationResult`・`simulationMatchId`を
  batch全体でretentionしない）
- streaming aggregation（`O(matchup数)`のmemory、`O(totalMatches)`にしない）
- local matchIndex（`(CombatV1Matchup, localMatchIndex)`が実行identityの正本）
- deterministic ordered matrix（`combatV1GenerateMatchupMatrix`の初出順）
- completed-only win denominator
- winner-preserved `invariantViolation`互換性（Shape A/B）
- pure aggregator（Core Engineをimportしない、synthetic resultのみでtest可能）
- immutable result（`List.unmodifiable`、全field final）
- Development Snapshot責務分離（domain modelに`toJson()`を生やさない、devtools層に
  閉じる）

Phase 12B-2Aは、`CombatV1BatchAggregationAccumulator`（Phase 12B-1）を一切変更
しない——独立した並行accumulator（`CombatV1BatchDescriptiveStatisticsAccumulator`）
を追加し、Batch Runnerが両方へ同じ`CombatV1MatchSimulationResult`を渡すのみ
（31章「Batch Runner Integration」）。

## 4. actionCount Semantics（固定）

`CombatV1MatchSimulationResult.actionCount`（Phase 12A由来、Phase 11B
`CombatV1CpuMatchResult.actionCount`をそのまま転記した値）の意味を、Phase
12B-2Aのstatistics入力として以下の通り固定する
（`lib/src/combat_v1/combat_v1_cpu_match_runner.dart`のdoc comment・実装を確認
済み）:

> `CombatV1ActionExecutor.execute`が成功した**public CPU action**の数
> （discard/declareTechnique/playCounter/declineCounter/declarePin/rest/
> standUp/endTurnの8種のみ）。action loop（`CombatV1CpuMatchRunner.run`の
> `while (true)`）内で、1つのpublic actionが成功実行されるたびに`actionCount`
> がインクリメントされる。

**別actionとして数えないもの**（重要——Phase 12B-2Aのhistogramに混入しない）:

- draw（ターン開始時の1枚draw、山札再構築時のshuffle+draw）
- shuffle（discard pileからdraw pileへの再構築）
- direct PIN/SUBMISSIONの自動resolution（`CombatV1DeclineCounterAction`1回の
  Command呼び出し内で完結する内部処理）
- turn transition（`_advanceTurnAfterEnd`によるactivePlayerIndex/turnNumber更新、
  `_startTurn`によるdraw/phase遷移）
- ROUGH制限のセット/解除等、Engine内部で自動的に行われるstate遷移

これらはEngineのCommand実行の副作用として発生するが、CPU runnerのaction loopが
明示的に選択・実行した「1手」ではないため、`actionCount`には含まれない。この
semanticsはPhase 11B/12Aで既に確立されているものであり、Phase 12B-2Aはこれを
一切変更しない——単にstatisticsの入力として使うのみ。

**範囲**: `CombatV1CpuMatchRunner.run`のloop構造（`actionCount >= maxActions`で
safetyLimit終了する分岐が、action実行前・action loop先頭でチェックされる）から、
構造的に`0 <= actionCount <= maxActions`が成立する。この関係はPhase 12Aの
loop実装そのものから導かれるものであり、Phase 12B-2Aで新たに強いvalidatorを
追加する必要はない（24章「Action Histogram Range」参照）。

## 5. finalTurnNumber Semantics（固定）

Public名称`finalTurnNumber`を維持する——`playedTurns`/`completedTurns`等への
renameは行わない。

意味（`CombatV1CpuMatchResult.finalTurnNumber` = `finalState.turnNumber`を
そのまま転記）:

> 最終state（`CombatV1MatchState`）の`turnNumber`。1始まり。試合終了時に最後に
> いたturn番号。**そのturn自体が完了した（次のturnへ遷移した）ことを意味しない**
> ——decisive actionがturn途中で発生すれば、そのturn番号のまま試合が終わる。

`turnNumber`は`CombatV1MatchState`のコンストラクタdefaultで`1`から始まり
（`combat_v1_match_state.dart:138`）、`_advanceTurnAfterEnd`（`combat_v1_engine.dart`）
でのみ`+1`される。`_advanceTurnAfterEnd`は`endTurn`/`rest`/PIN
1・2カウントkickout/SUBMISSION ESCAPEの内部共通処理として呼ばれ、これらは
いずれもPhase 11Bのpublic action 8種のうちの1つの実行結果として発生する
（`_advanceTurnAfterEnd`が、action loopの外側やaction実行と無関係に自発的に
呼ばれることはない）。

したがって`finalTurnNumber <= actionCount + 1`という関係が、現行の
`combat_v1_engine.dart`/`combat_v1_cpu_match_runner.dart`の実装構造上は常に
成立する。**ただし、この関係はPhase 12Aが正式にpublic contractとして保証して
いるものではなく、`_advanceTurnAfterEnd`の呼び出し経路という実装詳細に依存する
構造的事実に過ぎない**。Phase 12B-2Aはこれをformal structural invariantとしては
採用せず、strict validator（例: `finalTurnNumber`が`actionCount + 1`を超えたら
`CombatV1IllegalActionException`）を追加しない（25章参照）。Histogram側は
（後述する通り）sparse Mapを採用しているため、この関係が成立しない値が来ても
安全に扱える。

Statistics field名は`finalTurnNumberStats`のような誤読を避けた名前
（`CombatV1MatchLengthStatistics.finalTurnNumber`）とし、「試合が完了した
turn数」ではなく「決着時点のturn番号の分布」であることをdoc commentで明示する。

## 6. Completed-Only Denominator（正式MUST）

Phase 12B-2Aのlength statisticsは、**completed-only**を正式MUSTとする。対象は
`CombatV1MatchSimulationResult.termination == CombatV1CpuMatchTermination.matchOver`
のみ。`safetyLimit`・`invariantViolation`（Shape A/Bいずれも）は除外する。

理由（Phase 12B-1 13章「Denominator Semantics」と同じ哲学）:

- `safetyLimit`はrunner safety guard（`maxActions`）による強制打ち切りであり、
  ゲームとして正常に決着した試合長ではない。これをlengthに混ぜると、実際の
  試合長分布が人為的に`maxActions`付近へ偏る。
- `invariantViolation`は、Shape B（winner保持済み）であっても「最終invariant
  検証で異常が見つかった」結果であり、正常な試合長として扱わない。
  checkpoint途中（Shape A）の場合はなおさら、試合として完結していない。

判定はPhase 12B-1同様`termination`のみで行う——`winnerPlayerIndex`の有無や
`hasWinner`のようなmetadataでは判定しない（41章「Completed-Only Tests」で
Shape A/Bとも除外されることを直接検証する）。

`allExecuted`（safetyLimit/invariantViolationを含む全実行試合のlength
statistics）は今回のMUSTではない。既存構造上ほぼ追加コストなしでdesignを
複雑化せず分離できる場合のみSHOULDとして許容されるが、本実装では追加しない
——`actionCount`/`finalTurnNumber`は`CombatV1MatchSimulationResult`の型として
`termination`に関係なく常にnon-null値を持つため、`allExecuted`を足すこと自体は
技術的に容易だが、「Dashboard primary metricはcompletedを使う」という前提の下、
今回はスコープを最小限に保ちcompleted-onlyのみとする。

## 7. Public Result Hierarchy

既存Phase 12B-1 aggregate schema（`CombatV1GlobalAggregate`/
`CombatV1MatchupAggregate`等）を直接肥大化させない。新規に独立したvalue type
treeを追加する（`combat_v1_batch_length_statistics.dart`）:

```
CombatV1NumericDistributionSummary
  int sampleCount
  double? mean
  double? median
  double? p90
  double? p95
  int? min
  int? max

CombatV1MatchLengthStatistics
  CombatV1NumericDistributionSummary actionCount
  CombatV1NumericDistributionSummary finalTurnNumber

CombatV1GlobalDescriptiveStatistics
  CombatV1MatchLengthStatistics length

CombatV1MatchupDescriptiveStatistics
  CombatV1Matchup matchup
  CombatV1MatchLengthStatistics length

CombatV1BatchDescriptiveStatistics
  CombatV1GlobalDescriptiveStatistics global
  List<CombatV1MatchupDescriptiveStatistics> matchups  // unmodifiable, canonical order
```

`CombatV1BatchSimulationResult`（Phase 12B-1）へは、既存fieldは一切変更せず、
末尾に`statistics`を追加する:

```
CombatV1BatchSimulationResult
  ├ config / requestedMatchCount / executedMatchCount        (既存, 12B-1)
  ├ global / matchups / wrestlers / seat / mirror             (既存, 12B-1)
  └ statistics: CombatV1BatchDescriptiveStatistics            (新規, 12B-2A)
        ├ global: CombatV1GlobalDescriptiveStatistics
        │     └ length: CombatV1MatchLengthStatistics
        └ matchups: List<CombatV1MatchupDescriptiveStatistics>
              └ [i]: { matchup, length: CombatV1MatchLengthStatistics }
```

`CombatV1GlobalDescriptiveStatistics`/`CombatV1MatchupDescriptiveStatistics`が
`length`という中間fieldを持つ設計は、Phase 12B-2B（final state statistics）が
将来同じwrapperへ`finalState`のような兄弟fieldを**additiveに**追加できる余地を
残すためである——Phase 12B-2A自身はこの余地を使わない（`length`のみを持つ）。

すべてimmutable: `CombatV1NumericDistributionSummary`/
`CombatV1MatchLengthStatistics`/`CombatV1GlobalDescriptiveStatistics`/
`CombatV1MatchupDescriptiveStatistics`はconst constructor・全field final。
`CombatV1BatchDescriptiveStatistics.matchups`は`List.unmodifiable`。

## 8. Empty Sample Semantics

`sampleCount == 0`の場合:

- `mean = null`
- `median = null`
- `p90 = null`
- `p95 = null`
- `min = null`
- `max = null`

`0`や`0.0`をfabricateしない。Phase 12B-1のzero denominator philosophy
（rate系getterが`totalMatches == 0`で`null`を返す方針）と揃える。

`CombatV1NumericDistributionSummary.empty`という`static const`をライブラリ内に
用意し、histogram accumulatorの`build()`が`sampleCount == 0`のとき、この値を
そのまま返す。

## 9. Mean Algorithm

整数`sum`/`count`から計算する——**incremental floating meanは使わない**。

```dart
int _sampleCount = 0;
int _sum = 0;

void add(int value) {
  _sampleCount += 1;
  _sum += value;
}

// build時のみ:
final double mean = _sum / _sampleCount;  // int / int => double（Dart組込み演算）
```

理由（Phase 12A seed derivationとは独立した、統計固有の判断）:

- deterministic: `add`の呼び出し順序に関わらず、整数`sum`は結合則的に同じ値になる
  （floating pointの加算は結合則を満たさないため、streaming増分平均だと
  traversal順で微小に異なる値になり得る）。
- VM/Web差を抑えやすい: 最終的な1回の`int / int`除算のみがdouble演算であり、
  Dart VM・dart2js/Node間でも同じIEEE754 double演算として一致する
  （47章「VM / Web Numeric Check」）。
- numerical behaviorが単純: 中間状態が常に整数のみ。

想定scale（29章「Numeric Safe Sum」）: `160,000 matches × maxActions 500 =
80,000,000`。JS safe integer範囲（2^53 - 1 ≈ 9.007×10^15）内に十分収まる。
`maxActions`はconfigurableで上限を持たないため、極端な設定で理論上
overflowし得るが、Phase 12A seed mixer等とは別問題であり、本Phaseでは
明示的なguardを追加しない（想定scaleをdoc上の前提として明記するに留める）。

## 10. Median Algorithm

正式定義（nearest-rankではなく、標準的なorder statistics定義）:

- **odd sample**: 中央1値（`sampleCount`が奇数なら、1-basedで`rank =
  (sampleCount + 1) / 2`の値）。
- **even sample**: 中央2値の算術平均（`rank = sampleCount / 2`と
  `rank = sampleCount / 2 + 1`の値の平均）。

例: `[1, 2, 3, 4]` → median `2.5`。`[1, 2, 3]` → median `2`。

戻り値: `double?`（`sampleCount == 0`なら`null`）。

Histogramの累積count（sorted distinct valueをkeyとする）を先頭から走査し、
累積countが目的のrankへ到達した最初のvalueを、そのrankの値として採用する
（下記11章と同じ`valueAtRank`ヘルパーを共有する）。

## 11. p90 / p95 Algorithm

nearest-rank方式。1-based rank:

```
rank = ceil(p * sampleCount)
```

- p90: `rank = ceil(0.90 * sampleCount)`
- p95: `rank = ceil(0.95 * sampleCount)`

Histogramの累積countがrank以上となる最初のsource valueを採用する。

**浮動小数点ではなく整数演算でrankを計算する**（VM/Web間の浮動小数点誤差を
排除するため）:

```dart
// ceil(9n/10) == (9n + 9) ~/ 10
int p90Rank(int n) => (9 * n + 9) ~/ 10;

// ceil(19n/20) == (19n + 19) ~/ 20
int p95Rank(int n) => (19 * n + 19) ~/ 20;
```

一般形: `ceil(a/b) == (a + b - 1) ~/ b`（`a`, `b`が正の整数の場合）。p90は
`a = 9 * sampleCount, b = 10`、p95は`a = 19 * sampleCount, b = 20`
（`0.90 = 9/10`, `0.95 = 19/20`という既約分数を使うことで、`0.90 *
sampleCount`のような浮動小数点乗算を経由しない）。

戻り値はAPI一貫性のため`double?`（`valueAtRank`が返す`int`を`.toDouble()`する）。

## 12. Min / Max

source（`actionCount`/`finalTurnNumber`）が`int`なので`int? min`/`int? max`を
採用する。Histogramのsorted distinct valuesの先頭・末尾がそのまま`min`/`max`
になる。`sampleCount == 0`なら`null`。

## 13. Histogram Strategy / Allocation Policy

**Raw action/turn valuesのListを全match分保持しない**。exact bounded histogram
（`Map<int, int>`、value → 出現回数）のみを保持する。

**採用方式: sparse `Map<int, int>`**（固定`List<int>`ではない）。

判断基準（22章の「Sparse Mapを採用する場合」の基準にそのまま合致）:

- memoryが実際に観測したdistinct valueの数に比例する（`config.maxActions`の
  設定値には一切比例しない）。
- exact quantile計算が可能（binningによる近似誤差なし）。
- quantile計算時、bucket keys（distinct values）をsortする必要がある——
  ただし対象は「observed distinct value数」のみであり、`sampleCount`や
  `maxActions`そのものではない。

固定`List<int>`を採用しなかった理由: `CombatV1BatchSimulationConfig.maxActions`
はconfigurable・上限なし（`maxActions > 0`のみが検証される、
`combat_v1_batch_simulation_config.dart`参照）。固定Listだと`maxActions`の値
そのものに応じたallocation size（またはそれに対するarbitrary allocation
guard）を決める必要があり、「Histogram都合だけでCombat gameplayのmaxActions
意味を不必要に制限しない」（23章相当）という方針と衝突しやすい。さらに
`finalTurnNumber`は`actionCount`のような`maxActions`直接の上限を**正式契約
としては持たない**（5章）ため、固定Listでは「turnNumber用の配列サイズを
どう決めるか」という別の恣意的な上限を追加で導入することになる。

sparse Mapであれば、`actionCount`・`finalTurnNumber`のいずれについても、
`maxActions`の実際の値やturn数の理論上限に関わらず、**observed valueの
distinct数にのみ比例する**memoryで安全に扱える——追加のallocation guard・
上限定数は導入しない。

## 14. Action Histogram Range

`actionCount`は4章の通り、Phase 11B/12Aのloop構造から`0 <= actionCount <=
maxActions`が構造的に成立する。sparse Mapのkey数は最大でも
`min(sampleCount, maxActions + 1)`に収まる——固定Listでなくとも、実運用上の
memory使用量は妥当な範囲に収まる。Phase 12Aが既に（構造的に）この範囲を
保証しているため、Phase 12B-2A側で重複するrange validationは追加しない。

## 15. Turn Histogram Range

`finalTurnNumber >= 1`は`CombatV1MatchState.turnNumber`のdefault値（`1`）と
`_advanceTurnAfterEnd`の`+1`のみの遷移から常に成立する。上限
（`finalTurnNumber <= actionCount + 1`）は5章で述べた通り構造的事実に過ぎず、
Phase 12Aの正式contractではないため、Phase 12B-2Aはこれをstructural
invariantとして固定・validationしない。sparse Mapは`finalTurnNumber`の値に
一切の上限仮定を置かないため、この判断と矛盾なく安全に動作する。

## 16. Null Semantics

- `sampleCount == 0` → `mean`/`median`/`p90`/`p95`/`min`/`max`すべて`null`
  （8章）。
- `sampleCount >= 1` → すべて非null（`min`/`max`は`int`、他は`double`）。

「部分的にnull」（例: `sampleCount > 0`なのに`mean`だけnull）は発生しない
——`build()`は`sampleCount == 0`かどうかで完全に分岐し、中間状態を返さない。

## 17. Internal Invariants

`CombatV1BatchDescriptiveStatisticsAccumulator`（および内部の
`_CombatV1HistogramAccumulator`/`_CombatV1MatchLengthStatisticsAccumulator`）
が満たすべき内部invariant:

- histogramの全bucket countの合計は常に`sampleCount`と一致する。
- `sum`は`add`された全valueの合計と常に一致する（floating pointを経由しない
  整数加算のみ）。
- `_CombatV1MatchLengthStatisticsAccumulator.add`は、completed matchについて
  のみ呼ばれる（呼び出し側——`CombatV1BatchDescriptiveStatisticsAccumulator.add`
  ——が`termination == matchOver`のときのみ`actionCount`/`finalTurnNumber`用の
  値をpushする）。
- matchup bucketは、`termination`に関わらず（total内訳と同様、Phase 12B-1
  core aggregatorのmatchup bucket生成と同じタイミングで）**初出時に必ず
  作成される**——completed matchが1件もないmatchup（全試合safetyLimit/
  invariantViolation）でも、`sampleCount == 0`のempty
  `CombatV1MatchLengthStatistics`エントリとして`statistics.matchups`に必ず
  現れる（20章「Matchup Statistics Order」の対応関係を保つため）。

Batch Runner側（`CombatV1BatchSimulationRunner`）は、以下をPhase 12B-2A
自身の構造的invariantとしてbuild後に検証する（Codex reviewでの検証しやすさの
ため、Phase 12B-1の`_verifyMatchResultInvariants`/`_verifyInternalInvariants`
と同じ様式でfail-fastする）:

- `statistics.global.length.actionCount.sampleCount ==
  global.completedMatches`
- `statistics.global.length.finalTurnNumber.sampleCount ==
  global.completedMatches`
- `statistics.matchups.length == result.matchups.length`
- 各`i`について、`statistics.matchups[i].matchup == result.matchups[i].matchup`
  （canonical orderの一致）
- 各`i`について、`statistics.matchups[i].length.actionCount.sampleCount`
  （および`finalTurnNumber.sampleCount`）が対応する
  `result.matchups[i].completedMatches`と一致する

## 18. Matchup Statistics Order（20章）

`statistics.matchups`は、Phase 12B-1 `result.matchups`と同じcanonical order
（初出順、16 entries — 4×4 wrestler matrixの場合）を維持する。Map iteration/
hash orderへは依存しない——`CombatV1BatchDescriptiveStatisticsAccumulator`は
Phase 12B-1の`CombatV1BatchAggregationAccumulator`と全く同じ「`putIfAbsent`
成功時にorder listへ追加する」パターンを、同じ`CombatV1MatchSimulationResult`
streamに対して独立に適用する——両accumulatorは同じBatch Runnerのloopから
同じ順序で`add`されるため、結果として同じcanonical orderになる。17章の
Runner側invariant検証で、この対応が崩れていないことを明示的に検証する。

## 19. Streaming Memory / Memory Complexity

1 matchの処理フロー:

```
runSingleMatch
  → Phase 12B-1 core accumulator.add(result)
  → Phase 12B-2A statistics accumulator.add(result)
  → resultへの参照を破棄（次のloop iterationへ）
```

raw valuesは一切保持しない。Memory complexityは:

```
O(matchup count × (matchup毎のdistinct actionCount数 + distinct
  finalTurnNumber数))
  + O(global distinct actionCount数 + global distinct finalTurnNumber数)
```

であり、`O(totalMatches)`ではない。sparse Mapのkey数は`sampleCount`以下
かつ「実際に観測されたdistinct値の数」以下に収まる——値の重複が多いほど
（典型的なCPU vs CPU batchでは、多くの試合が近い`actionCount`/
`finalTurnNumber`帯に収束するため重複は多い）、実際のmemoryはさらに小さく
なる。

## 20. Batch Runner Integration

Phase 12B-1 Runner（`CombatV1BatchSimulationRunner.run`）へ最小限の接続のみ
行う:

```
matchResult
  → core accumulator.add(matchResult)      // 既存（Phase 12B-1）
  → statistics accumulator.add(matchResult) // 新規（Phase 12B-2A）
```

Phase 12A実行順・RNG消費・`CombatV1SimulationRunner.runSingleMatch`の呼び出し
方には一切影響を与えない——statistics accumulationは`CombatV1MatchSimulationResult`
という既に確定したstructured resultを読み取るのみで、simulationの実行や
RNG stateへは触れない。

## 21. Result Construction

Batch run完了後、Runnerは以下の2つのbundleをそれぞれ独立に構築する:

- core aggregate bundle（`CombatV1BatchAggregationAccumulator.build()`、既存）
- descriptive statistics bundle
  （`CombatV1BatchDescriptiveStatisticsAccumulator.build()`、新規）

両者を17章の構造的invariantで突き合わせた上で、`CombatV1BatchSimulationResult`
（`statistics`フィールド追加）へ詰め替える。すべてのcollectionは
`List.unmodifiable`のまま。

## 22. Development Snapshot Extension

Development Snapshot（`combatV1BatchResultSnapshotJson`）へ、top-level
additive fieldとして`statistics`を追加する。既存field（`metadata`/`global`/
`orderedMatchups`/`wrestlers`/`seat`/`mirror`）は**rename・delete・semantic
変更のいずれも行わない**。

```
statistics:
  global:
    completed:
      actionCount: { sampleCount, mean, median, p90, p95, min, max }
      finalTurnNumber: { sampleCount, mean, median, p90, p95, min, max }
  orderedMatchups:
    - wrestlerAId, wrestlerBId
      completed:
        actionCount: { ... }
        finalTurnNumber: { ... }
    - ...  // 16 entries、result.matchupsと同じcanonical order
```

`allExecuted`は実装しないため（6章）、`completed`の兄弟keyとしての
`allExecuted`ツリーは一切出力しない——不必要な空treeを作らない。

各`CombatV1NumericDistributionSummary`のJSON表現は`sampleCount`/`mean`/
`median`/`p90`/`p95`/`min`/`max`の7 keyで固定。emptyの場合`sampleCount: 0`、
他はJSON `null`のまま（`0`/`0.0`へfabricateしない、8章）。

`metadata.phase`は`"12B-1"`から`"12B-2A"`へ更新する——このfieldはformal
schemaではなく、開発時にどのPhaseで生成されたsnapshotかを示す人間可読な
metadataであるため、rename/削除にはあたらない
（`combat_v1_batch_result_snapshot_serializer_test.dart`の該当assertionも
同時に更新する）。

## 23. Snapshot Determinism

同一`CombatV1BatchSimulationResult`からは、`generatedAt`を除いて常に同一の
snapshot JSONになる——`statistics`もこの契約に従う。histogramの内部
`Map<int, int>`のiteration順（insertion順やhash順）には一切依存しない
——`build()`は必ずsorted distinct valuesを経由してmean/median/p90/p95/min/max
を計算するため、`add`の呼び出し順序（Batch Runnerのmatchup/matchIndex
loop順）が変わっても出力は変化しない（44章「Determinism」テストで直接
検証する）。

## 24. Benchmark Policy

通常のunit testへperformance thresholdは入れない——manual測定で十分とする。
少なくとも320 matches・1,600 matchesについて、可能なら16,000 matchesについて
測定する。記録する内容:

- config（wrestler数、matchesPerMatchup、maxActions、pairing）
- elapsed milliseconds
- matches/sec
- statistics accumulation有効時の値
- 生成されるsnapshot fileサイズ

160,000 matches規模は時間がかかる場合、無理に実行しない。測定結果は
Completion Reportへ記載する（Web Worker・isolate・async execution framework
は実装しない——54章のCompletion Reportで報告する数値は、単一スレッド・
同期実行でのbaseline measurementである）。

## 25. Dashboardとの境界

Phase 12B-2A自身はDashboard/UIを一切実装しない。`CombatV1BatchDescriptiveStatistics`
（および将来Phase 12B-2Bが追加する`CombatV1MatchFinalStateSummary`統計）は、
Dashboard v1が「読み取るだけ」で済む、既に完成したimmutable dataとして提供する
——Dashboard側の集計・再計算・warning判定ロジックは、Phase 12B-2A/12B-2Bの
責務には含めない。

## 26. Deferred: Final-State Statistics / Retention（12B-2B・12B-2C）

以下はPhase 12B-2A実装後も明示的に未実装のまま残す:

- **Phase 12B-2B**（Dashboard後）: final HP/final KOC/shared HEAT/differential
  のdescriptive statistics。`CombatV1MatchFinalStateSummary`には既に該当データ
  が存在するが、Phase 12B-2Aはこれらへ一切アクセスしない。
- **Phase 12B-2C**（必要になった場合）: bounded exceptional retention
  （safety/invariant match metadata list）、failure replay index、batch ID、
  large benchmark tooling、browser execution strategyの本格検討。

Phase 12B-2Aの`statistics`公開schemaは、これらを将来additiveに追加できる形
（`CombatV1GlobalDescriptiveStatistics`/`CombatV1MatchupDescriptiveStatistics`
が`length`のみを持つ中間wrapperである、7章参照）を意図しているが、それ自体を
今回実装することはない。
