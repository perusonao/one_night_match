# Combat Ver.1 — Playable Match UI 設計文書（Playable 1A / 1B 共通SSOT）

- ステータス: Playable 1A（Interactive Controller / Session）実装。
  Balance Dashboard 1A（`d473f709430d325aa67394111fd0b6d5e11a2e22`、merge済み）の
  public APIのみを利用し、Core Engine・Phase 11A/11B・Phase 12A/12B-1/12B-2A・
  Balance Dashboardは一切変更しない（`combat_v1_cpu_match_runner.dart`の
  内部実装をPlayable 1Aと共通のlifecycle helperへ抽出するrefactorのみ例外、
  6章参照）。
- 関連: [`combat_v1_phase11a_production_match_setup.md`](combat_v1_phase11a_production_match_setup.md) /
  [`combat_v1_phase11b_cpu.md`](combat_v1_phase11b_cpu.md) /
  [`combat_v1_phase12a_simulation_core.md`](combat_v1_phase12a_simulation_core.md) /
  [`combat_v1_balance_dashboard_1a.md`](combat_v1_balance_dashboard_1a.md)
- 実装:
  `lib/src/combat_v1/combat_v1_match_lifecycle.dart`（CPU
  runner／Playable共有のterminal cause分類・統合invariant検証helper）/
  `lib/src/combat_v1/playable/combat_v1_playable_match_config.dart` /
  `lib/src/combat_v1/playable/combat_v1_playable_match_snapshot.dart` /
  `lib/src/combat_v1/playable/combat_v1_playable_match_result.dart` /
  `lib/src/combat_v1/playable/combat_v1_playable_match_controller.dart`
- テスト: `test/combat_v1/playable/`配下（10章参照）。

---

## 1. Purpose（目的）

Flutter UI（Playable Match画面）を作る**前**に、Human（Player A）vs CPU
（Player B）の1試合を、既存Combat Ver.1 Engineの境界（Phase 11A Production
Match Setup・Phase 11B Legal Action / Executor / Decision Policy）だけを
再利用して、安全にstep-wise進行できる**UI非依存のcontroller/session層**を
完成させる。

「安全に」とは:

- Core Engineのルール（legality・damage・PIN/SUBMISSION resolution）を
  一切再実装しない
- Human/CPUどちらの「今の手番」も、`activePlayerIndex`の生値ではなく
  legal actionの実際のactorから導出する（Counterの防御側逆転を含む）
- Widgetへ渡す情報は常にhidden-safe（CPU手札の中身を一切含まない）
- stale action（古いUI stateから送信されたaction）をrevisionで検出し拒否する
- Engine RNGを試合を通じて単一instanceで継続させる

## 2. Phase Split（Playable 1A / 1B）

| Phase | 範囲 |
| --- | --- |
| Playable 1A（本ドキュメント対象） | Interactive Controller / Session（pure Dart、Flutter非依存）。Human A vs CPU Bの1試合をstep-wiseに進行できる状態にする。 |
| Playable 1B（未着手） | Playable 1A controllerを消費するFlutter Match画面・wrestler selection UI・card UI・result overlay・animation。 |

Playable 1Aで確定した`CombatV1PlayableMatchConfig`/
`CombatV1PlayableMatchController`/`CombatV1PlayableMatchSnapshot`/
`CombatV1PlayableMatchResult`のpublic API surfaceが、Playable 1Bの入力
契約になる。

## 3. Scope / Non-Scope

### Scope（今回実装するもの）

- Interactive Match Config（`CombatV1PlayableMatchConfig`）
- Interactive Match Controller / Session（`CombatV1PlayableMatchController`）
- Human action submission（stale-safe）
- CPU auto progression（1step API + until-human convenience API）
- Counter actor handling（defenderがHumanの場合に自動進行を止める）
- RNG continuity（Engine RNG単一instance・CPU Policy RNGとの分離）
- hidden-safe snapshot/projection
- 構造化されたtermination/result
- lifecycle/invariant共有helper（CPU runnerとの重複最小化）
- controller test群

### Non-Scope（今回実装しないもの、Playable 1Bへ先送り）

- Flutter Match画面・wrestler selection UI・card UI・result overlay・animation
- Title画面からの導線
- Balance Dashboard関連の変更
- Phase 12B-2B/2Cの実装
- Core Engineのルール変更・legality再実装・RNG消費順の変更

## 4. Human / CPU Seat

Playable 1Aでは固定:

- Human: Player A / `playerIndex == 0`
- CPU: Player B / `playerIndex == 1`
- CPU policy: `CombatV1RandomLegalPolicy`（既定。testでは
  `CombatV1FirstLegalPolicy`も選択可能、9章参照）

`CombatV1PlayableMatchController`は`humanPlayerIndex`/`cpuPlayerIndex`という
named constantを内部で使い、生の`0`/`1`リテラルを各所へ直接埋め込まない
——将来Human Bへ拡張する場合、この2定数を書き換える範囲を狭く保つための
最小限の配慮に留める（Playable 1AでHuman B対応そのものは実装しない、UI
selectorも今回不要）。

## 5. Reuse Existing Engine（再利用する既存境界）

Playable 1Aが直接呼び出すのは以下のみ:

- `CombatV1ProductionMatchStarter.start`
- `CombatV1LegalActionEnumerator.enumerate`
- `CombatV1LegalAction`（8 variant）
- `CombatV1ActionExecutor.execute`
- `CombatV1DecisionPolicy`（`CombatV1FirstLegalPolicy`/
  `CombatV1RandomLegalPolicy`）
- `productionCardCatalog`（`combatV1ProductionWrestlerRegistry`経由）
- `validateMatchStateInvariants`/`validatePlayerStateInvariants`
  （`CombatV1MatchLifecycle`経由）

technique/counter/PIN/REST/StandUp legality・damage計算・submission/PIN
resolutionはいずれもPlayable層で再実装しない。

## 6. Shared Lifecycle Helper（CPU runnerとの重複最小化）

`CombatV1CpuMatchRunner`（Phase 11B）は「統合invariant検証」
（`_validateRunnerInvariants`）と「terminal cause分類」
（`_classifyTerminalCause`）を独自private実装として持っていた。Playable
controllerも全く同じ2つの診断を必要とするため、両ロジックを
`lib/src/combat_v1/combat_v1_match_lifecycle.dart`の
`CombatV1MatchLifecycle`（static utility）へ抽出した:

- `CombatV1MatchLifecycle.validateIntegratedInvariants(state, rules: rules)`
  — `validateMatchStateInvariants` + 両playerの
  `validatePlayerStateInvariants` + `activePlayerIndex`範囲チェックを
  統合し、結合したメッセージ（`String?`）を返す。CPU runnerの
  `_validateRunnerInvariants`と完全に同じロジック・同じメッセージ文言。
- `CombatV1MatchLifecycle.classifyTerminalCause(...)` — CPU runnerの
  `_classifyTerminalCause`と完全に同じmapping（10パターン）。

`CombatV1CpuMatchRunner`側の変更は以下の2点のみ（**振る舞い・出力は一切
変更しない**）:

1. `CombatV1CpuMatchTerminalCause`を独自enumから
   `typedef CombatV1CpuMatchTerminalCause = CombatV1MatchTerminalCause;`
   （完全なalias）へ変更。既存のimport・型参照・switch文（Simulation層・
   Batch層・既存test）はすべて変更不要。
2. `_validateRunnerInvariants`/`_classifyTerminalCause`のメソッド本体を、
   上記の共有helper呼び出しへ差し替え（メソッド自体はprivateのまま残し、
   `run`側の呼び出し箇所は無変更）。

`CombatV1CpuMatchTermination`（`matchOver`/`safetyLimit`/
`invariantViolation`）はCPU runner固有のenumのまま変更しない——Playable
controllerは「Human入力待ち」という、CPU runnerには存在しない追加の
定常状態を持つため、terminationの語彙はPlayable側で独自に定義する
（17章）。CPU runner既存test（`combat_v1_cpu_match_runner_test.dart`・
`combat_v1_cpu_terminal_cause_test.dart`）は本refactor後も無変更のまま
全passすることを確認済み（12章）。

## 7. Controller Architecture / State Ownership

`CombatV1PlayableMatchController`は次のprivate stateのみを保持する
single-owner・plain Dart classとして設計する:

- `CombatV1MatchState _state`（唯一のsource of truth。直接Widgetへ渡さない）
- `Random _engineRandom`（Engine Command専用、11章）
- `CombatV1DecisionPolicy _cpuPolicy`（CPU decision専用、12章）
- `int _revision`（15章）
- `int _actionCount`
- `List<CombatV1LegalAction> _legalActions`（直近enumerate結果）
- `int? _currentActor`（8章参照。非terminalなら常に0/1、terminal/error時は
  `null`）
- `CombatV1PlayableControllerStatus _status`（17章）
- `String? _diagnosticMessage`（error/invariantViolation時のみ非null）
- `CombatV1MatchTerminalCause? _terminalCause`
- `CombatV1LegalAction? _lastAction`・`CombatV1MatchState? _stateBeforeLastAction`
  （terminal cause分類専用）
- `List<CombatV1PlayableObservation> _recentObservations`（bounded、13章）

Widget/呼び出し側は`_state`へ直接アクセスできない——常に
`controller.snapshot`（hidden-safeなprojection）を介して読み取る（9章）。

## 8. Actor Semantics（現在のactor解決）

`state.activePlayerIndex`だけでHuman/CPUの手番を判定しない
（`counterResponsePending`中は`activePlayerIndex`が攻撃側のまま変化しない
ため）。正本は次の手順で導出する:

1. `CombatV1LegalActionEnumerator.enumerate(state, ...)`で現在の
   legal actionsを列挙する。
2. 非emptyなら、全legal actionの`actorPlayerIndex`が一致することを
   validateする。
3. 一致すればそのplayerIndexを`_currentActor`とする。

Counter応答時は`CombatV1LegalActionEnumerator`が`pendingAttack.
defenderPlayerIndex`から`actorPlayerIndex`を導出するため
（`combat_v1_legal_action_enumerator.dart`）、CPU attackerからのCounter
promptでは`_currentActor`が自動的にHumanへ切り替わる——
`state.activePlayerIndex`はCPUのままでも、controllerの`_currentActor`は
Humanになる（14章）。

非terminalなのに`legalActions`が0件、またはactor不一致の場合は
`CombatV1PlayableControllerStatus.invariantViolation`として停止する
（CPU runnerと同じ方針、EndTurnをfabricateしない）。

## 9. Legal Action Snapshot

state変化のたびに一度だけenumerateし、結果を`_legalActions`/
`_currentActor`として保持する。`CombatV1PlayableMatchSnapshot.legalActions`
はこの結果を**Humanの手番の場合のみ**そのまま公開する:

```
legalActions = (status == active && currentActor == humanPlayerIndex)
    ? List.unmodifiable(_legalActions)
    : const []
```

CPUの手番中に`legalActions`を公開しないのは、Technique/Counter/Discard
Actionが`cardInstanceId`（CPU手札の物理カードID）を保持しており、それを
そのまま公開するとCPU手札の中身が漏洩するため（14章のhidden information
要件と直結する設計判断）。

## 10. RNG Continuity（Engine RNG）

controller構築時に一度だけ:

```dart
final engineRandom = Random(config.engineSeed);
```

を生成し、`CombatV1ProductionMatchStarter.start(..., random: engineRandom)`
（初期shuffle・初期手札配布）から、以後すべての
`CombatV1ActionExecutor.execute(..., random: engineRandom)`まで、**同一
instance**を試合終了まで使い回す。途中で`Random(engineSeed)`を再生成する
ことは一切ない。Widget rebuildが将来発生してもcontroller instance自体が
再生成されない限りRandom streamは継続する（controllerがFlutter
非依存のplain Dart classであること自体がこの継続性を構造的に保証する、
15章）。

## 11. CPU Policy RNG（分離）

```dart
final cpuPolicyRandom = Random(config.cpuPolicySeed);
final cpuPolicy = config.cpuPolicyKind.createFresh(cpuPolicyRandom);
```

Engine RNGとは常に別instance。CPU policy instanceもcontroller構築時に
一度だけ生成し、試合を通じて使い回す（policy自身が新規`Random()`を生成
しないことは`CombatV1RandomLegalPolicy`のPhase 11B契約のまま）。Human側の
decision用Randomは存在しない（Humanは常に明示的なaction送信）。

## 12. CPU Policy Injection

`CombatV1PlayableMatchConfig.cpuPolicyKind`は
`CombatV1PlayableCpuPolicyKind`という閉じたenum（`firstLegal`/
`randomLegal`）——Phase 12Aの`CombatV1SimulationPolicyKind`と同じ設計
思想（Codex review Major Finding M1相当の理由: 任意factory closureを
public configへ注入できないようにする）。Simulation層の
`CombatV1SimulationPolicyKind`は再利用しない——PlayableパッケージがSimulation
パッケージへ依存する向きの結合を避けるため、Playable専用の同型enumを
独立して定義する。production既定値は`randomLegal`（4章の固定要件）。
testでは`firstLegal`（deterministic baseline）を使う。scripted/custom
policyが必要なtestはtest code側で直接`CombatV1DecisionPolicy`を実装し、
public configへ任意factoryを再導入することはしない。

## 13. CPU Auto Progression / Counter Flow

`submitHumanAction`はHumanのactionを実行・settleするところまでで完結し、
CPU actionへの自動連鎖は**行わない**——実行後`_currentActor ==
cpuPlayerIndex`になった場合（`snapshot.isHumanInputRequired == false`）、
CPU進行は呼び出し側が明示的に`advanceCpuOneAction()`/
`advanceCpuUntilHumanInput()`を呼ぶことで行う（20章「CPU one-step API +
convenience loop」。Playable 1BがCPU 1手ごとにpresentation delayを挟める
よう、`submitHumanAction`自身はCPU進行を隠蔽・自動化しない設計とした）。

`advanceCpuUntilHumanInput()`は次のループを、`_currentActor ==
humanPlayerIndex`になる、またはterminal/safety limit/invariant
violationに達するまで回す:

```
enumerate → policy.choose → execute → invariant validate
  → observe → revision++ → re-enumerate → actor再判定
```

1 CPU actionで止まらない——CPU Technique宣言 → CPU/Human Counter phase →
action phase continuationのように複数actionを連続して進める。ただし
Human防御側のCounter promptになった時点（`_currentActor`がHumanへ
切り替わった時点）で直ちに停止する（8章のactor解決に従う自然な帰結）。
`advanceCpuOneAction()`は同じ内部step（1回分の
enumerate→choose→execute→...→再enumerate）をちょうど1回だけ実行する
——`advanceCpuUntilHumanInput()`はこの1 stepを内部でループしているだけの
convenience wrapper。

## 14. Stale-Action Handling

Engine state自体にrevisionフィールドは無いため、controller独自の
monotonic `int _revision`を持つ（`0`始まり、成功したpublic actionごとに
`+1`）。

```dart
CombatV1PlayableSubmitResult submitHumanAction({
  required int expectedRevision,
  required CombatV1LegalAction action,
});
```

`expectedRevision != _revision`の場合、`CombatV1ActionExecutor`を一切
呼び出さずreject（`CombatV1PlayableSubmitOutcome.rejectedStaleRevision`）
する——state・revisionとも変更しない。UIが再描画可能なrecoverable case
として区別できるよう、例外ではなく`CombatV1PlayableSubmitResult`の
`outcome`フィールドで表現する。

## 15. Human Action Validation / Execution

`submitHumanAction`は以下を**すべて**満たすactionのみ受理する:

1. `status == active`（そうでなければ`rejectedNotReady`）
2. `_currentActor == humanPlayerIndex`（そうでなければ`rejectedWrongActor`）
3. `action.actorPlayerIndex == humanPlayerIndex`（`rejectedWrongActor`）
4. `expectedRevision == _revision`（`rejectedStaleRevision`）
5. `_legalActions`に`action`が値として完全一致で含まれる
   （`rejectedIllegalAction`）——`CombatV1LegalAction`各variantの`==`は
   `actorPlayerIndex`＋`cardInstanceId`（該当する場合）の値比較のため、
   `cardInstanceId`によるphysical card identityでmatchする（同名複数
   physical cardに対応、cardName/cardId/technique nameをcommand identity
   として使わない）。

すべて満たした場合のみ`CombatV1ActionExecutor.execute`を呼び出し、成功後
に統合invariant validate → observation記録 → `_revision++`・
`_actionCount++` → 再enumerate、を行う。terminalならcontroller状態を
`matchOver`へ。非terminalでCPU actorになった場合も`submitHumanAction`
自体はそのまま結果（`isHumanInputRequired == false`な最新snapshot）を
返す——CPU progressionの実行は呼び出し側の次のステップ（13章）。

Executorが例外を送出した場合（snapshot由来のactionのみ受理するため通常
到達しないが、防御的に捕捉する）、controllerを`error`状態にし、
state/seed/action/revisionを含む診断メッセージを`diagnosticMessage`へ
保持する。自動retryは行わない。

## 16. Hidden Information / Viewer Projection

`CombatV1PlayableMatchSnapshot`はWidgetへ渡してよい情報のみを持つ。

**Human status**（`CombatV1PlayableHumanStatus`）: wrestler id/name・
HP/maxHP・KOC・posture・hand（`CombatV1PlayableHandCard`のList、
`cardInstanceId`/`cardId`/`displayName`/`category`/technique or counter
定義・`isUsable`）・hand count・draw/discard pile count・pin cards
held・reshuffle count。

**CPU status**（`CombatV1PlayableOpponentStatus`）: wrestler id/name・
HP/maxHP・KOC・posture・hand **count**・draw/discard pile count・pin
cards held・reshuffle countのみ。**CPU手札の`cardInstanceId`・`cardId`・
カード名・draw pileの中身・現在利用可能なCPU counterは一切含まない**。

**Pending attack**（`CombatV1PlayablePendingAttackView`、Counter UI用）:
`attackerPlayerIndex`/`defenderPlayerIndex`/攻撃card id・display
name・category・attribute・family・damage・result posture。宣言済みの
攻撃カードは既に公開情報（両者に見えている）であるため、これらの投影は
hidden information違反にならない。

`legalActions`は9章の通りHumanの手番の場合のみ公開する。
`recentObservations`（`CombatV1PlayableObservation`）はraw
`CombatV1MatchState`を保持しない——`actionIndex`/`turnNumber`/
`actorPlayerIndex`/実行された`CombatV1LegalAction`のみを保持する
（実行されたactionそのものは、宣言・discard・counter使用いずれも既に
「公開されたaction」であるため、これを見せることはhidden information
違反にならない）。

## 17. Termination / Controller Status

```dart
enum CombatV1PlayableControllerStatus {
  active,
  matchOver,
  safetyLimit,
  invariantViolation,
  error,
}
```

`runningCpu`のような追加statusは持たない——`advanceCpuOneAction`/
`advanceCpuUntilHumanInput`/`submitHumanAction`はいずれも同期処理で
呼び出し内に完結するため、呼び出しが返った時点で外部から観測できる
statusは常に上記5値のいずれかで確定する（"busy"な中間状態は外部から
観測不可能）。`matchOver`/`safetyLimit`/`invariantViolation`の3状態でのみ
`CombatV1PlayableMatchResult`（18章）を構築する。`error`は
`CombatV1ActionExecutor.execute`が予期せず例外を送出した場合専用で、
`diagnosticMessage`のみで表現する（19章）。

## 18. Match Result

`CombatV1PlayableMatchResult`は`status`が`matchOver`/`safetyLimit`/
`invariantViolation`のいずれかになった時点で1度だけ構築され、以後
`controller.result`から取得できる:

- `status`
- `terminalCause`（`status == matchOver`の場合のみ非null、
  `CombatV1MatchTerminalCause`をそのまま使う）
- `winnerPlayerIndex`/`winnerWrestlerId`（`status == matchOver`かつ
  勝者確定時のみ非null。safetyLimit/invariantViolationでは勝敗を
  fabricateせず常にnull）
- `actionCount`・`finalTurnNumber`・`safetyLimitReached`
- `invariantViolationMessage`（`status == invariantViolation`のみ非null）
- `finalHumanStatus`/`finalCpuStatus`（16章と同じhidden-safe projection、
  試合終了後もCPU手札は非公開のまま）
- `finalSharedHeat`・`finalPhase`・`finalActivePlayerIndex`
- seed metadata: `engineSeed`・`cpuPolicySeed`・`humanWrestlerId`・
  `cpuWrestlerId`・`maxActions`・`rules`

既存`CombatV1MatchSimulationResult`（Simulation層）はそのまま再利用しない
——`simulationMatchId`・owner audit・batch identityはPlayableに不要であり、
またSimulation packageへの依存方向を持ち込まないため（12章と同じ理由）。
`CombatV1MatchFinalStateSummary`も同様の理由で直接importせず、Playableは
`CombatV1PlayableHumanStatus`/`CombatV1PlayableOpponentStatus`（16章、
既にsnapshotで定義済みの型）をfinal resultでも再利用する——新規の
「3つ目のsummary型」を増やさないための設計判断。

## 19. Error Strategy

- 設定不正（未知wrestlerId・`maxActions <= 0`）は`CombatV1PlayableMatchConfig`
  のコンストラクタでfail-fast（`CombatV1IllegalActionException`を送出、
  Production Match Setupと同じ方針）。
- 未知wrestlerIdによる`CombatV1ProductionMatchStarter.start`失敗も同様に
  fail-fastで例外を伝播する（controller構築自体が失敗する——recoverableな
  runtime stateとして扱わない、programming errorのため）。
- 試合開始後の`CombatV1ActionExecutor.execute`失敗（本来到達しないはずの
  防御的ケース）は`CombatV1PlayableControllerStatus.error`として捕捉し、
  例外を外部へ再送出しない。
- invariant violation（開始直後・各action後）は`invariantViolation`
  statusとして捕捉する。
- stale revision・不正action送信（human turnでない／legal setに無い）は
  例外を投げず、`CombatV1PlayableSubmitResult.outcome`で表現する
  （14〜15章）。

## 20. Public Types（最小限）

- `CombatV1PlayableMatchConfig`
- `CombatV1PlayableCpuPolicyKind`
- `CombatV1PlayableMatchController`
- `CombatV1PlayableControllerStatus`
- `CombatV1PlayableSubmitOutcome` / `CombatV1PlayableSubmitResult`
- `CombatV1PlayableAdvanceResult`
- `CombatV1PlayableMatchSnapshot`
- `CombatV1PlayableHumanStatus` / `CombatV1PlayableOpponentStatus`
- `CombatV1PlayableHandCard`
- `CombatV1PlayablePendingAttackView`
- `CombatV1PlayableObservation`
- `CombatV1PlayableMatchResult`
- `CombatV1MatchLifecycle` / `CombatV1MatchTerminalCause`
  （`combat_v1_match_lifecycle.dart`、CPU runnerと共有）

UI presentation専用の型（アニメーション用item・カード演出metadata等）は
Playable 1Bまでprivate/internalのまま追加しない。

## 21. Tests

`test/combat_v1/playable/`配下、pure deterministic fixture中心
（production 4 wrestlerを使用）:

- start test（Human index 0・CPU index 1・initial legal actions・hidden
  safety）
- technique test（revision/actionCount増加・RNG continuity）
- counter tests（Human counter・Human decline・CPU counter・counter actor
  correctness）
- PIN test（Engine自動解決を通す、controller側で独自PIN logicを持たない
  ことを確認）
- REST / StandUp / EndTurn test
- stale revision test
- hidden information test（CPU手札instanceId/cardId/nameがsnapshot
  surfaceに存在しないことをdirect object inspectionで確認）
- RNG determinism test（同一config+同一human選択+同一CPU seedで同一結果）
- different seed test（RNG-dependent sequence identityの変化を固定、
  winner差をassertしない）
- safety limit test（低いmaxActionsで強制、winner非fabrication確認）
- invariant/no-legal test
- mirror test（同一wrestler同士）
- observation retention test（bound超過で古いものを破棄）
- integration full-match test（固定seed・deterministic policyで1試合完走）

## 22. Playable 1B Boundary

Playable 1Bが実装する範囲（本ドキュメントでは設計しない）:

- `CombatV1PlayableMatchController`を消費するFlutter `MatchScreen`
- wrestler selection UI（Title画面からの導線を含む）
- 手札・PIN・COUNTER・RESTなどのcard/action UI
- `advanceCpuOneAction`を使ったCPU 1手ごとのpresentation delay/animation
- result overlay（`CombatV1PlayableMatchResult`の表示）
- `CombatV1PlayablePendingAttackView`を使ったCounter prompt UI

## 23. Mobile UI Deferred Design Summary

Playable 1Aのcontroller APIは非同期を要求しない（CPU progressionは
delayなしで即座に完了する）。Playable 1Bで「CPU 1手ごとにdelayを入れて
見せる」演出を実現する場合は、`advanceCpuOneAction()`をUI側の
`Future.delayed`ループから呼び出す想定（20章の`CombatV1PlayableAdvanceResult.
actionsExecuted`でループ継続要否を判定できる）。`advanceCpuUntilHumanInput()`
はdelay演出が不要な場面（テスト・低スペック端末向けの即時進行オプション等）
向けのconvenience APIとして残す。Controller自体はTimer/Streamを一切
持たないplain Dart classであるため、Flutter側のwidget lifecycle（dispose
等）と結合しない——Playable 1Bはcontroller instanceの生成・破棄
タイミングを自由に設計できる。
