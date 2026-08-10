# ONE NIGHT MATCH Combat Ver.1 戦闘ルール仕様書（SSOT）

- ステータス: **Phase 0 確定版**（Combat Ver.1 Engine設計フェーズの正式仕様。ゲームロジックの実装はまだ行われていない）
- 位置づけ: **Combat Ver.1（④ Combat Ver.1 Engine）のSingle Source of Truth（SSOT）**。
  Combat Ver.1の仕様と実装（`lib/src/combat_v1/`、Phase 1以降に新規作成予定）に矛盾がある場合、
  原則として本書を優先する。本書自体を変更する場合は変更理由を明記して更新する（29章「変更履歴」参照）。
- 対象読者: Combat Ver.1のEngine実装・CPU実装・シミュレーション実装・バランス調整に関わる全セッション。
- 出典: ユーザー提供資料「ONE_NIGHT_MATCH_戦闘ルール_Ver.1_検証版」（.docx、4レスラー総当たり検証用・
  2026-08-09時点）を一次資料とし、Combat Ver.1 Engine設計セッション（Phase 0）で確定した追加事項を統合したもの。
- 関連ドキュメント:
  - [`docs/design/combat_v1_phase1_design.md`](design/combat_v1_phase1_design.md) — Phase 1技術設計
    （ディレクトリ構成・データモデル・State Machine・Engine API・テスト計画）
  - [`docs/design/combat_v1_open_questions.md`](design/combat_v1_open_questions.md) — 未決定事項一覧
- 既存3エンジンとの関係: 本書はいずれの既存エンジンの仕様も変更しない。
  - ① Prototype（`lib/src/game.dart`）
  - ② Level Match（`lib/src/level_match/`、`lib/src/wrestler_editor/`）
  - ③ Technique Match（`lib/src/technique_deck/`、`lib/src/playtest_analytics/`）

  Combat Ver.1は上記3エンジンに**直接実装しない**。独立した第4のエンジン
  （④ Combat Ver.1 Engine、想定配置 `lib/src/combat_v1/`）として新規構築する（1章参照）。

> **本書の読み方**: 本書はCombat Ver.1のルールブックである。未確定・検証中の数値・技名は
> 「検証用」「未確定」「検証候補」「後続Phaseで決定」のいずれかを明記する。**推測による補完は行わない**。
> 一次資料（docx）に記載がない項目は、本セッションで新たに確定した場合のみ追記し、それ以外は
> 「未確定」として28章にまとめる。

---

## 0. この文書の位置づけ

本書は、ONE NIGHT MATCHの新しい戦闘仕様「Ver.1」を固定し、火神アカリ／白銀レイナ／豪田ミサキ／黒蝶ジャックの
4人で総当たり検証を行うための基準仕様である。未確定・仮称の技名や数値は「検証用」として扱い、検証後に調整する
（一次資料 docx 1章より）。

Combat Ver.1 Engine設計セッション（Phase 0）により、以下が追加で確定した。

- Ver.1は既存3エンジンに実装せず、独立した新エンジン（④）として構築する（1章）。
- HP・KOC・PINカードはいずれも試合開始時から存在する基本リソースとして扱う（2章）。
- FINISHERの決着方式（NORMAL／DIRECT PIN／SUBMISSION）は独立したenumで表現し、
  技が持つ「SUBMISSION技かどうか」という属性とは別概念として扱う（13章）。
- 開発は Phase 0〜16 の順で進め、Ver.1の基本ルールが一通り動作した時点で
  旧3エンジンを削除する「Legacy Engine Removal Gate」を設ける（26・27章）。

---

## 1. Engine方針（④ Combat Ver.1 Engine）

- Combat Ver.1は、①Prototype／②Level Match／③Technique Matchのいずれにも直接実装しない。
- 新しく「④ Combat Ver.1 Engine」を独立して構築する。想定配置は `lib/src/combat_v1/`。
- ④は①②③のコードを**直接importして成立させる構造にはしない**（独立性を優先する）。
- 既存資産（設計パターン・アルゴリズム・テスト方法・Simulator設計等）を**参考にすることはできる**が、
  コードそのものへの依存は作らない。
- Combat EngineはUI非依存（Pure Dart寄り）の構造とする。Flutter Widgetをエンジンへ渡す設計は禁止する。
  UI／CPU／Simulator／Testが同じCommand APIを呼び出せる構造を目指す。
- 詳細な技術設計（ディレクトリ構成・データモデル・API）は
  [`docs/design/combat_v1_phase1_design.md`](design/combat_v1_phase1_design.md) を参照。

---

## 2. 基本リソース

Combat Ver.1 Engineが扱う主要リソース: **HP／KOC／ENERGY／HEAT／PIN CARD／HAND／DECK／DISCARD／STAND・DOWN**。

| 項目 | 仕様 |
|---|---|
| HP | **初期値150（全レスラー共通、レスラーごとの差は設けない）**。TECHNIQUEのDMGで減少。0未満にはならない（14章）。 |
| KOC | 初期値**10**。PINのカウント（1／2／2.9）／SUBMISSIONからの脱出に使用（8・9・10章）。 |
| ENERGY | レスラーごとに属性別に定義される固定プール。自ターン開始時に全回復。TECHNIQUEとCOUNTERで消費（5章）。 |
| HEAT | 両者共有。TECHNIQUE等で10単位を基本に上昇。**200以上でFINISHER解禁**。消費しない（12章）。 |
| 状態 | STAND／DOWN。技の使用条件、PIN条件などに影響（11章）。 |
| PINカード | 共有4枚。試合開始時は各プレイヤー2枚ずつ保持。移動ルールは9章参照。 |
| HAND／DECK／DISCARD | 30枚デッキ、初期手札5枚、山札切れは捨て札シャッフルで再構築（FATIGUEなし、16章）。 |

---

## 3. デッキ

各レスラー30枚固定。

| 区分 | 枚数 | 備考 |
|---|---|---|
| NORMAL | 18枚 | 8種類。基本技は3枚、その他は原則2枚（検証用の暫定基準）。 |
| SIGNATURE | 4枚 | 2種類×2枚。 |
| FINISHER | 2枚 | 2種類×1枚。 |
| COUNTER | 6枚 | 3種類×2枚。 |
| **合計** | **30枚** | |

- **ENERGYカードは使用しない**。ENERGYはレスラー固有の固定プールであり、デッキに含めない（5章）。
- 初期手札は5枚。
- NORMALの同名カード上限は3枚を基本とする。
- 正式な4レスラーのデッキ内容は後続Phase（Phase 10想定）で完成させる。21章の「30枚デッキ配分（現時点）」は
  検証段階の暫定基準であり、確定値ではない。

---

## 4. ターン進行

自ターンの流れ:

1. 自ターン開始時にENERGYを全回復する。
2. 山札から1枚引く。
3. 手札から任意の1枚を捨てる（手札循環）。
4. DOWN状態なら、起き上がり／RESTなどの処理を行う（11章、Phase 7で実装）。
5. 使用条件を満たすTECHNIQUEを使用する。
6. TECHNIQUEまたはCOUNTERを1枚使用したら、原則として山札から1枚補充する。
7. 攻撃継続、PIN、SUBMISSION、またはターン終了を選択する。
8. 山札がなくなった場合は捨て札をシャッフルして新しい山札とする。FATIGUEペナルティは設けない（16章）。

**Combo Speedは採用しない**。同一ターン内のTECHNIQUE使用回数は、基本的にENERGYによって制限する。
ENERGYが残っており、かつその他の使用条件（相手の状態等）を満たしていれば、
TECHNIQUE → TECHNIQUE → TECHNIQUE と攻撃を継続できる。Combo Speedのような第二の攻撃回数リソースは導入しない。
ROUGHによる「次ターンTECHNIQUE最大1枚」（15章）は、この通常の複数TECHNIQUE使用を制限する効果として機能する。

---

## 5. ENERGY

ENERGYは属性別に定義される。属性は以下の6種:

**打（strike）／関（joint）／投（throwing）／飛（aerial）／ラフ（rough）／＊（wild）**

- レスラーごとにENERGY配分が異なる（例は18章参照）。
- 自ターン開始時に全回復する。
- TECHNIQUEとCOUNTERの両方で使用する（COUNTERの詳細は7章、Phase 4で実装）。
- **EnergyPool（持っているENERGY）とEnergyCost（技が要求するENERGY）は別モデルとして扱う。**

  例:
  ```
  EnergyPool（アカリ）:  打5 / 関1 / 投2 / 飛2 / ラフ0 / ＊1
  Technique Cost（例）:  打2
  ```

### 5.1 ＊（ワイルドENERGY）

＊はワイルドENERGYである。基本的には、打／関／投／飛／ラフの任意の属性ENERGY COST不足分を補える。

**解決手順（確定）**:
1. 各属性の具体的なENERGY（打・関・投・飛・ラフ）をまず使用する。
2. 各属性で不足している分を合算する。
3. 合算した不足分の合計を、保有する＊ENERGYで補えるか判定する（属性ごとに個別のワイルド消費順序は設けず、
   ＊は属性を跨いで融通できる共有資源として扱う）。

例:
```
残ENERGY:        打1 / 投0 / ＊2
TECHNIQUE COST:   打2 / 投1

不足: 打1 + 投1 = 合計2
＊2があるため使用可能。
```

### 5.2 COUNTERでの＊(ワイルド)ENERGYの扱い（Phase 4で確定）

TECHNIQUE支払い（5.1章）とは別に、COUNTER支払い（動的ENERGY COST、7章）専用のポリシーを
`CombatV1RulesConfig.counterAllowsWildSubstitution`として持つ。**既定値は`false`**——COUNTERの
synthetic cost支払いでは、既定で＊による補完を許可しない。

例（必要「投3」の場合）:

| 実際の支払い | Config=false | Config=true |
|---|---|---|
| 投3 | 成功 | 成功 |
| 投2 + ＊1 | 失敗 | 成功 |
| 投1 + ＊2 | 失敗 | 成功 |
| 投0 + ＊3 | 失敗 | 成功 |

支払いアルゴリズム自体（属性ごとの不足分合算→＊で補完、5.1章の解決手順）は新規実装せず、
`resolveEnergyPayment(..., allowWildSubstitution: rules.counterAllowsWildSubstitution)`として
既存ロジックをそのまま再利用する。

---

## 6. TECHNIQUE

TECHNIQUEには属性、技系統、ENERGY COST、DMG、HEAT、使用可能状態などを定義する。

- 技ごとに、STAND→STAND／STAND→DOWN／DOWN→DOWN のような状態変化を表現できる。
- 技系統（TechniqueFamily）はCOUNTERの成立判定に使う概念。正式taxonomyはPhase 4で確定した（23章）。
- ENERGY COSTの合計（`CombatV1EnergyCost.total`）は必ず0より大きい（zero-cost技は禁止、Phase 4確定）。
- DIRECT PIN（PIN不要で成功後に自動的にPINへ移行する性質）は、**FINISHER限定ではなく技全般に付与できる**
  汎用フラグとして扱う（8章、13章とあわせて参照）。
- 技自体が「SUBMISSIONホールド技である」という性質（例: 鳳凰固め、白銀ロック）と、
  「FINISHERとしてSUBMISSION決着方式を持つこと」は**別概念**として扱う（13章で詳述）。

---

## 7. COUNTER（Phase 4で正式実装）

COUNTERカード自体には固定ENERGY COSTを設定しない。

- 返し必要コストは、**返される側のTECHNIQUEのENERGY COST「総量」
  （`CombatV1EnergyCost.total`）と同値**とする。攻撃Costの属性構成
  （例: 投2＋打1）をCOUNTER側へコピーするのではなく、COUNTERに定義された
  **単一の属性**でその総量を支払う（例: 攻撃Cost合計3・COUNTER属性=投なら
  「投3」を要求する）。
- このため高COST技は高火力であるだけでなく、COUNTER側にも多くのENERGYを要求し、自然に返されにくくなる。
- 技系統・技系統グループを確認して成立判定する（4章参照）。attribute（ENERGY属性）の一致だけでは
  COUNTER成立にはしない。
- COUNTER時の＊(wild)ENERGYの扱いは`CombatV1RulesConfig.counterAllowsWildSubstitution`
  （既定値`false`）で確定した（9章参照）。

### 7.1 PendingAttack・counterResponsePending（State Machine）

TECHNIQUE宣言（`declareTechnique`）は即座に成功解決しない。宣言時点ではlegality検証・ENERGY支払い確定・
使用カードのhandからの除去・`techniquesUsedThisTurn`の加算のみを行い、DMG・HEAT・相手posture変化・discard・
drawはすべて据え置く。宣言された攻撃内容は`CombatV1PendingAttack`（immutableなDomain
model）として保持し、`CombatV1MatchPhase.counterResponsePending`へ遷移する。

```
action ──(declareTechnique)──▶ counterResponsePending ──┬─(playCounter)──▶ action
                                                          └─(declineCounter)──▶ action
```

- `counterResponsePending`の間、`activePlayerIndex`は宣言した攻撃側のまま変化しない。COUNTER成立でも
  攻守交代しない。
- `playCounter`（COUNTER成立）: 攻撃の効果を完全に無効化する（DMGなし・HEATなし・posture変更なし）。
  攻撃カードは攻撃側のdiscardへ、使用したCOUNTERカードは防御側のdiscardへ移動し、**攻撃側・防御側の
  双方が1枚ずつdraw**する（手札循環を維持し、COUNTERを手札破壊効果にしないため）。
- `declineCounter`（COUNTERしない）: 攻撃を通常通り成立させる（DMG→HP 0
  clamp→shared HEAT→相手posture変化→攻撃カードを攻撃側discardへ→攻撃側1
  draw）。ゲーム結果としてはPhase 3の即時成功解決と同じになる。
- COUNTERはTECHNIQUEではないため、`techniquesUsedThisTurn`には含めない（15章）。
- 防御側が支払ったCOUNTER ENERGYは、防御側の次の自ターン開始時（通常のENERGY全回復）まで自動回復しない。

### 7.2 CombatV1EnergyCost.total

`CombatV1EnergyCost`に、具体ENERGY属性のCost合計を返す`total`（`int`）を追加した。COUNTER必要量の算出
（7章）に使う。Technique Costは`total > 0`をPhase 4正式ルールとする——zero-cost
TECHNIQUEは禁止する。Cost側にwild要求を設定することも禁止（5.1章の既存不変条件のまま）、負数のCostも禁止。

---

## 8. PIN（Phase 5で正式実装）

通常PINは、相手がDOWNで、その攻撃ターン中にTECHNIQUEを成功させている場合に行える
（`action`フェーズから攻撃側が任意に宣言する。Engine APIは`declarePin`、8.3章参照）。
DIRECT PINを持つ技は成功後に自動的にPINへ移行する（TECHNIQUE成功解決と同一Command内で
遷移し、後から古い成功記録を参照して再発火させることはない、8.3章参照）。
**DIRECT PINでもPINカードを使用する**。

### 8.1 PINカード

- PINカードは共有4枚。試合開始時は各プレイヤー2枚ずつ保持する。中央poolは持たず、
  各PlayerStateの保有枚数（`pinCardsHeld`）で管理する
  （`playerA.pinCardsHeld + playerB.pinCardsHeld == 4`を常に維持するmatch-level invariant）。
- **移動の主体と向き（Phase 5で確定）**: PINは攻撃側が自分の保有PINカードを1枚使用して開始する。
  1カウントまたは2カウントでkick outされた場合、攻撃側が使用したそのPINカード1枚を
  **攻撃側→防御側へ**移動する。
- 2.9カウントでkick outされた場合はPINカードを移動しない。攻撃側は使用したPINカードを
  そのまま保持し、攻撃側は`action`フェーズへ戻って攻撃を継続する（8.2・8.3章参照）。
- **最低1枚保証（正式採用）**: 現在PINカードが1枚しかないプレイヤー（この場合は攻撃側）は、
  そのカードを相手へ移動しない。つまり各プレイヤーは常に最低1枚のPINカードを保持する
  （移動が抑止されても、KOC消費・カウント結果自体は通常どおり発生する）。

例（攻撃側A・防御側B、A=1枚しか保有していない場合）:

```
A.pinCardsHeld = 1, B.pinCardsHeld = 3
1カウントでkick out → 最低1枚保証によりカードは移動しない（A=1のまま、B=3のまま）
```

### 8.2 カウント

PINのカウントは、防御側が段階ごとに応答する多段階のやり取りではなく、
**PIN開始時点の防御側KOCから最終カウントを一括で決定する**（`pinResponsePending`のような
段階的な入力待ちフェーズは設けない、8.3章参照）。

| 防御側KOC | 消費KOC | カウント | 効果 |
|---|---|---|---|
| KOC >= 3 | KOC3 | 1カウント | 返した側（防御側）は山札から追加で1枚引く |
| KOC == 2 | KOC2 | 2カウント | — |
| KOC == 1 | KOC1 | 2.9カウント | 攻撃側は攻撃を継続できる（`action`フェーズへ戻る） |
| KOC == 0 | 支払い不能 | 3カウント | PIN決着（攻撃側の勝利で試合終了） |

- **KICK OUTは自動（Phase 5で確定）**: 防御側が必要なKOCを保有していれば必ずkick outする。
  「保有していてもあえて支払わない」という選択肢は存在しない。
- KOC支払いは防御側のみが行う（攻撃側はKOCを支払わない）。

### 8.3 PIN後の展開（Phase 5で確定）

- **1カウントまたは2カウントでkick out**: 攻撃側のターンを終了し、防御側へ主導権を移す
  （`endTurn`と同じ内部処理——ENERGY全回復・1ドロー——で防御側の新しいターン
  （`discard`フェーズ）へ進む）。防御側の状態（DOWN等）はこの遷移では変化しない。
- **2.9カウントでkick out**: 攻撃側は`action`フェーズへ戻り、残りENERGY等の許す範囲で
  TECHNIQUEの使用・追加のPIN宣言などを継続できる（`activePlayerIndex`は変化しない）。
- **3カウント（KOC不足）**: PIN決着として試合が終了する（攻撃側の勝利。`winner`/`isOver`の
  Domain表現はPhase 5で正式追加した、[`combat_v1_phase1_design.md`](design/combat_v1_phase1_design.md)
  「Phase 5での更新」節参照）。

Phase 1ではPIN・カウント処理・PINカード移動のロジックは実装しなかった。PlayerStateにPINカード
保有数（試合開始時2枚ずつ）を正しく初期化するところまでが対象だった（Phase 1範囲は
[`combat_v1_phase1_design.md`](design/combat_v1_phase1_design.md) 参照）。上記8.1〜8.3章の内容は
Phase 5で正式実装した（技術設計の詳細は同書「Phase 5での更新」節を参照）。

---

## 9. KOC

KOCは初期値10。PINのカウント（8章）およびSUBMISSIONからの脱出（10章）に使用する共通リソース。
`koc >= 0`をDomain invariantとして保証し、支払い可能性を先に判定してから消費する
（負のKOCをCommandで生成しない、8.2章）。

Phase 1ではKOCの消費・判定ロジックは実装しなかった。PlayerStateにKOC=10が試合開始時に正しく
初期化されるところまでが対象だった。PINでのKOC消費はPhase 5で正式実装した（8章参照）。

---

## 10. SUBMISSION

SUBMISSIONはPINカードを使用しない。**通常SUBMISSIONとSUBMISSION FINISHERは別ルールとして扱う**
（13章「FINISHER」とあわせて参照。「技がSUBMISSION属性を持つこと」と「FINISHERとしてSUBMISSION決着方式を
持つこと」を混同しないこと）。

### 10.1 通常SUBMISSION

- 例: 鳳凰固め、白銀ロック
- 相手HP50以下で宣言可能。
- ESCAPE: KOC1を消費。**HP0でもKOCがあればESCAPE可能**。
- KOCを支払えなければGIVE UP。

Phase 6で以下を正式実装した（技術設計の詳細は
[`combat_v1_phase1_design.md`](design/combat_v1_phase1_design.md)「Phase 6での更新」節参照）。

- **突入方法（Phase 6で確定）**: 自動トリガーのみ。`submissionHold=true`のTECHNIQUEがCOUNTERされずに
  成立し、解決後の相手HPが閾値（既定50、`CombatV1RulesConfig.submissionHpThreshold`）以下になった場合に
  限り、DIRECT PIN（8章）と同じ仕組みでTECHNIQUE成功解決と同一Command（`declineCounter`）内で
  自動的にSUBMISSIONへ移行する。`declarePin`のような攻撃側が任意に宣言する独立APIは追加しない
  （相手HPが閾値以下というだけでは宣言できず、必ずsubmissionHold技の成功が引き金になる）。
- **ESCAPE/GIVE UP判定（Phase 6で確定）**: 完全自動。防御側が必要なKOC
  （既定1、`CombatV1RulesConfig.submissionEscapeKocCost`）を保有していれば必ずESCAPEする
  （PINのKICK OUT自動判定、8.2章と同じ思想。「保有していてもあえて支払わない」という選択肢は存在しない）。
  KOCを支払えなければGIVE UPで試合が終了する（`winnerPlayerIndex`を攻撃側に設定）。防御側に実質的な
  選択肢が無いため、PINの`pinResponsePending`と同様、SUBMISSION専用の入力待ちフェーズ
  （`CombatV1MatchPhase`の新規値）や`CombatV1PendingSubmission`のようなpublic Domain
  modelは追加していない。
- **ESCAPE成功後の展開（Phase 6で確定）**: 攻撃側のターンを終了し、防御側（ESCAPEした側）へ主導権を移す
  （`endTurn`と同じ内部処理、PIN 1／2カウントと同じ扱い、8.3章）。
- **directPin/submissionHoldの排他（Phase 6で確定）**: 同一TECHNIQUEに`directPin=true`と
  `submissionHold=true`を同時に設定することは、Catalog validation（23.6章）で禁止する
  （`techniqueDirectPinSubmissionHoldConflict`）。`category==finisher`の技は`directPin`/
  `submissionHold`をそもそも参照しないため対象外（13章、2.4章）。
- **stale snapshot対策**: DIRECT PINと同じ思想で、`state.lastSuccessfulTechnique`
  （match-level・ターンを跨いで残る）は一切参照せず、TECHNIQUE成功解決の中で今まさに解決した
  pending攻撃を直接使って判定する。これにより、古い成功記録によるSUBMISSIONの再発火は構造的に発生しない。
- **PINカードは操作しない**: 本章冒頭のとおりSUBMISSIONはPINカードを使用しない。ESCAPE/GIVE UPの
  いずれも`pinCardsHeld`を変化させない。

### 10.2 SUBMISSION FINISHER

- 例: 白銀スペシャル
- HP1〜50: KOC1でESCAPE可能。
- **HP0: 即GIVE UP**（HP0による特殊決着の唯一の例外パターン。14章参照）。

Phase 6ではSUBMISSION FINISHERのロジックは実装しない（Phase 9でFINISHER全体とあわせて実装する、13章）。
SUBMISSION FINISHERの自動解決ロジック自体はPhase 9で正式実装した（13.3章参照）。

---

## 11. REST / DOWN

DOWN状態の自ターンでは、起き上がりまたはRESTを選択できる。

- REST: HP+10回復（**最大150を超えない**）。RESTしたターンはTECHNIQUEを使用できないが、COUNTERは使用可能。
- ダブルダウンはVer.1では採用しない。

Phase 1ではSTAND／DOWNの基本状態モデル（状態の保持と、技によるSTAND→DOWN等の遷移）のみを扱う。
起き上がり／REST選択のロジック自体はPhase 7で実装した。

Phase 7で以下を正式実装した（一次資料・本章の記載には「起き上がりまたはRESTを選択できる」という
選択の存在自体は明記されていたが、Command構造・posture遷移・ターン終了処理などの実装上の詳細は
明記されていなかったため、Phase 7実装セッション内でユーザーへ確認したうえで正式仕様として採用した。
技術設計の詳細は[`combat_v1_phase1_design.md`](design/combat_v1_phase1_design.md)「Phase
7での更新」節参照）。

- **起き上がり（Phase 7で確定）**: RESTしない場合の復帰は、明示的なCommand
  `standUp`として実装する。posture: down→standへ遷移するのみで、HP・KOC・PINカード・ENERGY・
  HEAT・hand/draw/discardのいずれも変化しない。`phase`／`activePlayerIndex`／`turnNumber`も
  変化せず、そのターンの行動を消費しない（起き上がった後、同一ターン内で通常のTECHNIQUE使用等へ
  進められる）。
- **REST（Phase 7で確定）**: `rest`として実装する。posture: down→standへ遷移し、HPを
  `CombatV1RulesConfig.restHpRecovery`（既定10）回復する（`maxHp`を超えない）。RESTはそのターンの
  行動を確定し、`endTurn`と同じ内部処理（手番交代・turnNumber加算・新しい手番プレイヤーのターン
  開始処理）まで一括で進める。KOC・PINカード・HEATはRESTでは変化しない。
- **選択可能条件（Phase 7で確定）**: 起き上がり／RESTはいずれも`phase == action`かつ自分（active
  player）がDOWN状態の場合のみ選択できる。STAND状態では選択できない（DOWN限定）。
- **DOWN時の合法行動（Phase 7で確定）**: 自分（active player）がDOWN状態のままでは、TECHNIQUE
  宣言（`declareTechnique`）・通常PIN宣言（`declarePin`）・`endTurn`のいずれも実行できない
  （legality reasonCode: `selfDown`）。先に`rest`または`standUp`でDOWNから復帰する必要がある。
  COUNTER（`playCounter`/`declineCounter`）は自分がDOWN状態でも一切制限されない（本章「RESTした
  ターンはCOUNTERは使用可能」に対応する。防御側のCOUNTER legality判定はpostureを参照しないため、
  追加の制限を設けていない）。
- **「RESTしたターンはTECHNIQUEを使用できない」の実現方法（Phase 7で確定）**: RESTがそのターンの
  行動を確定し即座にターンを終了させること自体によって自然に満たされる。TECHNIQUE使用を個別に
  禁止するフラグは追加しない。
- **draw/discard・`lastSuccessfulTechnique`への影響（Phase 7で確定）**: 起き上がり／RESTはいずれも
  hand/draw/discardを直接操作しない（RESTのターン終了処理に伴う新しい手番プレイヤーの1ドローは、
  既存の`_startTurn`と同じ処理を再利用しただけであり、REST/起き上がり専用の追加draw/discardは無い）。
  `lastSuccessfulTechnique`も起き上がり／RESTでは一切変更しない（21章の方針、根拠のないclear処理は
  追加しない）。

---

## 12. HEAT

- HEATは両プレイヤー共有。試合開始時 `sharedHeat = 0`。
- TECHNIQUE等で10単位を基本に上昇する。
- **200以上でFINISHER解禁**。
- HEATは消費リソースではない（FINISHER使用時にも消費しない）。

Phase 1ではFINISHER解禁・決着処理は実装しないが、`sharedHeat`の増加自体は最小戦闘ループの一部として扱う。

---

## 13. FINISHER

共有HEAT 200以上で使用可能。FINISHERだから自動的にPINになる、という処理にはしない。

FINISHERの決着方式は、**独立したenumとして明示的に保持する**（技のフラグからの導出ではない）:

```dart
enum CombatV1FinisherType {
  normal,     // 強力な通常TECHNIQUE。成功しても自動PINしない。攻撃側がその後PINを選択できる
  directPin,  // 技成功後に自動的にPIN処理へ移行する
  submission, // 技成功後にFINISHER専用SUBMISSION処理（10.2章）へ移行する
}
```

| 種別 | 意味 |
|---|---|
| A. NORMAL FINISHER | 通常の強力なTECHNIQUEとして扱う。成功→DMG→HEAT→状態変化→その後、必要なら攻撃側が通常PINを選択する。 |
| B. DIRECT PIN FINISHER | 成功後、自動的にPINへ移行する（8章のPINカードルールに従う）。 |
| C. SUBMISSION FINISHER | 専用SUBMISSION処理（10.2章）へ移行する。 |

**重要な区別**: 技モデル上の「この技はSUBMISSIONホールドである」という汎用フラグ（6章）と、
「この技はFINISHERとしてSUBMISSION決着方式（`CombatV1FinisherType.submission`）を持つ」ことは別概念である。
通常技・固有技にもSUBMISSION技は存在しうる（例: 通常SUBMISSION技である鳳凰固め・白銀ロックはFINISHERではない）。
汎用フラグの値だけを見てSUBMISSION FINISHERと自動判定する設計にはしない。

Phase 1ではFINISHER決着ロジックは実装しない。`CombatV1FinisherType` enumおよび技モデル上の表現のみ
先行して定義する。FINISHER解禁・決着処理そのものはPhase 9で正式実装した（13.1〜13.4章参照）。

### 13.1 FINISHER解禁条件（Phase 9で確定）

- 共有HEAT（[`CombatV1MatchState.sharedHeat`](../design/combat_v1_phase1_design.md)）が
  `CombatV1RulesConfig.finisherHeatThreshold`（既定200、12章）以上のとき、`category ==
  finisher`のTECHNIQUEを宣言できる。判定は既存の`checkTechniqueLegality`へ統合し、専用の
  独立APIは追加しない（`finisherHeatNotReached`reasonCode）。
- HEATは消費リソースではない（12章）ため、一度解禁されたFINISHERがHEAT減少により再び
  使用不可へ戻ることはない。
- 1ターン内でのFINISHER使用回数に、SSOTが定める特別な上限は無い。4章の方針
  （Combo Speed不採用、ENERGYのみが同一ターン内の技使用回数を制限する）がFINISHERにも
  そのまま適用される。

### 13.2 finisherTypeと技モデル上のフィールドとの関係（Phase 9で確定）

`category == finisher`の技では、`directPin`/`submissionHold`フィールドはそもそも参照しない
（`finisherType`のみが決着方式を決定する、2.4章で確定済みの優先順位ルールをPhase 9の実装へ
反映した）。決着方式ごとの自動移行判定は、既存のDIRECT PIN／通常SUBMISSION自動移行の仕組み
（8章・10.1章）を`finisherType`経由でそのまま再利用する:

- `finisherType == normal`: 自動移行なし。攻撃側は事後に既存の`declarePin`
  （8章、通常PINと同じlegality判定）を任意で呼べる。
- `finisherType == directPin`: 技成功と同一Command内でPINへ自動移行する（8章のPINカード
  ルール——カウント・KOC消費・PINカード移動・kick out後の展開まで——にそのまま従う）。
- `finisherType == submission`: 13.3章のFINISHER専用SUBMISSION処理へ自動移行する。

### 13.3 SUBMISSION FINISHERの自動解決（Phase 9で確定、10.2章とあわせて参照）

`finisherType == submission`の技が成立し、解決後の相手HPが
`CombatV1RulesConfig.submissionHpThreshold`（既定50）以下になった場合、通常SUBMISSION
（10.1章）と同じ仕組みでTECHNIQUE成功解決と同一Command内で自動的にFINISHER専用SUBMISSION
処理へ移行する（突入条件の閾値自体は通常SUBMISSIONと共通の値を再利用する）。

ESCAPE/GIVE UP判定は通常SUBMISSIONと同じ「防御側KOCから完全自動で決定する」方式だが、
唯一の相違点として10.2章の「HP0: 即GIVE UP」を実装する: 解決後の相手HPが0の場合、防御側の
KOC保有量に関わらず必ずGIVE UPとなる（ESCAPEの機会自体が発生しない）。相手HPが1以上
（かつ閾値以下）の場合は、通常SUBMISSIONと全く同じKOCベースのESCAPE/GIVE UP判定
（防御側KOC>=1なら必ずESCAPE、KOC==0ならGIVE UP）を適用する。

ESCAPE成功後の展開（攻撃側のターンを終了し、防御側の新しいターンへ進める）・PINカードを
一切操作しない点は、いずれも通常SUBMISSIONと同一である。

### 13.4 COUNTER・ROUGHとの関係（Phase 9で確定）

- **COUNTER**: FINISHERはCOUNTER可能（Phase 9セッションでユーザーが確認）。既存の
  `declareTechnique`→`counterResponsePending`→`playCounter`/`declineCounter`という
  State Machine（7章）はカテゴリを問わず一律に適用され、FINISHERを対象外にする特別な
  仕組みは導入しない。COUNTER成立時は他のTECHNIQUEと全く同じく完全に無効化される
  （DMG・HEAT・相手posture変化のいずれも発生せず、`lastSuccessfulTechnique`も更新しない）。
- **ROUGH**: FINISHER自体にROUGH属性（`attribute == rough`）が設定されている場合、
  ROUGHの判定（15章）はcategoryを問わずattributeのみを基準にするため、既存のロジック
  （宣言時点で`roughTechniqueUsedThisTurn`をセットする等）がそのまま適用される。FINISHER
  専用の追加ルールは無い。

---

## 14. HP0の扱い

- HP0 = 即KOではない。
- HPは0未満にはならない（0でクランプ）。
- HP0でも試合は継続する。
- HP0でも、ルール上可能であれば以下のような行動を行える:
  - COUNTERする
  - PINからKOCでKICK OUTする
  - 通常SUBMISSIONからKOC1でESCAPEする
  - RESTする
- HP0による特殊な決着は、**その効果が明示された技だけに限定する**。
  例: SUBMISSION FINISHER（10.2章）の「HP0なら即GIVE UP」。
- 通常TECHNIQUEでHP0になっても、それだけでは決着しない（即KO処理は実装しない）。

---

## 15. ROUGH（ラフ属性）

ROUGHは相手のコンボを切る妨害属性として扱う。反則カウント／反則負けはVer.1では導入しない。

- ROUGH属性TECHNIQUEを1枚でも使用したターンはPINできない。
- 最後に成功したTECHNIQUEがROUGHの状態で攻撃ターンを終了した場合、相手は次の自ターンに
  TECHNIQUEを**最大1枚**しか使用できない。
  - **重要**: 「相手が技を一切使用できない」ではない。最大1枚である。
  - COUNTER、REST、起き上がりなどはこの「TECHNIQUE 1枚」に含めない。

Phase 1ではROUGHの特殊処理（PIN不可・次ターン制限）は実装しない。Phase 8で正式実装した。

### 15.1 「使用」と「成功」の判定基準（Phase 8で確定）

本章冒頭の2つのルールは、本文の用語どおり異なる判定基準を持つ:

- 「1枚でも**使用**したターンはPINできない」（1点目）は**宣言時点の基準**（使用ベース）。
  `techniquesUsedThisTurn`（7.1章）と同じ「宣言時点で確定し、COUNTERされても取り消さない」基準に
  統一する。COUNTERされたROUGH技も、そのターンのPIN不可の対象になる。
- 「最後に**成功**したTECHNIQUEがROUGH」（2点目）は**`lastSuccessfulTechnique`（成功ベース）の
  基準**。COUNTERされたROUGH技は`lastSuccessfulTechnique`を更新しないため（7.1章）、次ターン制限の
  トリガーにはならない。

これら2つの判定基準・2つのstate（`CombatV1PlayerState.roughTechniqueUsedThisTurn`／
`roughTechniqueLimitActive`）を混同しないこと。

### 15.2 PIN不可ルールの対象範囲（Phase 8で確定）

「1枚でも使用したターンはPINできない」は**通常PIN（`declarePin`/`checkPinLegality`）のみ**が対象。
DIRECT PIN（8章）は技成功と同一Command内で自動遷移するため対象外——`checkPinLegality`を経由しない
経路であり、ROUGH属性かつ`directPin==true`の技であっても、DIRECT PINは通常どおり自動的に成立する
（両立を許容する。この組み合わせを禁止するCatalog validationは追加しない）。同様に、SUBMISSION
自動遷移（10.1章）もROUGH使用フラグを一切参照しない——SUBMISSIONは「PIN」ではないため、本章の
ルールの対象外である（23.4章の「attribute=rough・family=CHOKEの反則的な首絞め」のように、ROUGH技が
`submissionHold=true`を持つ組み合わせも問題なく成立する）。

### 15.3 次ターン制限の判定基準・消費・失効（Phase 8で確定）

- 「TECHNIQUE最大1枚」の“1枚”も**宣言時点の基準**（使用ベース）。COUNTERされた技も1枚に含む
  （15.1章と同じ基準に統一する）。
- 次ターン制限は、攻撃ターンが終了する経路（`endTurn`・REST・PIN 1/2カウントkickout・SUBMISSION
  ESCAPEのいずれも、8.3・10.1・11章で「endTurnと同じ内部処理」と明記されている）すべてで一様に
  判定する。
- 制限は、そのターンの終了とともに（TECHNIQUEを1枚使ったかどうかに関わらず）消滅する。次のさらに
  次のターンへ持ち越さない。

---

## 16. 山札切れ・手札循環

- 山札がなくなった場合は捨て札をシャッフルして新しい山札とする。
- FATIGUEダメージ、HEAT加算、強制TKOなどのペナルティは発生しない。

### 16.1 手札循環

自ターン開始時: ENERGY全回復 → 1枚ドロー → 1枚捨てる → ACTION（TECHNIQUE使用フェーズ）

- TECHNIQUE使用成功後: 1枚ドロー
- COUNTER使用成功後: 1枚ドロー（COUNTERはPhase 4で実装）

Phase 1では、ターン開始ドロー・1枚捨てる・TECHNIQUE使用後1枚ドロー・山札切れ時の再構築までを実装対象とする。

---

## 17. 4レスラーの方向性

検証段階の方向性。数値・技名は未確定を含む。

| レスラー | 主軸 | 特徴 | 主な決着 |
|---|---|---|---|
| 火神アカリ | 打撃＋飛び | コンボ／爆発力 | PIN＋SUBMISSION |
| 白銀レイナ | 関節＋投げ | 足攻め／技巧 | SUBMISSION＋PIN |
| 豪田ミサキ | 投げ＋打撃 | 高COST・高DMG・返されにくい | PIN |
| 黒蝶ジャック | ROUGH＋打撃 | コンボ制限／高HEAT | PIN |

---

## 18. ENERGY配分（検証値）

| レスラー | 打 | 関 | 投 | 飛 | ラフ | ＊ | 合計 |
|---|---|---|---|---|---|---|---|
| アカリ | 5 | 1 | 2 | 2 | 0 | 1 | 11 |
| レイナ | 2 | 4 | 3 | 0 | 0 | 1 | 10 |
| ミサキ | 3 | 0 | 4 | 0 | 1 | 1 | 9 |
| ジャック | 3 | 1 | 1 | 0 | 4 | 1 | 10 |

---

## 19. 豪田ミサキ TECHNIQUE（検証版）

高COST・高DMG型。新しいPOWERゲージなどは追加しない。高COST技ほど、DMGが高く、返し必要ENERGYも高いという
既存ルールだけで「返されにくいパワーファイター」を表現する。

例: COST1→DMG10、COST2→DMG20、COST3→DMG30、COST4→DMG40。

| 技 | 格 | COST | DMG | HEAT | 状態 | 特性 |
|---|---|---|---|---|---|---|
| 逆水平チョップ | NORMAL | 打1 | 10 | 10 | STAND→STAND | |
| ショルダータックル | NORMAL | 打1 | 10 | 20 | STAND→DOWN | |
| ボディスラム | NORMAL | 投1 | 10 | 10 | STAND→STAND | |
| ブレーンバスター | NORMAL | 投2 | 20 | 20 | STAND→DOWN | |
| バックドロップ | NORMAL | 投2 | 20 | 20 | STAND→DOWN | |
| パワースラム | NORMAL | 投3 | 30 | 30 | STAND→DOWN | |
| ラリアット | NORMAL | 打2 | 20 | 20 | STAND→DOWN | |
| ギロチンドロップ | NORMAL | 打1 | 10 | 20 | DOWN→DOWN | |
| 豪快バックドロップ | SIGNATURE | 投3 | 30 | 40 | STAND→DOWN | |
| 剛腕ラリアット | SIGNATURE | 打2 | 20 | 30 | STAND→DOWN | |
| 豪田ボム | FINISHER | 投3 | 30 | 40 | STAND→DOWN | DIRECT PIN |
| 豪田ドライバー | FINISHER | 投4 | 40 | 50 | STAND→DOWN | 最大火力（検証対象） |

「豪田ドライバー：投4／DMG40」が重要な検証対象。

---

## 20. 黒蝶ジャック ROUGH関連（検証版）

ROUGH＋打撃型。ROUGH TECHNIQUEは30枚中5枚程度を検証基準とする。

| 技 | 格 | 属性 | COST | DMG | HEAT | 採用枚数 |
|---|---|---|---|---|---|---|
| チョーク攻撃 | NORMAL | ROUGH | ラフ1 | 10 | 20 | ×1 |
| 顔面かきむしり | NORMAL | ROUGH | ラフ1 | 10 | 20 | ×1 |
| 黒蝶クラッシュ | SIGNATURE | ROUGH | ラフ2 | 20 | 40 | ×2 |
| 黒蝶ドライバー | FINISHER | ROUGH | ラフ3 | 30 | 50 | ×1 |
| ブラック・ジャック | FINISHER | STRIKE | 打3 | 30 | 50 | ×1 |

- ジャックのROUGH TECHNIQUEは30枚中5枚を初期基準とする。
- **踏みつけはROUGHではなく通常技として扱う。**
- 黒蝶ドライバー: 妨害型FINISHER。ブラック・ジャック: 決着型FINISHER、という役割分担。

---

## 21. 30枚デッキ配分（現時点、検証段階の暫定基準）

- アカリ: 基本NORMAL＝エルボースマッシュ×3、ミドルキック×3。その他NORMALは原則×2。
  SIGNATURE各×2、FINISHER各×1、COUNTER各×2。
- レイナ: 基本NORMAL＝サイドヘッドロック×3、足四の字×3。ドラゴンスクリューを含むその他NORMALは原則×2。
  SIGNATURE各×2、FINISHER各×1、COUNTER各×2。
- ミサキ: 基本NORMAL＝逆水平チョップ×3、ボディスラム×3。その他NORMALは原則×2。
  SIGNATURE各×2、FINISHER各×1、COUNTER各×2。
- ジャック: NORMAL18枚は個別配分。ROUGHはチョーク×1、顔面かきむしり×1、黒蝶クラッシュ×2、
  黒蝶ドライバー×1＝計5枚を基準（ジャックのSIGNATURE／FINISHER／COUNTERの内訳は一次資料に記載がなく、
  本書でも未確定のまま残す。推測補完はしない）。

Phase 1ではこの正式デッキ内容は使用せず、テスト用フィクスチャで代替する（Phase 10で正式データ化）。

---

## 22. アカリ・レイナの技データ（未確定）

アカリ・レイナの全12技（NORMAL8・SIGNATURE2・FINISHER2相当）の詳細数値（COST／DMG／HEAT／状態／特性）は、
**一次資料（docx）に記載がなく、本セッションでも未確定のまま**とする。17章の方向性、21章のデッキ配分の
一部（基本NORMAL名）のみが判明している。

**推測で技データを補完しない。** 後続Phase（Phase 10想定）でユーザーから仕様が追加された時点で本書へ反映する。

---

## 23. 技系統（TechniqueFamily）— Phase 4で正式確定

COUNTERの成立判定で、攻撃TECHNIQUEの技系統（family）とCOUNTERが返せる技系統／技系統グループを比較する
（23.4章）。Phase 1の`familyId`（自由文字列、nullable）という暫定構造は、Phase
4で正式な型付き`CombatV1TechniqueFamily`（必須・非nullable）へ移行した。旧String
ID互換レイヤーは設けていない。

### 23.1 attribute／family／groupは別概念

- **attribute**（`CombatV1EnergyAttribute`）: ENERGY支払い・技属性（5章）。
- **family**（`CombatV1TechniqueFamily`）: COUNTERで「何系の技か」を判定する具体分類（本章）。
- **group**（`CombatV1TechniqueFamilyGroup`）: familyをまとめるCOUNTER用上位分類（23.2章）。

Technique自身はgroupを保持しない。groupは常にfamilyから導出する。

### 23.2 Family Group

`CombatV1TechniqueFamilyGroup`は閉じた型（enum）。5種:

**STRIKE／AERIAL／THROW／SUBMISSION／FOUL**

**重要**: `FOUL` group（COUNTER分類上のgroup）と`CombatV1EnergyAttribute.rough`（ENERGY属性のラフ）は
**別概念**であり、同一視しない。

### 23.3 Technique Family（正式taxonomy）

`CombatV1TechniqueFamily`は閉じた型（enum）。以下30 family（groupごとの内訳）:

| group | family |
|---|---|
| STRIKE | ELBOW／CHOP／KICK／KNEE／LARIAT／TACKLE／STOMP／GUILLOTINE_DROP |
| AERIAL | DROP_KICK／BODY_PRESS／SPLASH |
| THROW | ARM_DRAG／DDT／LEG_TAKEDOWN／SLAM／BACKDROP／SUPLEX／POWERBOMB／DRIVER |
| SUBMISSION | ARMBAR／HEADLOCK／LEG_LOCK／FIGURE_FOUR／CROSSFACE／STRETCH／CHOKE／CLAW／NECK_LOCK |
| FOUL | LOW_BLOW／WEAPON |

補足:
- `BACKDROP`と`SUPLEX`は別family（同じTHROW groupだが異なるfamily）。
- `FIGURE_FOUR`は`LEG_LOCK`へ統合しない（別family）。
- `STOMP`はSTRIKE group（踏みつけは通常技として扱う、20章の踏みつけ方針と整合）。
- `FOUL_FINISH`はfamilyとして定義しない。

`CHOKE`はattribute横断（23.4章参照）。

### 23.4 CHOKEはattribute横断

familyはattributeへ従属させない。同じ`CHOKE` familyでも、attribute（joint／rough等）は技ごとに異なりうる
（例: attribute=joint・family=CHOKEの絞め技と、attribute=rough・family=CHOKEの反則的な首絞めが両立する）。

### 23.5 COUNTER matching

成立条件: `familyMatch || groupMatch`。

```
familyMatch = counter.counterableFamilies contains attack.family
groupMatch  = counter.counterableGroups contains attack.family.group
```

attribute（ENERGY属性）の一致だけではCOUNTER成立にしない。例: `attack.attribute == strike` かつ
`counter.attribute == strike` でも、family/groupが非対応ならCOUNTER不可。

### 23.6 Catalog validation（Technique／Counter Definitionの整合性検証）

デッキ構成（30枚・category等、4章）の検証（Deck validation）とは別に、Technique／Counter
**Definitionそのもの**の整合性を検証するCatalog validationを設ける（責務を分離する）。

`CombatV1Counter`は最低限、id／name／attribute／counterableFamilies／counterableGroupsを持つ。以下は
Catalog validationエラーとする:

**Technique側**:
- ENERGY COSTが不正（負数、またはwildを要求している）
- ENERGY COSTの合計（`total`）が0以下（zero-cost技禁止、7.2章）
- attributeがwild
- damage／heatGainが負数
- `directPin`と`submissionHold`が同時にtrue（`category != finisher`の技のみ対象、Phase
  6で確定。10.1章参照。`category == finisher`の技はこの2フィールドを参照しないため対象外）

**Counter側**:
- counterableFamiliesとcounterableGroupsの両方空
- family重複／group重複
- `Counter.attribute == wild`
- groupと、そのgroupに完全包含されるfamilyの冗長同時指定（例: `counterableGroups: [STRIKE]`かつ
  `counterableFamilies: [KICK]`はKICKがSTRIKEに含まれるため冗長）

**Catalog横断**:
- Technique／Counter間でのcardId衝突
- カタログMapのキーと定義の`id`の不一致

---

## 24. CPU検証ロジックの原則（将来Phase向け、参考情報）

Phase 11（CPU実装）以降で参照する原則。Phase 1では適用しない。

- 確定勝利（3カウント／GIVE UP）を最優先。
- PIN／SUBMISSION／追撃を、相手HP・KOC・PIN資源・追撃可能性から比較する。
- COUNTERは使用可能なら必ず使うのではなく、重要技へのENERGY温存も評価する。
- FINISHERはHEATが低い序盤では交換候補、HEAT100以降は使用可能性に応じて温存、HEAT200以上では
  高優先度保持とする。
- 1カウントの追加ドローは手札状況・FINISHER探索・COUNTER確保などの価値を評価して選択する。
- ROUGHは相手を弱らせる局面では妨害に使い、決着圏ではPIN不可のデメリットも考慮する。

---

## 25. 検証で記録する指標（将来Phase向け、参考情報）

Phase 12〜13（Simulator／バランス検証）以降で使用する想定の指標。Phase 1では扱わない。

- 勝率（先攻／後攻別）・決着方法・平均／中央値ターン
- PIN回数、1／2／2.9カウント回数、PINカード移動
- SUBMISSION／ESCAPE／GIVE UP回数
- HEAT200到達ターン、FINISHER使用・成功・決着率
- REST回数、山札再構築回数
- 各TECHNIQUEのドロー／使用／成功／被COUNTER／与DMG／勝利貢献
- COUNTERの使用可能回数・実使用回数・COST別成功率
- ミサキのCOST3/4技が実際に返されにくいか
- ジャックのROUGH締め回数と相手TECHNIQUE制限回数

---

## 26. 開発ロードマップ（Phase 0〜16）

依存関係を考慮した推奨実装順。各Phaseの詳細な技術設計は該当Phase着手時に
`docs/design/`配下へドキュメントを追加する。

| Phase | 内容 | 概要 |
|---|---|---|
| Phase 0 | 設計・SSOT確定 | 本書および`combat_v1_phase1_design.md`の確定（今回） |
| Phase 1 | Core Skeleton | Match生成〜ENERGY消費〜DMG適用〜HEAT加算〜手札循環の最小ループ。UI非依存でテスト可能な状態にする |
| Phase 2 | Deck / Hand | 30枚デッキの正式構成検証、手札循環の仕上げ |
| Phase 3 | ENERGY / TECHNIQUE | ENERGY・TECHNIQUE処理の本実装（Phase 1で土台は構築済み） |
| Phase 4 | COUNTER | 動的コスト（攻撃技コスト＝返し必要コスト）、技系統マッチング、＊ワイルドのCOUNTER時ポリシー確定 |
| Phase 5 | PIN / KOC | 1／2／2.9カウント階層、PINカード移動（最低1枚保証込み）、KOC消費処理 |
| Phase 6 | SUBMISSION | 通常SUBMISSION・SUBMISSION FINISHERの実装 |
| Phase 7 | DOWN / REST | 起き上がり／REST選択の実装 |
| Phase 8 | ROUGH | PIN不可・次ターンTECHNIQUE最大1枚制限の実装 |
| Phase 9 | FINISHER | `CombatV1FinisherType`に基づく3種の決着フローの実装 |
| **— Legacy Engine Removal Gate —** | | 27章の条件を満たした時点で旧3エンジンを削除（27章） |
| Phase 10 | 4 Wrestlers / Deck Data | アカリ・レイナの技データ確定、4レスラー全員の正式30枚デッキ実装 |
| Phase 11 | CPU | Combat Ver.1専用CPU実装 |
| Phase 12 | Simulator | Config／Simulator／Report／Diagnostics分離によるシミュレーション基盤（②の設計を参考） |
| Phase 13 | Balance Validation | 6組み合わせ×大量対戦によるバランス検証 |
| Phase 14 | UI | Combat Ver.1専用UI実装 |
| Phase 15 | Presentation / Animation / Audio | 演出・アニメーション・音声 |
| Phase 16 | Final Validation | 最終検証 |

---

## 27. Legacy Engine Removal Gate

**非常に重要**: 既存3エンジン（①Prototype／②Level Match／③Technique Match）は永久には残さない。
Combat Ver.1完成後、正式戦闘Engineを1つに統一する。

### 27.1 Gate通過条件

以下をすべて満たした時点で、旧エンジン削除Phaseへ進む。

1. Combat Ver.1の基本戦闘ルールが実装済みである。
2. COUNTER／PIN／KOC／SUBMISSION／REST／ROUGH／FINISHERが動作する。
3. 各ルールのテストが成功する。
4. UI非依存で、試合開始から決着まで1試合を最後まで実行できる。
5. 旧Engineから再利用したい資産の洗い出しが完了している。
6. 削除前の状態をGitで保存している。

### 27.2 削除対象（Gate通過後）

- ① Prototype、② Level Match、③ Technique Match
- 対象候補: 旧Engine本体、旧Engine専用UI、旧Engine専用CPU、旧Engine専用Simulator、旧Engine専用テスト、
  旧Engine専用保存処理、不要な旧データモデル、タイトル画面の旧モード導線

### 27.3 削除前に必ず評価する資産

Playtest Analytics、Simulatorの設計、Report、Diagnosticsなど、Ver.1へ再利用価値のある資産は
**削除前に必ず評価する**。必要なものをVer.1側へ移植してから削除する。**旧Engine互換レイヤーは作らない。**

---

## 28. 未決定事項

詳細は [`docs/design/combat_v1_open_questions.md`](design/combat_v1_open_questions.md) を参照。

---

## 29. 変更履歴

- **Phase 0（Combat Ver.1 Engine設計セッション）**: 本書を新規作成。一次資料（docx「ONE_NIGHT_MATCH_
  戦闘ルール_Ver.1_検証版」）の内容を全面的に統合したうえで、以下を追加確定した。
  - Combat Ver.1を独立エンジン（④）として構築する方針（1章）
  - HP初期値150を全レスラー共通固定とする（2章、14章）
  - KOC・PINカードをPhase 1の基本リソースとして扱う（9章、8章）
  - PINカード最低1枚保証ルールの正式採用（8.1章）
  - ＊（ワイルドENERGY）の解決手順（具体属性優先→不足分合算→＊で補完）の確定（5.1章）
  - Combo Speedを不採用とし、ENERGYで攻撃継続回数を制御する方針の確定（4章）
  - `CombatV1FinisherType`を独立enumとして定義し、技のSUBMISSIONフラグとは別概念とする方針（13章）
  - 開発ロードマップ（Phase 0〜16）とLegacy Engine Removal Gateの正式条件（26・27章）

- **Phase 4（COUNTER）**: 以下を新規確定した。
  - 技系統（TechniqueFamily、30 family）・技系統グループ（TechniqueFamilyGroup、5
    group）の正式taxonomyを確定し、Phase 1の`familyId: String?`から型付きenumへ移行（23章）
  - COUNTER matching（family/groupのいずれか一致で成立、attribute一致だけでは不成立）の確定（23.5章）
  - COUNTER動的ENERGY COST（返される攻撃Costの総量を、COUNTER側は単一属性で支払う）の確定（7章）
  - COUNTER時の＊(wild)ENERGY使用ポリシー（`counterAllowsWildSubstitution`、既定`false`）の確定（5.2章）
  - `CombatV1EnergyCost.total`の追加とTechnique Cost `total > 0`（zero-cost技禁止）の正式ルール化（7.2章）
  - `CombatV1PendingAttack`（public immutable Domain
    model）・`counterResponsePending`フェーズを追加したState Machineの確定（7.1章）
  - `declareTechnique`（Phase
    3までの`playTechnique`を改称、宣言のみを行い即時解決しない）・`playCounter`・`declineCounter`
    Command APIの確定（7.1章）

- **Phase 5（PIN/KOC）**: 以下を新規確定した。
  - PINカード移動の主体・向き: 攻撃側が自分の保有PINカードを1枚使用してPINを開始し、
    1カウント／2カウントでkick outされた場合、その1枚を攻撃側→防御側へ移動する。2.9カウントでは
    移動しない（8.1章）。
  - PINカウントの決定方式: 段階応答（`pinResponsePending`のような多段階の入力待ち）ではなく、
    PIN開始時点の防御側KOCから最終カウントを一括で決定する方式で確定した（8.2章）。
  - KICK OUTは自動: 防御側が必要KOCを保有していれば必ずkick outする。「保有していてもあえて
    支払わない」という選択肢は導入しない（8.2章）。
  - KOC/カウント対応表（KOC>=3→1カウント／KOC==2→2カウント／KOC==1→2.9カウント／KOC==0→
    3カウントでPIN決着）とKOC支払いは防御側のみが行う方針の確定（8.2章）。
  - kick out後の展開: 1／2カウントは攻撃側のターンを終了し防御側へ主導権を移す
    （`endTurn`と同じ内部処理）。2.9カウントは攻撃側が`action`フェーズへ戻り攻撃を継続できる
    （8.3章）。
  - `winnerPlayerIndex: int?`／`isOver`を`CombatV1MatchState`へ正式追加し、PINによる3カウント
    決着で試合が終了する経路を確定した（技術設計は`combat_v1_phase1_design.md`参照）。
  - DIRECT PINはTECHNIQUE成功解決と同一Command内で遷移し、古い`lastSuccessfulTechnique`を
    後から参照して再発火させない設計方針を確定した（8章）。

- **Phase 6（SUBMISSION）**: 以下を新規確定した（一次資料・`combat_rules_v1.md`本文には記載が
  なかったため、Phase 6実装セッション内でユーザーへ確認したうえで正式仕様として採用した）。
  - 通常SUBMISSIONへの突入方法: 自動トリガーのみ。`submissionHold=true`のTECHNIQUEがCOUNTERされず
    成立し、解決後の相手HPが閾値（既定50）以下ならDIRECT PINと同じ仕組みで同一Command内で自動的に
    SUBMISSIONへ移行する。攻撃側が任意に宣言する独立API（`declarePin`に相当するもの）は追加しない
    （10.1章）。
  - ESCAPE/GIVE UP判定方式: 完全自動。防御側KOC>=1（既定コスト1）なら自動的にKOCを支払いESCAPE
    成功、KOC==0なら自動的にGIVE UPで試合終了する。PINのKICK OUT自動判定と同じ思想で、防御側の任意
    選択は存在しないため、`CombatV1PendingSubmission`のような入力待ちDomain
    modelおよび専用`CombatV1MatchPhase`は追加していない（10.1章）。
  - ESCAPE成功後の展開: 攻撃側のターンを終了し、ESCAPEした側（防御側）の新しいターンへ進める
    （PIN 1／2カウントと同じ扱い、10.1章）。
  - `directPin`と`submissionHold`の排他: 同一TECHNIQUEに両方trueを設定することをCatalog
    validationで禁止する（`category==finisher`の技は対象外、10.1章・23.6章）。

- **Phase 7（REST / 起き上がり）**: 以下を新規確定した（一次資料・`combat_rules_v1.md`本文には
  「起き上がりまたはRESTを選択できる」という選択の存在自体は明記されていたが、Command構造・
  posture遷移・ターン終了処理などの実装上の詳細は明記されていなかったため、Phase 7実装セッション内
  でユーザーへ確認したうえで正式仕様として採用した）。
  - 起き上がり（RESTしない場合の復帰）は明示的なCommand（`standUp`）として実装する。posture:
    down→standへ遷移するのみで、他のフィールドは一切変化せず、ターンを消費しない（11章）。
  - RESTは`rest`として実装する。posture: down→standへ遷移し、HPを`restHpRecovery`（既定10）
    回復する（`maxHp`を超えない）。RESTはそのターンの行動を確定し、`endTurn`と同じ内部処理で
    ターンを終了する（11章）。
  - 起き上がり／RESTはいずれもDOWN状態限定（`phase == action`かつ自分がDOWN状態の場合のみ選択
    可能、STAND状態では選択不可）で確定した（11章）。
  - 自分（active player）がDOWN状態のままでは、TECHNIQUE宣言・通常PIN宣言・`endTurn`のいずれも
    実行できない（`selfDown`）方針で確定した。COUNTERは自分のDOWN状態による制限を一切受けない
    （11章）。

- **Phase 8（ROUGH）**: 一次資料・`combat_rules_v1.md`本文（15章）には「1枚でも使用したターンは
  PINできない」「相手は次の自ターンにTECHNIQUE最大1枚」という2つのルールの存在自体は明記されて
  いたが、「使用」と「成功」のどちらの基準で判定するか、COUNTERされたROUGH技の扱い、DIRECT
  PINとの関係、次ターン制限の失効条件は明記されていなかったため、Phase
  8実装セッション内でユーザーへ確認したうえで以下を正式仕様として採用した（15.1〜15.3章）。
  - 「1枚でも使用したターンはPINできない」の“使用”は宣言時点の基準（使用ベース）。COUNTERされた
    ROUGH技も対象になる（15.1章）。
  - このPIN不可ルールは通常PIN（`declarePin`/`checkPinLegality`）のみが対象。DIRECT
    PINは技成功と同一Command内で自動遷移するため対象外——両立を許容し、禁止するCatalog
    validationも追加しない（15.2章）。
  - 「次の自ターンにTECHNIQUE最大1枚」の“1枚”も宣言時点の基準（使用ベース）。COUNTERされた技も
    1枚に含む（15.3章）。
  - 次ターン制限は、そのターンの終了とともに（消費の有無に関わらず）消滅する。持ち越しはしない
    （15.3章）。

- **Phase 9（FINISHER）**: `CombatV1FinisherType`に基づく3種の決着フロー（13章）を正式実装した。
  一次資料・`combat_rules_v1.md`本文には「共有HEAT200以上でFINISHER解禁」「FINISHERだから自動的に
  PINになる、という処理にはしない」「finisherType 3種の意味」までは明記されていたが、以下は
  明記されていなかったため、Phase 9実装セッション内でユーザーへ確認したうえで正式仕様として
  採用した。
  - FINISHERはCOUNTER可能（13.4章）。既存のCOUNTER State Machine（7章）をカテゴリを問わず
    一律に適用し、FINISHERを対象外にする特別な仕組みは導入しない。
  - それ以外の項目（FINISHER解禁条件・finisherTypeと`directPin`/`submissionHold`フィールドとの
    優先順位・SUBMISSION FINISHERのHP0特例・COUNTER以外の決着タイミング等）は、いずれも
    Phase 0〜8で既に確定していたSSOT本文・優先順位ルール（2.4章、`combat_v1_open_questions.md`
    G番）から導出可能だったため、新たな確認は不要と判断した（13.1〜13.3章参照）。
  - `CombatV1RulesConfig.finisherHeatThreshold`（既定200）を新規追加した。
