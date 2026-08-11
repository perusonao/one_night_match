# Combat Ver.1 Phase 12A — Simulation Core 設計文書

- ステータス: Phase 12A（Simulation Core 実装）完了時点。
- 関連: [`../combat_rules_v1.md`](../combat_rules_v1.md)（SSOT） /
  [`combat_v1_phase11a_production_match_setup.md`](combat_v1_phase11a_production_match_setup.md) /
  [`combat_v1_phase11b_cpu.md`](combat_v1_phase11b_cpu.md)
- 実装: `lib/src/combat_v1/simulation/combat_v1_simulation_seed.dart` /
  `combat_v1_simulation_config.dart` / `combat_v1_match_simulation_result.dart` /
  `combat_v1_simulation_result.dart` / `combat_v1_simulation_runner.dart`
- テスト: `test/combat_v1/combat_v1_simulation_seed_test.dart` /
  `combat_v1_simulation_config_test.dart` / `combat_v1_simulation_runner_test.dart`

---

## 1. 目的とスコープ

Phase 12Aは、Phase 11Bで完成したCPU対戦基盤（`CombatV1CpuMatchRunner`）とPhase 11Aの
Production Match Setup（`CombatV1ProductionMatchStarter`）を利用して、以下を満たす
「Simulation Core」を実装することを目的とする:

- 同じ設定＋同じseedなら再現可能なCPU vs CPU対戦を、1試合または複数試合実行できる
- 実行結果を構造化された`CombatV1SimulationResult`/`CombatV1MatchSimulationResult`として
  取得できる
- 4 Production Wrestler（misaki/jack/akari/reina）すべてがSimulation Runner経由で起動できる

Simulator自身はCPU対戦ロジック（合法手列挙・意思決定・Engine Command実行・terminal cause
判定・invariant validation）を一切再実装しない——Phase 11Bの`CombatV1CpuMatchRunner`を
呼び出す上位層としてのみ実装する。

## 2. Phase 12Bへ送る項目（スコープ外）

以下はPhase 12A完了時点で意図的に未実装（Phase 12B以降）:

- 4×4 matchup matrix・wrestler別勝率・first-player bias分析・wrestler ranking
- balance statistics（Technique/Counter/REST/HEAT/ENERGY統計）・balance warnings
- CSV/JSON export・dashboard・グラフ・replay UI・Simulator画面等のUI
- heuristic AI・AI tuning・automatic balance adjustment
- isolate並列化・database保存・Engine event sourcing

Phase 12Aは、これらをPhase 12Bが構築するための実行・観測基盤（deterministic simulation
runner・structured result model）のみを提供する。

## 3. Architecture

```
CombatV1SimulationConfig
        |
        v
CombatV1SimulationRunner
        |
        +-- deriveV1SimulationSeeds（deterministic seed derivation）
        +-- combatV1SimulationOwnerId（owner namespace）
        +-- CombatV1ProductionMatchStarter.start（Phase 11A）
        +-- CombatV1CpuMatchRunner.run（Phase 11B）
        |
        v
CombatV1MatchSimulationResult（1試合）
        |
        v
CombatV1SimulationResult（複数試合の集約）
```

`CombatV1SimulationRunner`自身の責務は、(1) `CombatV1SimulationConfig`とmatchIndexから
試合固有のseed群・owner namespaceを決定論的に導出する、(2) Phase 11A/11Bの既存APIをその
seed/namespaceで呼び出す、(3) 結果をSimulation独自のresult modelへ詰め替える、の3点のみ。
CPU対戦ロジック自体はPhase 11Bへ完全委譲する。

## 4. Phase 11Bとの境界

Simulatorが直接呼び出すPhase 11B/11A API:

- `CombatV1ProductionMatchStarter.start`（Phase 11A、試合開始）
- `CombatV1CpuMatchRunner.run`（Phase 11B、bounded single match進行）
- `CombatV1CpuMatchResult`（`termination`/`terminalCause`/`actionCount`/`finalTurnNumber`/
  `lastAction`/`finalState`等、Phase 11Bのstructured result）
- `CombatV1DecisionPolicy`実装（`CombatV1FirstLegalPolicy`/`CombatV1RandomLegalPolicy`）

Simulator側で新規に持つ責務（Phase 11Bが持たないもの）:

- masterSeedから複数試合分のseed群を導出するseed derivation
- 試合をまたいだowner namespace管理（physical instanceId衝突回避）
- 複数試合の実行ループと結果集約（`CombatV1SimulationResult`）
- Policyの生成をmatch単位で遅延させる`CombatV1SimulationPolicySpec`（Policy metadata）

Core Engine（`combat_v1_engine.dart`）は変更していない。Production wrestler/deck/card
balance dataも変更していない。

## 5. Simulation Config

`CombatV1SimulationConfig`（`combat_v1_simulation_config.dart`）はimmutableな実行設定。

```dart
CombatV1SimulationConfig({
  required String wrestlerAId,
  required String wrestlerBId,
  required CombatV1SimulationPolicySpec playerAPolicy,
  required CombatV1SimulationPolicySpec playerBPolicy,
  required int matchCount,
  required int masterSeed,
  int maxActions = 500,
  CombatV1RulesConfig rules = const CombatV1RulesConfig(),
})
```

コンストラクタでfail-fast検証する:

- `wrestlerAId`/`wrestlerBId`が`combatV1ProductionWrestlerRegistry`（Phase 11A）に存在する
  こと——`CombatV1ProductionMatchStarter`と同じレジストリを使い、同じ形で未知wrestlerを拒否
  する
- `playerAPolicy.id`/`playerBPolicy.id`が空白のみでないこと
- `matchCount > 0`
- `maxActions > 0`

Config自身はRandomインスタンスを一切保持しない（`masterSeed`という整数のみを持ち、実際の
`Random`は`CombatV1SimulationRunner`が試合ごとに生成する）。

### Policy metadata

`CombatV1SimulationPolicySpec`（同ファイル）は、Policyの安定したid（`CombatV1DecisionPolicy.id`
と同じ値、例: `firstLegal`/`randomLegal`）と、match毎に導出されたPolicy Randomを受け取って
`CombatV1DecisionPolicy`を生成するfactoryの組。

```dart
class CombatV1SimulationPolicySpec {
  final String id;
  final CombatV1DecisionPolicy Function(Random policyRandom) create;

  static const firstLegal = CombatV1SimulationPolicySpec(...);
  static const randomLegal = CombatV1SimulationPolicySpec(...);
}
```

`CombatV1RandomLegalPolicy`はconstructorでRandomを要求するstateful policyのため、Config側で
単一インスタンスとして保持すると複数試合で同じ乱数sequenceを使い回してしまう。`create`を
match毎に呼び出すことで、試合ごとに独立したPolicy Randomを注入する。Phase 12Aでは
`firstLegal`/`randomLegal`の2種のみを想定し、heuristic policy framework等の拡張は行わない。

## 6. Seed Strategy

`combat_v1_simulation_seed.dart`が、以下の階層でseedを導出する:

```
masterSeed
    |
    +-- matchSeed（masterSeed + matchIndex + wrestlerAId/BId + policyAId/BId から導出）
            |
            +-- engineSeed
            +-- playerAPolicySeed
            +-- playerBPolicySeed
```

`deriveV1SimulationSeeds`は`CombatV1SimulationSeedSet`（`matchIndex`/`masterSeed`/`matchSeed`/
`engineSeed`/`playerAPolicySeed`/`playerBPolicySeed`/`derivationVersion`）を返すpure function。
同じ`masterSeed`・`matchIndex`・`wrestlerAId`・`wrestlerBId`・`playerAPolicyId`・
`playerBPolicyId`なら常に同じ結果を返す。`wrestlerAId`/`wrestlerBId`/policy idのいずれかが
変わればmatchSeedも変わる——同じ`masterSeed`/`matchIndex`のまま対戦カードやpolicyだけを
差し替えて複数のSimulationを実行しても、seed群が意図せず衝突しない。

### derivation方式

1. `masterSeed`/`matchIndex`/`wrestlerAId`/`wrestlerBId`/`playerAPolicyId`/`playerBPolicyId`
   と`lane`識別子（`'match'`）を`'|'`区切りの文字列へ直列化する
2. 自前実装の32-bit FNV-1aハッシュで整数化する（`String.hashCode`/`Object.hashCode`は
   プラットフォーム間の安定性が保証されないため使用しない）
3. MurmurHash3 finalizer相当の32-bit deterministic mixer（`_mix32`）でavalancheを高める

`matchSeed`が決まった後、`engineSeed`/`playerAPolicySeed`/`playerBPolicySeed`はそれぞれ
`matchSeed`と異なる`lane`文字列（`'engine'`/`'policyA'`/`'policyB'`）から同じ手順で導出する。
`Random`を順番に呼び出して子seedを作る方式（呼び出し回数の変化に脆弱）は採用していない。

`combatV1SeedDerivationVersion`（現在`1`）を`CombatV1SimulationSeedSet.derivationVersion`
として公開し、Simulation Resultのreplay metadataへも記録する。derivationロジックを変更する
場合は必ずインクリメントする。

Phase 12Aでは32-bit mixerによる小規模実装で十分とし、暗号学的な強度は要求しない。

## 7. RNG Separation

`CombatV1SimulationRunner.runSingleMatch`は、1試合につき独立した3本の`Random`インスタンスを
生成する:

- **Engine Random**（`Random(seeds.engineSeed)`）: `CombatV1ProductionMatchStarter.start`の
  初期shuffle・手札配布から、`CombatV1CpuMatchRunner.run`のEngine Command実行
  （shuffle/draw/PIN/COUNTER解決）まで、1試合を通して同一instanceを継続して使う——Simulation
  Core自身が「Engine Random」を試合全体で単一のRNG streamとして扱う設計とした
- **Player A Policy Random**（`Random(seeds.playerAPolicySeed)`）
- **Player B Policy Random**（`Random(seeds.playerBPolicySeed)`）

3本はいずれも独立した`Random`インスタンスであり、Simulation Core自身が他のRandomを共有・
再利用することはない。Phase 11B（`CombatV1CpuMatchRunner`）が既に持つRNG分離契約
（policyのRandom呼び出し回数がEngine RNG/他playerのpolicy RNGへ影響しない）をそのまま
利用し、壊していない。

`combat_v1_simulation_runner_test.dart`のRNG分離テストでは、(1) playerB Policy Randomの
seedを変えてもplayerAの最初の意思決定が変化しないこと、(2) playerAのPolicy Random消費回数
（`_BurnThenFirstLegalPolicy`で意図的に変化させる）が変化しても、選択結果自体が同じである
限りEngine Random由来のfinalStateが変化しないこと、を確認している。

### 設計上の注意（engineSeedと初期手札配布の関係）

Engine RandomはEngineの初期shuffle（手札配布）にも使われるため、`engineSeed`を変えると
初期手札構成そのものが変わり、結果としてplayerAの最初の合法手集合も変わりうる。これはRNG
分離違反ではなく、Engine Randomが正しく試合状態へ影響している証拠であり、意図した挙動
である。RNG分離が保証するのは「Policy Randomの呼び出し回数・タイミングがEngine Random/
他playerのPolicy Randomへ影響しないこと」であり、「Engine Randomを変えても試合状態が
変化しないこと」ではない。

## 8. Owner Namespace

`combatV1SimulationOwnerId`（`combat_v1_simulation_runner.dart`）が、
`sim-<masterSeed>-<matchIndex>-<a|b>`という形式でplayerA/Bのowner namespaceを決定論的に
生成する。

- wrestlerIdそのものはownerIdとして使わない（同一wrestlerのmirror matchでplayerA/Bの
  physical instanceIdが衝突する原因になるため）
- `masterSeed`を含めることで、複数のSimulationを跨いでもownerIdの意味が明確になる
- 現在時刻は使わない（再現性を壊すため）

## 9. Result Model

### CombatV1MatchFinalStateSummary（`combat_v1_match_simulation_result.dart`）

1試合の決着後stateから抽出した平坦化summary。`CombatV1MatchState`自体（hand/drawPile/
discardPileの中身・human可読log等）は保持しない。value equality（`==`/`hashCode`）を持ち、
determinism/replay testで直接比較できる。保持する項目: 両playerのHP/KOC/posture/PIN cards
held/hand・drawPile・discardPileサイズ/reshuffle count、shared HEAT、final phase、
activePlayerIndex、pending attack有無。

### CombatV1MatchSimulationResult

1試合ごとの構造化result。Phase 11Bの`CombatV1CpuMatchResult.fromCpuResult`から詰め替える
factoryで構築し、Simulator側でPIN/SUBMISSION種別やsafetyLimit/invariantViolationの意味を
再解釈しない。保持する項目:

- `matchIndex`/`wrestlerAId`/`wrestlerBId`
- Policy: `playerAPolicyId`/`playerBPolicyId`
- Seed: `masterSeed`/`matchSeed`/`engineSeed`/`playerAPolicySeed`/`playerBPolicySeed`/
  `seedDerivationVersion`
- `maxActions`/`rules`（replay metadataの一部）
- Execution: `termination`/`terminalCause`/`winnerPlayerIndex`/`winnerWrestlerId`/
  `actionCount`/`finalTurnNumber`/`safetyLimitReached`/`lastAction`/
  `invariantViolationMessage`
- `finalStateSummary`（`CombatV1MatchFinalStateSummary`）

full action traceやfinalState自体（`CombatV1MatchState`全体）は保持しない——Result肥大化を
避けるため。

### CombatV1SimulationResult（`combat_v1_simulation_result.dart`）

複数試合実行結果。`config`（実行に使った`CombatV1SimulationConfig`のsnapshot）・`matches`
（unmodifiable）・`requestedMatchCount`・`executedMatchCount`を持つ。整合確認用に
`completedCount`/`safetyLimitCount`/`invariantViolationCount`のderived getterのみを提供し、
勝率・平均値等の本格集計（Phase 12Bのスコープ）は含めない。

## 10. Determinism Contract

同一`config`・`matchIndex`（したがって同一`masterSeed`/`wrestlerAId`/`wrestlerBId`/
`playerAPolicy`/`playerBPolicy`）なら、`CombatV1SimulationRunner.runSingleMatch`は常に
ゲーム上意味のある同一情報（`termination`/`terminalCause`/`winnerPlayerIndex`/
`winnerWrestlerId`/`actionCount`/`finalTurnNumber`/`finalStateSummary`/導出されたseed群）を
返す。

`CombatV1MatchState.matchId`（`CombatV1Engine.start`が`DateTime.now().microsecondsSinceEpoch`
から生成する時刻依存値）はdeterminism比較対象に含めない——`CombatV1MatchSimulationResult`
自体が`matchId`を一切保持しない設計とすることで、時刻依存値をreplay keyとして誤用できない
ようにしている。

## 11. Replay Metadata

`CombatV1MatchSimulationResult`は、その1試合を再実行するために必要な値
（`wrestlerAId`/`wrestlerBId`/`playerAPolicyId`/`playerBPolicyId`/`masterSeed`/`matchSeed`/
`engineSeed`/`playerAPolicySeed`/`playerBPolicySeed`/`seedDerivationVersion`/`maxActions`/
`rules`/`matchIndex`）をすべて保持する。

ただし実際の再実行には、Policy id文字列からPolicy Random生成factoryへ戻すこと（closureの
serialization）が必要であり、Phase 12Aではこれを行わない。そのためreplayは、同一の
`CombatV1SimulationConfig`（`CombatV1SimulationResult.config`から取得）と対象の`matchIndex`
を組み合わせて`CombatV1SimulationRunner.runSingleMatch`を呼び直す形で行う
（`combat_v1_simulation_runner_test.dart`「G. Replay」参照）。Phase 12Aではreplay UIや
result全体のserializationは実装しない。

## 12. safetyLimit / invariantViolation Semantics

Phase 11Bの`CombatV1CpuMatchTermination`（`matchOver`/`safetyLimit`/`invariantViolation`）を
そのまま`CombatV1MatchSimulationResult.termination`へ転記する。Simulator側で:

- `safetyLimit`をdraw/loss/winへ変換することはない（`winnerPlayerIndex`/`winnerWrestlerId`は
  `null`のまま）
- `invariantViolation`を握りつぶしたり、別のterminationへ読み替えたりしない
- 人間可読logを解析してPIN/submission/direct PIN/submission finisherを独自判定することはない
  （`terminalCause`はPhase 11Bが分類した値をそのまま転記する）

Phase 12Aでは原則としてPhase 11B Runnerの通常invariant validationを有効にしたまま実行する
（`CombatV1CpuMatchRunner`の3箇所のcheckpointをそのまま利用）。将来の大規模simulation向けに
これを無効化可能にする設計余地は残すが、Phase 12Aでは性能最適化を行わない。

## 13. Test Coverage概要

- `combat_v1_simulation_seed_test.dart`: pure function・determinism・matchIndex/wrestler/
  policy/masterSeed差異によるmatchSeed分離・engine/A/B seed分離・derivation version固定
- `combat_v1_simulation_config_test.dart`: valid config・matchCount/maxActions<=0拒否・
  unknown wrestler拒否・invalid policy拒否
- `combat_v1_simulation_runner_test.dart`: 1試合実行・複数試合実行（matchIndex安定・owner
  namespace非衝突・match seed一意・card conservation/instanceId uniqueness）・
  determinism（FirstLegal/RandomLegal双方、複数masterSeed）・RNG分離（Simulation Runner
  wiring境界）・replay・safetyLimit保持・4 Production Wrestler起動確認

既存Phase 11Bテスト（`combat_v1_cpu_match_runner_test.dart`等）が既に検証しているCPU対戦
ロジック自体の網羅的な再テストは行わず、Simulation境界として必要な確認のみを追加している。
