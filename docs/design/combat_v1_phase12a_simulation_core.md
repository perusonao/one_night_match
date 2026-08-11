# Combat Ver.1 Phase 12A — Simulation Core 設計文書

- ステータス: Phase 12A（Simulation Core 実装）完了時点。Codex reviewの3ラウンド
  （1ラウンド目「C. CHANGES REQUIRED」— Major Finding M1: policy factory closure
  問題、Minor Finding: seed serializationの曖昧性／2ラウンド目「C. CHANGES
  REQUIRED」— Blocking Finding M2: simulation match ID・owner ID metadata不足／
  3ラウンド目（PR #15）「C. CHANGES REQUIRED BEFORE MERGE」— Blocking Finding M3:
  simulationMatchIdがmaxActions/rulesを識別子へ含んでいなかった）を、いずれも
  修正済み。
- 関連: [`../combat_rules_v1.md`](../combat_rules_v1.md)（SSOT） /
  [`combat_v1_phase11a_production_match_setup.md`](combat_v1_phase11a_production_match_setup.md) /
  [`combat_v1_phase11b_cpu.md`](combat_v1_phase11b_cpu.md)
- 実装: `lib/src/combat_v1/simulation/combat_v1_simulation_seed.dart` /
  `combat_v1_simulation_policy.dart` / `combat_v1_simulation_config.dart` /
  `combat_v1_match_simulation_result.dart` / `combat_v1_simulation_result.dart` /
  `combat_v1_simulation_runner.dart`
- テスト: `test/combat_v1/combat_v1_simulation_seed_test.dart` /
  `combat_v1_simulation_seed_golden_test.dart` / `combat_v1_simulation_config_test.dart` /
  `combat_v1_simulation_policy_test.dart` / `combat_v1_simulation_runner_test.dart`

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
- Policyの生成をmatch単位で遅延させる`CombatV1SimulationPolicyKind`（Policy metadata、
  5章参照）

Core Engine（`combat_v1_engine.dart`）は変更していない。Production wrestler/deck/card
balance dataも変更していない。

## 5. Simulation Config

`CombatV1SimulationConfig`（`combat_v1_simulation_config.dart`）はimmutableな実行設定。

```dart
CombatV1SimulationConfig({
  required String wrestlerAId,
  required String wrestlerBId,
  required CombatV1SimulationPolicyKind playerAPolicy,
  required CombatV1SimulationPolicyKind playerBPolicy,
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
- `matchCount > 0`
- `maxActions > 0`

Config自身はRandomインスタンスを一切保持しない（`masterSeed`という整数のみを持ち、実際の
`Random`は`CombatV1SimulationRunner`が試合ごとに生成する）。

### Policy metadata（Codex review Major Finding M1対応）

**当初の設計とその問題**: Phase 12A初期実装では、Policyを`String id`＋任意の
`CombatV1DecisionPolicy Function(Random) create`クロージャの組（`CombatV1SimulationPolicySpec`）
で表現していた。Codex exact-HEAD reviewで、これはpublic `CombatV1SimulationConfig`から任意の
factory closureを注入できることを意味し、以下を防げないというMajor Finding（M1）が指摘された:

- external mutable stateをclosureへcaptureできる
- 同じpolicy instanceを複数matchで使い回せる
- closureが供給されたRandomを無視できる
- `id`文字列と実際に生成されたpolicyの`id`を不一致にできる

これらはいずれもPhase 12Aの最重要契約「同じ`CombatV1SimulationConfig` + `masterSeed` +
`matchIndex`から同じsimulationを再現できる」をpublic API上保証できないことを意味する。

**修正後の設計**: `CombatV1SimulationPolicyKind`（`combat_v1_simulation_policy.dart`、新規）は、
Simulationで利用可能なPolicyをPhase 11Bの built-in 2種類（`CombatV1FirstLegalPolicy`/
`CombatV1RandomLegalPolicy`）へ閉じたenum。

```dart
enum CombatV1SimulationPolicyKind {
  firstLegal,
  randomLegal;

  String get policyId => switch (this) { ... }; // 実際のPhase 11B policy.idから読み取る
  CombatV1DecisionPolicy createFresh(Random policyRandom) => switch (this) { ... };
}
```

enumであるため、以下がすべて構造的に保証される（第三者custom policy registry等の汎用拡張
機構はPhase 12Aでは追加しない——必要になった場合は将来Phaseで扱う）:

1. validな`CombatV1SimulationConfig`から任意closureを注入できない——`playerAPolicy`/
   `playerBPolicy`の型が`CombatV1SimulationPolicyKind`である以上、`values`の2種類以外は
   コンパイル時に受け付けない
2. external mutable stateをpolicy生成へ持ち込めない——enum variantはfieldを持たない
   （instance固有のstateを保持しようがない）
3. 各matchでfresh policy instanceを生成する——`createFresh`は毎回新規instanceを返す
   （`CombatV1FirstLegalPolicy`はstateless policyだが、それでも`const`を使わずに
   毎回再構築する——「stateの有無に関わらずinstanceを使い回さない」ことを構造で保証する
   ため）
4. `randomLegal`は必ず[createFresh]へ渡されたRandomをそのまま
   `CombatV1RandomLegalPolicy`のconstructorへ渡す——独自のRandomを新規生成したり、供給
   されたRandomを無視したりしない
5. `firstLegal`はRandomを消費しなくても毎match再構築する（3と同じ理由）
6. `policyId`と実際のPhase 11B policyの`id`が構造上不一致にならない——`policyId`は
   `'firstLegal'`/`'randomLegal'`という文字列literalをSimulation層で別途保持せず、常に
   実際にPhase 11B policyクラスをinstantiateしてその`.id`を読み取ることで値を得る
   （`static final`で1度だけ計算）。Phase 11B側で`id`文字列が変更されれば自動的に
   追従するため、descriptor IDとruntime policy IDが構造的に乖離することはない
7. Simulation Resultの`playerAPolicyId`/`playerBPolicyId`は、実際に実行された
   `CombatV1DecisionPolicy.id`（`CombatV1CpuMatchResult.policyAId`/`policyBId`）から
   転記する——使用policyを識別できる
8. 同一`CombatV1SimulationConfig`と`matchIndex`から`CombatV1SimulationRunner.runSingleMatch`
   を呼び直せば、同じ`CombatV1SimulationPolicyKind`から同じderived seedで同じPolicy
   implementationが再構築される（replayが可能、11章）
9. Phase 11B policy実装（`CombatV1FirstLegalPolicy`/`CombatV1RandomLegalPolicy`）自体を
   複製しない——`createFresh`は既存classのconstructorを呼ぶだけ
10. Phase 11B public API（`combat_v1_decision_policy.dart`）のみを利用する

`combat_v1_simulation_policy_test.dart`が、この10項目のうち直接test可能な性質
（fresh instance保証・descriptor ID一致・供給Random尊重・enum closure）を固定している。

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
   と`lane`識別子（`'match'`）を、[長さ接頭辞方式](#seed-serialization)でbijectiveに直列化する
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

### Seed serialization（Codex review Minor Finding対応）<a name="seed-serialization"></a>

**当初の問題**: `components`を単純に`'|'`区切りでjoinしていたため、要素の内容次第で異なる
`components`列が同じ直列化結果になり得た（例: `['a', 'b|c']`と`['a|b', 'c']`はどちらも単純
joinで`'a|b|c'`になってしまう）。wrestlerId/policyIdは現状レジストリ由来の既知文字列に
限られるため実害は無かったが、任意の文字列を将来受け付けるようになった場合に備え、Codex
reviewは「異なるcomponents列が同じserialized keyになる余地」自体を構造的に排除するよう
指摘した。

**修正内容**: 各要素の直前にUTF-16 code unit数（`String.length`、プラットフォーム非依存）と
`':'`を書き込む長さ接頭辞（length-prefix）方式へ変更した（`_encodeLengthPrefixed`）。

```
parts = ['combatV1SimSeed.v1', '42', '0', 'misaki', 'jack', 'firstLegal', 'randomLegal', 'match']
→ "18:combatV1SimSeed.v1" + "2:42" + "1:0" + "6:misaki" + "4:jack" + "10:firstLegal" + "11:randomLegal" + "5:match"
```

長さが明示されているため、直列化結果から常に一意に元の`parts`列を復元できる——異なる
`parts`列が同じ直列化結果になることは構造上あり得ない（bijective encoding）。

この変更は`hashCode`/`Object.hash`/runtime依存hash/時刻/Engine matchIdのいずれも使用しない
という既存制約を維持したまま行った。Phase 12Aはまだmergeされていないため、この直列化方式を
seed derivation version 1の正式仕様として確定する（バージョンのインクリメントは行わない）。

### VM/Web数値精度の修正（`_mul32`）

Codex reviewの「可能な範囲でVM/Web双方で同一golden値になることを確認する」という要求に
従って実測したところ、`_fnv1a32`/`_mix32`内の乗算（`(hash * prime) & 0xFFFFFFFF`等）が
Dart VM（`dart run`）と dart2js（`dart compile js` + Node.jsで実行）で異なる結果を返す
ことを確認した——32-bit×32-bitの素朴な乗算は最大64-bit相当の中間結果になり得るが、Dart
VM上の`int`は64-bitとして正確に計算できる一方、dart2js/dartdevcでコンパイルされたWeb上
では`int`がJavaScriptのnumber（53-bit精度のdouble）で表現されるため、64-bit相当の中間結果
は精度を失う。

これを`_mul32(a, b)`という16-bit分割の安全乗算へ置き換えて修正した（`aLo*bLo`・
`(aHi*bLo + aLo*bHi) & 0xFFFF`・最終結果、いずれも最大でも約2^33までしか到達せず、
53-bit精度でも誤差なく表現できる）。修正後、`combat_v1_simulation_seed_golden_test.dart`
（7個の`test()`、内部で計9パターンの`deriveV1SimulationSeeds`呼び出しを比較）すべてで
Dart VMとdart2js（Node.js経由）の出力がbit単位で一致することを確認した——「golden
testの数（7）」と「検証した入力パターンの数（9）」は別概念であり、混同しないよう明記する
（Codex review「Golden Test Count Nit」対応）。

### Golden Seed Tests

`combat_v1_simulation_seed_golden_test.dart`が、seed/identity derivationの既知入力→
既知出力を固定literalとしてpinする（実装からその場で計算した値をexpectedにはしない）。
将来アルゴリズムが意図せず変化した場合、この既存golden testがfailすることで検出できる。
M3でRNG seed derivationとsimulation identity derivationを分離したため（前述）、この
ファイルも2つのgroupへ分かれている:

- **A. RNG seed golden vectors**（7個の`test()`）: `deriveV1SimulationSeeds`の
  `matchSeed`/`engineSeed`/`playerAPolicySeed`/`playerBPolicySeed`のgolden値。M3修正
  でも1件も変更していない（`deriveV1SimulationMatchId`が独立したため、RNG seed
  derivationのgolden値は影響を受けない）
- **B. simulationMatchId golden vectors**（7個の`test()`）: `deriveV1SimulationMatchId`
  のgolden値。M3で`maxActions`/`rules`を識別子へ追加したため算出方式自体が変わり、
  golden値もM2時点から全面的に更新されている（Codex reviewが明示的に許容した変更）

カバーするシナリオ（両group共通）:

- normal positive masterSeed
- masterSeed = 0
- negative masterSeed
- mirror wrestler matchup（wrestlerA == wrestlerB）
- wrestlerA/Bが異なるケース（akari vs reina）
- policy identity差（同一masterSeed/matchIndex/wrestlerで、playerAPolicyIdだけを
  firstLegal/randomLegalで変えた場合の両方のgolden値）
- matchIndex差（matchIndex 0/1双方のgolden値、およびEngine/policyA/policyB domain
  separationの確認）

`maxActions`/`rules`の差異ケース（M3固有）は`combat_v1_simulation_seed_test.dart`の
「I. simulationMatchId identity」group（Test A〜D、固定literalではなく構造的な差異の
確認）で扱う。

golden値は本テスト追加・更新時に、Dart VM（`dart run`）とdart2js（`dart compile js` +
Node.jsで実行）の両方で実際に算出し、bit単位で一致することを確認済み。

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

### Resultへの保存（Codex review Blocking Finding M2対応）

`CombatV1SimulationRunner.runSingleMatch`は`playerAOwnerId`/`playerBOwnerId`を1度だけ
計算し、同じローカル変数を(1) `CombatV1ProductionMatchConfig`（実際にphysical card
instance生成へ使われる値）と(2) `CombatV1MatchSimulationResult.fromCpuResult`（Result
metadataとして保存する値）の両方へ渡す。Result用に別途再計算しない設計にすることで、
「Resultに記録されたowner namespace」と「実際にcard instance生成へ使用されたowner
namespace」の一致を構造的に保証する（再計算経路が2つ存在すると、将来の変更でこの2つが
乖離するリスクが生まれるため）。

## 9. Result Model

### CombatV1MatchFinalStateSummary（`combat_v1_match_simulation_result.dart`）

1試合の決着後stateから抽出した平坦化summary。`CombatV1MatchState`自体（hand/drawPile/
discardPileの中身・human可読log等）は保持しない。value equality（`==`/`hashCode`）を持ち、
determinism/replay testで直接比較できる。保持する項目: 両playerのHP/KOC/posture/PIN cards
held/hand・drawPile・discardPileサイズ/reshuffle count、shared HEAT、final phase、
activePlayerIndex、pending attack有無。

### Simulation Match ID（Codex review Blocking Finding M2/M3対応）

Codex reviewの2ラウンド目で、`CombatV1MatchSimulationResult`に(1) Simulator独自の
deterministic match ID、(2) 実際に使用したowner IDが保存されていないというBlocking
Finding M2が指摘された。`CombatV1Engine.start`が生成する`matchId`
（`DateTime.now().microsecondsSinceEpoch`由来）は意図的にResultから除外しているが
（10章）、その代わりとなるSimulator独自のcanonical identityが存在しなかった。

M2時点の初期実装は、`matchSeed`から`'matchId'`という新しいlaneを派生させる方式だった。
しかし3ラウンド目のreviewで、この方式は`maxActions`・`CombatV1RulesConfig`の違いを
`simulationMatchId`へ反映できないというBlocking Finding M3が指摘された——`matchSeed`は
RNG streamの再現にしか関与せず、`maxActions`/`rules`を一切考慮しないため、同じseed/
matchIndex/wrestler/policyのまま`maxActions`や`rules`だけを変えても、試合結果・
terminationが変わるにもかかわらず同じ`simulationMatchId`になってしまう問題があった。

#### M3修正: RNG derivationとsimulation identity derivationの分離

`deriveV1SimulationMatchId`（`combat_v1_simulation_seed.dart`）を、`deriveV1SimulationSeeds`
から完全に独立したpure functionとして新設した。`matchSeed`の派生値ではなく、
`masterSeed`/`matchIndex`/`wrestlerAId`/`wrestlerBId`/`playerAPolicyId`/
`playerBPolicyId`に加えて`maxActions`・`rules`（の全outcome-affecting field、後述）を
直接入力として受け取り、独自のlane（`'simulationMatchId'`）・独自のversion tag
（`combatV1SimulationIdentityVersion`、RNG seedの`combatV1SeedDerivationVersion`とは
独立してバージョン管理）で導出する。

```
sim-v<simulationIdentityVersion>-<masterSeed>-<matchIndex>-<identityValueの8桁16進数>
```

保証する性質:

- **deterministic**: 同一の全引数（`maxActions`/`rules`を含む）なら常に同じ結果
- **match separation**: `matchIndex`が異なれば別の結果になる（`matchIndex`自体も
  文字列内に直接埋め込むことで二重に保証する）
- **maxActions/rules差の反映**: 他の引数が同一でも、`maxActions`や`rules`の
  outcome-affecting fieldが異なれば別の結果になる（M3の核心）
- **Engine matchId independent**: `CombatV1Engine.start`が生成する時刻依存`matchId`を
  一切参照しない
- **Random非消費**: pure functionのみで構成され、`Random`を一切消費しない
- **RNG seedへ無影響**: `deriveV1SimulationSeeds`の結果（したがって既存golden vector
  の`matchSeed`/`engineSeed`/`playerAPolicySeed`/`playerBPolicySeed`）には一切影響しない
  ——2つの関数はもはや共有する計算ステップを持たない（低レベルhash primitiveのみ共有）
- **replay**: `CombatV1SimulationResult.config` + `matchIndex`から
  `CombatV1SimulationRunner.runSingleMatch`を呼び直せば、同じ`simulationMatchId`になる

#### Rules Canonical Representation

`CombatV1RulesConfig`をidentityへ含める際、`toString()`・`hashCode`・`Object.hash`・
runtime依存表現・Map/Set iteration・reflection・`DateTime`のいずれも使わない
——`_rulesIdentityComponents`（`combat_v1_simulation_seed.dart`）が、
`CombatV1RulesConfig`の全19 field（`deckComposition`の4 sub-fieldを含む）を、
`'fieldName', value`という固定順のtag/value pairとして明示的に列挙し、既存の
length-prefix encoding（`_encodeLengthPrefixed`）へそのまま渡す。field名をtagとして
挿入することで、値の並びだけでは区別できない曖昧さを避ける。

対象field一覧（`combat_v1_rules_config.dart`・`combat_v1_deck.dart`より）:

`startingHp` / `startingKoc` / `startingPinCards` / `startingHandSize` /
`deckComposition.normalCount` / `deckComposition.signatureCount` /
`deckComposition.finisherCount` / `deckComposition.counterCount` /
`normalSameNameLimit` / `signatureSameNameLimit` / `finisherSameNameLimit` /
`counterSameNameLimit` / `counterAllowsWildSubstitution` / `totalPinCards` /
`pinCountOneKocCost` / `pinCountTwoKocCost` / `pinCountTwoPointNineKocCost` /
`submissionHpThreshold` / `submissionEscapeKocCost` / `restHpRecovery` /
`roughRestrictedTechniqueLimit` / `finisherHeatThreshold`

reflection・generic serializer・code generationのような大規模な汎用機構は、Phase 12Aの
scopeでは意図的に採用していない——明示的・小規模・review可能な実装を優先した。

**Future Rule Addition Risk**: `CombatV1RulesConfig`に新しいfieldが追加された場合、
`_rulesIdentityComponents`への追加を忘れると、そのfieldの違いが`simulationMatchId`へ
反映されなくなる。これを検知しやすくするため、`combat_v1_simulation_seed_test.dart`の
「I. simulationMatchId identity」group「Test C」が、現時点で列挙済みの19 fieldそれぞれに
ついて「その1 fieldだけを変えると`simulationMatchId`が変わる」ことを網羅的に固定して
いる。新fieldを追加する際は、`_rulesIdentityComponents`とTest Cの両方を更新すること
（コード上のコメントにも同じ注意書きを記載）。

#### VM/Web一致

M3で新設した`deriveV1SimulationMatchId`も、既存の`_mul32`（16-bit分割の安全乗算）・
length-prefix encoding・8桁16進数フォーマットをそのまま利用するため、Dart VMと
dart2js（`dart compile js` + Node.jsで実行）で同一の結果になることを実測で確認済み
（`maxActions`/`rules`の差異ケースを含む）。

### CombatV1MatchSimulationResult

1試合ごとの構造化result。Phase 11Bの`CombatV1CpuMatchResult.fromCpuResult`から詰め替える
factoryで構築し、Simulator側でPIN/SUBMISSION種別やsafetyLimit/invariantViolationの意味を
再解釈しない。保持する項目:

- `matchIndex`/`simulationMatchId`/`wrestlerAId`/`wrestlerBId`
- Owner: `playerAOwnerId`/`playerBOwnerId`（Codex review M2対応、8章参照——実際に
  `CombatV1ProductionMatchConfig`へ渡した値をそのまま転記）
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
`winnerWrestlerId`/`actionCount`/`finalTurnNumber`/`finalStateSummary`/導出されたseed群/
`simulationMatchId`/`playerAOwnerId`/`playerBOwnerId`）を返す。

`CombatV1MatchState.matchId`（`CombatV1Engine.start`が`DateTime.now().microsecondsSinceEpoch`
から生成する時刻依存値）はdeterminism比較対象に含めない——`CombatV1MatchSimulationResult`
自体が`matchId`を一切保持しない設計とすることで、時刻依存値をreplay keyとして誤用できない
ようにしている。

## 11. Replay Metadata

`CombatV1MatchSimulationResult`は、その1試合を再実行するために必要な値
（`wrestlerAId`/`wrestlerBId`/`playerAOwnerId`/`playerBOwnerId`/`playerAPolicyId`/
`playerBPolicyId`/`masterSeed`/`matchSeed`/`engineSeed`/`playerAPolicySeed`/
`playerBPolicySeed`/`seedDerivationVersion`/`maxActions`/`rules`/`matchIndex`/
`simulationMatchId`）をすべて保持する。

ただし実際の再実行には、`CombatV1SimulationPolicyKind`から`CombatV1DecisionPolicy`を生成し
直す処理（`createFresh`）が必要であり、Phase 12Aではresult全体のserializationを行わない。
そのためreplayは、同一の`CombatV1SimulationConfig`（`CombatV1SimulationResult.config`から
取得）と対象の`matchIndex`を組み合わせて`CombatV1SimulationRunner.runSingleMatch`を呼び直す
形で行う（`combat_v1_simulation_runner_test.dart`「G. Replay」参照）。
`CombatV1SimulationPolicyKind`はenumのため、同じkindからは常に同じPolicy実装
（`CombatV1FirstLegalPolicy`/`CombatV1RandomLegalPolicy`）が再構築される（5章）。Phase 12A
ではreplay UIは実装しない。

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
  policy/masterSeed差異によるmatchSeed分離・engine/A/B seed分離・derivation version固定・
  **I. simulationMatchId identity**（Codex review Blocking Finding M3直接固定: Test A
  maxActions差／Test B rules差／Test C 全19 rule fieldの網羅的table-driven確認／Test D
  determinism、およびmatchIndex/wrestler/policy差での分離の維持確認）
- `combat_v1_simulation_seed_golden_test.dart`: RNG seed derivation（group A、golden値
  M3でも不変）とsimulation identity derivation（group B、golden値はM3で全面更新）の
  golden vector、VM/Web両方で算出・一致確認済み
- `combat_v1_simulation_config_test.dart`: valid config・matchCount/maxActions<=0拒否・
  unknown wrestler拒否・policy APIが構造的に2種類へ閉じていること
- `combat_v1_simulation_policy_test.dart`: Codex review Major Finding M1の直接固定
  （descriptor ID/runtime policy ID一致・fresh instance保証・供給Random尊重・external
  mutable state不可）
- `combat_v1_simulation_runner_test.dart`: 1試合実行・複数試合実行（matchIndex安定・owner
  namespace非衝突・match seed一意・card conservation/instanceId uniqueness）・
  determinism（FirstLegal/RandomLegal双方、複数masterSeed）・RNG分離（Simulation Runner
  wiring境界）・replay（`simulationMatchId`/owner ID一致を含む）・safetyLimit保持・
  4 Production Wrestler起動確認・**J. simulationMatchId / owner metadata**
  （Codex review M2/M3直接固定: simulation match ID determinism・matchIndex separation・
  Engine matchId independence・Test A/B（Runner/Result levelでのmaxActions/rules差異、
  RNG seed群不変の確認込み）・owner metadataの実使用値との一致・owner A/B separation・
  match separation・mirror matchでのowner分離）

既存Phase 11Bテスト（`combat_v1_cpu_match_runner_test.dart`等）が既に検証しているCPU対戦
ロジック自体の網羅的な再テストは行わず、Simulation境界として必要な確認のみを追加している。
