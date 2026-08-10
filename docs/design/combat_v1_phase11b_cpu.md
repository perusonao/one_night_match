# Combat Ver.1 Phase 11B — CPU / Legal Action基盤 設計文書

- ステータス: Phase 11B（CPU / Legal Action基盤 実装）完了時点。
- 関連: [`../combat_rules_v1.md`](../combat_rules_v1.md)（SSOT） /
  [`combat_v1_phase1_design.md`](combat_v1_phase1_design.md) /
  [`combat_v1_phase11a_production_match_setup.md`](combat_v1_phase11a_production_match_setup.md)
- 実装: `lib/src/combat_v1/combat_v1_legal_action.dart` /
  `combat_v1_legal_action_enumerator.dart` / `combat_v1_decision_policy.dart` /
  `combat_v1_action_executor.dart` / `combat_v1_action_observer.dart` /
  `combat_v1_cpu_match_runner.dart`
- テスト: `test/combat_v1/combat_v1_legal_action_test.dart` /
  `combat_v1_legal_action_enumerator_test.dart` /
  `combat_v1_decision_policy_test.dart` / `combat_v1_action_executor_test.dart` /
  `combat_v1_cpu_match_runner_test.dart` /
  `combat_v1_cpu_production_integration_test.dart`

---

## 1. 目的とスコープ

Phase 11Bは「強いAI」ではなく、以下を満たすCPU基盤を作ることを目的とする:

- Combat V1ルールに違反しない（legal actionだけを生成する）
- deterministic test可能
- random decisionもseed再現可能
- CPU vs CPUを1試合、boundedに実行可能
- Phase 12 Simulator・将来UIのLegal Action列挙が再利用可能

Heuristic AI・Wrestler固有AI・damage評価・PIN/FINISHER重み付け・Counter価値評価・REST判断AI・
Simulator batch処理・win rate集計・analytics・CSV/JSON export・UI・balance
tuningはPhase 11Bのスコープ外（Phase 12以降）。

## 2. レイヤー構成と責務分離

```
CombatV1LegalAction
        ↓
CombatV1LegalActionEnumerator
        ↓
CombatV1DecisionPolicy
        ↓
CombatV1ActionExecutor
        ↓
CombatV1CpuMatchRunner（+ 任意でCombatV1ActionObserver）
```

各層の責務は明確に分離し、混ぜない:

| 層 | 責務 | 責務でないもの |
|---|---|---|
| `CombatV1LegalAction` | 「今この瞬間に合法な1手」の宣言的データ | legality判定・Engine呼び出し・random |
| `CombatV1LegalActionEnumerator` | `CombatV1MatchState`から合法手を全列挙 | 手の選択・独自ルール実装 |
| `CombatV1DecisionPolicy` | 合法手から1手を選ぶ | legality判定・Engine呼び出し |
| `CombatV1ActionExecutor` | `CombatV1LegalAction`→Engine Commandの薄いmapping | Engineルールの再実装 |
| `CombatV1CpuMatchRunner` | 上記4層を1試合分、boundedに回す | batch simulation・analytics |

Core Engine（`combat_v1_engine.dart`）はPhase 11Bで変更していない。CPU基盤はEngineを利用する
application/CPU層として実装した。

## 3. CombatV1LegalAction

sealed class（`combat_v1_legal_action.dart`）。variantは8種類:

- `CombatV1DiscardAction`（discardフェーズ専用）
- `CombatV1TechniqueAction`
- `CombatV1CounterAction`
- `CombatV1DeclineCounterAction`
- `CombatV1PinAction`（通常PINのみ。DIRECT PINはEngine自動処理のためvariant化しない）
- `CombatV1RestAction`
- `CombatV1StandUpAction`
- `CombatV1EndTurnAction`

directPin/submit/giveUp/escape/finisher resolutionはvariantとして追加しない——これらはEngine
内部（`declineCounter`の内部処理）で自動的に解決され、外部から選択可能な「手」として存在しない
（docs/combat_rules_v1.md 8・10・13章）。

### actorPlayerIndex

`state.activePlayerIndex`をそのままActionのactorとして使い回さない。`counterResponsePending`中は
`activePlayerIndex`が攻撃側のまま変化しない（docs/combat_rules_v1.md 7.1章）ため、
`CombatV1CounterAction`/`CombatV1DeclineCounterAction`のactorPlayerIndexは常に防御側
（`pendingAttack.defenderPlayerIndex`、実質的に`1 - activePlayerIndex`）になる。それ以外の
variantのactorは`state.activePlayerIndex`。

### physical instanceId

カードを使うAction（discard/technique/counter）は必ず`cardInstanceId`（`CombatV1DeckEntry.instanceId`）
を持つ。cardId（カード定義identity）ではなく、同名カードを区別できる物理instanceを常に指定する。

Actionは`CombatV1MatchState`/Catalog/Rules/Randomを一切保持しない。「宣言時点の意図」のみを表す
軽量な値であり、古いstateから生成したActionを新しいstateへ適用した場合の扱いは
`CombatV1ActionExecutor`の責務（stale action検出、6章参照）とする。

### Action Identity（Phase 12向け構造的識別）

`CombatV1LegalActionKind`（`discard`/`technique`/`counter`/`declineCounter`/`pin`/`rest`/
`standUp`/`endTurn`）を各Actionの`kind`getterとして公開する。Phase 12・
`CombatV1ActionObserver`がsealed patternに依存せず、構造的にAction種別を識別できるようにする
ための安定したidentity。カードを使わないActionの`cardInstanceId`は`null`を返す（基底classの
既定実装）。

## 4. CombatV1LegalActionEnumerator

入力: `CombatV1MatchState` / `CombatV1CardCatalog` / `CombatV1RulesConfig`。
出力: `List<CombatV1LegalAction>`。

原則: 「CPUが合法性を判断する」のではなく、可能な限り既存Engine legality API
（`checkTechniqueLegality`/`checkCounterLegality`/`checkPinLegality`/`checkStandUpLegality`/
`checkRestLegality`）へ委譲する。FINISHER HEAT gate・ENERGY支払い・posture条件・ROUGH制限・
Counter family/group matching・PIN条件・SUBMISSION・DIRECT PINといったルールはEnumerator側で
再実装しない。

`discardCard`/`declineCounter`/`endTurn`にはPhase 11B時点でpublic legality APIが存在しない
（既知の制約、7章参照）。これらについては、対応するCommand自身が要求する最小限のprecondition
（`phase`・`posture`等、Command本体のガード節と同じ条件）のみをEnumerator側で扱うことを本
Phaseでは許容している。

### phase別列挙

| phase / posture | 列挙されるAction |
|---|---|
| `discard` | active playerのhand全物理instanceの`CombatV1DiscardAction` |
| `action` / STAND | legal `CombatV1TechniqueAction`全件 + legal `CombatV1PinAction`（あれば） + `CombatV1EndTurnAction` |
| `action` / DOWN | legal `CombatV1StandUpAction`（あれば） + legal `CombatV1RestAction`（あれば）。Technique/PIN/endTurnは列挙しない |
| `counterResponsePending` | 防御側handのlegal `CombatV1CounterAction`全件 + 必ず1件の`CombatV1DeclineCounterAction` |
| `state.isOver == true` | 空List |
| `setup`/`turnEnd` | `CombatV1IllegalActionException`（Engineが外部へ返すことのない内部限定フェーズのため） |

### 空Listの扱い

正常な非terminal stateで空Listが返ることは想定しない（discardフェーズでhandが0枚等の異常
stateを除く）。Enumerator自身はsilentにCPU終了の合図として空Listを返すだけで、それを診断する
のは呼び出し側（`CombatV1CpuMatchRunner`）の責務——`CombatV1CpuMatchTermination.invariantViolation`
として明確なfailureにする（8章参照）。

### completeness / soundness

Enumeratorが返した全Actionを同じstateで`CombatV1ActionExecutor`へ渡した際、
`CombatV1IllegalActionException`が出ないことをtestで保証している
（`combat_v1_legal_action_enumerator_test.dart`の`_expectAllExecutable`）。「列挙したが実行
できない」を構造的に防ぐ。

## 5. CombatV1DecisionPolicy

```dart
abstract interface class CombatV1DecisionPolicy {
  String get id;
  CombatV1LegalAction choose(
    CombatV1MatchState state,
    List<CombatV1LegalAction> legalActions,
  );
}
```

`legalActions`が空の場合はfail-fast（`CombatV1IllegalActionException`）。`id`は安定した文字列
（`firstLegal`/`randomLegal`）とし、Phase 12・将来のheuristic policyが同じSimulator APIで
policyを識別できるようにする。

### CombatV1FirstLegalPolicy（deterministic baseline）

「自然なCPU」「強いCPU」ではなく、明確なテスト用baselineとして実装する。優先順位を固定する:

1. PIN
2. Counter
3. declineCounter
4. standUp
5. Technique
6. REST
7. endTurn
8. discard

phase上存在しないAction typeは無視する。List入力順には依存しない。同じAction type内では
`cardInstanceId`昇順でdeterministicに選ぶ——これによりProduction definition順（＝物理カード
生成順）のbiasが発生することを許容し、doc/testで明示する。このbiasを直すためのHeuristicは
実装しない。

以下は仕様上許容される（CPU品質評価用ではなく決定論的baselineであるため）:

- Counterがあれば必ずCounterする
- DOWNならRESTよりstandUpを優先する
- FINISHERを特別優先しない
- Technique内でinstanceId順biasがある

### CombatV1RandomLegalPolicy（type-first random）

物理LegalAction全件から一様randomは採用しない（手札枚数が多いAction typeほど選ばれやすくなる
biasを避けるため）。2段階方式を採用する:

1. 現在存在するAction Kind（`CombatV1LegalActionKind`）を一様randomで1つ選択する
2. 選択したkind内のActionから一様randomで1つ選択する

例: Technique 8枚・PIN 1件・endTurn 1件が列挙された場合、Technique type/PIN/endTurnはそれぞれ
1/3の確率で選ばれ、Technique typeが選ばれた後に8枚から1枚を一様randomで選ぶ。Counter 3件+
decline 1件の場合も同様、Counter typeが1/2、decline単体で1/2——カード枚数そのものがCounter率
等を過剰に上げない設計とする。

kind selectionはcanonical順（`discard`/`technique`/`counter`/`declineCounter`/`pin`/`rest`/
`standUp`/`endTurn`固定順）で現在存在するkindを抽出し、その配列へ`nextInt`でインデックスする
——同じ`legalActions`集合・同じRandom sequenceに対して常に同じ選択列を返す。

### Random注入

Policy内部で`Random()`を新規生成しない。constructorまたは明示dependencyとしてRandomを受け取る
（`CombatV1RandomLegalPolicy(Random decisionRandom)`）。これにより同seedで同じ選択sequenceを
再現できる。

## 6. RNG分離（decision RNG / engine RNG）

CPU decision用RandomとEngine resolution用Randomを分離する。最低限、以下の3本を独立して注入
できる構造にした:

- `engineRandom`（`CombatV1CpuMatchRunner.run`の引数。shuffle/draw/PIN/COUNTER解決などEngine
  Command専用）
- playerAのpolicy random（`CombatV1RandomLegalPolicy`のconstructor引数として、呼び出し側が
  playerA用に生成）
- playerBのpolicy random（同上、playerB用）

`CombatV1CpuMatchRunner`自身はpolicy用のRandomを一切生成・共有しない。Policyのrandom呼び出し
回数が増えても、shuffle・draw・PIN・COUNTER解決等のEngine RNG sequenceへ意図せず影響しない
（`CombatV1ActionExecutor.execute`にはpolicyのRandomを一切渡さない）。

Phase 11Bではmaster seed derivation system（1つのseedから3本のRandomを規則的に導出する仕組み）
までは実装しない。Phase 12が個別のRandomインスタンスを生成して注入できれば十分という位置付け。

`combat_v1_cpu_match_runner_test.dart`のRNG分離テストでは、playerAの最初の意思決定が
playerBのRandom seedへ依存しないこと、reshuffleが発生しない短いbounded runの範囲で
`engineRandom`のseedを変えてもpolicy選択列・finalStateが変化しないことを確認している
（真の統計的独立性の網羅的証明ではなく、配線が誤って共有・混線していないことの実用的な検証）。

## 7. CombatV1ActionExecutor

`CombatV1LegalAction`を既存Engine Commandへ変換する薄いlayer。責務はaction variant
dispatch・actor一致検証・Engine command呼び出し・Catalog/rules/random受け渡しのみ。Engine
ルールの再実装はしない。

### mapping

| LegalAction | Engine Command |
|---|---|
| `CombatV1DiscardAction` | `CombatV1Engine.discardCard` |
| `CombatV1TechniqueAction` | `CombatV1Engine.declareTechnique` |
| `CombatV1CounterAction` | `CombatV1Engine.playCounter` |
| `CombatV1DeclineCounterAction` | `CombatV1Engine.declineCounter` |
| `CombatV1PinAction` | `CombatV1Engine.declarePin` |
| `CombatV1RestAction` | `CombatV1Engine.rest` |
| `CombatV1StandUpAction` | `CombatV1Engine.standUp` |
| `CombatV1EndTurnAction` | `CombatV1Engine.endTurn` |

### actor検証とstale action

`action.actorPlayerIndex`が`state`から導出される期待actor（COUNTER/declineCounterなら
`1 - state.activePlayerIndex`、それ以外なら`state.activePlayerIndex`）と一致しない場合、Engine
呼び出し前に`CombatV1IllegalActionException`をfail-fastで送出する。

正常フローは常に「同じimmutable stateからenumerate → choose → execute」。古いstateから生成した
Actionを新しいstateへ適用してEngineが拒否した場合も、recoverable CPU failureとして握り潰さず、
programming/application misuseとしてfail-fastする（Engine自身のlegality再検証が最終防衛線に
なる）。

## 8. CombatV1CpuMatchRunner

bounded single CPU vs CPU matchを進行させるrunner。batch simulation・statistics・analytics・
exportはPhase 12へ回す。

### maxActions

既定500。ゲームルールのturn limit/draw条件ではなく、runner safety guard。
`CombatV1ActionExecutor.execute`成功後にのみカウントする。以下は1 actionとしてカウントする:

- discard / declareTechnique / playCounter / declineCounter / declarePin / rest / standUp /
  endTurn（8種のみ）

Engine内部で自動的に行われるdirect PIN resolution・submission resolution・draw・shuffle・
posture update・turn transitionは追加actionとしてカウントしない（例:
`fx_normal_direct_pin`のようなDIRECT PIN技は「declareTechnique」+「declineCounter（内部でPIN
自動解決）」の2 actionで完結し、PIN自体は3件目としてカウントされない。
`combat_v1_cpu_match_runner_test.dart`「C. automatic directPin resolution」参照）。

### termination

`CombatV1CpuMatchTermination`で3種を構造的に区別する:

- `matchOver`: Engineでwinnerが確定した正常終了（`CombatV1MatchState.isOver`）。
- `safetyLimit`: ゲームは未終了だが`maxActions`へ到達。winnerを捏造しない・draw扱いにもしない・
  Engine stateも書き換えない（到達した時点のstateをそのまま返すのみ）。
- `invariantViolation`: state invariant違反、または非terminal stateでlegal actionが0件
  （programming/invariant上の異常）。

### terminal cause（Terminal Metadata）

`termination == matchOver`の場合のみ、`CombatV1CpuMatchTerminalCause`
（`normalPin`/`directPin`/`submission`/`submissionFinisher`/`other`）を付与する。

`CombatV1MatchState.isOver`になる経路はEngine実装上、以下の2つのみである
（`combat_v1_engine.dart`の`_resolvePendingAttack`/`declarePin`参照）:

1. `CombatV1PinAction`（`declarePin`、通常PIN）の3カウント
2. `CombatV1DeclineCounterAction`（`declineCounter`）の内部で自動解決されるDIRECT
   PIN／SUBMISSIONのGIVE UP

前者は無条件に`normalPin`。後者は、declineCounter実行直前の`stateBefore.pendingAttack`が
保持する**公開field**（`category`/`finisherType`/`directPin`/`submissionHold`）だけから、
`_resolvePendingAttack`のeffectiveDirectPin/effectiveSubmissionHold導出と同じロジックで
`directPin`/`submission`/`submissionFinisher`を判定する。`CombatV1PendingAttack`のこれらの
fieldはいずれも既にpublicであるため、Core Engineの変更やprivate stateへのアクセスを一切必要と
しない——Engine内部実装の複製ではなく、既に公開されている宣言時点スナップショットの読み取りの
みで完結する分類である。

`CombatV1TechniqueAction`（Technique宣言そのもの）・`CombatV1CounterAction`（COUNTER成立、
攻撃は無効化されるため）・`CombatV1RestAction`/`CombatV1StandUpAction`/`CombatV1EndTurnAction`/
`CombatV1DiscardAction`は、単独でmatchを終了させることがない（それぞれのEngine Command実装が
`winnerPlayerIndex`を更新する経路を持たない）ため、`_classifyTerminalCause`の対象外。

`CombatV1FinisherType.normal`のFINISHER成功は、それ自体では自動決着しない
（docs/combat_rules_v1.md 13章「成功しても自動PINしない」）。その後に攻撃側が任意で
`declarePin`を呼んで決着した場合は`normalPin`として分類され、「FINISHER technique
success」と「terminal PIN」は別概念のまま区別される（FINISHER成功自体をterminal causeとして
扱うことはない）。

### invariant validation

`validateMatchStateInvariants`を以下の3箇所で実行する（性能より正しさを優先するPhase 11Bの
方針。Phase 12でパフォーマンス最適化を検討する余地は残す）:

1. `initialState`に対して開始直後
2. 各`CombatV1ActionExecutor.execute`成功後
3. result返却直前（`_buildResult`。既に`invariantViolation`が確定している場合は二重検証しない）

いずれかで不整合が見つかった場合、`safetyLimit`/`matchOver`ではなく必ず`invariantViolation`
として返す。

### 非terminal stateでlegal action 0件

match未終了なのに`CombatV1LegalActionEnumerator.enumerate`の結果が空Listの場合、CPUが
何もしないまま黙って続行することはない。`safetyLimit`でも正常終了でもなく、明示的に
`invariantViolation`として返す。

### Structured Action Observation

`CombatV1ActionObserver`（`combat_v1_action_observer.dart`）はoptionalなextension
point。渡された場合、成功した各public actionについて`onActionResolved`を呼び出し、
`CombatV1ActionObservation`（`actionIndex`/`turnNumber`/`actorPlayerIndex`/`action`/
`stateBefore`/`stateAfter`）を通知する。Phase 11B自身はobservationを一切蓄積・分析しない
——Phase 12（Simulator）がcollectorを差し込むための構造だけを用意する。observerを渡さなくても
runnerは正常動作する。

Counter response時の「Counter available and used」「Counter available but declined」
「no Counter available（forced decline）」の区別は、Phase 11B側で集計しない。Phase 12が
`stateBefore`に対して`CombatV1LegalActionEnumerator.enumerate`を再実行すれば、その時点の
legal Counter一覧と実際に選ばれたActionを突き合わせて再構築できるため、observationへ
legal action一覧を複製する必要はない。

### CombatV1CpuMatchResult

Phase 12が再利用しやすい最小限の形にする（analytics項目は増やしすぎない）:

- `finalState` / `actionCount` / `finalTurnNumber` / `termination` / `maxActions`
- `policyAId` / `policyBId`
- `lastAction`（1件もactionが成功しなかった場合は`null`）
- `terminalCause`（`termination == matchOver`の場合のみ非null）
- `invariantViolationMessage`（`termination == invariantViolation`の場合のみ非null）
- 派生getter: `hasWinner` / `lastPhase` / `lastActivePlayerIndex` / `hasPendingAttack`

## 9. deck exhaustionはEngine責務

CPU Runner側でdeck exhaustionの独自処理は行わない。Engineのdiscard recycle・shuffle・draw・
draw no-opへ完全委譲する。deck empty loss・fatigue・drawといった新ルールをrunner側で追加する
ことはない（docs/combat_rules_v1.md 16章）。

## 10. Production Match Setupとの関係

Production CPU integration test（`combat_v1_cpu_production_integration_test.dart`）では
Phase 11Aの`CombatV1ProductionMatchStarter.start`を正式な試合開始入口として利用する。

ただし`CombatV1LegalActionEnumerator`/`CombatV1DecisionPolicy`/`CombatV1ActionExecutor`/
`CombatV1CpuMatchRunner`自体はProduction Match Starter内部へ強結合させていない
——`CombatV1CpuMatchRunner`は`initialState`・`catalog`・`rules`・engine用`Random`・両playerの
`CombatV1DecisionPolicy`を受け取って動作する汎用runnerであり、Production固有の初期化経路を
知らない。

## 11. Phase 12との境界

Phase 11Bに含めなかったもの（Phase 12以降のスコープ）:

- 4×4等のbatch simulation・win rate・matchup aggregation・statistics（median/p95等）
- CSV/JSON simulation export
- balance warnings・Technique/Counter/REST/HEAT aggregate analytics
- dashboard・replay UI
- Heuristic AI・Wrestler固有AI・damage評価・PIN/FINISHER重み付け・Counter価値評価・REST判断AI
- Core Engineの大規模event system

Phase 11Bは、これらをPhase 12が構築するための土台（Legal Action model・Enumerator・Policy
interface・Executor・bounded Runner・Action Observer extension point）のみを提供する。
