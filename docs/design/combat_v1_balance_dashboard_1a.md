# Combat Ver.1 — Balance Dashboard 1A 設計文書

- ステータス: Balance Dashboard 1A（Fixed Default Run / Read-only Dashboard）実装。
  Phase 12B-2A（`5d94512c842c96ecd17676536418b6fba4dcf99a`、merge済み）のpublic APIの
  みを利用し、Core Engine・Phase 12A（Simulation Core）・Phase 12B-1（Batch Core
  Aggregation）・Phase 12B-2A（Match Length Statistics）は一切変更しない。
- 関連: [`combat_v1_phase12b2a_match_length_statistics.md`](combat_v1_phase12b2a_match_length_statistics.md) /
  [`combat_v1_phase12b1_batch_core_aggregation.md`](combat_v1_phase12b1_batch_core_aggregation.md) /
  [`combat_v1_phase12a_simulation_core.md`](combat_v1_phase12a_simulation_core.md) /
  [`combat_v1_phase11a_production_match_setup.md`](combat_v1_phase11a_production_match_setup.md)
- 実装: `lib/src/combat_v1/dashboard/combat_v1_balance_dashboard_view_model.dart`
  （pure ViewModel + mapper）/
  `combat_v1_balance_dashboard_formatting.dart`（pure formatting helper）/
  `combat_v1_balance_simulation_service.dart`（fixed config + Stopwatch +
  runner呼出し + mapping）/ `combat_v1_balance_dashboard_screen.dart`（Flutter UI）/
  `lib/src/screens.dart`（Debug分析からの導線追加）
- テスト: `test/combat_v1/dashboard/combat_v1_balance_dashboard_view_model_test.dart`
  （pure mapper/formatting test）/
  `combat_v1_balance_dashboard_screen_test.dart`（widget test、synthetic
  ViewModel injection）/
  `combat_v1_balance_simulation_service_integration_test.dart`（実runner使用、
  小規模16 matches）

---

## 1. Purpose（目的）

Combat Ver.1のbalance simulation結果を、最短でブラウザ上に表示できる状態にする。
既存Title画面の「Debug分析」配下から、開発者が明示的に「Run Default
Simulation」を押すと、固定default configでbatch simulationを実行し、結果を
Flutter UI上に表示する。

Dashboard 1Aはdevelopment analysis UIであり、ゲーム本編UIではない。

## 2. Scope（今回実装するもの）

- fixed default configによるCPU vs CPU batch simulation実行（4 wrestler ×
  100 matches/matchup = 1,600 matches）
- 明示的な「Run Default Simulation」ボタン（自動実行しない）
- `CombatV1BatchSimulationResult`から画面表示用へのpure ViewModel mapping
- Global summary / Wrestler summary / 4×4 Matchup Matrix / Mirror panel /
  Player A・B panel / Length panel の表示
- idle/running/error/successの4 state
- percent/null formattingの統一
- Debug分析画面からのnamed-route不使用の導線追加（`Navigator.push` +
  `MaterialPageRoute`）
- screen-local state（`StatefulWidget` + `setState`）
- widget test / pure ViewModel test / 小規模integration test

## 3. Non-Scope（今回実装しないもの）

Dashboard 1Bおよびそれ以降へ明示的に先送りする:

- editable config（matches/seed/policy/maxActions/rules/wrestler subset）
- config preset
- matchup detail modal / cell click
- historical runs / run比較
- chart / heatmap閾値
- balance warning（win rate thresholdによる自動判定）
- confidence interval・有意差検定
- HP/KOC/HEATのdescriptive statistics（Phase 12B-2B scope）
- exceptional retention（failure replay等、Phase 12B-2C scope）
- replay UI・batch ID・CSV/JSON web export・URL state
- Web Worker / isolate並列化・cancellation・progress callback・chunking
- Batch Runner本体・aggregate・statistics schemaへの変更

Dashboard 1AはPhase 12B-1／Phase 12B-2Aが確立したpublic boundary
（`CombatV1BatchSimulationRunner.run` → `CombatV1BatchSimulationResult`）だけを
利用する消費者であり、その内部実装・schemaを一切変更しない。

## 4. Entry Point（導線）

既存Title画面の「Debug分析」ボタン → `DebugScreen`
（`lib/src/screens.dart`）配下へ、新規ボタン「Combat V1 Balance
Dashboard（開発用）」を追加する。

既存architecture（`Navigator.push` + `MaterialPageRoute`）にそのまま合わせ、
named route・GoRouter・Router APIは新規導入しない。ラベルに「開発用」を含め、
一般ゲーム機能と混同しないようにする（build modeによる非表示制御は行わない）。

## 5. Fixed Default Config

Dashboard 1Aは設定編集不可。以下を`CombatV1BalanceSimulationService`内で
固定生成する:

| 項目 | 値 |
|---|---|
| wrestlers | misaki, jack, akari, reina（`combatV1DefaultBatchWrestlerIds`） |
| matchesPerMatchup | 100 |
| total matches | 1,600（4×4 matchup × 100） |
| masterSeed | 12345 |
| playerAPolicy | RandomLegal |
| playerBPolicy | RandomLegal（`CombatV1PolicyPairing.randomVsRandom`） |
| maxActions | 500 |
| rules | `const CombatV1RulesConfig()`（Core Engine既定値） |

この値は`CombatV1BatchSimulationConfig`のdefault値と一致するが、Dashboard 1A
はこれを独自にhard-codeする（`CombatV1BalanceSimulationService`
内の`combatV1BalanceDashboardDefaultConfig()`が唯一の定義元）——将来
`CombatV1BatchSimulationConfig`のdefault値が変わった場合でも、Dashboard 1Aの
「正式default」は本ドキュメント・本関数が明示的に定義する値のまま保たれる。

## 6. Data Flow（正式data path）

```
CombatV1BatchSimulationConfig（fixed）
  → CombatV1BatchSimulationRunner.run（Phase 12B-1、既存public API）
  → CombatV1BatchSimulationResult（domain result、Phase 12B-1/12B-2A）
  → CombatV1BalanceDashboardViewModel.fromResult（pure mapper）
  → Flutter UI（CombatV1BalanceDashboardScreen）
```

Development Snapshot JSON（`combat_v1_batch_result_snapshot_serializer.dart`/
`combat_v1_batch_result_snapshot_writer.dart`）は一切経由しない。Snapshotは
CLI開発者向けのdevtoolsであり、Dashboardのsource of truthではない。

**禁止**: `BatchResult → JSON → parse → UI`という経路。ViewModelは常に
domain object（`CombatV1BatchSimulationResult`とその子aggregate/statistics
tree）から直接構築する。

## 7. Do Not Import dart:io Writer

`combat_v1_batch_result_snapshot_writer.dart`は`dart:io`に依存する。
Dashboard/Flutter Web側の実装ファイル（ViewModel/Service/Screen）からは
このfileを一切importしない。Dashboard 1Aではserializerも不要——Web build
のimport graphへ`dart:io`を混入させないことを明示的な設計制約とする。

検証方法: 8章「Web Build Validation」参照。

## 8. ViewModel

`lib/src/combat_v1/dashboard/combat_v1_balance_dashboard_view_model.dart`。

`CombatV1BalanceDashboardViewModel.fromResult(CombatV1BatchSimulationResult
result)`という1つのfactory constructorのみを公開するpure mapper。UI widgetは
`CombatV1BatchSimulationResult`のtreeを直接探索しない——常にこのViewModelの
field経由でアクセスする。

構造:

- `runSummary`（`CombatV1DashboardRunSummary`）: wrestlerIds・
  matchesPerMatchup・requested/executedMatchCount・masterSeed・
  playerA/BPolicyLabel・maxActions・rulesLabel
- `globalSummary`（`CombatV1DashboardGlobalSummary`）: totalMatches・
  completedMatches・completionRate・playerA/BWinRate・safetyLimitMatches/Rate・
  invariantViolationMatches/Rate・avgActions・p90Actions
- `healthSummary`（`CombatV1DashboardHealthSummary`）: safetyLimit /
  invariantViolationそれぞれの`CombatV1DashboardHealthMetric`
  （count/rate/status）
- `wrestlerRows`（`List<CombatV1DashboardWrestlerRow>`）: canonical順（4件）
- `matchupMatrix`（`CombatV1DashboardMatchupMatrix`）: wrestlerIds（canonical
  順）＋`rows[i][j]`の2次元`CombatV1DashboardMatchupCell`
- `mirrorSummary`（`CombatV1DashboardMirrorSummary`）
- `seatSummary`（`CombatV1DashboardSeatSummary`、Player A/B panel）
- `lengthSummary`（`CombatV1DashboardLengthSummary`）: actionCount /
  finalTurnNumberそれぞれの`CombatV1DashboardDistributionSummary`
  （sampleCount/mean/median/p90/p95/min/max）

`matchupMatrix`は`result.config.wrestlerIds`（canonical順）と
`result.matchups`（`Map<CombatV1Matchup, CombatV1MatchupAggregate>`へ変換）
から、行＝Player A・列＝Player Bの構造で組み立てる。対応する
`CombatV1MatchupAggregate`が見つからない場合（構造的に発生し得ないが）は
`StateError`でfail-fastする——silent fallbackはしない。

displayNameは`combatV1ProductionWrestlerRegistry[wrestlerId]!.wrestler.name`
を唯一のsource of truthとする。未知のwrestlerIdは`StateError`でfail-fastする
（Dashboard 1Aは常にProduction registryに存在するIDのみを扱うため、この分岐は
到達しないことをtestで確認する）。

## 9. Formatting

`combat_v1_balance_dashboard_formatting.dart`が唯一の定義元。

- percent: `0.637` → `"63.7%"`（小数点1桁固定、`100.0%`/`0.0%`も同形式）
- null: 全dashboardで`"—"`に統一（`N/A`・`未計測`等は使わない）
- nullable count / nullable double も同じ`"—"`

ViewModelは常にraw値（`double?`/`int`/`int?`）を保持し、formattingはUI
widget（`Text`）が上記helperを呼び出す際に行う——ViewModel自体は文字列化
しない（pure data / pure format helperの責務分離）。

## 10. State Model

`CombatV1BalanceDashboardScreen`は`StatefulWidget` + `setState`（既存
architectureに合わせる、Provider/Riverpod/BLoC等は導入しない）。

```dart
enum _DashboardRunStatus { idle, running, success, error }
```

保持するstate:

- `_status`（`_DashboardRunStatus`、初期値`idle`）
- `_lastOutput`（`CombatV1BalanceRunOutput?`、ViewModel+runtime+ranAtを含む）
- `_errorMessage`（`String?`）

Domain resultそのもの（`CombatV1BatchSimulationResult`）はscreen stateへ
保持しない（14章参照）——ViewModelのみを保持することで、UI層が常にpure
read-only structure経由でしかdomain treeへ触れられないようにする。

Dashboard 1Aではdraft config stateは持たない（configはfixedのため）。

## 11. Execution Model

Runボタン押下（`_run()`）:

1. 二重run防止（`_status == running`なら即return、48章）
2. `setState(() => _status = running, _errorMessage = null)`
3. `WidgetsBinding.instance.endOfFrame`を1回awaitし、spinnerを描画させる
   （12章）
4. `widget.runFunction()`を呼ぶ（既定値は
   `CombatV1BalanceSimulationService().run`）
   - service内部: `Stopwatch`開始 → fixed
     `CombatV1BatchSimulationConfig`構築 →
     `CombatV1BatchSimulationRunner.run` →
     `CombatV1BalanceDashboardViewModel.fromResult` → `Stopwatch`停止 →
     `DateTime.now()`で`ranAt`記録 → `CombatV1BalanceRunOutput`を返す
5. 成功: `setState(() => _lastOutput = output, _status = success)`
6. 例外: `setState(() => _errorMessage = ..., _status = error)`

`ranAt`（`DateTime.now()`）はUI/service metadataであり、domain
statistics・determinismには一切影響しない（Batch Runner・aggregate・
statisticsへは渡さない）。

## 12. Main-Thread Limitation

Dashboard 1AはWeb Worker / isolate化しない。`CombatV1BatchSimulationRunner.run`
は同期実行のため、1,600 matches実行中はFlutterのmain isolateをblockする
可能性がある。

このため:

- Runボタン押下後、`WidgetsBinding.instance.endOfFrame`を1回awaitしてから
  実際のrunner呼び出しへ進む（spinner/disabled buttonが最低1 frame描画
  されることを保証する。`Duration.zero`のみのdelayより、frame描画意図が
  明確な方式として採用）
- Dashboard内に開発向け注釈「実行中は画面操作が一時的に停止する場合が
  あります」を表示する
- progress表示はindeterminate（`LinearProgressIndicator` +
  「Running 1,600 simulations…」）のみ。progress callbackはBatch Runnerへ
  追加しない（22章）
- Cancelボタンは実装しない（sync runnerでは処理中のイベントを処理できない
  ため、23章）

## 13. Layout

既存`Scaffold` + `AppBar` + `ListView` + `Card`のconventionに合わせる。

Desktop/Web:

- `Center` + `ConstrainedBox(maxWidth: ...)`でcontentを中央寄せ
- summary card grid（`GridView`/`Wrap`、既存`playtest_analytics_screen.dart`の
  `_StatTile`パターンを踏襲）
- wrestler summary table
- 4×4 matchup matrix（`SingleChildScrollView(scrollDirection: horizontal)`で
  常時横scroll可能にする——狭幅でもdataを欠落させない）
- mirror / seat panel
- length panel

Mobile: 上記を縦積み（`ListView`が自然に縦積みになる）。

新規chart dependencyは追加しない。`Card`/`Table`/`GridView`/`Container`のみで
構築する。

## 14. Matrix Semantics

4×4 ordered matrix。行＝Player A（行側wrestler）、列＝Player B（列側
wrestler）。セルの主表示は「行側wrestlerがPlayer Aとして勝ったcompleted
試合の割合」（`playerAWinRateCompletedMatches`）。

UI上に必ず説明文を表示する:

> 行＝Player A、列＝Player B。セルの勝率は行側レスラーがPlayer Aとして
> 勝ったcompleted試合の割合です。

A vs B と B vs A は別cellとして両方表示する（mirror matchのみ同一
wrestlerでdiagonal上に現れる）。diagonal（mirror）はsubtleなstyleで区別
するが、強いheatmap配色（勝率高低を赤/緑で意味付け）はしない——neutral
surface + subtle accentのみ。

## 15. Health Semantics

Invariant violation・safety limitは「balance threshold heuristic」ではなく
「engine/runtime healthの0/nonzero判定」として扱う（既存Batch Runnerが
構造的invarianceをfail-fastで守っている前提の上で、それでも観測された
異常件数を可視化する）:

- invariant violation: `count == 0` → normal、`count > 0` → health error
- safety limit: `count == 0` → normal、`count > 0` → health warning

Win rate threshold（例: 「Misakiが60%超えたらOP」等）による自動balance
warningは実装しない（31章、balance thresholdとhealth checkは明確に別概念）。

## 16. Test Strategy

- **Pure ViewModel test**（`combat_v1_balance_dashboard_view_model_test.dart`）:
  percent/null formatting、display-name lookup、canonical wrestler
  order、global summary mapping、wrestler rows、4×4 matrix（16 cells）・
  row/column semantics・A vs B/B vs A分離・mirror diagonal、seat
  mapping、mirror mapping、length stats mapping、health 0/nonzero、
  statistics/core matchup整合、unknown/missing matchup handling。
  synthetic `CombatV1BatchSimulationResult`（Engineを起動しない）を使う。
- **Widget test**（`combat_v1_balance_dashboard_screen_test.dart`）:
  idle（title/config summary/Runボタン）、running（button
  disabled/progress/running text）、success（summary/4 wrestler
  rows/4×4 matrix/seat/mirror/length）、null表示（`—`）、error（persistent
  error panel）、responsive smoke（狭幅でoverflowなし）。すべて
  `runFunction`をfakeへ差し替え、1,600 real simulationは実行しない。
- **Integration test**（`combat_v1_balance_simulation_service_integration_test.dart`）:
  canonical 4 wrestler・1 match/matchup（16 matches）で
  service → runner → mapperの実結線を確認する。大量simulationの
  correctness再検証は行わない（Phase 12B-1/12B-2A側で既に検証済み）。

## 17. Dashboard 1B Deferred Scope

以下はDashboard 1Bで検討する:

- matchesPerMatchup変更・masterSeed変更・policy A/B selector・maxActions
  advanced setting
- stale-result表示・matchup detail（cell click/detail panel）
- performance warning（1,600 matches実行時間が長い場合の案内）
- 上記に伴うdraft config state・config validation UI

## 18. Phase 12B-2B / 12B-2C Deferred Scope

Dashboard 1Aの実装はこれらへ一切踏み込まない:

- Phase 12B-2B: final HP/KOC/shared HEATのdescriptive statistics
- Phase 12B-2C: exceptional retention（failure replay index等）

Dashboard 1Aは既存のBatch Runner・aggregate・statistics publicAPIをそのまま
消費するのみで、Batch Runner本体・aggregate・statistics schemaへの変更は
一切行わない。
