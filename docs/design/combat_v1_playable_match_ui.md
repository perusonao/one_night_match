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
3. Counter response（`counterResponsePending`） → 「Counterするか、
   技を受けるか選択してください」（+ legalActionsにCounterが実在
   する場合のみ「無効化できます」を補足）。
4. DOWN decision（`action`かつHuman DOWN） → Stand Up／Restの意味。
5. Action phase（`action`かつHuman STAND） → primaryはlegalActionsに
   実在するkindのみ列挙。secondaryはcontext hintを以下の順で1件のみ
   選ぶ: (a) PIN opportunity → (b) Shared HEAT Finisher unlock →
   (c) Opponent DOWN significance（PINが非legalの場合のみ） →
   (d) continued Technique／Energy（このターン中に既にTechniqueを
   使用済み、かつ現在も合法な場合のみ——「1ターン1Technique」の誤解を
   防ぐ。毎ターン表示しないよう、未使用ターンでは出さない）。

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
