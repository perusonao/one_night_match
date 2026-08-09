# Combat Ver.1 — Phase 1 技術設計（Core Skeleton）

- ステータス: **Phase 0確定版**（設計のみ。`lib/src/combat_v1/`はまだ作成していない）
- 対象仕様: [`../combat_rules_v1.md`](../combat_rules_v1.md)（SSOT）
- 未決定事項: [`combat_v1_open_questions.md`](combat_v1_open_questions.md)
- 位置づけ: Phase 1「Core Skeleton」（UIなしで最小戦闘ループを実行できる状態）の技術設計。
  実装（コード・テストコード）はまだ行っていない。実装開始は別途指示を受けてから行う。

## 更新履歴

- Phase 0 第2回設計レビューで以下を反映して更新:
  - KOC・PINカード保有数（`koc`／`pinCardsHeld`）をPhase 1のPlayerStateへ前倒しで追加（旧案はPhase 5で追加としていた）
  - `CombatV1FinisherType`を独立enumとして追加（旧案は`directPin`/`submissionHold`からの導出案だったが不採用）
  - ＊ENERGYの解決アルゴリズムを確定（具体属性優先→不足分合算→＊で補完）
  - 不正Command呼び出し時は`CombatV1IllegalActionException`を送出する方針を確定
  - `winner`/`isOver`はPhase 1で追加しないことを正式決定（7章参照）

---

## 1. Phase 1 ディレクトリ構成

既存①②③の慣行（サブフォルダなし、`<prefix>_<role>.dart`によるフラット構成）に合わせる。

```
lib/src/combat_v1/
  combat_v1_enums.dart         … 共有enum（属性・状態・カード区分・フェーズ・FinisherType）
  combat_v1_energy.dart        … EnergyPool / EnergyCost / 支払い解決ロジック
  combat_v1_technique.dart     … CombatV1Technique（技カード定義モデル）
  combat_v1_counter.dart       … CombatV1Counter（COUNTERカード、Phase1は最小形）
  combat_v1_deck.dart          … DeckEntry / DeckDefinition / DeckComposition
  combat_v1_wrestler.dart      … CombatV1Wrestler（静的レスラープロフィール）
  combat_v1_rules_config.dart  … CombatV1RulesConfig（調整可能なルール定数）
  combat_v1_match_state.dart   … CombatV1PlayerState / CombatV1MatchState
  combat_v1_engine.dart        … CombatV1Engine（Command API本体、例外クラス含む）
```

ファイル数がおおよそ15〜20を超えて見通しが悪くなった時点で、`models/`／`engine/`／`rules/`／`simulation/`への
サブフォルダ化を再検討する（現時点では時期尚早と判断）。

Phase2以降、同ディレクトリ直下に `combat_v1_counter_rules.dart` / `combat_v1_pin_rules.dart` /
`combat_v1_submission_rules.dart` / `combat_v1_rest_rules.dart` / `combat_v1_rough_rules.dart` /
`combat_v1_finisher_rules.dart` を追加していく想定（8章「拡張ポイント」参照）。

`cpu/`・`simulation/`・UI関連ディレクトリはPhase 1では作成しない。

---

## 2. Phase 1 データモデル

### 2.1 共有enum（`combat_v1_enums.dart`）

| enum | 値 | 用途 |
|---|---|---|
| `CombatV1EnergyAttribute` | `strike`(打) / `joint`(関) / `throwing`(投) / `aerial`(飛) / `rough`(ラフ) / `wild`(＊) | ENERGY属性。既存`MoveAttribute`とは非依存の新規enum |
| `CombatV1WrestlerPosture` | `stand` / `down` | Ver.1は`fatigued`相当の第3状態を持たない（HP0≠自動DOWN） |
| `CombatV1CardCategory` | `normal` / `signature` / `finisher` / `counter` | デッキの4区分。技カテゴリ検証・COUNTERカードの識別を兼ねる |
| `CombatV1MatchPhase` | `setup` / `discard` / `action` / `turnEnd` | 3章参照 |
| `CombatV1FinisherType` | `normal` / `directPin` / `submission` | **今回追加**。FINISHERの決着方式を独立enumで保持（技のsubmissionHoldフラグからは導出しない） |

### 2.2 各モデル

| モデル | 責務 | 主要フィールド | mutable方針 | JSON化 | 後続Phaseとの関係 |
|---|---|---|---|---|---|
| `CombatV1RulesConfig` | 調整可能な数値の一元管理 | `startingHp=150`, `startingKoc=10`, `startingPinCards=2`, `startingHandSize=5`, `deckComposition`(§2.3), `normalSameNameLimit=3` | immutable, `const` | 不要 | Phase5でKOC消費量・PINカード総数(4)、Phase7でREST回復量、Phase9でFINISHER解禁HEAT(200)を追記 |
| `CombatV1EnergyPool` | レスラー固有の固定ENERGY量を保持 | `Map<CombatV1EnergyAttribute,int> amounts` | immutable | 不要 | Phase4のCOUNTER支払いでも同じ型を再利用 |
| `CombatV1EnergyCost` | 技が要求するENERGYを保持（Poolとは別モデル） | `Map<CombatV1EnergyAttribute,int> amounts`（`wild`は要求側に現れない） | immutable | 不要 | Phase4でCOUNTER側のコスト（＝相手技のcost）としてもそのまま再利用可能 |
| `CombatV1Technique` | 技1枚の静的定義 | `id`, `name`, `category`, `attribute`, `energyCost`, `damage`, `heatGain`, `requiredOpponentState`(nullable), `causesDown`(bool), `familyId`(nullable String, Phase4予約), `directPin`(bool, default false, category!=finisherの場合のみ意味を持つ), `submissionHold`(bool, default false, 汎用フラグ), `finisherType`(nullable `CombatV1FinisherType`, category==finisherの場合のみ意味を持つ) | immutable, `const` | 不要 | §2.4に詳細 |
| `CombatV1Counter` | COUNTERカード1枚の静的定義（Phase1は最小形） | `id`, `name`, `attribute`, `counterableFamilyIds`(空リスト初期値, Phase4予約) | immutable, `const` | 不要 | Phase4で判定ロジックを追加してもモデル自体は壊さない |
| `CombatV1DeckComposition` | デッキのカテゴリ別枚数設定 | `normalCount=18`, `signatureCount=4`, `finisherCount=2`, `counterCount=6`（合計30を検証するgetter） | immutable, `const` | 不要 | Phase10で種別ごとの内訳（基本技3枚等）を扱う上位モデルを追加する余地を残す |
| `CombatV1DeckEntry` | デッキ内の物理カード1枚 | `instanceId`, `cardId`, `category` | immutable | 不要 | Phase4以降もそのまま使える |
| `CombatV1DeckDefinition` | 1人ぶんの30枚デッキ定義 | `wrestlerId`, `entries: List<CombatV1DeckEntry>` | immutable | 不要 | Phase10で正式データに差し替え。Phase1はテスト用フィクスチャで足りる |
| `CombatV1Wrestler` | レスラー静的プロフィール | `id`, `name`, `energyPool: CombatV1EnergyPool` | immutable, `const` | 不要 | Phase10でレスラー追加時もモデル変更不要 |
| `CombatV1PlayerState` | 1人の試合内状態（スナップショット） | `wrestlerId`, `wrestlerName`, `maxHp`, `hp`(0でクランプ), `koc`(**今回追加**), `pinCardsHeld`(**今回追加**), `posture`, `energyPool`, `spentEnergy`, `drawPile`, `hand`, `discardPile`, `reshuffleCount`, `techniquesUsedThisTurn` | immutable, `copyWith` | 不要 | §2.5参照 |
| `CombatV1MatchState` | 試合全体の不変ルート状態 | `matchId`, `playerA`, `playerB`, `activePlayerIndex`, `sharedHeat`, `turnNumber`, `phase`, `log: List<String>` | immutable, `copyWith` | 不要 | `winnerIndex`/`isOver`は**Phase1では追加しない**（§2.6で再評価の結論を記載） |

### 2.3 `CombatV1DeckComposition`の初期値

```
normalCount = 18, signatureCount = 4, finisherCount = 2, counterCount = 6  (合計30)
```

ENERGYカードは含まない。Phase1のテストは実データではなく最小フィクスチャで検証する。

### 2.4 `CombatV1Technique`のFINISHER関連フィールドについて（今回の変更点）

前回設計案では`finisherType`を`directPin`/`submissionHold`から導出する方針だったが、**不採用**とし、
独立enum `CombatV1FinisherType`を明示的に保持する方式へ変更した（`combat_rules_v1.md` 13章）。

**優先順位ルール（今回確定）**:
- `category == finisher` の場合: `finisherType`（`normal`/`directPin`/`submission`）が決着方式を決定する。
  この場合、`directPin`/`submissionHold`の値は参照しない（値を持たせても無視する。矛盾する値を持たせないための
  検証は現時点では型システムに強制させず、Phase10のデータ投入時のレビューで担保する）。
- `category != finisher`（NORMAL/SIGNATURE）の場合: `directPin`/`submissionHold`のみが意味を持つ。
  `finisherType`は`null`とする。

これにより、「技がSUBMISSION属性を持つこと」と「FINISHERとしてSUBMISSION決着方式を持つこと」が
型レベルでも明確に分離される。

Phase1ではこれらのフィールドは**保持するが判定には使わない**（値を持たせるだけ）。

`familyId`は`String?`（自由文字列、nullable）とし、専用enumは今回作らない（技系統マスタが未確定のため）。

### 2.5 `CombatV1PlayerState`へのKOC・PINカード前倒し追加について

前回設計案ではPhase 5で追加する提案だったが、**今回KOC・PINカードはCombat Ver.1の基本リソースとして
Phase 1のPlayerStateから保持する**方針に変更した（`combat_rules_v1.md` 2章・8章・9章）。

- `koc: int`（初期値10）
- `pinCardsHeld: int`（初期値2）

Phase 1では**消費・判定ロジックは実装しない**。試合開始時に正しい初期値が設定されることのみを対象とする
（7章「今回の変更点の影響」参照）。

### 2.6 `winner`/`isOver`の再評価結論

**Phase 1では追加しない**（前回設計時の判断を維持）。

理由: Phase 1にはPIN・SUBMISSION・FINISHERいずれの決着条件も実装されないため、試合が「終了する」経路が
存在しない。KOC・PINカードをPhase 1のPlayerStateへ追加したこと自体は決着条件の実装を意味しない
（あくまで初期化のみが対象）。決着条件が一切ない状態で`isOver`/`winner`フィールドを持たせても、
常に未設定・未使用のまま残る「死んだフィールド」になるため、引き続き追加を見送る。
Phase 5（PIN/KOC）・Phase 6（SUBMISSION）・Phase 9（FINISHER）のいずれかで、実際の決着条件と同時に追加する。

---

## 3. Match State Machine（Phase 1）

過去の「無限手番」バグ（③のCPU多様性ペナルティが唯一の合法手を拒否し続けた事例）を踏まえ、
**エンジン自身は自律的な選択を一切行わない**（常に外部からの明示的なコマンド呼び出しでのみ状態が進む）
設計とし、不正な呼び出しは黙って無視せず例外を送出する（4章）。

外部から観測可能なフェーズは4つのみ。`turnStart`/`draw`は`start`/`endTurn`の内部処理として吸収する。

```
setup ──(start)──▶ discard ──(discardCard)──▶ action ──(playTechnique)*──▶ action
                       ▲                           │
                       │                        (endTurn)
                       └───────────(内部でturnStart+draw実行)───────────┘
```

| フェーズ | 意味 | 許可コマンド | 遷移条件 |
|---|---|---|---|
| `setup` | `start()`実行前の概念上の初期状態（外部からは観測されない） | — | — |
| `discard`（ターン開始直後） | ENERGY全回復＋1ドロー済み、手札から1枚捨てる必要がある | `discardCard(instanceId)` | 捨てたら`action`へ |
| `action` | TECHNIQUE使用または攻撃継続/ターン終了を選べる | `playTechnique(instanceId)` / `endTurn()` | `playTechnique`後も`action`のまま。`endTurn`で相手の`discard`へ |
| `turnEnd`（内部遷移） | `endTurn()`呼び出し直後、次のプレイヤーのturnStart（ENERGY全回復・techniquesUsedThisTurnリセット）＋draw（山札再構築含む）を自動実行 | — | 完了後、新active playerの`discard`へ |

**設計上のポイント**（前回設計から変更なし）:
- `action`フェーズで使える技がなくても、エンジンは自動でターンを終了しない。判定は
  `hasAnyPlayableTechnique(state)`という読み取り専用ヘルパーを使うかどうか、呼び出し側の責務とする。
- `activePlayerIndex`は一連のフェーズ遷移全体を通じて単一の値。Phase1には攻守交代の概念が存在しない
  （COUNTERが無いため）。Phase4で`CombatV1MatchPhase`へ`counterResponsePending`等を追加する想定。

---

## 4. Engine API

`CombatV1Engine`は不変状態を受け取り、新しい不変状態を返す静的関数群とする。UI/CPU/Simulator/Testは
すべて同じAPIを呼ぶ（UI Widgetを一切渡さない）。

```dart
class CombatV1Engine {
  static CombatV1MatchState start({
    required CombatV1Wrestler wrestlerA,
    required CombatV1DeckDefinition deckA,
    required CombatV1Wrestler wrestlerB,
    required CombatV1DeckDefinition deckB,
    required CombatV1RulesConfig rules,
    Random? random,
  });

  static CombatV1MatchState discardCard(CombatV1MatchState state, String instanceId);
  static CombatV1MatchState playTechnique(CombatV1MatchState state, String instanceId);
  static CombatV1MatchState endTurn(CombatV1MatchState state);

  // ---- 読み取り専用の判定API（例外を出さず安全に呼べる） ----
  static CombatV1ActionCheck checkTechniqueLegality(CombatV1MatchState state, String instanceId);
  static bool hasAnyPlayableTechnique(CombatV1MatchState state);
}

class CombatV1ActionCheck {
  const CombatV1ActionCheck(this.legal, this.reason);
  final bool legal;
  final String reason;
}

class CombatV1IllegalActionException implements Exception {
  CombatV1IllegalActionException(this.message);
  final String message;
}
```

**不正呼び出しの扱い（今回確定）**: フェーズ不一致・ENERGY不足・手札に存在しないカード・使用条件を
満たさないTECHNIQUEなどの場合、`discardCard`/`playTechnique`/`endTurn`は同じstateを黙って返す
（silent no-op）のではなく `CombatV1IllegalActionException` を投げる（fail-fast）。
ただし`checkTechniqueLegality()`等の読み取り専用APIは、例外ではなく`legal`/`reason`を返す方式のままとする。

---

## 5. ENERGY支払い仕様（今回確定）

`CombatV1EnergyPool`（固定・不変）と`CombatV1PlayerState.spentEnergy`（このターンでの使用済み量）を
別々に持ち、`availableEnergyFor(a) = pool.amountFor(a) - (spentEnergy[a] ?? 0)`で残量を都度計算する。
ターン開始時の「全回復」は`spentEnergy`を空`{}`へリセットするだけで、`energyPool`自体は変化しない。

```dart
class CombatV1EnergyPaymentResult {
  const CombatV1EnergyPaymentResult.success(this.updatedSpent) : failureReason = null;
  const CombatV1EnergyPaymentResult.failure(this.failureReason) : updatedSpent = null;
  final Map<CombatV1EnergyAttribute, int>? updatedSpent;
  final String? failureReason;
  bool get isSuccess => updatedSpent != null;
}

CombatV1EnergyPaymentResult resolveEnergyPayment({
  required CombatV1EnergyPool pool,
  required Map<CombatV1EnergyAttribute, int> spent,
  required CombatV1EnergyCost cost,
  required bool allowWildSubstitution, // Phase1のTECHNIQUE支払いは常にtrue。Phase4のCOUNTERでは別値を渡せる
}) { ... }
```

**解決アルゴリズム（確定）**:
1. 各具体属性（打・関・投・飛・ラフ）についてコストと残量を比較し、不足分を求める。
2. 不足分を属性横断で**合算**する。
3. 合算した合計不足分が、保有する＊(wild)の残量以下であれば支払い成立。属性ごとに個別の
   ワイルド消費順序は設けない（＊は属性を跨いで融通できる共有資源）。

**COUNTERでの扱い**: `allowWildSubstitution`という引数を用意するだけで、Phase4でCOUNTER側のポリシーが
決まった時点で値を差し替え可能にしている。ポリシー自体の中身はPhase4まで確定しない。

---

## 6. Phase 1 テスト計画

```
test/combat_v1/
  combat_v1_engine_test.dart   … Match初期化〜ターン進行の一連のテスト（メイン）
  combat_v1_energy_test.dart   … Pool/Cost/ワイルド支払いの単体テスト
  combat_v1_deck_test.dart     … デッキ構成・シャッフル・山札再構築の単体テスト
```

| ファイル | テストケース |
|---|---|
| `combat_v1_engine_test.dart` | Match初期化（`start`でphase=discardになる）／HP150／KOC10／PIN CARD 2枚ずつ／共有HEAT0／ENERGY初期値（レスラー固有Pool通り）／初期手札5枚／30枚デッキ／ターン開始ENERGY全回復（`spentEnergy`が空になる）／ターン開始1ドロー／1ディスカード（`discard`フェーズでのみ許可、他フェーズで呼ぶと例外）／TECHNIQUE DMG適用／HP0クランプ（負にならない）／HP0で試合終了しない（`isOver`相当のフィールド自体が存在しないことをもって検証）／共有HEAT加算／TECHNIQUE後1ドロー／同一ターン複数TECHNIQUE（ENERGYが尽きるまで`playTechnique`を繰り返し呼べる）／ターン終了（activePlayerIndex交代・turnNumber増加）／山札再構築（合計枚数保存）／FATIGUEなし（山札切れ時にHP/HEATが変化しない）／不正Commandが例外になる（`CombatV1IllegalActionException`） |
| `combat_v1_energy_test.dart` | TECHNIQUE COST支払い（具体属性のみで足りるケース）／ENERGY不足時にTECHNIQUE使用不可（`checkTechniqueLegality`がfalseを返す、`playTechnique`は例外）／＊ENERGY（単一属性不足を＊で補うケース）／複数属性不足を＊で補完（合算方式の検証） |
| `combat_v1_deck_test.dart` | デッキ30枚（`normal18+signature4+finisher2+counter6`の内訳検証）／山札再構築（ドロー時に山札が空なら捨て札をシャッフルして山札にする） |

KOC/PINカードは初期化のみが対象（消費・判定はPhase5）。COUNTER/PIN/SUBMISSION/REST/ROUGH/FINISHER関連の
判定テストはPhase1では作成しない（該当ロジックが存在しないため）。すべて`Random(固定seed)`を使い
再現可能にする。

---

## 7. 今回の変更点による影響

### 7.1 KOC / PINカードをPhase 1へ追加したことによる影響

- `CombatV1PlayerState`のフィールドが2つ増える（`koc`, `pinCardsHeld`）が、**ロジックへの影響はない**
  （Phase1のCommand API・State Machineはこれらのフィールドを一切参照しない）。
- Phase1のテストに初期値検証（KOC=10、PINカード=2枚ずつ）が追加される。
- `CombatV1RulesConfig`に`startingKoc`/`startingPinCards`の2定数が追加される。
- リスクとしては、Phase5でPIN/KOCの本ロジックを実装する際に、Phase1で先に確定させた初期値・型
  （`int`単純型）で不足がないかを再確認する必要がある（例: PINカード総数4枚のうち「共有プール」としての
  管理が必要になった場合、`CombatV1MatchState`側にも`totalPinCardsInPlay`のような検証用フィールドが
  必要になるかもしれない——ただしこれはPhase5で判断する）。

### 7.2 FinisherTypeを独立enumにしたことによる影響

- `CombatV1Technique`に`finisherType: CombatV1FinisherType?`フィールドが追加される。
- `directPin`/`submissionHold`との優先順位ルール（§2.4）をコード上のコメントとして明記する必要がある
  （型システムだけでは「category==finisherのときはfinisherTypeが優先」という規約を強制できないため）。
- Phase9（FINISHER実装）で、`finisherType`の値に応じた3分岐（normal/directPin/submission）を
  `combat_v1_finisher_rules.dart`に実装する際、モデル変更は不要（enumの値を読むだけで済む）。
- Phase1では実害はない（値を保持するのみで、判定には使わない）。

---

## 8. Phase 2以降への拡張ポイント

| 機能 | 追加場所（想定） | 既存モデルへの影響 |
|---|---|---|
| COUNTER本処理 | `combat_v1_counter_rules.dart`（新規）＋ENERGYの`allowWildSubstitution`ポリシー確定 | `CombatV1Counter.counterableFamilyIds`を実データで埋める。`CombatV1MatchPhase`に応答待ちフェーズを追加 |
| PIN / KOC | `combat_v1_pin_rules.dart`（新規） | `CombatV1PlayerState.koc`/`pinCardsHeld`（Phase1で追加済み）を実際に消費・移動させるロジックを追加 |
| SUBMISSION | `combat_v1_submission_rules.dart`（新規） | `CombatV1Technique.submissionHold`を実データで使用開始 |
| REST | `combat_v1_rest_rules.dart`（新規） | `CombatV1MatchPhase`にDOWN時の選択フェーズを追加、`CombatV1RulesConfig.restHpRecovery`を追加 |
| ROUGH | `combat_v1_rough_rules.dart`（新規） | `CombatV1PlayerState.techniquesUsedThisTurn`（Phase1で用意済み）を上限判定に利用 |
| FINISHER | `combat_v1_finisher_rules.dart`（新規） | `CombatV1Technique.finisherType`（Phase1で用意済み）を使用開始。`CombatV1RulesConfig.finisherHeatThreshold=200`を追加 |
| CPU | `lib/src/combat_v1/cpu/`（新規） | `checkTechniqueLegality`等の読み取り専用APIのみを使う設計。Engine本体は変更不要 |
| Simulator/Report/Diagnostics | `lib/src/combat_v1/simulation/`（新規、②のConfig/Simulator/Report/Diagnostics分離を参考） | Engine本体は変更不要 |

---

## 9. Phase 1で実装しない方がよいもの（過剰設計の指摘）

- **KOC消費・PINカード移動・SUBMISSION ESCAPEロジックの先行実装** — Phase1はフィールドの初期化のみ。
  ロジックはPhase5/6で実装する。
- **`CombatV1RulesConfig`へのPINカード総数(4枚)／REST回復量／FINISHER解禁HEATの先行追加** — 使われない
  ルール定数を今から抱えると「値だけあってロジックがない」状態が長期化する。該当Phaseで追加する。
- **`winner`/`isOver`の先行追加** — §2.6の通り、決着条件が一切ないため見送る。
- **`familyId`を専用enumとして先に確定させること** — 技系統の確定が完了していない。`String?`のまま。
- **`models/`/`engine/`/`rules/`のサブディレクトリ化** — 現時点のファイル数では時期尚早。

---

## 10. Phase 1 実装予定ファイル一覧

**新規作成（9ファイル、いずれも`lib/src/combat_v1/`直下）**:
`combat_v1_enums.dart`, `combat_v1_energy.dart`, `combat_v1_technique.dart`, `combat_v1_counter.dart`,
`combat_v1_deck.dart`, `combat_v1_wrestler.dart`, `combat_v1_rules_config.dart`,
`combat_v1_match_state.dart`, `combat_v1_engine.dart`

**新規テストファイル（3ファイル、`test/combat_v1/`直下）**:
`combat_v1_engine_test.dart`, `combat_v1_energy_test.dart`, `combat_v1_deck_test.dart`

**既存ファイルの変更**: なし（①`game.dart`／②`level_match/`・`wrestler_editor/`／③`technique_deck/`・
`playtest_analytics/`はいずれも無変更）。`pubspec.yaml`も新規依存追加不要。

**注**: 上記はいずれもPhase 0（今回）では作成しない。Phase 1着手の指示を受けてから作成する。

---

## 11. Phase 3での更新（技術設計の差分）

Phase 3（TECHNIQUE Core完成 + COUNTER受け入れ準備）で、本書のPhase 1設計から以下を更新した。
ゲームルール自体（`combat_rules_v1.md`）の変更ではなく、実装内部の技術設計の差分である。

### 11.1 `CombatV1Engine`のAPIを`Map<String, CombatV1Technique>`から`CombatV1CardCatalog`へ移行

`playTechnique`/`checkTechniqueLegality`/`hasAnyPlayableTechnique`の`techniques:`引数
（`Map<String, CombatV1Technique>`）を、Phase 2で導入済みの`CombatV1CardCatalog`
（`combat_v1_deck_validation.dart`）を受け取る`catalog:`引数へ統一した。

理由: entry.categoryとカード定義categoryの整合性確認・COUNTERカードの誤用検出には、
TECHNIQUEだけでなくCOUNTER側のカタログも横断参照する必要があるため
（`CombatV1CardCatalog.categoryOf`が両方を見る）。Deck validationに続き、Engine実行時の
legality判定でも「カード参照の正式な横断入口」をCatalogに一本化した。

### 11.2 `CombatV1ActionCheck`に`reasonCode`を追加

`CombatV1TechniqueLegalityReasonCode`（`legal`/`wrongPhase`/`cardNotInHand`/
`missingCatalogEntry`/`notTechnique`/`categoryMismatch`/`counterCannotAttack`/
`finisherNotImplemented`/`opponentStateMismatch`/`invalidTechniqueData`/
`insufficientEnergy`）を追加し、`CombatV1ActionCheck`の第3引数（デフォルト`legal`）とした。
`legal`/`reason`（人間可読文字列）は既存のまま維持し、後方互換を保っている。UI/CPU/Simulatorが
`reason`文字列を解析しなくてよいようにするための構造化情報。

### 11.3 `playTechnique`の内部分離（Phase 4 COUNTER挿入点）

`playTechnique`を内部で以下の2段階に分離した。

1. `_prepareTechniqueUse`: `checkTechniqueLegality`を呼び、legalityを検証したうえで
   ENERGY支払いを確定する（`_PreparedTechniqueUse`を返す）。不正なら
   `CombatV1IllegalActionException`を送出し、この時点では`state`を一切変更しない。
2. `_resolveSuccessfulTechnique`: `_PreparedTechniqueUse`を受け取り、SSOTで確定した順序
   （ENERGY消費→DMG適用→HP 0 clamp→shared HEAT加算→相手状態変化→使用カードdiscard→
   1 draw）で効果を適用する。失敗しない（例外を送出しない）。

Phase 3では`playTechnique`がこの2つを間を置かず連続して呼ぶだけだが、Phase 4で
COUNTERを実装する際は、`_prepareTechniqueUse`の結果（`_PreparedTechniqueUse`）を
`counterResponsePending`の間保持しておき、COUNTER不成立なら`_resolveSuccessfulTechnique`
へ、COUNTER成立なら無効化パスへ渡す、という拡張を想定している。Phase 3では
`CombatV1PendingTechnique`・`counterResponsePending`フェーズ・`declareTechnique`公開APIは
作らない（`_PreparedTechniqueUse`は非公開のprivateクラス）。

### 11.4 静的データvalidationの追加

immutableモデルのコンストラクタには重いruntime validationを追加せず（`Map`の中身を検証する
`assert`はconst constructorと相性が悪いため、既存のコメント方針を踏襲）、代わりに以下の
読み取り専用APIを追加した。

- `CombatV1EnergyPool.isValid`／`CombatV1EnergyCost.isValid`（`combat_v1_energy.dart`）:
  負数の禁止、および`CombatV1EnergyCost`は追加でwildを要求Costとして持たないことを検証する。
- `CombatV1Technique.isStaticDataValid`（`combat_v1_technique.dart`）: `energyCost.isValid`を
  参照する。`checkTechniqueLegality`が`invalidTechniqueData`reasonCodeの判定に使う。
- `validatePlayerStateInvariants`（新規`combat_v1_state_invariants.dart`）: `spentEnergy`が
  `energyPool`を超えていないかを検証する読み取り専用ヘルパー。Engine本体のCommand APIには
  自動配線せず、CPU/Simulator/テストがオプトインで呼び出す想定。

### 11.5 FINISHER/COUNTERの拒否

`checkTechniqueLegality`は、FINISHERを`finisherNotImplemented`、COUNTERカードを
`counterCannotAttack`として明示的に拒否する（Phase 9・Phase 4まで本処理を実装しない）。
`entry.category`とカード定義の`category`が一致しない場合も`categoryMismatch`として拒否する
（Deck validationと同じ不変条件を、Engine実行時にも防御的に再確認する）。

### 11.6 新規ファイル

`combat_v1_state_invariants.dart`（`lib/src/combat_v1/`）を追加した。
