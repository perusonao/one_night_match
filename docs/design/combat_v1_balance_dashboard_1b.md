# Combat Ver.1 — Balance Dashboard 1B 設計文書

- ステータス: Balance Dashboard 1B（Editable Config / Presets / Detail /
  UX Polish）実装。Playable 1A/1B/1C（merge・Production deploy済み）・
  Balance Dashboard 1A（merge済み）を変更せず、additiveに拡張する。Core
  Engine・Phase 12A（Simulation Core）・Phase 12B-1（Batch Core
  Aggregation）・Phase 12B-2A（Match Length Statistics）は一切変更しない。
- 関連: [`combat_v1_balance_dashboard_1a.md`](combat_v1_balance_dashboard_1a.md) /
  [`combat_v1_phase12b2a_match_length_statistics.md`](combat_v1_phase12b2a_match_length_statistics.md) /
  [`combat_v1_phase12b1_batch_core_aggregation.md`](combat_v1_phase12b1_batch_core_aggregation.md) /
  [`combat_v1_phase12a_simulation_core.md`](combat_v1_phase12a_simulation_core.md)
- 実装:
  `lib/src/combat_v1/dashboard/combat_v1_balance_dashboard_run_config.dart`
  （新規、UI draft configのpure value type + validation + `toBatchConfig`）/
  `combat_v1_balance_dashboard_view_model.dart`（既存mapperへmatchup detail
  mapperをadditiveに追加）/ `combat_v1_balance_dashboard_formatting.dart`
  （変更なし）/ `combat_v1_balance_simulation_service.dart`（`run()`が
  `CombatV1BatchSimulationConfig`を引数に取るよう拡張）/
  `combat_v1_balance_dashboard_screen.dart`（editable config UI・stale
  UX・matchup detail UI等をadditiveに実装）
- テスト:
  `test/combat_v1/dashboard/combat_v1_balance_dashboard_run_config_test.dart`
  （新規、pure Dart configのvalidation test）/
  `combat_v1_balance_dashboard_view_model_test.dart`（matchup detail
  mapper test追加）/ `combat_v1_balance_dashboard_screen_test.dart`
  （config編集・stale result・reentrancy・matchup detail・mobile・
  Analysis confirmationのwidget test）/
  `combat_v1_balance_simulation_service_integration_test.dart`
  （editable config → service → runner → ViewModel → matchup detail
  mapperの小規模real integration test追加）

---

## 1. Purpose（目的）

Balance Dashboard 1A（fixed default run / read-only）を拡張し、開発者が
同じCombat Ver.1 Batch Simulationを、条件を変えてブラウザ上で分析できる
development analysis UIにする。正式なbalance判定ツールや統計研究環境には
しない（3章「Non-Goals」）。

## 2. Scope（今回実装するもの）

- matchesPerMatchup（preset: Smoke 20 / Quick 100 / Analysis 1000 /
  Custom 1..1000）・masterSeed・Player A/B policy・maxActions（Advanced
  section）の編集
- wrestler set（canonical 4人固定）・rules（`const CombatV1RulesConfig()`
  固定）は編集不可のまま
- draftConfig / lastRunConfigの分離、stale result表示
- Run button状態（Idle/Run Again/Run Updated Simulation）、reentrancy
  guard、frame yield（1A同様）
- performance warning（>100/matchup）・Analysis preset（1000/matchup、
  16,000 total）実行前のconfirmation dialog
- 4×4 matrix cell tap → matchup detail（desktop: inline panel、mobile:
  bottom sheet）
- responsive（mobile config縦積み、matrix horizontal scroll維持）

## 3. Non-Goals（今回実装しないもの）

Phase 12B-2B（final-state statistics）・Phase 12B-2C（retention/batch
ID）・HP/KOC/HEAT aggregate・confidence interval・auto balance
judgment・OP/weak warning・ranking algorithm・historical run
persistence・multiple-run comparison・CSV/JSON export・replay UI・Web
Worker/isolate・cancellation・parallel simulation・rules editor・custom
wrestler set・URL state・chart library・Playable UI変更・Production
Data変更・Core Engine変更。

## 4. Config Model — `CombatV1BalanceDashboardRunConfig`

`combat_v1_balance_dashboard_run_config.dart`。UI側config typeで、責務は
3つのみ:

1. UI入力（preset選択・custom text・seed text・policy・maxActions
   text）の保持
2. field単位のinline validation（`matchesPerMatchupError` /
   `masterSeedError` / `maxActionsError`、`isValid`）
3. 検証済み値からdomainの`CombatV1BatchSimulationConfig`への変換
   （`toBatchConfig()`）

domain configのrule engineを再実装しない——wrestlerIdsは常に
`combatV1DefaultBatchWrestlerIds`（canonical 4人）、rulesは常に
`const CombatV1RulesConfig()`（default引数のまま）。

`CombatV1BalanceDashboardRunConfig.initial()`が初期draft
（54章相当、1Aのfixed defaultと同一値: Quick(100)・seed 12345・
RandomLegal/RandomLegal・maxActions 500）。

## 5. Presets（matchesPerMatchup）

`CombatV1BalanceDashboardMatchesPreset` enum: `smoke`(20) /
`quick`(100、default) / `analysis`(1000) / `custom`（custom text field
から読み取り）。

- Custom rangeは`1..1000`（`hardMaxMatchesPerMatchup = 1000`、Dashboard
  UI guardであってdomain ruleではない——`CombatV1BatchSimulationConfig`
  へ新しい上限を追加しない）
- Total matches（`16 × matchesPerMatchup`）は入力付近に常時表示
- `matchesPerMatchup > 100`でperformance warning
  （"Large runs may temporarily freeze the browser."）を表示
- `matchesPerMatchup >= 1000`（Analysis preset、またはcustomで1000
  ちょうど）はrun前のconfirmation dialogが必須

## 6. Master Seed / Policies / Max Actions

- Master Seed: editable integer text field（blank不可、整数以外
  invalid、符号は問わない）
- Player A/B Policy: 既存`CombatV1SimulationPolicyKind`
  （`firstLegal`/`randomLegal`）のdropdown。新しいpolicyは追加しない
- Max Actions: Advanced section（`ExpansionTile`）内、editable
  integer、最小1

## 7. Draft Config vs Last Run Config

Screen state（`_CombatV1BalanceDashboardScreenState`）は`_draft`
（`CombatV1BalanceDashboardRunConfig`）と`_lastRunConfig`
（`CombatV1BatchSimulationConfig?`、run開始時のsnapshot）を分離して
保持する。設定を変更しても`_lastOutput`（既存result）を即消さない
——結果は常に`_lastRunConfig`に結び付く。

`_lastRunConfig`はrun開始時に`_draft.toBatchConfig()`で1回だけ変換した
インスタンスをそのまま保持する（41章「Config Immutability」相当）
——run中にdraft configを変更できないため、結果との不一致は起きない。

## 8. Stale Result UX

`_isStale`は、`_lastRunConfig`が存在し、かつ`_draft`の実効値
（matchesPerMatchup/masterSeed/playerAPolicy/playerBPolicy/maxActions）
が`_lastRunConfig`と1つでも異なる場合にtrueになる。true時は
`Settings changed — run again to refresh results.`というbannerを表示
する。stale resultはそのまま閲覧できるが、bannerにより「現在draftと
同じ結果」という誤認を防ぐ。

## 9. Run Button States

- Idle: `Run Simulation`
- Success + unchanged config: `Run Again`
- Success + stale config: `Run Updated Simulation`
- Running: `実行中…`（button disabled）

## 10. Execution / Reentrancy / Frame Yield

`_run()`:

1. running中なら即return（二重run禁止）
2. draftがinvalidなら即return（Run buttonがdisabledのため通常到達
   しない）
3. `_draft.toBatchConfig()`でbatch configを構築
4. `requiresRunConfirmation`（>=1000/matchup）ならconfirmation
   dialogを表示、Cancelなら`return`（runner未実行のまま——simulation
   cancellation機能ではない）
5. `_executeRun(batchConfig)`: `_status = running` →
   `WidgetsBinding.instance.endOfFrame`を1回await（1Aと同じ frame
   yield） → `widget.runFunction(batchConfig)`呼び出し → 成功なら
   `_lastOutput`/`_lastRunConfig`更新、失敗ならerror state

running中はRun button・preset chip・custom field・seed field・policy
dropdown・maxActions fieldすべてdisabled。

## 11. Main-Thread Limitation

1Aと同様、Web Worker/isolateは使用しない。`CombatV1BatchSimulationRunner.run`
は同期実行のため、実行中はmain isolateをblockする可能性がある。画面上に
注釈を表示し、progress表示はindeterminate（`LinearProgressIndicator` +
`Running N simulations…`）のみ——Batch Runnerへprogress callbackは追加
しない。

## 12. Matchup Detail

4×4 matrixのcellをtapすると、そのmatchupのdetailを表示する。

- **データソース**: `CombatV1DashboardMatchupCell.detail`
  （`CombatV1DashboardMatchupDetail`、ViewModel内で`CombatV1MatchupAggregate`
  と`CombatV1MatchupDescriptiveStatistics`をmatchup keyで対応付けて
  構築、40章「Domain Alignment」相当——対応するstatisticsが見つから
  ない場合はfail-fast）
- **内容**: Wrestler A/B・Total Matches・Completed・Player A/B
  Wins・Win Rate・Safety Limit count/rate・Invariant Violation
  count/rate・Terminal Causes（normalPin/directPin/submission/
  submissionFinisher/other、既存enum/fieldをそのまま表示）・Action
  Count分布（Mean/Median/P90/P95/Min/Max）・Final Turn分布（同）
- **Desktop**: matrix下のinline panel（`_MatchupDetailPanel`）
- **Mobile**（幅 < 600px）: `showModalBottomSheet` +
  `DraggableScrollableSheet`（scrollable）
- **selection state**: `_selectedMatchup`（`CombatV1Matchup?`、
  screen-local）。新run成功後も同じmatchup keyが存在すれば自動的に
  selectionが維持される（wrestler setがcanonical固定のため常に
  存在する）。見つからない場合は安全にnull扱い（44章）
- **matrix cell**: selected cellはsubtle outline（gold border）で示す
  ——heatmap配色は追加しない（28章「Matrix Cell」）

## 13. Responsive

- Mobile（< 600px幅）: config controlsは縦積み（`LayoutBuilder`で
  Policy dropdownの2列/1列を切り替え）、matrixは既存の
  horizontal `SingleChildScrollView`を維持、matchup detailはbottom
  sheet
- Desktop: 960px max widthのcentered layoutを維持

## 14. No New Dependencies / No Snapshot Data Source

新規chart/UIライブラリは追加しない（`Card`/`Table`/`GridView`/`Container`/
`ExpansionTile`/`DropdownButtonFormField`/`ChoiceChip`等、既存Flutter
Material widgetのみ）。正式data pathは1Aと同じ:

```
CombatV1BatchSimulationConfig（draft → toBatchConfig）
  → CombatV1BatchSimulationRunner.run
  → CombatV1BatchSimulationResult
  → CombatV1BalanceDashboardViewModel.fromResult（matchup detail含む）
  → Flutter UI
```

Development Snapshot JSON・`dart:io`依存writerはimportしない（1Aと
同じ制約を維持）。

## 15. Test Strategy

- **Config test**（`combat_v1_balance_dashboard_run_config_test.dart`）:
  default config・preset 20/100/1000・custom valid/invalid（0・1001・
  空欄・非数値）・invalid seed・invalid maxActions・policy A/B
  mapping（全組み合わせ）
- **ViewModel test**: 既存1A testに加え、matchup detail mapper
  （16 cellすべてがdetailを持つ・A vs B/B vs A分離・counts/rates・
  terminal causes・action/final turn distribution・statistics
  matchup欠落時のfail-fast）
- **Widget test**: idle（config card表示）・preset切り替え・
  validation error表示とRun button disabled・reentrancy（running中の
  control disabled・duplicate run防止）・stale result UX（変更後
  banner表示・再run後消滅）・last run metadata（draft変更後もrun時点
  のconfigを表示）・matchup detail（desktop inline panel・mobile
  bottom sheet・selection維持）・Analysis confirmation（Cancel/Run）・
  responsive smoke（320px、overflowなし）。すべて`runFunction`を
  fakeへ差し替え、16,000等の大規模simulationは実行しない
- **Integration test**: 1Aの軽量integration testに加え、editable
  config service → runner → ViewModel → matchup detail mapperの
  実結線をcanonical 4 wrestler・1 match/matchup（16 matches）で確認

## 16. Balance Dashboard 1C+ Deferred Scope

以下はDashboard 1Bでは実装しない（将来phaseで検討）:

- Phase 12B-2B: final HP/KOC/HEATのdescriptive statistics
- Phase 12B-2C: exceptional retention（failure replay index等）
- historical run persistence・multiple-run比較・CSV/JSON export・
  replay UI・URL state・chart library・Web Worker/isolate並列化・
  cancellation・auto balance judgment・confidence interval

Dashboard 1Bは引き続き、Batch Runner・aggregate・statistics
public boundaryの消費者に留まり、その内部実装・schemaを変更しない。
