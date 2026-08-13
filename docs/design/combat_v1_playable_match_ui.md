# Combat Ver.1 — Playable Match UI 設計文書（Playable 1A / 1B 共通SSOT）

- ステータス: Playable 1A（Interactive Controller / Session）
  COMPLETE / MERGED。Playable 1B（Minimal Playable Match UI、24章以降）
  実装済み。いずれもBalance Dashboard 1A
  （`d473f709430d325aa67394111fd0b6d5e11a2e22`、merge済み）の
  public APIのみを利用し、Core Engine・Phase 11A/11B・Phase 12A/12B-1/12B-2A・
  Balance Dashboardは一切変更しない（`combat_v1_cpu_match_runner.dart`の
  内部実装をPlayable 1Aと共通のlifecycle helperへ抽出するrefactorのみ例外、
  6章参照）。Playable 1BはPlayable 1Aのpublic API（20章「Public Types」）を
  一切変更していない。
- 関連: [`combat_v1_phase11a_production_match_setup.md`](combat_v1_phase11a_production_match_setup.md) /
  [`combat_v1_phase11b_cpu.md`](combat_v1_phase11b_cpu.md) /
  [`combat_v1_phase12a_simulation_core.md`](combat_v1_phase12a_simulation_core.md) /
  [`combat_v1_balance_dashboard_1a.md`](combat_v1_balance_dashboard_1a.md)
- 実装（Playable 1A）:
  `lib/src/combat_v1/combat_v1_match_lifecycle.dart`（CPU
  runner／Playable共有のterminal cause分類・統合invariant検証helper）/
  `lib/src/combat_v1/playable/combat_v1_playable_match_config.dart` /
  `lib/src/combat_v1/playable/combat_v1_playable_match_snapshot.dart` /
  `lib/src/combat_v1/playable/combat_v1_playable_match_result.dart` /
  `lib/src/combat_v1/playable/combat_v1_playable_match_controller.dart`
- 実装（Playable 1B）: `lib/src/combat_v1/playable_ui/`配下（24章以降参照）。
- テスト: `test/combat_v1/playable/`配下（Playable 1A、10章参照）・
  `test/combat_v1/playable_ui/`配下（Playable 1B、31章参照）。

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
- `List<CombatV1PlayableObservation> _recentObservations`（bounded、上限8件。
  超過分は古いものから破棄する。13章）

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

---

# Playable 1B — Minimal Playable Match UI（実装追記）

以下はPlayable 1B（Human A vs CPU Bの1試合をブラウザ上で最後まで遊べる
状態にする）で確定した実装判断。Playable 1A契約（1〜23章）は無断変更
していない——Playable 1Bが直接呼び出すのは`CombatV1PlayableMatchConfig`/
`CombatV1PlayableMatchController`/`CombatV1PlayableMatchSnapshot`/
`CombatV1PlayableMatchResult`・`submitHumanAction`・`advanceCpuOneAction`/
`advanceCpuUntilHumanInput`のみ（20章「Public Types」の範囲内）。
`CombatV1MatchState`・`CombatV1LegalActionEnumerator`・
`CombatV1ActionExecutor`をWidgetから直接呼び出すことは一切ない。

## 24. Screen Flow / Entry Point

2画面構成:

- `CombatV1PlayableSetupScreen`（wrestler selection・Start Match）
- `CombatV1PlayableMatchScreen`（試合本体・Counter bottom sheet・
  result overlay）

別Result Screenは作らない——result overlayはMatch Screen内の
`Positioned.fill`カード（`_ResultOverlay`）として実装する。

Title画面（`lib/src/screens.dart`）の`TitleScreen`へ、既存の
`Navigator.push` + `MaterialPageRoute`パターンのまま新しいボタン
「Combat Ver.1 対戦（Experimental）」を追加した（Balance Dashboardの
「Combat V1 Balance Dashboard（開発用）」導線とは別で、Debug分析画面の
中ではなくTitle画面上に直接置く——一般プレイヤーが直接試せる場所に置き、
かつ「Experimental」であることをボタン文言で明示する、という7〜8章の
要件に対応）。

ボタン追加でTitle画面のボタン総数が増えたため、既存の中央寄せ固定
`Column`が低い画面高（狭幅スマホ・一部widget test surface）でoverflow
する回帰が発生した。`LayoutBuilder` + `SingleChildScrollView` +
`ConstrainedBox(minHeight: ...)`でラップし、収まる場合は従来通り中央
寄せ、収まらない場合のみscrollできるようにして解消した（既存
`test/screens_title_test.dart`は無変更のまま全passすることを確認済み）。

## 25. Setup Screen

`CombatV1PlayableSetupScreen`（StatefulWidget）:

- Human/CPU wrestler選択（production 4体、固定表示順
  `combatV1PlayableWrestlerOrder = ['misaki','jack','akari','reina']`
  ——`combatV1DefaultBatchWrestlerIds`（Simulation/Batch package）へは
  依存させず、Playable UI専用に独立して同じ値を再定義する。12章と同じ
  設計思想）
- display nameは`combatV1ProductionWrestlerRegistry[id].wrestler.name`
  （唯一のsource of truth、`combatV1PlayableWrestlerDisplayName`
  helper経由）——UI literalでレスラー名を重複管理しない
- mirror match（同一wrestler）を禁止しない
- 既定選択: Human=`akari`、CPU=`reina`
- Start Matchで`CombatV1PlayableMatchScreen(humanWrestlerId:,
  cpuWrestlerId:)`へ`Navigator.push`

## 26. Match Session Adapter（Controller Factory Injection）

`lib/src/combat_v1/playable_ui/combat_v1_playable_match_session.dart`に、
`CombatV1PlayableMatchController`のうちMatch Screenが実際に使う
API（`snapshot`/`result`/`submitHumanAction`/`advanceCpuOneAction`）だけを
抽出した`abstract interface class CombatV1PlayableMatchSession`を定義し、
production既定実装`CombatV1PlayableRealMatchSession`は該当APIを
そのままcontrollerへ委譲するだけの薄いadapter（ロジックの再実装は一切
行わない）。

`CombatV1PlayableSessionFactory = CombatV1PlayableMatchSession Function(
CombatV1PlayableMatchConfig config)`をMatch Screenのconstructor
parameterとして注入可能にする（既定は`combatV1PlayableDefaultSessionFactory`
——実controllerを構築する）。widget testはこのfactoryへscripted fake
session（`FakePlayableMatchSession`、test専用）を差し込むことで、実Engine
を一切経由せずCPU loop・Counter promptなどの複雑な状態遷移を検証できる
（74・84章の設計意図をそのまま実現）。

## 27. Seed Strategy（実装）

`combat_v1_playable_match_session.dart`の
`combatV1PlayableGenerateSeeds()`が、UI/application層専用のseed生成の
唯一の実装:

```dart
typedef CombatV1PlayableSeedPair = ({int engineSeed, int cpuPolicySeed});
CombatV1PlayableSeedPair combatV1PlayableGenerateSeeds() {
  final source = Random();
  final engineSeed = source.nextInt(1 << 31);
  var cpuPolicySeed = source.nextInt(1 << 31);
  if (cpuPolicySeed == engineSeed) cpuPolicySeed = (cpuPolicySeed + 1) & 0x7fffffff;
  return (engineSeed: engineSeed, cpuPolicySeed: cpuPolicySeed);
}
```

`Random()`（seedなし、システムentropy由来）を使用——`DateTime.now()`を
UI層でも直接読まない設計とした（Web/native両対応、同一microsecond内の
複数呼び出しでも異なる値になる）。この関数はcontroller/domain層には
一切持ち込まない——`CombatV1PlayableMatchScreen`が`initState`/Rematch時に
1度だけ呼び出し、結果を`CombatV1PlayableMatchConfig.engineSeed`/
`.cpuPolicySeed`へ明示的に渡す。widget testは
`CombatV1PlayableSeedGenerator`（`CombatV1PlayableSeedPair Function()`）を
constructor経由で差し替え、固定値を返す。

Seedは画面右上の「Match Details」アイコンボタン（`AlertDialog`）で
`Engine Seed`/`CPU Policy Seed`/`Max Actions`/`Rules`として表示できる。

## 28. Match Screen — State / CPU Loop / Counter Prompt

`CombatV1PlayableMatchScreen`（StatefulWidget）の最小state: `_session`
（`CombatV1PlayableMatchSession`）・`_snapshot`・`_config`（debug表示用）・
`_selectedCardInstanceId`・`_submitErrorMessage`・`_cpuBusy`・
`_counterSheetOpen`。

- **CPU one-step progression**: `advanceCpuOneAction()`を`Future.delayed
  (widget.cpuDelay)`ループから呼び、1step毎に`setState`する（16章）。
  `advanceCpuUntilHumanInput()`は使わない。既定delay
  `combatV1PlayableDefaultCpuDelay = Duration(milliseconds: 400)`
  （17章の推奨範囲内）、widget testは`Duration.zero`または任意値を
  constructor経由で注入する。
- **CPU loop停止条件**: `status == active && !isHumanInputRequired`の間
  ループを継続し、Human手番（Counterの防御側逆転を含む）または
  terminal/safety/invariant/errorで自然に停止する（8・13章の
  actor解決にそのまま従う）。
- **Reentrancy guard**: `_cpuBusy`フラグで二重loop起動を防止（20章）。
  loop中は`IgnorePointer`でHuman hand/primary actionsを無効化する。
- **Mounted safety**: `Future.delayed`後・`advanceCpuOneAction`後の両方で
  `if (!mounted) return;`を確認する（19章）。
- **Counter prompt**: `isHumanInputRequired && pendingAttack != null`に
  なった時点で`showModalBottomSheet`（`isDismissible: false` +
  `enableDrag: false` + 内部を`PopScope(canPop: false, ...)`でラップ）を
  1度だけ開く（`_counterSheetOpen`フラグで多重表示防止）。CPU防御時
  （`isHumanInputRequired == false`）はpromptを一切出さない。

## 29. Action Presentation

Human手番のprimary actionsは`snapshot.legalActions`の`kind`集合から
機械的に導出する（UI側でlegality判定を再実装しない）:

- `phase == discard`: 「手札から1枚捨ててください」＋Discard buttonのみ
  （Technique等は隠す）
- Human DOWN（`posture == down && phase == action`）: 大きな`DOWN`表示
  ＋Stand Up/Restのみ（hand行自体を非表示）
- それ以外（action phase・STAND）: 選択中card + `kind`一致で
  Technique button・PIN/End Turn（End Turnは`OutlinedButton`で視覚
  優先度を下げる、38章）
- Counter応答局面: 下部barではなくbottom sheetが担当

card tapは即実行せず選択のみ（30章）。選択済みcardと一致する
`CombatV1LegalAction`が現在のlegal action snapshotに無ければbuttonは
disabledのまま（`onPressed: null`）。

hand cardには`displayName`/`category`/技属性・DMG・HEAT・Cost（`counter`
の場合はCost属性のみ）・FINISHER/COUNTER badge・`isUsable`disabled
styling（「現在は使用できません」）を表示する——`CombatV1PlayableHandCard`
が持つmetadataのみを使い、reasonをUI側で再計算しない（31章）。

## 30. Recent Action Log（実装判断・簡略化）

`recentObservations`のHuman-readable mapping
（`combatV1PlayableObservationLabel`）は、actor（`YOU`/`CPU`）＋
action **kind**（例: 「技を使用」「PINを宣言」「RESTでHPを回復」）のみで
構成し、カード表示名は含めない。

理由: Human自身のcardは実行後handから既に取り除かれており（discard/
technique使用済み）、CPUのcardは常に非公開のため、`cardInstanceId`から
安全に表示名を逆引きできる経路が hidden-safe snapshot API上に存在しない
（`CombatV1PlayableObservation.action`は`cardInstanceId`のみ保持し、
displayNameは保持しない、16章）。Catalogを直接引いてinstanceIdから
名前を解決する実装も可能だが、それはUI層がEngineの内部identityへ
直接アクセスすることになり、hidden information境界を弱める設計になる
ため意図的に採用しなかった。kindベースのlabelはdamage等を再計算せず、
hidden information違反のリスクもない。

## 31. Widget / Integration Tests

`test/combat_v1/playable_ui/`配下（実Engineを経由しないsynthetic
snapshot中心、`combat_v1_playable_ui_test_fixtures.dart`が共有fixture）:

- `combat_v1_playable_ui_formatters_test.dart` — pure formatter単体test
- `combat_v1_playable_setup_screen_test.dart` — Setup画面
- `combat_v1_playable_match_screen_test.dart` — Match初期表示・Discard・
  Technique・DOWN・PIN・Hidden Info・Result overlay（matchOver/
  safetyLimit/invariantViolation/error全4状態、"53章 Winner Display
  Guard"の直接検証を含む）
- `combat_v1_playable_match_screen_cpu_test.dart` — CPU loop（busy
  indicator・delay injection・Human手番での停止）・Counter prompt
  （選択→submit・Decline・外側tap不可・CPU防御時は非表示）
- `combat_v1_playable_mobile_overflow_test.dart` — 320px幅でSetup/
  Match（action/DOWN）/Counter prompt/Result overlayがoverflowしない
  ことを`tester.takeException()`で確認
- `combat_v1_playable_match_screen_integration_test.dart` — 実
  `CombatV1PlayableMatchController`（`combatV1PlayableDefaultSessionFactory`
  経由）でSetup config → controller → Match UIの接続を確認する
  integration test。無理に賢い自動選択ロジックは作らず、単純な
  button優先順位（Counter decline > Discard > StandUp/PIN/EndTurn/Rest）
  で数手だけ進める（terminalまでの完走は必須にしない、88章）

## 32. Browser Smoke Test（実施結果）

`flutter build web`成功後、ローカルでbuildを配信し、Playwright +
Chromium（headless、`--enable-unsafe-swiftshader`）で実際にbrowser
smoke testを実施した。Title → Setup（wrestler選択・mirror確認）→
Start Match → Discard → Technique → PIN → Counter（decline）→ CPU
自動進行 → `試合終了` → `YOU WIN`（PIN）→ Rematch → 新しい試合が
Turn 1から再開、まで実際に完走することを確認した（console error 0件・
page error 0件、layout overflow無し）。Match Detailsダイアログ
（Engine Seed表示）も確認済み。

（sandboxed環境固有の注記: headless Chromiumの既定proxy設定では
`fonts.gstatic.com`・`www.gstatic.com`（canvaskit CDN）への外部fetchが
失敗するため、smoke test実行時のみ`build/web/flutter_bootstrap.js`の
`useLocalCanvasKit`を有効化し、Google Fontsのfetchをproxy経由へ
route替えした。production build成果物・アプリコードには一切影響しない、
テスト実行環境限定の回避策。）

# Playable 1C — Action Feedback / PIN Readability / Context Help（実装追記）

## 33. Objective

Playable 1A/1B merge後の独立playtestで最も大きかった指摘は、ルールバランス
ではなく「何が起きたか分からない」（Technique結果・CPU行動・PIN結果が
追えない、KOC/HEAT/FINISHERの意味が伝わらない、Rest/Stand Upの違いが
事前に分からない）だった。Playable 1Cは、この“action feedback / UX
readability”のみを対象にした小規模polishフェーズであり、ゲームルール・
バランス・Core Engineは一切変更しない。

## 34. Scope

- Human/CPU Technique action後のresult feedback（actor・技名・damage・
  target HP変化・posture変化・HEAT変化）
- PIN/SUBMISSION結果のtext feedback（KICK OUT / MATCH OVER、ESCAPED /
  GIVE UP）
- Counter成立/decline後の結果feedback
- Recent action logの高粒度化（技名・damage結果・posture変化）と、
  「直近1件を大きめbanner・その前数件をcompact list」への整理
- KOC/HEAT/Rest/Stand Up/Discardの短いcontext help
- FINISHER使用不能時のHEAT閾値hint
- wrestler energy pool（production data由来）の1行表示、hand横スクロール
  cue
- Setup wrestler選択・Human hand cardへのaccessibility semantics
  （`selected`/`enabled`）
- 上記に対応するpure/widget/semantics/integration test、mobile
  （390×844・320×720）widget test

## 35. Non-Scope

- damage formula・KOC rule・PIN rule・Counter rule・HEAT threshold・
  FINISHER条件・wrestler/card balance・deck・random/seed戦略・action
  orderの変更（Core Engine/Production Dataは無変更）
- PIN 1→2→3 countのstep animation（LATER）
- tutorial state machine・multi-step onboarding・spotlight overlay
  （LATER、31章と同じ方針を継承）
- Balance Dashboard 1B・Phase 12B-2B/2C（着手しない）
- CPU delayの大幅な変更（既定400msを維持。最大でも600ms程度までの調整の
  みを許容する方針だったが、今回は400msのまま——17章の推奨レンジ内）
- Playable 1A Known Minor（REST direct test coverage・winner metadata
  gate・Human hand list immutability）への着手

## 36. Action Feedback Model

`lib/src/combat_v1/playable/combat_v1_playable_action_feedback.dart`に
新規追加した、pure presentation-only value object
`CombatV1PlayableActionFeedback`（と`CombatV1PlayableFeedbackKind`/
`CombatV1PlayablePinFeedbackOutcome`/
`CombatV1PlayableSubmissionFeedbackOutcome`）。

- `actorPlayerIndex`/`opponentPlayerIndex`・`actionDisplayName`（技/
  COUNTER名）・`damage`・`hpOwnerPlayerIndex`/`hpBefore`/`hpAfter`・
  `postureOwnerPlayerIndex`/`postureBefore`/`postureAfter`・
  `heatBefore`/`heatAfter`・`kocOwnerPlayerIndex`/`kocBefore`/
  `kocAfter`・`pinOutcome`/`submissionOutcome`を持つ。該当しない値は
  すべて`null`のまま（推測でデフォルト値を埋めない）。
- 文言・banner構成は持たない——`playable_ui/
  combat_v1_playable_feedback_formatters.dart`のpure formatter
  （`combatV1PlayableFeedbackTitle`/`combatV1PlayableFeedbackDetailLines`/
  `combatV1PlayableFeedbackCompactLabel`）が、この値だけからUI文字列を
  導出する。

### 36.1 どこで構築するか

11章「Where to Build Feedback」の優先順位Aに従い、
`CombatV1PlayableMatchController._applyAction`（Playable 1A production
file）を拡張した。各actionの実行直後、既に保持している
`stateBefore`/`_state`（実行後）という2つの`CombatV1MatchState`を比較
（before/after diff）し、`CombatV1PlayableActionFeedback`を1件構築して
`_recentFeedback`（`_recentObservations`と同じ8件保持のbounded
history）へ追加する。Widget/UI層は、この構築済みのpure valueを読むだけで、
damage・PIN/SUBMISSION判定を一切再計算しない。

controllerは既にraw `CombatV1MatchState`と`CombatV1CardCatalog`を内部に
持っている（`_buildHandCard`/`_buildPendingAttackView`と同じ信頼境界）
ため、この拡張はhidden information境界を新たに広げるものではない
——feedbackが参照する情報は次のいずれかに限られる:

1. 実際に観測されたbefore/after差分（HP・posture・共有HEAT・KOC）。
2. 既に宣言・使用済み（＝両者へ公開済み）のTECHNIQUE/COUNTERカードの
   静的Catalogデータ（`cardId`から解決した`name`等）。

CPU未使用の手札・CPU counter候補・draw order・非公開deck内容はいずれも
参照しない（46章「No Hidden Info Regression」）。

### 36.2 kind別の構築方法

- `discard`/`endTurn`: 数値deltaを一切持たない（no changeケース）。
- `standUp`: actor自身のposture before/after。
- `rest`: actor自身のHP before/after（実際の回復量はここから逆算できる。
  `restHpRecovery`のようなrules literalはUI/feedbackへ持ち込まない）。
- `pin`（通常PIN宣言）: 防御側KOC before/after、および
  `!stateBefore.isOver && stateAfter.isOver && winner==attacker`から
  `pinOutcome`（`kickOut`/`matchOver`）を導出する。1/2/2.9のような
  具体的なcount値は一切表示しない（39章参照）。
- `technique`（宣言のみ）: `counterResponsePending`へ遷移するだけで
  damage等は未確定のため、`actionDisplayName`（宣言直後の
  `pendingAttack`から解決した技名）のみを持つ軽量feedback
  （`techniqueDeclared`）。
- `counter`: 防御側が使用したCOUNTERの表示名（`playCounter`実行後、
  防御側discardPileの末尾から逆引き——既に公開されたaction結果の解決
  であり、hidden information違反にならない）と、無効化された攻撃側
  TECHNIQUEの表示名（`relatedActionDisplayName`）を持つ。damage等の
  deltaは持たない（攻撃は完全に無効化されるため）。
- `declineCounter`（TECHNIQUE成立解決）: `techniqueResolved`。
  攻撃側/防御側のHP・posture・共有HEATのbefore/afterを保持し、実際に
  適用されたdamageは`defenderBefore.hp - defenderAfter.hp`から導出する
  （Technique metadataの宣言damageをそのまま使わない、37章）。同一
  actionでDIRECT PIN/SUBMISSIONへ自動移行した場合
  （`docs/combat_rules_v1.md`8・10章）は、[`pinOutcome`]/
  [`submissionOutcome`]も追加で設定する——判定は、宣言済みTECHNIQUEの
  静的metadata（`directPin`/`submissionHold`/`finisherType`、公開情報）
  と、防御側KOCの実測差分・試合終了の有無（PIN/SUBMISSION以外では
  KOCが変化しないというEngine全体の不変条件）から行う。legality判定・
  カウント計算の再実装ではなく、Engineが実際に到達したstate遷移を
  観測しているだけである。

## 37. Do Not Fabricate Deltas（39章と対応）

damage・HP変化・posture変化・HEAT変化・KOC変化はすべて、before/after
`CombatV1MatchState`の実測差分から導出する。Technique/Counter
Catalogの宣言値（`damage`・`heatGain`等）は、technique名・属性等の
表示にのみ使う——「実際に入ったdamage」として扱わない。

## 38. PIN / SUBMISSION Feedback

- 通常PIN宣言・DIRECT PIN自動移行のいずれも、feedback上は同じ
  `CombatV1PlayablePinFeedbackOutcome`（`kickOut`/`matchOver`）で表現し、
  banner上は「PIN ATTEMPT」＋結果（`KICK OUT!`／`3 COUNT — MATCH
  OVER`）を表示する。
- SUBMISSION（submissionHold技・FINISHER submissionType）は
  `CombatV1PlayableSubmissionFeedbackOutcome`（`escaped`/`matchOver`）で
  表現し、「SUBMISSION」＋結果（`ESCAPED`／`GIVE UP — MATCH OVER`）を
  表示する。
- Result overlay（matchOver）とのつながり: PIN/SUBMISSIONでの決着は、
  直前の`latestFeedback`（`PIN ATTEMPT`→`3 COUNT — MATCH OVER`等）と、
  続くResult overlay（`YOU WIN`/`CPU WIN`＋`combatV1PlayableTerminalCauseLabel`）
  が同じ決着を指すため、体験として自然に繋がる（53章のwinner display
  guardは無変更のまま維持）。

## 39. PIN Count Safety

PIN countがstructured data（1/2/2.9のいずれで終わったか）として安全に
取得できる経路は存在しない——`determinePinCountResult`
（`combat_v1_pin_rules.dart`）は防御側KOCとrulesから決定論的に計算
できるが、Playable 1Cではこの値をUI feedbackへ持ち込まないことを意図的
に選んだ（同じ計算をUI/session層で行うこと自体は技術的に可能だが、
「1」「2」「2.9」の具体的な数値をユーザーへ見せる要件が無く、将来の
ルール定数変更で数値表示だけが古くなるリスクを避けるため）。
表示するのは、before/after/`winnerPlayerIndex`から確実に判定できる
「KICK OUT（試合continue）」と「3 COUNT — MATCH OVER（試合決着）」の
2値のみ。防御側KOCのbefore/after実測値（38章の`kocBefore`/`kocAfter`）
は表示する——これは推測ではなく実測なので安全。

## 40. Recent Action Log / Latest Feedback Banner（UI実装）

`combat_v1_playable_match_screen.dart`の`_ActorAndRecentPanel`を拡張:

- 直近1件（`snapshot.latestFeedback`）を、actor labelの直下に大きめの
  `_LatestFeedbackBanner`（title＋detail lines）として表示する。次の
  actionのfeedbackが届くまで表示され続ける（40章「Feedback Display
  Duration」の推奨方針——CPU delay自体は変更せず、feedback
  persistenceで可読性を確保する）。
- その前の直近4件（`snapshot.recentFeedback`）を、compact
  1行ラベル（`combatV1PlayableFeedbackCompactLabel`）のWrapとして
  表示する（8件保持全件を必ずしも見せない、画面を長文ログで埋めない
  方針）。
- この可変高panel全体を`ConstrainedBox(maxHeight: 132)` +
  `SingleChildScrollView(physics: NeverScrollableScrollPhysics())`で
  内部clipし、Human status panel/Primary actions barが常に
  scroll不要で画面内へ収まる既存レイアウト（`Expanded`＋固定bottom
  bar）を壊さないようにした——feedback内容量が可変になったことに伴う、
  今回追加した安全策。

既存の`recentObservations`/`combatV1PlayableObservationLabel`
（Playable 1B、kindのみのlabel）はそのまま維持している——Playable 1A
publicAPIとして引き続き有効であり、削除の必要はない。

## 41. CPU Readability

CPU actionもHumanと同一のfeedback構築経路（36章）を通るため、
technique名・damage・target HP変化・posture変化・HEAT変化が同じ粒度で
表示される（`actorPlayerIndex`が`CombatV1PlayableMatchController.
cpuPlayerIndex`になるだけで、構築ロジックは共通）。30章で「CPU側は
常に非公開のため」kindベースのlabelに留めていた制限は、Playable 1Cで
意図的に緩和した——ただし対象は常に「既に宣言・使用済みの（＝公開
された）CPUカード」のみで、CPU未使用手札・counter候補は一切参照しない
（46章）。

## 42. Context Help（KOC / HEAT / Rest / Stand Up / Discard / Finisher）

- **KOC**: 既存のHP/KOC status panelのTooltip（「PIN /
  Submissionからの脱出に使用」）をそのまま維持。
- **HEAT**: `_SharedStatusPanel`を「HEAT 360 / 200」という進捗風表示
  から、`Shared HEAT {value}` + `Finisher Unlock {threshold}`の
  別表示へ変更し、閾値到達後は`UNLOCKED`badgeを添える。Tooltipで
  「HEATは両者共有・蓄積型（減りません）」「閾値は上限ではなく解禁
  ライン」を明示する。360のような閾値超過値も、progress barではなく
  数値表示のため自然に見える。
- **FINISHER**: hand card（`_HandCardTile`）のfinisher cardへ
  `Requires HEAT {threshold}`を常設表示する。使用不能な場合は、
  HEAT不足だと安全に判定できる時のみ`Requires HEAT {threshold}
  (current {sharedHeat})`、それ以外は既存の汎用メッセージ
  （「現在は使用できません」）に留める——HEAT以外のlegality reasonを
  UI側で断定しない（25章のFINISHER Feedback指針どおり）。
- **Rest / Stand Up**: Human DOWN時（`_DownIndicator`）に、それぞれ
  「立ち上がって、このターンの行動を続ける」「HPを回復してターン
  終了」という短い説明を追加。回復量はrules literalとしてUI側に
  持ち込まない（安全に数値取得できないため）。
- **Discard**: discard prompt直下に「ターン開始時に手札を1枚捨てます」
  を追加。

いずれもフルtutorial化しない（tutorial state machine・multi-step
onboarding・spotlight overlayは今回も未実装のまま、35章）。

## 43. Wrestler Description / Hand Scroll Cue

- Setup画面の`_WrestlerChoiceCard`へ、
  `combatV1ProductionWrestlerRegistry`のwrestler静的データ
  （`energyPool`）から`ENERGY {attr}{amount} / ...`
  （既存formatter`combatV1PlayableEnergyCostLabel`を再利用）を1行
  追加した。新しいbalance説明・archetype名は作らず、既存production
  dataの数値をそのまま表示するに留めている。
- Human hand（`_HandRow`）がカード2枚以上の場合、「→
  横にスクロールできます」の小さなcueを追加した。

## 44. Accessibility Semantics

- Setup wrestler choice card: `Semantics(button: true, selected:
  <選択状態>, label: <wrestler名>)`。
- Human hand card（`_HandCardTile`、Counter promptの選択sheetでも共用）:
  `Semantics(button: true, selected: <選択状態>, enabled: <isUsable>,
  label: <card表示名>)`。

複雑なfirst-time persistence・tutorial saveは今回のscopeに含めない
（29章と同じ方針）。

## 45. Hidden Info Regression Guard

36章の通り、feedbackが参照するのは「既に公開されたaction結果」
（実行済みTECHNIQUE/COUNTERの静的Catalogデータ）と「実測state差分」
のみ。CPU未使用hand card・CPU counter候補・draw order・非公開deck
内容はfeedback構築のいずれの分岐でも参照しない——これはPlayable 1A
snapshot（16章）が元々持っていた保証をそのまま維持している。

## 46. Winner Guard / Architecture Boundary（維持）

53章「Winner Display Guard」（`status != matchOver`ではwinner表示
禁止）は無変更。Raw `CombatV1MatchState`をWidgetへ渡す経路も追加して
いない——feedbackは常にcontroller内部でpure valueへ変換してから
snapshotへ載せる（7・48章のsession/controller boundaryをそのまま
維持）。

## 47. Mobile Considerations

- feedback banner・finisher hint等、内容量が可変になったpanelが増えた
  ため、320×720に加えて390×844でもWidget testを追加した
  （`combat_v1_playable_mobile_overflow_test.dart`「390×844（Playable
  1C 追加）」group）。
- `_HandCardTile`内部（finisher HEAT要件hint等の追加行）は
  `SingleChildScrollView(physics: NeverScrollableScrollPhysics())`で
  包み、カードの見た目の高さ（`SizedBox(height: 182)`、Playable 1Bの
  168pxから拡張）を超える内容が万一発生してもRenderFlex overflowに
  ならないようにした。
- `_ActorAndRecentPanel`のfeedback表示block自体も40章の通り
  `ConstrainedBox(maxHeight: 132)`で上限を設け、Human status
  panel/Primary actions barが常にscroll不要で画面内に収まる既存レイ
  アウトを維持している。

## 48. Deferred（今回は実装しない）

- PIN 1→2→3のstep animation（LATER、45章「No Full PIN Animation」）。
- tutorial state machine・multi-step onboarding・skip
  tutorial・spotlight overlay framework（LATER、30章「No Tutorial
  System」）。
- sound（今回無し）。
- card art / wrestler art（今回無し）。

## 49. Tests（Playable 1C）

- **Pure**（`test/combat_v1/playable/combat_v1_playable_scenario_test.dart`
  「Playable 1C: Action Feedback」group、実controller経由）: Human/CPU
  technique resolved feedback（技名・damage・HP変化・posture遷移・
  HEAT変化）、discard/endTurnのno-changeフィードバック（全delta
  null）、PIN kickout feedback、PIN match-over feedback。
- **Widget**
  （`test/combat_v1/playable_ui/combat_v1_playable_feedback_widget_test.dart`）:
  Human/CPU technique feedback banner、feedback persistence、PIN
  kickout/match-overメッセージ、KOC/HEAT context help、HEAT
  閾値超過表示、FINISHER HEAT要件hint、Rest/Stand Up/Discard
  説明、hand scroll cue、Setup/Match両方のaccessibility semantics
  （selected/enabled）。
- **Mobile**
  （`combat_v1_playable_mobile_overflow_test.dart`）: 320×720に加え、
  390×844でSetup/Match（feedback banner+finisher hint込み）/Counter/
  Resultのoverflow無しを確認。
- 既存Playable 1A/1B test（80件）はいずれも無変更のまま
  green——HEAT表示format変更に伴い`combat_v1_playable_match_screen_test.dart`
  の該当assertionのみ更新した（`HEAT 40 / 200` →
  `Shared HEAT 40`/`Finisher Unlock 200`）。

---

# Playable 1C.1 — Rule Clarity（実装追記）

Production上の実ブラウザ検証で、ユーザーが以前指摘した5項目のうち
「A. Discard」はRESOLVED、残り4項目（B. Energy／C. COUNTER／D.
TECHNIQUE DOWN対象／E. PIN）がPARTIAL〜NOT RESOLVEDだった。今回は
**ルールを一切変更せず**、UI/help/presentation層のみでこの4項目を
解消する。

## 50. Production UX Findings（今回の起点）

| 項目 | Production検証結果 | 対応 |
|---|---|---|
| A. Discard | RESOLVED | 今回scope外（維持） |
| B. 使用可能な技ENERGY | PARTIAL | 53〜57章 |
| C. COUNTERの通常時使用可否 | PARTIAL | 58〜59章 |
| D. 技のDOWN対象 | PARTIAL | 60〜61章 |
| E. PINの状態・意味 | NOT RESOLVED | 62〜65章 |

## 51. Strict Purpose / Non-Scope

**目的**: プレイヤーが画面だけで、自分が使えるENERGYの種類・量、技の
ENERGY COST、カードが使える／使えない理由、COUNTERの用途、TECHNIQUEの
DOWN/STANDが誰に対するものか、PINの意味・条件、`PIN N`の意味、KOCとPIN
の関係を理解できるようにする。

**禁止事項（今回は一切変更しない）**: energy rules・card cost・discard
rules・Counter legality・Technique result posture・PIN
condition・KOC rule・Submission rule・wrestler balance・Production
Data・RNG。すべてUI表示（新しいsnapshot fieldの追加を含む、下記52章）と
文言のみ。

大規模tutorial（tutorial state machine・spotlight overlay・tutorial
persistence・step-by-step onboarding engine）は今回も作らない（30章
「No Full Tutorial」と同じ方針を維持）。

## 52. Energy Semantics 調査結果（実装前提）

`lib/src/combat_v1/combat_v1_energy.dart`・`combat_v1_match_state.dart`・
docs/combat_rules_v1.md 5章から確認した事実:

- `CombatV1EnergyPool`（`CombatV1PlayerState.energyPool`）はレスラー
  固有の**固定**capacity。技使用で減少しない。
- `CombatV1PlayerState.spentEnergy`が「今サイクルで使用済みのENERGY」
  （属性別Map）。自ターン開始時（`_startTurn`）に`spentEnergy: const {}`
  へ戻すだけで、`energyPool`自体は一切変化しない。
- 現在使用可能な量 = `energyPool.amountFor(attr) -
  (spentEnergy[attr] ?? 0)`（`CombatV1PlayerState.availableEnergyFor`、
  既存の公開getter）。
- **結論**: ENERGYはターン内では消費されるが、自ターン開始時に全回復
  する。「消費されない固定値」でも「永続的に減り続ける値」でもない
  ため、`Current Energy`という名称は使わず、`Technique Energy`と
  `Your Energy`（比較文脈）を採用した（8章の既定方針どおり）。
- HEAT（`CombatV1MatchState.sharedHeat`）とは完全に別モデル（両者
  共有・蓄積型・消費されない・FINISHER解禁の可否のみに関係）。ENERGY
  は個人所有・属性別・技/COUNTERの支払いにのみ関係。UIでも別セクション
  として表示する（既存の`_SharedStatusPanel`とHuman専用の新設
  `_EnergyPanel`で分離、54章）。
- FINISHER cardは「ENERGY COST」（技を宣言するための支払い）と
  「HEAT解禁閾値」（`category==finisher`を宣言できる前提条件）が
  独立した別条件（13章）。HEAT到達だけで「使用可能」と断定しない
  （既存のfinisher HEAT hint/disabled messageを維持）。
- Technique支払いは常に`allowWildSubstitution: true`
  （docs 5.1章・Phase 1で確定）。COUNTER支払いは
  `CombatV1RulesConfig.counterAllowsWildSubstitution`（既定false）。
  今回のUI診断（56章）はTechniqueのみを対象とし、COUNTER側のポリシー
  値をUIへ複製しない。

**Snapshot変更**（表示専用の読み取りモデル拡張、legality判定は一切
追加しない）:

- `CombatV1PlayableHumanStatus`へ`energyPool`
  （`CombatV1EnergyPool`）・`availableEnergy`
  （`Map<CombatV1EnergyAttribute, int>`、全属性の現在使用可能量）を
  追加。いずれも`CombatV1PlayerState`の既存fieldをそのまま読むだけ。
- `CombatV1PlayableOpponentStatus`（CPU）には追加しない——Humanの
  ENERGY構成のみを画面へ出す（9章「Match Screen Energy Panel」の
  要求どおり、CPUの内部状態は公開しない）。
- `CombatV1PlayablePendingAttackView`へ`energyCostTotal`
  （`CombatV1PendingAttack.energyCost.total`）を追加。COUNTERの動的
  必要量（7章「返される側のTECHNIQUEのENERGY COST総量」）を表示する
  ために必要——宣言済みの攻撃の静的metadataであり、既に両者へ公開
  済みの情報のため hidden information違反にならない。

## 53. Match Screen Energy Panel（新設 `_EnergyPanel`）

`combat_v1_playable_match_screen.dart`の`_HumanStatusPanel`直下に
Human専用の`_EnergyPanel`（key:
`combat_v1_playable_energy_panel`）を常時表示する（Setup画面だけの
表示ではなく、Match中いつでも参照できる、9章）。

- 表示形式: 保有量が1以上の属性のみ、`{属性} {使用可能}/{保有}`
  （例: `打 2/5`）。保有量0の属性（そのレスラーが持たない属性）は
  表示しない。
- Tooltipで「ENERGYは技/COUNTERで消費されるが自ターン開始時に全回復
  する」「HEATとは別リソース」の2点を明示する。

## 54. Card Cost Comparison（`_HandCardTile`拡張）

Technique cardの本文に、既存の`Cost {属性}{量}`表示に代えて
`Energy {属性}{cost} / {available}`
（`combatV1PlayableEnergyComparisonLabel`、`availableEnergy`が無い
呼び出し元では従来の`Cost`表示にfallback）を表示する。UI側で新しい
legality判定は行わない——2つの公開数値（技のCost・現在の使用可能量）
を並べて見せるだけ。

## 55. Why Unusable — Energy（安全な診断のみ）

`_HandCardTile._disabledMessage()`は、`card.isUsable == false`の
場合に理由を推測せず、安全に判定できる場合のみ具体的な理由を出す
（既存のFINISHER HEAT不足判定と同じ方針を踏襲）:

1. `card.category == counter` → 用途説明（58章）。
2. FINISHER HEAT不足だと判定できる → 既存の`Requires HEAT
   X (current Y)`。
3. Technique cardで、**Core Engineの`resolveEnergyPayment`関数
   そのもの**（`combat_v1_energy.dart`、再実装ではなく同一関数の
   呼び出し）を、公開snapshot値（`availableEnergy`を仮想的な
   pool・`spent: {}`として渡す）に対して再適用し、実際に支払いが
   失敗すると判定できた場合のみ`Energy不足: {属性}{available} /
   必要{cost}`を表示する。
4. 上記いずれでもない場合は既存の汎用`現在は使用できません`に留める
   （posture不一致・ROUGH制限など、UIが安全に断定できない理由は
   推測しない）。

この方式は「UI独自のlegality判定」ではない——`isUsable`自体は
一貫してLegalAction（`CombatV1LegalActionEnumerator` →
`CombatV1Engine.checkTechniqueLegality`）がSSOTのまま変更されず、
`resolveEnergyPayment`はEngine本体が支払い解決に使っている関数を
そのまま呼び出しているだけであり、UI側で新しい判定ロジックを実装
していない。

### 55.1 GitHub Codex App Finding修正（wild ENERGYを比較表示へ含める）

PR #22作成後、GitHub連携のCodex App（`chatgpt-codex-connector`、オフ
ラインで実施したexact-HEAD独立レビューとは別の自動レビュー統合）が
`combatV1PlayableEnergyComparisonLabel`（54章「Card Cost
Comparison」）に対してP2 findingを投稿した: 技のTECHNIQUE支払いは
常に＊(wild)補完を許可する（docs/combat_rules_v1.md 5.1章）ため、
具体属性だけが不足していても＊で支払えれば`isUsable == true`のまま
だが、比較表示の分母（使用可能量）が具体属性の保有量のみだったため、
実際は使用可能な技でも`打2 / 1`のように支払い不可能に見える表示に
なりうる、という指摘だった。

分母へ、その属性の具体的な使用可能量に加えて＊(wild)の使用可能量を
加算するよう修正した。[cost]は`CombatV1EnergyCost.isValid`により
＊自体をコストとして持たない（5.1章）ため、同じwild量を複数属性へ
加算しても二重計上にはならない——Production Catalogの現行技は
いずれも単一属性costのみのため、この表示は実際の支払い可否と常に
一致する。新しいlegality判定の追加ではなく、既に公開されている
＊保有量（`availableEnergy[wild]`）を比較表示へ含めるだけの変更
であり、`_energyWouldFail`（55章、`resolveEnergyPayment`を再利用する
安全診断）の判定結果とも整合する。

## 56. Counter Semantics（新規help、既存sheetは維持）

- 通常Action中（`counterResponsePending`ではない）のCounter cardは
  必ずdisabled（Engineが`counterResponsePending`以外でCounter
  actionを列挙しないため）。この場合の`_disabledMessage()`は
  「相手の技を受ける時に使用」を返す（COUNTERの用途を明示、14・15章の
  要求）。
- COUNTER response sheet（`_CounterPromptSheet`）自体は既存のまま
  （タイトル「返し技を選択」で通常カード選択と区別済み、16章の判断
  どおり大改造しない）。
- 新規追加: `_PendingAttackSummary`に「COUNTERに必要なENERGY: 合計X
  （COUNTERカード自身の属性1種で支払います）」を追加
  （`pending.energyCostTotal`、7章のCOUNTER動的cost仕様を画面へ
  反映）。Counter card自身にも、pending文脈がある場合は`Cost {属性}
  {合計}`を、無い場合は「必要量は返す技によって変わります」を表示
  する。
- Usability判定はCounter response時・通常Action時いずれも
  `card.isUsable`（LegalActionのSSOT）のみを使用し、変更していない
  （17章）。

## 57. Opponent Target Semantics 調査結果（Technique DOWN/STAND）

`combat_v1_technique.dart`・`combat_v1_pending_attack.dart`から確認
した事実:

- `CombatV1Technique`/`CombatV1PendingAttack`は
  `requiredOpponentState`（`CombatV1WrestlerPosture?`）と
  `resultOpponentState`（同）のみを持つ。**いずれも「相手」の状態を
  指すfieldであり、使用者自身（自分）のpostureを変える field は
  技モデルに一切存在しない**。
- 自分（active player）のposture制約は技ごとの個別fieldではなく、
  `selfDown`という汎用reasonCode（DOWN状態では技を宣言できない、11章）
  として一律に効いている——起き上がり/RESTの画面（既存の
  `_DownIndicator`）が既にこの制約を説明している。
- **Self-Down Possibility Check（21章）の結論**: Techniqueによって
  使用者自身のpostureが変化する仕組みは存在しない（コード上に
  該当fieldが無いことをgrepで確認済み）。したがって「一律 相手→DOWN
  に変更してよいか」のSTOP判定は不要——`resultOpponentState`は
  常に相手を指すという前提のままラベリングしてよい。
- 20章の例文「自分: STAND必要」は、実際のmodelには存在しない
  self-required-posture fieldを指しているように読めるが、上記の
  とおりそのfieldはコード上存在しない。「Technique使用者側の必要
  postureが存在する場合は対象を明示する」という条件付き指示は、
  存在しないため該当なし（vacuously satisfied）——per-card表示は
  追加していない。32章「Card Detail」の`Required posture`は
  `requiredOpponentState`（相手の必要状態）を指すと解釈し、59章の
  とおり実装した。

## 58. Opponent Target Label（実装）

`combat_v1_playable_ui_formatters.dart`に3つの純関数を追加した:

- `combatV1PlayableRequiredOpponentStateLabel` — 例:
  `相手がSTANDの時のみ使用可`（`requiredOpponentState`が非nullの
  場合のみ表示）。
- `combatV1PlayableOpponentResultStateLabel` — 例: `相手 →
  DOWN`（`resultOpponentState`が非nullの場合のみ表示。単独の
  `DOWN`/`STAND`表示は行わない、19章）。
- `combatV1PlayablePendingResultStateLabel` — COUNTER応答中の
  pending攻撃（相手＝CPUが使用した技）専用。対象は防御側＝Human
  自身になるため`あなた → DOWN`とラベリングする（カード面とは
  向きが逆であることに注意——`_PendingAttackSummary`で使用）。
  `resultOpponentState == null`の場合は`状態変化なし`。

Technique cardには required/result いずれも「該当する場合のみ」
表示し、`resultOpponentState == null`（状態変化なし）の技には何も
表示しない（推測で「状態変化なし」を全カードに付与するとノイズに
なるため、非nullの場合のみ明示する方針とした）。

## 59. PIN Semantics 調査結果（最優先項目）

`combat_v1_match_state.dart`・`combat_v1_engine.dart`・
docs/combat_rules_v1.md 8・9章から確認した事実:

- `CombatV1PlayerState.pinCardsHeld`は**保有しているPINカードの
  物理枚数**（共有4枚、開始時各2枚）であり、「PINカウント」
  （kick outの1/2/2.9/3カウント）とは**別概念**。旧UI表示
  `PIN {pinCardsHeld}`の`{pinCardsHeld}`はこのカード枚数であり、
  カウントの意味ではない——ユーザー指摘のとおり初見では誤解を招く
  表記だった。
- PIN action（`declarePin`、通常PIN）は攻撃側が保有PINカードを1枚
  使用して開始する。1/2カウントでkick outされると、その1枚が攻撃側
  →防御側へ移動する（最低1枚保証あり）。2.9カウントでは移動しない。
  DIRECT PINも同様にPINカードを使用する。
- PINのカウント（1/2/2.9/3）は防御側の**KOC**から一括で決まる
  （表: docs 8.2章）。KOC支払いは防御側のみが行う。KICK OUTは
  「保有していれば必ず行う」自動判定（選択肢は無い）。
- KOC（初期値10）はPINのKICK OUTと、SUBMISSIONからのESCAPE
  （10章）の両方に使う共通リソース。
- 通常PINの宣言条件: 相手がDOWN・そのターン中にTECHNIQUEを成功
  させている・自分がROUGH技をそのターン使用していない、の3条件
  （checkPinLegality）。既存の`CombatV1LegalActionEnumerator`が
  legalなときのみPIN actionを列挙する。

## 60. PIN Status Label（実装、`PIN N`廃止）

`_StatusPanelShell`の表示を`PIN {pinCardsHeld}`から**`PIN Cards
{pinCardsHeld}`**へ変更した（key:
`combat_v1_playable_pin_cards_text`）。曖昧な`PIN N`はUI上どこにも
残していない。近傍にTooltipで「PINを仕掛ける際に使用する保有カード
枚数です（開始時2枚）。KICK OUTの結果次第で相手との間を移動します」
を追加した（PIN resourceの意味の説明、24章）。

Match resultのcount表示（PIN ATTEMPT / KICK OUT / 3 COUNT — MATCH
OVER、既存Playable 1Cの`combat_v1_playable_feedback_formatters.dart`）
は無変更のまま維持し、`PIN Cards`という語とは明確に別のfeedback
として扱われている（28章「PIN Card vs Count Clarity」）。

## 61. PIN Action Condition Help（実装）

PIN button（`combat_v1_playable_action_pin`）にTooltipを追加した:
「PINカードを1枚使ってDOWN中の相手にPINを仕掛けます（このターン中に
技を成功させている場合のみ選択できます）」。完全な条件の羅列はせず、
実際にLegalActionが存在する時だけbuttonが表示される既存の挙動は
維持している（25章）。

## 62. KOC + PIN Relation（実装）

Human/CPU status panelのKOC Tooltipを「PINのKICK OUTやSubmissionから
の脱出に使用するリソースです（開始時10、防御側のみ消費）」へ更新した
（26章）。KICK OUT時の実際のKOC delta（`{owner} KOC {before} →
{after}`）は既存Playable 1Cの`_LatestFeedbackBanner`
（`combat_v1_playable_feedback_formatters.dart`、無変更）がそのまま
表示し続ける。

### 62.1 Codex Review Major Finding修正（決着条件の表現）

初版の用語ヘルプ（63章）KOC説明は「尽きると3カウント／GIVE UPで試合
が決着します」という文言だった。Codex独立レビューで、Core
semantics上の決着条件は「KOC残量が0になること」ではなく「その時点で
要求されるKOC costを支払えないこと」である指摘を受けた
（`combat_v1_pin_rules.dart`の`determinePinCountResult`——
`CombatV1RulesConfig`の閾値（既定: 1カウント3／2カウント2／
2.9カウント1）のいずれも支払えない場合に`null`を返し、
`CombatV1Engine._resolvePin`がPIN決着とする。SUBMISSIONも同様に
`rules.submissionEscapeKocCost`を支払えない場合にGIVE UP、
`_resolveSubmission`参照）。既定値では最終的な閾値がKOC1のため
「残り0で決着」という結果になりやすいが、これはrules
configの既定値に起因する結果であり、決着条件そのものの定義ではない
——ruleを変更すれば「remaining KOC=2・required KOC=3」のように
0以外でも支払い不能になり得る。

用語ヘルプの文言を「必要なKOCを支払えないと、3カウント／GIVE UPで
試合が決着します」へ修正した（`combat_v1_playable_match_screen.dart`）。
PIN／SUBMISSION双方に共通する説明として成立し、UI側で新しい
legality/決着判定ロジックを実装していない（既存の`_resolvePin`/
`_resolveSubmission`が確定させた結果を説明する文言のみの変更）。

## 63. Compact Rule Help（新設ダイアログ、tutorialではない）

AppBarへ新しいIconButton（key:
`combat_v1_playable_rules_help_button`、`Icons.help_outline`）を追加
し、`_showRulesHelp()`でTechnique
Energy／Shared HEAT／COUNTER／PIN Cards／KOCの5用語を1〜2文ずつ
説明するAlertDialogを表示する。tutorial state machine・spotlight
overlay・tutorial persistence・step-by-step onboarding engineは
一切実装していない（29〜30章の既定方針を維持）。

## 64. Card Detail（32章の反映）

`_HandCardTile`のTechnique分岐に、既存のCategory/Energy Cost
（比較表示化）/Damage/HEATに加え、Required posture
（`requiredOpponentState`）・Result opponent posture
（`resultOpponentState`）を追加した。COUNTER分岐には動的Costの
説明（56章）を追加した。FINISHER thresholdの表示（Requires HEAT
hint）は既存のまま。

## 65. Hidden Information Regression（維持確認）

`CombatV1PlayableOpponentStatus`（CPU）にはENERGY関連fieldを一切
追加していない——構造的にCPUのENERGY構成をUIへ渡すことができない
（コンパイル時に該当fieldが存在しない）。`_EnergyPanel`はHuman
専用の1インスタンスのみで、CPU用のEnergyパネルは存在しない。既存の
hidden information regression test（40章）に加え、63章のテストで
Energy panelがHuman専用であることも確認した。

## 66. Scope / Non-Scope（1C.1）

**Scope**: 上記のUI表示・snapshot読み取りモデルの拡張（Energy pool/
available energy/pending energy cost totalの3 field追加）・
formatter追加・widgetのラベル/Tooltip/Dialog追加。

**Non-Scope（今回変更しない）**:

- energy rules・card cost・discard rules・Counter legality・
  Technique result posture・PIN condition・KOC rule・Submission
  rule・wrestler balance・Production Data・RNG（Core Engine層は
  一切変更していない）。
- disabled card tap・scroll cue・controller feedback test深化などの
  Playable 1C既知Minor（33章、今回は同じwidgetを触った箇所以外は
  意図的に手を付けていない）。
- Flutter SDK pinning・deploy provenance・build reproducibility
  （34章、別follow-up）。
- Balance Dashboard 1B branch（35章、PR未作成のまま保留・今回一切
  変更していない）。
- Phase 12B-2B/2C（今回のscope外、リークなし）。

## 67. Tests（Playable 1C.1）

- **Widget**
  （`test/combat_v1/playable_ui/combat_v1_playable_1c1_clarity_test.dart`、
  新設）: Energy panel表示・保有量0属性の非表示・card cost
  comparison・`resolveEnergyPayment`経由の安全なEnergy不足診断
  （支払い可能な場合に誤って断定しないケースも含む）・Shared
  HEATとの分離・CPU側非公開・通常Action中Counter cardの用途
  caption・Counter応答時のCOUNTER動的cost表示・Technique
  cardのrequired/result posture表示（相手→DOWN・相手がSTAND/DOWNの
  時のみ使用可）・pending攻撃の`あなた → DOWN`表示・`PIN N`が存在
  しないこと/`PIN Cards N`表示・PIN Cards Tooltip・PIN button
  Tooltip・KOC Tooltip（PIN/Submission両方に言及）・用語ヘルプ
  ダイアログの内容。全17 caseがgreen。
- 既存Playable 1A/1B/1C test（1721件）はいずれも無変更のままgreen
  （snapshot/fixture側のみ、新規必須fieldへ既定値を追加する形で
  更新した——`CombatV1PlayableHumanStatus.energyPool`/
  `availableEnergy`・`CombatV1PlayablePendingAttackView.energyCostTotal`）。
- Mobile overflow test（320×720・390×844、既存
  `combat_v1_playable_mobile_overflow_test.dart`、無変更）も新しい
  Energy panel/card comparison行を含めてgreenのまま——`_HandRow`の
  card高さを182px→232pxへ拡張し、新規行が`SingleChildScrollView`の
  範囲内に収まるようにした。

# Playable 2A-1 — Match Guidance（実装追記）

## 68. Match Guidance

### 68.1 Objective

独立Player Experience Auditで、Combat V1は
rules-complete／operable（LegalActionに従って正しく操作でき、DMG／
HEAT／KOC等のfeedbackも正しい）ではあるものの、「なぜその行動を選ぶ
のか」「次に何を狙うべき状態なのか」（HP／KOC／DOWN／PIN／Submission
の関係、勝利への近さ）がプレイ画面から理解しにくい
（decision-readableでない）と評価された。Playable 2A-1は、新ルールを
一切追加せず、既存ルールの因果関係だけをUIから理解可能にする最初の
スライス。

### 68.2 Scope / Non-Scope

今回実装したのは以下の2種類のみ。

- **Current Action Guidance**（primary）: 現在のphase／pending
  state／postureから、「今プレイヤーが何をする段階なのか」を短い文で
  示す（Discard／Counter response／DOWN decision／Action phaseの4分岐）。
- **Context Hint**（secondary、最大1行）: 現在の盤面から、「その状態には
  どういう意味があるのか」を短く補足する（PIN opportunity／Shared
  HEAT Finisher unlock／Opponent DOWN significance／continued
  Technique、優先順位付きで最大1件）。

今回のnon-scope（後続2A slice、または恒久的にscope外）:

- 攻略AI・recommendation（「このカードを使え」「Counterした方が得」等）
  は一切生成しない。
- Counter outcome詳細・pending攻撃のHEAT・Direct PIN／Submission／
  Finisher type・unusable Counter理由の本格対応（Playable 2A-4予定）。
- PIN count prediction・勝率表示・新resource／新meter／新action／
  新phase。
- Combat rules（HP 0／KOC／PIN／Submission／Direct PIN／Counter
  legality・resolution／Shared HEAT／Energy／Draw・Discard／DOWN・
  STAND／Finisher unlock）・Core combat engine・CPU AI・deck
  composition・wrestler／technique dataは一切変更しない。

### 68.3 Architecture

```
CombatV1PlayableMatchSnapshot
        ↓
combatV1PlayableDeriveMatchGuidance（pure関数、priority判定を集約）
        ↓
CombatV1PlayableMatchGuidance（primary/secondary/kind、UI-oriented model）
        ↓
_MatchGuidancePanel（Widget、テキストをそのまま表示するだけ）
```

新設
`lib/src/combat_v1/playable_ui/combat_v1_playable_match_guidance.dart`
（既存`combat_v1_playable_ui_formatters.dart`と同じ「pure UI
formatting helpers」層——Flutter widget treeを構築しない、副作用
なし）。Widget側（`_MatchGuidancePanel`、`combat_v1_playable_match_screen.dart`
内）はderiveされた文字列をそのまま表示するのみで、legality・優先順位
判定を一切再実装しない。

- **LegalAction SSOT**: 「PIN可能」「Technique／PIN／End Turnを選択
  できます」等の断定は、必ず`snapshot.legalActions`にそのkindの
  actionが実在する場合のみ行う。独自の合法性判定は一切追加しない。
- **Magic number複製の回避**: Shared HEAT Finisher unlock閾値は
  `snapshot.finisherHeatThreshold`をそのまま参照する（UI側に`200`を
  複製しない）。REST回復量（`CombatV1RulesConfig.restHpRecovery`）は
  snapshotに公開されていないため、DOWN decision guidanceの文言は
  具体的な数値を持たない（既存`_ActionHint`のRest説明と同じ方針）。
- **Hidden information safety**: 参照するのは
  `CombatV1PlayableMatchSnapshot`の公開fieldのみ
  （`cpu.posture`・`sharedHeat`・`finisherHeatThreshold`・
  `legalActions`・Human自身の`recentObservations`）。CPU hand
  contents／hidden Counter／hidden Energy／CPUが次に使える具体的
  Techniqueは、そもそも`CombatV1PlayableOpponentStatus`が保持して
  いないため参照しようがない。「相手はCounterを持っていません」の
  ような推測表示も行わない。

### 68.4 Guidance Priority

優先順位判定は`combatV1PlayableDeriveMatchGuidance`1箇所へ集約する
（Widget側へ条件分岐を散乱させない）。

1. Human入力待ちでない場合（CPU処理中）／試合終了時は`null`（既存
   actor label「CPU行動中」／Result overlayが代替、重複表示しない）。
2. Discard phase → 強制discardの案内（+ DOWNなら「次の行動前に
   Stand Up／Restが必要」、そうでなければ「残したカードは攻撃や
   Counterに使用できます」）。
3. Counter response（`counterResponsePending`） → legalActionsに
   Counter actionが実在する場合のみ「Counterするか、技を受けるか
   選択してください」（+「無効化できます」を補足）。実在しない場合
   （`CombatV1DeclineCounterAction`のみがlegal）は「使用できる
   Counterがありません。技を受けます」——存在しない選択肢を
   提示しない（Review Findings Fix、68.6章）。
4. DOWN decision（`action`かつHuman DOWN） → Stand Up／Restの意味。
5. Action phase（`action`かつHuman STAND） → primaryはlegalActionsに
   実在するkindのみ列挙。secondaryはcontext hintを以下の順で1件のみ
   選ぶ: (a) PIN opportunity → (b) Shared HEAT threshold到達 →
   (c) Opponent DOWN significance（PINが非legalの場合のみ） →
   (d) continued Technique／Energy（このターン中に既にTechniqueを
   使用済み、かつ現在も合法な場合のみ——「1ターン1Technique」の誤解を
   防ぐ。毎ターン表示しないよう、未使用ターンでは出さない）。(b)の
   文言はHEAT条件についてのみ述べ、Finisherを実際に使用できるとは
   断定しない（Review Findings Fix、68.6章）。

### 68.5 Tests（Playable 2A-1）

- **Pure derivation logic**
  （`test/combat_v1/playable_ui/combat_v1_playable_match_guidance_test.dart`、
  新設、22 case）: Human入力待ちでない場合のnull化・Discard（強制／
  DOWN併発で「今すぐ」と誤解させない）・DOWN decision（Rest回復量の
  数値を複製しない）・Counter response（使用可能Counterの有無で
  secondary出し分け）・Action phase primaryがlegalActionsのみを
  反映（PIN／Technique非legal時に案内しない）・context hint優先順位
  （PIN可能＞Finisher解禁＞相手DOWN、同時成立時の絞り込み含む）・
  continued Technique（同ターン内使用済みのみ・別ターンの使用は
  根拠にしない・未使用ターンでは出さない）・hidden information
  regression guard。
- **Widget**
  （`test/combat_v1/playable_ui/combat_v1_playable_match_guidance_widget_test.dart`、
  新設、3 case）: Discard phaseでのprimary/secondary表示、PIN
  opportunity context表示、CPU処理中はguidance widget自体を表示せず
  既存actor label（「CPU行動中」）のみが表示されること。
- **Mobile overflow**
  （既存`combat_v1_playable_mobile_overflow_test.dart`へ追加、新設
  group「Match Guidance（Playable 2A-1 追加）」12 case）:
  guidance文言が最も長くなる代表構成（Discard×DOWN併発／DOWN
  decision／Action phase×PIN opportunity+latest feedback banner
  併発／Counter response）を、320／360／390pxの3幅で検証。
- 既存Playable 1A〜1C.1 test（1744件）はいずれも無変更のままgreen。
  ただし1件、既存
  `combat_v1_playable_feedback_widget_test.dart`の
  `find.textContaining('HPを回復')`（`findsOneWidget`）が、DOWN
  decision guidanceのsecondary文言と字面が衝突したため、guidance側の
  文言を「Rest — HP回復・ターン終了」（既存`_ActionHint`の
  「HPを回復してターン終了」と一字一句一致させない）へ調整した——
  既存test自体は無変更。
- 合計1780件がgreen（既存1744件 + 新設36件）。

## 69. Review Findings Fix（Codex独立レビュー、Major 1件・Minor 1件）

review target: `ce7dfbcbb2844e4d017f59b54a4793d723e3e8e9`。

- **Major — Counter不能時にも存在しないCounter選択を案内**:
  `_counterResponseGuidance`が、`legalActions`に
  `CombatV1CounterAction`が1件も無い（＝`CombatV1DeclineCounterAction`
  のみがlegal）場合でも、primaryが「Counterするか、技を受けるか
  選択してください」のまま変わらず、実際には存在しないCounterという
  選択肢を提示していた。Fix: `hasUsableCounter`（既存判定、SSOTは
  `snapshot.legalActions`のまま変更なし）でprimary自体を分岐させ、
  Counter不能時は「使用できるCounterがありません。技を受けます」の
  みを返す（secondaryも付けない）。
- **Minor — Shared HEAT文言がFinisher全体の使用条件を満たしたように
  読める**: 「FINISHER解禁 — Shared HEATなので双方が使用条件を
  満たせます」は、Finisher card所持・Energy・posture等の他条件や
  CPU側のhidden handまで満たしているかのように誤読されうる。Fix:
  「FINISHER HEAT到達 — Shared HEATなので双方がHEAT条件を満たして
  います」へ変更し、HEAT条件についてのみ述べる（Finisherが実際に
  legalかどうかは断定しない）。

いずれもCombat rule・LegalAction semantics・Guidance derivationの
pure architecture（Snapshot → derivation → view model → Widget）は
無変更。修正はderivation関数内の文言分岐のみ。

# Playable 2A-2 — Win Path / Match Direction（実装追記）

## 70. Match Direction

### 70.1 Objective

独立Player Experience Auditの2つのCritical findingは、

- HPを0にすることと勝利の関係が理解できない（HP0だけでは通常敗北に
  ならない）
- Submissionを狙う方法が理解できない（Submissionは独立ボタンではなく、
  対応Technique成立時に自動解決される）

であり、High findingとして「KOCとPIN progressionが結びつかない」
「優勢／劣勢を構成するresourceの優先順位がない」「DOWNの戦術的意味が
分断されている」「Finisher unlockと実際の決着routeが結びついていない」
が挙げられていた。

Playable 2A-1（68章）は「今何を選べるか」（Current Action Guidance）を
改善したが、「なぜそれをするのか」「どこまで勝利に近づいているのか」
（Win Path / Match Direction）は依然として画面から読み取れなかった。
Playable 2A-2は、新ルールを一切追加せず、既存ルールの因果関係（Snapshot
から公開済みの情報）だけを使って、この「勝利までの道筋」を短い文章で
示す2つ目のスライス。

役割分担（6章のUI Goal・14章「なぜそれをするのか／どこまで勝利に近づいて
いるのか」に対応）:

- Playable 2A-1（Match Guidance）: 「今できること」——phase／pending
  state／postureから「今この瞬間に何を選べるか」。Human入力待ちで
  ない場合（CPU処理中）は表示しない。
- Playable 2A-2（Match Direction）: 「なぜそれをするのか／どこまで
  勝利に近づいているのか」——HP／KOC／Posture／Shared HEATという
  「試合全体の状態」から「勝利までの道筋のどこにいるか」。試合が
  `active`である限りHuman/CPUどちらの手番でも表示する（Guidanceとの
  意図的な挙動差、70.3章）。

### 70.2 Core Rule確認（Win Path図のハードコード回避）

5章のWin Path図（Technique → HP/DOWN → 決着機会 → PIN/Submission →
KOC消費 → 勝利）をそのままUI文言へ焼き直すのではなく、実装前に以下を
Core実装から確認した:

- **PINのカウント／決着**（`combat_v1_pin_rules.dart`
  `determinePinCountResult`）: 防御側KOCが支払える最も有利なカウント
  （1＝KOC3／2＝KOC2／2.9＝KOC1）を返し、**いずれのcostも支払えない
  場合（KOC 0）にのみ`null`を返す**——これが3カウント（PIN決着）となる
  唯一の入力。「KOCが少ないほど不利」ではなく「必要なKOCを支払えない
  ことが決着条件」という62.1章の既存整理と同じ結論を、Direction側でも
  再確認した。
- **SUBMISSIONの突入条件**（`combat_v1_submission_rules.dart`
  `submissionEligible`）: 相手HPが`CombatV1RulesConfig.
  submissionHpThreshold`（既定50）**以下**（0を含む）で宣言可能。
  ESCAPE/GIVE UPは`determineSubmissionOutcome`——防御側KOCが
  `submissionEscapeKocCost`（既定1）を支払えなければGIVE UP。
- **SUBMISSION FINISHERのHP0特例**（`combat_v1_finisher_rules.dart`
  `determineFinisherSubmissionOutcome`）: 相手HPが0の場合、KOC保有量に
  関わらず即GIVE UP——ただしこれは「SUBMISSION FINISHERが**既に**
  成立した後」の特例であり、「HP0だけで試合が決着する」という意味では
  ない（HP0自体が通常決着条件になることはない、14章「HP0の扱い」）。
  Direction側はこの特例を個別にモデル化せず、「HP0だけでは決着しない
  （PIN／Submissionの成立が必要）」という、より広く安全に成り立つ
  一般則のみを文言化した（70.4章 hpZeroClarify）。
- **DIRECT PIN**（`docs/combat_rules_v1.md`8章）: DIRECT PINを持つ技は
  FINISHER限定ではなく技全般に付与でき、TECHNIQUE成功と同一Command内で
  PIN不要のまま自動的にPINへ移行する——通常PIN（`checkPinLegality`、
  相手DOWN必須）とは別経路。`CombatV1LegalAction`にDIRECT PIN用の
  variantは存在しない（外部から選択可能な「手」ではない）ため、
  Directionの文言は「（通常）PINには相手のDOWNが必要」という限定を
  含む形にとどめ、「決着にはDOWNが必須」のような、DIRECT PINと矛盾する
  絶対表現は使わない（70.4章）。

### 70.3 Architecture

```
CombatV1PlayableMatchSnapshot
        ↓
combatV1PlayableDeriveMatchDirection（pure関数、priority判定を集約）
        ↓
CombatV1PlayableMatchDirection（primary/secondary/kind、UI-oriented model）
        ↓
_MatchDirectionPanel（Widget、テキストをそのまま表示するだけ）
```

新設`lib/src/combat_v1/playable_ui/combat_v1_playable_match_direction.dart`
（既存`combat_v1_playable_match_guidance.dart`と同じ「pure UI
formatting helpers」層）。`combat_v1_playable_match_guidance.dart`
自体は無変更——14章の方針どおり、責務が異なるため既存fileを肥大化
させず新規fileへ分離した。

- **LegalAction SSOT**: 「相手のKOCを削るチャンスです」という
  pinOpportunity routeは、`snapshot.legalActions`にPIN actionが実在
  する場合のみ選ばれる。独自の合法性判定は一切追加しない。
- **Magic number複製の回避**: Finisher解禁閾値は既存
  `snapshot.finisherHeatThreshold`をそのまま参照する。Submission
  突入HP閾値は、今回`CombatV1PlayableMatchSnapshot`へ新規field
  `submissionHpThreshold`として追加した
  （`CombatV1RulesConfig.submissionHpThreshold`を`finisherHeatThreshold`
  と全く同じ方法で公開するだけ——Core rule・値そのものは無変更。71章）。
  PINのKOC cost表（1/2/2.9＝KOC3/2/1）は公開しない——「KOC 0＝次に
  成立したPIN/Submissionで決着」という、KOCの構造的下限（負のKOCが
  存在しない）だけを根拠にした判定にとどめ、rules configのcost値を
  複製しない（70.4章decisiveKoc）。
- **Hidden information safety**: 参照するのは`CombatV1PlayableMatchSnapshot`
  の公開fieldのみ（`cpu.hp`・`cpu.koc`・`cpu.posture`・
  `human.posture`・`sharedHeat`・`finisherHeatThreshold`・
  `submissionHpThreshold`・`legalActions`）。`CombatV1PlayableOpponentStatus`
  は構造的にCPU手札の内容・hidden Energy・hidden Counterを保持しない
  ため、参照しようがない。

### 70.4 Direction Priority

優先順位判定は`combatV1PlayableDeriveMatchDirection`1箇所へ集約する。
「勝利までの道筋のどこにいるか」を最も強く示す信号から順に、最大1件
のみを返す（Guidanceの「1 primary + 最大1 secondary」と同じ設計）。

1. `status != active` → `null`（Result overlayが既に決着を説明する
   ため重複表示しない、Guidanceの優先順位1と同じ考え方）。
2. **decisiveKoc**（相手KOC ≤ 0） → 次に成立したPIN／Submissionで
   決着する、最も強い信号（70.2章参照）。「必ず決着になる」という
   言い切りは避け、PIN／Submissionが実際に成立することを前提とした
   表現にとどめる（Review Findings Fix、70.10章）。
3. **pinOpportunity**（`legalActions`にPINが実在＝Human手番かつ
   action phase） → 「相手のKOCを削るチャンスです」——2A-1の「PIN可能
   — 相手のKOCを削り、決着を狙えます」（現在選べる操作）とほぼ同じ
   内容を繰り返さないよう、Review Findings Fixで文言を調整した
   （70.10章）。Guidanceが「今できること」を担当するため、Directionは
   同じ事実を反復せず「KOCが何を意味するか／なぜPINが勝ち筋になるか」
   だけを述べる。
4. **submissionRoute**（相手HPが`submissionHpThreshold`以下・0より
   大） → Submissionが視野に入っていることを示す。KOCによる
   ESCAPE可能性があることも明示し、「HPが下がれば即決着」という
   誤解を避ける。
5. **hpZeroClarify**（相手HP＝0） → 7章の「HP0＝即敗北」誤解防止。
   「HP0ですが、これだけでは決着しません」を明示する。
6. **opponentDownRoute**（相手がDOWN、かつ3.のPINがまだlegalでない
   場合） → 「DOWNからPINへ繋げれば、決着に近づきます」。2A-1の
   「相手はDOWN中 — PINや一部Techniqueにつながる重要な状態です」
   （状態そのものの説明）とは文言を分け、Directionでは「勝利への
   道筋」の観点でのみ述べる（11章の重複回避要件）。
7. **humanDownRisk**（Human自身がDOWN） → 「DOWNは、相手がPINを
   狙うための条件の一つです」。PINの他の条件（そのターン中の技成功・
   ROUGH不使用）までは断定しない。
8. **finisherRoute**（Shared HEATが解禁閾値以上） → 「FINISHERが
   解禁 — 決着ルートの選択肢が広がります」。2A-1の「FINISHER
   HEAT到達」という文言・断定範囲とは変えている（12章「必要以上に
   重複説明しない」要件、70.5章）。
9. **neutral**（上記いずれにも該当しない試合序盤など） → Win Path
   全体像を1文で示す（「Techniqueで攻めてDOWNを作り、決着を
   目指しましょう」）。

CPUの手番中（`isHumanInputRequired == false`）は`legalActions`が空
（9章、CPU手札漏洩防止）のため2.のpinOpportunityへは到達できない
——この場合でも相手がDOWNなら6.のopponentDownRouteへ安全に
fallbackする（「PINが合法」と誤って断定しない）。

### 70.5 情報階層（13章に対応する実装判断）

- **HP = damage / submission context**: HP自体の推移はaction feedback
  （36〜39章、無変更）が担当する。DirectionはHPを「Submission route
  の入口」「HP0＝即敗北ではない」という文脈でのみ扱う。
- **KOC = finish resistance**: 「KOC = life」という単純化はしない
  （8章の禁止事項）。Direction側もKOCの多寡を連続的な優劣として
  語らず、「0＝次に成立したPIN/Submissionで決着」という構造的に安全な
  境界のみを特別扱いする——KOCが1でも10でも、0でない限り同じ
  neutral/他のroute扱いとなる（KOC 1〜9の間で異なる文言を出し
  分けない）。
- **Posture（DOWN）= 直接的な戦術機会**: 相手DOWN（opponentDownRoute）
  ／Human自身のDOWN（humanDownRisk）の両方をカバーし、11章の
  「DOWNを単なる状態異常ではなくPIN opportunity等につながる重要な
  状態として理解できるようにする」を、2A-1と重複しない文言で満たす。
- **HEAT = Finisher unlock**: 12章「HEATが高い＝自分だけ有利ではない」
  を踏まえ、finisherRouteは最も低い優先順位（8番目）に置き、2A-1と
  同じ「HEAT到達」という言い回しは使わない。

### 70.6 Submission HP Threshold の公開（Snapshot拡張）

`CombatV1PlayableMatchSnapshot`へ`submissionHpThreshold`
（`int`、`CombatV1RulesConfig.submissionHpThreshold`をそのまま公開）
を追加した——既存`finisherHeatThreshold`と全く同じ設計（16章の
"public rule constant"の公開パターン）。`CombatV1PlayableMatchController.snapshot`
getterで`_rules.submissionHpThreshold`をそのまま渡すだけであり、
Core rule・`CombatV1RulesConfig`の値・計算ロジックは一切変更していない
——10章「Coreの実際のHP threshold等を調査し、magic numberをUIへ
複製しない」を、2A-1のfinisherHeatThresholdと同じ手段で満たした。

### 70.7 UI / Mobile

`_MatchDirectionPanel`（`combat_v1_playable_match_screen.dart`）は
`_ActorAndRecentPanel`内、Match Guidance・latest feedback banner・
recent action logと同じ高さ上限つき領域（`ConstrainedBox(maxHeight:
132)`）の中へ置いた。この領域は実際にscroll可能——初版実装では
`SingleChildScrollView(physics: NeverScrollableScrollPhysics())`により
scrollそのものを無効化しており、これがReview Findings Fix（70.10章）で
Major findingとして指摘・修正された。以下は初版実装時点の配置判断の
記録。

当初、Shared status panelの直下に独立panelとして常時固定領域へ追加
したところ、320px幅の既存mobile overflow test（Playable 2A-1で追加
した「Action phase（PIN opportunity context + latest feedback banner
併発）」ケース）で新規に`RenderFlex overflowed`が発生した——固定
（非scroll）領域の合計高さが増え、`Expanded`（Technique area）へ
渡る残り高さが不足したため。17章「guidanceがTechnique areaを過度に
押し下げない」の直接的な回帰であり、Match Guidanceと同じ「内容量が
可変な情報は高さ上限つき領域内に置く」という既存の安全弁（40章）へ
Directionも合流させることで解消した——Guidance自体の位置・挙動は
無変更のまま。ただしこの時点では領域内のscrollを`NeverScrollableScrollPhysics`
のまま無効化していたため、「overflowは起きないが、高さ上限を超えた
情報にユーザーが到達できない」という別の問題を残していた（70.10章で
修正）。

役割は明確に分離しつつ、視覚的にも一目で区別できるよう、Direction
のprimaryは`_teal`（新規accent color）、Guidanceは既存white70/38の
ままとした——ただしfont sizeはGuidanceと同じ12/11spに揃え、primary
action（下部bottom bar）より視覚的に強くならないようにしている
（17章）。

320／360／390pxの3幅で、Match Guidance（PIN可能）とMatch Direction
（相手のKOCを削るチャンスです）が同時に最長表示される代表構成、
および相手KOC0（decisiveKoc、primary+secondaryとも表示）の代表構成を
追加検証した（70.8章）。

### 70.8 Tests（Playable 2A-2、Review Findings Fix反映後の最終状態）

- **Pure derivation logic**
  （`test/combat_v1/playable_ui/combat_v1_playable_match_direction_test.dart`、
  新設、32 case）: match start/neutral・opponent HP
  high/low/zero・opponent KOC high/low/zero・opponent STAND/DOWN・PIN
  legal/illegal・HEAT below/at閾値・Human DOWN・Counter response
  phase・CPU turn（Guidanceと異なりnullにしない）・match over
  （null）・priority ordering（KOC0＞PIN legal＞HP低下＞相手DOWNの
  優先順位、同時成立時の絞り込み含む）・hidden information regression
  guard・Submission/HEAT threshold境界値（＝／＋1・－1）・priority
  collision（KOC0+PIN legal・KOC0+Human DOWN・HP0+KOC0・submission
  threshold+opponent DOWN・CPU turn+KOC0・Counter response+脆弱な
  相手、71章「Review Findings Fix」9章対応）。
- **Widget**
  （`test/combat_v1/playable_ui/combat_v1_playable_match_direction_widget_test.dart`、
  新設、5 case）: 通常action phase・相手が脆弱な状態（HP低下→
  submission route）・KOC/決着opportunity（相手KOC0→decisiveKoc）・
  CPU turn（Guidanceと異なり表示し続けることを確認）・試合終了時は
  表示しない。
- **Mobile overflow**
  （既存`combat_v1_playable_mobile_overflow_test.dart`へ追加、新設
  group「Match Direction（Playable 2A-2 追加）」320／360／390pxの
  3幅×2 caseで計6 case + 「Match Direction Reachability（Review
  Findings Fix、Major）」1 case、計7 case）: Match Guidance PIN可能 +
  Match Direction pinOpportunity + latest feedback banner併発、相手
  KOC0（decisiveKoc、secondaryまで表示）の代表構成、および高さ上限を
  超える内容量でも実際にscrollして末尾のrecent logへ到達できることを
  widget rectangleのintersectionで検証（71章「Review Findings Fix」）。
  既存「Match Guidance（Playable 2A-1 追加）」groupも本Phaseの構造
  変更（70.7章）後に再検証し、全ケースgreenのままであることを確認した
  （このgroup追加時点で一度`RenderFlex overflowed`回帰を検出し、
  70.7章の対応で解消している）。
- `test/combat_v1/playable/`・`test/combat_v1/playable_ui/`配下
  （既存164件 + 新設44件 = 208件）が全件green
  （`flutter test test/combat_v1/playable test/combat_v1/playable_ui`）。
  既存test（`combat_v1_playable_ui_test_fixtures.dart`の`testSnapshot`
  へ`submissionHpThreshold`を既定値50付きで追加した以外）は無変更の
  ままpassする。
- リポジトリ全体`flutter test`・`flutter analyze`の最終結果は71章
  「Validation」に記載する。

### 70.9 Scope / Non-Scope（2A-2）

**Scope**: 70章の`combat_v1_playable_match_direction.dart`（新設
pure derivation）・`_MatchDirectionPanel`（新設widget）・
`CombatV1PlayableMatchSnapshot.submissionHpThreshold`（既存
`finisherHeatThreshold`と同型の新規field）・対応するpure/widget/mobile
test・本ドキュメント更新。

**Non-Scope（今回変更しない、2章の全項目を再確認済み）**: Combat V1
ルール変更・HP defeat rule追加・KO rule追加・KOC計算変更・PIN count
計算変更・Submission条件変更・Finisher条件変更・Shared HEAT rule
変更・Energy rule変更・Draw/Discard rule変更・Counter rule変更・PIN
Cards rule変更・LegalAction semantics変更・Core Engine変更・CPU AI
変更・wrestler/technique data変更・新resource／新meter追加・勝率
表示・AIによる推奨カード・hidden information利用（CPU hand/Energy/
Counter推測を含む）。Technique card自体へのSubmission badge追加
（Playable 2A-3予定）にも着手していない。

## 71. Review Findings Fix（Playable 2A-2独立レビュー、Major 1件・Minor 2件）

review target: `6eec4a06629bdb9654599d3dd2ea5e237d1c8c52`。CHANGES
REQUIREDの独立レビュー結果を受け、以下のみを修正した——Playable 2A-3
には着手せず、Combat Core／rule／LegalAction semantics／CPU AI／
wrestler・technique data／dependenciesはいずれも無変更のまま。

### 71.1 Major — Reachable Information（Match Direction / feedback / recent logが到達不能）

**問題**: `_ActorAndRecentPanel`内の高さ上限つき領域
（`ConstrainedBox(maxHeight: 132)`）が、`SingleChildScrollView(physics:
const NeverScrollableScrollPhysics())`によりscrollそのものを無効化して
いた。Match Direction（primary/secondary）・latest feedback banner・
recent action logの合計content量が132pxを超えても`RenderFlex
overflowed`は起きないが（70.7章の初版判断どおり）、ユーザーは
末尾の情報へ一切到達できなかった——「overflow exceptionが無い」ことと
「表示された情報に実際に到達できる」ことは別問題であるという指摘
どおりの回帰だった。

**Fix**: `_ActorAndRecentPanel`を`StatelessWidget`から`StatefulWidget`
へ変更し、Stateが保持する`ScrollController`を`SingleChildScrollView`
（`physics`指定を削除——既定の可動physicsに戻す）と`Scrollbar`
（`thumbVisibility: true`）へ接続した。

- **旧構造**: `ConstrainedBox(maxHeight: 132)` →
  `SingleChildScrollView(physics: NeverScrollableScrollPhysics())` →
  `Column([...])`。
- **新構造**: `ConstrainedBox(maxHeight: 132)` → `Scrollbar(controller:
  _scrollController, thumbVisibility: true)` →
  `SingleChildScrollView(key: ..., controller: _scrollController)` →
  `Column([...])`。
- **なぜ情報へ到達可能になったか**: 高さ上限（132px）自体は変更して
  いない（4章「Do Not Solve by Simply Increasing Height」——固定値を
  増やすだけの対応は根本解決にならないため採用しなかった）。
  かわりに、上限を超えた分の内容を実際にscrollできるようにすること
  で、content量（長文・feedback・4件のrecent log・320px幅）が
  どれだけ増えても、末尾まで到達可能な構造にした。`_scrollController`
  はWidgetのState（`_ActorAndRecentPanelState`）が生存する間保持され、
  毎buildごとに再生成されないため、`Scrollbar(thumbVisibility: true)`
  が要求する「ScrollPositionにattachされたScrollController」を安定
  して満たす。
- **outer scroll / Technique areaとの競合確認**: この領域は画面上、
  Technique area（`Expanded` + 独立した`SingleChildScrollView`）とは
  Columnの兄弟要素であり、親子関係にない（`_ActorAndRecentPanel`は
  `Expanded`の外側）。そのため、この領域を実際にscroll可能にしても、
  Technique area側のscroll gestureとは競合しない——3章「Preferred
  approach」が想定した「まずは内部領域を縦scroll可能にする最小修正」
  がそのまま安全に適用できるケースだった。
- **Scroll UX**: `Scrollbar(thumbVisibility: true)`により、常時
  visibleなscrollbar thumbを表示し、ユーザーが「この領域はscroll
  可能」だと視覚的に把握できるようにした（5章）。既存デザイン
  （padding・font size・panel構成）は変更していない。

**Major Regression Test**（実際のwidget testによる証明）:
`test/combat_v1/playable_ui/combat_v1_playable_mobile_overflow_test.dart`
の新設group「Match Direction Reachability（Review Findings Fix、
Major）」（1 case、320px幅）:

- Direction primary＋secondaryとも表示される代表状態（相手KOC0）・
  複数行のlatest feedback（damage/HP/posture/HEATすべて変化）・
  recent action log最大代表数（4件）を組み合わせ、`ConstrainedBox`の
  132px上限を確実に超える構成にした。
- **Before scroll**: `tester.getRect`で取得した末尾のrecent log entry
  （`combat_v1_playable_recent_log_item_3`、新設key）のRectが、
  scrollable viewport（`combat_v1_playable_actor_recent_scroll`、
  新設key）のRectと交差していない（`item.bottom > viewport.bottom`）
  ことを確認——この確認自体が「そもそもscrollが必要な状況を
  再現できているか」のテスト前提チェックを兼ねる。
- **User scroll**: `tester.drag`でscrollable領域を上方向へdragし、
  `tester.pumpAndSettle()`。
- **After scroll**: 同じ末尾recent log entryのRectが、viewportの
  Rectと`overlaps`（交差）することを確認——`tester.takeException() ==
  null`だけに頼らず、実際に情報へ到達できたことをrectangleの
  intersectionで直接検証した。

### 71.2 Minor — PIN Guidance / Direction Duplication

**問題**: PIN legal時、Guidance「PIN可能 — 相手のKOCを削り、決着を
狙えます」とDirection「PINで相手のKOCを削りましょう」/「KOCが尽きる
と、PINやSubmissionで決着します」がほぼ同じ内容を繰り返していた。

**Fix**: Guidanceの役割（「今できること」＝PINが選べるという
legalActions SSOTに基づく事実）はそのまま維持し、Directionの文言を
「KOCという勝ち筋resourceの意味」だけに絞った。

| | Before | After |
| --- | --- | --- |
| Direction primary | `PINで相手のKOCを削りましょう` | `相手のKOCを削るチャンスです` |
| Direction secondary | `KOCが尽きると、PINやSubmissionで決着します` | `KOCが尽きると、成立したPINやSubmissionで決着します` |
| Guidance（維持） | `PIN可能 — 相手のKOCを削り、決着を狙えます`（無変更） | 同左 |

責務分離: Guidance＝「PINが今選べる」という事実（legalActions
SSOTのまま、Direction側では独自に再計算しない）。Direction＝「なぜ
それが勝ち筋になるか」（KOCというresourceの意味・決着へのつながり）。
PIN legalityの判定・KOC減少量の独自計算はいずれも追加していない
——`combatV1PlayableDeriveMatchDirection`のpinOpportunity分岐は
既存どおり`snapshot.legalActions`のみを参照する（71.1章の構造変更・
本Fixのいずれもこの分岐のlegality判定ロジック自体は無変更）。

### 71.3 Documentation Wording

「次のPIN／Submissionが必ず決着」という、PIN／Submissionの成立を
前提としない言い切りが、code comment・design doc双方に残っていた
（KOC 0は「PIN／SUBMISSIONが成立した場合に防御側が支払えない」状態
であり、それ自体が試合を自動的に終わらせるわけではない）。

- `lib/src/combat_v1/playable_ui/combat_v1_playable_match_direction.dart`:
  decisiveKocのcode comment・UI文言（secondary）を「次に成立した
  PIN／SUBMISSIONは決着になる」という、成立を前提とした表現へ修正。
- 本ドキュメント（70.3・70.4・70.5・70.7・70.8章）の該当箇所も同様に
  修正した。
- UI文言自体（decisiveKocのsecondary）も「次のPINまたはSubmissionが
  決着のチャンスです」→「次に成立したPINまたはSubmissionで決着
  します」へ変更——UI文言より強い断定をdocumentationに残さない
  （8章）方針を、UI文言自体の精度向上と合わせて満たした。

### 71.4 Boundary Tests / Priority Collisions

9章の要求どおり、Core上到達可能な組み合わせのみを
`test/combat_v1/playable_ui/combat_v1_playable_match_direction_test.dart`
へ追加した（thresholdはsnapshot構築時に使った同一のlocal変数を
assertion側でも再利用し、Coreのmagic numberをテストロジックへ
独自に複製していない）。

- **Submission threshold**: `HP == submissionHpThreshold`
  （submissionRouteになる）／`HP == submissionHpThreshold + 1`
  （ならない）。
- **HEAT threshold**: `sharedHeat == finisherHeatThreshold`
  （finisherRouteになる）／`sharedHeat == finisherHeatThreshold - 1`
  （ならない）。
- **Priority collisions**（6 case）: `KOC 0 + PIN legal` →
  decisiveKoc／`KOC 0 + Human DOWN` → decisiveKoc／`HP 0 + KOC 0` →
  decisiveKoc（hpZeroClarifyより上位）／`submission threshold +
  opponent DOWN` → submissionRoute（opponentDownRouteより上位）／
  `CPU turn + KOC 0` → decisiveKoc（CPUの手番でも表示）／`Counter
  response + 脆弱な相手（HP低下）` → submissionRoute（phaseに
  関わらず計算される）。

いずれも実装済みpriority（70.4章の順序）どおりの結果であることを
確認した——priority順序自体（decisiveKoc＞pinOpportunity＞
submissionRoute＞hpZeroClarify＞opponentDownRoute＞humanDownRisk＞
finisherRoute＞neutral）は本Fixで変更していない。

### 71.5 HP/KOC Rule Wording（維持確認）

独立レビューでrule correctness自体はPASS。本Fixでも以下の意味は
一切変更していない（10章）:

- HP: HP 0だけでは通常決着しない（hpZeroClarify、decisiveKocに
  優先されない限り表示される）。
- KOC: KOC 0は「PIN／Submissionが成立したとき」に防御側が支払える
  costが無くなる状態（＝最終抵抗消失）であり、それ自体が試合を
  終わらせるものではない（71.3章の文言修正で明確化）。
- Submission: HP threshold以下であることだけをもって、Submission
  actionが現在使用可能とは断定しない（submissionRouteの文言は
  「視野に入っている」に留め、legalActionsの断定は行わない）。
- PIN: 現在PIN可能かどうかは引き続き`snapshot.legalActions`のみを
  SSOTとする（71.2章のpinOpportunity文言修正後も判定ロジックは
  無変更）。

### 71.6 CPU Turn / Hidden Information（維持確認）

Match DirectionはCPU turn中も表示され続ける（70.1・70.4章の既存
設計を維持）。本Fixで新しいhidden information依存は追加していない
——参照fieldは70.3章に記載の公開fieldのみのまま
（`submissionHpThreshold`追加を含め、CPU hand／CPU Energy／CPU
Counter／CPU Finisher possession／deck order／next draw／AI internal
stateはいずれも参照していない）。71.4章の追加testでも、CPU turn中の
decisiveKoc表示が「Humanが今操作可能に見える命令形」を含まないこと
（primary文言はUI表示状態の説明のみで、Counter/PIN等の具体的な
button操作を指示する文言を含まない）を確認済み。

### 71.7 Validation

- `flutter analyze`: No issues found。
- `flutter test test/combat_v1/playable test/combat_v1/playable_ui`:
  既存197件 + 新設11件（reachability regression test 1件・boundary/
  priority collision test 10件） = **208件**全件green。
- `flutter test`（リポジトリ全体）: **1825件**全件green（前回報告
  1814件 + 本Fix新設11件）。
- `flutter build web --release --base-href /one_night_match/
  --no-web-resources-cdn`: 成功。

### 71.8 Changed Files（本Fix）

- `lib/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart`:
  `_ActorAndRecentPanel`をStateful化しscroll可能にした（71.1章）。
  recent log各itemへindexed keyを追加（reachability testで安定して
  末尾要素を特定するため）。
- `lib/src/combat_v1/playable_ui/combat_v1_playable_match_direction.dart`:
  pinOpportunity・decisiveKocの文言・code commentを修正（71.2・
  71.3章）。derivationのpriority判定ロジック自体は無変更。
- `test/combat_v1/playable_ui/combat_v1_playable_match_direction_test.dart`:
  新wordingに合わせたassertion更新（PIN文言重複を検出するguard追加）・
  boundary/priority collision test追加（71.4章）。
- `test/combat_v1/playable_ui/combat_v1_playable_mobile_overflow_test.dart`:
  reachability regression test追加（71.1章）。
- `docs/design/combat_v1_playable_match_ui.md`: 本章（71章）追加、
  70章内の該当wording修正（71.3章）。

### 71.9 Scope Verification

Combat rule変更: NO / Core変更: NO / LegalAction semantics変更: NO /
CPU AI変更: NO / data変更: NO / dependencies変更: NO / hidden
information exposure変更: NO（71.6章）。

# Playable 2A-3 — Technique / Counter Decision Readability（実装追記）

## 72. Purpose

Playable 2A-1（「今できること」）・2A-2（「何を目指すか」）に続き、
2A-3の目的は「Technique を選ぶ時点、および Counter する時点で、その
カード／攻撃が試合の勝ち筋にどう関係するか理解できる」状態にすること
（UX / Information Architectureフェーズ、Combat ruleの追加・変更は
行わない）。

具体的には:

- Technique cardを見た時点で「単なるダメージ技か」「DOWNを作る技か」
  「PINへ直接つながるか」「Submissionを狙う技か」「FINISHERなら何で
  決着を狙うか」を理解できるようにする。
- Counter応答時に「Counterしなかった場合に何が起こる可能性があるか」
  （incoming attackのDMG・HEAT・posture結果・特殊trait）を理解できる
  ようにする。

## 73. Existing Model Audit（実装前調査結果）

事前調査で、以下の情報が既にCore/data層（`CombatV1Technique`/
`CombatV1PendingAttack`/`CombatV1Counter`）のSSOTとして存在すること
を確認した:

| 情報 | SSOT | Playable snapshot/UIへの露出（2A-2時点） |
|---|---|---|
| Direct PIN | `CombatV1Technique.directPin` | Hand card経由で技術的にはアクセス可能だが、UIに未反映 |
| Submission Hold | `CombatV1Technique.submissionHold` | 同上 |
| Finisher resolution type | `CombatV1Technique.finisherType` | 同上（FINISHER badgeはcategoryのみで判定、typeを見ていなかった） |
| Technique family | `CombatV1Technique.family` | Hand cardには存在するがUI未表示 |
| ROUGH（attribute） | `CombatV1Technique.attribute == rough` | attribute表示（打/関/投/飛/ラフ/＊）はあるが、ROUGH固有の意味（PIN不可・次ターン制限）は未説明 |
| Counter family/group matching | `techniqueFamilyMatchesCounter`（`combat_v1_counter_rules.dart`、pure function） | legality判定にのみ使用、UI説明なし |
| pending attackのHEAT gain | `CombatV1PendingAttack.heatGain` | **snapshotに未露出**（`CombatV1PlayablePendingAttackView`に field 無し） |
| pending attackのdirectPin/submissionHold/finisherType | `CombatV1PendingAttack`の同名field | **snapshotに未露出** |

つまり「Core/dataには存在するがPlayable snapshot/UIへ出ていない情報」
は、`CombatV1PlayablePendingAttackView`のHEAT/directPin/submissionHold/
finisherTypeの4 fieldのみだった（Technique側は既にHand card経由で
公開済みだったため、snapshot自体の拡張は不要）。この4 fieldのみを
最小限追加し、それ以外は既存の公開済みデータを新しいUI widgetへ
反映するだけで実装した（16章「Combat ruleを再実装しない」方針）。

Core/data → snapshot → UIの流れ:

```
CombatV1Technique / CombatV1PendingAttack（Core SSOT、directPin/
submissionHold/finisherType/family/attributeを保持）
    ↓
CombatV1PlayableHandCard.technique（既存、無変更）／
CombatV1PlayablePendingAttackView（4 field追加）
    ↓
combat_v1_playable_technique_traits.dart（pure derivation——
FINISHERのeffective directPin/submissionHold優先順位・badge文言・
family/group表示名・Counter prevents summaryを算出するだけで、
legality/damage判定は一切行わない）
    ↓
_TechniqueTraitBadges / _PendingAttackSummary / _HandCardTile（widget）
```

## 74. Technique Card — Decision Traits

Technique cardへ、勝敗判断上重要なtraitを短いbadgeとして追加した
（Tier 1情報、5〜6章）。

- **DIRECT PIN**: `combatV1PlayableTechniqueHasEffectiveDirectPin`が
  trueの非FINISHER技。Tooltip: 「成立時、自動でPINへ移行します
  （通常のPIN選択とは別の経路です）」——通常PINのLegalAction判定と
  混同しない文言に留める（9章 DO NOT INVENT LEGALITY）。
- **SUBMISSION**: `combatV1PlayableTechniqueHasEffectiveSubmissionHold`が
  trueの非FINISHER技。Tooltip: 「成立後、相手HPが{閾値}以下だと
  Submission判定に自動移行します（Escapeされる場合があります）」
  ——「今Submissionできる」「これでギブアップ」等の過剰断定を避ける
  （8章 SUBMISSION WORDING）。
- **ROUGH**: `technique.attribute == rough`。Tooltip: 「このターン
  使用するとPINできなくなります。成立させてターンを終えると、相手の
  次ターンTECHNIQUEを最大1枚に制限します」（15章・15.1章の2つの
  判定基準を両方明示）。
- **FINISHER / FINISHER · PIN / FINISHER · SUBMISSION**:
  `category == finisher`の場合、`finisherType`に応じた合成badge
  （`combatV1PlayableFinisherResolutionBadgeLabel`）。FINISHERの
  場合、単独のDIRECT PIN/SUBMISSION badgeとは重複表示しない
  （`_resolvePendingAttack`のeffectiveDirectPin/effectiveSubmissionHold
  と同じ優先順位、`_effectiveDirectPin`/`_effectiveSubmissionHold`
  helperで再現）。

Badgeは`isUsable`（現在使用可能か）とは完全に独立して表示される——
HEAT未到達で現在使用不可なFINISHERでも、trait badge自体は「成立
した場合の性質」を示すものとして表示され続ける（22章「trait表示と
usable/unusableの混同防止」、widget testで明示的に確認済み）。

## 75. Information Priority（Tier）

Technique cardへ全metadataを常時詰め込まず、優先順位を明確化した:

- **Tier 1（勝敗ルート）**: DIRECT PIN・SUBMISSION・FINISHER
  resolution・ROUGH——常時badgeとしてcategory labelの直後（DMG/HEAT
  等より前）に表示。
- **Tier 2（即時結果）**: DMG・HEAT・posture結果——既存表示のまま。
- **Tier 3（legality/resource）**: Energy比較・required posture・
  usability——既存表示のまま。
- **Tier 4（advanced information）**: Technique family・Counter
  taxonomy——Technique hand cardには常時表示しない（mobile card過密化
  回避、6章）。Familyは代わりにCounter Prompt Sheet側（76章）で、
  「このCounterが現在のpending攻撃をどう返せるか」という実用的な
  文脈でのみ表示する。

## 76. Counter Response — Incoming Attack Summary

`_PendingAttackSummary`（Counter Prompt Sheet内）へ以下を追加した:

- **HEAT gain**: 既存のattribute/DMG/posture結果行へ追記
  （`pending.heatGain`）。
- **Direct PIN / SUBMISSION / FINISHER resolution / ROUGH badge**:
  Technique cardと同じ`_TraitBadge`コンポーネントを再利用
  （`combatV1PlayablePendingAttackHasEffectiveDirectPin`/
  `HasEffectiveSubmissionHold`/`IsRough`、74章と同じ優先順位・文言）。
- **Counter Success Meaning**（`combatV1PlayableCounterPreventsSummary`）:
  「Counterが成立すると、この技のDMG・HEAT・状態変化を防げます」
  （trait無しの場合）に加え、DIRECT PINなら「自動PINへの移行」、
  SUBMISSION Holdなら「Submissionへの移行条件を満たすこと」も防げる
  ことを追記する。文言は`combat_v1_engine.dart` `playCounter`の実装
  コメント「攻撃効果は無効、DMG/HEAT/posture変更なし」（7.1章）と
  一致することを確認済み——Counterが成立すれば技自体が不成立になる
  ため、技成立を前提とする自動遷移（DIRECT PIN／SUBMISSION自動移行）
  も一切発生しない、という既存Core semanticsをそのまま言い換えた
  だけであり、新しいCombat ruleではない。

usable Counter cardには「対応: {family/group label}」を追加した
（`combatV1PlayableCounterFamilyMatchLabel`、Core純粋関数
`techniqueFamilyMatchesCounter`をそのまま使用——このCounterが
family一致で返せるか、group一致で返せるかを表示するだけで、新しい
legality判定は追加していない）。

## 77. LegalAction Boundary（維持）

Counter unavailable時（`legalActions`にCounter actionが存在しない）
の既存挙動——「使用できるCOUNTERカードがありません。技を受けます」
——は無変更のまま維持した。新しいtrait badge表示によって「Counter
可能に見える」誤認を防ぐため、trait badgeはあくまでincoming attack
（既に宣言済みのpublic情報）の性質を説明するだけであり、Counter
actionの可否判定には一切関与しない。widget testで、Counter
unavailable時でもtrait badge（incoming attack情報）が引き続き読め、
かつCounter選択肢が案内されないことを明示的に確認した（77章、
`combat_v1_playable_2a3_readability_test.dart`）。

## 78. Hidden Information Boundary（維持）

新規参照fieldは以下のみ——いずれも「宣言済みTechnique/COUNTERの
静的metadata」であり、印刷されたカードテキストに相当する既に公開
された情報（16章「宣言済みの攻撃カードは既に両者へ公開された情報」）:

- `CombatV1PendingAttack.heatGain`/`directPin`/`submissionHold`/
  `finisherType`（新規snapshot field 4件）。
- `CombatV1Counter.counterableFamilies`/`counterableGroups`
  （既存、印刷されたカードテキスト）。
- `techniqueFamilyMatchesCounter`（Core純粋関数、表示専用の再利用）。

CPU hand contents／CPU Counter cards／CPU Energy／CPU future action／
CPU Finisher possession／deck order／next draw／AI internal
evaluationはいずれも一切参照していない
（`CombatV1PlayableOpponentStatus`は無変更）。

## 79. Mobile Strategy

Technique hand cardの固定height（`_HandRow`のSizedBox）を232px→268px
へ拡張し、trait badge行の追加分を吸収した。Counter hand専用
SizedBox（168px、`_CounterPromptSheet`）は対象外——counter card自体は
trait badge行を持たないため（family match行は1行のみ追加、既存の
`SingleChildScrollView(physics: NeverScrollableScrollPhysics())`の
余白内に収まる）。

320/360/390px幅での代表ケース（複数の重要traitを持つTechnique
card・trait badge付きFINISHER card・HEAT/trait/prevents hint込みの
Counter応答・特殊決着技のCounter応答）でoverflowが無いこと、および
primary control（End Turn button・decline button）がviewport内に
あってhit-testableであることを、`combat_v1_playable_mobile_overflow_test.dart`
の新設groupで確認した（24章）。

既存test（`combat_v1_playable_match_screen_test.dart`のDiscard
シナリオ）は、hand card heightの拡張により既定test viewport
（800×600）でtap対象が一時的にExpanded/scrollview領域の下端を
越えたため、`tester.ensureVisible`を追加して対応した——実機で
ユーザーがscrollしてから操作するのと同じ挙動であり、assertion自体は
無変更。

## 80. Deferred（27章と対応、今回やらない）

- full Technique encyclopedia / full family taxonomyチュートリアル。
- 全unusable Counter理由の完全な列挙。
- CPU hand prediction・推奨AI・best move highlighting・win
  probability・deck probability。
- wrestler-specific strategy・新tutorial engine・card redesign。

これらは必要であれば後続Phaseの対象とする。

## 81. Tests（Playable 2A-3）

- **Pure derivation**
  （`test/combat_v1/playable_ui/combat_v1_playable_technique_traits_test.dart`、
  新設、28 case）: FINISHER優先順位ルール（technique自身の
  directPin/submissionHoldとfinisherTypeが矛盾する構成での優先順位
  含む）・ROUGH判定・FINISHER resolution badge label・pending
  attack側の同じ優先順位・SUBMISSION/DIRECT PIN/ROUGH wordingの安全性
  （過剰断定フレーズが含まれないことを明示的に検証）・Counter family
  match label（family一致／group一致／不一致）・Counter prevents
  summary（trait有無での文言分岐）・family/group表示label。
- **Widget**
  （`test/combat_v1/playable_ui/combat_v1_playable_2a3_readability_test.dart`、
  新設、13 case）: Technique cardのDIRECT PIN/SUBMISSION/ROUGH/
  FINISHER合成badge表示・trait badgeがisUsableと独立して表示される
  こと・通常技はbadge非表示・Counter available時のDMG/HEAT/prevents
  hint/decline可視性・Direct PIN incoming/Submission incoming/
  Finisher incomingそれぞれのbadge表示・Counter unavailable時の
  regression safety（Counter選択非案内・incoming情報可読性・decline
  進行明確性）・usable Counter cardのfamily match表示。
- **Mobile regression**
  （`combat_v1_playable_mobile_overflow_test.dart`拡張、新設12
  case）: 320/360/390px幅で、複数重要trait併発Technique card・
  trait badge付きFINISHER card・長いCounter incoming summary・
  特殊決着技Counter応答のoverflow無し、およびprimary control
  reachability。
- 既存Playable 1A〜2A-2 test（1825件）は、`CombatV1PlayablePendingAttackView`
  新規必須field 4件へ`testPendingAttack`ヘルパー経由で既定値
  （technique由来）を補完する形でfixtureのみ更新——assertion自体は
  1件（Discardシナリオのtap、79章）を除き無変更。

## 82. Validation

- `flutter analyze`: No issues found。
- `flutter test test/combat_v1/playable test/combat_v1/playable_ui`:
  既存208件 + 新設53件 = **261件**全件green。
- `flutter test`（リポジトリ全体）: **1878件**全件green（Playable
  2A-2 baseline 1825件 + 本Phase新設53件）。
- `flutter build web --release --base-href /one_night_match/
  --no-web-resources-cdn`: 成功。

## 83. Changed Files（Playable 2A-3）

- `lib/src/combat_v1/playable/combat_v1_playable_match_snapshot.dart`:
  `CombatV1PlayablePendingAttackView`へ`heatGain`/`directPin`/
  `submissionHold`/`finisherType`の4 field追加（73章）。
- `lib/src/combat_v1/playable/combat_v1_playable_match_controller.dart`:
  `_buildPendingAttackView`で上記4 fieldを`CombatV1PendingAttack`
  からそのまま複製。
- `lib/src/combat_v1/playable_ui/combat_v1_playable_technique_traits.dart`
  （新設）: pure trait derivation/formatter（74〜76章）。
- `lib/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart`:
  `_TechniqueTraitBadges`/`_TraitBadge`widget新設、`_HandCardTile`へ
  trait badge・Counter family match表示を追加、`_PendingAttackSummary`
  へHEAT/trait badge/prevents summaryを追加、hand row height
  232px→268pxへ拡張（74・76・79章）。
- `lib/src/combat_v1/playable_ui/combat_v1_playable_match_guidance.dart`:
  古い「Playable 2A-4予定」注記を、実際に2A-3で実装した旨へ更新
  （doc comment修正のみ、判定ロジック無変更）。
- `test/combat_v1/playable_ui/combat_v1_playable_ui_test_fixtures.dart`:
  `testPendingAttack`が新規4 fieldをtechniqueから補完するよう更新。
- `test/combat_v1/playable_ui/combat_v1_playable_technique_traits_test.dart`
  （新設）・`combat_v1_playable_2a3_readability_test.dart`（新設）・
  `combat_v1_playable_mobile_overflow_test.dart`（拡張）: 81章参照。
- `test/combat_v1/playable_ui/combat_v1_playable_match_screen_test.dart`:
  Discardシナリオへ`ensureVisible`追加（79章）。
- `docs/design/combat_v1_playable_match_ui.md`: 本章（72〜84章）追加。

## 84. Scope Verification

Combat rule変更: NO / Core resolution変更: NO / LegalAction
semantics変更: NO / CPU AI変更: NO / wrestler data変更: NO /
technique data変更: NO / dependency追加: NO / hidden information
exposure変更: NO（78章）。

# Playable 2A-3 Review Findings Fix（実装追記）

独立レビューでCHANGES REQUIREDとなった3件（Major 1・Minor 2）を、
2A-3 branch上でCore/rules/LegalAction semanticsを一切変更せず修正した。

## 85. [Major] DIRECT PIN Wording — DOWN条件の欠落

**問題**: 74章で導入したDIRECT PIN trait detailの文言
「成立時、自動でPINへ移行します」は、Core semanticsより強すぎた。

**Core再確認**（`combat_v1_engine.dart` `_resolvePendingAttack`）:
`effectiveDirectPin`が真でも、自動PINへ移行するのはTechnique解決後に
相手が`CombatV1WrestlerPosture.down`である場合のみ
（`if (effectiveDirectPin && next.opponent.posture ==
CombatV1WrestlerPosture.down)`）。DOWNにならない場合（例:
`resultOpponentState: null`でSTANDのまま等）は、成立してもPINへは
移行しない。

**修正後の文言**（`combatV1PlayableDirectPinTraitDetail`）:

> 成立後、相手がDOWNなら自動でPINへ移行します（通常のPIN選択とは別経路です）

以下4点の意味を維持している:
1. Technique成立が前提
2. 解決後に相手がDOWNである条件
3. その場合にのみ自動PINへ移行
4. 通常のPIN LegalActionとは別経路（現在PIN actionがlegalであることと
   混同しない）

通常Direct PIN（`CombatV1Technique.directPin: true`の非FINISHER技）と
`finisherType == directPin`（FINISHER）の両方が、この同じ文言を共有する
——`combatV1PlayableDirectPinTraitDetail()`は両方の呼び出し箇所
（Technique card・Counter Prompt Sheet双方の、DIRECT PIN単独badge・
FINISHER · PIN合成badgeいずれも）から共通で呼ばれるため、修正は
1箇所で完結し、通常Direct PINとFINISHER Direct PINへ同時に適用される。

### 85.1 Tests

`combat_v1_playable_technique_traits_test.dart`（pure）:

- 修正後文言が「DOWN」「自動でPIN」「別経路」を含み、旧文言（DOWN条件
  無し）とは完全一致しないことを確認。
- **A**: `directPin: true`・`resultOpponentState`省略（＝成立しても
  DOWNを保証しない）非FINISHER技でも、DIRECT PIN traitは
  `combatV1PlayableTechniqueHasEffectiveDirectPin`でtrueのまま
  （trait表示自体は維持）——detail文言がDOWN条件を含むことを確認。
- **B**: `finisherType == directPin`かつDOWNを保証しない構成でも、
  同じDOWN条件付きdetail文言が適用されることを確認
  （`FINISHER · PIN`badge label自体は変わらない）。
- **C**: DOWNになる（`resultOpponentState: down`の）Direct PIN技でも
  trait表示自体は消えないことを確認。

`combat_v1_playable_2a3_readability_test.dart`（widget）:

- Direct PIN incoming（Counter応答）のDIRECT PIN badge Tooltipが
  「DOWN」を含むことを確認。

## 86. [Minor] ROUGH + Counter — 非対称性の説明不足

**Core再確認**（`combat_v1_engine.dart`、15.1章）:

- **A. 宣言時点で発生**（防げない）: 攻撃側の「このターンPIN宣言
  不可」（`roughTechniqueUsedThisTurn`）は、ROUGH技を宣言した時点で
  確定し、Counterされても取り消されない
  （`declareTechnique`内で無条件更新）。
- **B. 成立後に発生**（Counterで防げる）: 相手の次ターンTECHNIQUE
  最大1枚制限（`roughTechniqueLimitActive`）は`lastSuccessfulTechnique`
  ベース（`_advanceTurnAfterEnd`）——Counterが成立すればこの技は
  そもそも成立せず`lastSuccessfulTechnique`が更新されないため、
  次ターン制限のトリガー自体が発生しない。

**修正**: 新規pure function`combatV1PlayableRoughCounterAsymmetryNote()`
（`combat_v1_playable_technique_traits.dart`）を追加し、ROUGH incoming
技のCounter Prompt Sheet（`_PendingAttackSummary`）へ、既存の
`combatV1PlayableCounterPreventsSummary`（DMG/HEAT/状態変化/
DIRECT PIN/SUBMISSIONの完全無効化semantics）とは別行で表示する:

> 相手はこのターン、既にPINを宣言できません（宣言時点で確定・
> Counterしても変わりません）。次ターンのTECHNIQUE制限（最大1枚）は
> Counterで防げます

「ROUGHの全効果を防げる」という誤解を避けるため、防げるもの
（次ターン制限）と防げないもの（このターンのPIN不可）を1文ずつ
明示する。widget key: `combat_v1_playable_pending_rough_counter_note`
（ROUGH incoming時のみ表示、非ROUGH incomingでは`findsNothing`）。

### 86.1 Architecture

既存のpure derivation構造（`combat_v1_playable_technique_traits.dart`）
を維持し、新しいCombat ruleの追加・Counter resolutionの変更は一切
行っていない——Core（`_advanceTurnAfterEnd`のROUGH次ターン制限判定・
`declareTechnique`の`roughTechniqueUsedThisTurn`確定タイミング）が
既に持つ2つの異なる判定基準をそのまま言い換えただけ。入力は既に
public/hidden-safeな`pending attack`のROUGH判定
（`combatV1PlayablePendingAttackIsRough`）のみ。

### 86.2 Tests

`combat_v1_playable_technique_traits_test.dart`（pure、3 case）:

- 次ターンTECHNIQUE制限を「防げます」と言及。
- このターンのPIN制限は「既に」発生済みで「変わりません」（Counterで
  防げない）と言及。
- 「すべて防」「全て防」「ROUGHを無効」等、全効果防止と読める断定
  文言を含まない。

`combat_v1_playable_2a3_readability_test.dart`（widget、2 case）:

- ROUGH incoming: `combat_v1_playable_pending_rough_counter_note`が
  表示され、「次ターン」「既に」を含む。
- 非ROUGH incoming: 同widgetが表示されない（`findsNothing`）。

## 87. [Minor] Mobile Visibility Tests — 実可視性検証の不足

**問題**: 既存mobile testは`tester.takeException() == null`のみで
「overflowしない」ことしか検証しておらず、「情報が実際に読める／
押せる」ことを保証していなかった（Playable 2A-2で発生した
regressionと同種の穴）。

**修正**: `combat_v1_playable_mobile_overflow_test.dart`へ、実座標
（`tester.getRect`）ベースのintersection検証を追加した。

### 87.1 実際のclip viewportをkeyで公開

Match Screenの本体（`Expanded` + `SingleChildScrollView`でTechnique
areaを包む部分）へ`combat_v1_playable_technique_area_scroll`キーを
追加した（`combat_v1_playable_match_screen.dart`、UI挙動の変更なし、
test可観測性のためのkey追加のみ）。

**Review過程での発見**: 当初、画面全体の矩形（`Offset.zero &
size`）をviewport近似として使っていたが、これはAppBar・CPU/Human
status panel・Energy panel・primary action bar等、Technique area
以外の固定要素の分だけ過大な近似になり、実際にはscroll clipで
見えない要素を誤って「viewport内」と判定してしまう
（旧実装でclipされてもgreenになるtestという、まさにレビュー指摘の
穴そのもの）。Technique area自身の`SingleChildScrollView`のrender
box（`Expanded`が実際に割り当てた高さ）を正しいclip viewportとして
使うよう修正した。

### 87.2 Technique Card（4.1章）

情報量最大級のTechnique card fixture（`_maxInfoTechnique`、ROUGH属性
+ Direct PIN FINISHER + required/result posture + 長い名前、
`jack_kurocho_driver`相当）を新設し、320/360/390px幅で:

- Technique name・trait badge（FINISHER · PIN・ROUGH）・DMG/HEAT行・
  Energy行・required/result posture行・unusable reasonが、実際に
  到達可能（初期状態で見えているか、scroll後に見える）ことを、
  clip viewportとのintersectionで検証（`expectReachableInViewport`
  helper、scroll前に見えない場合は該当Scrollableを実際にscrollして
  再検証する）。
  - 320px幅では、他panelの折り返しにより実際にscrollが必要になる
    ケースを確認した（unusable reason行）——scroll前は`false`、
    scroll後は`true`になることをassertion側でも検証しており、
    「scroll不要な状況でtestが誤ってgreenになる」ことを防いでいる
    （Match Direction Reachability testと同じ設計、71.1章）。
- 選択可能なcardについては、tap targetの実座標ベースのhit-test
  可能性も検証した。`tester.tap()`（widgetの全高込みの幾何中心を
  狙う）は、狭幅×実際のprimary action button併存時、`ensureVisible`
  後もcenterの一部がclip viewport外に残ることがあると判明した——
  これはreal deviceでの実際の未到達を意味しない（指は現在見えている
  範囲内の任意の点を押せる）。そのため「card rectと実際のclip
  viewportの交差領域の中心」（＝実際に見えていて押せる点）で
  `tester.tapAt`を実行し、その結果（Technique action buttonが
  有効化される）を検証することで、real device相当のhit-test
  可能性を確認する方式にした。

### 87.3 Counter UI（4.2章）

情報量最大級のincoming Technique（`_maxInfoTechnique`、ROUGH +
FINISHER · PIN + family: driver）と、それを実際に返せるCounter
fixture（`_maxInfoMatchingCounter`、group: throwing——既定の
`testCounterCard()`はfamily: elbowのみ対応のため、familyの異なる
`_maxInfoTechnique`とは組み合わせられないと判明したため専用に構築）
を使い、320/360/390px幅で以下への到達可能性を実座標で検証した:

- incoming summary（`combat_v1_playable_pending_effect_line`）
- Counter prevents explanation
  （`combat_v1_playable_pending_counter_prevents_hint`）
- ROUGH consequence note（`combat_v1_playable_pending_rough_counter_note`、
  86章）
- family/group information（`combat_v1_playable_counter_family_match`）
- Counter card information（`combat_v1_playable_counter_card_c1`）
- decline button（`combat_v1_playable_counter_decline_button`）
- Play Counter button（`combat_v1_playable_counter_play_button`）

scroll前にviewport外の要素は、実際に対応するScrollableをscrollして
から再検証する（`expectReachable` helper）——旧実装でclipされても
greenになるtestにしないという方針を、既存のMatch Direction
Reachability test（71.1章）と同じ設計で踏襲した。

### 87.4 実際にUI変更が必要だったか

**production UI（`combat_v1_playable_match_screen.dart`）本体への
変更は最小限**——`combat_v1_playable_technique_area_scroll`という
test可観測性のためのkey追加1件のみで、レイアウト・spacing・card
heightの変更は行っていない。当初、320px幅のtap target到達性で
widget中心ベースのhit-test warningが発生したが、調査の結果、これは
production UIの実際の到達不能ではなく、`tester.tap()`のwidget幾何
中心ベースの判定方法がこの部分可視シナリオに適さないというtest
methodology側の問題と判明した（87.2章）。「情報量最大級のTechnique
card」の各行についても、320px幅でのみ一部要素（unusable reason）が
初期scroll位置では見えないことが判明したが、これはscroll後に確実に
到達可能であることを検証済みであり、真の情報欠落ではない。したがって
5章「Information Density」が想定する「実際のUI修正」（Wrap調整・
spacing調整・card height調整）は不要だった——test側の検証方法
（viewport近似・tap座標）を実際のCore/production挙動に即して
正確化することで、review findingsに対応した。

### 87.5 Tests

- `combat_v1_playable_mobile_overflow_test.dart`拡張: 新設12 case
  （Technique Card 320/360/390px×2種類・Counter UI 320/360/390px×1種類）。
  全件、実座標ベースのintersection/reachability/hit-test検証を伴う。

## 88. Validation（Review Findings Fix）

- `flutter analyze`: No issues found。
- `flutter test test/combat_v1/playable test/combat_v1/playable_ui`:
  既存261件 + 新設18件 = **279件**全件green。
- `flutter test`（リポジトリ全体）: **1896件**全件green（2A-3
  baseline 1878件 + 本Fix新設18件）。
- `flutter build web --release --base-href /one_night_match/
  --no-web-resources-cdn`: 成功。
- `git diff --check`: 問題なし。
- Playable 2A-1（Match Guidance）・2A-2（Win Path / Match Direction）
  のregressionは確認していない（本Fixで対象widget・derivationへの
  変更なし）。

## 89. Changed Files（Review Findings Fix）

- `lib/src/combat_v1/playable_ui/combat_v1_playable_technique_traits.dart`:
  `combatV1PlayableDirectPinTraitDetail`のDOWN条件明記（85章）、
  `combatV1PlayableRoughCounterAsymmetryNote`新設（86章）、関連doc
  comment更新。
- `lib/src/combat_v1/playable_ui/combat_v1_playable_match_screen.dart`:
  `_PendingAttackSummary`へROUGH consequence note追加（86章）、
  Technique area scrollviewへkey追加（87.1章）。
- `test/combat_v1/playable_ui/combat_v1_playable_technique_traits_test.dart`:
  DIRECT PIN DOWN条件・ROUGH非対称性のpure test追加（85.1・86.2章）。
- `test/combat_v1/playable_ui/combat_v1_playable_2a3_readability_test.dart`:
  DIRECT PIN Tooltip DOWN条件・ROUGH incoming/非incoming widget test
  追加（85.1・86.2章）。
- `test/combat_v1/playable_ui/combat_v1_playable_mobile_overflow_test.dart`:
  実座標ベースのMobile Visibility test群を新設（87章）。
- `docs/design/combat_v1_playable_match_ui.md`: 本章（85〜90章）追加。

## 90. Scope Verification（Review Findings Fix）

Combat rule変更: NO / Core resolution変更: NO / LegalAction
semantics変更: NO / CPU AI変更: NO / wrestler data変更: NO /
technique data変更: NO / dependency追加: NO / hidden information
exposure変更: NO。

# Playable 2A-4 — Match Flow / Result Feedback Readability（実装追記）

## 91. Purpose

Playable 2A-1（Match Guidance＝今何をするか）・2A-2（Match Direction＝
何を目指すか）・2A-3（Technique Readability＝技が何をするか）に続き、
2A-4は「直前に何が起きたか」→「状態がどう変化したか」→「次の判断へ
どうつながるか」という因果関係を、ログを解析しなくても読めるように
する。新しいCombat ruleは追加しない、presentation/playability
改善のみのフェーズ。

## 92. Existing Architecture Audit（実装前調査結果）

着手前に、Playable 1Cで既に構築済みのfeedback基盤を調査した。

- `lib/src/combat_v1/playable/combat_v1_playable_action_feedback.dart`
  （`CombatV1PlayableActionFeedback`）: controllerが各actionのbefore/
  after `CombatV1MatchState`差分から構築する、pure presentation-only
  value object（36章）。damage・HP/posture/HEAT/KOC変化・PIN/
  SUBMISSION結果を実測値として保持し、Technique metadataの宣言値を
  そのまま「実際の結果」として扱わない（37章「Do Not Fabricate
  Deltas」）。
- `lib/src/combat_v1/playable_ui/combat_v1_playable_feedback_formatters.dart`:
  上記value objectをUI文字列へ変換する、pure formatter層。
- `combat_v1_playable_match_screen.dart`の`_LatestFeedbackBanner`: 直近
  1件を大きめbannerとして表示し、次のactionまで表示を持続する
  （40章「Feedback Display Duration」）。

この基盤は「1段階（title＋flat detail line群）」の表示であり、5〜7章
（本追記の要求仕様）が求める「Primary result / Secondary consequence
の2段階」「情報階層Tier」「FINISHER/ROUGH Counterの明示」を満たして
いなかった。11章の方針（「既存feedback derivationがある場合は無意味
に別系統を作らず拡張する」）に従い、新しいderivation fileを新設せず、
既存の2ファイルを拡張する方針を採った——別名の並行しくみ
（`combat_v1_playable_match_feedback.dart`のような新規file）は作成
していない。

## 93. Snapshot Projection 拡張（Public情報のみ）

`CombatV1PlayableActionFeedback`へ、以下4つのbool field（既定
`false`）を追加した:

- `isFinisher`（`techniqueResolved`用）: 宣言済み（＝両者へ公開済み）
  TECHNIQUEの`category == finisher`をそのまま複製する。Primary文言へ
  「(FINISHER)」を明示するために使う。
- `preventedDirectPin`/`preventedSubmissionHold`（`counterPlayed`用）:
  **Review Findings Fix（Major、独立レビュー指摘）**により、当初実装
  （trait保有＝防いだと断定）から修正済み。102章参照——「無効化された
  攻撃側TECHNIQUEがDIRECT PIN/SUBMISSION Hold traitを持っていた」
  ことではなく、「Counterしなければ`combat_v1_engine.dart`
  `_resolvePendingAttack`が実際にその自動移行（DIRECT PIN/SUBMISSION
  resolutionへの遷移）へ進んでいた」ことを意味する。
- `preventedIsRough`（`counterPlayed`用）: Counterで無効化された攻撃
  側TECHNIQUEが持っていた、宣言済み・公開済みの静的性質（ROUGH属性）
  をそのまま複製する。ROUGH属性自体はCounterの成否に関わらず変化
  しない静的な事実であり、DIRECT PIN/SUBMISSIONのような「実際に
  transitionへ進むか」という追加条件を持たないため、trait複製のまま
  で正確（86章のROUGH非対称性説明に使う）。

いずれも`combat_v1_playable_match_controller.dart`の
`_buildTechniqueResolvedFeedback`/`_buildFeedback`（counter case）が、
既に保持している`stateBefore.pendingAttack`（宣言済みTECHNIQUEの静的
metadata）から導出する——CPU未使用の手札・CPU counter候補・draw
order・非公開deck内容はいずれも参照しない（16章のhidden information
境界を維持）。DIRECT PIN/SUBMISSION Holdの優先順位判定（FINISHER
category時は`finisherType`が優先）は、`_buildTechniqueResolvedFeedback`
が既に持っていたロジックと同一のものを`_effectiveDirectPin`/
`_effectiveSubmissionHold`という2つのprivate static helperへ集約し、
重複実装を避けた。`preventedDirectPin`/`preventedSubmissionHold`が
実際にtransition条件（DOWN posture／HP閾値）まで満たすかどうかの
判定は、102章で追記する
`combat_v1_playable_counter_prevention.dart`の2つのpure function
（`combatV1PlayableWouldTransitionToDirectPin`/
`combatV1PlayableWouldTransitionToSubmission`）が担う。

## 94. Result Feedback Model — Primary / Secondary / Severity

`combat_v1_playable_feedback_formatters.dart`へ以下を追加した:

- `CombatV1PlayableFeedbackSeverity`（4値のTier enum: `matchDecisive`
  ／`majorStateChange`／`techniqueResult`／`minorEvent`）と、それを
  [feedback]だけから導出する`combatV1PlayableFeedbackSeverity`。
- `CombatV1PlayableMatchFeedback`（`severity`／`primary`／`secondary`）
  ——Match Guidance/Match Directionと同じ「primary 1文＋必要時のみ
  secondary 1文」構成のUI-oriented value object。
- `combatV1PlayableDeriveMatchFeedback`——`CombatV1PlayableActionFeedback`
  1件からこのmodelを導出するpure function。kind別に
  `_derivePinResolvedFeedback`/`_deriveTechniqueResolvedFeedback`/
  `_deriveCounterFeedback`へ分岐する。

値の意味づけ（実装時に実際のCore semanticsと照合済み、6章の例文を
そのまま仕様化していない）:

- **Technique成立**: primaryに「actor — 技名（＋FINISHERならその旨）
  — N DAMAGE」、secondaryに「HP変化・posture変化・HEAT変化」を
  `·`区切りでまとめる。同一action内でDIRECT PIN/SUBMISSIONへ自動
  移行した場合は、secondaryへ「PIN ATTEMPT — 結果」/「SUBMISSION —
  結果」と、防御側KOC変化を追記する。PIN countの具体的な数値
  （1/2/2.9）は39章の方針どおり一切含めない。
  - DIRECT PINだがEngineが実際にはDOWN条件を満たさず自動移行しな
    かった境界（`pinOutcome == null`）では、PIN関連の文言を一切
    出さない——「成立時、条件を満たすと」という宣言済みTECHNIQUEの
    可能性と、実際に起きた事実を混同しない（37章と同じ方針）。
- **COUNTER成立**: primaryに「actor countered with 技名」、secondaryに
  「防いだ内容」（DMG・HEAT・状態変化、＋DIRECT PIN/SUBMISSION Hold
  なら追加でその旨）。ROUGH技を防いだ場合は、2A-3
  86章で確定した非対称性（宣言時点で確定するPIN不可はCounterされて
  も取り消されない／成立ベースの次ターンTECHNIQUE制限はCounterで
  防げる）を、過去形のLatest Result向けに言い換えて追記する——同じ
  事実の言い換えであり、新しいCombat ruleではない。
- **通常PIN宣言**: primaryに「actor — PIN ATTEMPT — 結果」、secondary
  に防御側KOC変化。
- **Rest/Stand Up/discard/end turn/technique宣言**: Tier 4の補助
  イベントとして、primaryのみ（rest時のみsecondaryにHP変化）。

## 95. Result Feedbackの情報階層（Tier、実装）

`combatV1PlayableFeedbackSeverity`が導出するTier:

- **Tier 1（matchDecisive）**: PIN 3-count／SUBMISSION GIVE UP
  （`pinOutcome`/`submissionOutcome == matchOver`）、またはFINISHER
  成立（`isFinisher`）。
- **Tier 2（majorStateChange）**: PIN宣言・COUNTER成立、または
  Technique成立でPIN/SUBMISSIONへ自動移行した場合・相手をDOWNさせた
  場合。
- **Tier 3（techniqueResult）**: 上記に該当しない通常のTechnique成立
  （DMG・HEAT・posture変化）。
- **Tier 4（minorEvent）**: discard・turn transition・Stand Up・
  Rest・Technique宣言。

`_LatestFeedbackBanner`（match_screen.dart）は、Tier 1/2の場合のみ
背景・枠線を強調する（alpha/widthを上げる）。ただし色・強調度だけに
依存しない——文言自体が既に「PIN ATTEMPT — 3 COUNT — MATCH OVER」の
ように事実を明示しているため、Tier表示は補助的な視覚強調に留める
（18章「Accessibility Semantics」）。

## 96. Guidance / Direction / Latest Result / Recent Logの責務分離

重複表示を避けるため、4つのpanelの責務を再確認した（8〜9章）:

- **Match Guidance**（2A-1）: 今できること。legal actionのSSOTに基づく
  提案（例:「PIN可能」）。
- **Match Direction**（2A-2）: 勝利までの道筋（例:「相手のKOCを削る
  チャンスです」）。
- **Latest Result**（本追記）: 直前に実際に起きた事実のみ、過去形。
  「〜しましょう」「〜が可能です」のような提案・評価語彙は一切
  含めない——widget test（`combat_v1_playable_feedback_widget_test.dart`
  「Latest Result — Guidance / Direction責務分離」）で、Guidance
  primaryとLatest Result primaryが異なる文字列であり、Latest Result
  側にGuidanceの提案語彙（`pin`等）が漏れていないことを確認した。
- **Recent Log**: 時系列確認用の簡潔な履歴（`combatV1PlayableFeedbackCompactLabel`、
  既存のまま無変更）。内部ID・enum名・instance IDは含めない
  （9章「デバッグログ化しない」方針を維持）。

## 97. Hidden Information Boundary（維持）

新規参照fieldはすべて「宣言済み（＝両者へ公開済み）TECHNIQUEの静的
metadata」（93章）であり、CPU hand contents／CPU Energy／CPU Counter
possession／CPU Finisher possession／deck order／next draw／CPU AI
decision／internal evaluation／random rollの非公開値／future legal
action predictionはいずれも一切参照していない
（`CombatV1PlayableOpponentStatus`は無変更）。

## 98. Mobile Strategy

既存の`ConstrainedBox(maxHeight: 132)` + `Scrollbar`/
`SingleChildScrollView`（70.10章のscroll reachability機構、Playable
2A-2）をそのまま活用した——Latest Resultのprimary/secondary化は表示
内容の再構成のみで、この安全弁のレイアウト自体は変更していない。

`combat_v1_playable_mobile_overflow_test.dart`へ新設した「Latest
Result Reachability（Playable 2A-4 追加）」groupで、320/360/390px幅
の代表ケース3種を検証した:

1. 長いFINISHER技結果 + Match Direction secondary + recent log 5件
   ——overflowせず、実際にscrollして末尾のrecent log entryへ到達
   できる。
2. DIRECT PIN/SUBMISSION Hold/ROUGHすべてを防いだ長いCounter
   secondary + Technique/End Turn control——overflowせず、下部固定
   領域（primary action bar・hand card）が常にscroll不要でviewport内
   へ収まり、hit-testableである。
3. PIN 3-count（Result overlay内のterminal feedback）——overflowせず、
   Rematch/Backボタンへ到達できる。

## 99. Test Strategy

- **Pure test**（新設
  `test/combat_v1/playable_ui/combat_v1_playable_feedback_formatters_test.dart`、
  25件）: `combatV1PlayableFeedbackSeverity`の全kind分岐・
  `combatV1PlayableDeriveMatchFeedback`のPrimary/Secondary内容
  （Technique成功・damage・HEAT・DOWN・FINISHER・Direct PIN自動移行・
  DOWN条件を満たさない境界・SUBMISSION ESCAPE/GIVE UP・PIN kick out/
  3-count・COUNTER成立＋DIRECT PIN/SUBMISSION/ROUGH・Rest・Stand Up・
  discard・end turn）を、実Engineを経由せずsynthetic feedbackで検証
  した。
- **Real controller test**（`combat_v1_playable_scenario_test.dart`
  「72. Human counter」拡張）: 実際にCounterが成立するシナリオを
  seed探索で見つけ、`preventedIsRough`がCounter前の`pendingAttack`
  （宣言済み・公開済み情報）の静的traitと一致することを確認した
  ——`preventedDirectPin`/`preventedSubmissionHold`については102章
  「Review Findings Fix」参照（trait一致ではなく、Core条件
  （DOWN posture／HP閾値）まで満たすかで期待値を計算し直している）。
- **Widget test**（`combat_v1_playable_feedback_widget_test.dart`
  拡張）: FINISHER成立時のprimary表示・ROUGH Counterの非対称性
  secondary表示・Guidanceとの責務重複が無いことを追加検証した。既存
  15件（PIN/SUBMISSION/HEAT/discard/accessibility等）はkey名変更
  （`_title`/`_details` → `_primary`/`_secondary`、他fileから参照
  されていないことを確認済み）以外は無変更で全green。
- **Mobile test**: 98章参照。

## 100. Non-Goals（今回は実装しない）

- Combat Core rule・damage/HP/KOC/PIN/Submission/Finisher/Counter/
  DOWN/Shared HEAT/Energy計算の変更。
- LegalAction semanticsの変更、UI側での操作可能性の独自再計算。
- PIN countの具体的な数値（1/2/2.9）表示（39章の方針を継続）。
- Draw/Discard詳細のTier引き上げ（Tier 4のまま、情報過多を避ける）。
- CPU AI・wrestler/technique data・deck構成・random挙動・依存関係の
  変更。

## 101. Scope Verification（Playable 2A-4）

Combat rule変更: NO / Core resolution変更: NO / LegalAction
semantics変更: NO / CPU AI変更: NO / wrestler data変更: NO /
technique data変更: NO / dependency変更: NO / hidden information
exposure: NO。

## 102. Review Findings Fix（独立レビュー指摘の修正、実装追記）

初回実装（91〜101章）の独立レビューでCHANGES REQUIREDとなり、以下を
最小差分で修正した。Combat Core・LegalAction semantics・CPU AI・
wrestler/technique data・依存関係はいずれも無変更（101章のScope
Verificationは修正後も全てNOのまま）。

### 102.1 Major — preventedDirectPin/preventedSubmissionHoldの意味の訂正

**問題**: 初回実装の`preventedDirectPin`/`preventedSubmissionHold`は、
無効化された攻撃側TECHNIQUEが持つDIRECT PIN/SUBMISSION Hold trait
（`_effectiveDirectPin`/`_effectiveSubmissionHold`の戻り値）だけで
`true`になっていた。しかしCore（`combat_v1_engine.dart`
`_resolvePendingAttack`）では、traitを持つだけでは自動移行は起きない
——追加条件を満たす場合のみ実際にDIRECT PIN/SUBMISSION resolutionへ
進む。「traitを持っていた」ことと「Counterしなければ実際にその
transitionへ進んでいた」ことを混同していたのがMajor指摘の要旨。

**Coreの実際の条件**（`_resolvePendingAttack`、`combat_v1_engine.dart`
1017〜1173行）:

- **DIRECT PIN**: `effectiveDirectPin`が真であることに加え、
  `resolvedOpponentPosture = pending.resultOpponentState ??
  state.opponent.posture`（`resultOpponentState`が非nullならそちらを
  優先、nullなら防御側の現在postureをそのまま維持）が
  `CombatV1WrestlerPosture.down`である場合にのみDIRECT PIN自動移行が
  発生する（`if (effectiveDirectPin && next.opponent.posture ==
  down)`）。
- **SUBMISSION**: `effectiveSubmissionHold`が真であることに加え、
  damage適用後の防御側HP（`max(0, min(hp - damage, maxHp))`）が
  `submissionEligible`（`combat_v1_submission_rules.dart`、
  `opponentHp <= rules.submissionHpThreshold`、既定50）を満たす場合
  にのみSUBMISSION resolutionへ移行する。

**修正内容**: `lib/src/combat_v1/playable/combat_v1_playable_counter_prevention.dart`
を新設し、上記2条件をCoreのコードと直接照合した2つのpure function
として実装した:

- `combatV1PlayableWouldTransitionToDirectPin({effectiveDirectPin,
  resultOpponentState, defenderPostureBeforeResolution})`
- `combatV1PlayableWouldTransitionToSubmission({effectiveSubmissionHold,
  defenderHpBeforeResolution, defenderMaxHp, damage, rules})`
  ——閾値比較はCore自身の`submissionEligible`をそのまま呼び出し、
  再実装しない。

`combat_v1_playable_match_controller.dart`の`counter` caseは、この
2 functionの戻り値を`preventedDirectPin`/`preventedSubmissionHold`
へそのまま使う（`defenderPostureBeforeResolution`/
`defenderHpBeforeResolution`は`stateBefore`の防御側status——
TECHNIQUE宣言からCounter応答までの間、防御側posture/HPは変化しない
ため、Coreが`declineCounter`へ渡すstateと同じ値になる）。

新しいCombat rule判定は追加していない——Coreが既に持つ2条件を、
安全にprojectionしただけ。判定はcontroller/projection側
（`combat_v1_playable_counter_prevention.dart`・
`combat_v1_playable_match_controller.dart`）で完結し、
`combat_v1_playable_feedback_formatters.dart`（presentation
formatter）は確定済みのbool値をそのまま文章化するだけの既存責務を
維持している（94章のCounter成立secondaryの文言・条件分岐は無変更）。

### 102.2 Submission Finisher Boundary

`combat_v1_finisher_rules.dart`
`determineFinisherSubmissionOutcome`を確認したところ、通常SUBMISSION
とSUBMISSION FINISHERの相違点は「SUBMISSION resolutionへの突入条件」
ではなく「突入後のESCAPE/GIVE UP判定」のみだった——解決後の相手HPが
0の場合、SUBMISSION FINISHERはKOC保有量に関わらず即GIVE UPになる
（10.2章の特殊処理）が、この処理は`submissionEligible`による突入
判定より後段の話であり、`preventedSubmissionHold`が意味する
「SUBMISSION resolutionへ移行したか」には影響しない。そのため
`combatV1PlayableWouldTransitionToSubmission`はNORMAL/FINISHERで
同一の式をそのまま使い、無理な統合や別式は導入していない。

「SUBMISSION trait」（技が持つ性質）・「SUBMISSION transition」
（resolutionへ実際に移行すること、`preventedSubmissionHold`が指す
もの）・「GIVE UP」（SUBMISSION resolution突入後の決着結果の1つ）は
それぞれ別概念であり、`preventedSubmissionHold`は3つ目
（GIVE UPを防いだ）を一切意味しない——2つ目（transitionへの移行）
だけを意味する。

### 102.3 ROUGH Counter Semantics（維持確認）

独立レビューでROUGH Counter semantics（86章の非対称性、`preventedIsRough`
の扱い）はPASS済みだったため、変更していない。`preventedIsRough`は
引き続き宣言済みtraitの複製のまま——DIRECT PIN/SUBMISSIONと異なり
「実際にtransitionへ進むか」という追加のCore条件を持たないため
（ROUGH属性は技の静的な性質であり、Counterされてもされなくても値が
変わらない）、trait複製のままで正確である。

### 102.4 Test Coverage 追加

- **Pure test**（新設
  `test/combat_v1/playable/combat_v1_playable_counter_prevention_test.dart`、
  15件）: `combatV1PlayableWouldTransitionToDirectPin`/
  `combatV1PlayableWouldTransitionToSubmission`を、production
  wrestler/catalogに依存しないsynthetic入力で検証した——DOWN
  posture／HP閾値の境界（ちょうど閾値・閾値+1・damageで閾値内へ入る
  境界・HPがマイナスになる場合のclamp等）を網羅する。
- **Real controller test**（`combat_v1_playable_scenario_test.dart`
  「72. Human counter」拡張・「72. Counter Prevents accuracy」新設）:
  実際にCounterが成立するシナリオをseed探索で見つけ、
  `preventedDirectPin`/`preventedSubmissionHold`がtrait一致ではなく
  Core条件一致になっていることを確認した。SUBMISSION側は、production
  catalog上SUBMISSION Hold traitを持つ技をCounterできるカードが
  白銀レイナの`counter_reina_silver_lock_reversal`（crossface family
  対象）1種のみであること（`combat_v1_counter_catalog.dart`——armbar
  familyを対象とするCounterはgame data上存在しない、Phase 10C-0.5 A7
  で明示的に許容された仕様）を確認したうえで、reina同士のmirror
  matchで実際にCPUがCounterする局面をturn 1宣言→CPU応答パターンで
  探索し、`preventedSubmissionHold == false`（damage適用後HPが閾値を
  超える、trait保有のみのケース）を実Core Engine resolutionを通して
  確認した。
- **Formatter test**（`combat_v1_playable_feedback_formatters_test.dart`
  拡張）: `preventedDirectPin`/`preventedSubmissionHold ==
  false`の場合に、「自動PIN移行を防いだ」/「SUBMISSION移行条件を
  防いだ」という断定文言を一切出力しないことを、negative assertionで
  追加検証した。
- **Widget test**（`combat_v1_playable_feedback_widget_test.dart`
  拡張）: 同じnegative/positive assertionをwidget tree（実際に
  renderされるLatest Result banner）まで通して確認した。

### 102.5 Minor — Mobile Visibility / Hit-testability 強化

`combat_v1_playable_mobile_overflow_test.dart`「Latest Result
Reachability（Playable 2A-4 追加）」groupを、`findsOneWidget`だけの
存在確認から、実際のclip viewportとのintersection確認へ強化した:

- ケース2（Counter result）: Latest Result primary/secondaryの実座標
  （`getRect`）を、実際に属するclip viewport
  （`combat_v1_playable_actor_recent_scroll`）と比較し、scroll前に
  viewport外なら実際にdragしてからscroll後のintersectionを確認する
  （既存「Match Direction Reachability」groupと同じ手法）。Technique
  cardは画面全体ではなく、実際のTechnique scroll viewport
  （`combat_v1_playable_technique_area_scroll`、2A-3で確立した
  observabilityを再利用）と比較する。End Turn buttonは中心座標が
  screen内にあることの確認に加え、実際に`tester.tap`し、
  `FakePlayableMatchSession.submitCalls`で`endTurn` actionが実際に
  送信されたことまで確認する。
- ケース3（Result overlay）: overlay自身の実viewport
  （`Positioned.fill`により画面全体を覆う）に対する、terminal Latest
  Result primary/secondaryのintersectionを確認する（長文で収まらない
  場合はoverlay内をscrollしてから再確認）。Rematchボタンを実際に
  `tester.tap`し、`sessionFactory`が2回目の呼び出しで非terminalな
  sessionを返すようscriptedしたうえで、Result overlayが実際に消える
  （新しい試合へ遷移する）ことまで確認する。
- 2A-3で確立したCounter応答UIのdecline button hit-test
  （`Technique / Counter Decision Traits`group、D.）も、中心座標の
  確認だけでなく実際に`tester.tap`し、`declineCounter` actionが
  送信されることまで確認するよう強化した。

2A-2（Guidance/Direction/Recent Log reachability）・2A-3（Technique
readability・trait badges・Counter family/group・ROUGH説明・
Technique card hit-testability・320/360/390px coverage）の既存
regression testはすべて無変更のまま全green。

# Playable 2A-5 — Card Interaction / Hand Readability（実装追記）

## 103. Purpose / User Observation

Playable 2A-1〜2A-4は「今何をすべきか」（Guidance）「なぜそれが勝利に
つながるか」（Direction）「直前に何が起きたか」（Result）という
*説明*の情報階層を整備してきた。実プレイで観測された問題は、その説明
そのものではなく、最も頻繁に行う操作——「Technique handを見て、
理解して、選んで、使用する」——の周りにある:

1. Technique使用時にEnergyをほとんど見ずにプレイしていた（Energyが
   Technique cardの小さな1行にしか出ておらず、判断の中心に無かった）。
2. 「技として出すカード」と「discardとして捨てるカード」の見た目が
   同じで、区別がつきにくかった。
3. 手札を確認するのにscrollが必要だった。
4. Technique使用buttonが画面下部（Primary actions bar）にあり、カード
   選択後に視線・指を大きく移動する必要があった。
5. PLAY TECHNIQUE等の主要操作が英語で直感的でなかった。
6. Guidance/Direction/Latest Result/Recent Logの追加により、最も頻繁に
   操作するTechnique handの表示領域が圧迫されてきていた。

2A-5は新しいCombat ruleを追加しない。2A-2〜2A-4で追加した情報を削除
するのでもない——「カードを選び、必要コストを理解し、技を出す」ことを
画面の中心へ戻すため、既存の情報階層を整理する presentation-only の
フェーズ。

## 104. 実装前 Investigation — なぜscrollが必要だったか

`combat_v1_playable_match_screen.dart`の旧`build()`は次の順でColumnを
構築していた（上から）:

CPU status panel → Shared status panel → Actor label + Match Guidance +
（既定展開の）Match Direction/Latest Result banner/Recent Log（最大
132px scroll box）→ Error banner → `Expanded`（Technique handの縦
scroll領域）→ Human status panel → Energy panel → Primary actions bar
（Stand Up/Rest/Technique/PIN/End Turn）。

Technique hand card自体は1枚268px（Playable 2A-3でtrait badge行が
追加されて232px→268pxへ拡張済み）。`Expanded`より上の固定panel群
（CPU status・actor label・Guidance・132px scroll box）と、`Expanded`
より下の固定panel群（Human status・Energy panel・Primary actions
bar）を合算すると、320〜390px幅・600〜850px高の一般的なモバイル
viewportでは、`Expanded`へ実際に割り当てられる高さがしばしば
268pxを下回っていた——つまり**1枚の手札card全体を表示するだけでも
scrollが必要**な構造だった。単純に既存panelの高さを増やす／削る
のではなく、次の3点で高さの使い方そのものを変えた:

- 両wrestlerの背景status（CPU/Human status panel）を隣接させて画面
  上部へ集約する（Tier優先度が相対的に低い情報を1箇所にまとめる）。
- Guidance（Tier 3）は常時表示のまま、Direction/Latest Result banner/
  Recent Log（Tier 4）を既定で折りたたむ（106章）。
- Energy panel（Tier 2）をTechnique handの直上へ移動し、`Expanded`の
  外の固定領域からは完全に取り除く。

## 105. Hand-First Hierarchy（優先順位）

Tier 1: 現在選択・操作するTechnique hand。
Tier 2: Technique使用に必要な情報（DMG/HEAT/必要Energy/現在Energy/
使用可能・不可能/posture/important trait/discard先の区別）。
Tier 3: 現在必要なGuidance。
Tier 4: Match Direction / Latest Result / Recent Log。

Tier 1・2は常に画面内（scroll不要な想定範囲）に収まるよう最優先で
扱い、Tier 4は既定で折りたたんで縦方向の空間をTier 1・2へ譲る
（106章）。Tier 3（Guidance）は「今何ができるか」という短い1〜2行
情報のため、常時表示のままでもTier 1・2を圧迫しない。

## 106. Guidance / Direction / Result / Logの圧縮

`_ActorAndRecentPanel`をStateful化し、`_detailExpanded`（既定
`false`）を追加した:

- 常時表示: actor label（あなたのターン/CPU行動中等）＋ Match
  Guidance（primary + secondary、Tier 3）。
- 既定で折りたたみ（Tier 4）: Match Direction・Latest Result banner・
  Recent Log。折りたたみ中は、widget自体を`SizedBox.shrink()`にする
  （高さ0の`ConstrainedBox`ではなく完全に取り除く）ことで、
  `Expanded`（Technique hand領域）へ渡る高さを実際に増やす。
- ただしLatest Result（「直前に実際に起きたこと」）だけは、折りたたみ
  中も1行のcompact要約（`combat_v1_playable_latest_feedback_compact_
  summary`）を出す——既存`combatV1PlayableDeriveMatchFeedback`が
  導出したprimary文言をそのまま小さく表示するだけで、新しい
  derivationは行わない。
- `combat_v1_playable_detail_toggle`（TextButton、「▼ 試合の詳細
  （勝利へのヒント・直前の結果・履歴）」/「▲ 閉じる」）をtapすると
  展開・再度tapで折りたたむ。展開後の中身（Match Direction panel・
  Latest Result banner・Recent Logの`Scrollbar`付き`SingleChildScrollView`）
  は2A-2で確立した「実際にscroll可能」実装をそのまま再利用する
  ——widgetもkeyも変更していない。

Playable 2A-2で修正した「情報が存在するがclipされて到達不能」という
regressionを再発させないため、折りたたみは「表示しない」ではなく
「ユーザーの明示操作（toggle tap）で必ず元の内容へ到達できる」構造に
した——widget tree自体には残さないが、同じkey・同じ中身が常に1tapで
出現する。

## 107. Energy Presentation（技選択時の中心情報）

Technique hand card自体の表示（Playable 1C.1以来の「Cost + 使用可能
Energyの比較」）は変更していない。加えて、カードを選択すると
hand直下に現れる`_SelectedTechniquePanel`内に、「必要 Energy」
「現在 Energy」を縦に並べた`_SelectedTechniqueEnergyBlock`を設けた:

- 「必要 Energy」: `combatV1PlayableEnergyCostLabel`（既存formatter）。
- 「現在 Energy」: 新設`combatV1PlayableEnergyAvailableLabel`
  （`combat_v1_playable_ui_formatters.dart`）。ワイルド(＊)込みの実効
  使用可能量を返す共通helper`combatV1PlayableEffectiveAvailableEnergy`
  を新設し、既存`combatV1PlayableEnergyComparisonLabel`もこのhelperを
  使うようリファクタリングした（同じ値を2箇所で別々に計算しない、
  出力の矛盾を構造的に防ぐ）。

「使用可能／不可能」の断定は`card.isUsable`（`CombatV1PlayableHand
Card`、controller側で`legalActions`から機械的に導出済み——LegalAction
がSSOT）をそのまま使う。不可能な場合の理由文言は、Playable 1C.1で
導入済みの`_disabledMessage`ロジックを`_handCardDisabledMessage`
（module-level pure function）へ抽出し、`_HandCardTile`と
`_SelectedTechniquePanel`の両方が同じ関数を呼ぶ——理由の断定ロジック
を2箇所に重複実装しない。新しいlegality判定・新しいunusable reasonは
一切追加していない。

## 108. Technique Selection → Direct Execution（近接した操作）

カードを選択すると、`_TechniqueSelectionArea`内でhand（`_HandRow`）の
直下に`_SelectedTechniquePanel`が現れる:

技名 → trait badges（Playable 2A-3の`_TechniqueTraitBadges`をそのまま
再利用）→ DMG/HEAT → required/result posture → Energy比較block
（107章）→ 使用可能／不可能status行 → 「技を使う」button。

「技を使う」buttonは`combat_v1_playable_action_technique`という既存
keyをそのまま維持し、以前`_PrimaryActionsBar`（画面下部）にあった
ものをこのpanelへ移設した——`findAction(CombatV1LegalActionKind.
technique, cardInstanceId: ...)`/`onSubmit`という既存の
`_findLegalAction`/`_submitAction`経路をそのまま使う（新しいsubmit
経路は作らない）。カード未選択時はbutton自体が存在しない（以前の
「常に表示されるが disabled」から「選択して初めて現れる」へ変更）。

COUNTERカードを通常Action phase中に選択した場合（COUNTERは相手の
技への応答専用で、この文脈では常にunusable）、Technique buttonは
出さず、既存の安全な用途説明（「相手の技を受ける時に使用」）を
panel内へそのまま表示する——新しいlegality判定は行わない。

`_PrimaryActionsBar`は、カード選択と無関係な行動（Stand Up/Rest/PIN/
End Turn）専用に縮小した。discard確定buttonも同様にbarから削除した
（109章）。

## 109. Technique使用とDiscardを明確に分離

Core semanticsを先に調査した結果、discardは「Techniqueの追加コスト」
ではなく、`phase == discard`という独立したフェーズであり
（`combat_v1_legal_action_enumerator.dart` `_enumerateDiscard`）、
このフェーズでは**手札の全カードが常に`CombatV1DiscardAction`として
legal**（技としての使用可否＝`isUsable`とは無関係）であることを
確認した。したがって「STEP 1 技を選ぶ → STEP 2 追加コストのdiscard
カードを選ぶ」という2段階選択フローは実際のCore semanticsに存在せず、
実装しない（依頼文中の例をそのままルール化しない）。

代わりに、discard phase専用の`discardMode`を`_HandRow`/`_HandCardTile`
へ追加した:

- discard modeのcard tile（`_buildDiscardMode`）は、DMG/HEAT/Energy行/
  trait badge/使用可否messageを一切出さない——技として使えるかどうか
  はdiscard判断と無関係であり、見せると「技を選んでいる」ように
  誤解させるため。名前・category・（選択中なら）「捨てるカードとして
  選択中」の3行だけの簡潔なtileにし、高さも108px（technique modeの
  268pxより低い）に縮めた。
- 選択すると`_DiscardConfirmPanel`がhand直下へ現れる:「捨てるカード」
  ラベル＋カード名＋「別のカードをタップすると変更できます」＋
  「手札を捨てる」button。「変更する」専用buttonは追加していない——
  既存`_onSelectCard`のtoggle/switch挙動（別カードをtapすると選択が
  切り替わる、同じカードを再tapすると選択解除）をそのまま使う。
- 確定buttonのkey（`combat_v1_playable_action_discard`）・submit経路
  （`findAction(CombatV1LegalActionKind.discard, cardInstanceId:
  ...)`/`onSubmit`）は変更していない。

この結果、「技として出すカード」（DMG/HEAT/Energy/trait付きの大きめ
tile）と「discard対象のカード」（名前とcategoryだけの簡潔なtile）は
見た目が明確に異なり、mental modelを混同しない。

## 110. Japanese Primary Actions

`combatV1PlayableActionKindLabel`（`combat_v1_playable_ui_formatters.dart`）
を日本語化した:

| kind | 旧 | 新 |
| --- | --- | --- |
| technique | Use Technique | 技を使う |
| discard | Discard | 手札を捨てる |
| counter | Play Counter | 返し技を使う |
| declineCounter | 技を受ける | 返し技を使わない |
| standUp | Stand Up | 立ち上がる |
| rest | Rest | 休む |
| endTurn | End Turn | ターン終了 |
| pin | PIN | PIN（変更なし） |

`_CounterPromptSheet`のPlay Counter/Decline buttonも、独自の英語
literalを廃してこのformatterを直接参照するよう変更した（文言のSSOTを
1箇所へ集約）。DOWN状態の`_ActionHint`（Stand Up/Restの短い説明）も
同じformatterを参照し、button文言とhint文言が食い違わないようにした。
Result overlayのRematch/Backボタンも「再戦」/「戻る」へ日本語化した。

DMG/HEAT/ENERGY/PIN/SUBMISSION/COUNTER/FINISHERは、ゲーム内用語として
既に定着しているため機械的な日本語化の対象から除外した——「操作
button」と「ゲーム用語」を区別する方針どおり。

## 111. Counter Interaction

Counter promptシート（`_CounterPromptSheet`）は、Playable 2A-3までに
確立した構造（incoming Technique summary → 使用可能なCounter hand →
Play/Decline button）を維持している。2A-5ではbutton文言の日本語化
（110章）のみを行った——incoming attack summaryとCounter選択・
確定操作は元々同じbottom sheet内で近接しており、Direct PIN条件・
Submission threshold・ROUGH Counter非対称性・family/group一致・
Counter prevention facts・hidden information境界・LegalAction SSOTは
一切変更していない。

## 112. Mobile Strategy

320/360/390px幅で以下を検証した（`combat_v1_playable_2a5_card_
interaction_test.dart`「Hand Visibility」「320/360/390px — 実座標
hit-testability」group）:

- 通常の1枚hand選択時、scroll前から技名・DMG/HEAT行・Energy行が
  実際にTechnique area viewport（`combat_v1_playable_technique_area_
  scroll`）内へ届いていること（card全体の矩形一致ではなく、実際に
  読む必要がある行単位で確認する——card下部のtrait detail等まで
  無条件に見えている必要はない）。
- hand cardの選択→Technique buttonのtap、hand cardの選択→discard
  確定buttonのtapを、`getRect`によるclip viewportとのintersectionで
  実座標を求めたうえで`tapAt`し、実際に期待する`CombatV1LegalAction`
  が`submitHumanAction`へ渡ることまで確認する（widget中心座標だけの
  確認や、widget treeに存在するだけの確認はしない、Playable 2A-3
  Review Findings Fixで確立した方針を踏襲）。

既存2A-2〜2A-4のmobile reachability test（Match Direction Reachability・
Latest Result Reachability・Technique/Counter Decision Traits等）は、
106章の折りたたみ変更に合わせて「`combat_v1_playable_detail_toggle`を
tapしてから展開後の内容を検証する」よう更新した——検証している内容
（到達可能性・overflow無し・hit-testability）自体は変更していない。

## 113. LegalAction SSOT / Hidden Information Boundary（維持）

2A-5はpresentation-onlyであり、以下は一切変更していない:

- `card.isUsable`・`snapshot.legalActions`が唯一のSSOT。新しい
  `_SelectedTechniquePanel`/`_DiscardConfirmPanel`のbuttonは、いずれも
  既存`_findLegalAction`が返す`CombatV1LegalAction`が`null`でない
  場合のみ有効化される——UI側でlegalityを再計算・再実装していない。
- unusable reasonの断定（Energy不足／HEAT要件／COUNTER用途）は、
  Playable 1C.1で確立した安全な診断ロジック（`resolveEnergyPayment`を
  公開snapshot値へ再適用するだけ）を抽出・再利用しただけで、新しい
  断定は追加していない。
- CPU hand・CPU Energyの非公開値・CPU Counter/Finisher所持・deck
  order・next draw・CPU AI evaluation・future CPU actionは、2A-5でも
  一切表示・推測していない（既存`CombatV1PlayableOpponentStatus`が
  構造的にこれらを保持しないため、Widget側で表示しようがない）。

## 114. Non-Goals（今回は実装しない）

- Combat Core semantics（damage/PIN/Submission/Finisher/ROUGH/Energy/
  discard rule）の変更。
- LegalAction semantics・CPU AI・wrestler/technique data・deck
  compositionの変更。
- 依頼文中の「STEP 1 技を選ぶ → STEP 2 discardカードを選ぶ →
  STEP 3 確認」という2段階discard flow（109章の調査結果どおり、
  実際のCore semanticsに存在しない架空のフローのため実装しない）。
- Guidance/Direction/Result/Logの内容そのものの変更（責務・derivation
  logicは無変更、表示タイミング・折りたたみのみ変更）。
- Counterの新しいUI構造（button文言の日本語化のみ）。
- Playable 2A-6以降のスコープ（新しい画面・新しいCore機能等）。

## 115. Test Strategy（2A-5）

- 既存2A-1〜2A-4のwidget/mobile testは、削除せず106章の折りたたみへ
  合わせて更新した（`combat_v1_playable_feedback_widget_test.dart`・
  `combat_v1_playable_match_direction_widget_test.dart`・
  `combat_v1_playable_mobile_overflow_test.dart`の該当group）。
- `combat_v1_playable_match_screen_test.dart`のTechnique/Discard flow
  testを、「buttonは選択後にのみ現れ、hand直下から直接submitされる」
  という新しい操作モデルに合わせて更新した。
- 新設`combat_v1_playable_2a5_card_interaction_test.dart`で、Energy
  readability・Technique選択→直接実行・discard modeの視覚的分離・
  discard確認/変更・日本語主要操作・Guidance/Direction/Result/Logの
  既定折りたたみと明示展開・Counter日本語操作・320/360/390pxでの
  hand visibility・実座標hit-testabilityを新規に検証した。
- `combat_v1_playable_ui_formatters_test.dart`へ、主要操作button
  labelが日本語（PINのみ例外）であることを固定するtestを追加した。

# Playable 2A-5 Review Findings Fix — Hand Comparison / Mobile
# Readability（実装追記）

## 116. Purpose

独立レビュー結果は「CHANGES REQUIRED」だったが、2A-5全体が不合格
だったわけではない。Energy visibility・Energy不足理由・Technique/
discardの意味分離・Technique選択後のinline action・日本語化・
LegalAction SSOT・hidden information boundary・Counter flow・2A-4
feedback pipeline・mobile reachabilityはいずれも良好と評価された。

唯一かつ最大のMajor問題は、初期手札5枚を比較するために横scrollが
必要だったこと——134px幅×268px高のcard 1枚をhorizontal `ListView`で
並べる実装のままだったため、320px幅では同時に2枚程度しか見えず、
実プレイfeedback「スクロールしないと手札が見れないのは不便」が本質的に
未解消のままだった。

今回の修正目的は「5枚すべての詳細カードを画面内へ押し込むこと」では
ない。目的は「5枚の候補をscrollせず比較し、使うカードを決められる」
状態にすることであり、詳細確認そのものは選択後のinteraction（縦scroll
を含む）を許容する。

## 117. Compact Hand — 一覧＝比較、詳細＝判断確認

`_HandRow`（technique選択時、`discardMode == false`）を、固定高さの
horizontal `ListView`から`Wrap`ベースのcompact hand cardへ置き換えた
（`_HandCardTile.compactMode`）。

- compact card（92px幅、可変高さ、`Wrap(spacing: 6, runSpacing: 6)`）
  には最低限、識別できる名前・required Energy
  （`combatV1PlayableEnergyCostLabel`）・使用可能／不可能（アイコン＋
  不透明度）・selected state（border色）を表示する。加えて、DMG
  （短い1行）と、major trait 1つ（FINISHER/PIN/SUBMISSION/ROUGHの
  いずれか、優先度は`_compactPrimaryTrait`——`_TechniqueTraitBadges`と
  同じ優先度だが、FINISHERの場合は合成label・ROUGH併記をせず単独の
  `FINISHER`のみ）を追加する。
- 320/360/390pxいずれでも、92px幅カード＋6pxスペーシングで1行3枚
  折り返しになる（3×90+2×6=282〜288px、320px幅の利用可能幅296pxに
  収まる）。5枚なら2行——横scroll無しで同時に視認できる。
- Technique detail（DMG/HEAT/required・result posture/trait badge
  合成label/使用不可の具体理由）は、既存2A-5の`_SelectedTechniquePanel`
  （選択後にhand直下へ現れる）へ集約した。「詳細をすべてcompact card
  へ詰め込む」のではなく「一覧＝比較（compact）」「詳細＝判断確認
  （選択後panel）」「実行＝選択カードの近く（同じpanel内の『技を
  使う』）」という3段階に責務を分離した。
- discard phase（`discardMode == true`）は元々108px高の簡潔なtileで
  カード枚数も少なく、横scroll listのまま維持した（6章「Do Not
  Regress Play vs Discard」——discard UXは流用・変更しない）。横
  scroll cue（`combat_v1_playable_hand_scroll_hint`）もdiscard phase
  専用に限定した——technique modeは横scroll自体が不要になったため。

`_CounterPromptSheet`のCounter hand（応答時、通常1〜3枚程度）は
compactModeを使わず、既存の詳細card表示のまま維持した——Counter候補は
枚数が少なく、2A-3で確立したreadability（trait badge・family/group
情報）を壊さないため。

## 118. Selected Technique Panel — 変更なし（既存の良い情報を維持）

`_SelectedTechniquePanel`自体の構造・情報（技名・DMG・HEAT・required/
current Energy・使用可能／不可能・unusable reason・trait・posture・
「技を使う」button）は2A-5から変更していない。今回のfixで、
required/result posture Text（`combatV1PlayableRequiredOpponentState
Label`/`combatV1PlayableOpponentResultStateLabel`）に、実装時に欠落
していたkey（`combat_v1_playable_card_required_posture`/
`_result_posture`）を追加した（既存の`_HandCardTile`旧detailed
rendering側には元々付与されていたが、選択panel側に付け忘れていた
——2A-5当時からのbug fix、機能自体は変更していない）。

## 119. Japanese HEAT Unusable Reason（Minor）

`_handCardDisabledMessage`のfinisher HEAT不足分岐が
`'Requires HEAT $threshold (current $heat)'`という英語のまま残って
いたのを、`'HEATが不足しています（必要 $threshold / 現在 $heat）'`
へ日本語化した（HEATというゲーム用語自体は維持）。同じ趣旨で、
使われていなかった（Counter sheetの`_HandCardTile`旧detailed
renderingのみに残存し、実際には到達しないdead code状態だった）
finisher usable時のhint文言も`'HEAT $threshold以上で使用可'`へ
統一した。他の主要判断領域（compact card・selected panel・Counter
prompt）を確認したが、DMG/HEAT/ENERGY/PIN/SUBMISSION/COUNTER/
FINISHERというゲーム内用語以外の不要な英語は見つからなかった。

## 120. Mobile Strategy（320/360/390px）

320/360/390pxいずれも、Wrapによる3列折り返しで統一した——幅ごとに
列数を変える最適化は行っていない（task指示「必ずしも全幅で完全に
同じlayoutである必要はない」を踏まえつつ、最小の変更で「5枚を
scroll無しで比較できる」目標を満たす、最もシンプルな構成を選んだ）。

- `combat_v1_playable_2a5_review_fix_test.dart`「Large Hand Mobile」
  groupで、5枚（`_techA`〜`_techE`、使用可否混在）のcompact cardが
  scroll前に実座標で`combat_v1_playable_technique_area_scroll`
  viewportとintersectしていることを、320/360/390pxそれぞれ確認した
  （`findsOneWidget`だけでなく`getRect`のintersectionで検証）。
- 同groupでcompact cardそれぞれのtap targetを`getRect`と
  `viewport.intersect`から実座標を求めて`tapAt`し、選択panelの名前が
  期待どおり切り替わることまで確認した。
- 「Selected Detail Reachability」groupで、選択後panel（DMG/HEAT/
  Energy/trait/unusable reason/「技を使う」）が320/360/390pxで
  （必要なら縦scrollを許容して）到達可能であることを確認した——
  「一覧＝比較はscroll不要、詳細閲覧は必要に応じてscroll可能」という
  役割分離を実座標で担保する。

## 121. Energy Visibility / LegalAction SSOT（維持）

Energy比較ロジック（`combatV1PlayableEnergyComparisonLabel`/
`combatV1PlayableEnergyAvailableLabel`/`combatV1PlayableEffective
AvailableEnergy`）・`_handCardDisabledMessage`・`card.isUsable`
（controller側で`legalActions`から機械的に導出済み）は一切変更して
いない。compact card・selected panelのどちらも、これら既存の公開
関数・fieldをそのまま参照するだけで、新しいlegality判定・新しい
Energy計算は追加していない。`combat_v1_playable_2a5_review_fix_test.dart`
「Energy Exact Boundary」groupで、required Energy == available
Energyの境界（isUsable境界）でusable/unusableとbutton enabled状態が
正しく切り替わることを、実際のtap→submit経路まで固定した。

## 122. Play vs Discard Distinction（維持）

`_HandRow`のcompactMode追加は`discardMode == false`（technique
選択時）にのみ適用され、discard phaseの表示・操作（`_buildDiscard
Mode`、`_DiscardConfirmPanel`）は変更していない。compact hand card
とdiscard hand card（108px高・DMG/HEAT/Energyを表示しない簡潔な
tile）は見た目が明確に異なる構成のまま維持されている。

## 123. Regression Verification

以下の既存test群を、削除・skipせず、compact hand導入に伴う構造変化
（trait badge・posture・disabled messageが選択後panelへ集約された
こと）に合わせて更新した——検証していた内容自体（trait表示・Energy
不足理由・posture対象明示・discard用途説明等）は変更していない:

- `combat_v1_playable_1c1_clarity_test.dart`（B. Energy／C. COUNTER／
  D. TECHNIQUE DOWN/STAND）
- `combat_v1_playable_2a3_readability_test.dart`（Technique Card —
  Decision Traits）
- `combat_v1_playable_feedback_widget_test.dart`（横scroll cue／
  FINISHER threshold hint）
- `combat_v1_playable_match_screen_test.dart`（unusable card表示）
- `combat_v1_playable_mobile_overflow_test.dart`（Mobile Visibility
  — Technique Card／Technique・Counter Decision Traits B・C）

Playable 2A-2（Guidance/Direction/Recent Log reachability）・2A-3
（Counter Response — Incoming Attack Summary、`counterResponsePending`
経由でcompactModeの影響を受けない）・2A-4（Latest Result/Recent Log/
feedback severity/prevented Direct PIN/prevented Submission/Result
overlay）・2A-5 approved good behavior（日本語化・discard分離・End
Turn・Counter flow）のtestは無変更のまま全green。

## 124. Non-Goals（今回は実装しない）

- Combat Core・LegalAction semantics・CPU AI・wrestler/technique
  data・dependenciesの変更。
- Counter hand（応答時）へのcompact化——枚数が少なく、既存detail
  表示で問題ないため対象外。
- discard handのcompact化——6章の判断どおり、既存UXを維持。
- 幅ごとの列数最適化（320/360/390で異なるWrap列数にする等）——3列
  折り返しの統一構成で目標（5枚scroll無し比較）を満たすため対象外。
